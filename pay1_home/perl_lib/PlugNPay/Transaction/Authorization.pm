# Abstract class for authorizations.

use strict;
use PlugNPay::Transaction;

package PlugNPay::Transaction::Authorization;
our @ISA = 'PlugNPay::Transaction';

sub init {
  die "Direct initialization of PlugNPay::Authorization failed, it is an abstract class.  Caller: " . join(':',caller());
}

sub processTransaction {
  my $self = shift;

  my %results;

  if (!$self->getGatewayAccount()->canProcessAuthorizations()) {
    $results{'error'} = 1;
    $results{'errorMessage'} = 'This account can not process authorizations.';
  } else {
    $self->processAuthorization(); # To be implemented by subclasses.
  }

  return %results;
}

1;
