package PlugNPay::API::REST::Responder::Reseller::Merchant::RiskTrak::Stats;

use strict;
use PlugNPay::Reseller;
use PlugNPay::Reseller::Chain;
use PlugNPay::GatewayAccount::RiskTrak;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;

  my $reseller = $self->getResourceData()->{'reseller'};
  my $options = $self->getResourceOptions();

  my $merchant = $options->{'merchant'};

  my $chain = new PlugNPay::Reseller::Chain();
  $chain->setReseller($reseller);

  my $statsInfo = {};
  if ($chain->hasDescendant($reseller) || $reseller eq $self->getGatewayAccount()) {
    my $risktrak = new PlugNPay::GatewayAccount::RiskTrak();
    $risktrak->setGatewayAccount($merchant);
    my $hash = {};
    $statsInfo = $risktrak->getStats($options);
    $self->setResponseCode(200);
  } else {
    $self->setResponseCode(403);
  }

  return { 'statsInfo' => $statsInfo };
}

1;


