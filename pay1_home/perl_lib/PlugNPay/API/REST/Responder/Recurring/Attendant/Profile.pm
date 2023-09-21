package PlugNPay::API::REST::Responder::Recurring::Attendant::Profile;

use strict;
use PlugNPay::Recurring::Attendant;
use PlugNPay::Recurring::Attendant::Profile;
use PlugNPay::GatewayAccount::LinkedAccounts;
use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  my $merchant = $self->getResourceData()->{'merchant'};
  if (!$merchant) {
    $merchant = $self->getGatewayAccount();
  } else {
    if ($merchant ne $self->getGatewayAccount()) {
      my $linked = new PlugNPay::GatewayAccount::LinkedAccounts($merchant)->isLinkedTo($self->getGatewayAccount());
      if (!$linked) {
        $self->setResponseCode(403);
        return {'status' => 'ERROR', 'message' => 'Access Denied'};
      }
    }
  }

  if ($action eq 'read') {
    $self->_read();
  } elsif ($action eq 'update') {
    $self->_update();
  } elsif ($action eq 'delete') {
    $self->_delete();
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

  my $attendant = new PlugNPay::Recurring::Attendant();
  if (!$attendant->doesCustomerExist($merchant, $customer)) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Customer already exists.' };
  }

  my $profile = new PlugNPay::Recurring::Attendant::Profile();
  my $saveStatus = $profile->saveProfile($inputData, $customer, $merchant);
  if (!$saveStatus->{'status'}) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $saveStatus->{'errorMessage'} };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Saved profile successfully.' };
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customer = $self->getResourceData()->{'customer'};

  my $attendant = new PlugNPay::Recurring::Attendant();
  if (!$attendant->doesCustomerExist($merchant, $customer)) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Customer does not exist.' };
  }

  my $profiles = [];
  my $profile = new PlugNPay::Recurring::Attendant::Profile();
  if (!$profile->loadProfile($customer, $merchant)) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Failed to load profile.' };
  }

  push (@{$profiles}, {
    'username'        => $profile->getUsername(),
    'name'            => $profile->getName(),
    'email'           => $profile->getEmail(),
    'company'         => $profile->getCompany(),
    'addr1'           => $profile->getAddr1(),
    'addr2'           => $profile->getAddr2(),
    'city'            => $profile->getCity(),
    'state'           => $profile->getState(),
    'zip'             => $profile->getZip(),
    'country'         => $profile->getCountry(),
    'shippingName'    => $profile->getShippingName(),
    'shippingAddr1'   => $profile->getShippingAddr1(),
    'shippingAddr2'   => $profile->getShippingAddr2(),
    'shippingCity'    => $profile->getShippingCity(),
    'shippingState'   => $profile->getShippingState(),
    'shippingZip'     => $profile->getShippingZip(),
    'shippingCountry' => $profile->getShippingCountry(),
    'phone'           => $profile->getPhone(),
    'fax'             => $profile->getFax(),
    'status'          => $profile->getStatus(),
    'recurringFee'    => $profile->getMonthly(),
    'startDate'       => $profile->getStartDate(),
    'endDate'         => $profile->getEndDate(),
    'balance'         => $profile->getBalance(),
    'billCycle'       => $profile->getBillCycle()
  });

  $self->setResponseCode(200);
  return { 'status' => 'success', 'profile' => $profiles };
}

sub _update {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customer = $self->getResourceData()->{'customer'};
  my $inputData = $self->getInputData();

  my $attendant = new PlugNPay::Recurring::Attendant();
  if (!$attendant->doesCustomerExist($merchant, $customer)) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Customer does not exist.' };
  }

  my $profile = new PlugNPay::Recurring::Attendant::Profile();
  my $updateStatus = $profile->updateProfile($inputData, $customer, $merchant);
  if (!$updateStatus->{'status'}) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updateStatus->{'errorMessage'} };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Update profile successfully.' };
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customer = $self->getResourceData()->{'customer'};

  my $attendant = new PlugNPay::Recurring::Attendant();
  if (!$attendant->doesCustomerExist($merchant, $customer)) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Customer does not exist.' };
  }

  my $profile = new PlugNPay::Recurring::Attendant::Profile();
  my $deleteStatus = $profile->deleteProfile($customer, $merchant);
  if (!$deleteStatus->{'status'}) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deleteStatus->{'errorMessage'} };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Deleted profile successfully.' };
}

1;
