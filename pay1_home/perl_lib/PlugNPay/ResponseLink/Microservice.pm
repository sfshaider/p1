package PlugNPay::ResponseLink::Microservice;

use strict;
use LWP::UserAgent;
use HTTP::Request;
use JSON::XS;
use PlugNPay::Logging::DataLog;
use PlugNPay::ResponseLink::LocalProxy::Request;
use PlugNPay::ResponseLink::LocalProxy;
use PlugNPay::Debug;
use Time::HiRes;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $serviceURL = shift;
  if ($serviceURL) {
    $self->setURL($serviceURL);
  }

  $self->{'errors'} = [];

  return $self;
}

sub setURL {
  my $self = shift;
  my $URL = shift;
  $self->{'URL'} = $URL;
}

sub getURL {
  my $self = shift;
  return $self->{'URL'};
}

sub addError {
  my $self = shift;
  my $error = shift;

  push @{$self->{'errors'}}, $error;
}

sub getErrors {
  my $self = shift;

  return  $self->{'errors'} || [];
}

sub setMethod {
  my $self = shift;
  my $method = shift;
  $self->{'method'} = $method;
}

sub getMethod {
  my $self = shift;
  return $self->{'method'} || 'OPTIONS';
}

sub setContent {
  my $self = shift;
  $self->setData(@_);
}

sub getContent {
  my $self = shift;
  return $self->getData(@_);
}

sub setData {
  my $self = shift;
  my $content = shift;
  $self->{'data'} = $content;
}

sub getData {
  my $self = shift;
  return $self->{'data'} || {};
}

sub setJSON {
  my $self = shift;
  my $json = shift;
  $self->{'jsonContent'} = $json;
}

sub getJSON {
  my $self = shift;
  return $self->{'jsonContent'};
}

sub setContentType {
  my $self = shift;
  my $contentType = shift;
  $self->{'contentType'} = $contentType;
}

sub getContentType {
  my $self = shift;
  return $self->{'contentType'} || 'application/json';
}

sub setRawResponse {
  my $self = shift;
  my $rawResponse = shift;
  $self->{'rawResponse'} = $rawResponse;
}

sub getRawResponse {
  my $self = shift;
  return $self->{'rawResponse'};
}

sub setResponseCode {
  my $self = shift;
  my $responseCode = shift;
  $self->{'responseCode'} = $responseCode;
}

sub getResponseCode {
  my $self = shift;
  return $self->{'responseCode'};
}

sub setDecodedResponse {
  my $self = shift;
  my $decodedResponse = shift;
  $self->{'decodedResponse'} = $decodedResponse;
}

sub getDecodedResponse {
  my $self = shift;

  my $decoded;
  eval {
    $decoded = decode_json($self->{'rawResponse'});
    $self->{'decodedResponse'} = $decoded;
  };

  if ($@) {
    $self->addError($@);
    my $logger = new PlugNPay::Logging::DataLog({ collection => 'microservice-general' });
    # $logger->log({error => $@, url => $self->getURL(), raw => $self->{'rawResponse'}});
  }

  return $decoded;
}

sub setTimeout {
  my $self = shift;
  my $timeout = shift;
  $self->{'timeout'} = $timeout;
}

sub getTimeout {
  my $self = shift;
  return $self->{'timeout'};
}

sub setDebug {
  my $self = shift;
  $self->{'_debug_'} = 1;
}

sub unsetDebug {
  my $self = shift;
  $self->{'_debug_'} = 0;
}

sub debugEnabled {
  my $self = shift;
  return $self->{'_debug_'} == 1;
}

sub doRequest {
  my $self = shift;
  my $data = shift;

  my $logger = new PlugNPay::Logging::DataLog({ collection => 'microservice-general' });

  if (!$data) {
    $data = $self->getData();
  }

  my $success = 1;
  eval {
    my $method = $self->getMethod();
    my $url = $self->getURL();

    my $json = $self->getJSON();
    if (!defined $json) {
      $json = encode_json($data);
    }

    my $contentType = 'application/json'; # only supported content type by this module

    my $request = new PlugNPay::ResponseLink::LocalProxy::Request();
    $request->setMethod($method);
    $request->setUrl($url);
    if ($method ne 'get') {
      $request->setContent($json);
      $request->setContentType($contentType);
    }

    my $timeout = $self->getTimeout();
    if ( $timeout && $timeout =~ /^\d+$/) {
      $request->setTimeoutSeconds($timeout)
    }    

    $request->addHeader('Accept', 'application/json');
    $request->setInsecure(); # pretty much always for internal until all in ecs

    my $localProxy = new PlugNPay::ResponseLink::LocalProxy();
    my $debugStart = Time::HiRes::time();
    my $response = $localProxy->do($request);
    my $debugEnd = Time::HiRes::time();

    if ($ENV{'DEBUG_MICROSERVICE_DURATION'} eq 'TRUE') {
      my $duration = $debugEnd - $debugStart;
      print STDERR "MICROSERVICE: url: $url, duration: $duration seconds\n";
    }

    my $json = $response->getContent();
    $self->setRawResponse($json);
    my ($code,$message) = split(/\s/,$response->getStatus());
    $self->setResponseCode($code);

    if ($response->isSuccess()) {
      $success = 1;
    } else {
      $self->addError($response->getStatus());
      $self->addError($response->getContent());
      $success = 0;
    }
  };

  if ($@) {
    $self->setRawResponse('{"error":"' . $@ . '", "status":"failure"}');
    $self->setResponseCode('520');
    $self->setDecodedResponse({});
    $self->addError($@);
    $success = 0;
  }

  if ($self->debugEnabled()) {
    debug {
      message => 'microservice request',
      url => $self->getURL(),
      requestContent => $data,
      requestContentType => $self->getContentType,
      repsonseRawContent => $self->getRawResponse(),
      responseContent => $self->getDecodedResponse(),
      responseCode => $self->getResponseCode(),
      errors => $self->getErrors()
    };
  }

  return $success;
}

1;
