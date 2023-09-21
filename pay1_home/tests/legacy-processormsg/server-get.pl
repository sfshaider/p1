#!/bin/env perl

use PlugNPay::Processor::ProcessorMessageServiceClient;

my $pms = new PlugNPay::Processor::ProcessorMessageServiceClient;

my $request = $pms->newGetTransactionsRequest();

$request->setProcessor('testprocessor');
$request->setCount(5);
print "url is " . $request->getURL() . "\n";
my $response = $pms->sendRequest($request);

use Data::Dumper;
print Dumper($response);
