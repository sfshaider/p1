package PlugNPay::Processor::ProcessorMessageServiceClient::PostTransactionResultRequest;

# pragprog: "Not All Code Duplication Is Knowledge Duplication"

use strict;

use JSON::XS;

use PlugNPay::Util::Status;
use PlugNPay::Processor::ProcessorMessageServiceClient::PostTransactionResultResponse;

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

sub setTransactionRequestId {
  my $self = shift;
  my $transactionRequestId = shift;
  $self->{'transactionRequestId'} = $transactionRequestId;
}

sub setData {
  my $self = shift;
  my $data = shift;
  $self->{'data'} = $data;
}

sub getMethod {
  return 'POST';
}

sub getURL {
  my $self = shift;

  my $url = "v1/transaction/result";

  return $url;
}

sub toJSON {
  my $self = shift;

  my $jsonData = {
    transactionRequestId => "" . $self->{'transactionRequestId'},
    data                 => $self->{'data'}
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
  return new PlugNPay::Processor::ProcessorMessageServiceClient::PostTransactionResultResponse();
}

1;