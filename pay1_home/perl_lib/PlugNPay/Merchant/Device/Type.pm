package PlugNPay::Merchant::Device::Type;

use PlugNPay::DBConnection;
use strict;

sub new {
  my $class = shift;
  my $self = {};

  bless $self,$class;

  return $self;
}

sub setID {
  my $self = shift;
  my $id  = shift;

  $self->{'id'} = $id;
}

sub getID {
  my $self = shift;

  return $self->{'id'};
}

sub setType {
  my $self = shift;
  my $type = shift;

  $self->{'type'} = $type;
}

sub getType {
  my $self = shift;

  return $self->{'type'};
}

sub loadTypes {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/
                           SELECT id, type
                           FROM merchant_device_type
                          /);

  $sth->execute() or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});
  my $types = [];

  if(@{$rows}) {
    foreach my $row (@{$rows}) {
      my $type = new PlugNPay::Merchant::Device::Type();
      $type->setID($row->{'id'});
      $type->setType($row->{'type'});
      push @{$types},$type;
    }
  }

  return $types;
}

sub loadTypeByID {
  my $self = shift;
  my $id = shift;

  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('merchant_cust', q/
                           SELECT type
                           FROM merchant_device_type
                           WHERE id = ? /);

  $sth->execute($id) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});

  if(@{$rows}) {
    $self->setID($id);
    $self->setType($rows->[0]{'type'});
  }
}

sub loadTypeByType {
  my $self = shift;
  my $type = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/
                           SELECT id
                           FROM merchant_device_type
                           WHERE type = ? /);
  
  $sth->execute($type) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  if(@{$rows}) {
    $self->setID($rows->[0]{'id'});
    $self->setType($type);
  }
}

1;