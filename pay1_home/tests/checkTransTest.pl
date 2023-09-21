#!/bin/env perl
use strict;

use lib '/home/pay1/perl_lib';
use PlugNPay::Processor;
use miscutils;
my @arr = ('orderID','2016022617335910567','publisher-name','scotttest','accttype','credit','operation','reauth','mode','reauth','processor','testprocessor','card-amount','1.00');
my %res = &miscutils::_legacyCheckTrans(@arr);

use Data::Dumper;
my $proc = new PlugNPay::Processor({'shortName' => 'testprocessor'});
print $proc->getReauthAllowed() . "\n\n";
print Dumper \%res;
