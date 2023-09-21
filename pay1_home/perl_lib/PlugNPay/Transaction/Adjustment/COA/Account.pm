package PlugNPay::Transaction::Adjustment::COA::Account;

use strict;
use JSON::XS;

use PlugNPay::ResponseLink;
use PlugNPay::Transaction::Adjustment::GlobalSettings;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setAccountNumber {
  my $self = shift;
  my $accountNumber = shift;
  $self->{'accountNumber'} = $accountNumber;
}

sub getAccountNumber {
  my $self = shift;
  return $self->{'accountNumber'};
}

sub setName {
  my $self = shift;
  my $name = shift;
  $self->{'name'} = $name;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub setNotes {
  my $self = shift;
  my $notes = shift;
  $self->{'notes'} = $notes;
}

sub getNotes {
  my $self = shift;
  return $self->{'notes'};
}

sub setACHFee {
  my $self = shift;
  my $fee = shift;
  $fee =~ s/[^\d\.]//g;
  $self->{'fee'} = $fee;
}

sub getACHFee {
  my $self = shift;
  return $self->{'fee'};
}

sub exists {
  my $self = shift;
  my $requestData = {
    accountNumber => $self->getAccountNumber(),
    gateway => 'plugnpay',
    gatewayAccountIdentifier => $self->getGatewayAccount(),
    mode => 'read'
  };

  return ($self->callAPI($requestData)->{'exists'});
}

sub load {
  my $self = shift;
  my $requestData = {
    accountNumber => $self->getAccountNumber(),
    gateway => 'plugnpay',
    gatewayAccountIdentifier => $self->getGatewayAccount(),
    mode => 'read'
  };

  my $apiData = $self->callAPI($requestData);
  if (ref $apiData eq 'HASH') {
    $self->setAccountNumber($apiData->{'accountNumber'});
    $self->setName($apiData->{'name'});
    $self->setACHFee($apiData->{'achFee'});
    $self->setNotes($apiData->{'notes'});
    $self->setGatewayAccount($apiData->{'gatewayAccountIdentifier'});
  }

  return $self->callAPI($requestData);
}

sub create {
  my $self = shift;
  if (!$self->exists()) {
    return $self->_save('create');
  }
  return 0;
}

sub update {
  my $self = shift;

  if ($self->exists()) {
    return $self->_save('update');
  }
}

sub _save {
  my $self = shift;
  my $mode = shift;
  my $requestData = {
    name => $self->getName(),
    achFee => $self->getACHFee(),
    notes => $self->getNotes(),
    gateway => 'plugnpay',
    gatewayAccountIdentifier => $self->getGatewayAccount(),
    mode => $mode
  };

  return $self->callAPI($requestData);
}  
  

sub callAPI {
  my $self = shift;
  my $requestData = shift;

  my $gs = new PlugNPay::Transaction::Adjustment::GlobalSettings();
  my $host = $gs->getHost();

  my $url = sprintf('http://%s/private/customer.cgi',$host);

  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL($url);
  $rl->setRequestMethod('post');
  $rl->setRequestData($requestData);
  $rl->setRequestMode('DIRECT');

  $rl->doRequest();
  if (!$rl->requestFailed) {
    my $data = decode_json($rl->getResponseContent());
    return $data;
  }
  return 0;
}



1;
