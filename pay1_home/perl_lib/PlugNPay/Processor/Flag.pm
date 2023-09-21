package PlugNPay::Processor::Flag;

use strict;
use PlugNPay::AWS::ParameterStore;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $processorCodeHandle = shift;
  if ($processorCodeHandle) {
    $self->{'processorCodeHandle'} = $processorCodeHandle;
  }

  return $self;
}

sub setFlag {
  my $self = shift;
  my $flag = shift;
  $self->{'flag'} = $flag;
}

sub setProcessorCodeHandle {
  my $self = shift;
  my $codeHandle = shift;
  $self->{'processorCodeHandle'} = $codeHandle;
}

sub get {
  my $self = shift;
  my $flag = shift || $self->{'flag'};
  my $codeHandle = shift || $self->{'processorCodeHandle'};

  my $parameter = '/PROCESSOR/' . uc($codeHandle) . '/' . uc($flag);

  my $flagValue = &PlugNPay::AWS::ParameterStore::getParameter($parameter);
  if (!$flagValue) {
    return undef;
  }

  return $flagValue;
}

1;
