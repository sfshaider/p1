package PlugNPay::Transaction::Logging::Format;

use strict;
use PlugNPay::Transaction::JSON;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub format {
  if (ref($_[0]) eq 'PlugNPay::Transaction::Logging::Format') {
    shift @_;
  }

  my $transactionObj = shift;
  my $transactionHash = {};

  if (ref($transactionObj) !~ /^PlugNPay::Transaction/) {
    return $transactionHash;    
  }

  my $formatter = new PlugNPay::Transaction::JSON();
  $transactionHash = $formatter->transactionToJSON($transactionObj);
   
  return $transactionHash;
}

1;
