package PlugNPay::Batch::ID;

use strict;
use PlugNPay::Email;
use PlugNPay::Batch::File;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub setBatchID {
  my $self = shift;
  my $batchID = shift;
  $self->{'batchID'} = $batchID;
}

sub getBatchID {
  my $self = shift;
  return $self->{'batchID'};
}

sub setTransTime {
  my $self = shift;
  my $transTime = shift;
  $self->{'transTime'} = $transTime;
}

sub getTransTime {
  my $self = shift;
  return $self->{'transTime'};
}

sub setProcessID {
  my $self = shift;
  my $processID = shift;
  $self->{'processID'} = $processID;
}

sub getProcessID {
  my $self = shift;
  return $self->{'processID'};
}

sub setStatus {
  my $self = shift;
  my $status = shift;
  $self->{'status'} = $status;
}

sub getStatus {
  my $self = shift;
  return $self->{'status'};
}

sub setFirstOrderID {
  my $self = shift;
  my $firstOrderID = shift;
  $self->{'firstOrderID'} = $firstOrderID;
}

sub getFirstOrderID {
  my $self = shift;
  return $self->{'firstOrderID'};
}

sub setLastOrderID {
  my $self = shift;
  my $lastOrderID = shift;
  $self->{'lastOrderID'} = $lastOrderID;
}

sub getLastOrderID {
  my $self = shift;
  return $self->{'lastOrderID'};
}

sub setUsername {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return $self->{'username'};
}

sub setHeader {
  my $self = shift;
  my $header = shift;
  $self->{'header'} = $header;
}

sub getHeader {
  my $self = shift;
  return $self->{'header'};
}

sub setHeaderFlag {
  my $self = shift;
  my $headerFlag = shift;
  $self->{'headerFlag'} = $headerFlag;
}

sub getHeaderFlag {
  my $self = shift;
  return $self->{'headerFlag'};
}

sub setEmailAddress {
  my $self = shift;
  my $emailAddress = shift;
  $self->{'emailAddress'} = $emailAddress;
}

sub getEmailAddress {
  my $self = shift;
  return $self->{'emailAddress'};
}

sub setEmailFlag {
  my $self = shift;
  my $emailFlag = shift;
  $self->{'emailFlag'} = $emailFlag;
}

sub getEmailFlag {
  my $self = shift;
  return $self->{'emailFlag'};
}

sub setHostURL {
  my $self = shift;
  my $hostURL = shift;
  $self->{'hostURL'} = $hostURL;
}

sub getHostURL {
  my $self = shift;
  return $self->{'hostURL'};
}

sub _setBatchDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'batchID'}      = $row->{'batchid'};
  $self->{'transTime'}    = $row->{'trans_time'};
  $self->{'processID'}    = $row->{'processid'};
  $self->{'status'}       = $row->{'status'};
  $self->{'firstOrderID'} = $row->{'firstorderid'};
  $self->{'lastOrderID'}  = $row->{'lastorderid'};
  $self->{'username'}     = $row->{'username'};
  $self->{'headerFlag'}   = $row->{'headerflag'};
  $self->{'header'}       = $row->{'header'};
  $self->{'emailFlag'}    = $row->{'emailflag'};
  $self->{'emailAddress'} = $row->{'emailaddress'};
  $self->{'hostURL'}      = $row->{'hosturl'};
}

sub loadBatch {
  my $self = shift;
  my $batchID = shift; # unique

  my $dbs = new PlugNPay::DBConnection();

  eval {
    my $sth = $dbs->prepare('uploadbatch', q/SELECT batchid,
                                                    trans_time,
                                                    processid,
                                                    status,
                                                    firstorderid,
                                                    lastorderid,
                                                    username,
                                                    header,
                                                    emailflag,
                                                    emailaddress,
                                                    headerflag,
                                                    hosturl
                                             FROM batchid
                                             WHERE batchid = ?/);
    $sth->execute($batchID) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    if (@{$rows} > 0) {
      my $row = $rows->[0];
      $self->_setBatchDataFromRow($row);
    }
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
    $logger->log({
      'batchID'  => $batchID,
      'error'    => $@,
      'module'   => 'PlugNPay::Batch::ID'
    });
  }
}

sub markBatchComplete {
  my $self = shift;
  my $batchID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('uploadbatch', q/UPDATE batchid
                                             SET status = ?
                                             WHERE batchid = ?/);
    $sth->execute('success',
                  $batchID) or die $DBI::errstr;
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
    $logger->log({
      'error'    => $@,
      'batchID'  => $batchID,
      'function' => 'markBatchComplete',
      'module'   => 'PlugNPay::Batch::ID'
    });
  }
}

sub searchForCompleteBatches {
  my $self = shift;
  
  my $dbs = new PlugNPay::DBConnection();

  eval {
    my $sth = $dbs->prepare('uploadbatch', q/SELECT batchid,
                                                    trans_time,
                                                    processid,
                                                    status,
                                                    firstorderid,
                                                    lastorderid,
                                                    username,
                                                    header,
                                                    emailflag,
                                                    emailaddress,
                                                    headerflag,
                                                    hosturl
                                             FROM batchid
                                             WHERE status <> ?/);
    $sth->execute('success') or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});

    my $batches = [];
    foreach my $row (@{$rows}) {
      my $batch = new PlugNPay::Batch::ID();
      $batch->_setBatchDataFromRow($row);

      # if there are no more pending transactions .. the batch is complete
      my $batchFile = new PlugNPay::Batch::File();
      if (!$batchFile->checkPendingTransactions($batch->getBatchID())) {
        # update batch
        $self->markBatchComplete($batch->getBatchID());

        # send email
        $self->sendBatchEmail($batch);
      }
    }
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
    $logger->log({
      'error'    => $@,
      'function' => 'searchForCompleteBatches',
      'module'   => 'PlugNPay::Batch::ID'
    });
  }
}

sub sendBatchEmail {
  my $self = shift;
  my $batch = shift;

  eval {
    my $hostURL = 'pay1.plugnpay.com';
    if ($batch->getHostURL()) {
      $hostURL = $batch->getHostURL();
    }

    my $email = new PlugNPay::Email();
    $email->setTo($batch->getEmailAddress());
    $email->setFrom('support@' . $hostURL);
    $email->setFormat('text');
    $email->setVersion('legacy');
    $email->setGatewayAccount($batch->getUsername());
    $email->setSubject('Batch file results ' . $batch->getBatchID());

    my $content = "The below links will contain the results of your batch upload.\n";
    $content .= "The results can not be accessed directly by clicking on the link in this email.\n";
    $content .= "Please login to your Administration area first, then copy and paste the links into the Address bar at the top of your browser.\n";
    $content .= "\n";
    $content .= "https://" . $hostURL . '/admin/uploadbatch.cgi?function=retrieveresults&batchid=' . $batch->getBatchID() . "\n";
    $content .= "\n";
    $content .= "Success only https://" . $hostURL . '/admin/uploadbatch.cgi?function=retrieveresults&batchid=' . $batch->getBatchID() . "&transtatus=successonly\n";
    $content .= "\n";
    $content .= "Failure only https://" . $hostURL . '/admin/uploadbatch.cgi?function=retrieveresults&batchid=' . $batch->getBatchID() . "&transtatus=failureonly\n";
    $content .= "\n\n";
  
    $email->setContent($content);
    $email->send();
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
    $logger->log({
      'error'    => $@,
      'function' => 'sendBatchEmail',
      'module'   => 'PlugNPay::Batch::ID'
    });
  }
}

1;
