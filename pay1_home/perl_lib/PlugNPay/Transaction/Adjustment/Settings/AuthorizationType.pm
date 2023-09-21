package PlugNPay::Transaction::Adjustment::Settings::AuthorizationType;

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
  return $_typeData;
}

sub getEnabledTypes {
  my $self = shift;

  my @enabledTypes;

  foreach my $type (@{$_typeData}) {
    if ($type->{enabled} == 1) {
      my $enabledType = new ref($self);
      $enabledType->load($type->{'id'});
      push @enabledTypes,$enabledType;
    }
  }

  return \@enabledTypes;
}

sub load {
  my $self = shift;
  my $id = shift;
  $self->setID($id);
  $self->_load();
}

sub _load {
  my $self = shift;
  my $idOrType = shift || $self->getID() || $self->getType();

  foreach my $type (@{$_typeData}) {
    if ($idOrType eq $type->{'id'} || $idOrType eq $type->{'type'}) {
      $self->setID($type->{'id'});
      $self->setType($type->{'type'});
      $self->setEnabled($type->{'enabled'});
      $self->setName($type->{'name'});
      $self->setDescription($type->{'description'});
    }
  }
}

sub _loadTypeData {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id,type,enabled,name,description FROM adjustment_authorization_type
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  if ($result) {
    my @types;
    foreach my $row (@{$result}) {
      my $type = {
        id => $row->{'id'},
        type => $row->{'type'},
        enabled => $row->{'enabled'},
        name => $row->{'name'},
        description => $row->{'description'}
      };
      push @types,$type;
    }
    $_typeData = \@types;
  }
}

1;
