package Feedr;

use strict;
use warnings;

require Carp;
use AnyEvent::HTTP;
use Time::Duration::Parse ();
use URI;
use XML::Feed;
use XML::LibXML;
use YAML::Tiny;

use constant DEBUG => $ENV{DEBUG};

sub new {
    my $class = shift;

    my $self = {};
    bless $self, $class;

    $self->{config} ||= {};

    return $self;
}

sub parse_cmd_args {
    my $self = shift;
    my (@args) = @_;

    my $config = shift @args or Carp::croak("Config is required");

    DEBUG && warn "Loading config '$config'\n";

    $self->{config} = YAML::Tiny->read($config)
      or die "Can't load config: $YAML::Tiny::errstr: $!\n";

    return $self;
}

sub run {
    my $self = shift;

    my $feed = $self->_fetch_feeds;

    $feed = $self->_pick_not_older_than($feed);

    $feed = $self->_grep_by_keywords($feed);

    if ($feed->items) {
        $feed = $self->_resolve_urls($feed);

        $feed = $self->_merge_with_old_feed($feed);

        $feed = $self->_pick_not_older_than($feed);

        $feed = $self->_sort_items($feed);

        $self->_save_feed($feed);
    }
    else {
        DEBUG && warn "No results\n";
    }

    return $self;
}

sub _fetch_feeds {
    my $self = shift;

    DEBUG && warn "Downloading feeds...\n";

    my $global_feed = XML::Feed->new('RSS');

    my $feeds = $self->{config}->[0]->{feeds};

    my $cv = AnyEvent->condvar;

    foreach my $feed (@$feeds) {
        $cv->begin;

        http_get $feed,
          timeout => 15,
          sub {
            my ($data, $headers) = @_;

            if ($headers->{Status} =~ m/^2/) {
                eval {
                    my $feed = XML::Feed->parse(\$data);
                    $global_feed->splice($feed);
                    1;
                }
                or do {
                    DEBUG && warn "Error parsing $feed\n";
                };
            }
            else {
                DEBUG && warn "Error [$headers->{Status}] downloading $feed\n"

                  # TODO
            }

            $cv->end;
          };
    }

    $cv->recv;

    $self->_fix_dates($global_feed);

    return $global_feed;
}

sub _pick_not_older_than {
    my $self = shift;
    my ($feed) = @_;

    my $age = $self->{config}->[0]->{limits}->{age} || 0;
    my $age_in_seconds = Time::Duration::Parse::parse_duration($age);

    DEBUG && warn "Removing older then '$age' ($age_in_seconds) items...\n";

    my @items = $feed->items;
    @items = grep { $_->issued->epoch > time - $age_in_seconds } @items;

    $feed = XML::Feed->new('RSS');
    foreach my $item (@items) {
        $feed->add_entry($item);
    }

    return $feed;
}

sub _grep_by_keywords {
    my $self = shift;
    my ($feed) = @_;

    my $keywords = $self->{config}->[0]->{limits}->{keywords};
    return $feed unless defined $keywords;

    $keywords = [$keywords] unless ref $keywords eq 'ARRAY';
    return $feed unless @$keywords;

    DEBUG && warn "Greping by " . join(', ', @$keywords) . "...\n";

    my @items;

    foreach my $item ($feed->items) {
        foreach my $keyword (@$keywords) {
            if ($item->category) {
                if (grep { $_ =~ m/$keyword/i } $item->category) {
                    push @items, $item;
                }
            }
            else {
                DEBUG
                  && warn
                  "No categories available, searching through content";

                if ($item->content =~ m/\s*$keyword\s*/) {
                    push @items, $item;
                }
            }
        }
    }

    $feed = XML::Feed->new('RSS');
    foreach my $item (@items) {
        $feed->add_entry($item);
    }

    return $feed;
}

sub _merge_with_old_feed {
    my $self = shift;
    my ($feed) = @_;

    my $old_feed_file = $self->{config}->[0]->{output};
    return $feed unless -e $old_feed_file;

    DEBUG && warn "Merging...\n";

    my $old_feed = XML::Feed->parse($old_feed_file);
    foreach my $entry ($old_feed->entries) {
        $feed->add_entry($entry);
    }

    return $feed;
}

sub _resolve_urls {
    my $self = shift;
    my ($feed) = @_;

    DEBUG && warn "Resolving URLs...\n";

    my $cv = AnyEvent->condvar;
    foreach my $item ($feed->items) {
        $cv->begin;

        http_get $item->link,
          timeout => 15,
          sub {
            my ($data, $headers) = @_;

            my $url = $headers->{URL};
            $url = URI->new($url);
            $url->query(undef);
            $url->fragment(undef);
            $url = $url->as_string;
            $url =~ s{\s*\[.*?\]$}{};

            $item->link($url);

            $cv->end;
          };
    }

    $cv->recv;

    return $feed;
}

sub _sort_items {
    my $self = shift;
    my ($feed) = @_;

    DEBUG && warn "Sorting...\n";

    my @items = $feed->items;

    @items = sort { $b->issued->epoch <=> $a->issued->epoch } @items;

    $feed = XML::Feed->new('RSS');

    my %seen = ();

    foreach my $item (@items) {
        next if $seen{$item->link};

        $feed->add_entry($item);

        $seen{$item->link}++;
    }

    return $feed;
}

sub _fix_dates {
    my $self = shift;
    my ($feed) = @_;

    DEBUG && warn "Fixing dates...\n";

    my @items = $feed->items;
    foreach my $item (@items) {
        next if $item->issued && $item->unwrap->{pubDate};

        my $pubDate = $item->issued || $item->unwrap->{pubDate};

        if (!$pubDate) {
            DEBUG && warn "No pubDate available, searching through link";

            if ($item->unwrap->{link} =~ m{/(\d\d\d\d)/(\d\d)/(?:(\d\d)/)?}i)
            {
                my $issued = DateTime->new(
                    year  => $1,
                    month => $2,
                    day   => $3 || 1
                );
                $item->issued($issued);
            }
            else {
                DEBUG && warn "Can't parse date\n";
                $item->issued(DateTime->now);
            }
        }
        elsif (
            $pubDate =~ m/^(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z?$/i)
        {
            DEBUG && warn "Unexpected date format, but still parseable";

            my $issued = DateTime->new(
                year   => $1,
                month  => $2,
                day    => $3,
                hour   => $4,
                minute => $5,
                second => $6
            );
            $item->issued($issued);
        }
        else {
            DEBUG && warn "Can't parse date\n";
            $item->issued(DateTime->now);
        }
    }

    return $feed;
}

sub _save_feed {
    my $self = shift;
    my ($feed) = @_;

    DEBUG && warn "Saving...\n";

    $feed->title($self->{config}->[0]->{title});
    $feed->description($self->{config}->[0]->{description});
    $feed->link($self->{config}->[0]->{link});
    $feed->modified(($feed->items)[0]->issued);

    my $xml = $feed->as_xml;

    my $dom = XML::LibXML->new(
        no_blanks        => 1,
        clean_namespaces => 1,
        no_network       => 1
    )->parse_string($xml);

    open my $file, '>', $self->{config}->[0]->{output};
    print $file $dom->toString(2);

    return $self;
}

1;
