package PlugNPay::API::REST::Responder::Reseller::Merchant::RemoteClient;

use strict;
use PlugNPay::GatewayAccount;
use PlugNPay::Reseller;
use PlugNPay::Reseller::Chain;

use base 'PlugNPay::API::REST::Responder::Abstract::RemoteClient';

sub checkRCPermission {
  my $self = shift;
  my $resellerName = $self->getResourceData()->{'reseller'};
  my $merchantName = $self->getResourceData()->{'merchant'};

  if (!$merchantName) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'no merchant info sent' };
  }

  if (!$resellerName) {
    $resellerName = $self->getGatewayAccount();
  } 

  my $reseller = new PlugNPay::Reseller($resellerName);
  if (!$reseller->exists()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'reseller not found' };
  }

  my $ga = new PlugNPay::GatewayAccount($merchantName);
  if (!$ga->exists()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'merchant not found' };
  }

  if ($resellerName ne $self->getGatewayAccount()) {
    my $chain = new PlugNPay::Reseller::Chain($reseller->getResellerAccount());
    if (!$chain->hasDescendant($resellerName)) {
      $self->setResponseCode(403);
      return { 'status' => 'error', 'message' => 'unauthorized privileges to make changes' };
    }
  }

  if (($resellerName ne $ga->getReseller()) || (!$reseller->getFeature('reset_client_password'))) {
    $self->setResponseCode(403);
    return { 'status' => 'error', 'message' => 'unauthorized privileges to make changes' };
  }

  return { 'status' => 'success' };
}

1;
