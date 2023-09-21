package PlugNPay::Stats::Query;

use strict;
use PlugNPay::AWS::Lambda;
use List::Util qw(minstr maxstr);
use PlugNPay::Logging::DataLog;


############################################
# Module: PlugNPay::Stats::Query
# Description: Calls stats_query lambda to get amount/count for data passed


sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}


sub getQueryStats {
  my $self = shift;
  my $args = {};
  my $response = {};

  $args->{'lambda'} = 'stats_query';
  $args->{'invocationType'} = 'RequestResponse';
  $args->{'data'} = $self->{'query'};

  # check for missing data
  if (!exists $self->{'query'}{'type'} || !exists $self->{'query'}{'dateRange'} || !exists $self->{'query'}{'data'}){

    my $log = new PlugNPay::Logging::DataLog({'collection' => 'stats_query'});

    $response->{'payload'}{'data'} = '';
    $response->{'payload'}{'error'} = "Missing required data (type, dateRange[], data[])";
    $response->{'payload'}{'status'} = 'error';

    $log->log({
      'status'       => $response->{'payload'}{'status'},
      'error'        => 'Failed to add data',
      'errorMessage' => $response->{'payload'}{'error'},
      'package'      => 'PlugNPay::Stats::Query',
      'function'     => 'addData'
    });

  } else {
    $response = PlugNPay::AWS::Lambda::invoke($args);
  }

  return $response->{'payload'};
}

sub addData {
  my $self = shift;
  my $data = shift;
  my $status = 1;

  eval {
    # check for missing data
    if (!exists $data->{'identifier'} || !exists $data->{'currency'} || !exists $data->{'mode'} || !exists $data->{'status'}) {
      die "Missing required data (identifier,currency,mode,status)";
    }

    push(@{$self->{'query'}{'data'}}, $data);
  };

  if ($@) {
    $status = 0;
    my $log = new PlugNPay::Logging::DataLog({'collection' => 'stats_query'});
    $log->log({
      'status'       => 'error',
      'error'        => 'Failed to add data',
      'errorMessage' => $@,
      'package'      => 'PlugNPay::Stats::Query',
      'function'     => 'addData'
    });
  }

  return $status;
}

sub setDates {
  my $self = shift;
  my $type = shift;
  my $dates = shift;
  my $status = 1;
  my $numOfDates = @{$dates};

  eval {
    $self->{'query'}{'type'} = $type;

    if ($type eq "range") {
      if ($numOfDates > 2 || $numOfDates < 2) { # range type must be between 2 dates
        die "Incorrect number of dates provided, must be 2 dates";
      }
      my $minDate = minstr(@{$dates}); # find earlier date
      my $maxDate = maxstr(@{$dates}); # find later date

      push(@{$self->{'query'}{'dateRange'}}, $minDate); # push earlier date to first element in the array
      push(@{$self->{'query'}{'dateRange'}}, $maxDate); # push later date to second element in the array

    } elsif ($type eq "multi") {
      $self->{'query'}{'dateRange'} = $dates;

    } elsif ($type eq "single") {
      if ($numOfDates > 1) { # single type must have one date
        die "Too many dates provided, must be single date";
      }
      push(@{$self->{'query'}{'dateRange'}}, ${$dates}[0]); # push date to dateRange array

    } else {
      die "Invalid type (single, multi, range)"
    }
  };

  if ($@) {
    $status = 0;
    my $log = new PlugNPay::Logging::DataLog({'collection' => 'stats_query'});
    $log->log({
      'status'       => 'error',
      'error'        => 'Failed to set dates',
      'errorMessage' => $@,
      'package'      => 'PlugNPay::Stats::Query',
      'function'     => 'setDates'
    });
  }
  return $status

}

1;

