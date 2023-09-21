package PlugNPay::API::REST::Responder::Merchant::Order::Transaction::EMV::CloudEMV;

use strict;
use PlugNPay::Transaction;
use PlugNPay::Util::Status;
use PlugNPay::GatewayAccount;
use PlugNPay::Client::Dishout;
use PlugNPay::Client::Datacap;
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

  if ($action eq 'create') {
    $response = $self->_create();
  } elsif ($action eq 'read'){
    $response = $self->_read();
  } elsif ($action eq 'delete') {
    $response = $self->_delete();
  } else {
    $self->setResponseCode(501);
  }

  return $response;
}

sub _create {
  my $self = shift;
  my $inputData = $self->getInputData();
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();

  my $response = {};
  my $loadedTransaction;
  my $isRequestValid = 1;
  my $errMsg = '';

  if (!$inputData->{'transactionID'} || !$inputData->{'terminalSerialNumber'}) {
    my @messages = ();
    $isRequestValid = 0;
    $self->setResponseCode(400);
    push(@messages, 'No transaction id sent in request body.') if !$inputData->{'transactionID'};
    push(@messages, 'No terminal serial number sent in request body.') if !$inputData->{'terminalSerialNumber'};
    $errMsg = join(', ', @messages);
  } else {
    $loadedTransaction = $self->_loadOriginalTransaction($inputData->{'transactionID'}, $merchant);  
    if (ref($loadedTransaction !~ /PlugNPay::Transaction/)) {
      $isRequestValid = 0; 
      $self->setResponseCode(404);
      $errMsg = 'Transaction does not exist.';
    } elsif ($loadedTransaction->getTransactionState() !~ /_PENDING$/) {
      $isRequestValid = 0;
      $self->setResponseCode(409);
      $errMsg = 'Transaction has already been processed.';
    }
  }
  
  if ($isRequestValid) {
    my $processor = $loadedTransaction->getProcessor();
    my $terminalSerialNumber = $inputData->{'terminalSerialNumber'};
    my $status = new PlugNPay::Util::Status(1);

    if (lc $processor eq 'datacap') {
      my $datacap = new PlugNPay::Client::Datacap($merchant);
      $status = $datacap->performTransaction({ 'terminalSerialNumber' => $terminalSerialNumber, 'transaction' => $loadedTransaction });
    } elsif (lc $processor eq 'slingshot') {
      my $dishout = new PlugNPay::Client::Dishout($merchant);
      $status = $dishout->performTransaction({ 'terminalSerialNumber' => $terminalSerialNumber, 'transaction' => $loadedTransaction });
    } elsif (lc $processor eq 'plugnpay') {
      my $pnpProcessor = new PlugNPay::Processor::SemiIntegrated();

      if ($loadedTransaction->getTransactionState() =~ /^CREDIT_PENDING$/i && $loadedTransaction->getPNPTransactionReferenceID()) {
        $status = $pnpProcessor->canPerformReturn($loadedTransaction, $processor);
      }

      if ($status) {
         $status = $pnpProcessor->savePendingTransaction({
          'stationID'            => $inputData->{'stationID'} || 0,
          'orderID'              => $loadedTransaction->getPNPOrderID(),
          'transactionID'        => $inputData->{'transactionID'},
          'terminalSerialNumber' => $inputData->{'terminalSerialNumber'},
          'amount'               => $loadedTransaction->getTransactionAmount(),
          'state'                => $loadedTransaction->getTransactionState(),
          'merchant'             => $merchant
        });

      }
    } else {
      $status->setFalse();
      $status->setError('Processor not supported.');
    }

    if (!$status) {
      $self->setResponseCode(422);
      $response = {'status' => 'ERROR', 'message' => $status->getError(), 'transactionID' => $inputData->{'transactionID'}};
    } else {
      $self->setResponseCode(201);
      $response = {'status' => 'PENDING', 'message' => 'Your transaction was sent for processing.', 'transactionID' => $inputData->{'transactionID'}};
    }

  } else {
    $response = {'status' => 'ERROR', 'message' => $errMsg, 'transactionID' => $inputData->{'transactionID'}};
  }

  return $response;
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $transactionID = $self->getResourceData()->{'transaction'};

  if (!$transactionID) {
    $self->setResponseCode(400);
    return { 'status' => 'ERROR', 'message' => 'No transaction ID sent in URL.' };
  }

  my $loadedTransaction = $self->_loadOriginalTransaction($transactionID, $merchant);

  if (ref($loadedTransaction) !~ /PlugNPay::Transaction/) {
    $self->setResponseCode(404);
    return { 'status' => 'ERROR', 'message' => 'Transaction does not exist.' };
  }

  if ($loadedTransaction->getTransactionState() !~ /_PENDING$/) {
    my $state = new PlugNPay::Transaction::State();
    my $stateID = $state->getTransactionStateID($loadedTransaction->getTransactionState());
    my $processorDetails = $loadedTransaction->getProcessorDataDetails()->{$stateID};
    $self->setResponseCode(200);
    return {
      'status'        => $processorDetails->{'processor_status'} || $loadedTransaction->getTransactionState(),
      'transactionID' => $transactionID,
      'authCode'      => $loadedTransaction->getAuthorizationCode(),
      'message'       => $processorDetails->{'processor_message'}
    };
  }

  my $response;
  my $processor = $loadedTransaction->getProcessor();
  my $processorID = new PlugNPay::Processor::ID()->getProcessorID($processor);

  if (lc $processor eq 'datacap') {
    my $datacap = new PlugNPay::Client::Datacap();
    my $transactionResults = $datacap->loadTransactionResults($transactionID)->{$processorID}{$transactionID};

    $self->setResponseCode(200);
    $response = {
      'status'        => $transactionResults->{'processor_status'},
      'transactionID' => $transactionID,
      'authCode'      => $transactionResults->{'authorization_code'},
      'message'       => $transactionResults->{'processor_message'}
    };
  } elsif (lc $processor eq 'slingshot' || lc $processor eq 'plugnpay') {
    $self->setResponseCode(200);
    $response = {
      'status'        => $loadedTransaction->getTransactionState(),
      'transactionID' => $transactionID,
      'message'       => 'Transaction is still pending.'
    };
  } else {
    $self->setResponseCode(422);
    $response = { 'status' => 'ERROR', 'message' => 'Processor not supported' };
  }

  return $response;
}

sub _delete {
  my $self = shift;
  my $transID = $self->getResourceData()->{'transaction'};
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $inputData = $self->getInputData();

  my $isRequestValid = 1;
  my $errMsg = '';
  my $response = {};
  my $loadedTransaction;

  if (!$inputData->{'terminalSerialNumber'}) {
    $self->setResponseCode(400);
    $isRequestValid = 0;
    $errMsg = 'No serial number provided in request.';
  } elsif (!$transID) {
    $self->setResponseCode(400);
    $isRequestValid = 0;
    $errMsg = 'No transaction ID provided in request.';
  } else {
    $loadedTransaction = $self->_loadOriginalTransaction($transID, $merchant);
    if (ref($loadedTransaction !~ /^PlugNPay::Transaction/i)) {
      $self->setResponseCode(404);
      $isRequestValid = 0;
      $errMsg = 'Transaction does not exist.';
    } elsif ($loadedTransaction->getTransactionState() !~ /SALE/i) {
      $self->setResponseCode(409);
      $isRequestValid = 0; 
      $errMsg = 'Can not void a non-sale transaction.';
    }
  }

  if ($isRequestValid) {
    my $processor = $loadedTransaction->getProcessor();

    $self->setResponseCode(201);
    $response = {'status' => 'SUCCESS', 'message' => 'Successfully created void transaction.', 'transactionID' => $transID};

    if (lc $processor eq 'plugnpay') {
      my $pnpProcessor = new PlugNPay::Processor::SemiIntegrated();
      if ($pnpProcessor->canPerformVoid($loadedTransaction)) {
        my $status = $pnpProcessor->savePendingTransaction({
          'stationID'            => $inputData->{'stationID'} || 0,
          'orderID'              => $loadedTransaction->getPNPOrderID(),
          'transactionID'        => $transID,
          'terminalSerialNumber' => $inputData->{'terminalSerialNumber'},
          'amount'               => $loadedTransaction->getTransactionAmount(),
          'state'                => 'VOID_PENDING',
          'merchant'             => $merchant,
          'processorReferenceID' => $loadedTransaction->getProcessorReferenceID()
        });
          
        if (!$status) {
          $self->setResponseCode(422);
          $response = { 'status' => 'ERROR', 'message' => $status->getError(), 'transactionID' => $transID };
        }

      } else {
        $self->setResponseCode(422);
        $response = {'status' => 'ERROR', 'message' => 'Cannot perform void. Please perform a return.', 'transactionID' => $transID};
      }
    } else {
        $self->setResponseCode(422);
        $response = {'status' => 'ERROR', 'message' => 'Processor not supported', 'transactionID' => $transID};
    } 
  } else {
    $response = {'status' => 'ERROR', 'message' => $errMsg, 'transactionID' => $transID};
  }

  return $response;
}

sub _loadOriginalTransaction {
  my $self = shift;
  my $transactionID = shift;
  my $merchant = shift;

  my $loader = new PlugNPay::Transaction::Loader();
  my $transaction;

  eval {
    my $loadedTransaction = $loader->newLoad({ 'username' => $merchant, 'pnp_transaction_id' => $transactionID })->{$merchant}{$transactionID};
    $transaction = $loader->convertToTransactionObject($loadedTransaction);
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'cloudemv' });
    $logger->log({ 'message' => 'CloudEMV -- Could not load original transaction: ' . $@, 'transactionID' => $transactionID });
  }

  return $transaction;
}


1;
