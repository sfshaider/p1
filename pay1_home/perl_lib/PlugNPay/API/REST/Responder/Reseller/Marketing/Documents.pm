package PlugNPay::API::REST::Responder::Reseller::Marketing::Documents;

use strict;
use PlugNPay::Reseller;
use PlugNPay::Reseller::Chain;
use PlugNPay::Reseller::MarketingInfo;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;

  my $reseller = $self->getResourceData()->{'reseller'};

  my $chain = new PlugNPay::Reseller::Chain();
  $chain->setReseller($self->getGatewayAccount());

  my $documentInfo = [];
  if ($chain->hasDescendant($reseller) || $reseller eq $self->getGatewayAccount()) {
    my $docs = new PlugNPay::Reseller::MarketingInfo();
    my $hash = {};
    $hash->{docs} = $docs->getDocs();
    $hash->{products} = $docs->getProductDocs();
    $hash->{echecks} = $docs->getEcheckDocs();
    push @{$documentInfo}, $hash;
  }
  
  $self->setResponseCode('200');
  return { 'documentInfo' => $documentInfo };
}

1;
