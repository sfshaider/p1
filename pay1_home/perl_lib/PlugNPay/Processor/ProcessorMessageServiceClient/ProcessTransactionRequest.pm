package PlugNPay::Processor::ProcessorMessageServiceClient::ProcessTransactionRequest;

# pragprog: "Not All Code Duplication Is Knowledge Duplication"

use strict;

use JSON::XS;

use PlugNPay::Util::Status;
use PlugNPay::Processor::ProcessorMessageServiceClient::ProcessTransactionResponse;

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

sub setMerchant {
  my $self = shift;
  my $merchant = shift;
  $self->{'merchant'} = $merchant;
}

sub setOrderId {
  my $self = shift;
  my $orderId = shift;
  $self->{'orderId'} = $orderId;
}

sub setData {
  my $self = shift;
  my $data = shift;
  $self->{'data'} = $data;
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

  my $url = sprintf("v1/transaction/");

  return $url;
}

sub toJSON {
  my $self = shift;

  my $jsonData = {
    data => $self->{'data'},
    merchant => $self->{'merchant'},
    orderId => $self->{'orderId'},
    processor => $self->{'processor'},
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
  return new PlugNPay::Processor::ProcessorMessageServiceClient::ProcessTransactionResponse();
}

1;