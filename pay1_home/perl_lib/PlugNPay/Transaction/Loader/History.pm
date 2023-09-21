package PlugNPay::Transaction::Loader::History;

use strict;
use PlugNPay::Processor;
use PlugNPay::Transaction;
use PlugNPay::DBConnection;
use PlugNPay::Util::UniqueID;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::Logging::Logger;
use PlugNPay::Logging::Performance;
use PlugNPay::Transaction::State;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $transInfo = shift;
  if ($transInfo && ref($transInfo) !~ /^PlugNPay::Transaction/) {
    $self->setTransactionID($transInfo);
  } elsif (ref($transInfo) =~ /^PlugNPay::Transaction/) {
    $self->setTransaction($transInfo);
  }

  return $self;
}

sub setTransactionID {
  my $self = shift;
  my $id = shift;

  $self->{'pnp_transaction_id'} = $id;
}

sub getTransactionID {
  my $self = shift;
  return $self->{'pnp_transaction_id'};
}

sub setTransaction {
  my $self = shift;
  my $transaction = shift;
  if (ref($transaction) =~ /^PlugNPay::Transaction/) {
    $self->{'transaction'} = $transaction;
  }
}

sub getTransaction {
  my $self = shift;
  return $self->{'transaction'};
}

sub getTransactionHistory {
  my $self = shift;
  return $self->loadTransactionHistory(@_);
}

sub loadTransactionHistory {
  my $self = shift;
  my $pnpID = shift || $self->getTransactionID();

  if ($pnpID =~ /^[0-9a-fA-F]+$/) {
    my $uniqueID = new PlugNPay::Util::UniqueID();
    $uniqueID->fromHex($pnpID);
    $pnpID = $uniqueID->inBinary();
  }

  my $logger = new PlugNPay::Transaction::Logging::Logger();
  my $logs =  $logger->loadLogs($pnpID);

  return $logs;
}

sub buildMultiple {
  my $self = shift;
  my $idArray = shift;
  my $logger = new PlugNPay::Transaction::Logging::Logger();

  if (ref($idArray) ne 'ARRAY') {
    return;
  }

  new PlugNPay::Logging::Performance('Before build multiple');
  my $logs =  $logger->loadMultipleLogs($idArray);
  my $history = {};
  my $stateMachine = new PlugNPay::Transaction::State();
  foreach my $pnpID (keys %{$logs}) {
    foreach my $log (@{$logs->{$pnpID}}) {
      if (ref($log) eq 'HASH') {
        my $fullTransState = $stateMachine->getTransactionStateName($log->{'new_state_id'});
        my ($state,$mode) = split('_',$fullTransState);
        my $tempData = {
          'state' => (uc($mode) eq 'READY' ? 'marked' : lc($state)),
          'status' => (lc($mode) ? lc($mode) : 'success'),
          'message' => $log->{'message'}
        };

        if ($mode ne 'PENDING') {
          $history->{$pnpID}{$state} = $tempData;
        }
      }
    }
  }
  new PlugNPay::Logging::Performance('Returning history');

  return $history;
}

sub buildTransactionHistory {
  my $self = shift;
  my $transaction = shift || $self->getTransaction();
  my $processor = new PlugNPay::Processor($transaction->getProcessor());

  if ($processor->usesUnifiedProcessing()) {
    return $self->buildUnifiedHistory($transaction);
  } else {
    return $self->buildLegacyHistory($transaction);
  }
}

#For "new" processors
sub buildUnifiedHistory {
  my $self = shift;
  my $transaction = shift;
  my $logs = $self->loadTransactionHistory($transaction->getPNPTransactionID());

  return $self->_compileLogs($logs,$transaction);
}

sub _compileLogs {
  my $self = shift;
  my $logs = shift;
  my $transaction = shift;
  my $pnpID = $transaction->getPNPTransactionID();
  my $history = {};
  my $dataLog = new PlugNPay::Logging::DataLog({'collection' => 'transaction_history'});

  if ($logs == 0) {
    #Probably was a legacy trans?
    $dataLog->log({'message' => 'No history log found in pnp_transaction', 'username' => $transaction->getGatewayAccount(), 'processor' => $transaction->getProcessor()});
    return {};
  }

  my $stateMachine = new PlugNPay::Transaction::State();
  foreach my $log (@{$logs}) {
    my ($state,$mode) = split('_',$stateMachine->getTransactionStateName($log->{'new_state_id'}));
    if ($log->{'transaction_id'} == $pnpID && uc($mode) eq 'PENDING' && ($state . $mode) ne $transaction->getTransactionState() && $mode ne 'PROBLEM') {
      my $historicTrans = new PlugNPay::Transaction($state, $transaction->getTransactionPaymentType());
      my $status;
      eval {
        $status = $historicTrans->cloneTransactionData($transaction);
        $historicTrans->setTransactionState($state);
        $historicTrans->setTransactionType($self->typeFromState($state));
        if (uc($state) eq 'POSTAUTH') {
          $historicTrans->setPostAuth();
        } elsif (uc($state) eq 'SALE') {
          $historicTrans->setSale();
        }
        $historicTrans->setProcessingPriority($transaction->getProcessingPriority());
        $historicTrans->setExtraTransactionData($transaction->getExtraTransactionData());
      };
      if ($status && !$@ && ref($historicTrans) =~ /^PlugNPay::Transaction::/) {
        $history->{$state} = $historicTrans;
      } else {
        #if error, log
        my $error = ( $@ ? $@ : 'Transaction creation error');
        $dataLog->log({'message' => 'Transaction History error occurred', 'username' => $transaction->getGatewayAccount(), 'error' => $error});
      }
    }
  }

  return $history;
}

sub typeFromState {
  my $self = shift;
  my $state = shift;

  return ($state =~ /VOID|CREDIT/ ? 'credit' : 'authorization');
}

# For "old" processors
sub buildLegacyHistory {
  my $self = shift;
  my $transaction = shift;
  my ($state,$mode) = split('_',$transaction->getTransactionState());
  my $logs = $self->loadLegacyLog($transaction->getOrderID(), $state);
  my $dataLog = new PlugNPay::Logging::DataLog({'collection' => 'transaction_history'});
  my $stateMachine = new PlugNPay::Transaction::State();

  my $history = {};

  if ($logs == 0) {
    #Probably was a legacy trans?
    $dataLog->log({'message' => 'No history log found in pnpdata', 'username' => $transaction->getGatewayAccount(), 'processor' => $transaction->getProcessor()});
    return {};
  }

  foreach my $log (@{$logs}) {
    my $historicTrans = new PlugNPay::Transaction($log->{'operation'}, $transaction->getTransactionPaymentType());
    my $status;
    my $historicState = $stateMachine->translateLegacyOperation($log->{'operation'},'success');
    eval {
      $status = $historicTrans->cloneTransactionData($transaction);
      $historicTrans->setTransactionState($historicState);
      $historicTrans->setTransactionType($self->typeFromState($historicState));
      $historicTrans->setTransactionDateTime($log->{'trans_time'});
      $historicTrans->setTransactionAmount($log->{'amount'});
      $historicTrans->setProcessingPriority($transaction->getProcessingPriority());
      my $extraData = $transaction->getExtraTransactionData();
      $extraData->{'batchID'} = $log->{'result'} if $log->{'result'} =~ /^\d+$/;
      delete $extraData->{'relatedTransactions'};
      $historicTrans->setExtraTransactionData($extraData);
    };
    if ($status && !$@ && ref($historicTrans) =~ /^PlugNPay::Transaction::/) {
      $history->{$historicState} = $historicTrans;
    } else {
      #if error, log
      my $error = ( $@ ? $@ : 'Transaction creation error');
      $dataLog->log({'message' => 'Transaction History error occurred', 'username' => $transaction->getGatewayAccount(), 'error' => $error});
    }
  }

  return $history;
}

sub loadMultipleLegacy {
  my $self = shift;
  my $username = shift;
  my $orderIDs = shift;
  my $history = {};
  if (ref($orderIDs) eq 'ARRAY' && @{$orderIDs} > 0) {
    my $qmarks = join(',',map{'?'} @{$orderIDs});
    my $select = q/
       SELECT orderid, operation, result, batch_time
         FROM trans_log FORCE INDEX (PRIMARY)
        WHERE orderid IN (/ . $qmarks . q/)
          AND username = ?
    /;
    push @{$orderIDs},$username;
    my $rows = [];
    my $dbs = new PlugNPay::DBConnection();
    eval {
      $rows = $dbs->fetchallOrDie('pnpdata', $select, $orderIDs, {})->{'result'};
    };

    if ($@) {
      new PlugNPay::Logging::DataLog({'collection' => 'transaction_history'})->log({
          'message'  => 'Legacy History error occurred',
          'username' => $username,
          'orderIDs' => $orderIDs,
          'error'    => $@
      });
    }

    foreach my $row (@{$rows}) {
      my $orderID = $row->{'orderid'};
      my $operation = $row->{'operation'};
      $history->{$orderID}{$operation . '_batchID'} = $row->{'result'} if $row->{'result'} =~ /^\d+$/;
      $history->{$orderID}{$operation . '_batch_time'} = $row->{'batch_time'} if (defined $row->{'batch_time'} && $row->{'batch_time'} ne '');
    }
  }

  return $history;
}

sub loadLegacyLog {
  my $self = shift;
  my $orderID = shift;
  my $state = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpdata',q/
            SELECT operation, amount, trans_time, trans_type, result
              FROM trans_log
             WHERE orderid = ?
               AND trans_type <> ?
               AND operation <> ?/);
  $sth->execute($orderID,$state,$state) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  return $rows;
}
1;
