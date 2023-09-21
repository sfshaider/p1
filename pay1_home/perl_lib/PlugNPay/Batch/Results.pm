package PlugNPay::Batch::Results;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

##################################
# Subroutine: insertBatchResults
# --------------------------------
# Description:
#   Inserts results from the 
# processed transaction in batch.
sub insertBatchResult {
  my $self = shift;
  my $batch = shift;
  my $result = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $status = new PlugNPay::Util::Status();

  eval {
    my $sth = $dbs->prepare('uploadbatch', q/INSERT INTO batchresult
                                             ( batchid,
                                               orderid,
                                               username,
                                               line )
                                             VALUES (?,?,?,?)/);
    $sth->execute($batch->getBatchID(),
                  $batch->getOrderID(),
                  $batch->getUsername(),
                  $result) or die $DBI::errstr; 
    $status->setTrue();
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
    $logger->log({
      'error'    => $@,
      'batch'    => $batch->getBatchID(),
      'username' => $batch->getUsername(),
      'function' => 'insertBatchResults',
      'module'   => 'PlugNPay::Batch::Results'
    });

    $status->setFalse();
  }

  return $status;
}

1;
