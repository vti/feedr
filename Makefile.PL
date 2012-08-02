#!/usr/bin/env perl

use 5.008007;

use strict;
use warnings;

use ExtUtils::MakeMaker;

my ($mm) = $ExtUtils::MakeMaker::VERSION =~ /^([^_]+)/;

WriteMakefile(
    NAME         => 'Feedr',
    VERSION_FROM => 'lib/Feedr.pm',
    ABSTRACT     => '',
    AUTHOR       => 'Viacheslav Tykhanovkskyi <vti@cpan.org>',

    ($mm < 6.3002 ? () : ('LICENSE' => 'artistic_2')),

    (   $mm < 6.46
        ? ()
        : ( META_MERGE => {
                requires  => {perl => '5.008007'},
                resources => {
                    license    => 'http://dev.perl.org/licenses/',
                    repository => 'http://github.com/vti/feedr'
                },
                no_index => {directory => [qw/t/]}
            },
            META_ADD => {
                build_requires     => {},
                configure_requires => {}
            },
        )
    ),

    PREREQ_PM => {
        'Math::Round'      => 0,
        'DateTime::Locale' => 0,

        'AnyEvent'              => 0,
        'AnyEvent::HTTP'        => 0,
        'Carp'                  => 0,
        'Time::Duration::Parse' => 0,
        'XML::Feed'             => 0,
        'YAML::Tiny'            => 0,
    },
    test => {TESTS => 't/*.t t/*/*.t'}
);
