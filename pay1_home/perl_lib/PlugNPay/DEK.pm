package PlugNPay::DEK;

use strict;
use warnings;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Logging::DataLog;

sub new {
  my $self = {};
  my $class = shift;

  bless $self, $class;
  return $self;
}

sub getKey {
  my $self = shift;
  return $self->{'key'};
}

sub setKey {
  my $self = shift;
  my $key = shift;
  $self->{'key'} = $key;
}

sub getDEKString {
  my $self = shift;
  return $self->{'dek_string'};
}

sub setDEKString {
  my $self = shift;
  my $dekString = shift;
  $self->{'dek_string'} = $dekString;
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

sub requestKey {
  my $self = shift;
  my $key = shift || $self->getKey();
  my $url = shift || $self->getUrl();
  my $requestHelper = new PlugNPay::ResponseLink::Microservice();
  $requestHelper->setURL($url . $key);
  $requestHelper->setContentType('application/json');
  $requestHelper->setMethod('GET');
  my $logger = new PlugNPay::Logging::DataLog({"collection" => "dek_collection"});
  my $response;
  eval {
    $requestHelper->doRequest();
    $response = $requestHelper->getDecodedResponse();
  };

  if ($@) {
    $logger->log("An error occured when trying to perform your request $@");
    die "An error occured when trying to perform your request $@";
  }
  $logger->log("key request was successful");
  return $response;
}

sub createKeyAndString {
  my $self = shift;
  my $key = shift || $self->getKey();
  my $url = shift || $self->getUrl();
  my $dekString = shift || $self->getDEKString();
  my $requestHelper = new PlugNPay::ResponseLink::Microservice();
  $requestHelper->setURL($url . $key);
  $requestHelper->setContentType('application/x-www-form-urlencoded');
  $requestHelper->setMethod('POST');
  $requestHelper->setContent({"dek_string" => $dekString});
  my $logger = new PlugNPay::Logging::DataLog({"collection" => "dek_collection"});
  my $response;
  eval {
    $requestHelper->doRequest();
    $response = $requestHelper->getDecodedResponse();
  };
  if ($@) {
    $logger->log("An error occured when trying to perform your request $@");
    die "An error occured when trying to perform your request $@";
  }
  $logger->log("key created succesfully");
  return $response;
}

1;
