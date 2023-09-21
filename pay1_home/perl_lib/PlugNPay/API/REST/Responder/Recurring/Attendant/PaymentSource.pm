package PlugNPay::API::REST::Responder::Recurring::Attendant::PaymentSource;

use strict;
use PlugNPay::Recurring::Attendant;
use PlugNPay::Recurring::Attendant::PaymentSource;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  my $resourceData = $self->getResourceData();

  my $merchant = $resourceData->{'merchant'} || $self->getGatewayAccount();

  if(!$merchant || !$resourceData->{'customer'}) {
    $self->setResponseCode(400);
    return {'status' => 'FAILURE', 'message' => 'Insufficient Data sent in request.'};
  }

  my $attendant = new PlugNPay::Recurring::Attendant();

  if(!$attendant->doesCustomerExist($merchant,$resourceData->{'customer'})) {
    $self->setResponseCode(404);
    return {'status' => 'FAILURE', 'message' => 'Customer does not exist.'};
  }

  if ($action eq 'read') {
    return $self->_read();
  } elsif ($action eq 'update') {
    return $self->_update();
  } elsif ($action eq 'delete') {
    return $self->_delete();
  }

  $self->setResponseCode(501);
  return {};
}

sub _read {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $merchant = $resourceData->{'merchant'} || $self->getGatewayAccount();

  my $paymentSource = new PlugNPay::Recurring::Attendant::PaymentSource();
  if ($paymentSource->loadPaymentSource($merchant, $resourceData->{'customer'})) {
    my $paymentSourceData = {
      cardNumber => $paymentSource->getCardNumber(),
      expMonth   => $paymentSource->getExpMonth(),
      expYear    => $paymentSource->getExpYear(),
      type       => $paymentSource->getPaymentSourceType()
    };
    $self->setResponseCode(200);
    return {'status' => 'SUCCESS', 'paymentSource' => [$paymentSourceData]};
  }
  $self->setResponseCode(422);
  return {'status' => 'FAILURE', 'message' => 'Failed to load customer payment source.'};
}

sub _update {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $inputData = $self->getInputData();
  my $merchant = $resourceData->{'merchant'} || $self->getGatewayAccount();

  my $paymentSource = new PlugNPay::Recurring::Attendant::PaymentSource();

  if ($paymentSource->updatePaymentSource($merchant, $resourceData->{'customer'},$inputData)) {
    $self->setResponseCode(200);
    return { 'status' => 'SUCCESS', 'message' => 'Successfully updated payment source information' };
  }

  $self->setResponseCode(422);
  return { 'status' => 'FAILURE', 'message' => 'Failed to update payment source information.' }

}

sub _delete {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $merchant = $resourceData->{'merchant'} || $self->getGatewayAccount();
  my $paymentSource = new PlugNPay::Recurring::Attendant::PaymentSource();

  if ($paymentSource->deletePaymentSource($merchant, $resourceData->{'customer'})) {
    $self->setResponseCode(200);
    return {'status' => 'SUCCESS', 'message' => 'Successfully removed customer payment source.'};
  }

  $self->setResponseCode(422);
  return {'status' => 'FAILURE', 'message' => 'Failed to delete customer payment source.'};

}

1;
