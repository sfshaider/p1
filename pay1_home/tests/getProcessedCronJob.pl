#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::Processor::RetrieveProcessedTransactions;
use PlugNPay::Processor;
my $cronner = new PlugNPay::Processor::RetrieveProcessedTransactions();
my $procList = PlugNPay::Processor::processorList();
my @procArr = map { $_->{'shortName'} } @{$procList};
my $json = $cronner->run(\@procArr);

print $json . "\n";
exit;
