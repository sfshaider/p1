package PlugNPay::Transaction::Adjustment::DefaultPaymentVehicle;

use strict;

use PlugNPay::DBConnection;

our $_vehicleData;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_vehicleData) {
    $self->_loadVehicleData();
  }

  my $id = shift;
  if ($id) {
    $self->setID($id);
    $self->_load();
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

sub setVehicleID {
  my $self = shift;
  my $vehicle = shift;
  $self->{'vehicle'} = $vehicle;
}

sub getVehicleID {
  my $self = shift;
  return $self->{'vehicle'};
}

sub setVehicleSubtypeID {
  my $self = shift;
  my $subtype = shift;
  $self->{'subtype'} = $subtype;
}

sub getVehicleSubtypeID {
  my $self = shift;
  return $self->{'subtype'};
}

sub setEnabled {
  my $self = shift;
  my $enabled = shift;
  $self->{'enabled'} = $enabled;
}

sub getEnabled {
  my $self = shift;
  return $self->{'enabled'};
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

sub getAllRows {
  my $self = shift;

  return $_vehicleData;
}

sub getAllEnabledRows {
  my $self = shift;

  my $arr = ();
  foreach my $row (@{$_vehicleData}) {
    if ($row->{'enabled'} == 1) {
      push @$arr, $row;
    }
  }

  return $arr;
}

sub _load {
  my $self = shift;

  foreach my $row (@{$_vehicleData}) {
    if ($self->getID() == $row->{'id'}) {
      $self->setID($row->{'id'});
      $self->setVehicleID($row->{'vehicle_id'});
      $self->setVehicleSubtypeID($row->{'subtype'});
      $self->setEnabled($row->{'enabled'});
      $self->setName($row->{'name'});
      $self->setDescription($row->{'description'});
      last;
    }
  }
}

sub _loadVehicleData {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection;
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id,vehicle_id,subtype,enabled,name,description FROM transaction_payment_vehicle_subtype
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  if ($result) {
    my @vehicleData;
    foreach my $row (@{$result}) {
      my $vehicle = {
        id => $row->{'id'},
        vehicle_id => $row->{'vehicle_id'},
        subtype => $row->{'subtype'},
        enabled => $row->{'enabled'},
        name => $row->{'name'},
        description => $row->{'description'},
      };
      push @vehicleData,$vehicle;
    }
    $_vehicleData = \@vehicleData;
  }
}

1;
