package PlugNPay::API::REST::Responder::Merchant::Order::Transaction::CustomData;

use strict;
use PlugNPay::Transaction::Logging::CustomData;
use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  
  if ($action eq 'read') {
    return $self->_read();
  }
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'};
  my $orderIDs = $self->getResourceDataArray()->{'order'};
  my $startTime = $self->getResourceOptions()->{'start_time'};
  my $endTime = $self->getResourceOptions()->{'end_time'};
  my $dataParser = new PlugNPay::Transaction::Logging::CustomData($merchant);
  my $data = {};

  my $response;
  if (!$startTime || !$endTime || !@{$orderIDs} || !$merchant) {
      $self->setResponseCode(422);
      $response = {'status' => 'failure', 'message' => 'Missing required data'};
  } else {
  
    eval {
      $data = $dataParser->loadCustomData($orderIDs,$startTime,$endTime);
    };
  
    if ($@) {
      $self->setResponseCode(520);
      $response = {'status' => 'failure', 'message' => 'An error occurred while parsing custom data', 'error' => $@};
    } elsif (keys %{$data}) {
      $self->setResponseCode(200);
      $response = {'status' => 'success', 'orders' => $data, 'message' => 'Successfully loaded custom data for order(s)'};
    } else {
      $self->setResponseCode(404);
      $response = {'status' => 'failure', 'message' => 'No data found for order(s) sent'};
    }
  }
 
  return $response;
}
1;
