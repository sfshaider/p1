#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 4;
use Test::Exception;
use Test::MockModule;

require_ok('PlugNPay::Processor::ProcessorMessageServiceClient::GetTransactionsRequest');

my $expectedJSON = '{"data":"hi"}';
my $req = new PlugNPay::Processor::ProcessorMessageServiceClient::GetTransactionsRequest();

lives_ok( sub {
  # url
  my $processor = 'testprocessor';

  $req->setProcessor($processor);

  my $url = $req->getURL();
  is($url,"v1/transaction/pending/",'url created successfully');

  my $count = 5;
  $req->setCount($count);
  my $jsonStatus = $req->toJSON();
  if ($jsonStatus) {
    my $json = $jsonStatus->{'json'};
    is($json,'{"count":5,"timeout":30,"processor":"testprocessor"}','toJson returns expected json');
  }
}, "lives while getting and url" );
