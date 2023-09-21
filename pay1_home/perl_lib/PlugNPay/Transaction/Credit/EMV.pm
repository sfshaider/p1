package PlugNPay::Transaction::Credit::EMV;

use strict;
use PlugNPay::Transaction::Credit;
use PlugNPay::GatewayAccount;

our @ISA = 'PlugNPay::Transaction::Credit';

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->setTransactionType('return');
  $self->setTransactionPaymentType('emv');

  return $self;
}

sub setProcessor {
  my $self = shift;
  my $processorCodeHandle = shift;

  $self->{'processor_code_handle'} = $processorCodeHandle;
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

sub validate {
  my $self = shift;

  return 1;
}