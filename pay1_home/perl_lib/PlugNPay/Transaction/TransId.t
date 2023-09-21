#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 11;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use Time::HiRes;

require_ok('PlugNPay::Transaction::TransId');


SKIP: {
  if (!defined $ENV{'TEST_INTEGRATION'} || $ENV{'TEST_INTEGRATION'} ne '1') {
    skip("Skipping microservice tests because TEST_INTEGRATION environment variable is not '1'", 5);
  }

  # generate 5 transaction ids
  for (my $i = 1; $i <= 5; $i++) {
    my $start = Time::HiRes::time();
    my $id = PlugNPay::Transaction::TransId::getTransIdV1({ username => 'pnpdemo'});
    my $end = Time::HiRes::time();
    my $duration = ($end - $start);
    ok($id > -1,'generated an id > -1');
    # .5 seconds is *very* generous, but in dev, things can run slow sometimes.
    # in production this *should* be way faster...way way faster
    ok($duration < .5,"id generated in < .5 seconds (actual: $duration)");
  }
}




