package PlugNPay::API::REST::Responder::Merchant::Recurring::Password;

use strict;
use warnings;
use PlugNPay::Logging::DataLog;
use PlugNPay::Recurring::Profile;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  if ($action eq 'update') {
    return $self->_update();
  } else {
     $self->setResponseCode(501);
     return {};
  }
}

sub _update {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customer = $self->getResourceData()->{'customer'};
  my $inputData = $self->getInputData();

  my $profile = new PlugNPay::Recurring::Profile({'merchant' => $merchant, 'customer' => $customer});
  my $password = $inputData->{'password'};
  $profile->setPassword($password);

  my $passwordStatus = $profile->savePassword();
  if (!$passwordStatus->{'status'}) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $passwordStatus->{'errorMessage'} };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'password saved succesfully' };
}

1;
