#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 6;
use Test::Exception;

require_ok('PlugNPay::Transaction::Logging::Adjustment');

my $testObject = new PlugNPay::Transaction::Logging::Adjustment();

# getBaseAmount()
$testObject->setBaseAmount('10.00');
is($testObject->getBaseAmount(),'10.00','getBaseAmount returns the amount set by setBaseAmount');



# setAdjustmentAmount(), getAdjustmentAmount(), setAdjustmentTotalAmount(), and getAdjustmentTotalAmount()
$testObject->setAdjustmentAmount('5.33');
is($testObject->getAdjustmentAmount(),'5.33','getAdjustmentAmount returns the amount set by setAdjustmentAmount');
is($testObject->getAdjustmentTotalAmount(),'5.33','getAdjustmentTotalAmount returns the amount set by setAdjustmentAmount');
$testObject->setAdjustmentTotalAmount('4.50');
is($testObject->getAdjustmentAmount(),'4.50','getAdjustmentAmount returns the amount set by setAdjustmentTotalAmount');
is($testObject->getAdjustmentTotalAmount(),'4.50','getAdjustmentTotalAmount returns the amount set by setAdjustmentTotalAmount');
