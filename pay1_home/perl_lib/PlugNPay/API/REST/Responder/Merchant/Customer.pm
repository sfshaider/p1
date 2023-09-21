package PlugNPay::API::REST::Responder::Merchant::Customer;

use strict;
use PlugNPay::Merchant::Customer::Link;
use PlugNPay::Merchant::Customer::JSON;
use PlugNPay::GatewayAccount::LinkedAccounts;

use base 'PlugNPay::API::REST::Responder';

# needed for create
sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  # check linked account
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  if ($merchant ne $self->getGatewayAccount()) {
    my $linked = new PlugNPay::GatewayAccount::LinkedAccounts($self->getGatewayAccount())->isLinkedTo($merchant);
    if (!$linked) {
      $self->setResponseCode(403);
      return { 'error' => 'Access Denied' };
    }
  }

  if ($action eq 'read') {
    return $self->_read();
  } elsif ($action eq 'create') {
    return $self->_create();
  } elsif ($action eq 'delete') {
    return $self->_delete();
  } elsif ($action eq 'update') {
    return $self->_update();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _create {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customerData = $self->getInputData();

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link($merchant);
  my $merchCustSaveStatus = $merchantCustomer->saveMerchantCustomer($customerData);
  if (!$merchCustSaveStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $merchCustSaveStatus->getError() };
  }

  my $savedUsername = $merchantCustomer->getUsername();
  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Successfully saved customer.', 'username' => $savedUsername };
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customer = $self->getResourceData()->{'customer'};
  my $options =  $self->getResourceOptions();

  my $count = 0;
  my $customers = [];

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link($merchant);
  if ($customer) {
    $merchantCustomer->loadCustomerIDByUsername($customer);
    if (!$merchantCustomer->getMerchantCustomerLinkID()) {
      $self->setResponseCode(404);
      return { 'status' => 'error', 'message' => 'Customer username not found.' };
    }

    my $customerJSON = new PlugNPay::Merchant::Customer::JSON();
    push (@{$customers}, $customerJSON->customerToJSON($merchantCustomer));
    $count++;
  } else {
    $merchantCustomer->setLimitData({ 'limit' => $options->{'pageLength'}, 'offset' => $options->{'page'} * $options->{'pageLength'} });

    my $customerList = $merchantCustomer->loadMerchantCustomers();
    if (@{$customerList} > 0) {
      my $customerJSON = new PlugNPay::Merchant::Customer::JSON();
      foreach my $customer (@{$customerList}) {
        push (@{$customers}, $customerJSON->customerToJSON($customer, 0));
      }
    }

    $count = $merchantCustomer->getMerchantCustomerListSize();
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'count' => $count, 'customers' => $customers};
}

sub _update {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customer = $self->getResourceData()->{'customer'};
  my $updateData = $self->getInputData();

  if (!$customer) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No customer specified' };
  }

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link($merchant);
  $merchantCustomer->loadCustomerIDByUsername($customer);
  if (!$merchantCustomer->getMerchantCustomerLinkID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Customer username not found.' };
  }

  my $updateStatus = $merchantCustomer->updateMerchantCustomer($updateData);
  if (!$updateStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Failed to update customer. ' . $updateStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => ' success', 'message' => 'Customer successfully updated' };
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customer = $self->getResourceData()->{'customer'};

  if (!$customer) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No customer specified' };
  }

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link($merchant);
  $merchantCustomer->loadCustomerIDByUsername($customer);
  if (!$merchantCustomer->getMerchantCustomerLinkID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Customer username not found.' };
  }

  my $deleteStatus = $merchantCustomer->removeMerchantCustomer();
  if (!$deleteStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deleteStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => ' success', 'message' => 'Customer successfully removed' };
}

1;
