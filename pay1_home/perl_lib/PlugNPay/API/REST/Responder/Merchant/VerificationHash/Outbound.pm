package PlugNPay::API::REST::Responder::Merchant::VerificationHash::Outbound;

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

  my $verificationHash = new PlugNPay::Merchant::VerificationHash();
  if (!$verificationHash->isAuthorized($merchant)) {
    $self->setResponseCode(403);
    return { 'status' => 'error', 'message' => 'Not authorized.' };
  }

  my $status = $verificationHash->createHash($merchant,
    'outbound', {
    'fields' => $inputData->{'fields'}
  });

  if (!$status) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $status->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Successfully saved response verification hash.' };
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();

  my $verificationHash = new PlugNPay::Merchant::VerificationHash();
  if (!$verificationHash->doesHashExist($merchant, 'outbound')) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'No verification hash found.' };
  }

  my $verificationHashData = $verificationHash->loadHash($merchant, 'outbound');
  $self->setResponseCode(200);
  return { 'status' => 'success', 'verificationHash' => $verificationHashData };
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();

  my $verificationHash = new PlugNPay::Merchant::VerificationHash();
  if (!$verificationHash->isAuthorized($merchant)) {
    $self->setResponseCode(403);
    return { 'status' => 'error', 'message' => 'Not authorized.' };
  }

  if (!$verificationHash->doesHashExist($merchant, 'outbound')) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'No response verification hash found.' };
  }

  my $status = $verificationHash->deleteHash($merchant, 'outbound');
  if (!$status) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $status->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully deleted response verification hash.' };
}

1;
