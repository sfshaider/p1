package PlugNPay::Processor::Network;

use strict;
use PlugNPay::Processor;
use PlugNPay::DBConnection;

our $map;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $options = shift;
  
  if (!defined $map) {
    $map = {};
  }

  if (ref($options) eq 'HASH') {
    if ($options->{'processor'}) {
      $self->setProcessorID($options->{'processor'});
      $self->load();
    }
    
    if ($options->{'networkID'}) {
      $self->setNetworkID($options->{'networkID'});
    }
  }

  return $self;
}

sub setProcessorID {
  my $self = shift;
  my $processorID = shift;
  if ($processorID !~ /^\d+$/) {
    my $processor = new PlugNPay::Processor({'shortName' => $processorID});
    $processorID = $processor->getID();
  }

  $self->{'processorID'} = $processorID;
}

sub getProcessorID {
  my $self = shift;
  return $self->{'processorID'};
}

sub setNetworkID {
  my $self = shift;
  my $networkID = shift;
  $self->{'networkID'} = $networkID;
}

sub getNetworkID {
  my $self = shift;
  return $self->{'networkID'};
}

sub getNetworkName {
  my $self = shift;
  my $networkID = shift || $self->getNetworkID();
  my $processorID = shift || $self->getProcessorID();

  if (!$map->{$processorID}{$networkID}) {
    $self->load($processorID, $networkID);
  }

  return $map->{$processorID}{$networkID};
}

sub load {
  my $self = shift;
  my $processorID = shift || $self->getProcessorID();
  my $networkID = shift || $self->getNetworkID();

  if (defined $networkID) {
    my $loaded = $self->_loadIndividualProcessorNetwork($networkID,$processorID);
    if ($loaded) {
      $map->{$processorID}{$networkID} = $loaded;
    }
  } else {
    $map->{$processorID} = $self->_loadAllForProcessor($processorID);
  }

  return $map->{$processorID};
}

sub _loadIndividualProcessorNetwork {
  my $self = shift;
  my $networkID = shift;
  my $processorID = shift;

  my $select = q/
    SELECT processor_id, network_id, network_name
      FROM processor_network_map
     WHERE processor_id = ?
       AND network_id = ?
  /;

  my $dbs = new PlugNPay::DBConnection();
  my $rows = $dbs->fetchallOrDie('pnpmisc', $select, [$processorID, $networkID], {})->{'result'};

  my $result;

  if (@{$rows} > 0 && $rows->[0]{'network_id'} eq $networkID) {
    $result = $rows->[0]{'network_name'};
  }

  return $result;
}

sub _loadAllForProcessor {
  my $self = shift;
  my $processorID = shift;
  
  my $select = q/
    SELECT processor_id, network_id, network_name
      FROM processor_network_map
     WHERE processor_id = ?
  /;
   
  my $dbs = new PlugNPay::DBConnection();
  my $rows = $dbs->fetchallOrDie('pnpmisc', $select, [$processorID], {})->{'result'};

  my $result = {};
  foreach my $row (@{$rows}) {
    if ($row->{'processor_id'} = $processorID) {
      $result->{$row->{'network_id'}} = $row->{'network_name'};
    }
  }

  return $result;
}

1;
