package PlugNPay::AWS::Kinesis;

use strict;
use PlugNPay::ResponseLink::Microservice; 
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Status;

sub new {
  my $class = shift;
  my $self = {};

  bless $self, $class;

  my $streamName = shift;
  if ($streamName ne '') {
    $self->setStreamName($streamName);
  }

  return $self;
}

sub setStreamName {
  my $self = shift;
  my $streamName = shift;

  $self->{'streamName'} = $streamName;
}

sub getStreamName {
  my $self = shift;
  return $self->{'streamName'};
}

sub insertData {
  my $self = shift;
  my $streamName = shift || $self->getStreamName();
  my $data = shift;
  my $url = shift;

  my $responseLink = new PlugNPay::ResponseLink::Microservice();
  $responseLink->setURL($url);
  $responseLink->setMethod("POST");
  $responseLink->setContent($data);
  $responseLink->setContentType("application/json");
  $responseLink->setTimeout(1);
  
  my $logger = new PlugNPay::Logging::DataLog({ "collection" => "kinesis" });
  my $status = new PlugNPay::Util::Status(1);
  
  my $isSuccess = $responseLink->doRequest();
  
  if (!$isSuccess) {
    $status->setFalse();
    $status->setError("Failed to insert data into stream: " . $streamName);
    $status->setErrorDetails($responseLink->getErrors());
    $logger->log({ 
      "streamName" => $streamName,
      "status" => $status->getStatus(), 
      "message" => $status->getErrorDetails() 
    });
  }
  
  return $status;
}

1;
