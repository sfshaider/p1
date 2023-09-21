package PlugNPay::API::REST::Responder::Username::Password;

use strict;
use PlugNPay::Username;
use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  my $response = {};

  if ($action eq 'update') {
    $response = $self->_update();
  } else {
    $self->setResponseCode(501);
    $response = {};
  }

  return $response;
}

sub _update {
  my $self = shift;
  my $loginDetails = $self->getInputData();
  my $username = new PlugNPay::Username($self->getGatewayAccount()); 
  my $response;

  my $password = $loginDetails->{'password'};
  $password =~ s/[^a-zA-Z0-9\+\-\.\*\@\$]//g;
  
  if ($password ne '') {
    $username->setTemporaryPasswordFlag(1) if $loginDetails->{'isTemporary'} eq 'true';
    my $ignoreHistoryCheck = 0;
    if ($loginDetails->{'ignoreHistoryCheck'} eq 'true' && $username->getSecurityLevel() eq '0') {
      $ignoreHistoryCheck = 1;
    }

    my $saved = 0;
    eval {
      $saved = $username->setPassword($password, {overrideHistoryCheck => $ignoreHistoryCheck});
    };   

    my $code    = 200;
    my $status  = 'success';
    my $message = 'Successfully changed password';

    if ($@) {
       $code    = 520;
       $status  = 'error';
       $message = 'Failed to change password';
       $self->log($@);
    } else {
      if (!$saved) {
        $code    = 422;
        $status  = 'failure';
        $message = 'Failed to change password';
        $self->log('Failed password change constraints');
      } else {
        $self->log('User ' . $self->getGatewayAccount() . ' changed their password');
      }
    }

    $self->setResponseCode($code);
    $response = {
      'message' => $message,
      'status'  => $status,
      'login'   => $self->getGatewayAccount()
    };

  } else {
    $self->setResponseCode(422);
    $response = { 
      'status'  => 'error',
      'message' => 'Bad password',
      'login'   => $self->getGatewayAccount()
    };
    $self->log('Invalid password sent');
  }

  return $response;
}

sub log {
  my $self = shift;
  my $message = shift;
  new PlugNPay::Logging::DataLog({ 'collection' => 'username' })->log({
    'username'  => $self->getGatewayAccount(),
    'message'   => $message,
    'responder' => 'PlugNPay::Username::Password'
  });
}

1;
