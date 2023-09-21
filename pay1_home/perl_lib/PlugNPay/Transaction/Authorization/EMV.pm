package PlugNPay::Transaction::Authorization::EMV;

use strict;
use PlugNPay::GatewayAccount;
use PlugNPay::Transaction::Authorization;

our @ISA = 'PlugNPay::Transaction::Authorization';

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->setTransactionType('auth');
  $self->setTransactionPaymentType('emv');

  return $self;
}

sub setProcessor {
  my $self = shift;
  my $processor = shift;

  $self->{'processor_code_handle'} = $processor;
}

sub getProcessor {
  my $self = shift;

  return $self->{'processor_code_handle'} if defined $self->{'processor_code_handle'};

  my $account = $self->getGatewayAccount();

  if(ref($account) =~ /^PlugNPay::GatewayAccount/) {
    return $account->getEmvProcessor();
  } else {
    my $gatewayObj = new PlugNPay::GatewayAccount($account);
    return $gatewayObj->getEmvProcessor();
  }
}

1;