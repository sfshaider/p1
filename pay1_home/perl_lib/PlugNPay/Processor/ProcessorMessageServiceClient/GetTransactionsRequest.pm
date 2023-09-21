package PlugNPay::Processor::ProcessorMessageServiceClient::GetTransactionsRequest;

# pragprog: "Not All Code Duplication Is Knowledge Duplication"

use strict;

use JSON::XS;

use PlugNPay::Processor::ProcessorMessageServiceClient::GetTransactionsResponse;

use PlugNPay::Util::Status;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub setProcessor {
  my $self = shift;
  my $processor = shift;
  $self->{'processor'} = $processor;
}

sub setCount {
  my $self = shift;
  my $count = shift;
  $self->{'count'} = $count;
}

sub setTimeout {
  my $self = shift;
  my $timeout = shift;
  $self->{'timeout'} = $timeout;
}

sub getTimeout {
  my $self = shift;
  return $self->{'timeout'} || 30;
}


sub getMethod {
  return 'POST';
}

sub getURL {
  my $self = shift;

  my $processor = $self->{'processor'};
  die('can not create url when processor is not defined') if !defined $processor || $processor eq '';

  my $url = 'v1/transaction/pending/';

  return $url;
}

sub toJSON {
  my $self = shift;

  my $jsonData = {
    processor => $self->{'processor'},
    count => $self->{'count'} || 1,
    timeout => $self->{'timeout'} || 30
  };

  my $status = new PlugNPay::Util::Status(1);

  my $json = '';
  eval {
    $json = encode_json($jsonData);
  };

  if ($@) {
    $status->setFalse();
    $status->setError($@);
  } else {
    $status->set('json',$json);
  }

  return $status;
}

sub getResponse {
  my $self = shift;
  return new PlugNPay::Processor::ProcessorMessageServiceClient::GetTransactionsResponse();
}

1;