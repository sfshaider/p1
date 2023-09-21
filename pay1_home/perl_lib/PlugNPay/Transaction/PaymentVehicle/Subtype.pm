package PlugNPay::Transaction::PaymentVehicle::Subtype;

use strict;

use PlugNPay::DBConnection;

our $_subtypes;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_subtypes) {
    $self->_loadSubtypes();
  }

  my $idOrSubtype = shift;
  if ($idOrSubtype) {
    $self->load($idOrSubtype);
  }

  return $self;
}

sub load {
  my $self = shift;
  my $id = shift;

  foreach my $subtype (@{$_subtypes}) {
    if ($subtype->{'id'} eq $id) {
      $self->setID($subtype->{'id'});
      $self->setPaymentVehicleID($subtype->{'vehicleID'});
      $self->setSubtype($subtype->{'subtype'});
      $self->setEnabled($subtype->{'enabled'});
      $self->setName($subtype->{'name'});
      $self->setDescription($subtype->{'description'});
      last;
    }
  }
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

sub setSubtype {
  my $self = shift;
  my $name = shift;
  $self->{'subtype'} = $name;
}
  

sub getSubtype {
  my $self = shift;
  return $self->{'subtype'};
}

sub getSubtypesForVehicle {
  my $self = shift;
  my $vehicle = shift || $self->getPaymentVehicleID();

  my @subtypes;
  foreach my $subtype (@{$_subtypes}) {
    if ($subtype->{'vehicleID'} eq $vehicle) {
      push @subtypes,$subtype;
    }
  }

  return \@subtypes;
}
  

sub setPaymentVehicleID {
  my $self = shift;
  my $id = shift;
  $self->{'paymentVehicleID'} = $id;
}

sub getPaymentVehicleID {
  my $self = shift;
  return $self->{'paymentVehicleID'};
}

sub setEnabled {
  my $self = shift;
  my $enabled = shift;
  $self->{'enabled'} = ($enabled ? 1 : 0);
}

sub getEnabled {
  my $self = shift;
  return ($self->{'enabled'} ? 1 : 0);
}

sub setName {
  my $self = shift;
  my $name = shift;
  $self->{'name'} = $name;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub setDescription {
  my $self = shift;
  my $description = shift;
  $self->{'description'} = $description;
}

sub getDescription {
  my $self = shift;
  return $self->{'description'};
}

sub getEnabledSubtypes {
  my $self = shift;

  my @enabledSubtypes;
  foreach my $subtype (@{$_subtypes}) {
    if ($subtype->{'enabled'}) {
      my $enabledSubtype = new ref($self);
      $enabledSubtype->load($subtype->{'id'});
      push @enabledSubtypes,$enabledSubtype;
    }
  }

  return \@enabledSubtypes;
}

sub _loadSubtypes {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id,vehicle_id,subtype,enabled,name,description FROM transaction_payment_vehicle_subtype
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  my @subtypes;
  if ($result) {
    foreach my $row (@{$result}) {
      my $subtype = { id => $row->{'id'}, 
               vehicleID => $row->{'vehicle_id'}, 
                 subtype => $row->{'subtype'},
                 enabled => $row->{'enabled'},
                    name => $row->{'name'},
             description => $row->{'description'} };
      push @subtypes,$subtype;
    }
  }

  $_subtypes = \@subtypes;
}


1;
