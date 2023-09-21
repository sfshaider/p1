package PlugNPay::Security::JWT;

use strict;
use PlugNPay::Die;
use PlugNPay::AWS::Lambda;
use PlugNPay::AWS::ParameterStore qw(getParameter);

our $_JWTLambdaName;
sub getLambdaName {
  if (!$_JWTLambdaName) {
    $_JWTLambdaName = $ENV{'JWT_LAMBDA_NAME'} || &PlugNPay::AWS::ParameterStore::getParameter('/SERVICE/LAMBDA/JWT');
  }

  return $_JWTLambdaName;
}

sub generate {
  my $data = shift;
  if (!defined $data || ref($data) ne 'HASH') {
    die 'missing data to create JWT';
  }

  my $claims = {};
  if (ref($data->{'claims'}) eq 'HASH') {
    $claims = $data->{'claims'};
  }

  my $lambda = &getLambdaName();
  my $secretType = $data->{'secretType'} || "RS256";
  my $requestData = { 
    'secretType'    => $secretType,
    'claims'        => $claims,
    'action'        => 'create'
  };

  if (defined $data->{'secretKeyName'} && $data->{'secretKeyName'} ne '') {
    $requestData->{'secretKeyName'} = $data->{'secretKeyName'};
  }

  my $response = &PlugNPay::AWS::Lambda::invoke({'lambda' => $lambda, 'invocationType' => 'RequestResponse', 'data' => $requestData});

  my $token;
  if (ref($response->{'payload'}) eq 'HASH') {
    my $error = $response->{'payload'}{'errorMessage'};
    if (defined $error || $error ne '') {
      die 'Failed to generate token: ' . $error;
    }
    $token = $response->{'payload'}{'token'};
  } else {
    fail('Failed to generate token: nil response from server');
  }

  return $token;
}

sub isValidToken {
  my $token = shift;
  my $lambda = &getLambdaName();
  my $requestData = {
    'tokenString' => $token,
    'action'      => 'verify'
  };
  
  my $response = &PlugNPay::AWS::Lambda::invoke({'lambda' => $lambda, 'invocationType' => 'RequestResponse', 'data' => $requestData});
  my $isValid = 0;
  if (ref($response->{'payload'}) eq 'HASH') {
    $isValid = $response->{'payload'}{'valid'};
  }

  return $isValid;
}

1;
