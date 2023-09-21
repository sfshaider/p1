package PlugNPay::Country::LegacyHash;

use strict;
use PlugNPay::Country;

our %_countryUSUSA;
our %_countryUS840;
our %_country840US;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!exists $_countryUSUSA{'US'}) {
    my $countryObj = new PlugNPay::Country();
    my $countryList = $countryObj->loadCountries();
    %_countryUSUSA = ();
    %_countryUS840 = ();
    foreach my $country (values %{$countryList}) {
      $_countryUSUSA{$country->{'twoLetter'}} = $country->{'threeLetter'};
      $_countryUS840{$country->{'twoLetter'}} = $country->{'numeric'};
    }
    %_country840US = reverse %_countryUS840;
  }
}

sub getCountryUSUSA {
  my $self = shift;
  if (ref($self) ne 'PlugNPay::Country::LegacyHash') {
    die('Incorrect implementation, call object method.');
  }
  return %_countryUSUSA;
}

sub getCountryUS840 {
  my $self = shift;
  if (ref($self) ne 'PlugNPay::Country::LegacyHash') {
    die('Incorrect implementation, call object method.');
  }
  return %_countryUS840;
}

sub getCountry840US {
  my $self = shift;
  if (ref($self) ne 'PlugNPay::Country::LegacyHash') {
    die('Incorrect implementation, call object method.');
  }
  return %_country840US;
}

1;
