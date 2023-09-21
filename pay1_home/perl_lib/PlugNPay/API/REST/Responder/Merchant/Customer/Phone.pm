package PlugNPay::API::REST::Responder::Merchant::Customer::Phone;

use strict;
use PlugNPay::Merchant::Customer::Phone;
use PlugNPay::Merchant::Customer::Phone::JSON;
use PlugNPay::Merchant::Customer::Phone::Expose;

use base 'PlugNPay::API::REST::Responder::Abstract::Merchant::Customer';

sub _create {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $inputData = $self->getInputData();

  my $exposePhone = new PlugNPay::Merchant::Customer::Phone::Expose();
  my $exposeStatus = $exposePhone->saveExposedPhone($inputData,
                                                    $merchantCustomer->getMerchantCustomerLinkID(),
                                                    { 'makeDefault' => $inputData->{'makeDefault'} });
  if (!$exposeStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $exposeStatus->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Successfully saved phone.' };
}

sub _read {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $phoneIdentifier = $self->getResourceData()->{'phone'};
  my $options = $self->getResourceOptions();

  my $count = 0;
  my $phones = [];

  my $exposePhone = new PlugNPay::Merchant::Customer::Phone::Expose();
  if ($phoneIdentifier) {
    $exposePhone->loadByLinkIdentifier($phoneIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
    if (!$exposePhone->getLinkID()) {
      $self->setResponseCode(404);
      return { 'status' => 'error', 'message' => 'Phone identifier does not exist.' };
    }

    my $phone = new PlugNPay::Merchant::Customer::Phone();
    $phone->loadPhone($exposePhone->getPhoneID());
    $phone->setIdentifier($phoneIdentifier);

    my $phoneJSON = new PlugNPay::Merchant::Customer::Phone::JSON();
    push (@{$phones}, $phoneJSON->phoneToJSON($phone));
    $count++;
  } else {
    $exposePhone->setLimitData({ 'limit' => $options->{'pageLength'}, 'offset' => $options->{'page'} * $options->{'pageLength'} });

    my $phoneList = $exposePhone->loadExposedPhones($merchantCustomer->getMerchantCustomerLinkID());
    if (@{$phoneList} > 0) {
      my $phoneJSON = new PlugNPay::Merchant::Customer::Phone::JSON();
      foreach my $customerPhone (@{$phoneList}) {
        my $phone = new PlugNPay::Merchant::Customer::Phone();
        $phone->loadPhone($customerPhone->getPhoneID());
        $phone->setIdentifier($customerPhone->getIdentifier());
        push (@{$phones}, $phoneJSON->phoneToJSON($phone));
      }
    }

    $count = $exposePhone->getPhoneListSize($merchantCustomer->getMerchantCustomerLinkID());
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'count' => $count, 'phones' => $phones };
}

sub _update {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $phoneIdentifier = $self->getResourceData()->{'phone'};
  my $inputData = $self->getInputData();

  if (!$phoneIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No phone identifier specified.' };
  }

  my $exposePhone = new PlugNPay::Merchant::Customer::Phone::Expose();
  $exposePhone->loadByLinkIdentifier($phoneIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
  if (!$exposePhone->getLinkID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Phone identifier does not exist.' };
  }

  my $updateExposeStatus = $exposePhone->updateExposedPhone($inputData);
  if (!$updateExposeStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updateExposeStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully updated phone.' };
}

sub _delete {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $phoneIdentifier = $self->getResourceData()->{'phone'};

  if (!$phoneIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No phone identifier specified.' };
  }

  my $exposePhone = new PlugNPay::Merchant::Customer::Phone::Expose();
  $exposePhone->loadByLinkIdentifier($phoneIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
  my $deletePhoneStatus = $exposePhone->deleteExposedPhone();
  if (!$deletePhoneStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deletePhoneStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Phone successfully deleted.' };
}

1;
