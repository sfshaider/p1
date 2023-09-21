# Abstract class for authorizations.
package PlugNPay::Transaction::StoreData;

use strict;
use PlugNPay::Transaction;

our @ISA = 'PlugNPay::Transaction';

sub init {
  die "Direct initialization of PlugNPay::StoreData failed, it is an abstract class.  Caller: " . join(':',caller());
}

sub processTransaction {
  my $self = shift;
  $self->processStoreData(); # To be implemented by subclasses.
}

1;
