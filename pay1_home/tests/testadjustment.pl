#!/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Transaction::Adjustment;

my $adjustmentCalculator = new PlugNPay::Transaction::Adjustment('bryaninc');
$adjustmentCalculator->setTransactionAmount(1.00);
$adjustmentCalculator->setTransactionIdentifier('transA');
$adjustmentCalculator->setState('BG');
$adjustmentCalculator->setCountryCode(840);
my $result = $adjustmentCalculator->calculate();
print Dumper $result;
exit;
