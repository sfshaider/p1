#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;
use Test::Exception;

require_ok('PlugNPay::Util::Cache::LRUCache');
require_ok('PlugNPay::GatewayAccount'); # used to try to reproduce a bug

my $cache = new PlugNPay::Util::Cache::LRUCache(1); # 1 second is sufficient for testing


# test/fix bug where error occurs when the same object can not be added to the cache twice
# we really need a bug tracker...
my $ga1 = new PlugNPay::GatewayAccount();
$ga1->setGatewayAccountName('ga1');

$cache->set('ga1',$ga1);
lives_ok(sub {
  $cache->set('ga1',$ga1)
}, 'error is not thrown when a gateway account is added to cache when it already exists');
