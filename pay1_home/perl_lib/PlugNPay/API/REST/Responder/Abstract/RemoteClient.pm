package PlugNPay::API::REST::Responder::Abstract::RemoteClient;

use strict;
use PlugNPay::Util::RandomString;
use PlugNPay::RemoteClient;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  my $verifyResponse = $self->checkRCPermission();
  if ($verifyResponse->{'status'} ne 'error') {
    if ($action eq 'create') {
      return $self->_create();
    } elsif ($action eq 'update') {
      return $self->_update();
    } else {
      $self->setResponseCode(501);
      return {};
    }
  } else {
    return $verifyResponse;
  }
}

sub _create {
  my $self = shift;
  my $client = $self->getResourceData()->{'merchant'};
  my $inputData = $self->getInputData();

  my $password = $inputData->{'password'};
  if ($inputData->{'generate_random_password'} || !defined $password) {
    $password = new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);
  }

  my $success = 0;
  eval {
    my $remoteClient = new PlugNPay::RemoteClient();
    $success = $remoteClient->manageRemoteClientAccount($password, $client, $client);
  };

  if ($@) {
    $self->setResponseCode(520);
    return {};
  }
     
  if ($success) {
    $self->setResponseCode(201);
    return { 'status' => 'success', 'message' => 'Created remote client account', 'password' => $password };
  } else {
    $self->setResponseCode(422);
    return { 'status' => 'failure', 'message' => 'Failed to create remote client account. Password check fail' };
  }
}

sub _update {
  my $self = shift;
  my $inputData = $self->getInputData();
  my $client = $self->getResourceData()->{'merchant'};

  my $password = $inputData->{'password'};
  if ($inputData->{'generate_random_password'} || !defined $password) {
    $password = new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);
  }

  my $success = 0;
  eval {
    my $remoteClient = new PlugNPay::RemoteClient();
    $success = $remoteClient->manageRemoteClientAccount($password, $client, $client);
  };

  if ($@) {
    $self->setResponseCode(520);
    return {};
  }

  if ($success) {
    $self->setResponseCode(200);
    return {'status' => 'success', 'message' => 'Updated remote client account', 'password' => $password};
  } else {
    $self->setResponseCode(422);
    return { 'status' => 'failure', 'message' => 'Failed to create remote client account. Password check fail' };
  }
}

# Make sure the reseller can reset RCPassword AND is the actual reseller for this login (Or the accounts reseller is a sub-reseller)
# This happens in sub modules
sub checkRCPermission {}

1;
