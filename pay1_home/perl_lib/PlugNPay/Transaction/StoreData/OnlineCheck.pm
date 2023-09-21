package PlugNPay::Transaction::StoreData::OnlineCheck;
use strict;

use PlugNPay::Transaction::StoreData;
use PlugNPay::GatewayAccount;
use PlugNPay::OnlineCheck;

our @ISA = 'PlugNPay::Transaction::StoreData';

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->setTransactionType('storedata');
  $self->setTransactionPaymentType('ach');

  return $self;
}

sub init {
  return 1;
}

sub setProcessor {
  my $self = shift;
  my $processor = shift;
  
  $self->{'processor_code_handle'} = $processor;
}

sub getProcessor {
  my $self = shift;

  return $self->{'processor_code_handle'} if defined $self->{'processor_code_handle'};

  my $ga = $self->getGatewayAccount();
  if (ref($ga) =~ /^PlugNPay::GatewayAccount/) {
     return $ga->getACHProcessor();
  } else {
    return new PlugNPay::GatewayAccount($ga)->getACHProcessor();
  }
}

sub validate {
  my $self = shift;

  my $problem = 0;

  #################################
  # Check Check Data for problems #
  #################################

  if (!defined $self->getOnlineCheck()) {
    $self->setValidationError('Account information missing.');
    $problem++;
  } else {
    if (defined $self->getOnlineCheck()->getABARoutingNumber() && !$self->getOnlineCheck()->verifyABARoutingNumber()) {
      $self->setValidationError('Invalid ABA routing number.');
      $problem++;
    }
  }

  return ($problem ? 0 : 1);
}

1;
