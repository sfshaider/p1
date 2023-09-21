package PlugNPay::Batch;

use strict;
use PlugNPay::Batch::ID;
use PlugNPay::Batch::File;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

#############################
# Subroutine: process
# ---------------------------
# Description:
#   Entry point for batch
#   job.
sub process {
  my $self = shift;
  $self->_process();
  $self->_cleanup();
}

sub _process {
  my $self = shift;

  eval {
    # look for pending batches in the batch file table
    my $batchFile = new PlugNPay::Batch::File();
    $batchFile->loadBatches();
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
    $logger->log({
      'error'    => $@,
      'function' => '_process',
      'module'   => 'PlugNPay::Batch'
    });
  }
}

sub _cleanup {
  my $self = shift;

  eval {
    my $batchID = new PlugNPay::Batch::ID();
    $batchID->searchForCompleteBatches();
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
    $logger->log({
      'error'    => $@,
      'function' => '_cleanup',
      'module'   => 'PlugNPay::Batch'
    });
  }
}

1;
