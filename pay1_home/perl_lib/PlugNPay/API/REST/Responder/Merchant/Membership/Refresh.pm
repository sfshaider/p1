package PlugNPay::API::REST::Responder::Merchant::Membership::Refresh;

use strict;
use PlugNPay::Membership::PasswordManagement;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  if ($action eq 'create' || $action eq 'update') {
    return $self->_create();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _create {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();

  my $passwordMgt = new PlugNPay::Membership::PasswordManagement();
  my $status = $passwordMgt->refresh($merchant);
  if (!$status) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $status->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Refresh successfully invoked.' };
}

1;
