package PlugNPay::API::REST::Responder::Merchant::Recurring::Attendant::Session;

use strict;
use CGI;
use PlugNPay::Recurring::Attendant;
use PlugNPay::GatewayAccount::LinkedAccounts;
use base 'PlugNPay::API::REST::Responder';


sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  if ($action eq 'create') {
    return $self->_create();
  } elsif ($action eq 'read') {
    return $self->_read();
  }

  $self->setResponseCode(501);
  return {};
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customer = $self->getResourceData()->{'customer'};
  my $sessionID = $self->getResourceData()->{'session'} || new CGI()->cookie('SESSIONID');

  my $attendant = new PlugNPay::Recurring::Attendant();
  if ($attendant->doesAttendantSessionExist($sessionID)) {
    $attendant->loadAttendantSession($sessionID);
    if ($attendant->getMerchant() ne $merchant || $attendant->getCustomer() ne $customer) {
      $self->setResponseCode(403);
      return { 'status' => 'error', 'message' => 'Access denied' };
    } else {
      my $sessionData = {
        'additionalData' => $attendant->getAdditionalData()
      };

      $self->setResponseCode(200);
      return { 'status' => 'success', 'session' => $sessionData };
    }
  } else {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Invalid session ID' };
  }
}

sub _create {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $inputData = $self->getInputData();
  
  if (!$resourceData->{'merchant'} || !$resourceData->{'customer'}) {
    $self->setResponseCode(400);
    return { 'status' => 'FAILURE', 'message' => 'Insufficient data sent in request.' };
  }
  
  my $merchant;
  if ($resourceData->{'merchant'} ne $self->getGatewayAccount()) {
    my $isLinked = new PlugNPay::GatewayAccount::LinkedAccounts($self->getGatewayAccount())->isLinkedTo($resourceData->{'merchant'});
    if (!$isLinked) {
      $self->setResponseCode(403);
      return { 'status' => 'FAILURE', 'message' => 'Account ' . $self->getGatewayAccount() . ' is not linked to authenticated account ' . $resourceData->{'merchant'} };
    } else {
      $merchant = $resourceData->{'merchant'};
    }
  } else {
    $merchant = $self->getGatewayAccount();
  }

  my $attendant = new PlugNPay::Recurring::Attendant();
  $attendant->setCustomer(lc $resourceData->{'customer'});
  $attendant->setMerchant($merchant);
  $attendant->setAdditionalData($inputData);

  if ($attendant->saveAttendantSession()) {
    $self->setResponseCode(201);
    return {'status' => 'SUCCESS', 'message' => 'Attendant session for ' . $attendant->getCustomer() . ' was successfully created.', 'sessionID' => $attendant->getSessionID(), 'url' => $attendant->getURL()};
  }

  $self->setResponseCode(422);
  return {'status' => 'FAILURE', 'message' => 'Failed to create attendant session for ' . $attendant->getCustomer()};
}

1;
