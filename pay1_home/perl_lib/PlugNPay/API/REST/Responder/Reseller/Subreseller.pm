package PlugNPay::API::REST::Responder::Reseller::Subreseller;

use strict;
use PlugNPay::Reseller;
use PlugNPay::Reseller::Chain;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;

  my $reseller = $self->getResourceData()->{'reseller'};

  my $chain = new PlugNPay::Reseller::Chain();
  $chain->setReseller($self->getGatewayAccount());

  my $subresellersInfo = [];
  # verify that submitted reseller is either the logged in account or a subreseller thereof
  if ($chain->hasDescendant($reseller) || $reseller eq $self->getGatewayAccount()) {
    my $subresellerChain = new PlugNPay::Reseller::Chain();
    $subresellerChain->setReseller($reseller);
    my $subresellers = $subresellerChain->getChildren();
    my $subresellersHash = PlugNPay::Reseller::infoList($subresellers);
    foreach my $subreseller (sort keys %{$subresellersHash}) {
	my %subresellerData;
        $subresellerData{'username'} = $subreseller;
        $subresellerData{'company'} = $subresellersHash->{$subreseller}{'name'};
        $subresellerData{'status'} = $subresellersHash->{$subreseller}{'status'};
	push @{$subresellersInfo},\%subresellerData;
    }
    $self->setResponseCode(200);
  } else {
    $self->setResponseCode(403);
  }
  
  return { 'subresellerInfo' => $subresellersInfo };
}

1;

