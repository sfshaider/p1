package PlugNPay::API::REST::Responder::Merchant::Customer::FuturePayment;

use strict;
use PlugNPay::Merchant::Customer::FuturePayment;
use PlugNPay::Merchant::Customer::FuturePayment::JSON;

use base 'PlugNPay::API::REST::Responder::Abstract::Merchant::Customer';

sub _create {
  my $self = shift;
  my $merchant = $self->getMerchant();
  my $merchantCustomer = $self->getMerchantCustomer();

  my $inputData = $self->getInputData();
  my $paymentDate = $inputData->{'paymentDate'};
  $paymentDate =~ s/[^0-9]//g;

  my $paymentInfo = {
    'amount'                   => $inputData->{'amount'},
    'description'              => $inputData->{'description'},
    'paymentDate'              => $paymentDate,
    'paymentSourceIdentifier'  => $inputData->{'paymentSourceID'},
    'billingProfileIdentifier' => $inputData->{'billingProfileID'},
    'transactionType'          => $inputData->{'operation'},
    'billingAccount'           => $merchant
  };

  my $futurePayment = new PlugNPay::Merchant::Customer::FuturePayment();
  my $saveFuturePayment = $futurePayment->scheduleFuturePayment($merchantCustomer->getMerchantCustomerLinkID(), $paymentInfo);
  if (!$saveFuturePayment) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $saveFuturePayment->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully scheduled future payment' };
}

sub _read {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $futurePaymentIdentifier = $self->getResourceData()->{'futurepayment'};
  my $options = $self->getResourceOptions();

  my $count = 0;
  my $futurePayments = [];

  my $futurePayment = new PlugNPay::Merchant::Customer::FuturePayment();
  if ($futurePaymentIdentifier) {
    $futurePayment->loadByFuturePaymentIdentifier($futurePaymentIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
    if (!$futurePayment->getFuturePaymentID()) {
      $self->setResponseCode(404);
      return { 'status' => 'error', 'message' => 'Future payment identifier not found.' };
    }

    my $futurePaymentJSON = new PlugNPay::Merchant::Customer::FuturePayment::JSON();
    push (@{$futurePayments}, $futurePaymentJSON->futurePaymentToJSON($futurePayment));
    $count++;
  } else {
    $futurePayment->setLimitData({ 'limit' => $options->{'pageLength'}, 'offset' => $options->{'page'} * $options->{'pageLength'} });

    my $futurePaymentList = $futurePayment->loadCustomerFuturePayments($merchantCustomer->getMerchantCustomerLinkID());
    if (@{$futurePaymentList} > 0) {
      my $futurePaymentJSON = new PlugNPay::Merchant::Customer::FuturePayment::JSON();
      foreach my $futurePayment (@{$futurePaymentList}) {
        push (@{$futurePayments}, $futurePaymentJSON->futurePaymentToJSON($futurePayment));
      }
    }

    $count = $futurePayment->getFuturePaymentListSize($merchantCustomer->getMerchantCustomerLinkID());
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'count' => $count, 'payments' => $futurePayments };
}

sub _update {
  my $self = shift;
  my $merchant = $self->getMerchant();
  my $merchantCustomer = $self->getMerchantCustomer();

  my $futurePaymentIdentifier = $self->getResourceData()->{'futurepayment'};
  my $inputData = $self->getInputData();

  if (!$futurePaymentIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Unspecified future payment id.' };
  }

  my $futurePayment = new PlugNPay::Merchant::Customer::FuturePayment();
  $futurePayment->loadByFuturePaymentIdentifier($futurePaymentIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
  if (!$futurePayment->getFuturePaymentID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Future payment identifier not found.' };
  }

  my $paymentDate = $inputData->{'paymentDate'};
  $paymentDate =~ s/[^0-9]//g;

  my $paymentInfo = {
    'amount'                   => $inputData->{'amount'},
    'paymentDate'              => $paymentDate,
    'transactionType'          => $inputData->{'operation'},
    'description'              => $inputData->{'description'},
    'paymentSourceIdentifier'  => $inputData->{'paymentSourceID'},
    'billingProfileIdentifier' => $inputData->{'billingProfileID'},
    'billingAccount'           => $merchant
  };

  my $updateFuturePayment = $futurePayment->updatePendingFuturePayment($paymentInfo);
  if (!$updateFuturePayment) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updateFuturePayment->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully updated future payment' };
}

sub _delete {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $futurePaymentIdentifier = $self->getResourceData()->{'futurepayment'};

  if (!$futurePaymentIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Unspecified future payment id.' };
  }

  my $futurePayment = new PlugNPay::Merchant::Customer::FuturePayment();
  $futurePayment->loadByFuturePaymentIdentifier($futurePaymentIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
  my $deleteStatus = $futurePayment->removeFuturePayment();
  if (!$deleteStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deleteStatus->getError() };
  }
 
  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully deleted future payment.' };
}

1;
