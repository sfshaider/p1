package PlugNPay::Legacy::SendMServerTrace;

use strict;

sub new {
  my $class = shift;

  my $self = {
    additionalTraceData => {}
  };

  bless $self,$class;
  return $self;
}

sub setTraceEnabled {
  my $self = shift;
  $self->{'enabled'} = 1;
}

sub setTraceDisabled {
  my $self = shift;
  $self->{'enabled'} = undef;
}

sub isEnabled {
  my $self = shift;
  return $self->{'enabled'};
}

sub setInputGatewayAccount {
  my $self = shift;
  return if !$self->isEnabled();

  my $operation = shift;
  $self->{'inputGatewayAccount'} = $operation;
}

sub getInputGatewayAccount {
  my $self = shift;
  return $self->{'inputGatewayAccount'};
}

sub setInputOperation {
  my $self = shift;
  return if !$self->isEnabled();

  my $operation = shift;
  $self->{'inputOperation'} = $operation;
}

sub getInputOperation {
  my $self = shift;
  return $self->{'inputOperation'};
}

sub setInputPairs {
  my $self = shift;
  return if !$self->isEnabled();

  my $pairs = shift;
  $self->{'inputPairs'} = $pairs;
}

sub getInputPairs {
  my $self = shift;
  return $self->{'inputPairs'};
}

sub setOutput {
  my $self = shift;
  return if !$self->isEnabled();

  my $output = shift;
  $self->{'output'} = $output;
}

sub getOutput {
  my $self = shift;
  return $self->{'output'};
}

sub addAdditionalTraceData {
  my $self = shift;
  return if !$self->isEnabled();

  my $key = shift;
  my $data = shift;
  $self->{'additionalTraceData'}{$key} = $data;
}

sub getAdditionalTraceData {
  my $self = shift;
  my $key = shift;
  return $self->{'additionalTraceData'}{$key};
}

sub setRawProcessorRequest {
  my $self = shift;
  return if !$self->isEnabled();

  my $raw = shift;
  $self->{'rawRequest'} = $raw;
}

sub getRawProcessorRequest {
  my $self = shift;
  return $self->{'rawRequest'};
}

sub setRawProcessorResponse {
  my $self = shift;
  return if !$self->isEnabled();
  my $raw = shift;
  $self->{'rawResponse'} = $raw;
}

sub getRawProcessorResponse {
  my $self = shift;
  return $self->{'rawResponse'};
}

sub setProcessorHost {
  my $self = shift;
  return if !$self->isEnabled();

  my $host = shift;
  $self->{'processorHost'} = $host;
}

sub getProcessorHost {
  my $self = shift;
  return $self->{'processorHost'};
}

1;
