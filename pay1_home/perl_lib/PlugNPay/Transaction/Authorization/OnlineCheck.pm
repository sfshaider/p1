package PlugNPay::Transaction::Authorization::OnlineCheck;

use strict;
use PlugNPay::Transaction::Authorization;
use PlugNPay::GatewayAccount;
use PlugNPay::OnlineCheck;

our @ISA = 'PlugNPay::Transaction::Authorization';

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->setTransactionType('auth');
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
  
  my $account =  $self->getGatewayAccount();
  if (ref($account) =~ /^PlugNPay::GatewayAccount/) {
    return $account->getACHProcessor();
  } else {
    my $gatewayObj = new PlugNPay::GatewayAccount($account);
    return $gatewayObj->getACHProcessor();
  }
}

sub validate {
  my $self = shift;

  my $problem = 0;

  #################################
  # Check Check Data for problems #
  #################################

 
  if (!defined $self->getOnlineCheck() && $self->getPNPToken() == "" && !defined $self->getPNPTransactionReferenceID()) {
    $self->setValidationError('Account information missing.');
    $problem++;
  } elsif (defined $self->getOnlineCheck() && (!$self->getPNPToken() && lc($self->getTransactionMode()) eq 'postauth')) {
    if (defined $self->getOnlineCheck()->getABARoutingNumber() && !$self->getOnlineCheck()->verifyABARoutingNumber()) {
      $self->setValidationError('Invalid ABA routing number.');
      $problem++;
    }
  }

  return ($problem ? 0 : 1);
}

1;
