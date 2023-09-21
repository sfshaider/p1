#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::GatewayAccount;

my $merchant = $ARGV[0] || 'dylaninc';

my $ga = new PlugNPay::GatewayAccount($merchant);

print 'Is MID valid: ' . $ga->checkMid() . "\n";
exit;
