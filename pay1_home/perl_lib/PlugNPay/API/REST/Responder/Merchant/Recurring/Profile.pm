package PlugNPay::API::REST::Responder::Merchant::Recurring::Profile;

use strict;
use PlugNPay::Recurring::Profile;
use PlugNPay::Recurring::Attendant;
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
        return {'status' => 'failure', 'message' => 'Access Denied'};
      }
    }
  }

  if ($action eq 'read') {
    $self->_read();
  } elsif ($action eq 'update' || $action eq 'create') {
    $self->_update();
  } elsif ($action eq 'delete') {
    $self->_delete();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customer = $self->getResourceData()->{'customer'};

  my $attendant = new PlugNPay::Recurring::Attendant();
  if (!$attendant->doesCustomerExist($merchant, $customer)) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Customer does not exist.' };
  }

  my $profiles = [];
  my $profile = new PlugNPay::Recurring::Profile();
  if (!$profile->load($merchant, $customer)) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Failed to load profile.' };
  }

  push (@{$profiles}, {
    'username'           => $profile->getUsername(),
    'name'               => $profile->getName(),
    'email'              => $profile->getEmail(),
    'company'            => $profile->getCompany(),
    'address1'           => $profile->getAddress1(),
    'address2'           => $profile->getAddress2(),
    'city'               => $profile->getCity(),
    'state'              => $profile->getState(),
    'postalCode'         => $profile->getPostalCode(),
    'country'            => $profile->getCountry(),
    'shippingName'       => $profile->getShippingName(),
    'shippingAddress1'   => $profile->getShippingAddress1(),
    'shippingAddress2'   => $profile->getShippingAddress2(),
    'shippingCity'       => $profile->getShippingCity(),
    'shippingState'      => $profile->getShippingState(),
    'shippingPostalCode' => $profile->getShippingPostalCode(),
    'shippingCountry'    => $profile->getShippingCountry(),
    'phone'              => $profile->getPhone(),
    'fax'                => $profile->getFax(),
    'status'             => $profile->getStatus(),
    'recurringFee'       => $profile->getRecurringFee(),
    'startDate'          => $profile->getStartDate(),
    'endDate'            => $profile->getEndDate(),
    'balance'            => $profile->getBalance(),
    'billCycle'          => $profile->getBillCycle(),
    'accountCode'        => $profile->getAccountCode(),
    'acctCode'           => $profile->getAccountCode()
  });

  $self->setWarning('Field "acctCode" is deprecated, please use "accountCode" instead.');
  $self->setResponseCode(200);
  return { 'status' => 'success', 'profile' => $profiles };
}

sub _update {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customer = $self->getResourceData()->{'customer'};
  my $inputData = $self->getInputData();

  my $profile = new PlugNPay::Recurring::Profile({merchant => $merchant, customer => $customer});
  $profile->setName($inputData->{'name'});
  $profile->setAddress1($inputData->{'address1'});
  $profile->setAddress2($inputData->{'address2'});
  $profile->setCity($inputData->{'city'});
  $profile->setState($inputData->{'state'});
  $profile->setPostalCode($inputData->{'postalCode'});
  $profile->setCountry($inputData->{'country'});
  $profile->setCompany($inputData->{'company'});
  $profile->setShippingName($inputData->{'shippingName'});
  $profile->setShippingAddress1($inputData->{'shippingAddress1'});
  $profile->setShippingAddress2($inputData->{'shippingAddress2'});
  $profile->setShippingCity($inputData->{'shippingCity'});
  $profile->setShippingState($inputData->{'shippingState'});
  $profile->setShippingPostalCode($inputData->{'shippingPostalCode'});
  $profile->setShippingCountry($inputData->{'shippingCountry'});
  $profile->setEmail($inputData->{'email'});
  $profile->setPhone($inputData->{'phone'});
  $profile->setFax($inputData->{'fax'});
  $profile->setStatus($inputData->{'status'});

  my $accountCode = $inputData->{'accountCode'};
  if (!defined $accountCode && exists $inputData->{'acctCode'}) {
    $accountCode = $inputData->{'acctCode'};
    $self->setWarning('Field "acctCode" is deprecated, please use "accountCode" instead.');
  }
  $profile->setAccountCode($accountCode);

  ############################################
  # Customer unable to update recurring data #
  ############################################
  if ($self->getContext() ne 'attendant') {
    $profile->setRecurringFee($inputData->{'recurringFee'});
    $profile->setStartDate($inputData->{'startDate'});
    $profile->setEndDate($inputData->{'endDate'});
    $profile->setBalance($inputData->{'balance'});
    $profile->setBillCycle($inputData->{'billCycle'});
  }

  my $updateStatus = $profile->save();
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

  my $profile = new PlugNPay::Recurring::Profile();
  my $deleteStatus = $profile->deleteProfile($customer, $merchant);
  if (!$deleteStatus->{'status'}) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deleteStatus->{'errorMessage'} };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Deleted profile successfully.' };
}

1;
