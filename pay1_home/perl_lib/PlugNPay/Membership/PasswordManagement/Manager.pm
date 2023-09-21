package PlugNPay::Membership::PasswordManagement::Manager;

use strict;
use PlugNPay::AWS::Lambda;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::AWS::ParameterStore;

our $PNP_PASSWORD_MANAGEMENT_LAMBDA;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  if (!defined $PNP_PASSWORD_MANAGEMENT_LAMBDA) {
    &PlugNPay::Membership::PasswordManagement::Manager::loadParameters();
  }

  return $self;
}

sub loadParameters {
  $PNP_PASSWORD_MANAGEMENT_LAMBDA = &PlugNPay::AWS::ParameterStore::getParameter('/PAY1/MEMBERSHIP/PASSWORD_REMOTE_LAMBDA');
}

##################################
# Subroutine: deleteCustomer
# --------------------------------
# Description:
#   Invokes an AWS lambda that 
#   does a GET request with mode
#   DELETE to remove a username 
#   on a remote server.
sub deleteCustomer {
  my $self = shift;
  my $requestData = shift;

  my $status = new PlugNPay::Util::Status(1);

  my $response = &PlugNPay::AWS::Lambda::invoke({
    'lambda'         => $PNP_PASSWORD_MANAGEMENT_LAMBDA,
    'invocationType' => 'Event',
    'data' => {
      'requestData' => {
        'action' => 'DELETE',
        'data'   => $requestData
      }
    }
  });

  my $lambdaStatus   = $response->{'status'};
  my $lambdaErrorMsg = $response->{'error'};
  if (!$lambdaStatus) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'customer_remote_password'});
    $logger->log({
      'mode'     => 'DELETE',
      'error'    => $lambdaErrorMsg
    });

    $status->setError($lambdaErrorMsg);
    $status->setFalse();
  }

  return $status;
}

##################################
# Subroutine: newCustomer
# --------------------------------
# Description:
#   Invokes an AWS lambda that 
#   does a GET request with mode
#   NEW to add/update a username 
#   on a remote server.
sub newCustomer {
  my $self = shift;
  my $requestData = shift;

  my $status = new PlugNPay::Util::Status(1);

  my $response = &PlugNPay::AWS::Lambda::invoke({
    'lambda'         => $PNP_PASSWORD_MANAGEMENT_LAMBDA,
    'invocationType' => 'Event',
    'data' => {
      'requestData' => {
        'action' => 'NEW',
        'data'   => $requestData
      }
    }
  });

  my $lambdaStatus   = $response->{'status'};
  my $lambdaErrorMsg = $response->{'error'};
  if (!$lambdaStatus) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'customer_remote_password'});
    $logger->log({
      'mode'     => 'NEW',
      'error'    => $lambdaErrorMsg
    });

    $status->setError($lambdaErrorMsg);
    $status->setFalse();
  }

  return $status;
}

1;
