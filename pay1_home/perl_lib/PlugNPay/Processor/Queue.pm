package PlugNPay::Processor::Queue;

use strict;
use warnings;
use PlugNPay::ResponseLink;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Logging::DataLog;

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;

  return $self;
}

sub setProcessorName {
  my $self = shift;
  my $processor = shift;
  $self->{'processor'} = $processor;
}

sub getProcessorName {
  my $self = shift;
  return $self->{'processor'};
}

sub setUsername {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return $self->{'username'};
}

sub setOrderID {
  my $self = shift;
  my $orderID = shift;
  $self->{'orderID'} = $orderID;
}

sub getOrderID {
  my $self = shift;
  return $self->{'orderID'};
}

sub setData {
  my $self = shift;
  my $data = shift;
  $self->{'data'} = $data;
}

sub getData {
  my $self = shift;
  return $self->{'data'};
}

sub setUrl {
  my $self = shift;
  my $url = shift;
  $self->{'url'} = $url;
}

sub getUrl {
  my $self = shift;
  return $self->{'url'};
}

sub sendForProcessing {
  my $self = shift;
  my $url = shift || $self->getUrl();
  my $processor = shift || $self->getProcessorName();
  my $username = shift || $self->getUsername();
  my $orderID = shift || $self->getOrderID();
  my $data = shift || $self->getData();
  my $requestHelper = new PlugNPay::ResponseLink();
  my $logger = new PlugNPay::Logging::DataLog({"collection" => "proc_queue_collection"});
  $requestHelper->setRequestURL($url);
  $requestHelper->setRequestMode("DIRECT");
  $requestHelper->setRequestContentType('application/x-www-form-urlencoded');
  $requestHelper->setRequestData({'processor' => $processor, 'username' => $username, 'orderID' => $orderID, 'data' => $data});

  $requestHelper->doRequest();
  my $errors = $requestHelper->getErrors();
  if(!$errors) {
    $logger->log("sending data for processing");
    return $requestHelper->getResponseContent();
  } else {
    $logger->log("Error(s) occured $errors");	  
    return $errors;
  }
}

sub serverRead {
  my $self = shift;
  my $processor = shift || $self->getProcessorName();
  my $url = shift || $self->getUrl();
  my $queryStr = "processor?=$processor";
  my $requestHelper = new PlugNPay::ResponseLink();
  $requestHelper->setRequestURL($url . $queryStr);
  $requestHelper->setRequestMethod('GET');
  $requestHelper->setRequestMode('DIRECT');
  $requestHelper->doRequest();
  my $logger = new PlugNPay::Logging::DataLog({"collection" => "proc_queue_collection"});
  my $errors = $requestHelper->getErrors();
  if (!$errors) {
    $logger->log("reading data from server");	  
    return $requestHelper->getResponseContent();
  } else {
    $logger->log("Error(s) occured $errors");
    return $errors;
  }
}

sub serverRespond {
  my $self = shift;
  my $url = shift || $self->getUrl();
  my $data = shift || $self->getData();
  my $requestHelper = new PlugNPay::ResponseLink::Microservice();
  my $logger = new PlugNPay::Logging::DataLog();
  $requestHelper->setMethod('POST');
  $requestHelper->setContentType("application/json");
  $requestHelper->setURL($url);
  $logger->log("sending response to client");
  $requestHelper->doRequest($data);
}

1;
