#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;
use Test::Exception;
use Test::MockModule;
use PlugNPay::GatewayAccount;

require_ok('remote_strict');

ok(remote::testRemoteStrict(),'remote_strict.pm loads remote.pm');