#!/usr/bin/env perl

use FindBin '$RealBin';

use lib 't/lib';

BEGIN {
    unshift @INC, "$RealBin/lib";
    unshift @INC, "$_/lib" for glob "$RealBin/../contrib/*";
}

use Test::Class::Load qw(t/tests);

BEGIN { $ENV{TEST_SUITE} = 1 }

Test::Class->runtests;
