package PlugNPay::Merchant::Customer::FuturePayment::JSON;

use strict;
use PlugNPay::Merchant;
use PlugNPay::Membership::Profile;
use PlugNPay::Membership::Plan::Type;
use PlugNPay::Merchant::Customer::PaymentSource::Expose;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub futurePaymentToJSON {
  my $self = shift;
  my $futurePayment = shift;
  my $json = {};

  my $transType = new PlugNPay::Membership::Plan::Type();
  $transType->loadPlanType($futurePayment->getTransactionTypeID());

  my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
  $exposePaymentSource->loadExposedPaymentSource($futurePayment->getPaymentSourceID());

  $json->{'amount'}                  = $futurePayment->getAmount();
  $json->{'description'}             = $futurePayment->getDescription();
  $json->{'allowModify'}             = $futurePayment->isModifiable();
  $json->{'paymentDate'}             = $futurePayment->getPaymentDate();
  $json->{'creationDate'}            = $futurePayment->getCreationDate();
  $json->{'billingAccount'}          = new PlugNPay::Merchant($futurePayment->getBillingAccountID())->getMerchantUsername();
  $json->{'profilePayment'}          = $futurePayment->isProfilePayment();
  $json->{'transactionType'}         = $transType->getType();
  $json->{'futurePaymentIdentifier'} = $futurePayment->getIdentifier();
  $json->{'paymentSourceIdentifier'} = $exposePaymentSource->getIdentifier();

  if ($futurePayment->isProfilePayment()) {
    my $profile = new PlugNPay::Membership::Profile();
    $profile->loadBillingProfile($futurePayment->getProfileID());
    $json->{'profileIdentifier'} = $profile->getIdentifier();
  }

  return $json;
}

1;
