package PlugNPay::API::REST::Responder::Username;

use strict;
use PlugNPay::Username;
use PlugNPay::GatewayAccount;
use base "PlugNPay::API::REST::Responder";

sub _getOutputData{
  my $self = shift;
  
  my $username = $self->getResourceData()->{'username'};
  my $response = 'false';

  if (PlugNPay::GatewayAccount::exists($username)){  
    $response = 'true';
  }

  my $user = new PlugNPay::Username($self->getGatewayAccount());

  if ($user->exists($username)){
    $response = 'true';
  }

  $self->setResponseCode('200');

  return {'exists' => $response};
  
}

1;
