package PlugNPay::API::REST::Responder::Session;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::API::REST::Session;
use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  
  if (lc($action) eq 'create') {
    $self->setResponseCode(201);
    return $self->_create();
  } else {
    return $self->_read();
  }
}

sub _create {
  my $self = shift;
  my $requestData = $self->getInputData();
  my $session = new PlugNPay::API::REST::Session();
  my $time = new PlugNPay::Sys::Time();
  my $expires = $requestData->{'expirationTime'};

  if (!defined $expires) {
    $time->addHours(1);
  } else {
    $time->fromFormat('db',$expires);
  }
  $session->setExpireTime($time->inFormat('db'));
  
  if (defined $requestData->{'multiUse'} && $requestData->{'multiUse'} eq 'true') {
    $session->setMultiUse();
  } else {
    $session->setSingleUse();
  }

  #Set valid domains for use with session Key
  my $domainArray = $requestData->{'domains'};
  $session->setValidDomains($domainArray);

  my $id = $session->generateSessionID($self->getGatewayAccount());

  return { 'session_id' => $id };
}

sub _read {
  my $self = shift;
  my $data = $self->getResourceData()->{'session'};
  if (defined $data) {
    my $session = new PlugNPay::API::REST::Session();
    my $time = $session->checkTimeLeft($data);
    $self->setResponseCode(200);

    return $time;
  } else {
    $self->setResponseCode(400);
    
    return {'status' => 'failed', 'message' => 'Bad Request'};
  }
}

1;
