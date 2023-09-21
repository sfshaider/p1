package PlugNPay::Transaction::Adjustment::Settings::Threshold;

use strict;

use PlugNPay::DBConnection;
use PlugNPay::Util::RPN;

our $_thresholdModes;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_thresholdModes) {
    $self->_loadThresholdModes();
  }

  my $idOrMode = shift;
  if (defined $idOrMode) {
    $self->_load($idOrMode);
  }
 
  return $self;
}

sub setTransactionAmount {
  my $self = shift;
  my $transactionAmount = shift;
  $self->{'transactionAmount'} = $transactionAmount;
}

sub getTransactionAmount {
  my $self = shift;
  return $self->{'transactionAmount'};
}

sub setPercent {
  my $self = shift;
  my $thresholdPercent = shift;
  $self->{'thresholdPercent'} = $thresholdPercent;
}

sub getPercent {
  my $self = shift;
  return $self->{'thresholdPercent'};
}

sub setFixed {
  my $self = shift;
  my $fixedThreshold = shift;
  $self->{'fixedThreshold'} = $fixedThreshold;
}

sub getFixed {
  my $self = shift;
  return $self->{'fixedThreshold'};
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
  $self->{enabled} = $enabled;
}

sub getEnabled {
  my $self = shift;
  return $self->{enabled};
}

sub setName {
  my $self = shift;
  my $name = shift;
  $self->{'name'} = $name;
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

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub getAllRows {
  my $self = shift;

  return $_thresholdModes; 
}

sub getEnabledModes {
  my $self = shift;

  my @enabledModes;

  foreach my $mode (@{$_thresholdModes}) {
    if ($mode->{'enabled'} == 1) {
      my $enabledMode = new ref($self);
      $enabledMode->load($mode->{'id'});
      push @enabledModes, $enabledMode;
    }
  }

  return \@enabledModes;
}

sub calculateThreshold {
  my $self = shift;
  my $rpn = new PlugNPay::Util::RPN();

  $rpn->addVariable('percent',($self->getPercent() / 100) * $self->getTransactionAmount());
  $rpn->addVariable('fixed',$self->getFixed());
  $rpn->setFormula($self->_infoForThresholdMode($self->getID(),'formula'));
  return $rpn->calculate();
}

sub _infoForThresholdMode {
  my $self = shift;
  my $mode = shift;
  my $key = shift;
  foreach my $validMode (@{$_thresholdModes}) {
    if ($mode eq $validMode->{'id'} || $mode eq $validMode->{'mode'}) {
      return $validMode->{$key};
    }
  }
}

sub load {
  my $self = shift;
  my $id = shift;
  $self->setID($id);
  $self->_load();
}

sub _load {
  my $self = shift;
  my $idOrMode = $self->getID() || $self->getMode() || shift;
  foreach my $mode (@{$_thresholdModes}) {
    if ($idOrMode eq $mode->{'id'} || $idOrMode eq $mode->{'mode'}) {
      $self->setID($mode->{'id'});
      $self->setMode($mode->{'mode'});
      $self->setEnabled($mode->{'enabled'});
      $self->setName($mode->{'name'});
      $self->setDescription($mode->{'description'});
    }
  }
}

sub _loadThresholdModes {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id,mode,formula,enabled,name,description FROM adjustment_threshold_mode
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  if ($result) {
    my @modes;
    foreach my $row (@{$result}) {
      my $mode = {
        id => $row->{'id'},
        mode => $row->{'mode'},
        formula => $row->{'formula'},
        enabled => $row->{'enabled'},
        name => $row->{'name'},
        description => $row->{'description'},
      };

      push @modes,$mode;
    }

    $_thresholdModes = \@modes;
  }
}


1;
