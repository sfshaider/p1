package PlugNPay::Token::Client;

use strict;
use LWP::UserAgent;
use LWP::Debug qw(+);
use HTTP::Request;
use PlugNPay::Token::Response;
use PlugNPay::Environment;
use PlugNPay::AWS::ParameterStore;
use PlugNPay::Logging::DataLog;
use PlugNPay::Metrics;
use PlugNPay::ResponseLink::Microservice;

our $cachedServer;

# Example
#
#  my $req = new  PlugNPay::Token::Request();
#  $req->setRequestType('REQUEST_TOKENS');
#  $req->addCardNumber('card1','4111111111111111');
#
#  my $client = new PlugNPay::Token::Client();
#  $client->setRequest($req);
#  my $resp = $client->getResponse();
#  print $resp->get('card1') . "\n";
#

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;


  return $self;
}

sub setRequest {
  my $self = shift;
  my $request = shift;

  $self->{'request'} = $request;
  delete $self->{'response'};
}

sub getServer {
  if (!defined $cachedServer || $cachedServer eq '') {
    my $env = $ENV{'PNP_RESTFUL_TOKEN'} || $ENV{'PNP_TOKEN_SERVER'};
    $cachedServer = $env || PlugNPay::AWS::ParameterStore::getParameter('/TOKEN/SERVER',1);
  }

  die("Failed to load token server") if $cachedServer eq '';

  return $cachedServer;
}

sub doRequest {
  my $self = shift;
  my $content;

  if ($self->{'request'}) {
    eval {
      my $content = $self->{'request'}->getRequestDataRef();

      my $server = getServer();

      my $ms = new PlugNPay::ResponseLink::Microservice();
      $ms->setURL($server);
      $ms->setMethod('POST');
      $ms->setContent($content);

      # start time for calculating request duration
      my $metrics = new PlugNPay::Metrics();
      my $start = $metrics->timingStart();

      my $success = $ms->doRequest();
      
      my $response = $ms->getRawResponse();

      $metrics->timingEnd({
        metric => 'service.token.response_time',
        start => $start
      });

      
      if ($success) {
        my $req = $self->{'request'};
        my $respData = new PlugNPay::Token::Response($response,$req->getRequestType);
        $self->{'response'} = $respData;


        return 1;
      }
    };
    if ($@) {
      my $logger = new PlugNPay::Logging::DataLog({ collection => 'perl_tokenserver_client' });
      $logger->log({ error => 'token server request failed', message => $@ });
    }
  }
  return 0;
}

sub getResponse {
  my $self = shift;
  if (!$self->{'response'}) {
    $self->doRequest();
  }
  return $self->{'response'} || new PlugNPay::Token::Response();
}

1;
