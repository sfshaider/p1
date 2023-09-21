package PlugNPay::API::REST::Responder::Merchant::RemoteClient;

use strict;
use PlugNPay::GatewayAccount;
use PlugNPay::GatewayAccount::LinkedAccounts;

use base 'PlugNPay::API::REST::Responder::Abstract::RemoteClient';

sub checkRCPermission {
  my $self = shift;
  my $merchantName = $self->getResourceData()->{'merchant'};
 
  my $ga = new PlugNPay::GatewayAccount($merchantName);

  if (!$merchantName) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'no merchant sent' };
  }

  if (!$ga->exists($merchantName)) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'merchant not found' };
  }

  if ($merchantName ne $self->getGatewayAccount()) {
    my $linkedAccounts = new PlugNPay::GatewayAccount::LinkedAccounts($self->getGatewayAccount());
    if (!$linkedAccounts->isLinkedTo($merchantName)) {
      $self->setResponseCode(403);
      return { 'status' => 'error', 'message' => 'unauthorized privileges' };
    } 
  }
  return { 'status' => 'success' };
}

1;
