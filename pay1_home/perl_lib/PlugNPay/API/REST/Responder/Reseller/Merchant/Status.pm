package PlugNPay::API::REST::Responder::Reseller::Merchant::Status;

use strict;
use PlugNPay::GatewayAccount::Status;
use PlugNPay::GatewayAccount;
use PlugNPay::Reseller;
use PlugNPay::Reseller::Chain;
use PlugNPay::Logging::DataLog;
use PlugNPay::Sys::Time;
use base 'PlugNPay::API::REST::Responder::Abstract::Reseller';

sub __getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  if ($action eq 'update') {
    return $self->_update();
  } elsif($action eq 'read') {
      return $self->_read();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

# if called from api set reason and date.
sub _update {
  my $self = shift;
  my $data = $self->getInputData();
  my $username = $data->{'gatewayAccount'};
  my $status = $data->{'status'}; 
  my $resellerName = $self->getReseller();
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'gatewayaccount'});
  my $timeSent = new PlugNPay::Sys::Time()->nowInFormat('db_gm');
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $reseller = new PlugNPay::Reseller($resellerName);

  #Check payall
  my $payall = ($reseller->getPayAllFlag() == 1 ? 1 : 0);
  $gatewayAccount->setForceStatusChange($payall);

  if ($gatewayAccount->isCancelled() && !$payall) {
    $self->setResponseCode(403);
    return {'message' => 'Insufficient privileges to alter account status', 'status' => 'failure'};
  }

  # Check privileges 
  if ($gatewayAccount->getReseller ne $self->getReseller()) {
    $self->setResponseCode(403);
    return {'message' => 'Insufficient privileges to access this account', 'status' => 'failure'};
  }

  my $reason = "Sent from API on $timeSent";

  if(!$status) {
    $self->setResponseCode(422);
    return {
      'status' => 'error',
      'message' => 'status is undefined'
    };
  }
  if(!($gatewayAccount->exists($username))) {
    $self->setResponseCode(404);
    return {
      'status' => 'error',
      'message' => 'unable to load gateway account'
    };
  }
  if($status eq 'debug') {
    $gatewayAccount->setDebug($reason);
  } elsif($status eq 'live') { 
    # Only allow live if reseller pays merchant fees
    if ($payall) {
      $gatewayAccount->setLive($reason);
    } else {
      $self->setResponseCode(403);
      return {'status' => 'failure', 'message' => 'Not allowed to set live'};
    }
  } elsif($status eq 'pending') {
    $gatewayAccount->setPending($reason);
  } elsif($status eq 'test') {
    $gatewayAccount->setTest($reason);
  } elsif($status eq 'cancelled') {
    $gatewayAccount->setCancelled($reason);
  } elsif($status eq 'hold') {
    $gatewayAccount->setOnHold($reason);
  } else {
    $self->setResponseCode(422);
    return {
      'status' => 'error',
      'message' => 'invalid status'
    };
  }
  # set default response code of 200, only changed if status is undefined,
  # or if gatewayaccount can't be loaded, or an invalid status is sent
  $gatewayAccount->save();
  $self->setResponseCode(200);
  $logger->log({
    'status' => $status,
    'sent' => $timeSent
  });
  return {
    'status' => 'success',
    'message' => 'updated status'
  };
}

sub _read {
  my $self = shift;
  my $data = $self->getResourceData();
  my $resellerName = $self->getReseller();
  my $username = $data->{'merchant'};
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'gatewayaccount'});
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);

  # Check privileges
  if ($resellerName ne $gatewayAccount->getReseller()) {
    $self->setResponseCode(403);
    return {'message' => 'Insufficient privileges to access this account', 'status' => 'failure'};
  }

  if(!($gatewayAccount->exists($username))) {
    $self->setResponseCode(404);
    return {
      'status' => 'error',
      'message' => 'unable to load gateway account'
    };
  } else {
    my $status = $gatewayAccount->getStatus();
    $self->setResponseCode(200);
    $logger->log({
      'accountStatus' => $status,
      'username' => $username
    });
    return {
      'status' => 'success',
      'message' => 'account was found',
      'accountStatus' => $status
    }
  }
}


1;
