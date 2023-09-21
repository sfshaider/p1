#!/bin/env perl

use strict;
use warnings;
use Test::More tests => 14;
use Test::Exception;
use Test::MockModule;

use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::Transaction::Loader');
require_ok('PlugNPay::Transaction');
require_ok('PlugNPay::Transaction::TransactionProcessor');
require_ok('PlugNPay::CreditCard');
require_ok('PlugNPay::Contact');

SKIP: {
  if (!skipIntegration("Skipping database tests because TEST_INTEGRATION environment variable is not '1'", 9)) {
    my $testResources = setup('pnpdemo');
    testLoad($testResources);
  }
}

sub setup {
    my $merchant = shift;

    my $transaction = new PlugNPay::Transaction('auth', 'card');
    $transaction->setTransactionAmount('1.00');
    $transaction->setGatewayAccount($merchant);
    $transaction->setProcessor('testprocessor');
    $transaction->setAccountCode(1,'abcd');
    $transaction->setAccountCode(2,'efgh');
    $transaction->setAccountCode(3,'ijkl');
    $transaction->setAccountCode(4,'mnop');
    $transaction->setCurrency('USD');
    $transaction->setPostAuth();
    my $cc = new PlugNPay::CreditCard('4111111111111111'); 
    $cc->setExpirationMonth('12');
    $cc->setExpirationYear(99);
    $cc->setName('test');
    $transaction->setCreditCard($cc);
    $transaction->setBillingInformation(new PlugNPay::Contact());
    $transaction->setShippingInformation(new PlugNPay::Contact());
    $transaction->setIgnoreCVVResponse();
    $transaction->setIgnoreFraudCheckResponse();
    $transaction->setReceiptSendingEmailAddress('test@example.com');
    my $transProc = new PlugNPay::Transaction::TransactionProcessor();
    my $result = $transProc->process($transaction);

    return {
      inputTransaction => $transaction,
      result => $result
    };
}

sub testLoad {
  my $resources = shift;

  my $inputTransaction = $resources->{'inputTransaction'};
  my $result = $resources->{'result'};

  my $merchant = $inputTransaction->getGatewayAccountName();

  my $orderId = $inputTransaction->getMerchantTransactionID();
  my $loader = new PlugNPay::Transaction::Loader({'loadPaymentInfo' => 0});
  my $trans = $loader->load({'gatewayAccount' => $merchant, 'orderID' => $orderId})->{$merchant}{$orderId};

  my $account = $trans->getGatewayAccountName();
  is($account,$inputTransaction->getGatewayAccountName(),'loaded gateway account matches gateway account from input transaction');

  my $processor = $trans->getProcessorShortName();
  is($processor,$inputTransaction->getProcessorShortName(),'loaded processor matches processor from input transaction');

  my $amount = $trans->getTransactionAmount();
  is($amount,$inputTransaction->getTransactionAmount(),'loaded amount matches amount from input transaction');

  my $currencyCode = $trans->getCurrency();
  is($currencyCode,$inputTransaction->getCurrency(),'loaded currency code matches currency from input transaction');

  my $accountCode = $trans->getAccountCode(1);
  is($accountCode,$inputTransaction->getAccountCode(1),'loaded account code 1 matches account code from input transaction');

  my $accountCode2 = $trans->getAccountCode(2);
  is($accountCode2,$inputTransaction->getAccountCode(2),'loaded account code 2 matches account code from input transaction');

  my $accountCode3 = $trans->getAccountCode(3);
  is($accountCode3,$inputTransaction->getAccountCode(3),'loaded account code 3 matches account code from input transaction');

  my $accountCode4 = $trans->getAccountCode(4);
  is($accountCode4,$inputTransaction->getAccountCode(4),'loaded account code 4 matches account code from input transaction');

  my $publisherEmail = $trans->getReceiptSendingEmailAddress();
  is($publisherEmail, $inputTransaction->getReceiptSendingEmailAddress(), 'loaded receipt sending email address (publisher email) matches input transaction');
}
