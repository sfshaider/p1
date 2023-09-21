package PlugNPay::Logging::MessageLog;

use Sys::Syslog;
use Sys::Syslog qw(:extended :standard :macros);
use PlugNPay::Util::UniqueID;
use PlugNPay::Logging::DataLog;
use strict;


sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  # not sure if I'm going to use this
  my $sessionGenerator = new PlugNPay::Util::UniqueID();
  $sessionGenerator->generate();
  $self->{'session'} = $sessionGenerator->inHex();

  return $self;
}

sub logMessage { # message is redundant
  my $self = shift;
  $self->log(@_);
}

sub log {
  my ($self,$message,$additionalSettings) = @_;

  my $processName;

  if (ref($additionalSettings) eq 'HASH') {
    $processName = $additionalSettings->{'file'};
  }

  $processName |= ($ENV{'SCRIPT_NAME'} || $0);

  my $data = {};
  $data->{'SCRIPT'} = $processName;
  $data->{'message'} = $message;
  my $logger = new PlugNPay::Logging::DataLog({ collection => 'general_message_log' });
  $logger->log($message);
}

sub DESTROY
{
  my $self = shift;
}

1;
