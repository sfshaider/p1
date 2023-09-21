package PlugNPay::API::REST::Responder::Merchant::Customer::Address;

use strict;
use PlugNPay::Merchant::Customer::Address;
use PlugNPay::Merchant::Customer::Address::JSON;
use PlugNPay::Merchant::Customer::Address::Expose;

use base 'PlugNPay::API::REST::Responder::Abstract::Merchant::Customer';

sub _create {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $inputData = $self->getInputData();

  my $expose = new PlugNPay::Merchant::Customer::Address::Expose();
  my $exposeStatus = $expose->saveExposedAddress($inputData,
                                                 $merchantCustomer->getMerchantCustomerLinkID(),
                                                 { 'makeDefault' => $inputData->{'makeDefault'} });
  if (!$exposeStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $exposeStatus->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Successfully saved address.' };
}

sub _read {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $addressIdentifier = $self->getResourceData()->{'address'};
  my $options = $self->getResourceOptions();

  my $count = 0;
  my $addresses = [];

  my $exposeAddress = new PlugNPay::Merchant::Customer::Address::Expose();
  if ($addressIdentifier) {
    $exposeAddress->loadByLinkIdentifier($addressIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
    if (!$exposeAddress->getLinkID()) {
      $self->setResponseCode(404);
      return { 'status' => 'error', 'message' => 'Address identifier does not exist.' };
    }

    my $address = new PlugNPay::Merchant::Customer::Address();
    $address->loadAddress($exposeAddress->getAddressID());
    $address->setIdentifier($addressIdentifier);

    my $addressJSON = new PlugNPay::Merchant::Customer::Address::JSON();
    push (@{$addresses}, $addressJSON->addressToJSON($address));
    $count++;
  } else {
    $exposeAddress->setLimitData({ 'limit' => $options->{'pageLength'}, 'offset' => $options->{'page'} * $options->{'pageLength'} });

    my $addressList = $exposeAddress->loadExposedAddresses($merchantCustomer->getMerchantCustomerLinkID());
    if (@{$addressList} > 0) {
      my $addressJSON = new PlugNPay::Merchant::Customer::Address::JSON();
      foreach my $customerAddress (@{$addressList}) {
        my $address = new PlugNPay::Merchant::Customer::Address();
        $address->loadAddress($customerAddress->getAddressID());
        $address->setIdentifier($customerAddress->getIdentifier());
        push (@{$addresses}, $addressJSON->addressToJSON($address));
      }
    }

    $count = $exposeAddress->getAddressListSize($merchantCustomer->getMerchantCustomerLinkID());
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'count' => $count, 'addresses' => $addresses };
}

sub _update {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $addressIdentifier = $self->getResourceData()->{'address'};
  my $inputData = $self->getInputData();

  my $exposeAddress = new PlugNPay::Merchant::Customer::Address::Expose();
  if (!$addressIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No address identifier specified.' };
  }

  $exposeAddress->loadByLinkIdentifier($addressIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
  if (!$exposeAddress->getLinkID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Address identifier does not exist.' };
  }

  my $updateExposeStatus = $exposeAddress->updateExposedAddress($inputData);
  if (!$updateExposeStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updateExposeStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Updated address successfully.' };
}

sub _delete {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $addressIdentifier = $self->getResourceData()->{'address'};

  my $exposeAddress = new PlugNPay::Merchant::Customer::Address::Expose();
  if (!$addressIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No address identifier specified.' };
  }

  $exposeAddress->loadByLinkIdentifier($addressIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
  my $deleteAddressStatus = $exposeAddress->deleteExposedAddress();
  if (!$deleteAddressStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deleteAddressStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Address successfully deleted.' };
}

1;
