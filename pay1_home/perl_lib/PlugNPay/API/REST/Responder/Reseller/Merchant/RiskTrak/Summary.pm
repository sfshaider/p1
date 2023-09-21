package PlugNPay::API::REST::Responder::Reseller::Merchant::RiskTrak::Summary;

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
  my $orderid = $options->{'OID'};

  my $chain = new PlugNPay::Reseller::Chain();
  $chain->setReseller($reseller);

  my $summaryInfo = {};
  # verify that submitted reseller is either the logged in account or a subreseller thereof
  if ($reseller = $self->getGatewayAccount() || $chain->hasDescendant($reseller)) {
    my $risktrak = new PlugNPay::GatewayAccount::RiskTrak();
    $risktrak->setGatewayAccount($merchant);
    my $hash = {};
    $summaryInfo = $risktrak->getSummary($orderid);
    $self->setResponseCode(200);
  } else {
    $self->setResponseCode('403');
  }

  return { 'summaryInfo' => $summaryInfo };
}

1;

