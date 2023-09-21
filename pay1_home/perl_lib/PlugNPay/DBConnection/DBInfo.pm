package PlugNPay::DBConnection::DBInfo;

use strict;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::AWS::ParameterStore;

our $info_cache;
our $key_cache;

sub getServiceName {
  return $ENV{'PNP_SERVICE_NAME'} || 'PAY1';
}

sub getDBInfoServer {
  my $envService = $ENV{'PNP_DBINFO_SERVER'};

  my $paramService;
  if (!defined $envService) {
    $paramService = PlugNPay::AWS::ParameterStore::getParameter('/DBINFO/SERVER',1);
    if (!defined $paramService) {
      print STDERR "Failed to read DBInfo service from parameter store.\n";
    }
  }

  my $service = $envService || $paramService;

  if (!$service) {
    print STDERR "DBInfo service is not defined in environment nor parameter store.\n";
  }

  return $service;
}

sub getDBInfoServiceKey {
  if (!$key_cache) {
    my $serviceName = getServiceName();
    my $serviceKeyNameParameter = '/DBINFO/SERVICE_KEY/' . uc($serviceName);
    my $key = PlugNPay::AWS::ParameterStore::getParameter($serviceKeyNameParameter,1);

    if ($key) {
      $key_cache = $key;
    } else {
      print STDERR "Failed to read DBInfo service key from parameter store.\n";
    }
  }

  return $key_cache;
}

sub getDBInfo {
  if (!$info_cache) {
    my $serviceName = getServiceName();
    my $server = getDBInfoServer();
    my $key = getDBInfoServiceKey();
    my $data = { key => $key };

    my $url = $server . '/service/' . lc($serviceName);

    my $ms = new PlugNPay::ResponseLink::Microservice();
    $ms->setURL($url);
    $ms->setMethod('POST');
    $ms->setContentType('application/json');
    $ms->setTimeout(10); # 2 is too short.

    my $response;
    if (!$ms->doRequest($data)) {
      die('Failed to get db info!');
    }

    $response = $ms->getDecodedResponse();

    if (!$response) {
      die('No db info response!')
    }

    $info_cache = $response->{'credentials'};
  }

  return $info_cache;
}

1;
