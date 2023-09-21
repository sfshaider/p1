package PlugNPay::API::REST::Responder::Merchant::Credential;

use strict;
use PlugNPay::Merchant::Credential;
use PlugNPay::Merchant::Credential::JSON;
use PlugNPay::GatewayAccount::LinkedAccounts;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  # check linked account
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  if ($merchant ne $self->getGatewayAccount()) {
    my $linked = new PlugNPay::GatewayAccount::LinkedAccounts($self->getGatewayAccount())->isLinkedTo($merchant);
    if (!$linked) {
      $self->setResponseCode(403);
      return { 'error' => 'Access Denied' };
    }
  }

  if ($action eq 'create') {
    return $self->_create();
  } elsif ($action eq 'read') {
    return $self->_read();
  } elsif ($action eq 'delete') {
    return $self->_delete();
  } elsif ($action eq 'update') {
    return $self->_update();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _create {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $inputData = $self->getInputData();

  my $credential = new PlugNPay::Merchant::Credential($merchant);
  my $saveCredentialStatus = $credential->saveMerchantCredential($inputData);
  if (!$saveCredentialStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $saveCredentialStatus->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Successfully saved merchant credential.' };
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $credentialIdentifier = $self->getResourceData()->{'credential'};
  my $options = $self->getResourceOptions();

  my $count = 0;
  my $credentials = [];

  my $credential = new PlugNPay::Merchant::Credential($merchant);
  if ($credentialIdentifier) {
    $credential->loadByCredentialIdentifier($credentialIdentifier);
    if (!$credential->getCredentialID()) {
      $self->setResponseCode(404);
      return { 'status' => 'error', 'message' => 'Credential identifier does not exist.' };
    }

    my $json = new PlugNPay::Merchant::Credential::JSON();
    push (@{$credentials}, $json->credentialToJSON($credential));
    $count++;
  } else {
    $credential->setLimitData({ 'limit' => $options->{'pageLength'}, 'offset' => $options->{'page'} * $options->{'pageLength'} });
    my $merchantCredentials = $credential->loadMerchantCredentials();
    if (@{$merchantCredentials} > 0) {
      my $json = new PlugNPay::Merchant::Credential::JSON();
      foreach my $merchantCredential (@{$merchantCredentials}) {
        push (@{$credentials}, $json->credentialToJSON($merchantCredential)); 
      }
    }

    $count = $credential->getMerchantCredentialListSize();
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'count' => $count, 'credentials' => $credentials };
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $credentialIdentifier = $self->getResourceData()->{'credential'};

  if (!$credentialIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No credential identifier specified.' };
  }

  my $credential = new PlugNPay::Merchant::Credential($merchant);
  $credential->loadByCredentialIdentifier($credentialIdentifier);
  my $deleteCredentialStatus = $credential->deleteMerchantCredential();
  if (!$deleteCredentialStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deleteCredentialStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully deleted merchant credential.' };
}

sub _update {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $credentialIdentifier = $self->getResourceData()->{'credential'};
  my $inputData = $self->getInputData();

  if (!$credentialIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No credential identifier specified.' };
  }

  my $credential = new PlugNPay::Merchant::Credential($merchant);
  $credential->loadByCredentialIdentifier($credentialIdentifier);
  if (!$credential->getCredentialID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Credential identifier does not exist.' };
  }

  my $updateCredentialStatus = $credential->updateMerchantCredential($inputData);
  if (!$updateCredentialStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updateCredentialStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully updated merchant credential.' };
}

1;
