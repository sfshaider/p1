package PlugNPay::API::REST::Responder::Country;

use strict;

use PlugNPay::Country;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;

  my $countries = new PlugNPay::Country();
  my $countryData = $countries->getCountries();

  $self->setResponseCode(200);
  return { countries => $countryData };
}

1;
