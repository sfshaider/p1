package PlugNPay::Merchant::Customer::Phone::JSON;

use strict;
use PlugNPay::Merchant::Customer::Phone::Type;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub phoneToJSON {
  my $self = shift;
  my $phone = shift;

  my $phoneType = new PlugNPay::Merchant::Customer::Phone::Type();
  $phoneType->loadType($phone->getGeneralTypeID());

  return {
    'phoneIdentifier' => $phone->getIdentifier(),
    'phoneNumber'     => $phone->getPhoneNumber(),
    'description'     => $phone->getDescription(),
    'generalType'     => $phoneType->getType(),
    'generalTypeID'   => $phoneType->getTypeID()
  };
}

1;
