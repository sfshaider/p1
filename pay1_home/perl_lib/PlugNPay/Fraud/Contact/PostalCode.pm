package PlugNPay::Fraud::Contact::PostalCode;

use strict;
use PlugNPay::DBConnection;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;
  my $postalCode = shift;
  if ($postalCode) {
    $self->setPostalCode($postalCode);
  }
  return $self;
}

sub setPostalCode {
  my $self = shift;
  my $postalCode = shift;
  $self->{'postalCode'} = $postalCode;
}

sub getPostalCode {
  my $self = shift;
  return $self->{'postalCode'};
}

sub load {
  my $self = shift;
  my $state = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $select = q/
    SELECT zipcode, city, state, country
      FROM zipcodes
     WHERE state = ?
  /;
  my $rows = [];
  eval {
    $rows = $dbs->fetchallOrDie('fraudtrack', $select, [$state], {})->{'results'};
  };

  my $result = {};
  foreach my $row (@{$rows}) {
    $result->{$row->{'zipcode'}} = $row;
  }

  $self->{'zips'}{$state} = $result;
}

sub isValid {
  my $self = shift;
  my $postalCode = shift || $self->getPostalCode();

  $postalCode =~ s/[^a-zA-Z0-9 ]//g;

  return length($postalCode) > 4;
}

sub matchesState {
  my $self = shift;
  my $state = uc shift;
  my $postalCode = shift || $self->getPostalCode();

  if (!defined $self->{'zips'}{$state}) {
    $self->load($state);
  }

  return uc($self->{'zips'}{$state}{$postalCode}{'state'}) eq $state;
}


1;
