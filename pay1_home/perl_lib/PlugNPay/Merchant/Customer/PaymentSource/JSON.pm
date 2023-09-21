package PlugNPay::Merchant::Customer::PaymentSource::JSON;

use strict;
use PlugNPay::Merchant::Customer::Address::Expose;
use PlugNPay::Merchant::Customer::PaymentSource::Type;
use PlugNPay::Merchant::Customer::PaymentSource::ACH::Type;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub paymentSourceToJSON {
  my $self = shift;
  my $paymentSource = shift;
  my $json = {};

  $json->{'lastFour'} = $paymentSource->getLastFour();
  $json->{'token'} = $paymentSource->getToken();
  $json->{'description'} = $paymentSource->getDescription();

  my $paymentType = new PlugNPay::Merchant::Customer::PaymentSource::Type();
  $paymentType->loadPaymentType($paymentSource->getPaymentSourceTypeID());
  $json->{'paymentType'} = $paymentType->getPaymentType();

  if ($paymentType->getPaymentType() =~ /card/i) {
    $json->{'expirationMonth'} = $paymentSource->getExpirationMonth();
    $json->{'expirationYear'} = $paymentSource->getExpirationYear();
    $json->{'isCommercialCard'} = $paymentSource->getIsCommercialCard();
    $json->{'cardBrand'} = $paymentSource->getCardBrand();
  } elsif ($paymentType->getPaymentType() =~ /ach/i) {
    my $accountType = new PlugNPay::Merchant::Customer::PaymentSource::ACH::Type();
    $accountType->loadACHAccountType($paymentSource->getAccountTypeID());
    $json->{'accountType'} = $accountType->getAccountType();
    $json->{'accountTypeID'} = $accountType->getAccountTypeID();
  }

  $json->{'lastUpdated'} = $paymentSource->getLastUpdated();

  my $exposeAddress = new PlugNPay::Merchant::Customer::Address::Expose();
  $exposeAddress->loadExposedAddress($paymentSource->getBillingAddressID());
  $json->{'billingAddressIdentifier'} = $exposeAddress->getIdentifier();

  $json->{'paymentSourceIdentifier'} = $paymentSource->getIdentifier();
  return $json;
}

1;
