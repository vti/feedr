package Feedr::Fetcher;

use strict;
use warnings;

use AnyEvent::HTTP;
use XML::Feed;

use constant DEBUG => $ENV{DEBUG};

sub new {
    my $class = shift;

    my $self = {@_};
    bless $self, $class;

    return $self;
}

sub fetch {
    my $self = shift;
    my ($urls, $cb) = @_;

    my $cv = AnyEvent->condvar;

    foreach my $url (@$urls) {
        $cv->begin;

        http_get $url,
          timeout => 15,
          sub {
            my ($data, $headers) = @_;

            if ($headers->{Status} =~ m/^2/) {
                $cb->($url, $data);
            }
            else {
                DEBUG && warn "Error [$headers->{Status}] downloading $url\n"

                  # TODO
            }

            $cv->end;
          };
    }

    $cv->recv;

    return $self;
}

1;
