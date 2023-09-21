#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef;
}

use strict;
use Test::More tests => 5;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);

use lib $ENV{'PNP_PERL_LIB'};
require_ok('PlugNPay::Partners::Cardinal::ApiKey');

my $account = 'pnpdemo';

my $key1Data = {
  'apiKeyName' => 'pnpdemo_test_key',
  'apiKey'     => '123',
  'apiKeyId'   => '456'
};

my $key2Data = {
  'apiKeyName' => 'pnpdemo_test_key_2',
  'apiKey'     => '789',
  'apiKeyId'   => '012'
};

SKIP: {
  if (!skipIntegration("skipping integration tests", 4)) {
    save($account, $key1Data);
    verifyApiKeyData($account, $key1Data);
    save($account, $key2Data);
    deleteKeyData($account, $key2Data);
  }
}

sub save {
  my $account = shift;
  my $data = shift;

  my $apiKey = new PlugNPay::Partners::Cardinal::ApiKey();
  $apiKey->setGatewayAccount($account);
  $apiKey->setApiKeyName($data->{'apiKeyName'});
  $apiKey->setApiKey($data->{'apiKey'});
  $apiKey->setApiKeyId($data->{'apiKeyId'});

  my $success = 0;
  my $status = $apiKey->save();
  if ($status->getStatus()) {
    my $decodedResponse = $status->get('decodedResponse');
    $success = $decodedResponse->{'error'} ? 0 : 1;
  }

  is($success, 1, 'api key data saved successfully');
}

sub verifyApiKeyData {
  my $account = shift;

  my $apiKey = new PlugNPay::Partners::Cardinal::ApiKey();
  $apiKey->setGatewayAccount($account);

  my $allData = $apiKey->getAllApiKeyData();
  my $apiKeyData = $allData->{'data'};
  my $exists = @{$apiKeyData} >= 1 ? 1 : 0;
  is($exists, 1, 'apiKeyData exists');
}

sub deleteKeyData {
  my $account = shift;
  my $data = shift;

  my $apiKey = new PlugNPay::Partners::Cardinal::ApiKey();
  $apiKey->setGatewayAccount($account);

  # Delete key
  $apiKey->setApiKeyId($data->{'apiKeyId'});

  my $success = 0;
  my $status = $apiKey->delete();
  if ($status->getStatus()) {
    my $decodedResponse = $status->get('decodedResponse');
    $success = $decodedResponse->{'error'} ? 0 : 1;
  }

  is($success, 1, 'key was deleted successfully');
}
