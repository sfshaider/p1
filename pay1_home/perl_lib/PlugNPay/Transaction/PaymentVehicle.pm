package PlugNPay::Transaction::PaymentVehicle;

use strict;

use PlugNPay::DBConnection;

our $_vehicles;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_vehicles) {
    $self->_loadVehicles();
  }

  my $idOrVehicle = shift;
  if ($idOrVehicle) {
    $self->load($idOrVehicle);
  }

  return $self;
}

sub setID {
  my $self = shift;
  my $id = shift;
  $self->{'id'} = $id;
}

sub getID {
  my $self = shift;
  return $self->{'id'};
}

sub setVehicle {
  my $self = shift;
  my $vehicle = shift;
  $self->{'vehicle'} = $vehicle;
}

sub getVehicle {
  my $self = shift;
  return $self->{'vehicle'};
}

sub load {
  my $self = shift;
  my $idOrVehicle = shift;

  foreach my $vehicle (@{$_vehicles}) {
    if ($vehicle->{'id'} eq $idOrVehicle || $vehicle->{'vehicle'} eq $idOrVehicle) {
      $self->setID($vehicle->{'id'});
      $self->setVehicle($vehicle->{'vehicle'});
      last;
    }
  }
}

sub isValid {
  my $self = shift;
  my $vehicle = shift;

  return ((grep { $_ eq $vehicle } @{$self->vehicleList()}) ? 1 : 0);
}

sub vehicleList {
  my $self = shift;
  my @vehicles = map { $_->{'vehicle'} } @{$_vehicles};
  return \@vehicles;
}

sub _loadVehicles() {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id, vehicle FROM transaction_payment_vehicle
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  my @vehicles;
  if ($result) {
    foreach my $row (@{$result}) {
      my $vehicle = { id => $row->{'id'}, vehicle => $row->{'vehicle'} };
      push @vehicles,$vehicle;
    }
  }

  $_vehicles = \@vehicles;
}



1;
