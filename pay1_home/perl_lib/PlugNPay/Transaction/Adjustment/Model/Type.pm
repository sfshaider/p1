package PlugNPay::Transaction::Adjustment::Model::Type;

use strict;

use PlugNPay::DBConnection();

our $_typeData;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_typeData) {
    $self->_loadTypeData();
  }

  my $idOrType = shift;
  if ($idOrType) {
    $self->_load($idOrType);
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

sub setType {
  my $self = shift;
  my $type = shift;
  $self->{'type'} = $type;
}

sub getType {
  my $self = shift;
  return $self->{'type'};
}

sub _load {
  my $self = shift;
  my $idOrType = shift || $self->getID() || $self->getType();

  foreach my $type (@{$_typeData}) {
    if ($idOrType eq $type->{'id'} || $idOrType eq $type->{'type'}) {
      $self->setID($type->{'id'});
      $self->setType($type->{'type'});
    }
  }
}

sub _loadTypeData {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id,type FROM adjustment_model_type
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  if ($result) {
    my @types;
    foreach my $row (@{$result}) {
      my $type = {
        id => $row->{'id'},
        type => $row->{'type'}
      };
      push @types,$type;
    }
    $_typeData = \@types;
  }
}

1;
