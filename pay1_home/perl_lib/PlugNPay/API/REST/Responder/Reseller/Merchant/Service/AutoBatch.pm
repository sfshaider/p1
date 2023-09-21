package PlugNPay::API::REST::Responder::Reseller::Merchant::Service::AutoBatch;

use strict;
use PlugNPay::GatewayAccount;
use PlugNPay::Reseller::Chain;
use PlugNPay::GatewayAccount::Services;
use JSON::XS qw(decode_json);

use URI qw();

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData{
  my $self = shift;
  my $ga = new PlugNPay::GatewayAccount($self->getResourceData()->{'merchant'});
  my $reseller = $self->getGatewayAccount();
  my $chain = new PlugNPay::Reseller::Chain($reseller);
  my $action = $self->getAction();

  if ($action eq 'update' && ($reseller eq $ga->getReseller() || $chain->hasDescendant($ga->getReseller()))) {
    return $self->_update();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _update {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $ga = $resourceData->{'merchant'};
  if (!$ga) {
    $self->setResponseCode(422);
    $self->setErrorMessage('Unable to determine api client account');
    return {};
  }

  my $input = $self->getInputData();
  my $autoBatch = $input->{'autoBatch'};

  my $services = new PlugNPay::GatewayAccount::Services($ga);
  $services->setAutoBatch($autoBatch);
  $services->save();
  $self->setResponseCode(200);
  return {};
}


1;
