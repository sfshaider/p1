#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef;
}

use strict;
use Test::More tests => 15;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);
use Switch;

use lib $ENV{'PNP_PERL_LIB'};
require_ok('PlugNPay::Partners::Cardinal::Settings');
require_ok('PlugNPay::GatewayAccount');

my $account = 'pnpdemo';

my $gatewayAccount = new PlugNPay::GatewayAccount($account);
my $originalStatus = $gatewayAccount->getStatus();
$gatewayAccount->setForceStatusChange('1');
$gatewayAccount->setTest();
$gatewayAccount->save();

my $settingData = {
  'orgUnitId'           => '123abc',
  'processorId'         => '123',
  'merchantId'          => 'pnpdemo_test',
  'transactionPassword' => 'pnpdemo_testpw',
  'enabled'             => '1',
  'staging'             => '1',
  'defaultApiKeyId'     => undef
};


SKIP: {
  if (!skipIntegration("skipping integration tests", 13)) {
    saveSettings($account, $settingData);
    verifySettings($account, $settingData);
    deleteSettings($account);
    saveSettings($account, $settingData); # re-save the data
    resetOriginalValues($gatewayAccount, $originalStatus)
  }
}

sub saveSettings {
  my $account = shift;
  my $settingData = shift;
  my $settings;

  $settings = new PlugNPay::Partners::Cardinal::Settings();
  $settings->setGatewayAccount($account);
  $settings->setOrgUnitId($settingData->{'orgUnitId'});
  $settings->setProcessorId($settingData->{'processorId'});
  $settings->setMerchantId($settingData->{'merchantId'});
  $settings->setTransactionPassword($settingData->{'transactionPassword'});
  $settings->setEnabled($settingData->{'enabled'});
  $settings->setStaging($settingData->{'staging'});
  $settings->setDefaultApiKeyId($settingData->{'defaultApiKeyId'});

  my $success = 0;
  my $status = $settings->saveSettings();
  if ($status->getStatus()) {
    my $decodedResponse = $status->get('decodedResponse');
    $success = $decodedResponse->{'error'} ? 0 : 1;
  }

  is($success, 1, 'Settings saved successfully');
}

sub verifySettings {
  my $account = shift;
  my $settingData = shift;
  my $settings;

  $settings = new PlugNPay::Partners::Cardinal::Settings($account);
  is($settings->customerHasSettings()->{'hasSettings'}, 1, "customer has settings");
  is($settings->getOrgUnitId(), $settingData->{'orgUnitId'}, 'orgUnitId is correct');
  is($settings->getProcessorId(), $settingData->{'processorId'}, 'processorId is correct');
  is($settings->getMerchantId(), $settingData->{'merchantId'}, 'merchantId is correct');
  is($settings->getTransactionPassword(), $settingData->{'transactionPassword'}, 'transactionPassword is correct');
  is($settings->getEnabled(), $settingData->{'enabled'}, 'enabled is correct');
  is($settings->getStaging(), $settingData->{'staging'}, 'staging is correct');
  is($settings->getDefaultApiKeyId(), $settingData->{'defaultApiKeyId'}, 'defaultApiKeyId is correct');
  is($settings->isApiKeyIdDefault($settingData->{'defaultApiKeyId'}), '1', 'api key is the default');
}

sub deleteSettings {
  my $account = shift;

  my $settings = new PlugNPay::Partners::Cardinal::Settings();
  $settings->setGatewayAccount($account);

  my $success = 0;
  my $status = $settings->delete();
  if ($status->getStatus()) {
    my $decodedResponse = $status->get('decodedResponse');
    $success = $decodedResponse->{'error'} ? 0 : 1;
  }
  is($success, 1, 'settings were deleted successfully');
}

sub resetOriginalValues {
  $gatewayAccount = shift;
  $originalStatus = shift;

  switch($originalStatus) {
    case 'pending' {$gatewayAccount->setPending()}
    case 'debug' {$gatewayAccount->setDebug()}
    case 'live' {$gatewayAccount->setLive()}
    case 'cancelled' {$gatewayAccount->setCancelled()}
    case 'test' {$gatewayAccount->setTest()}
    case 'fraud' {$gatewayAccount->setFraud()}
    case 'hold' {$gatewayAccount->setOnHold()}
  }
  $gatewayAccount->save();

  is($gatewayAccount->getStatus, $originalStatus, 'account status has been set back to its original value');
}








