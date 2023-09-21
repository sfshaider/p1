package PlugNPay::Legacy::SendMServerRequest;

use strict;
use PlugNPay::Die;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub setProcessor {
  my $self = shift;
  my $processor = shift;
  $processor =~ s/[^a-z0-9]//;
  $self->{'processor'} = $processor;
}

sub getProcessor {
  my $self = shift;
  return $self->{'processor'} || '';
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  if (!defined $self->{'gatewayAccount'} || $self->{'gatewayAccount'} eq '') {
    fail('gatewayAccount not defined');
  }
  return $self->{'gatewayAccount'};
}

sub setOperation {
  my $self = shift;
  my $operation = shift;
  $self->{'operation'} = $operation;
}

sub getOperation {
  my $self = shift;
  if (!defined $self->{'operation'} || $self->{'operation'} eq '') {
    fail('operation not defined');
  }
  return $self->{'operation'};
}

sub setPairs {
  my $self = shift;
  my $pairs = shift;
  $self->{'pairs'} = $pairs;
}

sub getPairs {
  my $self = shift;
  if (!defined $self->{'pairs'} || ref($self->{'pairs'}) ne 'HASH') {
    fail('pairs is not a hashref');
  }
  return $self->{'pairs'};
}

sub setExistingTransactionData {
  my $self = shift;
  my $data = shift;
  $self->{'existingTransactionData'} = $data;
}

sub getExistingTransactionData {
  my $self = shift;
  return $self->{'existingTransactionData'};
}

sub setTestRequest {
  my $self = shift;
  $self->{'testRequest'} = 1;
}

sub unsetTestRequest {
  my $self = shift;
  $self->{'testRequest'} = 0;
}

sub isTestRequest {
  my $self = shift;
  return $self->{'testRequest'} ? 1 : 0; # normalize to 0 or 1
}

sub setCertificationRequest {
  my $self = shift;
  $self->{'certificationRequest'} = 1;
}

sub unsetCertificationRequest {
  my $self = shift;
  $self->{'certificationRequest'} = 0;
}

sub isCertificationRequest {
  my $self = shift;
  return $self->{'certificationRequest'} ? 1 : 0; # normalize to 0 or 1
}

sub setTrace {
  my $self = shift;
  my $trace = shift;
  $self->{'trace'} = $trace;
}

sub getTrace {
  my $self = shift;
  return $self->{'trace'};
}

1;
