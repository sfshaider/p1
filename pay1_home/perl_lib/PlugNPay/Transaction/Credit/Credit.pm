package PlugNPay::Transaction::Credit::Credit;
use strict;

use PlugNPay::Transaction::Credit;
use PlugNPay::CreditCard;
use PlugNPay::GatewayAccount;

our @ISA = 'PlugNPay::Transaction::Credit';

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->setTransactionType('return');
  $self->setTransactionPaymentType('credit');
  return $self;
}

sub init {
  return;
}

sub setProcessor {
  my $self = shift;
  my $processorCodeHandle = shift;

  $self->{'processor_code_handle'} = $processorCodeHandle;
}

sub getProcessor {
  my $self = shift;

  return $self->{'processor_code_handle'} if defined $self->{'processor_code_handle'};

  my $account =  $self->getGatewayAccount();
  if (ref($account) =~ /^PlugNPay::GatewayAccount/) {
    return $account->getCardProcessor();
  } else {
    my $gatewayObj = new PlugNPay::GatewayAccount($account);
    return $gatewayObj->getCardProcessor();
  }
}

sub validate {
  my $self = shift;

  my $problem = 0;

  ################################
  # Check Card Data for problems #
  ################################

  if (!defined $self->getCreditCard() && $self->getPNPToken() == "" && !defined $self->getPNPTransactionReferenceID()) {
    $self->setValidationError('Card information missing.');
    $problem++;
  } elsif ($self->getTransactionMode() != 'void' && defined $self->getCreditCard() && !$self->getPNPTransactionReferenceID()) {
    if (!$self->getCreditCard()->verifyLength()) {
      $self->setValidationError('Invalid card length.');
      $problem++;
    }
  
    if (!$self->getCreditCard()->verifyLuhn10()) {
      $self->setValidationError('Card number did not pass luhn10 check.');
      $problem++;
    } 
  
    if ($self->getCreditCard()->isExpired()) {
      $self->setValidationError('Card is expired.');
      $problem++;
    }
  }

  return ($problem ? 0 : 1);
}
    

1;
