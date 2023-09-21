package PlugNPay::Transaction::Adjustment::COARemote::Account;

use strict;
use PlugNPay::ResponseLink;
use JSON::XS;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
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

sub setExists {
  my $self = shift;
  my $exists = shift;
  $self->{'exists'} = ($exists ? 1 : 0);
}

sub getExists {
  my $self = shift;
  if (!defined $self->{'exists'}) {
    $self->load();
  }
  return $self->{'exists'};
}

sub load {
  my $self = shift;
  my $requestData = {
    accountNumber => $self->getAccountNumber()
  };

  $self->callAPI($requestData);
}

sub create {
  my $self = shift;
  if (!$self->{'exists'}) {
    $self->save();
  } else {
    die('COA Account already exists.');
  }
}

sub update {
  my $self = shift;
  if ($self->{'exists'}) {
    $self->save();
  } else {
    die('COA Account does not exist.');
  }
}

sub save {
  my $self = shift;
  my $requestData = {
    accountNumber => $self->getAccountNumber(),
    name => $self->getName(),
    achFee => $self->getACHFee(),
    notes => $self->getNotes()
  };

  $self->callAPI($requestData);
}  
  

sub callAPI {
  my $self = shift;
  my $requestData = shift;

  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL('http://coa-api/private/customer.cgi');
  $rl->setRequestMethod('post');
  $rl->setRequestData($requestData);
  $rl->setRequestMode('DIRECT');

  $rl->doRequest();

  if (!$rl->requestFailed) {
    my $data = decode_json($rl->getResponseContent());
    if (ref $data eq 'HASH') {
      $self->setAccountNumber($data->{'accountNumber'});
      $self->setName($data->{'name'});
      $self->setACHFee($data->{'achFee'});
      $self->setNotes($data->{'notes'});
      $self->setExists(1);
    } else {
      $self->setExists(0);
    }
  }
}



1;
