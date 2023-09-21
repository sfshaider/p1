package PlugNPay::Transaction::Response::JSON;

use strict;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub responseToJSON {
  my $self = shift;
  my $response = shift;

  my $responseJSON = {};
  $responseJSON->{'status'}            = $response->getStatus();
  $responseJSON->{'errorMessage'}      = $response->getErrorMessage();
  $responseJSON->{'avsResponse'}       = $response->getAVSResponse();
  $responseJSON->{'authorizationCode'} = $response->getAuthorizationCode();
  $responseJSON->{'cvvResponse'}       = $response->getSecurityCodeResponse();
  $responseJSON->{'fraud'}             = $response->getFraudMessage();
  $responseJSON->{'isDuplicate'}       = $response->getDuplicate();
 
  return $responseJSON;
}

1;
