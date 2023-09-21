#!/bin/env perl

use lib $ENV{'PNP_PERL_LIB'};
use strict;
use warnings;
use PlugNPay::Processor::Queue;
use Data::Dumper;

my $url = "http://10.100.2.15:8888/client";
my $processor = "testprocessor1";
my $username = "pnpdemo";
my $orderID = 1;
my $data = "testdata";

my $processorQueue = new PlugNPay::Processor::Queue();
my $clientResponse = $processorQueue->sendForProcessing($url, $processor, $username, $orderID, $data);

print Dumper $clientResponse;

