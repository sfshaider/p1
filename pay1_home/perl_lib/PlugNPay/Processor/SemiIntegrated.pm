package PlugNPay::Processor::SemiIntegrated;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Util::UniqueID;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::State;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::Updater;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub setID {
  my $self = shift;
  my $id = shift;
  $self->{'id'} = $id;
}


sub savePendingTransaction {
  my $self = shift;
  my $options = shift;
  my $sysTime = new PlugNPay::Sys::Time();
  my $transID = $options->{'transactionID'};

  if ($transID =~ /^[0-9a-fA-F]+$/) {
    my $uuid = new PlugNPay::Util::UniqueID();
    $uuid->fromHex($transID);
    $transID = $uuid->inBinary();
  }

  my $creationTime = $sysTime->inFormat('iso_gm');
  my $dbs = new PlugNPay::DBConnection();

  my $status = new PlugNPay::Util::Status(1);

  my $sth = $dbs->prepare('pnpmisc', q/
                           INSERT INTO emv_pending_transaction (station_id, pnp_transaction_id, pnp_order_id, amount, terminal_serial_number, transaction_date_time, state, merchant,processor_reference_id)
                           VALUES (?,?,?,?,?,?,?,?,?)
                         /);


  eval {
   $sth->execute($options->{'stationID'},
                 $transID,
                 $options->{'orderID'},
                 $options->{'amount'},
                 $options->{'terminalSerialNumber'},
                 $creationTime,
                 $options->{'state'},
                 $options->{'merchant'},
                 $options->{'processorReferenceID'} || '') or die $DBI::errstr;
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'processor'});
    $logger->log({
      'status'        => 'ERROR',
      'message'       => 'Failed to insert pending connection.',
      'processor'     => 'SemiIntegrated',
      'function'      => 'savePendingTransaction',
      'module'        => 'PlugNPay::Processor::SemiIntegrated',
      'transactionID' => $options->{'transactionID'},
      'error'         => $@
    });
    $status->setFalse();
    $status->setError("Failed to save pending transaction.");
    $status->setErrorDetails($@);
  }
  return $status;
}

#loads all pending transactions for a merchant
sub loadTerminalPendingTransactions {
  my $self = shift;
  my $options = shift;

  my $dbs = new PlugNPay::DBConnection();

  my @params = ();
  push (@params, $options->{'merchant'});
  push (@params, $options->{'terminalSerialNumber'});

  my $query = q/
              SELECT station_id,pnp_transaction_id,pnp_order_id,amount,terminal_serial_number,transaction_date_time,state,merchant,processor_reference_id
              FROM emv_pending_transaction
              WHERE (merchant = ? AND terminal_serial_number = ?) /;

  if ($options->{'startTime'} && $options->{'endTime'}) {
    $query .= 'AND (transaction_date_time BETWEEN ? AND ?)';
    push (@params, $options->{'startTime'});
    push (@params, $options->{'endTime'});
  }

  my $sth = $dbs->prepare('pnpmisc', $query);

  eval {
    $sth->execute(@params) or die $DBI::errstr;
  };

  my $pendingTransactions = [];

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'processor'});
    $logger->log({
      'status'               => 'ERROR',
      'message'              => 'Failed to load pending transactions',
      'processor'            => 'SemiIntegrated',
      'module'               => ref($self),
      'function'             => 'loadTerminalPendingTransactions',
      'merchant'             => $options->{'merchant'},
      'terminalSerialNumber' => $options->{'terminalSerialNumber'},
      'error'                => $@
    });
    return $pendingTransactions;
  }

  my $rows = $sth->fetchall_arrayref({});
  my $uuid = new PlugNPay::Util::UniqueID();
  my $tranID;
  my $orderID;
  if (@{$rows}) {
    foreach my $row (@{$rows}) {
      $uuid->fromBinary($row->{'pnp_transaction_id'});
      $tranID = $uuid->inHex();
      $uuid->fromBinary($row->{'pnp_order_id'});
      $orderID = $uuid->inHex();
      push @{$pendingTransactions}, {
        'stationID'            => $row->{'station_id'},
        'orderID'              => $orderID,
        'transactionID'        => $tranID,
        'amount'               => $row->{'amount'},
        'terminalSerialNumber' => $row->{'terminal_serial_number'},
        'transactionDateTime'  => $row->{'transaction_date_time'},
        'state'                => $row->{'state'},
        'merchant'             => $row->{'merchant'},
        'processorReferenceID' => $row->{'processor_reference_id'}
      };
    } # end of for loop
  }
  return $pendingTransactions;
}

sub removePendingTransaction {
  my $self = shift;
  my $transID = shift;

  if ($transID =~ /^[0-9a-fA-F]+$/) {
    my $uuid = new PlugNPay::Util::UniqueID();
    $uuid->fromHex($transID);
    $transID = $uuid->inBinary();
  }

  my $status = new PlugNPay::Util::Status(1);

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/
                           DELETE FROM emv_pending_transaction
                           WHERE pnp_transaction_id = ?
                         /);

  eval {
    $sth->execute($transID) or die $DBI::errstr;
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'processor'});
    $logger->log({
      'status'            => 'ERROR',
      'message'           => 'Failed to remove pending emv transaction',
      'processor'         => 'SemiIntegrated',
      'function'          => 'removePendingTransaction',
      'module'            => ref($self),
      'pnpTransactionID'  => $transID,
      'error'             => $@
    });
    $status->setFalse();
    $status->setError("Failed to removed pending transaction");
    $status->setErrorDetails($@);
  }
  return $status;
}

sub doesTransactionExist {
  my $self = shift;
  my $transID = shift;

  if ($transID =~ /^[0-9a-fA-F]+$/) {
    my $uuid = new PlugNPay::Util::UniqueID();
    $uuid->fromHex($transID);
    $transID = $uuid->inBinary();
  }

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/ SELECT COUNT(id) as `exist`
                                         FROM emv_pending_transaction
                                         WHERE pnp_transaction_id = ?
                                      /);

  eval {
    $sth->execute($transID) or die $DBI::errstr;
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'processor'});
    $logger->log({
      'status'           => 'ERROR',
      'message'          => 'Failed to check if transaction exist.',
      'processor'        => 'SemiIntegrated',
      'function'         => 'doesTransactionExist',
      'module'           => ref($self),
      'pnpTransactionID' => $transID,
      'error'            => $@
    });
    return 0;
  }
  my $rows = $sth->fetchall_arrayref({});
  if (@{$rows}) {
    return $rows->[0]{'exist'};
  }
}

sub canPerformReturn {
  my $self = shift;
  my $returnTransaction = shift;
  my $processor = shift;

  my $hexID = $returnTransaction->getPNPTransactionReferenceID();
  my $merchant = $returnTransaction->getGatewayAccount();
  my $pnpID = $returnTransaction->getPNPTransactionReferenceID();

  unless ($hexID =~ /^[a-fA-F0-9]+$/) {
    my $uuid = new PlugNPay::Util::UniqueID();
    $uuid->fromBinary($pnpID);
    $hexID = $uuid->inHex();
  }

  my $searchCriteria = [
    {
      'merchant'               => $merchant,
      'pnp_transaction_ref_id' => $pnpID,
      'processor'              => $processor,
      'transaction_state'      => 'CREDIT_PENDING'
    },
    {
      'merchant'               => $merchant,
      'pnp_transaction_ref_id' => $pnpID,
      'processor'              => $processor,
      'transaction_state'      => 'CREDIT'
    }
  ];

  my $loader = new PlugNPay::Transaction::Loader();
  my $transactions = $loader->load($searchCriteria)->{$merchant};
  my $originalTransaction = $loader->load({ 'username' => $merchant, 'transactionID' => $pnpID })->{$merchant}{$hexID};
  my $status = PlugNPay::Util::Status();
  my $errMsg; 

  if (defined $originalTransaction) {
    my $total = 0;

    foreach my $transactionID (keys %{$transactions}) {
      my $transaction = $transactions->{$transactionID};
      if ($transactionID !~ /^$hexID$/ && ref($transaction) =~ /PlugNPay::Transaction::Credit::EMV/ && $transaction->getTransactionState() !~ /void/i) {
        $total += $transaction->getTransactionAmount();
      }
    }

    if ((($originalTransaction->getTransactionAmount() - $total) >= $returnTransaction->getTransactionAmount()) || $originalTransaction->getTransactionAmount() >= $total) {
      $status->setTrue();
    } else {
      $errMsg = 'Return amount cannot be greater than base amount.'; 
    }
  } else {
    $errMsg = 'The original transaction does not exist.';
  }

  if ($errMsg) {
    $self->updateFailedTransaction($returnTransaction);
    $status->setFalse();
    $status->setError('Cannot perform credit transaction.');
    $status->settErrorDetails($errMsg);
    
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'processor'});
    $logger->log({
      'status'    => 'ERROR',
      'message'   => 'Cannot perform credit transaction.',
      'processor' => 'SemiIntegrated',
      'function'  => 'canPerformReturnTransaction',
      'module'    => ref($self),
      'error'     =>  $errMsg 
    });
  }

  return $status;
}

sub canPerformVoid {
  my $self = shift;
  my $transaction = shift;
  my $currentTime = new PlugNPay::Sys::Time();
  my $transactionTime = new PlugNPay::Sys::Time('db_gm',$transaction->getTransactionDateTime());

  $transactionTime->addDays(1);

  return $transactionTime->isAfter($currentTime);
}

sub updateFailedTransaction {
  my $self = shift;
  my $transaction = shift;

  my $updater = new PlugNPay::Transaction::Updater();
  my $transID = $transaction->getPNPTransactionID();
  my $status = new PlugNPay::Util::Status(1);

  if ($transaction->getTransactionState() =~ /^VOID_PENDING$/i) {
    my $stateID = new PlugNPay::Transaction::State()->getTransactionStateID('SALE');
    return $updater->prepareForTransactionAlter({'state' => $stateID, 'pnp_transaction_id' => $transID});
  }

  my $errors = $updater->finalizeTransactions({
    $transID => {
      'pnp_transaction_id' => $transID,
      'wasSuccess'         => 'false'
    }
  });

  if (exists $errors->{$transID} && $errors->{$transID} == 1) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'SemiIntegrated' });
    $logger->log({
      'status'    => 'ERROR',
      'message'   => 'Failed to update transaction',
      'processor' => 'SemiIntegrated',
      'function'  => 'updateFailedTransaction',
      'module'    => ref($self) 
    });
    $status->setFalse();
    $status->setError("Failed to update failed transaction");
    $status->setErrorDetails($@);
  }
  return $status;
}

1;
