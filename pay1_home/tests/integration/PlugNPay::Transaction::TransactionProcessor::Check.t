#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Sys::Time qw(yy mm);

require_ok('PlugNPay::Transaction::TransactionProcessor::Check');
require_ok('PlugNPay::Transaction');
require_ok('PlugNPay::Transaction::TransactionProcessor');
require_ok('PlugNPay::CreditCard');

testFailReturn();

sub testFailReturn {
  my $transactionObj = new PlugNPay::Transaction('auth','card');

  my $cc = new PlugNPay::CreditCard();
  $cc->setExpirationMonth(mm());
  $cc->setExpirationYear(yy() + 1);
  $cc->setNumber('4111111111111111');
  $transactionObj->setCreditCard($cc);
  $transactionObj->setGatewayAccount('chrisinc');
  $transactionObj->setTransactionAmount(1.00);
  $transactionObj->setToAsynchronous();

  my $transactionProcessor = new PlugNPay::Transaction::TransactionProcessor();
  my $result = $transactionProcessor->process($transactionObj);
  # print STDERR Dumper($transactionObj); use Data::Dumper;

  my $returnTransactionObj = new PlugNPay::Transaction('return','card');
  $returnTransactionObj->setOrderID($transactionObj->getOrderID());
  $returnTransactionObj->setPNPTransactionReferenceID($transactionObj->getPNPTransactionReferenceID());

  my $returnResult = $transactionProcessor->process($returnTransactionObj);
  is(1,0);
}
