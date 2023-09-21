#!/bin/perl

use strict;
use PlugNPay::Processor::Flag;

my $pf = new PlugNPay::Processor::Flag('testprocessor2');
print $pf->get('test') . "\n";
exit;
