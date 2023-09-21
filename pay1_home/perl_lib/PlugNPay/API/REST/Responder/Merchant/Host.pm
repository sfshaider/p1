package PlugNPay::API::REST::Responder::Merchant::Host;

use strict;
use PlugNPay::Merchant::Host;
use PlugNPay::Merchant::Host::JSON;
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

  my $host = new PlugNPay::Merchant::Host($merchant);
  my $saveHostStatus = $host->saveMerchantHost($inputData);
  if (!$saveHostStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $saveHostStatus->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Successfully saved merchant host.' };
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $hostIdentifier = $self->getResourceData()->{'host'};
  my $options = $self->getResourceOptions();

  my $count = 0;
  my $hosts = [];

  my $host = new PlugNPay::Merchant::Host($merchant);
  if ($hostIdentifier) {
    $host->loadByHostIdentifier($hostIdentifier);
    if (!$host->getHostID()) {
      $self->setResponseCode(404);
      return { 'status' => 'error', 'message' => 'Host identifier does not exist.' };
    }

    my $json = new PlugNPay::Merchant::Host::JSON();
    push (@{$hosts}, $json->hostToJSON($host));
    $count++;
  } else {
    $host->setLimitData({ 'limit' => $options->{'pageLength'}, 'offset' => $options->{'page'} * $options->{'pageLength'} });
    my $merchantHosts = $host->loadMerchantHosts();
    if (@{$merchantHosts} > 0) {
      my $json = new PlugNPay::Merchant::Host::JSON();
      foreach my $merchantHost (@{$merchantHosts}) {
        push (@{$hosts}, $json->hostToJSON($merchantHost)); 
      }
    }

    $count = $host->getMerchantHostListSize();
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'count' => $count, 'hosts' => $hosts };
}

sub _update {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $hostIdentifier = $self->getResourceData()->{'host'};
  my $inputData = $self->getInputData();

  my $host = new PlugNPay::Merchant::Host($merchant);
  if (!$hostIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No host identifier sent.' };
  }

  $host->loadByHostIdentifier($hostIdentifier);
  if (!$host->getHostID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Invalid host identifier.' };
  }

  my $updateHostStatus = $host->updateMerchantHost($inputData);
  if (!$updateHostStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updateHostStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully updated merchant host.' };
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $hostIdentifier = $self->getResourceData()->{'host'};

  if (!$hostIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No host identifier specified.' };
  }

  my $host = new PlugNPay::Merchant::Host($merchant);
  $host->loadByHostIdentifier($hostIdentifier);
  my $deleteHostStatus = $host->deleteMerchantHost();
  if (!$deleteHostStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deleteHostStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully deleted merchant host.' };
}

1;
