package PlugNPay::API::REST::Responder::Token;

use PlugNPay::Token;

use strict;
use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  if ($action eq 'create') {
    return $self->_create();
  } elsif ($action eq 'read') {
    return $self->_read();
  } else {
    $self->getResponseCode(501);
    $self->setError('Bad request action');
    return {};
  }
}

sub _read {
  my $self = shift;
  my $token = $self->getResourceData()->{'token'};

  my $tokenObj = new PlugNPay::Token();
  my $paymentData = $tokenObj->fromToken($token);

  if (defined $paymentData && $paymentData ne '') {
    $self->setResponseCode(200);
    return {'paymentData' => $paymentData};
  } else {
    $self->setResponseCode(404);
    $self->setError('Token not found or no payment data found');
    return {};
  }
}

sub _create {
  my $self = shift;
  my $data = $self->getInputData();

  if (defined $data->{'paymentData'}) {
    my $tokenObj = new PlugNPay::Token();
    my $token = $tokenObj->getToken($data->{'paymentData'});

    if (defined $token && $token ne '') {
      $self->setResponseCode(201);
      return {'token' => $token};
    } else {
      $self->setResponseCode(520);
      $self->setError('No token data returned');
      return {};
    }
  } else {
    $self->setResponseCode('422');
    $self->setError('No data sent to be tokenized');
    return {};
  }
}

1;
