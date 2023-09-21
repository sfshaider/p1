package PlugNPay::AWS::Lambda;

use strict;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::AWS::ParameterStore;
use PlugNPay::Die;
use PlugNPay::ConfigService;

our $__cachedHost;

sub getServiceHost {
   if (!$__cachedHost) {
    my $envServiceHost = $ENV{'PNP_LAMBDA_PROXY_SERVICE'};

    my $configServiceHost;
    if ($envServiceHost eq '') {
      my $configService = new PlugNPay::ConfigService();
      my $config = $configService->getConfig({
        apiVersion => 1,
        name => 'pay1',
        formatVersion => 1
      });

      $configServiceHost = $config->{'lambdaService'}{'host'};
      if ($configServiceHost eq '') {
        die("Failed to load lambda proxy service host info from config service");
      }
    }
    $__cachedHost = $envServiceHost || $configServiceHost;
    $__cachedHost =~ s/\/+$//;
  } 

  return $__cachedHost;
}

sub invoke {
  my $args = shift;

  my $data;
  if (-e '/home/pay1/etc/lambda_proxy') {
    $data = &_invokeProxy($args);
  } else {
    require PlugNPay::AWS::Lambda::LambdaPython;
    $data = &PlugNPay::AWS::Lambda::LambdaPython::invokeWithPython($args);
  }

  return $data;
}

#New way using proxy
sub _invokeProxy {
  my $args = shift;
  my $lambdaName = $args->{'lambda'};
  # it seems some code calls it with a capital i?
  # fixed in PlugNPay::Util::Temp but it may be elsewhere in the code as well...
  my $invocationType = $args->{'invocationType'} || $args->{'InvocationType'}; 
  my $data = $args->{'data'};

  if (!$lambdaName || !$invocationType) {
    die("Missing lambda name ($lambdaName) or invocation type ($invocationType) from invoke request in PlugNPay::AWS::Lambda\n");
  }

  my $resultData = {};
  my $rl = new PlugNPay::ResponseLink::Microservice();

  eval {
    my $host = &getServiceHost();
    my $url = sprintf("%s/v1/lambda",$host);

    $rl->setURL($url);
    $rl->setMethod('POST');
    $rl->setContentType('application/json');
    $rl->setTimeout(60 || $args->{'timeout'});
    my $reqStatus = $rl->doRequest({
      'name' => $lambdaName,
      'invokeType' => $invocationType,
      'data' => $data
    });

    if (lc($invocationType) eq 'requestresponse') {
      $resultData = $rl->getDecodedResponse();
    } else {
      $resultData->{'status'} = $reqStatus && $rl->getResponseCode < 300 ? 'success' : 'problem';
    }
  };

  if ($@) {
    die($@);
  }

  return $resultData;
}





1;
