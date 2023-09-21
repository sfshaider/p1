#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 5;
use Test::Exception;
use Test::MockModule;

require_ok('PlugNPay::Processor::ProcessorMessageServiceClient::PostTransactionResultRequest');

my $expectedJSON = '{"transactionRequestId":"12345","data":"hi"}';
my $req = new PlugNPay::Processor::ProcessorMessageServiceClient::PostTransactionResultRequest();

lives_ok( sub {
  # json
  $req->setData("hi");
  $req->setTransactionRequestId("12345");

  my $status = $req->toJSON();
  if (!ok($status,'test json parses successfully')) {
    print $status->getError() . "\n";
  }

  is($status->get('json'),$expectedJSON, 'json created matches expected json');

  # url
  my $url = $req->getURL();
  is($url,"v1/transaction/result",'url created successfully');
}, "lives while getting json and url" );
