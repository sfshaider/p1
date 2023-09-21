package PlugNPay::Merchant::DeviceLink::Type;

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
  my $id = shift;

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
                           FROM merchant_device_link_type  /);

  $sth->execute() or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});
  my $types = [];

  if(@{$rows}) {
    foreach my $row (@{$rows}) {
      my $type = new PlugNPay::Merchant::DeviceLink::Type();
      $type->setID($row->{'id'});
      $type->setType($row->{'type'});
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
                           FROM merchant_device_link_type
                           WHERE id = ?
                          /);

  $sth->execute($id) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});

  if(@{$rows}) {
    $self->setID($id);
    $self->setType($rows->[0]{'type'});
  }
}

1;