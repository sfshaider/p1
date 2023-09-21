package PlugNPay::Transaction::Query;

# Note:  this module does *not* validate query syntax
 
use strict;
use JSON::XS;

use PlugNPay::Util::Status;
use PlugNPay::Transaction::Query::Request;

sub new {
  my $class = shift;
  my $self = shift;
  bless $self, $class;
  return $self;
}

sub getHost {
  my $self = shift;
  return 'https://microservice-nexus.local';
}

sub newRequest {
  return new PlugNPay::Transaction::Query::Request();
}

sub send {
  my $self = shift;
  my $request = shift;

  my $ms = new PlugNPay::ResponseLink::Microservice();


}


1;
