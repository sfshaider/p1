package PlugNPay::API::REST::Responder::Recurring::Attendant::BillMember;

use strict;
use PlugNPay::Recurring::Attendant;
use PlugNPay::Recurring::Attendant::BillMember;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  if ($action eq 'create') {
    $self->_create();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _create {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customer = $self->getResourceData()->{'customer'};
  my $inputData = $self->getInputData();

  my $saveProfile = 0;
  my $savePaymentSource = 0;

  if ($inputData->{'saveProfile'} || $inputData->{'savePaymentSource'}) {
    $saveProfile = 1;

    if ($inputData->{'savePaymentSource'}) {
      $savePaymentSource = 1;
    }
  }

  my $biller = new PlugNPay::Recurring::Attendant::BillMember();
  my $billStatus = $biller->billMember($customer, $merchant, $inputData, $saveProfile, $savePaymentSource);
  if (!$billStatus->{'status'}) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $billStatus->{'errorMessage'} };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Successfully billed member.' };
}

1;
