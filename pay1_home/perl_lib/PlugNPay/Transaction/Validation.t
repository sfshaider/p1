#!/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::More tests => 5;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use PlugNPay::Testing qw(skipIntegration);
use PlugNPay::Transaction::Response;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction;
use PlugNPay::Contact;

require_ok('PlugNPay::Transaction::Validation');
testTransactionDataValidation();
testTransactionObjectValidation();

exit;

sub testTransactionDataValidation {
  my $testInput = {
    'gatewayAccount'      => 'pnpdemo',
    'merchantOrderId'     => '1234567890',
    'amount'              => '1.00',
    'shippingInformation' => { 'name' => 'dylan', 'postalCode' => '12345' },
    'status'              => 'success'
  };

  my $mockDB = Test::MockModule->new('PlugNPay::Transaction::Loader');
  $mockDB->redefine('load' => sub {
    my $shipContact = new PlugNPay::Contact();
    $shipContact->setFullName('dylan');
    $shipContact->setPostalCode('12345');

    my $respObj = new PlugNPay::Transaction::Response();
    $respObj->setStatus('success');

    my $newTrans = new PlugNPay::Transaction('auth','card');
    $newTrans->setGatewayAccount('pnpdemo');
    $newTrans->setTransactionAmount('1.00');
    $newTrans->setOrderID('1234567890');
    $newTrans->setShippingInformation($shipContact);
    $newTrans->setResponse($respObj);
    return {
      'pnpdemo' => {
        '1234567890' => $newTrans
      }
    };
  });

  my $isValid = PlugNPay::Transaction::Validation::validateTransactionForEmailing($testInput);
  ok($isValid, 'Validated transaction data successfully');

  my $testBadInput = {
    'gatewayAccount'      => 'pnpdemo2',
    'merchantOrderId'     => '0987654321',
    'amount'              => '1200',
    'shippingInformation' => { 'name' => 'dylan', 'postalCode' => '12345' },
    'status'              => 'success'
  };

  my $shouldFail = PlugNPay::Transaction::Validation::validateTransactionForEmailing($testBadInput);
  ok(!$shouldFail, 'Proved data was invalid successfully');
}

sub testTransactionObjectValidation {
  my $testTransObj = new PlugNPay::Transaction('auth','card');
  my $isValid = PlugNPay::Transaction::Validation::isTransactionObject($testTransObj);
  ok($isValid, 'Verified variable is transaction object');
  my $isNotValid = PlugNPay::Transaction::Validation::isTransactionObject({});
  ok(!$isNotValid, 'Verified variable is not transaction object');
}

