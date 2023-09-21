package PlugNPay::Testing;

use strict;
use Exporter;
use Test::More;

our @ISA = qw(Exporter);
our @EXPORT = qw(INTEGRATION skipIntegration);

=pod

integration()

returns truthy or falsy depending on wether integration testing is enabled.

=cut
sub INTEGRATION {
  return $ENV{'TEST_INTEGRATION'} eq '1';
}

sub skipIntegration {
  my $skipMessage = shift;
  my $skipAmount = shift;

  skip($skipMessage,$skipAmount) if !INTEGRATION;
  return !INTEGRATION;  # reads better this way for use in if (i.e. if (!skipIntegaration))
}
