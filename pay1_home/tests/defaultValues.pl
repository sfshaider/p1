#!/usr/bin/perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use Data::Dumper;
use PlugNPay::Transaction::DefaultValues;

my $t = new PlugNPay::Transaction('sale', 'credit');
my $dv = new PlugNPay::Transaction::DefaultValues();
print Dumper $dv->setDefaultValues('pnpdemo', $t);
exit;
