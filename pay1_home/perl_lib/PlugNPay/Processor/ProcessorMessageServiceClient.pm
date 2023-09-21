package PlugNPay::Processor::ProcessorMessageServiceClient;

use strict;

use PlugNPay::Processor::ProcessorMessageServiceClient::ProcessTransactionRequest;
use PlugNPay::Processor::ProcessorMessageServiceClient::GetTransactionsRequest;
use PlugNPay::Processor::ProcessorMessageServiceClient::PostTransactionResultRequest;

use PlugNPay::ResponseLink::Microservice;

use PlugNPay::Util::Status;

use PlugNPay::Die;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub getHost {
  return $ENV{'PROCESSOR_MESSAGE_HOST'} or die('PROCESSOR_MESSAGE_HOST environment variable not set');
}

sub newProcessTransactionRequest {
  return new PlugNPay::Processor::ProcessorMessageServiceClient::ProcessTransactionRequest();
}

sub newGetTransactionsRequest {
  return new PlugNPay::Processor::ProcessorMessageServiceClient::GetTransactionsRequest();
}

sub newPostTransactionResultRequest {
  return new PlugNPay::Processor::ProcessorMessageServiceClient::PostTransactionResultRequest();
}

sub sendRequest {
  my $self = shift;
  my $request = shift;

  my $status = new PlugNPay::Util::Status(1);

  my $timeout = 60;

  # if the request has a timeout, add 5 seconds to it.
  eval {
    $timeout = $request->getTimeout() + 5.0;
  };

  my $url = $request->getURL();
  my $method = $request->getMethod();
  my $json = undef;
  if ($method ne 'GET') {
    my $jsonStatus = $request->toJSON();
    if ($jsonStatus) {
      $json = $jsonStatus->get('json');
    } else {
      $status->setError('Failed to encode json data');
      $status->setFalse();
      return $status;
    }
  }

  my $fullUrl = sprintf('%s/%s',getHost(), $url);
  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($fullUrl);
  $ms->setMethod($method);
  $ms->setJSON($json);
  $ms->setTimeout($timeout);

  my $ok = $ms->doRequest();

  my $status = new PlugNPay::Util::Status(1);

  if (!$ok) {
    my $errorsArrayRef = $ms->getErrors();
    my $errorString = join('; ',@{$errorsArrayRef});
    $status->setError($errorString);
    $status->setFalse();
    return $status;
  }

  my $jsonResponse = $ms->getRawResponse();

  my $response = $request->getResponse();
  $response->fromJSON($jsonResponse);
  $status->set('response',$response);

  return $status;
}

1;