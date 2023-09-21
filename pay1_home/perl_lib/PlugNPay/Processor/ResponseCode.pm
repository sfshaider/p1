package PlugNPay::Processor::ResponseCode;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Processor;
use PlugNPay::Logging::DataLog;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $processor = shift;
  if ($processor) {
    $self->loadMap($processor);
  }

  $self->loadSimplifiedResponseMap();

  return $self;
}

sub setProcessor {
  my $self = shift;
  my $processor = shift;
  my $procObj = new PlugNPay::Processor($processor);
  $self->{'processor'} = $processor->getProcessorID();
}

sub getProcessorID {
  my $self = shift;
  return $self->{'processor'};
}

sub setErrorCode {
  my $self = shift;
  my $errorCode = shift;
  $self->{'errorCode'} = $errorCode;
}

sub getErrorCode {
  my $self = shift;
  return $self->{'errorCode'};
}

sub _setMap {
  my $self = shift;
  my $map = shift;
  $self->{'map'} = $map;
}

sub getMap {
  my $self = shift;
  my $map = $self->{'map'};
  if (!$map || ref($map) ne 'HASH') {
    $map = $self->loadMap();
  }

  return $map;
}

#maps new processors to badcard/declined
sub getResultForCode { 
  my $self = shift;
  my $code = shift || $self->getErrorCode();
  my $response = '';
  eval {
    my $map = $self->getMap();
    $response = $map->{$code};
  };

  return $response;
}

#loads map of processor responses to map to declined/badcard/problem/etc
sub loadMap {
  my $self = shift;
  my $processor = shift || $self->getProcessorID();

  if ($processor !~ /^[0-9]+$/) {
    my $processorObj = new PlugNPay::Processor({'shortName' => $processor});
    $processor = $processorObj->getID();
  }
  
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/ SELECT code, response
                             FROM processor_response_code
                             WHERE processor_id = ? /);
  $sth->execute($processor) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});
  
  my $map = {};
  if (@{$rows} > 0) {
    foreach my $row (@{$rows}) {
      $map->{$row->{'code'}} = $row->{'response'};
    }
  }
  $self->_setMap($map);
  return $map;
}

#Below here is the "sresponse" mapping
sub getSimplifiedResponseCode {
  my $self = shift;
  my $processor = shift;
  my $code = shift;
  my $simplifiedCode;

  my $resp = $self->{'sresponse_map'};
  if ($processor && $code && exists $resp->{$processor}) {
    $simplifiedCode = uc($resp->{$processor}{$code}) || 'E';
  }

  return $simplifiedCode;
}

#called on creation
sub loadSimplifiedResponseMap {
  my $self = shift;
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $query = q/
        SELECT p.code_handle AS `processor`, sr.code AS `simplified_code`, psr.processor_code
          FROM processor p, processor_simplified_response psr, simplified_response sr
         WHERE psr.processor_id = p.id
           AND psr.simplified_response_id = sr.id
    /;
    my $results = $dbs->fetchallOrDie('pnpmisc', $query, [], {})->{'result'};
    my $sresp = {};
    foreach my $row (@{$results}) {
      my @values = split(',',$row->{'values'});
      $sresp->{$row->{'processor'}}{$row->{'processor_code'}} = $row->{'simplified_code'};
    }

    $self->{'sresponse_map'} = $sresp;
  };

  if ($@) {
    $self->log('loadSimplifiedResponseMap', $@);
    $self->{'sresponse_map'} = {};
  }
}

sub log {
  my $self = shift;
  my $function = shift;
  my $error = shift;
  new PlugNPay::Logging::DataLog({'collection' => 'processor'})->log({
    'module' => 'PlugNPay::Processor::ResponseCode',
    'function' => $function,
    'error' => $@
  });
}

1;
