package PlugNPay::Die;

use strict;

our $stopLoop = 0;

BEGIN {
  require Exporter;

  our @ISA = qw(Exporter);
  our @EXPORT = qw(die die_metadata fail);
}

sub die_metadata {
  require PlugNPay::Logging::DataLog;
  my $dieArgs = shift || [];
  my $metadata = shift || {};

  if ($stopLoop) {
    my $dataLog = new PlugNPay::Logging::DataLog({ collection => 'die' });
    $dataLog->log({ message => $dieArgs, metadata => $metadata }, { depth => 1, stackTraceEnabled => 1 });
    $stopLoop = 0;
  }

  die(@{$dieArgs}); # no, this is not recursive.  this is the normal die being called.
}

sub die {
  my $mainMessage = shift;
  my (undef,$file,$lineNumber) = caller();
  $mainMessage .= " at $file line $lineNumber, PlugNPay::Die";
  unshift @_, $mainMessage;

  $stopLoop = 1;

  die_metadata(\@_);
}

sub fail { # just calls normal die, does not call datalog
  my $message = shift;
  die($message);
}

1;
