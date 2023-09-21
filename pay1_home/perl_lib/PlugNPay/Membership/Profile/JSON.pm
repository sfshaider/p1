package PlugNPay::Membership::Profile::JSON;

use strict;
use PlugNPay::Membership::Plan;
use PlugNPay::Membership::Group;
use PlugNPay::Membership::Plan::JSON;
use PlugNPay::Membership::Group::JSON;
use PlugNPay::Membership::Plan::Settings;
use PlugNPay::Membership::Profile::Status;
use PlugNPay::Merchant::Customer::PaymentSource;
use PlugNPay::Merchant::Customer::PaymentSource::JSON;
use PlugNPay::Merchant::Customer::PaymentSource::Expose;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub profileToJSON {
  my $self = shift;
  my $profile = shift;

  my $status = new PlugNPay::Membership::Profile::Status();
  $status->loadStatus($profile->getStatusID());

  my $planSettings = new PlugNPay::Membership::Plan::Settings();
  $planSettings->loadPlanSettings($profile->getPlanSettingsID());

  my $plan = new PlugNPay::Membership::Plan();
  $plan->loadPaymentPlan($planSettings->getPlanID());

  my $group = new PlugNPay::Membership::Group();
  my $groupJSON = new PlugNPay::Membership::Group::JSON();
  my $profileGroups = [];
  foreach my $profileGroup (@{$group->loadProfileGroups($profile->getBillingProfileID())}) {
    push (@{$profileGroups}, $groupJSON->groupToJSON($profileGroup));
  }

  my $planJSON = new PlugNPay::Membership::Plan::JSON();

  my $profileData = {
    'billingProfileIdentifier' => $profile->getIdentifier(),
    'customerBalance'          => $profile->getBalance(),
    'profileLoyaltyCount'      => $profile->getLoyaltyCount(),
    'description'              => $profile->getDescription(),
    'allowRenewal'             => $profile->getAllowRenewal(),
    'chargeSignUpFee'          => $profile->getChargeSignUpFee(),
    'profileGroups'            => $profileGroups,
    'postDelays'               => ($profile->getLastSuccessfulBillDate() ? 1 : 0),
    'status'                   => $status->getStatus(),
    'statusID'                 => $status->getStatusID(),
    'creationDate'             => new PlugNPay::Sys::Time('iso', $profile->getCreationDate())->inFormat('yyyymmdd'),
    'currentCycleStartDate'    => new PlugNPay::Sys::Time('iso', $profile->getCurrentCycleStartDate())->inFormat('yyyymmdd'),
    'currentCycleEndDate'      => new PlugNPay::Sys::Time('iso', $profile->getCurrentCycleEndDate())->inFormat('yyyymmdd'),
    'plan'                     => $planJSON->planToJSON($plan),
    'planSettings'             => $planJSON->planSettingsToJSON($planSettings)
  };

  if ($profile->getPaymentSourceID()) {
    my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
    $exposePaymentSource->loadExposedPaymentSource($profile->getPaymentSourceID());

    my $paymentSource = new PlugNPay::Merchant::Customer::PaymentSource();
    $paymentSource->loadPaymentSource($exposePaymentSource->getPaymentSourceID());
    $paymentSource->setIdentifier($exposePaymentSource->getIdentifier());

    my $paymentSourceJSON = new PlugNPay::Merchant::Customer::PaymentSource::JSON();
    $profileData->{'paymentSource'} = $paymentSourceJSON->paymentSourceToJSON($paymentSource);
  }

  return $profileData;
}

1;
