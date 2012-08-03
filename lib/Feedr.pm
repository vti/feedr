package Feedr;

use strict;
use warnings;

require Carp;
use Time::Duration::Parse ();
use XML::Feed;
use XML::LibXML;
use YAML::Tiny;
use Feedr::Fetcher;
use Feedr::URLResolver;

use constant DEBUG => $ENV{DEBUG};

sub new {
    my $class = shift;

    my $self = {};
    bless $self, $class;

    $self->{config} ||= {};

    $self->{fetcher}      ||= Feedr::Fetcher->new;
    $self->{url_resolver} ||= Feedr::URLResolver->new;

    return $self;
}

sub parse_cmd_args {
    my $self = shift;
    my (@args) = @_;

    my $config = shift @args or Carp::croak("Config is required");

    DEBUG && warn "Loading config '$config'\n";

    $self->{config} = YAML::Tiny->read($config)->[0]
      or die "Can't load config: $YAML::Tiny::errstr: $!\n";

    return $self;
}

sub run {
    my $self = shift;

    my $feed = XML::Feed->new('RSS');

    $self->_fetch_feeds(
        sub {
            my ($url, $data) = @_;

            eval {
                my $local_feed = $self->_parse_feed($url, \$data);

                $feed->splice($local_feed);

                1;
            } or do {
                my $e = $@;

                DEBUG && warn "Can't parse feed from '$url': $e";
            };
        }
    );

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

    my $feeds =
      [map { ref $_ eq 'HASH' ? $_->{url} : $_ } @{$self->{config}->{feeds}}];

    $self->{fetcher}->fetch($feeds, @_);
}

sub _parse_feed {
    my $self = shift;
    my ($url, $data_ref) = @_;

    my $feed = XML::Feed->parse($data_ref);

    $self->_fix_dates($feed);

    $feed = $self->_pick_not_older_than($feed);

    if (my $global_keywords = $self->{config}->{limits}->{keywords}) {
        $feed = $self->_grep_by_keywords($feed, $global_keywords);
    }

    if (my $global_categories = $self->{config}->{limits}->{categories}) {
        $feed = $self->_grep_by_categories($feed, $global_categories);
    }

    my ($feed_config) =
      grep { ref $_ eq 'HASH' && $_->{url} eq $url }
      @{$self->{config}->{feeds}};

    if ($feed_config && (my $local_keywords = $feed_config->{keywords})) {
        $feed = $self->_grep_by_keywords($feed, $local_keywords);
    }

    if ($feed_config && (my $local_categories = $feed_config->{categories})) {
        $feed = $self->_grep_by_categories($feed, $local_categories);
    }

    return $feed;
}

sub _pick_not_older_than {
    my $self = shift;
    my ($feed) = @_;

    my $age = $self->{config}->{limits}->{age} || 0;
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
    my ($feed, $keywords) = @_;

    return $feed unless defined $keywords;

    $keywords = [$keywords] unless ref $keywords eq 'ARRAY';
    return $feed unless @$keywords;

    DEBUG && warn "Greping by " . join(', ', @$keywords) . "...\n";

    my @items;

    ITEM: foreach my $item ($feed->items) {
        foreach my $keyword (@$keywords) {
            my $not = $keyword =~ s/^!//;

            if ($item->content =~ m/\s*$keyword\s*/) {
                next ITEM if $not;

                push @items, $item;
            }
        }
    }

    $feed = XML::Feed->new('RSS');
    foreach my $item (@items) {
        $feed->add_entry($item);
    }

    return $feed;
}

sub _grep_by_categories {
    my $self = shift;
    my ($feed, $categories) = @_;

    return $feed unless defined $categories;

    $categories = [$categories] unless ref $categories eq 'ARRAY';
    return $feed unless @$categories;

    DEBUG && warn "Greping by " . join(', ', @$categories) . "...\n";

    my @items;

    ITEM: foreach my $item ($feed->items) {
        foreach my $category (@$categories) {
            my $not = $category =~ s/^!//;

            if ($item->category) {
                if (grep { $_ =~ m/$category/i } $item->category) {
                    next ITEM if $not;

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

    my $old_feed_file = $self->{config}->{output};
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

    return $self->{url_resolver}->resolve($feed);
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

    $feed->title($self->{config}->{title});
    $feed->description($self->{config}->{description});
    $feed->link($self->{config}->{link});
    $feed->modified(($feed->items)[0]->issued);

    my $xml = $feed->as_xml;

    my $dom = XML::LibXML->new(
        no_blanks        => 1,
        clean_namespaces => 1,
        no_network       => 1
    )->parse_string($xml);

    open my $file, '>', $self->{config}->{output};
    print $file $dom->toString(2);

    return $self;
}

1;
