package PlugNPay::API::REST::Responder::Merchant::Membership::Profile;

use strict;
use PlugNPay::Membership::Profile;
use PlugNPay::Membership::Profile::JSON;

use base 'PlugNPay::API::REST::Responder::Abstract::Merchant::Customer';

sub _create {
  my $self = shift;
  my $merchant = $self->getMerchant();
  my $merchantCustomer = $self->getMerchantCustomer();
  my $inputData = $self->getInputData();

  my $profile = new PlugNPay::Membership::Profile($merchant);
  my $saveProfileResponse = $profile->saveBillingProfile($merchantCustomer->getMerchantCustomerLinkID(), $inputData);
  my $saveProfileStatus = $saveProfileResponse->{'status'};
  if (!$saveProfileStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $saveProfileStatus->getError() };
  }

  my $response = { 'status' => 'success', 'message' => 'Saved profile successfully.' };
  if (exists $saveProfileResponse->{'transaction'}) {
    $response->{'transaction'} = $saveProfileResponse->{'transaction'};
  }

  $self->setResponseCode(201);
  return $response;
}

sub _read {
  my $self = shift;
  my $merchant = $self->getMerchant();
  my $merchantCustomer = $self->getMerchantCustomer();
  my $profileIdentifier = $self->getResourceData()->{'profile'}; 
  my $options = $self->getResourceOptions();
 
  my $count = 0;
  my $billingProfiles = [];

  my $profile = new PlugNPay::Membership::Profile($merchant);
  if ($profileIdentifier) {
    $profile->loadByBillingProfileIdentifier($profileIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
    if (!$profile->getBillingProfileID()) {
      $self->setResponseCode(404);
      return { 'status' => 'error', 'message' => 'Billing profile identifier not found.' };
    }

    my $json = new PlugNPay::Membership::Profile::JSON();
    push (@{$billingProfiles}, $json->profileToJSON($profile));
    $count++;
  } else {
    my $customerBillingProfiles = $profile->loadBillingProfiles($merchantCustomer->getMerchantCustomerLinkID());
    if (@{$customerBillingProfiles} > 0) {
      my $json = new PlugNPay::Membership::Profile::JSON();
      foreach my $customerBillingProfile (@{$customerBillingProfiles}) {
        push (@{$billingProfiles}, $json->profileToJSON($customerBillingProfile));
        $count++;
      }
    }
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'profiles' => $billingProfiles, 'count' => $count };
}

sub _update {
  my $self = shift;
  my $merchant = $self->getMerchant();
  my $merchantCustomer = $self->getMerchantCustomer();
  my $profileIdentifier = $self->getResourceData()->{'profile'};
  my $inputData = $self->getInputData();

  my $profile = new PlugNPay::Membership::Profile($merchant);
  $profile->loadByBillingProfileIdentifier($profileIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
  if (!$profile->getBillingProfileID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Billing profile identifier not found.' };
  }

  my $updateProfileStatus = $profile->updateBillingProfile($inputData);
  if (!$updateProfileStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updateProfileStatus->getError() };
  }
 
  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Updated profile successfully.' };
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getMerchant();
  my $merchantCustomer = $self->getMerchantCustomer();
  my $profileIdentifier = $self->getResourceData()->{'profile'};

  my $profile = new PlugNPay::Membership::Profile($merchant);
  $profile->loadByBillingProfileIdentifier($profileIdentifier, $merchantCustomer->getMerchantCustomerLinkID());
  my $deleteProfileStatus = $profile->deleteBillingProfile();
  if (!$deleteProfileStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deleteProfileStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Billing profile deleted successfully.' };
}

1;
