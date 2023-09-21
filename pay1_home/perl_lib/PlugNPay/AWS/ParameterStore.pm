package PlugNPay::AWS::ParameterStore;

use strict;
use PlugNPay::Die;
use PlugNPay::Logging::DataLog;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::ConfigService;

our $__cachedHost;

sub getServiceHost {
   if (!$__cachedHost) {
    my $envServiceHost = $ENV{'PNP_PARAMETER_STORE_PROXY'};

    my $configServiceHost;
    if ($envServiceHost eq '') {
      my $configService = new PlugNPay::ConfigService();
      my $config = $configService->getConfig({
        apiVersion => 1,
        name => 'pay1',
        formatVersion => 1
      });

      $configServiceHost = $config->{'paramService'}{'host'};
      if ($configServiceHost eq '') {
        die("Failed to load parameter store proxy service host info from config service");
      }
    }
    $__cachedHost = $envServiceHost || $configServiceHost;
    $__cachedHost =~ s/\/+$//;
  } 

  return $__cachedHost;
}

sub getParameter {
  my $parameterName = shift;
  my $withDecryption = shift;
  my $parameter;
  
  $parameter = &_getParameterWithProxy($parameterName,$withDecryption);

  return $parameter;
}

# New way, uses proxy
sub _getParameterWithProxy {
  my $parameterName = shift;
  my $withDecryption = shift;
  if (!defined $parameterName) {
    die('no parameter name set!');
  }


  my $parameterData;
  eval {
    my $requestData = {'names' => [$parameterName]};

    my $host = getServiceHost();
    my $url = sprintf('%s/v1/parameter',$host);

    my $ms = new PlugNPay::ResponseLink::Microservice($url);
    $ms->setMethod('POST');
    if (!$ms->doRequest($requestData)) {
      die ("failed to call proxy, see logs for more details");
    }

    $parameterData = $ms->getDecodedResponse();
  };

  my $parameterValue = '';
  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'aws_parameter_store'});
    $logger->log({'parameter' => $parameterName, 'withDecryption' => $withDecryption, 'error' => $@});
  } else {
    if (!$parameterData->{'error'} && ref($parameterData->{'parameters'}) eq 'HASH') {
      $parameterValue = $parameterData->{'parameters'}{$parameterName};
    }
  }

  return $parameterValue;
}

1;
