package PlugNPay::Processor::Query;

use strict;

use PlugNPay::Processor::Query::Response;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub do {
  my $query = shift;

  # call nexus to run queries.

  # return empty response for now.  to be completed later.
  my $response = new PlugNPay::Processor::Query::Response();

  return $response;
}

1;
