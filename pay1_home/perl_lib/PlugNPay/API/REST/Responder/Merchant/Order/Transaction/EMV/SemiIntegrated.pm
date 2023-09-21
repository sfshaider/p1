package PlugNPay::API::REST::Responder::Merchant::Order::Transaction::EMV::SemiIntegrated;

use strict;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::Loader;
use PlugNPay::Processor::SemiIntegrated;
use PlugNPay::GatewayAccount::LinkedAccounts;
use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  my $merchant = $self->getResourceData()->{'merchant'};

  if (!$merchant) {
    $merchant = $self->getGatewayAccount();
  } else {
    if ($merchant ne $self->getGatewayAccount()) {
      my $linked = new PlugNPay::GatewayAccount::LinkedAccounts($self->getGatewayAccount())->isLinkedTo($merchant);
      if (!$linked) {
        $self->setResponseCode(403);
        return {'status' => 'ERROR', 'message' => 'Access Denied'};
      }
    }
  }

  my $response = {};

  if ($action eq 'read') {
    $response = $self->_read();
  } elsif ($action eq 'delete') {
    $response = $self->_delete()
  } else {
    $self->setResponseCode(501);
  }

  return $response;
}

# Gets pending transactions and returns to terminal.
sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $terminalSerialNumber = $self->getResourceData()->{'terminal'};
  my $startTime = $self->getResourceOptions()->{'startTime'};
  my $endTime = $self->getResourceOptions()->{'endTime'};

  my $pnpProcessor = new PlugNPay::Processor::SemiIntegrated();

  my $emvPendingTransactions = $pnpProcessor->loadTerminalPendingTransactions({
    terminalSerialNumber => $terminalSerialNumber,
    merchant             => $merchant,
    startTime            => $startTime,
    endTime              => $endTime
  });

  my $response;
  if (!$emvPendingTransactions) {
    $self->setResponseCode(422);
    $response = {'status' => 'ERROR', 'message' => 'Failed to load emv pending transactions.', 'transactions' => []};
  } else {
    $self->setResponseCode(200);
    $response = {'status' => 'SUCCESS','message' => 'Successfully loaded pending transactions', 'transactions' => $emvPendingTransactions};
  }
  return $response;
}

# This method is for when removing a transaction off terminal.
sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $transID = $self->getResourceData()->{'transaction'};

  my $response = {'status' => 'SUCCESS', 'message' => 'Successfully removed pending transaction.', 'transactionID' => $transID};
  $self->setResponseCode(200);

  my $pnpProcessor = new PlugNPay::Processor::SemiIntegrated();
  my $status = $pnpProcessor->removePendingTransaction($transID);

  if (!$status) {
    $self->setResponseCode(422);
    $response = {'status' => 'ERROR', 'message' => $status->getError(), 'transactionID' => $transID};
  } else {
    my $loadedTransaction = $self->_loadOriginalTransaction($transID, $merchant);
    $status = $pnpProcessor->updateFailedTransaction($loadedTransaction);

    if (!$status) {
      $self->setResponseCode(422);
      $response = { 'status' => 'ERROR', 'message' => $status->getError(), 'transactionID' => $transID };
    }
  }
  return $response;
}

sub _loadOriginalTransaction {
  my $self = shift;
  my $transactionID = shift;
  my $merchant = shift;

  my $loader = new PlugNPay::Transaction::Loader({'loadPaymentData' => 1});
  my $transaction;

  eval {
    my $loadedTransaction = $loader->newLoad({ 'username' => $merchant, 'pnp_transaction_id' => $transactionID })->{$merchant}{$transactionID};
    $transaction = $loader->convertToTransactionObject($loadedTransaction);
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'SemiIntegrated'});
    $logger->log({
      'status'        => 'ERROR',
      'message'       => 'Failed to load origin transaction',
      'transactionID' => $transactionID,
      'module'        => 'PlugNPay::API::REST::Responder::EMV::SemiIntegrated',
      'function'      => '_loadOriginalTransaction',
      'error'         => $@
    });
  }
  return $transaction;
}
1;
