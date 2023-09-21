package PlugNPay::Util::Status;

use strict;
use Types::Serialiser;
use PlugNPay::Util::StackTrace;
use PlugNPay::Die;

use overload 'bool' => \&getStatus;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $status = shift;
  if ($status) {
    $self->setTrue();
  }

  return $self;
}

sub setTrue {
  my $self = shift;
  $self->{'_status_'} = 1;
}

sub setFalse {
  my $self = shift;
  $self->{'_status_'} = 0;
}

sub getStatus {
  my $self = shift;
  return $self->{'_status_'};
}

sub setError {
  my $self = shift;
  my $error = shift;
  $self->{'_error_'} = $error;
  $self->{'_stackTrace_'} = new PlugNPay::Util::StackTrace()->string();
}

sub getStackTrace {
  my $self = shift;
  return $self->{'_stackTrace_'};
}

sub getError {
  my $self = shift;
  if (!defined $self->{'_error_'}) {
    return 'No error.';
  } else {
    return $self->{'_error_'};
  }
}

sub setErrorDetails {
  my $self = shift;
  my $detail = shift;
  $self->{'_errorDetails_'} = $detail;
}

sub getErrorDetails {
  my $self = shift;
  if (!defined $self->{'_errorDetails_'}) {
    return 'No error details';
  } else {
    return $self->{'_errorDetails_'};
  }
}

sub set {
  my $self = shift;
  my $key = shift;
  my $value = shift;
  if ($key =~ /^_.*_$/) {
    die('Keys starting and ending with underscore are reserved.');
  }
  $self->{$key} = $value;
}

sub get {
  my $self = shift;
  my $key = shift;
  if ($key =~ /^_.*_$/) {
    die('Keys starting and ending with underscore are reserved.');
  }
  return $self->{$key};
}

1;
