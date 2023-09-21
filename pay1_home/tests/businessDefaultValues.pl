#!/usr/bin/perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use Data::Dumper;
use PlugNPay::CreditCard;
use PlugNPay::Transaction::DefaultValues;

my $t = new PlugNPay::Transaction('sale', 'credit');
$t->setTransactionAmount(100.30);

my $cc = new PlugNPay::CreditCard($ARGV[0]);
$t->setCreditCard($cc);
my $dv = new PlugNPay::Transaction::DefaultValues();
print Dumper $dv->setDefaultValues('vffdemo', $t);
exit;
