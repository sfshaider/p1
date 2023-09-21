package PlugNPay::Processor::ProcessorMessageServiceClient::ProcessTransactionResponse;

use strict;

use JSON::XS;

use PlugNPay::Util::Status;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub getData {
  my $self = shift;
  my $data = $self->{'data'} || '';
  return $data;
}

sub getError {
  my $self = shift;
  my $errorValue = $self->{'error'} ? 1 : 0;
  return $errorValue;
}

sub getMessage {
  my $self = shift;
  my $message = $self->{'message'} || '';
  return $message;
}

sub getRequestId {
  my $self = shift;
  my $requestId = $self->{'requestId'} || '';
  return $requestId;
}

sub fromJSON {
  my $self = shift;
  my $json = shift;

  $self->{'raw'} = $json;
  
  my $status = new PlugNPay::Util::Status(1);

  eval {
    my $data = decode_json($json);
    $self->_setFromData($data);
  };

  if ($@) {
    $status->setFalse();
    $status->setError($@);
  }

  return $status;
}

sub _setFromData {
  my $self = shift;
  my $data = shift;

  $self->{'data'}      = $data->{'data'};
  $self->{'error'}     = $data->{'error'};
  $self->{'message'}   = $data->{'message'};
  $self->{'requestId'} = $data->{'requestId'};
}

1;