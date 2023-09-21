package PlugNPay::Processor::Process::Settlement::Credit;

use strict;
use JSON::XS;
use Time::HiRes qw();
use PlugNPay::Sys::Time;
use PlugNPay::Processor::Process;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::Updater;
use PlugNPay::Transaction::Formatter;
use PlugNPay::Processor::SocketConnector;
use PlugNPay::Transaction::Logging::Logger;
use PlugNPay::Processor::Process::MessageBuilder;

# Special processing method: Need to update transaction, not add new transaction #

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

# Mark For Settlement #
sub markForSettlement {
  my $self = shift;
  my $transData = shift; # Can be array of IDs or single ID
  # Can also be a single hash {pnpID, settleAmount} or an array of hashes

  my $updater = new PlugNPay::Transaction::Updater();
  my $resp;
  $resp = $updater->markForSettlement($transData);

  return $resp;
}

##############
# Settlement #
##############
sub settle {
  my $self = shift;
  my $time = shift;
  my $username = shift;
  my $timeObj = new PlugNPay::Sys::Time();

  my $marked = $self->settleMarkedTransactions($timeObj->inFormatDetectType('iso_gm',$time),$username);
  my $pending = $self->redeemPendingTransactions($username);
  return { 'newly_settled_transactions' => $marked, 'previously_pending_transactions' => $pending };
}

#Redeem Old
sub redeemPendingTransactions {
  my $self = shift;
  my $username = shift || 'all';

  my $stateMachine = new PlugNPay::Transaction::State();
  my $loader = new PlugNPay::Transaction::Updater();
  my $pending = $loader->loadPendingSettlements($username);
  my $readyToRedeem = {};
  my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();
  foreach my $redeemable (@{$pending}) {
    my $content = $messageBuilder->requestContent($redeemable,$redeemable->{'processor_id'},'6','redeem');
    if (!$content->{'pnp_transaction_id'}) {
      $content->{'pnp_transaction_id'} = $content->{'transactionData'}{'pnp_transaction_id'};
    }
    $readyToRedeem->{$redeemable->{processor_id}}{$content->{requestID}} = $content;
  }
  my $redeemed = $self->redeemSettled($readyToRedeem);
  return $redeemed;
}

#Settle New
sub settleMarkedTransactions {
  my $self = shift;
  my $time = shift;
  my $username = shift || 'all';

  my $updater = new PlugNPay::Transaction::Updater();
  my $readyTransactions = $updater->loadTransactionsToSettle($time);
  my $pending = {};
  if ($username eq 'all') {
    my $allTransactions = {};
    foreach my $loadedUser (keys %{$readyTransactions}) {
        my $values = $readyTransactions->{$loadedUser};
        $allTransactions = {%$allTransactions, %$values};
    }
    $pending = $self->requestSettlement($allTransactions);
  } else {
    $pending = $self->requestSettlement($readyTransactions->{$username});
  }

  Time::HiRes::sleep(1);
  my $redeemed = $self->redeemSettled($pending);

  return $redeemed;
}

# settleTransactions
#   input: array ref
#     [{
#       gatewayAccount => <gatewayAccount>,
#       transactionId  => <transactionId>
#     }, ...]
#   output: hash ref
#     {
#       <gatewayAccount> => $results
#     }
# this needs to be modified a bit to make it a bit more async in the sense that
# right now it does all requests then redeems.  that means that if the processor
# has like 50k transactions to settle, they are waiting there until all the
# other transactions have been requested for settlement and everything up to
# that processor has been redeemed already...  would be bad if say there was an
# OOM error or container failed.
#
# so this needs to be changed to do smaller batches of requests/redeems at a time
# spanning processors maybe...
sub settleTransactions {
  my $self = shift;
  my $data = shift;

  # if data is a transaction reference, i.e. { gatewayAccount => $x, transactionId => $y }
  # then turn data into an array ref with that being the only item.
  if (ref($data) eq 'HASH') {
    $data = [$data];
  }

  my %transactionsForAccounts;
  foreach my $transactionInfo (@{$data}) {
    $transactionsForAccounts{$transactionInfo->{'gatewayAccount'}} ||= [];
    push @{$transactionsForAccounts{$transactionInfo->{'gatewayAccount'}}}, $transactionInfo->{'transactionId'};
  }

  my %resultsForAccounts;
  foreach my $account (keys %transactionsForAccounts) {
    my $pending = $self->requestSettlement($transactionsForAccounts{$account});
    $resultsForAccounts{$account} = $self->redeemSettled($pending);
  }

  return \%resultsForAccounts;
}

# Request #
sub requestSettlement {
  my $self = shift;
  my $transactions = shift;
  my $processorGroups = $self->buildProcessorGroups($transactions);
  my $transactionsSent = $self->requestProcessorGroupSettlement($processorGroups);

  return $transactionsSent;
}

sub requestProcessorGroupSettlement {
  my $self = shift;
  my $processorGroups = shift;
  my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();
  my $connector = new PlugNPay::Processor::SocketConnector();
  my $pendingTransactions = {};
  foreach my $processorID (keys %{$processorGroups}) {
    my $transactions = $processorGroups->{$processorID};
    my $mergedBatches = {};
    foreach my $transaction (values %{$transactions}) {
      my $message = $messageBuilder->build($transaction);
      my $jsonRequest = encode_json($message);
      my $jsonResponse;
      my $response;
      eval {
        $jsonResponse = $connector->connectToProcessor($jsonRequest,$processorID);
        $response = decode_json($jsonResponse);
      };
      if ($@ || !$response) {
        # TODO log error
        next;
      }
      my $transactionResponses = $response->{'responses'};
      $mergedBatches = {%{$mergedBatches},%{$transactionResponses}};
    }

    $pendingTransactions->{$processorID} = $mergedBatches;
  }
  return $pendingTransactions;
}

sub buildProcessorGroups {
  my $self = shift;
  my $transactions = shift;
  my $formatter = new PlugNPay::Transaction::Formatter();
  my $stateMachine = new PlugNPay::Transaction::State();
  my $processorGroups = {};
  foreach my $transactionID (keys %{$transactions}) {
    my $transaction = $transactions->{$transactionID};
    if ($stateMachine->checkNextState($transaction->{'transaction_state_id'},'POSTAUTH_PENDING')) {
      my $readyTransaction = $formatter->formatForSettlement($transaction);
      if (defined $processorGroups->{$transaction->{'processor_id'}} && ref($processorGroups->{$transaction->{'processor_id'}}) eq 'HASH') {
        $processorGroups->{$transaction->{'processor_id'}}{$readyTransaction->{'requestID'}} = $readyTransaction;
      } else {
        $processorGroups->{$transaction->{'processor_id'}} = {$readyTransaction->{'requestID'} => $readyTransaction};
      }

    } else {
      my $logger = new PlugNPay::Transaction::Logging::Logger();
      $logger->log({'transaction_id'=>$transaction->{'pnp_transaction_id'},
                    'transaction_ref_id' => $transaction->{'pnp_transaction_id'},
                    'previous_state_id' => $transaction->{'transaction_state_id'},
                    'next_state_id' => $transaction->{'transaction_state_id'},
                    'message' => 'Preventing invalid transaction from settling'
                   });
    }
  }

  my $batchedGroups = {};
  foreach my $processorID (keys %{$processorGroups}) {
    $batchedGroups->{$processorID} = $self->createBatches($processorGroups->{$processorID});
  }

  return $batchedGroups;
}

# Redeem #
sub redeemSettled {
  my $self = shift;
  my $pendingTransactions = shift;
  my $redeemed = {};
  foreach my $processorID (keys %{$pendingTransactions} ) {
    my $batch = $self->createBatches($pendingTransactions->{$processorID});
    my $processorRedeems = {};
    foreach my $item (values %{$batch}) {
      my $redeemedBatch = $self->redeemBatch($item,$processorID);
      $processorRedeems = {%{$processorRedeems},%{$redeemedBatch}};
    }
    $redeemed->{$processorID} = $processorRedeems;
  }

  return $redeemed;
}

sub createBatches {
  my $self = shift;
  my $pending = shift;
  my $count = 0;
  my $batches = {};
  foreach my $transactionID (keys %{$pending}) {
    if (ref($batches->{$count}) ne 'HASH') {
      $batches->{$count} = { $transactionID => $pending->{$transactionID} };
    } else {
      my @keys = keys %{$batches};
      if (@keys < 20) {
        $batches->{$count}{$transactionID} = $pending->{$transactionID};
      } else {
        $count++;
        $batches->{$count} = { $transactionID => $pending->{$transactionID} };
      }
    }
  }

  return $batches;
}

sub redeemBatch {
  my $self = shift;
  my $batch = shift;
  my $processorID = shift;
  my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();
  my $connector = new PlugNPay::Processor::SocketConnector();
  my $process = new PlugNPay::Processor::Process();
  my $updater = new PlugNPay::Transaction::Updater();

  #Redeem batch of pending settlements
  my $message = $messageBuilder->buildRedeemMessage($batch,$processorID);
  my $JSON = $connector->connectToProcessor(encode_json($message),$processorID);
  my $response = decode_json($JSON);
  my $completed = $process->getCompletedTransactions($response->{'responses'},$processorID);
  my $errors = $updater->finishSettlingTransactions($completed);
  $process->cleanupTransactions($processorID,$completed,$errors);

  return $completed;
}

1;
