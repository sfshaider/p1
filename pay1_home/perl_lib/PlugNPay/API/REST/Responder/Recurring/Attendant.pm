package PlugNPay::API::REST::Responder::Recurring::Attendant;

use strict;
use PlugNPay::Recurring::Attendant;
use base 'PlugNPay::API::REST::Responder';


sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  if ($action eq 'create') {
    return $self->_create();
  }
  $self->setResponseCode(501);
  return {};
}

sub _create {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $inputData = $self->getInputData();

  if (!$resourceData->{'merchant'} || !$resourceData->{'customer'}) {
    $self->setResponseCode(400);
    return { 'status' => 'FAILURE', 'message' => 'Insufficient data sent in request.' };
  }

  my $attendant = new PlugNPay::Recurring::Attendant();
  $attendant->setCustomer(lc $resourceData->{'customer'});
  $attendant->setMerchant($resourceData->{'merchant'});
  $attendant->setAdditionalData($inputData);
  
  if ($attendant->saveAttendantSession()) {
      $self->setResponseCode(201);
      return {'status' => 'SUCCESS', 'message' => 'Attendant session for ' . $attendant->getCustomer() . ' was successfully created.', 'sessionID' => $attendant->getSessionID(), 'url' => $attendant->getURL()};
  }

  $self->setResponseCode(422);
  return {'status' => 'FAILURE', 'message' => 'Failed to create attendant session for ' . $attendant->getCustomer()};
}

1;
