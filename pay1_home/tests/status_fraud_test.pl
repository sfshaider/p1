#!/bin/env perl

use strict;
use PlugNPay::GatewayAccount;
use Test::More qw( no_plan );

my $ga = new PlugNPay::GatewayAccount('bryaninc');
$ga->setFraud('because he told me to');
$ga->save();

is($ga->getStatus(), 'fraud', 'set fraud status');
exit;
