package PlugNPay::Debug;

use strict;

BEGIN {
  require Exporter;
  require PlugNPay::Logging::DataLog;

  our @ISA = qw(Exporter);
  our @EXPORT = qw(debug);
}

sub debug {
  if ($ENV{'DEBUG'} != 1) {
    return;
  }
  my $metadata = shift || {};
  my $options = shift || {};
  my $dataLog = new PlugNPay::Logging::DataLog({ collection => 'debug' });
  my ($logData) = $dataLog->log({ metadata => $metadata }, { depth => 1, stackTraceEnabled => $options->{'stackTrace'} });
}

1;
