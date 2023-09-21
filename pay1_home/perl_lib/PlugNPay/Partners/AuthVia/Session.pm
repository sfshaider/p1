package PlugNPay::Partners::AuthVia::Session;

use strict;
use PlugNPay::Die;
use PlugNPay::Util::UniqueID;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::AWS::ParameterStore qw(getParameter);

our $_authViaMicroserviceURL;

sub getServiceURL {
  if (!$_authViaMicroserviceURL) {
    $_authViaMicroserviceURL = &PlugNPay::AWS::ParameterStore::getParameter('/SERVICE/AUTHVIA/URL');
  }
  return $_authViaMicroserviceURL;
}

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub generate {
  my $self = shift;
  my $gatewayAccount = shift;
  my $uuid = new PlugNPay::Util::UniqueID()->generate();
  my $data = {'sessionId' => $uuid, 'gatewayAccount' => $gatewayAccount};

  my $ms = new PlugNPay::ResponseLink::Microservice($self->getServiceURL() . '/security/session');
  $ms->setMethod('POST');
  my $success = $ms->doRequest($data);
  if ($success == 0 || $ms->getResponseCode() == 520) {
    die ('failed to generate session for AuthVia', $ms->getErrors());
  }
  
  return $uuid;
}

1;
