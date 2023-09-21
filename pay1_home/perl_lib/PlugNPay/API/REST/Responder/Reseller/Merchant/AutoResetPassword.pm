package PlugNPay::API::REST::Responder::Reseller::Merchant::AutoResetPassword;

use base 'PlugNPay::API::REST::Responder';

use strict;
use PlugNPay::Password::Reset;
use PlugNPay::Reseller::Chain;
use PlugNPay::GatewayAccount;

sub _getOutputData {
  my $self = shift;

  my $action = $self->getAction();
  my $merchant = $self->getResourceData()->{'merchant'};
  my $ga = new PlugNPay::GatewayAccount($merchant);
  my $reseller = $self->getGatewayAccount();
  my $chain = new PlugNPay::Reseller::Chain($reseller);

  if ($reseller eq $ga->getReseller() || $chain->hasDescendant($ga->getReseller())) {
    if ($action eq 'read') {
      return $self->_get($merchant);
    }
    elsif ($action eq 'update') {
      return $self->_update($merchant);
    }
    else {
      $self->setResponseCode(501);
      return {};
    }
  }
  else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _get {
  my $self = shift;
  my $merchant = shift;

  my $passwordReset = new PlugNPay::Password::Reset();
  my $emailAddress = $passwordReset->getAutoResetPasswordEmail($merchant);

  $self->setResponseCode(200);
  return {'email' => $emailAddress};
}

sub _update {
  my $self = shift;
  my $merchant = shift;

  my $passwordReset = new PlugNPay::Password::Reset();
  $passwordReset->autoResetPassword($merchant);

  $self->setResponseCode(200);
  return {'message' => 'Password reset successfully'};
}

1;


