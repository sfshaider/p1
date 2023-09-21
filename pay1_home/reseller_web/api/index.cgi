#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::API::REST;
use PlugNPay::GatewayAccount::APIKey;
use PlugNPay::API::REST::Session;
use PlugNPay::Logging::MessageLog;
use PlugNPay::Logging::Performance;

my $performanceLogger = new PlugNPay::Logging::Performance('RESTful API start');
$ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};

my $logger = new PlugNPay::Logging::MessageLog();

my $rest = new PlugNPay::API::REST('/api');
$performanceLogger->addMetadata({'uri' => $rest->getResourcePath(), 'data' => $rest->getResourceData()});

# authenticate the request
my $apiAccount = $rest->getRequestHeader('X-Gateway-Account');
my $apiKeyName = $rest->getRequestHeader('X-Gateway-API-Key-Name');
my $apiKey     = $rest->getRequestHeader('X-Gateway-API-Key');
my $sessionID  = $rest->getRequestHeader('X-Gateway-Session');
my $origin     = $rest->getRequestHeader('Origin');

$logger->log("Origin Header: " . $origin, {context => 'REST API',vendor => 'PlugNPay'});

eval {
  # create api key object to verify the api key
  if (defined $sessionID ) { 
    my $sessionAuth = new PlugNPay::API::REST::Session($sessionID);
    my $auth = $sessionAuth->authenticate();
    my @domain = grep{$_ eq $origin} @{$sessionAuth->loadDomains($sessionID)};
    my $gatewayAccount = $sessionAuth->getGatewayAccount();
    $rest->setResponseACAOHeader(join(',',@domain)); 
  
    if ($auth->{'status'} && $rest->allowsSessionAuth()) {
      $rest->setRequestGatewayAccount($gatewayAccount);
      print $rest->respond();
    } else { 
      my $message = $auth->{'message'};
      if ($auth->{'status'}) {
        $message = 'Session Authentication not allowed';
      }
      $rest->setError('Authentication Failure: ' . $message);
      print $rest->_respond(403,{});
    }
  } elsif (defined $origin && $rest->allowsSessionAuth()) {
    my $validOrigin = new PlugNPay::API::REST::Session()->domainExists($origin);
    if ($validOrigin) {
      $rest->setResponseACAOHeader($origin);
      print $rest->_respond(200,{});
    } else {
      print $rest->_respond(403,{});
    }
  } else {
    my $apiKeyAuth = new PlugNPay::GatewayAccount::APIKey({ gatewayAccount => $apiAccount, keyName => $apiKeyName});
  
    # verify the authentication data
    if ($apiAccount && $apiKeyName && $apiKey && $apiKeyAuth->verifyKey($apiKey)) {
      print $rest->respond();
    } else {
      $rest->setError('Authentication Failure.');
      print $rest->_respond(403,{});
    }
  }
  
};

if ($@) {
  $logger->log('Bad API authentication: ' . $@);
  $rest->setError('Authentication Failure.');
  print $rest->_respond(403,{});
}

# Write and clear performance log singleton
$performanceLogger = new PlugNPay::Logging::Performance('RESTful API end');
$performanceLogger->write();

# Close DB connections
my $dbs = new PlugNPay::DBConnection();
$dbs->closeConnections();
exit;
