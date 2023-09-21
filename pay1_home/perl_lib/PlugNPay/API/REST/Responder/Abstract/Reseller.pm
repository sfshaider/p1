package PlugNPay::API::REST::Responder::Abstract::Reseller;

use strict;
use PlugNPay::Reseller::Chain;
use base 'PlugNPay::API::REST::Responder';

#Purpose: to check if the requestor is a super reseller of the sent reseller (or IS the sent reseller)
sub _getOutputData {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $inputData = $self->getInputData();

  my $resellerName = $resourceData->{'reseller'} || $inputData->{'reseller'};
  if ($resellerName && $resellerName ne $self->getGatewayAccount()) {
    my $resellerChain = new PlugNPay::Reseller::Chain($self->getGatewayAccount());
    unless ($resellerChain->hasDescendant($resellerName)) {
      $self->setResponseCode(403);
      return {'status' => 'failure', 'message' => 'Insufficient privileges'};
    }
  }

  $self->setReseller(($resellerName ? $resellerName : $self->getGatewayAccount()));
  return $self->__getOutputData();
}

#Overwrite this in sub-modules
sub __getOutputData {
  die('__getOutputData not implemented.');
}

#Can now access this in sub-modules
sub setReseller {
  my $self = shift;
  my $reseller = shift;
  $self->{'reseller'} = $reseller;
}

sub getReseller {
  my $self = shift;
  return $self->{'reseller'};
}

1;
