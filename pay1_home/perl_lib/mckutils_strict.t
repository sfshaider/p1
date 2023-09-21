#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

use PlugNPay::Testing qw(skipIntegration);

require_ok('mckutils_strict');

#integration test for mckutils namespace
testMain();

sub testMain {
  SKIP: {
    if (!skipIntegration('integration testing disabled',2)) {
      my %query = ('card-exp' => '12/25', 'publisher-name' => 'testing');
      mckutils->new(%query);
      is($mckutils::query{'card-exp'}, '12/25', 'mckutils gets card-exp');
      is($mckutils::query{'publisher-name'}, 'testing', 'mckutils gets publisher-name');
    }
  }
}
