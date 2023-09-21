package PlugNPay::API::REST::Responder::Merchant::VerificationHash::Inbound;

use strict;
use PlugNPay::Merchant::VerificationHash;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  if ($action eq 'create' || $action eq 'update') {
    return $self->_create();
  } elsif ($action eq 'read') {
    return $self->_read();
  } elsif ($action eq 'delete') {
    return $self->_delete();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _create {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $inputData = $self->getInputData();

  my $authorizationHash = new PlugNPay::Merchant::VerificationHash();
  if (!$authorizationHash->isAuthorized($merchant)) {
    $self->setResponseCode(403);
    return { 'status' => 'error', 'message' => 'Not authorized.' };
  }

  my $status = $authorizationHash->createHash($merchant,
    'inbound', {
    'fields'       => $inputData->{'fields'},
    'timeWindow'   => $inputData->{'timeWindow'}
  });

  if (!$status) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $status->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Successfully saved authorization hash.' };
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();

  my $authorizationHash = new PlugNPay::Merchant::VerificationHash();
  if (!$authorizationHash->doesHashExist($merchant, 'inbound')) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'No authorization hash found.' };
  }

  my $authorizationHashData = $authorizationHash->loadHash($merchant, 'inbound');
  $self->setResponseCode(200);
  return { 'status' => 'success', 'authorizationHash' => $authorizationHashData };
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();

  my $authorizationHash = new PlugNPay::Merchant::VerificationHash();
  if (!$authorizationHash->isAuthorized($merchant)) {
    $self->setResponseCode(403);
    return { 'status' => 'error', 'message' => 'Not authorized.' };
  }

  if (!$authorizationHash->doesHashExist($merchant, 'inbound')) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'No authorization hash found.' };
  }

  my $status = $authorizationHash->deleteHash($merchant, 'inbound');
  if (!$status) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $status->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully deleted authorization hash.' };
}

1;
