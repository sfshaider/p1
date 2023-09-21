package PlugNPay::ResponseLink::LocalProxy;

use strict;
use warnings FATAL => 'all';

use LWP::UserAgent;
use HTTP::Request;
use PlugNPay::ResponseLink::LocalProxy::Response;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub getProxyServer {
  # this shouldln't change lolbbq
  return 'http://localhost:8080/proxy';
}

sub do {
  my $self = shift;
  my $request = shift;

  if (ref($request) ne 'PlugNPay::ResponseLink::LocalProxy::Request') {
    die('input is not a request object');
  }

  my $userAgent = new LWP::UserAgent;
  $userAgent->agent('ResponseLink LocalProxy Client');

  # give proxy an additional second to respond
  $userAgent->timeout($request->getTimeoutSeconds() + 30);
  $userAgent->parse_head(0);

  my $proxyUrl = $self->getProxyServer();
  my $uaRequest = new HTTP::Request('POST' => $proxyUrl);

  $uaRequest->content_type('application/json');
  $uaRequest->content($request->toJson());

  my $result = $userAgent->request($uaRequest);
  my $response = new PlugNPay::ResponseLink::LocalProxy::Response({ response => $result });
  return $response;
}


1;