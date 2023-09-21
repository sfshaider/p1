package PlugNPay::API::REST::Responder::Reseller::Merchant::Password;

use strict;
use PlugNPay::GatewayAccount;
use PlugNPay::Reseller::Chain;
use PlugNPay::Password::Reset;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData{
  my $self = shift;
  my $ga = new PlugNPay::GatewayAccount($self->getResourceData()->{'merchant'});
  my $chain = new PlugNPay::Reseller::Chain($self->getGatewayAccount());
  my $action = $self->getAction();
  my $reseller = $self->getGatewayAccount();

  if ($action eq 'update' && ($reseller eq $ga->getReseller() || $chain->hasDescendant($ga->getReseller()))) {
    return $self->_update();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _update {
  my $self = shift;
  my $resetter = new PlugNPay::Password::Reset();
  my $env = new PlugNPay::Environment();
  eval {
    $resetter->sendResetConfirmation({
      loginUsername => $self->getResourceData()->{'merchant'},
      ip => $env->get('PNP_CLIENT_IP')
    });
    $self->setResponseCode(200);
  };

  if($@) {
    $self->setResponseCode(520);
    $self->setError('An error occured while resetting merchant password');
    return {};
  }

  return {'status' => 'success', 'message' => 'password was reset'};
}

1;
