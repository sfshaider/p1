#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::API::REST;
use PlugNPay::Environment;
use PlugNPay::CGI;
use PlugNPay::Security::CSRFToken;
use PlugNPay::Logging::Performance;
use PlugNPay::Logging::MessageLog;

PlugNPay::Logging::Performance::init();
my $performanceLogger = new PlugNPay::Logging::Performance('Reseller RESTful API start');

my $env = new PlugNPay::Environment();
my $reseller = $env->get('PNP_ACCOUNT');

my $rest = new PlugNPay::API::REST('/admin/api',{ context => 'reseller-admin'});
$performanceLogger->addMetadata({'uri' => $rest->getResourcePath(), 'data' => $rest->getResourceData()});

# get the reques token
my $requestToken = $rest->getRequestHeader('X-Gateway-Request-Token');
my $tokenVerifier = new PlugNPay::Security::CSRFToken();
$tokenVerifier->setToken($requestToken);

eval {
  if ($requestToken ne '' && $tokenVerifier->verifyToken()) {
    # set the reseller as the requesting gateway account, since headers can not be trusted
    $tokenVerifier->activity();
    $rest->setRequestGatewayAccount($reseller);
  
    # set the reseller in the resource data as well
  
    $rest->getResourceData()->{'reseller'} = $reseller if !defined $rest->getResourceData()->{'reseller'};
    my @resource = @{$rest->getResourcePath()};
    my $resourceIndex = 0;
    my $resourceElement = $resource[$resourceIndex];
    my $resourceData = $rest->getResourceData();
    my $action = $rest->getAction();
    print $rest->respond();
  }
};

if ($@) {
  my $logger = new PlugNPay::Logging::MessageLog();
  $logger->log('Bad API authentication: ' . $@);
  $rest->setError('Authentication Failure.');
  print $rest->_respond(403,{});
}

# Write and clear performance log singleton
$performanceLogger = new PlugNPay::Logging::Performance('Reseller RESTful API end');
$performanceLogger->write();

# Close DB connections
my $dbs = new PlugNPay::DBConnection();
$dbs->closeConnections();
exit;

