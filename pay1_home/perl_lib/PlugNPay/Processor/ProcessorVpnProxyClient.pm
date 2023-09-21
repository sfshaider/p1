package PlugNPay::Processor::ProcessorVpnProxyClient;

use strict;

use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Util::Status;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub getHost {
  return $ENV{'PROCESSOR_VPN_PROXY_HOST'} || 'processor-vpn-proxy.local';
}

sub getProxyUrl {
  return sprintf('https://%s/proxy',getHost());
}

sub getPortInfoUrl {
  return sprintf('https://%s/ports',getHost());
}


sub httpRequest {
  my $self = shift;
  my $input = shift;

  my $method = uc $input->{'method'};
  if (!defined $method) {
    die('method is required');
  }

  my $headers = $input->{'headers'} || {};
  if (ref($headers) ne 'HASH') {
    die('headers must be a hashref');
  }

  foreach my $headerName (keys %{$headers}) {
    my $value = $headers->{'headerName'};
    if (ref($value) eq '') {
      $headers->{$headerName} = [$value];
    } elsif (ref($value) ne 'ARRAY') {
      die('header value must be an array ref or a scalar');
    }
  }

  my $url = $input->{'url'};
  if (!defined $url) {
    die('url is required');
  }

  my $data = $input->{'data'};

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setMethod('POST');
  $ms->setURL($self->getProxyUrl());
  $ms->setContent({
    method => $method,
    headers => $headers,
    url => $url,
    data => $data
  });

  my $status = new PlugNPay::Util::Status(1);

  my $msStatus = $ms->doRequest();
  if (!$msStatus) {
    $status->setFalse();
    $status->setError('request failed');

    my $response = $ms->getDecodedResponse();
    $status->setErrorMessage($response->{'message'});

    return $status;
  }

  my $response = $ms->getDecodedResponse();

  my $responseData = $response->{'data'};

  $status->set('data',$responseData);
}

sub getPortInfoForIdentifier {
  my $self = shift;
  my $identifier = shift;

  my $url = getPortInfoUrlForIdentifier($identifier);

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setMethod('GET');
  $ms->setURL($url);

  my $status = new PlugNPay::Util::Status(1);

  my $msStatus = $ms->doRequest();
  if (!$msStatus) {
    $status->setFalse();
    $status->setError('failed to get port information');
    return $status;
  }

  my $response = $ms->getDecodedResponse();

  $self->mapPortInfoForIdentifierResponseToStatus($response,$status);

  return $status;
}

sub getPortInfoUrlForIdentifier {
  my $self = shift;
  my $identifier = shift;

  my $baseUrl = getPortInfoUrl();
  return sprintf('%s/%s', $baseUrl, $identifier);
}

sub mapPortInfoForIdentifierResponseToStatus {
  my $self = shift;
  my $response = shift;
  my $status = shift;

  my $port = $response->{'port'};
  my $remoteHost = $response->{'remoteHost'};
  my $remotePort = $response->{'remotePort'};
  my $name = $response->{'name'};

  $status->set('name',$name);
  $status->set('port',$port);
  $status->set('localDestination',sprintf('%s:%s',$self->getHost(),$port));
  $status->set('remotePort',$remotePort);
  $status->set('remoteHost',$remoteHost);
}

1;