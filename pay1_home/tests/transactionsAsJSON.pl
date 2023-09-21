#!/bin/env perl

use strict;
use Data::Dumper;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::Loader::History;
use PlugNPay::Transaction::JSON;
use PlugNPay::Transaction;
use JSON::XS qw(encode_json);


my $t = new PlugNPay::Transaction('auth','credit');
my $cc = new PlugNPay::CreditCard;
$cc->setNumber('4111111111111111');
$cc->setSecurityCode('123');
$t->setCreditCard($cc);
$cc->setExpirationMonth('01');
$cc->setExpirationYear('23');
my $t2j = new PlugNPay::Transaction::JSON();
my $j = $t2j->transactionToJSON($t,{ fullPaymentInfo => 1});
print Dumper($j);
print encode_json($j) . "\n";
