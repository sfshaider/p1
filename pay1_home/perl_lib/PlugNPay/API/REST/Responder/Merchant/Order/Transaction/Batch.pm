package PlugNPay::API::REST::Responder::Merchant::Order::Transaction::Batch;

use strict;
use PlugNPay::Environment;
use PlugNPay::Logging::DataLog;
use PlugNPay::Processor::Process::Batch;
use PlugNPay::GatewayAccount::LinkedAccounts;
use PlugNPay::Processor::Process::Batch::Result;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  my $data = shift;
  if ($action eq 'create') {
    $data = $self->_create();
  } elsif ($action eq 'update') {
    $data = $self->_update();
  } elsif ($action eq 'delete') {
    $data = $self->_delete();
  } elsif ($action eq 'read') {
    $data = $self->_read();
  } else {
    $self->setResponseCode(501);
  }

  return $data;
}

sub _create {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $batch = $self->getInputData();
  my $batchID = $batch->{'merchantBatchID'} || $self->getResourceData()->{'batch'};
  my $env = new PlugNPay::Environment();
  my $serverName = $self->getAuthenticationType() eq 'apiKey' ? $env->get('PNP_CLIENT_IP') : 'pay1.plugnpay.com/admin/batches';
  my $username = $self->checkUsername($merchant);
  my $batcher = new PlugNPay::Processor::Process::Batch($merchant);
  $batcher->setEmailFlag($batch->{'shouldEmail'});
  $batcher->setHeaderType($batch->{'header'});
  $batcher->setServerName($serverName);
  $batcher->setEmailAddress($batch->{'emailAddress'});
  $batcher->setBatchID($batchID);
  my $result = $batcher->uploadBatch($batch->{'batchFile'});
  my $failedTransactions = $batcher->getFailedTransactions();
  my $response = {};

  if ($result) {
    $self->setResponseCode(200);
    $response->{'status'} = 'success';
    my $message = 'Successfully batched transactions';

    if ($failedTransactions > 0) {
      $message = 'Batched transactions with some failures';
      $response->{'failureCount'} = $failedTransactions;
    }

    $response->{'message'} = $message;
    $response->{'batchID'} = $batcher->getBatchID();
    $response->{'merchant'} = $username;
  } else {
    $response->{'status'} = 'error';
    $response->{'message'} = $result->getError();
    $response->{'error'} = $result->getErrorDetails();
    $self->setResponseCode(422);
  }

  return $response;
}

sub _update {
  my $self = shift;
  my $batch = $self->getInputData();
  my $result = {};
  my $batcher = new PlugNPay::Processor::Process::Batch();
  my $username = $self->checkUsername($batch->{'username'} || $self->getResourceData()->{'merchant'});
  my $batchID = $batch->{'batchID'} || $self->getResourceData()->{'batch'};
  if ($batchID && $username) {
    my $status = $batcher->finalizeBatch($batchID, $username);
    my $message = 'Successfully finalized batch';
    if (!$status) {
      $message = $status->getError() . ': ' . $status->getErrorDetails();
    }

    $result = {
     'status'  => $status ? 'success' : 'problem',
     'message' => $message
    };

    my $code = $status ? 200 : 422;
    $self->setResponseCode($code);
  } else {
    $self->setResponseCode(400);
    $result = {
      'status'  => 'problem',
      'message' => 'Request missing required data, please make sure you have both batchID and merchant name in payload'
    };
  }

  return $result;
}

sub _delete {
  my $self = shift;
  my $inputData = $self->getInputData();
  my $result = {};
  my $merchant = $self->getResourceData()->{'merchant'} || $inputData->{'merchant'};
  my $batch = $self->getResourceData()->{'batch'} || $inputData->{'batchID'};
  my $batcher = new PlugNPay::Processor::Process::Batch();

  my $username = $self->checkUsername($merchant);

  if ($batch && $username) {
    my $status = $batcher->deleteBatch($batch, $username);
    my $message = 'Successfully cancelled batch';
    if (!$status) {
      $message = $status->getError() . ': ' . $status->getErrorDetails();
    }

    $result = {
     'status'  => $status ? 'success' : 'problem',
     'message' => $message
    };

    my $code = $status ? 200 : 422;
    $self->setResponseCode($code);
  } else {
    $self->setResponseCode(400);
    $result = {
      'status'  => 'problem',
      'message' => 'Request missing required data, please make sure you have both batchID and merchant name in payload'
    };
  }

  return $result;
}

sub _read {
  my $self = shift;
  my $batchID = $self->getResourceData()->{'batch'};
  my $username = $self->checkUsername($self->getResourceData()->{'merchant'});

  my $data = {};
  eval {
    my $batchLoader = new PlugNPay::Processor::Process::Batch::Result($username);
    $data = $batchLoader->loadResults($batchID);
  };

  my $response;

  if ($@) {
    $self->setResponseCode(520);
    $response = {
      'status'  => 'failure',
      'message' => 'An unknown error occurred while loading batch results'
    };
    $self->log($username, $batchID, $@);
  } else {
    $self->setResponseCode(200);
    $response = {
      'status'      => 'success',
      'batchResult' => $data,
      'message'     => 'loaded batch results'
    };
  }
}

sub checkUsername {
  my $self = shift;
  my $merchant = shift;
  my $usernameToUse = $self->getGatewayAccount();

  if ($merchant && $merchant ne $usernameToUse) {
    my $linkedAccount = new PlugNPay::GatewayAccount::LinkedAccounts($self->getGatewayAccount());
    $usernameToUse = $linkedAccount->isLinkedTo($merchant) ? $merchant : $self->getGatewayAccount();
  }

  return $usernameToUse;
}

sub log {
  my $self = shift;
  my $username = shift;
  my $batchID = shift;
  my $error = shift;
  new PlugNPay::Logging::DataLog({'collection' => 'uploadbatch'})->log({
    'requestor' => $self->getGatewayAccount(),
    'username'  => $username,
    'batchID'   => $batchID,
    'error'     => $@
  });
}

1;
