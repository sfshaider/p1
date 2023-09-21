#!/bin/env perl
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Transaction::Loader;

my $loader = new PlugNPay::Transaction::Loader({'loadPaymentInfo' => 0});
my $trans = $loader->load({'gatewayAccount' => 'chrisinc', 'orderID' => '2022010402304302765'})->{'chrisinc'}{'2022010402304302765'};
my $accountCode = $trans->getAccountCode(1);
print STDERR 'account code 1: ' . $accountCode . "\n";
