package PlugNPay::API::REST::Responder::Merchant::Masterpass;

use strict;
use PlugNPay::Client::Masterpass;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift; 
  my $action = $self->getAction();
  my $data = {};

  if ($action eq 'read') {
    $data = $self->_read();
  } else {
    $self->setResponseCode('404');
  }

  return $data;
}

sub _read {
  my $self = shift;
  my $username = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();

  my $masterpass = new PlugNPay::Client::Masterpass();
  my $token = $masterpass->getRequestTokenFromProcessor();
  my $callback = $masterpass->getCallbackURL();
  my $checkoutID = $masterpass->getCheckoutIDFromUsername($username);
  $self->setResponseCode(200);
  return {'request_token' => $token,
          'callback_url' => $callback,
          'checkout_id' => $checkoutID };
}

1;

