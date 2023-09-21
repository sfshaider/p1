package PlugNPay::Processor::RetrieveProcessedTransactions;

use strict;
use JSON::XS;
use PlugNPay::Processor::Process;
use PlugNPay::Processor::SocketConnector;
use PlugNPay::Util::UniqueID;
use PlugNPay::Logging::DataLog;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub run {
  my $self = shift;
  my $processors = shift;
  my $ids = [];
  my $response = '{}';
  
  eval {
    $ids = $self->getPendingTransactionIDs($processors);
    my $transactionProcessor = new PlugNPay::Processor::Process();
    my $transactions = $transactionProcessor->getProcessedTransactions($ids,{'noCleanup' => 1});
    $response = encode_json($transactions);
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'transaction_process'});
    $logger->log({'error' => $@, 'processors' => $processors, 'function' => 'run'});
  }

  return $response;
}

sub getPendingTransactionIDs {
  my $self = shift;
  my $processors = shift || [];
  my $ids = [];
  my $socket = new PlugNPay::Processor::SocketConnector();
  my $uuid = new PlugNPay::Util::UniqueID();
  foreach my $processor (@{$processors}) {
    eval {
      my $data = { 'messageID' => $uuid->inHex() };
      my $response = $socket->connectToProcessor(encode_json($data), $processor);
      my $pendingIDs = $response->{'pending_transaction_ids'};
      if (ref($pendingIDs) eq 'ARRAY' && @{$pendingIDs}) {
        push @{$ids},@{$pendingIDs};
      }
    };

    if ($@) {
      my $logger = new PlugNPay::Logging::DataLog({'collection' => 'transaction_process'});
      $logger->log({'error' => $@, 'processor' => $processor, 'function' => 'getPendingTransactionIDs'});
    }
  }

  return $ids;
}

1;
