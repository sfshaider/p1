#!/bin/env perl

use PlugNPay::Processor::ProcessorMessageServiceClient;

my $random = int(rand() * 10000000);
print "$random\n";

my $pms = new PlugNPay::Processor::ProcessorMessageServiceClient;

my $request = $pms->newProcessTransactionRequest();

$request->setProcessor('testprocessor');
$request->setMerchant('chrisinc');
$request->setOrderId($random);
$request->setData('transaction data');
$request->setTimeout(5);
print "url is " . $request->getURL() . "\n";
my $status = $pms->sendRequest($request);

use Data::Dumper;
print Dumper($status);
