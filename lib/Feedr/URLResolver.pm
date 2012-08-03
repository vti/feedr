package Feedr::URLResolver;

use strict;
use warnings;

use AnyEvent::HTTP;
use URI;

sub new {
    my $class = shift;

    my $self = {@_};
    bless $self, $class;

    return $self;
}

sub resolve {
    my $self = shift;
    my ($feed) = @_;

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

1;
