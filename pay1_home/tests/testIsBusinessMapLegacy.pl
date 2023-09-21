#!/bin/env perl
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Transaction;
use PlugNPay::Transaction::MapLegacy;
use PlugNPay::CreditCard;
use Data::Dumper;

my $transaction = new PlugNPay::Transaction('sale', 'credit');
my $card = new PlugNPay::CreditCard('411111111111111');
$card->setCommCardType('business');

$transaction->setCreditCard($card);

my $mapLegacy = new PlugNPay::Transaction::MapLegacy();
my $data = $mapLegacy->map($transaction);

print Dumper($data);
