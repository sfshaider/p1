package PlugNPay::Transaction::Adjustment::COA::ProcessorMap;

use strict;
use PlugNPay::DBConnection;

our $_processorMap;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_processorMap) {
    $self->_loadMap();
  }

  return $self;
}

sub _loadMap {
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT processor_id,coa_processor_id FROM coa_processor_map
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  my %processorMap;
  if ($result) {
    foreach my $row (@{$result}) {
      $processorMap{$row->{'processor_id'}} = $row->{'coa_processor_id'};
    }
    $_processorMap = \%processorMap;
  }
}

sub getCOAProcessor {
  my $self = shift;
  my $processorID = shift;
  return $_processorMap->{$processorID};
}

sub getProcessor {
  my $self = shift;
  my $coaProcessorID = shift;
  foreach my $processorID (keys %{$_processorMap}) {
    if ($_processorMap->{$processorID} eq $coaProcessorID) {
      return $processorID;
    }
  }
}

1;
