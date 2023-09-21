package PlugNPay::Processor::Process::Batch;

use strict;
use PlugNPay::Environment;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Transaction::TransactionProcessor;
use miscutils;
use rsautils;


sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $account = shift;
  $self->setGatewayAccount($account) if $account;

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
  delete $self->{'priority'};
}

sub getGatewayAccount {
  my $self = shift;
  my $env = new PlugNPay::Environment();
  return $self->{'gatewayAccount'} || $env->get('PNP_USER');
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

sub setBatchFile {
  my $self = shift;
  my $data = shift;

  $self->{'data'} = $data;
}

sub getBatchFile {
  my $self = shift;
  return $self->{'data'};
}

sub getMaxTransactions {
  my $self = shift;
  my $gatewayAccount = $self->getGatewayAccount();
  my $count = 15000;
  if ($gatewayAccount eq 'pnpdemo2') {
    $count = 50;
  }

  return $count;
}

sub getPriority {
  my $self = shift;
  my $priority = 0;

  if (!defined $self->{'priority'}) {
    # Grab processing priority from Features
    my $accountFeatures = new PlugNPay::Features($self->getGatewayAccount(),'general');
    if (($accountFeatures->get('upload_batch_priority') > 0) || ($accountFeatures->get('upload_batch_priority') < 0)){
      $priority = $accountFeatures->get('upload_batch_priority');
      $priority = substr($priority, 0, 2);
    }
  }

  $self->{'priority'} = $priority;

  return $priority;
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

sub setEmailAddress {
  my $self = shift;
  my $emailAddress = shift;
  $self->{'emailAddress'} = $emailAddress;
}

sub getEmailAddress {
  my $self = shift;
  return $self->{'emailAddress'};
}

sub setServerName {
  my $self = shift;
  my $serverName = shift;
  $self->{'serverName'} = $serverName;
}

sub getServerName {
  my $self = shift;
  return $self->{'serverName'};
}

sub setFailedTransactions {
  my $self = shift;
  my $failedTransactions = shift;
  $self->{'failedTransactions'} = $failedTransactions;
}

sub getFailedTransactions {
  my $self = shift;
  return $self->{'failedTransactions'};
}

sub setHeaderType {
  my $self = shift;
  my $headerType = lc shift;
  $self->{'headerType'} = $headerType;
}

sub getHeaderType {
  my $self = shift;
  return $self->{'headerType'};
}

sub parseBatchFile {
  my $self = shift;
  my $batch = shift;
  my $parsedBatch;

  if (ref($batch) ne 'ARRAY') {
    # Some filtering
    $batch =~ s/\^/\t/g;
    $batch =~ s/\%09/\t/g;
    $batch =~ s/\r//g;
    my @batchFileRows = split("\n", $batch);  
    $batch = \@batchFileRows;
  }

  return $self->_parseBatchArray($batch);
}

#For todays batcher on the go: preparsed before getting here
sub _parseBatchArray {
  my $self = shift;
  my $batchArray = shift;
  if (ref($batchArray) ne 'ARRAY') {
    die "Invalid batch array data\n";
  }  

  my @batchFileRows = @{$batchArray};
  my @headerRow = ();
  my $header;
 
  if ($batchFileRows[0] =~ /^\!BATCH/i) {
    $header = shift(@batchFileRows);
    @headerRow = split("\t", lc($header));
  } else {
    die "Invalid batch file: no header sent\n";
  }

  my @transArray = ();
  foreach my $line (@batchFileRows) {
    my %rowMap = ();
    my @row = split("\t", $line);
    @rowMap{@headerRow} = @row;
    push @transArray,\%rowMap;
  }

  my $response = {
    'transactions' => \@transArray,
    'header' => $header
  };

  return $response;
}

#Logic Func
sub uploadBatch {
  my $self = shift;
  my $batchFile = shift || $self->getBatchFile();

  my $status = new PlugNPay::Util::Status(1);
  my $batchID = $self->getBatchID();
  my ($batchIDIsUnique, $errorMessage) = $self->validateBatchID($batchID);
  my $data;
  eval {
    $data = $self->parseBatchFile($batchFile);
  };

  if ($batchIDIsUnique && !$@) {
    my $initialOrderID = new PlugNPay::Transaction::TransactionProcessor()->generateOrderID();
    my $currentOrderID = $initialOrderID;
    my $lastOrderID;
    my @dataToInsert = ();
    my $transactionTime = new PlugNPay::Sys::Time()->nowInFormat('gendatetime');
    my $header = $data->{'header'};
    for (my $i = 0; $i < @{$data->{'transactions'}}; $i++) {
      my $encryptedLine = $self->encryptSensitiveData($data->{'transactions'}[$i]);
      my $temp = {
         'orderID'         => $currentOrderID,
         'batchID'         => $batchID,
         'transactionData' => $encryptedLine,
         'transactionTime' => $transactionTime,
         'header'          => $header,
         'merchant'        => $self->getGatewayAccount(),
         'count'           => $i,
         'subAccount'      => $ENV{'SUBACCT'},
         'parseHeaderRow'  => $self->getHeaderType() eq 'true' ? 'yes' : ''
      };
      push @dataToInsert, $temp;  
      $lastOrderID = $currentOrderID;
      $currentOrderID = &miscutils::incorderid($currentOrderID);
    }

    if (!defined $lastOrderID || @dataToInsert == 0) {
      $status->setFalse();
      $status->setError('Invalid batch');
      $status->setErrorDetails('No transactions in batch');
    } elsif (@dataToInsert > $self->getMaxTransactions()) {
      my $count = @dataToInsert;
      $status->setFalse();
      $status->setError('Invalid batch');
      $status->setErrorDetails('Batch greater than maximum batch size. Size: ' . $count . ', Max: ' . $self->getMaxTransactions());
    } else {
      my $saveResponse = $self->saveBatch($batchID, $initialOrderID, $lastOrderID, $header, \@dataToInsert);
      $status = $saveResponse->{'status'};
      $self->setFailedTransactions($saveResponse->{'failedTransactions'});
    }
  } elsif ($@) {
    $status->setFalse();
    $status->setError('Invalid batch file format');
    $status->setErrorDetails($@);
  } else {
    $status->setFalse();
    $status->setError('Invalid batch id');
    $status->setErrorDetails($errorMessage);
  }

  return $status;
}

sub validateBatchID {
  my $self = shift;
  my $batchID = shift || $self->getBatchID();
  
  my $selectString = q/
     SELECT COUNT(batchid) AS `count`
     FROM batchfile
     WHERE batchid = ?
  /;

  my $isUnique = 0;
  my $dbs = new PlugNPay::DBConnection();
  eval {
    my $rows = $dbs->fetchallOrDie('uploadbatch', $selectString, [$batchID], {})->{'result'};
    $isUnique = $rows->[0]{'count'} == 0;
  };

  my $error = '';
  if ($@) {
    $error = $@;
  } elsif (!$isUnique) {
    $error = 'Batch ID is not unique';
  }

  return $isUnique, $error;
}

sub encryptSensitiveData {
  my $self = shift;
  my $data = shift; 
  
  my @sensitiveKeyNames = ('card-number','card_number','card-cvv','card_cvv','accountnum','x_card_num','x_card_code','x_bank_acct_num');
  foreach my $sensitiveKey (@sensitiveKeyNames) {
    if ($data->{$sensitiveKey}) {
      my ($encData,$encLength) = &rsautils::rsa_encrypt_card($data->{$sensitiveKey},'/home/p/pay1/pwfiles/keys/key','log');
      $data->{$sensitiveKey} = $encLength . '|' . $encData;
    }
  }

  return join("\t", values %{$data});
}

# Save Batch data
sub saveBatch {
  my $self = shift;
  my $batchID = shift;
  my $initialOrderID = shift;
  my $finalOrderID = shift;
  my $headerLine = shift;
  my $data = shift;
  my $status = new PlugNPay::Util::Status(1);
  
  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('uploadbatch');
  my $savedBatchDetails;
  my $failedCount = 0;
  eval {
    $savedBatchDetails = $self->saveBatchDetails($batchID, {'startID' => $initialOrderID, 'endID' => $finalOrderID, 'header' => $headerLine});
    if ($savedBatchDetails) {
      $failedCount = $self->saveTransactions($batchID, $headerLine, $data);
    }
  };
  
  if ($@) {
    $dbs->rollback('uploadbatch');
    $self->log({'error' => $@, 'batchID' => $batchID});
    $status->setFalse();
    $status->setError('Failed to save batch');
    $status->setErrorDetails($@);
  } elsif (!$savedBatchDetails) {
    $dbs->rollback('uploadbatch');
    $status->setFalse();
    $status->setError('Failed to save batch');
    $status->setErrorDetails('Batch details failed to save');
  } else {
    $dbs->commit('uploadbatch');
  }

  return {'status' => $status, 'failedTransactions' => $failedCount};
}

sub saveBatchDetails {
  my $self = shift;
  my $batchID = shift;
  my $data = shift;
  my $insertString = q/
      INSERT INTO batchid
      (batchid,trans_time,processid,status,firstorderid,lastorderid,username,headerflag,header,emailflag,emailaddress,hosturl)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
  /;
  my $batchTime = new PlugNPay::Sys::Time()->inFormat('gendatetime');
  my @values = (
      $batchID,
      $batchTime,
      'none',
      'locked',
      $data->{'startID'},
      $data->{'endID'},
      $self->getGatewayAccount(),
      $self->getHeaderType() eq 'true' ? 'yes' : '',
      $data->{'header'},
      $self->getEmailFlag() eq 'true' ? 'yes' : 'no',
      $self->getEmailAddress(),
      $self->getServerName()
  );

  my $dbs = new PlugNPay::DBConnection();
  my $insertedBatch;
  my $sth = $dbs->executeOrDie('uploadbatch', $insertString, \@values)->{'sth'};

  return $sth->rows();
}

# Save Transaction(s)
sub saveTransactions {
  my $self = shift;
  my $batchID = shift;
  my $headerLine = shift;
  my $transactions = shift;
  my @data = ();
  my $errorCount = 0;

  # Bane: Oh, you think garbage coding is your ally. But you merely adopted the garbage; I was born in it, molded by it.
  foreach my $row (@{$transactions}) {
    if (@data < 100) {
      my $temp = [
         $batchID,
         $row->{'transactionTime'},
         $row->{'orderID'},
         'none', #processid
         $row->{'merchant'} || $self->getGatewayAccount(),
         'locked', #status
         $row->{'transactionData'},
         $row->{'subAccount'},
         $self->getPriority()
      ];
      push @data,$temp;
    } else {
      my $saved = 1;
      eval {
        $saved = $self->_insertBatchPartition($batchID, \@data);
      };

      if ($@ || !$saved) {
        $self->log({'batchID' => $batchID, 'error' => $@}) if $@;
        $errorCount += 100;
      }

      @data = ();
    }
  }

  if (@data > 0) {
    my $saved = 1;
    eval {
      $saved = $self->_insertBatchPartition($batchID, \@data);
    };

    if ($@ || !$saved) {
      $self->log({'batchID' => $batchID, 'error' => $@}) if $@;
      $errorCount += @data;
    }
  }

  return $errorCount;
}

sub _insertBatchPartition {
  my $self = shift;
  my $batchID = shift;
  my $dataToInsert = shift;

  my @params = ();
  my @values = ();
  foreach my $transaction (@{$dataToInsert}) {
    push @params, '(' . join(',', map { '?' } @{$transaction}) . ')';
    push @values, @{$transaction};
  }

  my $saved = 0;
  if (@values > 0) {
    my $insertString = 'INSERT INTO batchfile (batchid,trans_time,orderid,processid,username,status,line,subacct,priority) VALUES ' . join(',',@params);
    my $dbs = new PlugNPay::DBConnection();

    $dbs->begin('uploadbatch');
    eval{
      $dbs->executeOrDie('uploadbatch', $insertString, \@values);
    };
  
    if ($@) {
       $self->log($batchID, $@);
       $dbs->rollback('uploadbatch');
    } else {
       $dbs->commit('uploadbatch');
       $saved = 1;
    }
  }

  return $saved;
}

sub finalizeBatch {
  my $self = shift;
  my $batchID = shift || $self->getBatchID();
  my $gatewayAccount = shift || $self->getGatewayAccount();
  my $status = new PlugNPay::Util::Status(1);
  my $dbs = new PlugNPay::DBConnection();

  my $updateTransactions = q/
    UPDATE batchfile
       SET status = 'pending'
     WHERE batchid = ? 
       AND username = ?
       AND status = 'locked'
  /;

  my $updateBatch = q/
    UPDATE batchid
       SET status = 'pending'
     WHERE batchid = ? 
       AND username = ?
       AND status = 'locked'
  /;

  my $effected = 0;
  $dbs->begin('uploadbatch');
  eval {
    my $sth = $dbs->executeOrDie('uploadbatch', $updateTransactions, [$batchID, $gatewayAccount])->{'sth'};
    $effected = $sth->rows();
  };

  if ($@ || $effected == 0) {
    my $error = $@ || 'Invalid batch';
    $dbs->rollback('uploadbatch');
    $status->setFalse();
    $status->setError('Failed to finalize batch');
    $status->setErrorDetails($error);
  } else {
    my $updated = 0;
    eval {
      my $sth = $dbs->executeOrDie('uploadbatch', $updateBatch, [$batchID, $gatewayAccount])->{'sth'};
      $updated = $sth->rows() > 0;
    }; 
    
    if ($@ || !$updated) {
      my $error = $@ || 'Invalid batch selected for update';
      $dbs->rollback('uploadbatch');
      $status->setFalse();
      $status->setError('Failed to finalize batch');
      $status->setErrorDetails($error);
    } else {
      $dbs->commit('uploadbatch');
    }
  }

  return $status;
}

sub deleteBatch {
  my $self = shift;
  my $batchID = shift || $self->getBatchID();
  my $gatewayAccount = shift || $self->getGatewayAccount();
  my $status = new PlugNPay::Util::Status(1);
  my $deleteTransactions = q/
     DELETE FROM batchfile 
           WHERE batchid = ?
             AND username = ?
             AND status = 'locked'
  /;

  my $deleteBatch = q/
     DELETE FROM batchid 
           WHERE batchid = ?
             AND username = ?
             AND status = 'locked'
  /;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('uploadbatch');
  eval {
    $dbs->executeOrDie('uploadbatch', $deleteTransactions, [$batchID, $gatewayAccount]);
    $dbs->executeOrDie('uploadbatch', $deleteBatch, [$batchID, $gatewayAccount]);
  };

  if ($@) {
    $dbs->rollback('uploadbatch');
    $status->setFalse();
    $status->setError('Failed to cancel batch');
    $status->setErrorDetails($@);
  } else {
    $dbs->commit('uploadbatch');
  }

  return $status;
}

#Logging
sub log {
  my $self = shift;
  my $data = shift || {};
  $data->{'gatewayAccount'} = $self->getGatewayAccount();
  
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'uploadbatch'});
  $logger->log($data);
}

1;
