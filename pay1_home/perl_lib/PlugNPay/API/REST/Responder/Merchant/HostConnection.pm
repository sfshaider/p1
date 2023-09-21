package PlugNPay::API::REST::Responder::Merchant::HostConnection;

use strict;
use PlugNPay::Merchant::HostConnection;
use PlugNPay::Merchant::HostConnection::JSON;
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

  if($action eq 'create') {
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

  my $hostConnection = new PlugNPay::Merchant::HostConnection($merchant);
  my $saveHostConnectionStatus = $hostConnection->saveMerchantHostConnection($inputData);
  if (!$saveHostConnectionStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $saveHostConnectionStatus->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Successfully saved merchant host connection.' };
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $hostConnectionIdentifier = $self->getResourceData()->{'hostconnection'};
  my $options = $self->getResourceOptions();

  my $count = 0;
  my $hostConnections = [];

  my $hostConnection = new PlugNPay::Merchant::HostConnection($merchant);
  if ($hostConnectionIdentifier) {
    $hostConnection->loadByHostConnectionIdentifier($hostConnectionIdentifier);
    if (!$hostConnection->getHostConnectionID()) {
      $self->setResponseCode(404);
      return { 'status' => 'error', 'message' => 'Host connection identifier does not exist.' };
    }

    my $json = new PlugNPay::Merchant::HostConnection::JSON();
    push (@{$hostConnections}, $json->hostConnectionToJSON($hostConnection));
    $count++;
  } else {
    $hostConnection->setLimitData({ 'limit' => $options->{'pageLength'}, 'offset' => $options->{'page'} * $options->{'pageLength'} });
    my $merchantHostConnections = $hostConnection->loadMerchantHostConnections();

    my $json = new PlugNPay::Merchant::HostConnection::JSON();
    foreach my $merchantHostConnection (@{$merchantHostConnections}) {
      push (@{$hostConnections}, $json->hostConnectionToJSON($merchantHostConnection));
    }

    $count = $hostConnection->getMerchantHostConnectionListSize();
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'count' => $count, 'hostConnections' => $hostConnections };
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $hostConnectionIdentifier = $self->getResourceData()->{'hostconnection'};

  if (!$hostConnectionIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Host connection identifier not specified.' };
  }

  my $hostConnection = new PlugNPay::Merchant::HostConnection($merchant);
  $hostConnection->loadByHostConnectionIdentifier($hostConnectionIdentifier);
  my $deleteHostConnectionStatus = $hostConnection->deleteMerchantHostConnection();
  if (!$deleteHostConnectionStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deleteHostConnectionStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Host connection deleted successfully.' };
}

sub _update {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $hostConnectionIdentifier = $self->getResourceData()->{'hostconnection'};
  my $inputData = $self->getInputData();

  if (!$hostConnectionIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No host connection identifier specified.' };
  }

  my $hostConnection = new PlugNPay::Merchant::HostConnection($merchant);
  $hostConnection->loadByHostConnectionIdentifier($hostConnectionIdentifier);
  if (!$hostConnection->getHostConnectionID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Host connection identifier does not exist.' };
  }

  my $updateHostConnectionStatus = $hostConnection->updateMerchantHostConnection($inputData);
  if (!$updateHostConnectionStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updateHostConnectionStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully updated merchant host connection.' };
}

1;
