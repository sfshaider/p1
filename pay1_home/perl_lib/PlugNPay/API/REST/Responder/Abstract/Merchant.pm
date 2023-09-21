package PlugNPay::API::REST::Responder::Abstract::Merchant;

use strict;
use PlugNPay::GatewayAccount::LinkedAccounts;
use base 'PlugNPay::API::REST::Responder';

#Purpose: to check if the requestor is a super reseller of the sent reseller (or IS the sent reseller)
sub _getOutputData {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $inputData = $self->getInputData();
  my $merchant = $resourceData->{'merchant'} || $inputData->{'merchant'};
  if ($merchant && $merchant ne $self->getGatewayAccount()) {
    my $linkedAccounts = new PlugNPay::GatewayAccount::LinkedAccount($self->getGatewayAccount());
    unless ($linkedAccounts->isLinkedTo($merchant)) {
      $self->setResponseCode(403);
      return {'status' => 'failure', 'message' => 'Insufficient privileges'};
    }
  }

  return $self->__getOutputData();
}

#Overwrite this in sub-modules
sub __getOutputData {
  die('__getOutputData not implemented.');
}

1;
