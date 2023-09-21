package PlugNPay::Fraud::Exempt;

use strict;
use PlugNPay::DBConnection;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $options = shift;

  if ($options->{'gatewayAccount'}) {
    $self->setGatewayAccount($options->{'gatewayAccount'});
    $self->load(); 
  }

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

sub setHashedCardNumbers {
  my $self = shift;
  my $hashedCardNumbers = shift;
  $self->{'hashedCardNumbers'} = $hashedCardNumbers;
}

sub getHashedCardNumbers {
  my $self = shift;
  return $self->{'hashedCardNumbers'};
}

sub load {
  my $self = shift;
  my $username = shift || $self->getGatewayAccount();
  my $dbs = new PlugNPay::DBConnection();
  my $rows = [];
  my $select = q/
    SELECT username, shacardnumber, ipaddress, trans_date
      FROM fraud_exempt
     WHERE username = ?
  /;
  eval {
    $rows = $dbs->fetchallOrDie('fraudtrack', $select, [$username], {})->{'result'};
  };

  my $results = {};
  foreach my $row (@{$rows}) {
    $results->{$row->{'username'}}{$row->{'shacardnumber'}} = {
      'isExempt'  => 1,
      'ipAddress' => $row->{'ipaddress'},
      'transDate' => $row->{'transDate'}
    };
  }

  $self->{'exemptCards'} = $results;
}

sub addExemption {
  my $self = shift;
  my $data = shift;
}

sub isExempt {
  my $self = shift;
  my $hashedCard = shift;
  my $username = shift || $self->getGatewayAccount();

  return $self->{'exemptCards'}{$username}{$hashedCard}{'isExempt'};
}

1;
