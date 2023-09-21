package PlugNPay::Transaction::StoreData::Credit;
use strict;

use PlugNPay::Transaction::StoreData;
use PlugNPay::GatewayAccount;
use PlugNPay::CreditCard;
use PlugNPay::GatewayAccount;

our @ISA = 'PlugNPay::Transaction::StoreData';

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->setTransactionType('storedata');
  $self->setTransactionState('STOREDATA');
  $self->setTransactionPaymentType('credit');

  return $self;
}

sub init {
  return;
}

sub setProcessor {
  my $self = shift;
  my $processor = shift;
  
  $self->{'processor_code_handle'} = $processor;
}

sub getProcessor {
  my $self = shift;
  return $self->{'processor_code_handle'} if defined $self->{'processor_code_handle'};

  my $gatewayAccount = $self->getGatewayAccount();
  if (defined $gatewayAccount) {

    if (ref $gatewayAccount ne 'PlugNPay::Transaction::GatewayAccount') {
      $gatewayAccount = new PlugNPay::GatewayAccount($gatewayAccount)
    }

    return $gatewayAccount->getCardProcessor();
  }
}

sub validate {
  my $self = shift;

  my $problem = 0;

  ################################
  # Check Card Data for problems #
  ################################

  if (!defined $self->getCreditCard()) {
    $self->setValidationError('Card information missing.');
    $problem++;
  } else {
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
