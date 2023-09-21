#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 6;
use Test::Exception;
use Test::MockModule;

require_ok('PlugNPay::Processor::ProcessorMessageServiceClient::PostTransactionResultResponse');

my $responseJSON = '{ "data": "hi", "error":false, "message": "Success!", "requestId": "12345" }';
my $resp = new PlugNPay::Processor::ProcessorMessageServiceClient::PostTransactionResultResponse();

lives_ok( sub {
  my $status = $resp->fromJSON($responseJSON);
  if (!ok($status,'test json parses successfully')) {
    print $status->getError() . "\n";
  }

  is($resp->getError(),'0', 'fromJSON parses and sets error correctly');
  is($resp->getMessage(),'Success!', 'fromJSON parses and sets message correctly');
  is($resp->getRequestId(),'12345', 'fromJSON parses and sets requestId correctly');

}, "lives while setting json" );

