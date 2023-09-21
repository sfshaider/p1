#!/bin/env perl

use strict;
use Test::More tests => 50;
use JSON::XS;
use PlugNPay::Transaction::Adjustment::Bucket;
use PlugNPay::Transaction::Adjustment::Settings;
use PlugNPay::API::MockRequest;
use PlugNPay::API::REST;
use PlugNPay::GatewayAccount;
use Test::MockModule;

require_ok('PlugNPay::API::REST::Responder::Merchant::Adjustment');
require_ok('PlugNPay::API::MockRequest');

my $dbsMock = Test::MockModule->new('PlugNPay::DBConnection');
if (!defined $ENV{'TEST_INTEGRATION'} || $ENV{'TEST_INTEGRATION'} ne '1') {
  # Mock PlugNPay::DBConnection
  my $noQueries = sub {
    print STDERR new PlugNPay::Util::StackTrace()->string("\n") . "\n";
    die('unexpected query executed')
  };
  $dbsMock->redefine(
      'executeOrDie' => $noQueries,
      'fetchallOrDie' => $noQueries
  );
}

# Integration tests, tested when $ENV{'TEST_INTEGRATION'} == "1"
SKIP: {
  if (!defined $ENV{'TEST_INTEGRATION'} || $ENV{'TEST_INTEGRATION'} ne '1') {
    skip("Skipping database tests because TEST_INTEGRATION environment variable is not '1'", 48);
  }
  testAdjustment();
}

sub testAdjustment {
  my $url = '/api/merchant/adjustment/';
  my $account = 'pnpdemo';
  my $cardA = '4111111111111111'; # visa debit
  my $cardB = '371746000000009';  # amex consumer
  my $cardC = '4444333322221111'; # visa business
  my $amount1 = '1000.00';
  my $amount2 = '100.00';
  my $amount3 = '0';

  # Set required gateway account settings
  my $gatewayAccount = new PlugNPay::GatewayAccount($account);
  $gatewayAccount->setCheckProcessor('testprocessorach');
  $gatewayAccount->save();

  my $data = {
      transactionInformation => [
          { transactionIdentifier => 1, transactionAmount => $amount1, paymentVehicleType => 'CARD', cardNumber => $cardA, paymentVehicleIdentifier => 'paymentOptionA' },
          { transactionIdentifier => 2, transactionAmount => $amount1, paymentVehicleType => 'CARD', cardNumber => $cardB, paymentVehicleIdentifier => 'paymentOptionB' },
          { transactionIdentifier => 3, transactionAmount => $amount1, paymentVehicleType => 'CARD', cardNumber => $cardC, paymentVehicleIdentifier => 'paymentOptionC' },
          { transactionIdentifier => 4, transactionAmount => $amount1, paymentVehicleType => 'ACH', paymentVehicleIdentifier => 'paymentOptionD' },
          { transactionIdentifier => 5, transactionAmount => $amount2, paymentVehicleType => 'CARD', cardNumber => $cardB, paymentVehicleIdentifier => 'paymentOptionE' },
          { transactionIdentifier => 6, transactionAmount => $amount3, paymentVehicleType => 'CARD', cardNumber => $cardB, paymentVehicleIdentifier => 'paymentOptionF' },
      ]
  };

  my $mockRequest = &createMockRequest($url, $data);

  # Set buckets
  my $bucketData = [
      { 'subtypeID'         => '2',
          'base'            => '0',
          'coaRate'         => '0',
          'totalRate'       => '2',
          'fixedAdjustment' => '0'
      },
      { 'subtypeID'         => '5',
          'base'            => '400',
          'coaRate'         => '0',
          'totalRate'       => '2.99',
          'fixedAdjustment' => '0'
      },
      { 'subtypeID'         => '5',
          'base'            => '0',
          'coaRate'         => '0',
          'totalRate'       => '0',
          'fixedAdjustment' => '12.5'
      },
      { 'subtypeID'         => '6',
          'base'            => '0',
          'coaRate'         => '0',
          'totalRate'       => '0',
          'fixedAdjustment' => '1'
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
    push @bucketArray, $bucket;
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

  # Set bucket mode
  my $bucketModes = { '1' => 'cumulative', '2' => 'single' };
  for my $bucketModeID (keys %{$bucketModes}) {
    my $bucketModeName = $bucketModes->{$bucketModeID};
    $adjustmentSettings->setBucketModeID($bucketModeID);

    # Set charge model
    my $models = { '7' => 'surcharge', '9' => 'intelligent rate', '12' => 'convenience fee', '14' => 'optional' };

    for my $modelID (keys %{$models}) {
      my $modelName = $models->{$modelID};
      $adjustmentSettings->setModelID($modelID);
      $adjustmentSettings->save();

      # Make api request
      my $result = &post($account, $mockRequest);

      my ($categoryA, $categoryB, $categoryC, $categoryE, $categoryF);
      my ($adjustmentA, $adjustmentB, $adjustmentC, $adjustmentD, $adjustmentE, $adjustmentF);
      foreach (keys %{$result}) {
        my $a = $result->{'content'}{'data'}{'paymentOptionA'};
        my $b = $result->{'content'}{'data'}{'paymentOptionB'};
        my $c = $result->{'content'}{'data'}{'paymentOptionC'};
        my $d = $result->{'content'}{'data'}{'paymentOptionD'};
        my $e = $result->{'content'}{'data'}{'paymentOptionE'};
        my $f = $result->{'content'}{'data'}{'paymentOptionF'};

        $categoryA = $a->{'category'};
        $categoryB = $b->{'category'};
        $categoryC = $c->{'category'};
        $categoryE = $e->{'category'};
        $categoryF = $f->{'category'};
        $adjustmentA = $a->{'calculatedAdjustment'}{'adjustment'};
        $adjustmentB = $b->{'calculatedAdjustment'}{'adjustment'};
        $adjustmentC = $c->{'calculatedAdjustment'}{'adjustment'};
        $adjustmentD = $d->{'calculatedAdjustment'}{'adjustment'};
        $adjustmentE = $e->{'calculatedAdjustment'}{'adjustment'};
        $adjustmentF = $f->{'calculatedAdjustment'}{'adjustment'};
      }

      my $expectedA = $modelName eq 'surcharge' ? '0' : '20';
      my $expectedB = $bucketModeName eq 'cumulative' ? '42.4' : '29.9';
      my $expectedC = $bucketModeName eq 'cumulative' ? '42.4' : '29.9';
      my $expectedD = '1';
      my $expectedE = '12.5';
      my $expectedF = '0';

      is($adjustmentA, $expectedA, "$bucketModeName $modelName adjustment for $amount1 on $categoryA");
      is($adjustmentB, $expectedB, "$bucketModeName $modelName adjustment for $amount1 on $categoryB");
      is($adjustmentC, $expectedC, "$bucketModeName $modelName adjustment for $amount1 on $categoryC (default bucket used)");
      is($adjustmentD, $expectedD, "$bucketModeName $modelName adjustment for $amount1 on ACH");
      is($adjustmentE, $expectedE, "$bucketModeName $modelName adjustment for $amount2 on $categoryE");
      is($adjustmentF, $expectedF, "$bucketModeName $modelName adjustment for $amount3 on $categoryF");
    }
  }
}

sub createMockRequest {
  my $url = shift;
  my $data = shift;

  my $mr = new PlugNPay::API::MockRequest();
  $mr->setResource($url);
  $mr->setMethod('POST');
  $mr->addHeaders({
      'content-type' => 'application/json'
  });
  $mr->setContent(encode_json($data));

  return $mr;
}

sub post {
  my $account = shift;
  my $mockRequest = shift;

  my $rest = new PlugNPay::API::REST('/api', { mockRequest => $mockRequest });
  $rest->setRequestGatewayAccount($account);
  my $response = $rest->respond({ skipHeaders => 1 });
  my $responseData = decode_json($response);
  return $responseData;
}