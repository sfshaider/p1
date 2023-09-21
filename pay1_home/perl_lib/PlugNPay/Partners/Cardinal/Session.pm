package PlugNPay::Partners::Cardinal::Session;

use strict;
use PlugNPay::Die;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Logging::DataLog;
use PlugNPay::GatewayAccount::InternalID;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub getCustomerId {
  my $self = shift;
  my $gatewayAccount = shift;
  my $customerId = '';

  my $iid = new PlugNPay::GatewayAccount::InternalID();
  $customerId = $iid->getIdFromUsername($gatewayAccount);

  return $customerId;
}

sub generate {
  my $self = shift;
  my $gatewayAccount = shift;
  my $sessionId = '';

  my $customerId = $self->getCustomerId($gatewayAccount);
  # force customerId to a number rather than a string
  $customerId = $customerId + 0;
  my $data = { 'customerId' => $customerId };

  my $serviceURL = 'http://proc-cardinal.local/create-session';
  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($serviceURL);
  $ms->setMethod('POST');
  $ms->setContentType('application/json');
  $ms->setContent($data);
  my $success = $ms->doRequest();
  my $responseCode = $ms->getResponseCode();
  my $rawResponse = $ms->getRawResponse();
  my $decodedResponse = $ms->getDecodedResponse();

  if ($success == 0 || $responseCode != 200) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'proc-cardinal' });
    $logger->log({
      'account'      => $gatewayAccount,
      'message'      => 'failed to generate session for CardinalCruise',
      'endpoint'     => $serviceURL,
      'responseCode' => $responseCode,
      'rawResponse'  => $rawResponse
    });
    die('failed to generate session for CardinalCruise ', $ms->getErrors());
  } else {
    $sessionId = $decodedResponse->{'sessionId'};
  }

  return $sessionId;
}

1;