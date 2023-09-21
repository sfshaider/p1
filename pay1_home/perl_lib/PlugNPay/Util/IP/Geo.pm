package PlugNPay::Util::IP::Geo;

use strict;
use PlugNPay::ResponseLink;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub lookup {
  my $self = shift;
  my $ip = shift;

  if ($self->{$ip}) { # returne already retrieved data if found.
    return$self->{$ip};
  }

  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL('http://geolocate:3000/ip/geo/' . $ip);
  $rl->setRequestMethod('GET');
  $rl->setRequestMode('DIRECT');
  $rl->setResponseAPIType('json');
  $rl->doRequest();
  my %response = $rl->getResponseAPIData();

  $self->{$ip} = \%response;
  return \%response;
}

sub lookupCountryCode {
  my $self = shift;
  my $ip = shift;

  my $data = $self->lookup($ip);
  return $data->{'countryCode'};
}

sub lookupCountryName {
  my $self = shift;
  my $ip = shift;

  my $data = $self->lookup($ip);
  return $data->{'countryName'};
}

1;
