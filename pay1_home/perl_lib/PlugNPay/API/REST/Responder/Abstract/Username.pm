package PlugNPay::API::REST::Responder::Abstract::Username;

use strict;
use PlugNPay::GatewayAccount::LinkedAccounts;
use PlugNPay::Username;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  my $username = $self->getResourceData()->{'username'} || $self->getGatewayAccount();
  my $validated = $self->validateCredentials($username);

  if ($action ne 'create' && !$validated && PlugNPay::Username::exists($self->getResourceData()->{'username'})) {
    $self->setResponseCode(403);
    return {'status' => 'failure', 'message' => 'Insufficient privileges'};
  }

  my $response = {};
  if ($action eq 'create') {
    $response = $self->_create();
  } elsif ($action eq 'read') {
    $response = $self->_read();
  } elsif ($action eq 'update') {
    $response = $self->_update();
  } elsif ($action eq 'delete') {
    $response = $self->_delete();
  } else {
    $self->setResponseCode(501);
  }

  return $response;
}

sub _create {
  my $self = shift;
  return {};
}

sub _read {
  my $self = shift;
  return {};
}

sub _update {
  my $self = shift;
  return {};
}

sub _delete {
  my $self = shift;
  return {};
}

sub validateCredentials {
  my $self = shift; 
  my $usernameToCheck = lc shift;
  my $checkAgainst = $self->getGatewayAccount();
  my $usernameObj = new PlugNPay::Username($checkAgainst);

  my $authorized = ($usernameToCheck eq lc $checkAgainst) && $usernameObj->getSecurityLevel() == 0;
  if (!$authorized) {
    my $loginObj = new PlugNPay::Username($usernameToCheck);
    my $linkedAccounts = new PlugNPay::GatewayAccount::LinkedAccounts($checkAgainst);
    $authorized = $linkedAccounts->isLinkedTo($loginObj->getGatewayAccount()) && $linkedAccounts->isMaster();
  }
    
  return $authorized;
}

1;
