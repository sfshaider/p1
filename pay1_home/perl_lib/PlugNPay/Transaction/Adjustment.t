#!/bin/env perl

use strict;
use Test::More tests => 57;
use Data::Dumper;
use PlugNPay::Transaction::Adjustment;
use PlugNPay::Transaction::Adjustment::Bucket;
use PlugNPay::Transaction::Adjustment::Settings;
use PlugNPay::GatewayAccount;
use Test::MockModule;

my $dbsMock = Test::MockModule->new('PlugNPay::DBConnection');
if (!defined $ENV{'TEST_INTEGRATION'} || $ENV{'TEST_INTEGRATION'} ne '1') {
  # Mock PlugNPay::DBConnection
  my $noQueries = sub {
    print STDERR new PlugNPay::Util::StackTrace()->string("\n") . "\n";
    die('unexpected query executed')
  };
  $dbsMock->redefine(
      'executeOrDie'  => $noQueries,
      'fetchallOrDie' => $noQueries,
      'getHandleFor'  => $noQueries
  );
}

require_ok('PlugNPay::Transaction::Adjustment');

my $account = 'pnpdemo';
my $cardA = '4111111111111111'; # visa debit
my $cardB = '371746000000009';  # amex consumer
my $cardC = '4444333322221111'; # visa business
my $cardD = '6011000990139424'; # discover rewards
my $amount1 = '1000.00';
my $amount2 = '100.00';
my $amount3 = '0';

# Integration tests, tested when $ENV{'TEST_INTEGRATION'} == "1"
SKIP: {
  if (!defined $ENV{'TEST_INTEGRATION'} || $ENV{'TEST_INTEGRATION'} ne '1') {
    skip("Skipping database tests because TEST_INTEGRATION environment variable is not '1'", 56);
  }

  # Set required gateway account settings
  my $gatewayAccount = new PlugNPay::GatewayAccount($account);
  $gatewayAccount->setCheckProcessor('testprocessorach');
  $gatewayAccount->save();

  my $data = [
    { transactionIdentifier => 1, transactionAmount => $amount1, paymentVehicleType => 'CARD', cardNumber => $cardA },
    { transactionIdentifier => 2, transactionAmount => $amount1, paymentVehicleType => 'CARD', cardNumber => $cardB },
    { transactionIdentifier => 3, transactionAmount => $amount1, paymentVehicleType => 'CARD', cardNumber => $cardC },
    { transactionIdentifier => 4, transactionAmount => $amount1, paymentVehicleType => 'CARD', cardNumber => $cardD },
    { transactionIdentifier => 5, transactionAmount => $amount1, paymentVehicleType => 'ACH' },
    { transactionIdentifier => 6, transactionAmount => $amount2, paymentVehicleType => 'CARD', cardNumber => $cardB },
    { transactionIdentifier => 7, transactionAmount => $amount3, paymentVehicleType => 'CARD', cardNumber => $cardB },
  ];

  # Set buckets
  my $bucketData = [
      {   'subtypeID'             => '1',
          'base'                  => '1500',
          'coaRate'               => '0',
          'totalRate'             => '0',
          'fixedAdjustment'       => '10'
      },
      {   'subtypeID'             => '2',
          'base'                  => '0',
          'coaRate'               => '0',
          'totalRate'             => '2',
          'fixedAdjustment'       => '0'
      },
      {   'subtypeID'             => '5',
          'base'                  => '400',
          'coaRate'               => '0',
          'totalRate'             => '2.99',
          'fixedAdjustment'       => '0'
      },
      {   'subtypeID'             => '5',
          'base'                  => '0',
          'coaRate'               => '0',
          'totalRate'             => '0',
          'fixedAdjustment'       => '12.5'
      },
      {   'subtypeID'             => '6',
          'base'                  => '0',
          'coaRate'               => '0',
          'totalRate'             => '0',
          'fixedAdjustment'       => '1'
      },
  ];

  my @bucketArray;
  foreach my $bucketInfo (@{$bucketData}) {
    my $bucket = new PlugNPay::Transaction::Adjustment::Bucket();
    $bucket->setPaymentVehicleSubtypeID($bucketInfo->{'subtypeID'});
    $bucket->setBase($bucketInfo->{'base'});
    $bucket->setCOARate($bucketInfo->{'coaRate'});
    $bucket->setTotalRate($bucketInfo->{'totalRate'});
    $bucket->setFixedAdjustment($bucketInfo->{'fixedAdjustment'});
    push @bucketArray,$bucket;
  }
  my $bucketCreator = new PlugNPay::Transaction::Adjustment::Bucket($account);
  $bucketCreator->setBuckets(\@bucketArray);

  # Adjustment settings
  my $adjustmentSettings = new PlugNPay::Transaction::Adjustment::Settings($account);
  $adjustmentSettings->setEnabled('1');
  $adjustmentSettings->setBucketDefaultSubtypeID('5'); # consumer
  $adjustmentSettings->setCapModeID('6');
  $adjustmentSettings->setCapDefaultSubtypeID('6');
  $adjustmentSettings->setThresholdModeID('3');
  $adjustmentSettings->setFixedThreshold('0');
  $adjustmentSettings->setPercentThreshold('0');
  $adjustmentSettings->save();

  for my $transData (@{$data}) {
    my $adjustmentCalculator = new PlugNPay::Transaction::Adjustment($account);
    $adjustmentCalculator->setCardNumber($transData->{'cardNumber'});
    $adjustmentCalculator->setTransactionAmount($transData->{'transactionAmount'});
    $adjustmentCalculator->setTransactionIdentifier($transData->{'transactionIdentifier'});
    $adjustmentCalculator->setPaymentVehicle($transData->{'paymentVehicleType'});
    &calculator($adjustmentCalculator);
  }

  sub calculator {
    my $adjustmentCalculator = shift;

    my $transactionAmount;
    my $paymentVehicle;
    foreach (keys %{$adjustmentCalculator}) {
      $transactionAmount = $adjustmentCalculator->{'transactionAmount'};
      $paymentVehicle = $adjustmentCalculator->{'paymentVehicle'};
    }

    # Set bucket mode
    my $bucketModes = {'1' => 'cumulative', '2' => 'single'};
    for my $bucketModeID (keys %{$bucketModes}) {
      my $bucketModeName = $bucketModes->{$bucketModeID};
      $adjustmentSettings->setBucketModeID($bucketModeID);

      # Set charge model
      my $models = { '7' => 'surcharge', '9' => 'intelligent rate', '12' => 'convenience fee', '14' => 'optional' };

      for my $modelID (keys %{$models}) {
        my $modelName = $models->{$modelID};
        $adjustmentSettings->setModelID($modelID);
        $adjustmentSettings->save();

        # Run calculate
        my $adjustmentResults = $adjustmentCalculator->calculate();

        my $calculatedAdjustment = $adjustmentResults->getAdjustmentData('calculated')->{'adjustment'};
        my $type = $adjustmentResults->getCardType;
        if ($paymentVehicle eq 'ACH') {
          $calculatedAdjustment = $adjustmentResults->getAdjustmentData('ach')->{'adjustment'};
          $type = 'ACH';
        }

        # Set expected results
        my $expectedAdjustment;
        my $expectedDebit = $modelName eq 'surcharge' ? '0' : '20';
        my $expectedConsumer;
        if ($transactionAmount >= 400) {
          $expectedConsumer = $bucketModeName eq 'cumulative' ? '42.4' : '29.9';
        } else {
          $expectedConsumer = '12.5';
        }
        my $expectedBusiness = $transactionAmount >= 1500 ? '10' : '0';
        my $expectedACH = '1';

        if ($transactionAmount > 0) {
          if ($type eq 'debit') {
            $expectedAdjustment = $expectedDebit;
          }
          elsif ($type eq 'consumer') {
            $expectedAdjustment = $expectedConsumer;
          }
          elsif ($type eq 'business') {
            $expectedAdjustment = $expectedBusiness;
          }
          elsif ($type eq 'ACH') {
            $expectedAdjustment = $expectedACH;
          }
          else { # expect default which is 'consumer'
            $expectedAdjustment = $expectedConsumer;
          }
        } else {
          $expectedAdjustment = 0;
        }

        my $typeLabel = $type ne '' ? $type : 'undefined card type';

        is($calculatedAdjustment, $expectedAdjustment, "$bucketModeName $modelName adjustment for $transactionAmount is $expectedAdjustment for $typeLabel");

      }
    }
  }
}