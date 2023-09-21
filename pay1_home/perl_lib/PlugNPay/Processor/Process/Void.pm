package PlugNPay::Processor::Process::Void;

use strict;
use JSON::XS;
use Time::HiRes qw();
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

sub void {
  my $self = shift;
  my $transactions = shift;
  my $formatter = new PlugNPay::Transaction::Formatter();
  my $stateMachine = new PlugNPay::Transaction::State();
  my $transactionsToSend = {};
  my $logger = new PlugNPay::Transaction::Logging::Logger;
  if (ref($transactions) eq 'HASH') {
    $transactions = [$transactions];
  }
  foreach my $transaction (@{$transactions}) {
    if ($stateMachine->checkNextState($transaction->{'transaction_state_id'},'VOID_PENDING')) {
      $logger->log({'transaction_id'=>$transaction->{'pnp_transaction_id'},
                    'transaction_ref_id' => $transaction->{'pnp_transaction_id'},
                    'previous_state_id' => $transaction->{'transaction_state_id'},
                    'next_state_id' => $stateMachine->getStates()->{'VOID_PENDING'},
                    'message' => 'Preparing Void of transaction'
                   });
        my $formattedForVoid = $formatter->formatForVoid($transaction);
      if (defined $transactionsToSend->{$transaction->{'processor_id'}} && ref($transactionsToSend->{$transaction->{'processor_id'}}) eq 'ARRAY') {
        $transactionsToSend->{$transaction->{'processor_id'}}{$formattedForVoid->{'requestID'}} = $formattedForVoid;
      } else {
        $transactionsToSend->{$transaction->{'processor_id'}} = { $formattedForVoid->{'requestID'} => $formattedForVoid };
      }
    } else {
      $logger->log({'transaction_id'=>$transaction->{'pnp_transaction_id'},
                    'transaction_ref_id' => $transaction->{'pnp_transaction_id'},
                    'previous_state_id' => $transaction->{'transaction_state_id'},
                    'next_state_id' => $transaction->{'transaction_state_id'},
                    'message' => 'Preventing invalid transaction from being voided'
                   });
    }
  }
  Time::HiRes::sleep(1);
  my $socket = new PlugNPay::Processor::SocketConnector();
  my $responses = {};
  my @keys = keys  %{$transactionsToSend};
  my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();
  foreach my $processorID (@keys) {
    my $JSON = encode_json($messageBuilder->build($transactionsToSend->{$processorID}));
    my $responseJSON = $socket->connectToProcessor($JSON,$processorID);
    my $decodedJSONHash = decode_json($responseJSON);
    my $decodedJSON = $decodedJSONHash->{'responses'};
    $responses->{$processorID} = $decodedJSON;
  }

  return $responses;
}

####################################
# Second part of trans processing  #
# Retrieves transaction responses  #
####################################
sub redeemPending {
  my $self = shift;
  my $pending = shift;
  my $transactions = $self->_retrieveTransactions($pending);

  return $transactions;
}

sub _retrieveTransactions {
  my $self = shift;
  my $pendingInformation = shift;
  my $updater = new PlugNPay::Transaction::Updater();
  my $transactions = {};
  my $connector = new PlugNPay::Processor::SocketConnector();
  my $process = new PlugNPay::Processor::Process();
  my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();
  foreach my $processorID (keys %{$pendingInformation}) {
    my $JSON = encode_json($messageBuilder->buildRedeemMessage($pendingInformation->{$processorID}, $processorID));
    my $responses = $connector->connectToProcessor($JSON,$processorID);
    my $responseDataHash = decode_json($responses);
    my $responseData = $process->getCompletedTransactions($responseDataHash->{'responses'},$processorID);
    $transactions->{$processorID} = $responseData;
    my $errors = $updater->finalizeTransactions($responseData);
    $process->cleanupTransactions($processorID,$responseData,$errors);
  }

  return $transactions;
}

1;
