package PlugNPay::Membership::Plan::JSON;

use strict;
use PlugNPay::Membership::Group;
use PlugNPay::Membership::Plan::Type;
use PlugNPay::Membership::Group::JSON;
use PlugNPay::Membership::Plan::Currency;
use PlugNPay::Membership::Plan::Settings;
use PlugNPay::Membership::Plan::BillCycle;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub planToJSON {
  my $self = shift;
  my $plan = shift;

  my $planSettings = new PlugNPay::Membership::Plan::Settings();
  $planSettings->loadPlanSettings($plan->getPlanSettingsID());

  my $planType = new PlugNPay::Membership::Plan::Type();
  $planType->loadPlanType($plan->getPlanTransactionTypeID());

  my $groups = new PlugNPay::Membership::Group();
  my $groupJSON = new PlugNPay::Membership::Group::JSON();

  my $planGroups = [];
  foreach my $group (@{$groups->loadPlanGroups($plan->getPlanID())}) {
    push (@{$planGroups}, $groupJSON->groupToJSON($group));
  }

  my $planInfo = {
    'merchantPlanID'        => $plan->getMerchantPlanID(),
    'activePlanSettings'    => $self->planSettingsToJSON($planSettings),
    'planGroups'            => $planGroups,
    'planTransactionTypeID' => $planType->getTypeID(),
    'planTransactionType'   => $planType->getType()
  };

  return $planInfo;
}

sub planSettingsToJSON {
  my $self = shift;
  my $planSettings = shift;

  my $currency = new PlugNPay::Membership::Plan::Currency();
  $currency->loadCurrency($planSettings->getCurrencyID());

  my $billCycle = new PlugNPay::Membership::Plan::BillCycle();
  $billCycle->loadBillCycle($planSettings->getBillCycleID());

  return {
    'planSettingID'         => $planSettings->getPlanSettingsID(),
    'signupFee'             => $planSettings->getSignUpFee(),
    'recurringFee'          => $planSettings->getRecurringFee(),
    'initialMonthDelay'     => $planSettings->getInitialMonthDelay(),
    'initialDayDelay'       => $planSettings->getInitialDayDelay(),
    'loyaltyFee'            => $planSettings->getLoyaltyFee(),
    'loyaltyCount'          => $planSettings->getLoyaltyCount(),
    'balance'               => $planSettings->getBalance(),
    'isInstallBilling'      => $planSettings->getInstallBilling(),
    'billCycleID'           => $billCycle->getBillCycleID(),
    'billCycleDisplayName'  => $billCycle->getDisplayName(),
    'billCycleDuration'     => $billCycle->getCycleDuration(),
    'currencyID'            => $currency->getCurrencyID(),
    'currency'              => $currency->getCurrencyCode()
  };
}

1;
