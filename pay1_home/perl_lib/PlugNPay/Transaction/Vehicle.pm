package PlugNPay::Transaction::Vehicle;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache(3);

our $idCache;
our $vehicleCache;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!defined $idCache || !defined $vehicleCache) {
    $vehicleCache = new PlugNPay::Util::Cache::LRUCache(2);
    $idCache = new PlugNPay::Util::Cache::LRUCache(2);
  }

  return $self;
}

##########################
# Transaction Vehicle ID #
##########################
sub getTransactionVehicleID {
  my $self = shift;
  my $vehicleType = shift;

  unless ($vehicleCache->contains($vehicleType)) {
    $self->loadVehicle($vehicleType,'vehicle');
  }

  return $vehicleCache->get($vehicleType);
}

sub loadVehicle {
  my $self = shift;
  my $value = shift;
  my $mode = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/
                          SELECT id,vehicle
                          FROM transaction_vehicle
                          WHERE / . ($mode eq 'vehicle' ? ' vehicle = ? ' : ' id = ? '));
  $sth->execute($value) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $vehicle = $rows->[0]{'vehicle'};
  my $id = $rows->[0]{'id'};

  if ($id && defined $vehicle) {
    $self->_addToCaches($id,$vehicle);
  }
}

sub loadAllVehicleIDs {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/
                          SELECT id,vehicle
                          FROM transaction_vehicle
                          /);
  $sth->execute() or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $hash = {};
  foreach my $row (@{$rows}){
    $hash->{$row->{'id'}} = $row->{'vehicle'};
  }

  return $hash;
}

sub getTransactionVehicleName {
  my $self = shift;
  my $id = shift;

  unless ($idCache->contains($id)) {
    $self->loadVehicle($id,'id');
  }

  return $idCache->get($id);
}

sub _addToCaches {
  my $self = shift;
  my $key = shift;
  my $value = shift;
  
  $idCache->set($key,$value);
  $vehicleCache->set($value,$key);
}

1;
