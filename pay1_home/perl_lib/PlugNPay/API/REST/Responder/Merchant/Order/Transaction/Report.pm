package PlugNPay::API::REST::Responder::Merchant::Order::Transaction::Report;

use strict;
use PlugNPay::Order::Report;
use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  my $data = {};
  if ($action eq 'read') {
    $data = $self->_read();
  } 
  elsif ($action eq 'create') {
    $data = $self->_create();
  }
  elsif ($action eq 'delete') {
    $data = $self->_delete();
  }  
  else {
    $self->setResponseCode('501');
  }

  return $data;
}


#read: Retrieves report for a patch id
sub _read {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $username = $self->getResourceData()->{'merchant'};
  my $batchId = $self->getResourceData()->{'report'};
  my $status = {};

  if ($batchId ne '') {
    $status = $self->getReports($username, $batchId);
  }
  else {
    $status = {'status' => 'ERROR', 'message' => 'Your request has an error: batchId is empty'};
    $self->setResponseCode(422);
  }
  return  $status;
}

sub _create {
  my $self = shift;
  
  my $username = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $inputData = $self->formatInput();

  # validate values for start and end range
  if (defined $inputData->{'start_date'} && defined $inputData->{'end_date'}) {
    my $formattedStart = new PlugNPay::Sys::Time()->inFormatDetectType('iso', $inputData->{'start_date'});
    my $formattedEnd = new PlugNPay::Sys::Time()->inFormatDetectType('iso', $inputData->{'end_date'});

    if (!defined $formattedStart && !defined $formattedEnd) {
      $self->setResponseCode(422);
      return { 'status' => 'error', 'message' => 'Invalid date range' };
    }

    $inputData->{'start_date'} = $formattedStart;
    $inputData->{'end_date'}   = $formattedEnd;
  } elsif (defined $inputData->{'start_time'} && defined $inputData->{'end_time'}) {
    my $formattedStart = new PlugNPay::Sys::Time()->inFormatDetectType('iso', $inputData->{'start_time'});
    my $formattedEnd = new PlugNPay::Sys::Time()->inFormatDetectType('iso', $inputData->{'end_time'});

    if (!defined $formattedStart && !defined $formattedEnd) {
      $self->setResponseCode(422);
      return { 'status' => 'error', 'message' => 'Invalid date range' };
    }

    $inputData->{'start_time'} = $formattedStart;
    $inputData->{'end_time'}   = $formattedEnd;
  } else {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Invalid date range' };
  }

  my $orderReport = new PlugNPay::Order::Report($username);
  my $result = $orderReport->saveOrderRequest({ 'query' => $inputData });

  my $status = {};
  if ($result) {
    $status = {'status' => 'Success', 'batchId' => $orderReport->getBatchID()};
    $self->setResponseCode(200);
  } else {
    $status = {'status' => 'ERROR', 'message' => $result->getError()};
    $self->setResponseCode(422);
  }

  return $status;
}

#delete: Deletes report for an patch id
sub _delete {
  my $self = shift;
  my $batchId = $self->getResourceData()->{'report'};
  my $username = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();

  my $status = {};
  if ($batchId ne '') {
    my $orderReport = new PlugNPay::Order::Report($username);
    if ($orderReport->batchIDExists($batchId)) {
      my $result= $orderReport->deleteOrderRequest($batchId);
      if ($result) {
        $status = {'status' => 'SUCCESS', 'message' => 'Order has been deleted.'};
        $self->setResponseCode(200);
      }
      else {
        $status = {'status' => 'ERROR', 'message' => $result->getError()};
        $self->setResponseCode(422);
      }
    }
    else {
      $status = {'status' => 'ERROR', 'message' => 'Invalid batch id'};
      $self->setResponseCode(404);
    }
  }
  else {
    $status = {'status' => 'ERROR', 'message' => 'Your request has an error: batch id is empty'};
    $self->setResponseCode(422);
  }
  return $status;
}


#formatInput: camel case serialized input property names to match with schema.
sub formatInput {
  my $self = shift;
  my $inputData = $self->getInputData();
  
  my $data = {
    'start_date'         => $inputData->{'startDate'},
    'end_date'           => $inputData->{'endDate'},
    'authorization_code' => $inputData->{'authorizationCode'},
    'amount'             => $inputData->{'amount'},
    'operation'          => $inputData->{'operation'},
    'processor'          => $inputData->{'processor'},
    'account_type'       => $inputData->{'accountType'},
    'orderID'            => $inputData->{'orderID'},
    'transactionID'      => $inputData->{'transactionID'},
    'transaction_ref_id' => $inputData->{'transactionRefID'},
    'transaction_time'   => $inputData->{'transactionTime'},
    'batchid'            => $inputData->{'batchID'},
    'vendor_token'       => $inputData->{'vendorToken'},
    'start_time'         => $inputData->{'startTime'},
    'end_time'           => $inputData->{'endTime'},
    'requestTokens'      => $inputData->{'requestTokens'}
  };

  # to remove NULL values
  my $queryData = {};
  foreach my $key (keys %{$data}) {
    if (defined $data->{$key}) {
      $queryData->{$key} = $data->{$key};
    }
  }
  
  return $queryData;
}

#getReports: obtains report after verify that batch id is valid.
# param: batch id
sub getReports {
  my $self = shift;
  my $username = shift;
  my $batchId = shift;
  
  my $status = {'status' => 'UNKNOWN', 'batchId' => $batchId};

  my $orderReport = new PlugNPay::Order::Report($username);
  
  if ($orderReport->batchIDExists ($batchId)) {
    $orderReport->loadOrderBatch($batchId);
    $self->setResponseCode(200);
    if ($orderReport->isPending($batchId)) {
      $status = {'status' => 'PENDING', 'message' => 'Your request has been submitted for processing.', 'batchId' => $batchId};
    }
    elsif ($orderReport->isProcessing($batchId)) {
      $status = {'status' => 'PROCESSING', 'message' => 'Your request is being processed.', 'batchId' => $batchId};
    }
    elsif ($orderReport->isProblem($batchId)) {
      $status = {'status' => 'ERROR', 'message' => 'An error has occurred.', 'batchId' => $batchId};
      $self->setResponseCode(422);
    }
    elsif ($orderReport->isComplete($batchId)) {
      my $link = $orderReport->getS3Link();
      $status = {'status' => 'SUCCESS', 'message' => 'Your order request is ready for download.', 'batchId' => $batchId, 'downloadLink' => $link};
    }
  }
  else {
    $status = {'status' => 'ERROR', 'message' => 'Invalid batch id.', 'batchId' => $batchId};
    $self->setResponseCode(404);
  }

  return {'status' => $status};
}

1;
