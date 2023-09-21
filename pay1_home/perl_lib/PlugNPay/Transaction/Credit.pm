# Abstract class for credits.

use strict;
use PlugNPay::Transaction;

package PlugNPay::Transaction::Credit;
our @ISA = 'PlugNPay::Transaction';

sub init {
  die "Direct initialization of PlugNPay::credit failed, it is an abstract class.  Caller: " . join(':',caller());
}

sub processTransaction {
  my $self = shift;

  my %results;

  if (!$self->getGatewayAccount()->canProcessCredits()) {
    $results{'error'} = 1;
    $results{'errorMessage'} = 'This account can not process credits.';
  } else {
    $self->processCredit(); # To be implemented by subclasses.
  }

  return %results;
}

1;
