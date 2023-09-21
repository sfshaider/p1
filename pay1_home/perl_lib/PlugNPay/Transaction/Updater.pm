package PlugNPay::Transaction::Updater;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::Transaction;
use PlugNPay::DBConnection;
use PlugNPay::Processor::ID;
use PlugNPay::Util::UniqueID;
use PlugNPay::Processor::Process;
use PlugNPay::Transaction::State;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::Vehicle;
use PlugNPay::Transaction::Logging::Logger;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::DetailKey;
use PlugNPay::Transaction::Logging::Logger;
use PlugNPay::Processor::Account;
use PlugNPay::Util::Status;
use PlugNPay::Util::UniqueID;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

# Used For logging now
sub updatePendingTransactions { #used for multiple transactions
  my $self = shift;
  my $data = shift;
  my $idFormatter = new PlugNPay::Util::UniqueID();
  my $processHandler = new PlugNPay::Processor::Process();
  my @responseData = ();
  foreach my $key (keys %{$data}) {
    my $codedItem = $data->{$key};
    my $item = $processHandler->decodePendingTransaction($codedItem);

    my $preparedData = {
                        'pnp_transaction_id'   => $item->{'pnp_transaction_id'},
                        'transaction_state_id' => $item->{'transaction_state_id'}
                        };

    $self->logPendingTransaction($preparedData);
    push @responseData,$preparedData;
  }

  return \@responseData;
}

sub logPendingTransaction {
  my $self = shift;
  my $data = shift;
  my $logger = new PlugNPay::Transaction::Logging::Logger();
  $logger->log(
               {
                'transaction_id'    => $data->{'pnp_transaction_id'},
                'message'           => 'Transaction was sent for processing.',
                'previous_state_id' => '14',
                'new_state_id'      => $data->{'transaction_state_id'}
               });

  return 1;
}

# Used for when we can't connect VIA socket to java, send to problem state #
# Similar to finalize, but generates results on the fly                    #
# Also used to fail forceauth transactions                                 #
sub failPendingTransactions {
  my $self = shift;
  my $transactions = shift;
  my $errorMessage = shift || 'Could not connect to processor';
  my $uniqueID = new PlugNPay::Util::UniqueID();
  my $stateObj = new PlugNPay::Transaction::State();
  my $dbs = new PlugNPay::DBConnection();
  my $logger = new PlugNPay::Transaction::Logging::Logger();
  my $error = {};
  foreach my $key (keys %{$transactions}) {
    my $transaction = $transactions->{$key};
    my $pnpID = $transaction->{'transactionData'}{'pnp_transaction_id'};
    my $previousState = $transaction->{'transactionData'}{'transaction_state_id'};
    my $newState = $stateObj->getNextState($previousState,'false');
    $dbs->begin('pnp_transaction');
    eval {
      $uniqueID->fromHex($pnpID);
      my $sth = $dbs->prepare('pnp_transaction',q/
                               UPDATE `transaction`
                               SET transaction_state_id = ?
                               WHERE pnp_transaction_id = ? /);
      $sth->execute($newState, $uniqueID->inBinary()) or die $DBI::errstr;
      $self->saveAdditionalProcessorDetails($pnpID,$newState,{'processor_message' => $errorMessage, 'processor_status' => 'problem'});
    };

    if ($@) {
      $dbs->rollback('pnp_transaction');

      $logger->log({'transaction_id' => $pnpID,
                  'previous_state_id' => $previousState, 'new_state_id' => $previousState,
                  'message' => 'Failed to process because "' . $errorMessage . '", DB update failed: ' . $@});
      $error->{$pnpID} = 1;
    } else {
      $dbs->commit('pnp_transaction');
      $logger->log({'transaction_id' => $pnpID,
                  'previous_state_id' => $previousState, 'new_state_id' => $newState,
                  'message' => 'Failed to process because "' . $errorMessage . '", moved to failed state'});
    }
  }

  return $error;
}

# Used after we receive response from processor #
sub finalizeTransactions {
  my $st = new PlugNPay::Util::StackTrace();
  my $self = shift;
  my $data = shift;
  # my $uniqueID = new PlugNPay::Util::UniqueID();
  my $stateObj = new PlugNPay::Transaction::State();
  my $vehicleObj = new PlugNPay::Transaction::Vehicle();
  my $emvID = $vehicleObj->getTransactionVehicleID('emv');
  my $dbs = new PlugNPay::DBConnection();
  my $logger = new PlugNPay::Transaction::Logging::Logger();
  my $error = {};
  foreach my $transactionKey (keys %{$data}) {
    my $transaction = $data->{$transactionKey};
    my $pnpID = $transaction->{'pnp_transaction_id'};
    my $pnpID = PlugNPay::Util::UniqueID::fromHexToBinary($pnpID);
    my $vehicleID = $transaction->{'transaction_vehicle_id'};
    if (!defined $vehicleID) {
      $vehicleID = $self->_loadVehicleID($pnpID);
    }

    my $previousState = $transaction->{'transaction_state_id'};
    if (!defined $previousState) {
      $previousState = $self->_loadStateID($pnpID);
    }
    my $processorRefID = $transaction->{'processor_reference_id'};
    my $successStatus = $transaction->{'wasSuccess'};
    my $nextState = $stateObj->getNextState($previousState,$successStatus);
    my $refID = $transaction->{'pnp_transaction_ref_id'};

    $logger->log({'transaction_id' => $pnpID,
                  'transaction_ref_id' => $refID,
                  'previous_state_id' => $previousState, 'new_state_id' => $nextState,
                  'message' => 'Processor responded with message: "' . $transaction->{'processor_message'} . '" and Status: ' . $transaction->{'processor_status'}});
    $dbs->begin('pnp_transaction');
    my $time = new PlugNPay::Sys::Time();
    eval {
      my $formattedDateTime = $time->inFormatDetectType('iso_gm',$transaction->{'transaction_date_time'});
      if (!$formattedDateTime) {
        $formattedDateTime = $time->nowInFormat('iso_gm');
      }

      $dbs->executeOrDie('pnp_transaction',q/
        UPDATE `transaction`
        SET authorization_code = ?,
            processor_token = ?,
            vendor_token = ?,
            transaction_state_id = ?,
            processor_transaction_date_time = ?
        WHERE pnp_transaction_id = ?
      /,[
        $transaction->{'authorization_code'},$transaction->{'processor_token'},
        $transaction->{'vendor_token'},$nextState,$formattedDateTime,$pnpID
      ]);

      my $vehicle = $vehicleObj->getTransactionVehicleName($transaction->{'transaction_vehicle_id'});
      if ($vehicle eq 'card' || $vehicle eq 'gift') {
        my $csth = $dbs->prepare('pnp_transaction',q/UPDATE card_transaction
                                  SET cvv_response = ?, avs_response = ?
                                  WHERE pnp_transaction_id = ?/);
        $csth->execute($transaction->{'cvv_response'},$transaction->{'avs_response'},$pnpID) or $self->log({'message' => 'update error','error' => $DBI::errstr});
      }
      $self->saveAdditionalProcessorDetails($pnpID,$nextState,{
        'processor_reference_id' => $processorRefID,
        'processor_message' => $transaction->{'processor_message'},
        'processor_status' => $transaction->{'processor_status'},
        %{($transaction)->{'additional_processor_details'} || {}}
      });

      $self->updateAccountCodes($pnpID,$previousState,$nextState);
      if ($vehicleID == $emvID) {
        $self->addEMVData($pnpID,$transaction);
      }
    };

    if ($@) {
      $logger->log({'transaction_id'     => $pnpID,
                    'transaction_ref_id' => $refID,
                    'previous_state_id'  => $nextState,
                    'new_state_id'       => $previousState,
                    'error'              => $@,
                    'message'            => 'an error occured while updating, rolling back. Processor ID: ' . $transaction->{'processor_reference_id'}});
      $error->{$pnpID} = 1;
      $dbs->rollback('pnp_transaction');
    } else {
      $dbs->commit('pnp_transaction');
    }
  }

  return $error;
}

sub finishSettlingTransactions {
  my $self = shift;
  my $data = shift;
  my $uniqueID = new PlugNPay::Util::UniqueID();
  my $stateObj = new PlugNPay::Transaction::State;
  my $vehicleObj = new PlugNPay::Transaction::Vehicle();
  my $dbs = new PlugNPay::DBConnection();
  my $logger = new PlugNPay::Transaction::Logging::Logger();
  my $error = {};

  if (ref($data) eq 'HASH') {
    my @tempArray = values %{$data};
    $data = \@tempArray;
  }

  foreach my $transaction (@{$data}) {
    my $pnpID = $transaction->{'pnp_transaction_id'};
    if ($pnpID =~ /^[a-fA-F0-9]+$/) {
      $uniqueID->fromHex($pnpID);
      $pnpID = $uniqueID->inBinary();
    }

    my $vehicleID = $transaction->{'transaction_vehicle_id'};
    if (!defined $vehicleID) {
      $vehicleID = $self->_loadVehicleID($pnpID);
    }

    my $previousState = $transaction->{'transaction_state_id'};
    if (!defined $previousState) {
      $previousState = $self->_loadStateID($pnpID,$transaction->{'transaction_vehicle_id'});
    }

    my $processorRefID = $transaction->{'processor_reference_id'};
    my $successStatus = $transaction->{'wasSuccess'};
    my $nextState = $stateObj->getNextState($previousState,$successStatus);
    my $refID = $transaction->{'pnp_transaction_ref_id'};

    $logger->log({'transaction_id'     => $pnpID,
                  'transaction_ref_id' => $refID,
                  'previous_state_id'  => $previousState,
                  'new_state_id'       => $nextState,
                  'message'            => 'Processor responded with message: "' . $transaction->{'processor_message'} . '" and Status: ' . $transaction->{'processor_status'}});

    $dbs->begin('pnp_transaction');
    my $time = new PlugNPay::Sys::Time;
    eval {
      my $formattedDateTime = $time->inFormatDetectType('iso_gm',$transaction->{'transaction_date_time'});
      if (!$formattedDateTime) {
        $formattedDateTime = $time->nowInFormat('iso_gm');
      }

      my $sth = $dbs->prepare('pnp_transaction',q/
                               UPDATE `transaction`
                               SET
                                   processor_token = ?,
                                   vendor_token = ?,
                                   transaction_state_id = ?,
                                   processor_settlement_date_time = ?,
                                   settled_amount = ?,
                                   settled_tax_amount = ?
                               WHERE pnp_transaction_id = ? AND transaction_state_id = ? /);

      my $settledAmount = $transaction->{'processor_transaction_amount'} || $transaction->{'settled_amount'};
      my $settledTaxAmount = $transaction->{'processor_transaction_tax_amount'} || $transaction->{'settled_tax_amount'};
      $sth->execute($transaction->{'processor_token'},
                    $transaction->{'vendor_token'},
                    $nextState,
                    $formattedDateTime,
                    $settledAmount,
                    $settledTaxAmount,
                    $pnpID,
                    $previousState) or $self->log({'message' => 'update error','error' =>$DBI::errstr});
      my $vehicle = $vehicleObj->getTransactionVehicleName($transaction->{'transaction_vehicle_id'});
      $self->saveAdditionalProcessorDetails($pnpID,$nextState,{'processor_reference_id' => $processorRefID});
      $self->saveAdditionalProcessorDetails($pnpID,$nextState,{'processor_message' => $transaction->{'processor_message'}, 'processor_status' => $transaction->{'processor_status'}});
      $self->saveAdditionalProcessorDetails($pnpID,$nextState,$transaction->{'additional_processor_details'});
    };

    if ($@) {
      $logger->log({'transaction_id'     => $pnpID,
                    'transaction_ref_id' => $refID,
                    'previous_state_id'  => $nextState, 'new_state_id' => $previousState,
                    'message'            => 'an error occured while updating, rolling back. Processor ID: ' . $transaction->{'processor_reference_id'}});
      $error->{$pnpID} = 1;
      $dbs->rollback('pnp_transaction');
      $self->log({'message' => 'update error','error' =>$@});
    } else {
      $dbs->commit('pnp_transaction');
    }
  }

  return $error;
}

# Why in Updater and not saver? Because we are 'updating' an existsing transaction with these
# Saving processor details #
sub saveAdditionalProcessorDetails {
  my $self = shift;
  my $transID = shift;
  my $stateID = shift;
  my $details = shift;
  my @values = ();
  my @params = ();

  if ($transID =~ /^[0-9a-fA-F]+$/) {
    my $uuid = new PlugNPay::Util::UniqueID();
    $uuid->fromHex($transID);
    $transID = $uuid->inBinary();
  }

  my $detailKeyObj = new PlugNPay::Transaction::DetailKey();

  foreach my $extraDetail (keys %{$details}) {
    my $keyID = $detailKeyObj->getDetailKeyID($extraDetail);
    my $value = $details->{$extraDetail};
    if (defined $value) {
      push @values,$transID;
      push @values,$stateID;
      push @values,$keyID;
      push @values,$value;
      push @params,'(?,?,?,?)';
    }
  }

  my $insert = 'INSERT IGNORE INTO transaction_additional_processor_detail
                (transaction_id,transaction_state_id,key_id,`value`)
                VALUES ' . join(',',@params);

  if (@values > 0) {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnp_transaction',$insert);
    $sth->execute(@values) or die $DBI::errstr;

    return 1;
  } else {
    return 0;
  }
}

# Settlement #
sub loadTransactionsToSettle {
  my $self = shift;
  my $timeOrOptions = shift;

  my ($query,$values) = $self->_generateLoadTransactionsToSettleQuery($timeOrOptions);

  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('pnp_transaction',$query);
  $sth->execute(@{$values}) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});

  my @transactionsToLoad = ();
  foreach my $row (@{$rows}) {
    push @transactionsToLoad, {'pnp_transaction_id' => $row->{'pnp_transaction_id'}};
  }

  my $loader = new PlugNPay::Transaction::Loader();
  my $transHash = $loader->unifiedLoad(\@transactionsToLoad);

  return $transHash;
}

sub _generateLoadTransactionsToSettleQuery {
  my $self = shift;
  my $timeOrOptions = shift; # time for backwards compatibility, options for ... options

  my $time; # time to search up to to settle, i.e. cutoff
  my $username;
  my $transactionIds; # array ref of transaction ids

  my @values;

  my $id = new PlugNPay::Transaction::State()->getStates->{'POSTAUTH_READY'};
  push @values,$id;

  if (ref($timeOrOptions) eq 'HASH') {
    $time = $timeOrOptions->{'time'};
    $username = $timeOrOptions->{'gatewayAccount'};
    $transactionIds = $timeOrOptions->{'transactionId'} || $timeOrOptions->{'transactionIds'};
    if ($transactionIds && ref($transactionIds) ne 'ARRAY') {
      $transactionIds = [$transactionIds];
    }
  } else {
    $time = $timeOrOptions;
  }

  my $uuid = new PlugNPay::Util::UniqueID();
  if (!defined $time && ref($timeOrOptions) ne 'HASH') { # preserving original functionality
    $time = new PlugNPay::Sys::Time()->nowInFormat('iso_gm');
  }

  my $usernameJoin = '';
  my $usernameConstraint = '';
  my $timeConstraint = '';
  my $transactionIdConstraint = '';

  if ($username) {
    $usernameJoin = ', `merchant`, `order`';
    $usernameConstraint = 'AND merchant.identifier = ? AND merchant.id = order.merchant_id and order.pnp_order_id = transaction.pnp_order_id';
    # $usernameConstraint = 'WHERE merchant.identifier = ? AND merchant.id = order.merchant_id and order.pnp_order_id = transaction.pnp_order_id';

    push @values,$username;
  }

  if ($time) {
    $timeConstraint = 'AND settlement_mark_date_time <= ?';
    push @values,$time;
  } elsif ($transactionIds && @{$transactionIds} > 0) {
    my $uniqueID = new PlugNPay::Util::UniqueID();
    my @binaryIds = map { $uniqueID->fromHex($_); $uniqueID->inBinary() } @{$transactionIds};
    $transactionIdConstraint = 'AND pnp_transaction_id in (' . join(',',map { '?' } @binaryIds) . ')';
    @values = (@values,@binaryIds);
  }

  my $query = qq/
    SELECT pnp_transaction_id,settlement_mark_date_time, settlement_amount
    FROM `transaction` $usernameJoin
    WHERE transaction_state_id = ?
    $timeConstraint
    $usernameConstraint
    $transactionIdConstraint
  /;

  return ($query,\@values);
}

sub addToSettlementJob {
  my $self = shift;
  my $transactions = shift;
  my $time = new PlugNPay::Sys::Time();
  my $uuid = new PlugNPay::Util::UniqueID();
  my $status = new PlugNPay::Util::Status();

  my $insert = "INSERT INTO mark_settlement_job
                (job_id,pnp_transaction_id,settlement_mark_date_time,settlement_amount)
                VALUES ";

  my @values = ();
  my @params = ();
  my $batchIDHash = {};
  foreach my $transaction (@{$transactions}) {
    push @params,' (?,?,?,?) ';
    push @values,$uuid->inBinary();
    push @values,$transaction->{'pnp_transaction_id'};
    push @values,$time->nowInFormat('iso_gm');
    push @values,$transaction->{'settlement_amount'};
    $batchIDHash->{$transaction->{'pnp_transaction_id'}} = $uuid->inHex();
  }

  if (@params > 0) {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $sth = $dbs->prepare('pnp_transaction',$insert . join(',',@params));
      $sth->execute(@values) or die $DBI::errstr;
      $sth->finish();
    };

    if ($@) {
      $self->log({'message' => 'Settlement Mark Job error','error' =>$@});
      $status->setFalse();
      $status->setError('Settlement Mark Job error');
      $status->setErrorDetails($@);
    } else {
      $status->setTrue();
    }

    $self->_logJobBatchIDs($batchIDHash);
  } else {
    $self->log({'message' => 'Settlement Mark Job error','error' =>'No transactions sent!'});
    $status->setFalse();
    $status->setError('Settlement Mark Job error');
    $status->setErrorDetails('No transactions sent');
  }

  return $status;
}

sub markForSettlement {
  my $self = shift;
  my $transData = shift;
  my $formatter = new PlugNPay::Transaction::Formatter();
  my $dbs = new PlugNPay::DBConnection();
  my $uuid = new PlugNPay::Util::UniqueID();
  my $stateMachine = new PlugNPay::Transaction::State();
  my $response = 0;
  my @transactionsToMark = ();

  if (ref($transData) eq 'ARRAY') {
    foreach my $transaction (@{$transData}) {
      my $transactionID;
      if (ref($transaction) eq 'HASH'){
        $transactionID = $transaction->{'pnp_transaction_id'};
      } else {
        $transactionID = $transaction;
      }

      if ($transactionID =~ /^[a-zA-Z0-9]+$/) {
        $uuid->fromHex($transactionID);
        $transactionID = $uuid->inBinary();
      }

      my $previousState = $self->_loadStateID($transactionID);
      if ($stateMachine->checkNextState($previousState,'POSTAUTH_READY')) {
        if (ref($transaction) eq 'HASH'){
          push @transactionsToMark,{'pnp_transaction_id' => $transactionID, 'settlement_amount' => $transaction->{'settlement_amount'}};
        } else {
          push @transactionsToMark,{'pnp_transaction_id' => $transactionID};
        }
      }
    }

    my $sortedTransactions = $self->checkIndustryCode(\@transactionsToMark);
    $response = $self->addToSettlementJob($sortedTransactions);

  } else {
    $response = $self->_markForSettlement($transData);
    return $response->[0];
  }

  return $response;
}

sub _markForSettlement {
  my $self = shift;
  my $transData = shift;

  my $transactionID;
  if (ref($transData) eq 'HASH'){
    $transactionID = $transData->{'pnp_transaction_id'};
  } else {
    $transactionID = $transData;
  }

  $transactionID = PlugNPay::Util::UniqueID::fromHexToBinary($transactionID);
  my $stateMachine = new PlugNPay::Transaction::State();

  my $previousState = $self->_loadStateID($transactionID);
  my $transactionToMark = [];
  if ($stateMachine->checkNextState($previousState,'POSTAUTH_READY')) {
    if (ref($transData) eq 'HASH'){
      $transactionToMark = [{'pnp_transaction_id' => $transactionID, 'settlement_amount' => $transData->{'settlement_amount'}}];
    } else {
      $transactionToMark = [{'pnp_transaction_id' => $transactionID}];
    }
  }

  my $sortedTransaction = $self->checkIndustryCode($transactionToMark);
  return $self->markSettlement($sortedTransaction);
}

sub checkIndustryCode {
  my $self = shift;
  my $transactionsToMark = shift;
  if (ref($transactionsToMark) ne 'ARRAY') {
    return [];
  }

  my $select = 'SELECT t.pnp_transaction_id,t.amount,o.pnp_order_id,m.identifier,p.processor_code_handle
                FROM `transaction` t, `order` o, `merchant` m, `processor` p
                WHERE ';

  my $whereClause = ' (t.pnp_order_id = o.pnp_order_id
                  AND o.merchant_id = m.id
                  AND t.processor_id = p.id
                  AND t.pnp_transaction_id = ?) ';

  my @params = ();
  my @values = ();
  my $idAmountHash = {};
  foreach my $transaction (@{$transactionsToMark}) {
    push @params,$whereClause;
    push @values,$transaction->{'pnp_transaction_id'};
    if (defined $transaction->{'settlement_amount'}) {
      $idAmountHash->{$transaction->{'pnp_transaction_id'}} = $transaction->{'settlement_amount'};
    }
  }

  my @response = ();
  unless (@params > 0 && @values > 0) {
    return [];
  }
  my $dbs = new PlugNPay::DBConnection();
  my $processorIDObj = new PlugNPay::Processor::ID();
  my $sth = $dbs->prepare('pnp_transaction',$select . join(' OR ', @params));
  $sth->execute(@values) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my @responses = ();
  foreach my $row (@{$rows}) {
    my $transactionAmount = $row->{'amount'};
    if ($idAmountHash->{$row->{'pnp_transaction_id'}} && ($idAmountHash->{$row->{'pnp_transaction_id'}} > $row->{'amount'})) {
      my $account = new PlugNPay::Processor::Account(
                                                     {
                                                      'gatewayAccount' => $row->{'merchant'},
                                                      'processorID' => $processorIDObj->getProcessorID($row->{'processor_code_handle'})
                                                     }
                                                    );
      my $settings = $account->getSettings();
      if (defined $settings->{'industrycode'} && lc($settings->{'industrycode'}) eq 'restaurant') {
        $transactionAmount = $idAmountHash->{$row->{'pnp_transaction_id'}};
      }
      push @responses, {'pnp_transaction_id' => $row->{'pnp_transaction_id'}, settlement_amount => $transactionAmount};
    } else {
      push @responses, {'pnp_transaction_id' => $row->{'pnp_transaction_id'}, settlement_amount => ( $idAmountHash->{$row->{'pnp_transaction_id'}} ? $idAmountHash->{$row->{'pnp_transaction_id'}} : $transactionAmount)};
    }

  }

  return \@responses;
}

# Private Functions #
# markSettlement:
#   input: Hash Ref
#          {
#            pnp_transaction_id: <id>,
#            gaatewayAccountMerchantId: <id>,
#            settlement_amount: <amount> (optional)
#          }
#   output: status object
sub markSettlement {
  my $self = shift;
  my $transactionData = shift;

  # POSTAUTH_READY means the transaction may be picked up for settlement
  # POSTAUTH_PENDING means the transaction is in the process of settling
  # POSTAUTH_READY may only be entered from a previous stat of AUTH as of this
  # writing
  # Updating to POSTAUTH_READY is enforced by updating where the current state
  # allows transition to it.
  my $stateMachine = new PlugNPay::Transaction::State();
  my $postauthReadyId = $stateMachine->getStates()->{'POSTAUTH_READY'};
  my $allowedPreviousStates = $stateMachine->getAllowedPreviousStateIds($postauthReadyId);
  my $transactionStateIdIn = join(',',map { '?' } @{$allowedPreviousStates});
  my $time = new PlugNPay::Sys::Time();

  my $update = 'UPDATE `transaction`
                   SET transaction_state_id = ?, settlement_mark_date_time = ?, settlement_amount = COALESCE(?,amount)
                 WHERE pnp_transaction_id = ?
                   AND transaction_state_id IN (' . $transactionStateIdIn . ')';

  my $settlementMarkTime = $time->nowInFormat('iso_gm');
  my $transactionId = PlugNPay::Util::UniqueID::fromHexToBinary($transactionData->{'transactionId'});

  my $settlementAmount = $transactionData->{'settlementAmount'};
  my @values = ($postauthReadyId,$settlementMarkTime,$settlementAmount,$transactionId,@{$allowedPreviousStates});

  my $sth;
  my $status = new PlugNPay::Util::Status(0);
  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('pnp_transaction',$update,\@values);
    my $validationResponse = $dbs->fetchallOrDie('pnp_transaction','SELECT transaction_state_id FROM `transaction` WHERE pnp_transaction_id = ?', [$transactionId],{});
    if ($validationResponse && $validationResponse->{'result'}) {
      my $newState = $validationResponse->{'result'}[0]{'transaction_state_id'};
      if ($newState != $postauthReadyId) {
        $status->setFalse();
        $status->setError('transaction not updated.  either the transaction id is incorrect or the state does not permit a change to POSTAUTH_READY')
      }
    }
    $status->setTrue();
  };

  if ($@) {
    $self->log({'message' => 'Settlement error','error' => $@});
    $status->setFalse();
    $status->setError('Settlement error');
    $status->setErrorDetails($@);
  }

  return $status;
}

sub _logJobBatchIDs {
  my $self = shift;
  my $batchIDHash = shift || {};

  my $dbs = new PlugNPay::DBConnection();
  eval {
     my @values = ();
     my @params = ();
     my $detailKeyObj = new PlugNPay::Transaction::DetailKey();
     my $state = new PlugNPay::Transaction::State();
     my $keyID = $detailKeyObj->getDetailKeyID('pnp_batch_id');
     foreach my $transactionID (keys %{$batchIDHash}) {
       push @values, ($transactionID, $state->getTransactionStateID('POSTAUTH_READY'), $keyID, $batchIDHash->{$transactionID});
       push @params, '(?,?,?,?)';
     }
     my $insert = q/
       INSERT INTO transaction_additional_processor_detail
       (`transaction_id`, `transaction_state_id`, `key_id`, `value`)
       VALUES / . join(',',@params);
     $dbs->executeOrDie('pnp_transaction',$insert, \@values);
  };

  return !$@;
}

sub updateSettlementJobs {
  my $self = shift;
  my $ids = $self->getJobs();

  my $dbs = new PlugNPay::DBConnection();

  my $jobResponse = {};
  my $uuid = new PlugNPay::Util::UniqueID();
  my @deleteArray = ();
  foreach my $id (keys %{$ids}) {
    my $jobStatus = 1;
    $dbs->begin('pnp_transaction');
    foreach my $transaction (@{$ids->{$id}}) {
      my $response = $self->markSettlement($transaction);
      $uuid->fromBinary($transaction->{'pnp_transaction_id'});
      $jobResponse->{$id}{$uuid->inHex()} = $response;
      $jobStatus *= $response->getStatus();
    }
    if ($jobStatus) {
      $dbs->commit('pnp_transaction');
      push @deleteArray,$id; #only delete on successful job
    } else {
      $dbs->rollback('pnp_transaction');
    }

    $jobResponse->{$id}{'status'} = $jobStatus;
  }

  $self->deleteJobs(\@deleteArray);

  my @jobKeys = keys %{$jobResponse};
  if (@jobKeys > 0) {
    $self->logJob($jobResponse);
  }


  return $jobResponse;
}

sub getJobs {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/SELECT job_id,
                                  pnp_transaction_id,
                                  settlement_mark_date_time,
                                  settlement_amount
                           FROM mark_settlement_job
                          /);
  $sth->execute() or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $idHash = {};
  my $uuid = new PlugNPay::Util::UniqueID();
  foreach my $row (@{$rows}) {
    $uuid->fromBinary($row->{'job_id'});
    my $jobID = $uuid->inHex();
    if (defined $idHash->{$jobID}) {
      push @{$idHash->{$jobID}},$row;
    } else {
      my $array = [$row];
      $idHash->{$jobID} = $array;
    }
  }

  return $idHash;
}

sub logJob {
  my $self = shift;
  my $data = shift;

  my $logger = new PlugNPay::Transaction::Logging::Logger();
  $logger->jobLog($data);

  return 1;
}

sub deleteJobs {
  my $self = shift;
  my $data = shift;
  my $status = new PlugNPay::Util::Status(1);

  if (@{$data} > 0) {
    my @params = ();
    my @values = ();
    my $uuid = new PlugNPay::Util::UniqueID();

    foreach my $id (@{$data}) {
      if ($id =~ /^[a-fA-F0-9]+$/) {
        $uuid->fromHex($id);
        push @values,$uuid->inBinary();
      } else {
        push @values,$id;
      }

      push @params, ' (job_id = ?) ';
    }

    my $dbs = new PlugNPay::DBConnection();
    if (@params > 0) {
      eval {

        my $sth = $dbs->prepare('pnp_transaction',q/DELETE FROM mark_settlement_job
                                                WHERE / . join(' OR ',@params));
        $sth->execute(@values) or die $DBI::errstr;
      };

      if ($@) {
        $status->setFalse();
        $status->setError('Error deleting settlment jobs');
        $status->setErrorDetails($@);
      }
    } else {
      $status->setFalse();
    }
  }

   return $status;
}

sub getAmountToSettle {
  my $self = shift;
  my $pnpID = shift;

  if ($pnpID =~ /^[a-fA-F0-9]+$/) {
    my $uuid = new PlugNPay::Util::UniqueID();
    $uuid->fromHex($uuid);
    $pnpID = $uuid->inBinary();
  }

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/SELECT amount,settlement_amount
                            FROM `transaction`
                            WHERE pnp_transaction_id = ? /);
  $sth->execute($pnpID) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});

  my $currentTrans = $rows->[0];
  my $amount = $currentTrans->{'amount'};
  if (defined $currentTrans->{'settlement_amount'} && $currentTrans->{'settlement_amount'} =~ /\d+.\d+/) {
    $amount = $currentTrans->{'settlement_amount'};
  }

  return $amount;
}

sub prepareForTransactionAlter {
  my $self = shift;
  my $transaction = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/ UPDATE `transaction`
                             SET transaction_state_id = ?
                             WHERE pnp_transaction_id = ? /);
  $sth->execute($transaction->{'state'},$transaction->{'pnp_transaction_id'}) or die $DBI::errstr;

  return 1;
}

sub _loadVehicleID {
  my $self = shift;
  my $transactionID = shift;
  my $loader = new PlugNPay::Transaction::Loader();
  return $loader->loadVehicleID($transactionID);
}

sub _loadStateID {
  my $self = shift;
  my $transactionID = shift;
  my $loader = new PlugNPay::Transaction::Loader();
  return $loader->loadStateID($transactionID);
}

sub loadPendingSettlements {
  my $self = shift;
  my $username = shift;
  my $select;
  my @params;
  if (defined $username && $username ne '' && $username ne 'all') {
    $select = 'SELECT t.pnp_transaction_id, t.transaction_state_id, p.processor_code_handle, t.settlement_amount
               FROM `transaction` t, `order` o, merchant m, processor p
               WHERE o.pnp_order_id = t.pnp_order_id AND m.identifier = ?
                 AND p.id = t.processor_id
                 AND o.merchant_id = m.id
                 AND t.transaction_state_id = ?';

    @params = ($username,'7');
  } else {
    $select = 'SELECT t.pnp_transaction_id, t.transaction_state_id, p.processor_code_handle, t.settlement_amount
               FROM `transaction` t, `processor` p
               WHERE t.transaction_state_id = ?
               AND p.id = t.processor_id';

    @params = ('7');
  }

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',$select);
  $sth->execute(@params) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});
  my $data = [];
  my $uuid = new PlugNPay::Util::UniqueID();
  my $processorIDObj = new PlugNPay::Processor::ID();
  foreach my $row (@{$rows}){
    $uuid->fromBinary($row->{'pnp_transaction_id'});
    my $newRow = { 'pnp_transaction_id' => $uuid->inHex(), 'processor_id' => $processorIDObj->getProcessorID($row->{'processor_code_handle'})};
    push @{$data}, $newRow;
  }

  return $data;
}

sub updateAccountCodes {
  my $self = shift;
  my $pnpID = shift;
  my $previousState = shift;
  my $nextState = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/
                UPDATE transaction_account_code
                   SET transaction_state_id = ?
                 WHERE transaction_state_id = ?
                   AND transaction_id = ?
               /);
  $sth->execute($nextState, $previousState, $pnpID) or $self->log({'error' => $DBI::errstr, 'message' => 'Error occurred while updating account codes'});
}

sub addEMVData {
  my $self = shift;
  my $pnpID = shift;
  my $transData = shift;
  my $status = new PlugNPay::Util::Status(1);

  my $firstSix = substr($transData->{'masked_card_number'},0,6);
  my $lastFour = substr($transData->{'masked_card_number'},-4);

  # Doing the needful
  $firstSix =~ s/\*/0/g;
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnp_transaction',q/
       INSERT INTO card_transaction
       (`card_first_six`, `card_last_four`, `pnp_transaction_id`)
       VALUES (?,?,?)
       ON DUPLICATE KEY UPDATE `card_first_six` = ?, `card_last_four` = ? /);
    $sth->execute($firstSix, $lastFour, $pnpID, $firstSix, $lastFour) or die $DBI::errstr;
  };

  if ($@) {
    $self->log({'error' => 'Failed to add card data for EMV transaction', 'transactionID' => $pnpID});
    $status->setFalse();
    $status->setError('Failed to add card data for EMV transaction');
    $status->setErrorDetails($@);
  }

  return $status;
}

# New ACH "settlement"
sub updateACHTransactions {
  my $self = shift;
  my $data = shift;
  my $uuid = new PlugNPay::Util::UniqueID();
  my $time = new PlugNPay::Sys::Time();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/
     UPDATE `transaction` SET
     transaction_state_id = ?, processor_settlement_date_time = ?
     WHERE pnp_transaction_id = ?
  /);
  my $stateMachine = new PlugNPay::Transaction::State();
  my $results = {};
  foreach my $transactionID (keys %{$data}) {
    my $transaction = $data->{$transactionID};
    $dbs->begin('pnp_transaction');
    $uuid->fromHex($transactionID);
    eval {
      my $nextState = $stateMachine->getTransactionStateID('POSTAUTH_PENDING');
      if ($transaction->{'status'} eq 'return') {
        $nextState = $stateMachine->getNextState('CREDIT_PENDING',$transaction->{'wasSuccess'});
      } elsif ($transaction->{'status'} eq 'complete') {
        $nextState = $stateMachine->getNextState('POSTAUTH_PENDING',$transaction->{'wasSuccess'});
      }

      my $newDateTime = $time->inFormatDetectType('iso_gm', $transaction->{'transaction_date_time'});
      $sth->execute($nextState,$newDateTime,$uuid->inBinary()) or die $DBI::errstr;
      $self->saveAdditionalProcessorDetails($transaction->{'pnp_transaction_id'},$nextState,$transaction->{'details'});
    };

    if ($@) {
      $dbs->rollback('pnp_transaction');
      $self->log({'error' => $@, 'message' => 'Error occurred while updating ACH transactions'});
      $results->{$uuid->inHex()} = { 'success' => 0, 'error' => $@, 'processor_status' => $transaction->{'status'} };
    } else {
      $results->{$uuid->inHex()} = { 'success' => 1, 'processor_status' => $transaction->{'status'} };
      $dbs->commit('pnp_transaction');
    }
  }

  return $results;
}

sub loadAuthorizedChecks {
  my $self = shift;
  my $time = shift;
  if (!$time || $time !~ /^\d{8}$/) {
    my $timeObj = new PlugNPay::Sys::Time();
    $time = $timeObj->nowInFormat('yyyymmdd_gm');
  }
  #Load pending trans for sent proc
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/
            SELECT t.pnp_transaction_id, a.value, p.processor_code_handle, m.identifier
            FROM transaction t, transaction_additional_processor_detail a,
                 transaction_additional_processor_detail_key k, processor p,
                 transaction_state s, transaction_vehicle v, merchant m, `order` o
            WHERE k.id = a.key_id
            AND o.pnp_order_id = t.pnp_order_id
            AND t.pnp_transaction_id = a.transaction_id
            AND k.name = ?
            AND t.transaction_state_id = s.id
            AND s.state IN (?,?,?)
            AND t.processor_id = p.id
            AND m.id = o.merchant_id
            AND t.transaction_vehicle_id = v.id
            AND v.vehicle = ?
            AND t.transaction_date <= ?/);
  $sth->execute('processor_reference_id','AUTH', 'POSTAUTH_PENDING', 'CREDIT_PENDING', 'ach', $time) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  return $rows;
}

# Log Function #
sub log {
  my $self = shift;
  my $data = shift;
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'transaction'});
  $logger->log($data);
}

1;
