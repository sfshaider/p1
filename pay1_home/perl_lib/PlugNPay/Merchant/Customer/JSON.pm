package PlugNPay::Merchant::Customer::JSON;

use strict;
use PlugNPay::Merchant::Customer;
use PlugNPay::Merchant::Customer::Phone;
use PlugNPay::Merchant::Customer::Address;
use PlugNPay::Merchant::Customer::Phone::Type;
use PlugNPay::Merchant::Customer::Phone::JSON;
use PlugNPay::Merchant::Customer::Phone::Expose;
use PlugNPay::Merchant::Customer::PaymentSource;
use PlugNPay::Merchant::Customer::Address::JSON;
use PlugNPay::Merchant::Customer::Address::Expose;
use PlugNPay::Merchant::Customer::PaymentSource::JSON;
use PlugNPay::Merchant::Customer::PaymentSource::Expose;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub customerToJSON {
  my $self = shift;
  my $merchantCustomer = shift;
  my $includeDetails = shift;
  $includeDetails = 1 if !defined $includeDetails;

  my $json = {};

  my $customer = new PlugNPay::Merchant::Customer();
  $customer->loadCustomer($merchantCustomer->getCustomerID());

  my $exposeAddress = new PlugNPay::Merchant::Customer::Address::Expose();
  $exposeAddress->loadExposedAddress($merchantCustomer->getDefaultAddressID());

  my $defaultAddress = new PlugNPay::Merchant::Customer::Address();
  $defaultAddress->loadAddress($exposeAddress->getAddressID());
  $defaultAddress->setIdentifier($exposeAddress->getIdentifier());

  my $exposePhone = new PlugNPay::Merchant::Customer::Phone::Expose();
  $exposePhone->loadExposedPhone($merchantCustomer->getDefaultPhoneID());

  my $defaultPhone = new PlugNPay::Merchant::Customer::Phone();
  $defaultPhone->loadPhone($exposePhone->getPhoneID());
  $defaultPhone->setIdentifier($exposePhone->getIdentifier());

  my $exposeFax = new PlugNPay::Merchant::Customer::Phone::Expose();
  $exposeFax->loadExposedPhone($merchantCustomer->getDefaultFaxID());

  my $defaultFax = new PlugNPay::Merchant::Customer::Phone();
  $defaultFax->loadPhone($exposeFax->getPhoneID());
  $defaultFax->setIdentifier($exposeFax->getIdentifier());

  my $addressJSON = new PlugNPay::Merchant::Customer::Address::JSON();
  my $paymentSourceJSON = new PlugNPay::Merchant::Customer::PaymentSource::JSON();
  my $phoneJSON = new PlugNPay::Merchant::Customer::Phone::JSON();

  $json->{'name'}               = $merchantCustomer->getName();
  $json->{'email'}              = $customer->getEmail();
  $json->{'username'}           = $merchantCustomer->getUsername();
  $json->{'defaultAddress'}     = $addressJSON->addressToJSON($defaultAddress);
  $json->{'defaultPhone'}       = $phoneJSON->phoneToJSON($defaultPhone);
  $json->{'defaultFax'}         = $phoneJSON->phoneToJSON($defaultFax);

  if ($includeDetails) {
    $json->{'addresses'}          = [];
    $json->{'phones'}             = [];
    $json->{'paymentSources'}     = [];

    foreach my $customerAddress (@{$exposeAddress->loadExposedAddresses($merchantCustomer->getMerchantCustomerLinkID())}) {
      my $address = new PlugNPay::Merchant::Customer::Address();
      $address->loadAddress($customerAddress->getAddressID());
      $address->setIdentifier($customerAddress->getIdentifier());
      push (@{$json->{'addresses'}}, $addressJSON->addressToJSON($address));
    }

    foreach my $customerPhone (@{$exposePhone->loadExposedPhones($merchantCustomer->getMerchantCustomerLinkID())}) {
      my $phone = new PlugNPay::Merchant::Customer::Phone();
      $phone->loadPhone($customerPhone->getPhoneID());
      $phone->setIdentifier($customerPhone->getIdentifier());
      push (@{$json->{'phones'}}, $phoneJSON->phoneToJSON($phone));
    }

    my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
    foreach my $customerPaymentSource (@{$exposePaymentSource->loadExposedPaymentSources($merchantCustomer->getMerchantCustomerLinkID())}) {
      my $paymentSource = new PlugNPay::Merchant::Customer::PaymentSource();
      $paymentSource->loadPaymentSource($customerPaymentSource->getPaymentSourceID());
      $paymentSource->setIdentifier($customerPaymentSource->getIdentifier());
      push (@{$json->{'paymentSources'}}, $paymentSourceJSON->paymentSourceToJSON($paymentSource));
    }
  }

  return $json;
}

1;
