package PlugNPay::API::REST::Responder::Reseller::Merchant::RiskTrak::History;

use strict;
use PlugNPay::Reseller;
use PlugNPay::Reseller::Chain;
use PlugNPay::GatewayAccount::RiskTrak;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;

  my $reseller = $self->getResourceData()->{'reseller'};
  my $options = $self->getResourceOptions();

  my $merchant = $self->getResourceData()->{'merchant'};

  my $chain = new PlugNPay::Reseller::Chain();
  $chain->setReseller($reseller);

  my $historyInfo = {};
  if ($chain->hasDescendant($reseller) || $reseller eq $self->getGatewayAccount()) {
    my $risktrak = new PlugNPay::GatewayAccount::RiskTrak();
    $risktrak->setGatewayAccount($merchant);
    $historyInfo = $risktrak->getHistory($options);
    $self->setResponseCode(200);
  } else {
    $self->setResponseCode(403);
  }

  return { 'history' => $historyInfo };
}

1;


