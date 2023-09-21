package PlugNPay::Client::Dishout;

use strict;
use JSON::XS;
use MIME::Base64;
use PlugNPay::Merchant;
use PlugNPay::Util::Status;
use PlugNPay::DBConnection;
use PlugNPay::ResponseLink;
use PlugNPay::Logging::DataLog;
use PlugNPay::Merchant::Device;
use PlugNPay::Processor::Account;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::Updater;
use PlugNPay::Processor::SocketConnector;
use PlugNPay::Processor::Process::MessageBuilder;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $merchant = shift || '';
  if ($merchant) {
    my $merchantObj = new PlugNPay::Merchant($merchant);
    $self->setMerchant($merchantObj->getMerchantUsername());
    $self->setMerchantID($merchantObj->getMerchantID());
  }
  
  return $self;
}

sub setTransaction {
  my $self = shift;
  my $transaction = shift;
  $self->{'transaction'} = $transaction;
}

sub getTransaction {
  my $self = shift;
  return $self->{'transaction'};
}

sub setDeviceInfo {
  my $self = shift;
  my $key = shift;
  my $value = shift;
  $self->{'deviceInfo'}{$key} = $value;
}

sub getDeviceInfo {
  my $self = shift;
  return $self->{'deviceInfo'};
}

sub setMerchant {
  my $self = shift;
  my $merchant = shift;
  $self->{'merchant'} = $merchant;
}

sub getMerchant {
  my $self = shift;
  return $self->{'merchant'};
}

sub setMerchantID {
  my $self = shift;
  my $merchantID = shift;
  $self->{'merchantID'} = $merchantID;
}

sub getMerchantID {
  my $self = shift;
  return $self->{'merchantID'};
}

sub performTransaction {
  my $self = shift;
  my $options = shift;
  my $status;

  $status = $self->_isMerchantConfigured($options->{'terminalSerialNumber'});

  if ($status) {
    $status = $self->_createTransaction($options->{'transaction'});
  } 

  return $status;
}


sub _isMerchantConfigured {
  my $self = shift;
  my $terminalSerialNumber = shift;
  my $merchantID = shift || $self->getMerchantID();
  my $terminal = new PlugNPay::Merchant::Device();

  my $status = new PlugNPay::Util::Status(1);
  
  if (!$terminal->doesSerialNumberExist($terminalSerialNumber)) {
    $status->setFalse();
    $status->setError('Configuration Error.');
    $status->setErrorDetails('Serial number does not exist.');
  } elsif (!$terminal->isDeviceConnectedToMerchant($merchantID, $terminalSerialNumber)) {
    $status->setFalse();
    $status->setError('Configuration Error.');
    $status->setErrorDetails('Device is not associated to the merchant specified.');
  } else { 
    $terminal->loadDeviceBySerialNumber($terminalSerialNumber);
    $self->setDeviceInfo('deviceID', $terminal->getDeviceID());
  }
  return $status;
}

sub _createTransaction {
  my $self = shift;
  my $transaction = shift || $self->getTransaction();
  my $merchant = shift || $self->getMerchant();
  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'processor' });
  my @tranState = split('_', $transaction->getTransactionState());

  my $status = new PlugNPay::Util::Status(1);
  my $operation = lc $tranState[0];
  my $errMsg = '';
  my $wasSentForProcessing = 1;
  my $response = {};
  my $process;

  if ($operation eq 'sale' || $operation eq 'credit') {
    $process = new PlugNPay::Processor::Process($operation);
    $transaction->setCustomData($self->getDeviceInfo());
    eval {
      $response = $process->dispatchTransaction($transaction);
    };

    if ($@) {
      $errMsg = 'Failed to connect to processor.';
      $wasSentForProcessing = 0;
    } elsif ($response->{'FinalStatus'} =~ /failure/i) {
      $errMsg = $response->{'MErrMsg'};
      $wasSentForProcessing = 0;
    }
  } else {
    $errMsg = 'Processor does not support ' . $operation . ' transactions';
    $wasSentForProcessing = 0;
  }

  if ($wasSentForProcessing) {     
    my $ssid;
    my $remainingAttempts = 20;
    my $avgTime = $self->getAverageTime($response);
    my $transactionID = $response->{'pnp_transaction_id'};

    while(!$ssid || $remainingAttempts > 0) {
      sleep($avgTime);
      $response = $self->getProcessedTransactions([$transactionID]);
      
      if($response->{$transactionID}{'processor_status'} =~ /problem/) {
        $errMsg = $response->{$transactionID}{'processor_messsage'};
        $self->updateTransaction($response->{$transactionID});
        last;
      } elsif ($response->{$transactionID}{'SSID'}) {
        my $pnpTranID = $response->{$transactionID}{'pnp_transaction_id'};
        $response->{$transactionID}{'transaction_status'} = $response->{$transactionID}{'response_message'};
        $ssid = $response->{$transactionID}{'SSID'};
        $process->cleanupTransactions($transactionID, {$pnpTranID => {'pnp_transaction_id' => $pnpTranID}});

        if (!$self->_storeSSID($ssid,$transactionID,$merchant)) {
          $errMsg = 'Failed to store SSID';
        } 
      }

      $remainingAttempts--;

      if ($remainingAttempts == 0) {
        $errMsg = 'Failed to retrieve SSID from processor.';
      }
    } #End of while
  }

  if ($errMsg) {	  
    $status->setFalse();
    $status->setError('Failed to create transaction.');
    $status->setErrorDetails($errMsg);
    $logger->log({
      'status'    => 'ERROR',
      'message'   => 'Failed to create transaction.',
      'processor' => 'Dishout',
      'function'  => '_createTransaction',
      'module'    => ref($self),
      'error'     => $errMsg
    });
  } 

  return $status;
}

sub updateTransaction {
  my $self = shift;
  my $transactionData = shift;
  my $updater = new PlugNPay::Transaction::Updater();
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'processor' });
  my $transactionID;
  my $isSuccess = 1;

  if (!defined $transactionData->{'OrderId'}) {
    $transactionID = $transactionData->{'pnp_transaction_id'};
    my $errors = $updater->finalizeTransactions({
      $transactionID => {
        'pnp_transaction_id' => $transactionID,
        'wasSuccess'         => $transactionData->{'wasSuccess'},
        'processor_status'   => $transactionData->{'processor_status'},
        'processor_message'  => $transactionData->{'processor_message'},
      }
    });

    if(exists $errors->{$transactionID} && $errors->{$transactionID} == 1) {
      $logger->log({'status' => 'ERROR', 'message' => 'Failed to update transaction.', 'processor' => 'Dishout','pnp_transaction_id' => $transactionID});
      $isSuccess = 0;
    }
  } else {
    my $ssid = $transactionData->{'OrderId'};
    my $data = $self->_loadTransactionID($ssid);
    my $binaryID = $data->{'pnp_transaction_id'};
    my $util = new PlugNPay::Util::UniqueID();

    $util->fromBinary($binaryID);
    $transactionID = $util->inHex();

    my ($wasSuccess, $processorStatus, $processorMessage);
    if ($transactionData->{'Status'} eq 'Approved') {
      $wasSuccess = 'true';
      $processorStatus = 'SUCCESS';
      $processorMessage = 'Successfully processed transaction';
    } else {
      $wasSuccess = 'false';
      $processorStatus = 'FAILURE';
      $processorMessage ='Failed to process transaction';
    }

    my $authorizationCode = $transactionData->{'AuthCode'};
    my $settlementAmount = $transactionData->{'CaptureAmount'};
    my $invoiceNo = $transactionData->{'InvoiceNumber'};
    my $orderDateTime = $transactionData->{'OrderDateTime'};
    my $processorReferenceID = $transactionData->{'PNREF'};
    my $customerID = $transactionData->{'CustomerId'};
    my $approvalCode = $transactionData->{'ApprovalCode'};
    my $maskedCardNumber =  "******". $transactionData->{'CardLast4'};

    $orderDateTime =~ s/^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2}).*/$1 $2/;

    my $details = {
      'processor_order_id'       => $ssid,
      'CustomerId'               => $customerID,
      'ApprovalCode'             => $approvalCode,
      'InvoiceNo'                => $invoiceNo,
      'processor_status'         => $processorStatus,
      'processor_message'        => $processorMessage
    };

    my $errors = $updater->finalizeTransactions({
      $transactionID => {
        'pnp_transaction_id'           => $transactionID,
        'wasSuccess'                   => $wasSuccess,
        'processor_reference_id'       => $processorReferenceID,
        'authorization_code'           => $authorizationCode,
        'processor_transaction_date'   => $orderDateTime,
        'settlement_amount'            => $settlementAmount,
        'additional_processor_details' => $details,
        'masked_card_number'           => $maskedCardNumber
      }
    });

    if (exists $errors->{$transactionID} && $errors->{$transactionID} == 1) {
      $logger->log('status' => 'ERROR', 'message' => 'Failed to update transaction', 'processor' => 'Dishout', 'pnp_transaction_id' => $transactionID);
      $isSuccess = 0;
    }
  }
  return $isSuccess;
}

sub _storeSSID {
  my $self = shift;
  my $ssid = shift;
  my $transactionID = shift;
  my $merchant = shift;

  my $dbh = new PlugNPay::DBConnection();
  my $sth = $dbh->prepare('pnpmisc', q/
                           INSERT INTO slingshot_pending_id (ssid, pnp_transaction_id, merchant)
                           VALUES (?, ?, ?)/);
  eval {
    $sth->execute($ssid, $transactionID, $merchant) or die $DBI::errstr;
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'processor'});
    $logger->log({'status' => 'ERROR', 'message' => 'Failed to insert SSID.', 'processor' => 'Dishout'});
    return 0;
  }
  return 1;
}

sub _loadTransactionID {
  my $self = shift;
  my $ssid = shift; 

  my $dbh = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $query = q/SELECT pnp_transaction_id, merchant 
                FROM slingshot_pending_id
                WHERE ssid = ?/;
  my $sth = $dbh->prepare($query);
  $sth->execute($ssid) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  return $rows->[0];
}

sub getProcessedTransactions {
  my $self = shift;
  my $ids = shift;
  my $loadedInfo = $self->_loadPendingInfo($ids);
  my $transactions = $self->_retreiveTransactions($loadedInfo);
 
  return $transactions;
} 

sub _loadPendingInfo {
  my $self = shift;
  my $ids = shift;
  my $loader = new PlugNPay::Transaction::Loader();
  my $data = {};

  if(ref($ids) eq 'ARRAY') {
    $data = $loader->loadPendingTransactionProcessor($ids);
  } else {
    my @array = ($ids);
    $data = $loader->loadPendingTransactionProcessor(\@array);
  }
  return $data;
}

sub _retreiveTransactions {
  my $self = shift;
  my $loadedInformation = shift;
  my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();
  my $transactions = {};
 
  foreach my $processorID (keys %$loadedInformation) { 
    my $data = $loadedInformation->{$processorID};
    my $JSON = encode_json($messageBuilder->build($data)); 
    my $connector = new PlugNPay::Processor::SocketConnector();
    my $responses = decode_json($connector->connectToProcessor($JSON, $processorID));
    my $responseHash = $responses->{'responses'};
    foreach my $tranID (keys %$responseHash) {
      $transactions->{$processorID} = $responseHash->{$tranID};
    }
  }
  return $transactions;
}

sub removePendingTransaction {
  my $self = shift;
  my $ssid = shift;
  my $dbh = new PlugNPay::DBConnection();

  my $sth = $dbh->prepare('pnpmisc', q/
                           DELETE FROM slingshot_pending_id
                           WHERE ssid = ?/);
  eval {
    $sth->execute($ssid) or die $DBI::errstr;
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'processor'});
    $logger->log({'status' => 'ERROR', 'message' => 'Failed to remove pending transaction with SSID: ' . $ssid, 'processor' => 'Dishout'});
    return 0;
  }
  return 1;
}

sub getAverageTime {
  my $self = shift;
  my $response = shift;
  my $shouldWaitLonger = shift || undef;

  my $avgTime = ($response->{'average_transaction_time'} / 1000);
  if($shouldWaitLonger) {
    $avgTime += .25;
  }
  return $avgTime;
}

#Save for future feature. Will be able to send push notifications straight to device.
sub pushToDevice {
  my $self = shift;
  my $deviceID = shift || $self->getCustomData()->{'deviceID'};
  my $merchant = shift || $self->getMerchant();

  my $rl = new PlugNPay::ResponseLink();

  my $processorAccount = new PlugNPay::Processor::Account({
    'gatewayAccount' => $merchant,
    'processorName' => 'slingshot'
  });

  my $encoded = encode_base64($processorAccount->getSettingValue('mid'). ":" . $processorAccount->getSettingValue('tid'));
  chomp $encoded;

  $rl->setRequestURL('https://getdishout.net/slingshot/PushToDeviceId');
  $rl->setRequestMethod('POST');
  $rl->setRequestHeaders({
    'Authorization' => "Basic " . $encoded,
    'Accept'        => 'application/json'
  });
  $rl->setRequestContentType('application/json');
  $rl->setRequestData({"deviceId" => $deviceID});
  $rl->doRequest();

  my $response = $rl->getResponseContent();
}

1;
