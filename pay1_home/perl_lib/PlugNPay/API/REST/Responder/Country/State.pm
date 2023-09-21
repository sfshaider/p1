package PlugNPay::API::REST::Responder::Country::State;

use strict;

use PlugNPay::Country;
use PlugNPay::Country::State;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;

  my $states = new PlugNPay::Country::State();
  my $stateData = $states->getStatesForCountry($self->getResourceData()->{'country'});

  $self->setResponseCode(200);
  return { states => $stateData };
}

1;
