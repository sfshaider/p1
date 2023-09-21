#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 5;
use Test::Exception;
use Test::MockModule;

require_ok('PlugNPay::Processor::ProcessorMessageServiceClient::ProcessTransactionRequest');

my $expectedJSON = '{"orderId":"1345","timeout":30,"processor":"testprocessor","merchant":"username","data":"hi"}';
my $req = new PlugNPay::Processor::ProcessorMessageServiceClient::ProcessTransactionRequest();

lives_ok( sub {
  # json
  my $processor = 'testprocessor';
  my $merchant = 'username';
  my $orderId = '1345';

  $req->setProcessor($processor);
  $req->setMerchant($merchant);
  $req->setOrderId($orderId);
  $req->setData("hi");
  my $status = $req->toJSON();
  if (!ok($status,'test json parses successfully')) {
    print $status->getError() . "\n";
  }

  is($status->get('json'),$expectedJSON, 'json created matches expected json');

  # url
  my $url = $req->getURL();
  is($url,"v1/transaction/",'url created successfully');
}, "lives while getting json" );

