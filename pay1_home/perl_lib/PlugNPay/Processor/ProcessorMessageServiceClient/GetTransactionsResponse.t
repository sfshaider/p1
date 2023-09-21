#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 15;
use Test::Exception;
use Test::MockModule;

require_ok('PlugNPay::Processor::ProcessorMessageServiceClient::GetTransactionsResponse');

my $transactionsJSON = q/[
  {
    "username": "pnpdemo",
    "orderId": "1234",
    "data": "this is some transaction data",
    "transactionRequestId": "firstTransactionId"
  },
  {
    "username": "pnpdemo2",
    "orderId": "3456",
    "data": "this is transaction data for another transaction",
    "transactionRequestId": "secondTransactionId"
  }
]/;
my $responseJSON = qq/{ "transactions": $transactionsJSON, "error":false, "message": "Success!", "requestId": "12345" }/;
my $resp = new PlugNPay::Processor::ProcessorMessageServiceClient::GetTransactionsResponse();

lives_ok( sub {
  my $status = $resp->fromJSON($responseJSON);
  if (!ok($status,'test json parses successfully')) {
    print $status->getError() . "\n";
  }
  is($resp->getError(),'0', 'fromJSON parses and sets error correctly');
  is($resp->getMessage(),'Success!', 'fromJSON parses and sets message correctly');
  is($resp->getRequestId(),'12345', 'fromJSON parses and sets requestId correctly');

  # two transactions, so getNextTransaction should return true twice
  $status = $resp->getTransaction();
  ok($status,'status returns true for the first transaction');
  my $transaction = $status->get('transaction');
  is($transaction->{'username'},'pnpdemo','first transaction username is correct');
  is($transaction->{'orderId'},'1234','first transaction orderId is correct');
  is($transaction->{'data'},'this is some transaction data','first transaction data is correct');
  is($transaction->{'transactionRequestId'},'firstTransactionId','first transaction request id is correct');

  $status = $resp->getTransaction();
  ok($status,'status returns true for the second transaction');
  $transaction = $status->get('transaction');
  is($transaction->{'username'},'pnpdemo2','second transaction username is correct');
  is($transaction->{'orderId'},'3456','second transaction orderId is correct');
  is($transaction->{'data'},'this is transaction data for another transaction','second transaction data is correct');
  is($transaction->{'transactionRequestId'},'secondTransactionId','second transaction request id is correct');


  $status = $resp->getTransaction();
  ok(!$status,'status returns false as there are no more transactions');

}, "lives while setting json" );

