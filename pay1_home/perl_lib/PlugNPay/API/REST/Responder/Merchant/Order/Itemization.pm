package PlugNPay::API::REST::Responder::Merchant::Order::Itemization;

use strict;
use PlugNPay::Order::Loader;
use PlugNPay::Order::JSON;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  my $data;

  if ($action eq 'read') {
    $data = $self->_read();
  } else {
    $self->setResponseCode(501);
  }

  return $data;
}

# Load Items #
sub _read {
  my $self = shift;
  my $merchantOrderID = $self->getResourceData()->{'order'};
  my $gatewayAccount = $self->getResourceData()->{'merchant'};
  my $response = {};

  if (!defined $gatewayAccount) {
    $gatewayAccount = $self->getGatewayAccount();
  }

  my $loader = new PlugNPay::Order::Loader();
  my $converter = new PlugNPay::Order::JSON();
  my $items;
  eval {
    $items = $loader->loadDetailsByMerchant($merchantOrderID, $gatewayAccount);
  };

  if ($@) {
    $response = {'status' => 'failure', 'message' => 'failed to load itemization'};
    $self->setResponseCode(520);
  } else {
    $response = {items => $converter->itemizationToJSON($items), 'status' => 'success', 'message' => 'successfully loaded itemization data'};
    $self->setResponseCode(200);
  }

  return $response;
}

1;
