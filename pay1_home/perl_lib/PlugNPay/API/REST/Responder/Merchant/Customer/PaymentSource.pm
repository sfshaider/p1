package PlugNPay::API::REST::Responder::Merchant::Customer::PaymentSource;

use strict;
use PlugNPay::Merchant::Customer::PaymentSource;
use PlugNPay::Merchant::Customer::PaymentSource::JSON;
use PlugNPay::Merchant::Customer::PaymentSource::Expose;

use base 'PlugNPay::API::REST::Responder::Abstract::Merchant::Customer';

sub _create {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $inputData = $self->getInputData();

  my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
  $exposePaymentSource->setBillingAccount($self->getMerchant());
  my $saveExposeStatus = $exposePaymentSource->saveExposedPaymentSource($inputData, $merchantCustomer->getMerchantCustomerLinkID());
  if (!$saveExposeStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $saveExposeStatus->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Successfully saved payment source.' };
}

sub _read {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $paymentSourceIdentifier = $self->getResourceData()->{'paymentsource'};
  my $options = $self->getResourceOptions();

  my $count = 0;
  my $paymentSources = [];

  my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
  if ($paymentSourceIdentifier) {
    $exposePaymentSource->loadByLinkIdentifier($paymentSourceIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
    if (!$exposePaymentSource->getLinkID()) {
      $self->setResponseCode(404);
      return { 'status' => 'error', 'message' => 'Payment source identifier does not exist.' };
    }

    my $paymentSource = new PlugNPay::Merchant::Customer::PaymentSource();
    $paymentSource->loadPaymentSource($exposePaymentSource->getPaymentSourceID());
    $paymentSource->setIdentifier($paymentSourceIdentifier);

    my $paymentSourceJSON = new PlugNPay::Merchant::Customer::PaymentSource::JSON();
    push (@{$paymentSources}, $paymentSourceJSON->paymentSourceToJSON($paymentSource));
    $count++;
  } else {
    $exposePaymentSource->setLimitData({ 'limit' => $options->{'pageLength'}, 'offset' => $options->{'page'} * $options->{'pageLength'} });

    my $paymentSourceList = $exposePaymentSource->loadExposedPaymentSources($merchantCustomer->getMerchantCustomerLinkID());
    if (@{$paymentSourceList} > 0) {
      my $paymentSourceJSON = new PlugNPay::Merchant::Customer::PaymentSource::JSON();
      foreach my $customerPaymentSource (@{$paymentSourceList}) {
        my $paymentSource = new PlugNPay::Merchant::Customer::PaymentSource();
        $paymentSource->loadPaymentSource($customerPaymentSource->getPaymentSourceID());
        $paymentSource->setIdentifier($customerPaymentSource->getIdentifier());
        push (@{$paymentSources}, $paymentSourceJSON->paymentSourceToJSON($paymentSource));
      }
    }

    $count = $exposePaymentSource->getPaymentSourceListSize($merchantCustomer->getMerchantCustomerLinkID());
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'count' => $count, 'paymentsources' => $paymentSources };
}

sub _update {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $paymentSourceIdentifier = $self->getResourceData()->{'paymentsource'};
  my $inputData = $self->getInputData();

  if (!$paymentSourceIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No payment source identifier specified.' };
  }

  # check if the payment source identifier exists
  my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
  $exposePaymentSource->loadByLinkIdentifier($paymentSourceIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
  if (!$exposePaymentSource->getLinkID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Payment source identifier does not exist.' };
  }

  $exposePaymentSource->setBillingAccount($self->getMerchant());
  my $updateExposeStatus = $exposePaymentSource->updateExposedPaymentSource($inputData);
  if (!$updateExposeStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updateExposeStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully updated payment source.' };
}

sub _delete {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $paymentSourceIdentifier = $self->getResourceData()->{'paymentsource'};

  if (!$paymentSourceIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No payment source identifier specified.' };
  }

  my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
  $exposePaymentSource->loadByLinkIdentifier($paymentSourceIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
  my $deletePaymentSourceStatus = $exposePaymentSource->deleteExposedPaymentSource();
  if (!$deletePaymentSourceStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deletePaymentSourceStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Payment source successfully deleted.' };
}

1;
