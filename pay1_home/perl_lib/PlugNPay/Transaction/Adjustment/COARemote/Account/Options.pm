package PlugNPay::Transaction::Adjustment::COARemote::Account::Options;

use strict;

use PlugNPay::DBConnection();

our $_modeData;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_modeData) {
    $self->_loadModeData();
  }

  my $idOrMode = shift;
  if ($idOrMode) {
    $self->_load($idOrMode);
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

sub setMode {
  my $self = shift;
  my $mode = shift;
  $self->{'mode'} = $mode;
}

sub getMode {
  my $self = shift;
  return $self->{'mode'};
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
  return $_modeData;
}

sub getAllEnabledRows {
  my $self = shift;

  my $arr = ();
  foreach my $row (@{$_modeData}) {
    if ($row->{enabled} == 1) {
      push @$arr, $row;
    }
  }

  return $arr;
}

sub _load {
  my $self = shift;
  my $idOrMode = shift || $self->getID() || $self->getMode();

  foreach my $mode (@{$_modeData}) {
    if ($idOrMode eq $mode->{'id'} || $idOrMode eq $mode->{'mode'}) {
      $self->setID($mode->{'id'});
      $self->setMode($mode->{'mode'});
      $self->setEnabled($mode->{'enabled'});
      $self->setName($mode->{'name'});
      $self->setDescription($mode->{'description'});
    }
  }
}

sub _loadModeData {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id,mode,enabled,name,description FROM adjustment_retail
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  if ($result) {
    my @modes;
    foreach my $row (@{$result}) {
      my $mode = {
        id => $row->{'id'},
        mode => $row->{'mode'},
        enabled => $row->{'enabled'},
        name => $row->{'name'},
        description => $row->{'description'},
      };
      push @modes,$mode;
    }
    $_modeData = \@modes;
  }
}

1;
