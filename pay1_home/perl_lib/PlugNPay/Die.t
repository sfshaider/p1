#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('PlugNPay::Die');

throws_ok(sub {
  die("nothing to see here");
}, qr/^nothing to see here/, 'call to die only outputs message, not stacktrace');
