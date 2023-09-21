package PlugNPay::Merchant::Customer::Address::JSON;

use strict;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub addressToJSON {
  my $self = shift;
  my $address = shift;

  return {
    'addressIdentifier' => $address->getIdentifier(),
    'name'              => $address->getName(),
    'line1'             => $address->getLine1(),
    'line2'             => $address->getLine2(),
    'city'              => $address->getCity(),
    'state'             => $address->getStateProvince(),
    'postalCode'        => $address->getPostalCode(),
    'country'           => $address->getCountry(),
    'company'           => $address->getCompany()
  };
}

1;
