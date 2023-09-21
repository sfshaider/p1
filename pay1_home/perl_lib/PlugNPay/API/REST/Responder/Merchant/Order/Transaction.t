#!/bin/env perl;
use strict;
use warnings;
use Test::More tests => 3;
use PlugNPay::API::MockRequest;
use PlugNPay::API::REST;
use PlugNPay::Testing;
use JSON::XS;

require_ok('PlugNPay::API::REST::Responder::Merchant::Order::Transaction');

TODO: {
  local $TODO = "These worked when they were needed, but no longer work.  They need to be updated to be reproducible.";
  ok(&testMerchantNameLoadForDateRange('dylaninc'), 'GET returns transactions for date range');
  ok(!&testMerchantNameLoadForDateRange('dylaninc2'), 'GET returns no transaction for date range (No longer loads other account\'s data)');
}

sub testMerchantNameLoadForDateRange {
  my $username = shift;
  my $resp = &testGET($username);
  my $trans = $resp->{'content'}{'data'}{'transactions'};
  my @keys = keys %{$trans};
  return @keys > 0;
}

sub testGET {
  my $username = shift;
  my $url = '/api/merchant/:' . $username . '/order/transaction/!/start_date/:20220101/end_date/:20220113';
  my $mr = new PlugNPay::API::MockRequest();
  $mr->setResource($url);
  $mr->setMethod('GET');
  $mr->addHeaders({
    'Accept' => 'application/json'
  });
  my $rest = new PlugNPay::API::REST('/api', { mockRequest => $mr });
  $rest->setRequestGatewayAccount($username);
  my $response = $rest->respond({ skipHeaders => 1 });
  my $responseData = decode_json($response);
  return $responseData;
}


