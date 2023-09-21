#!/bin/env perl

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Util::Status;

my $s = new PlugNPay::Util::Status;

$s->setFalse();
$s->setError("Intentional failure.");
$s->setErrorDetails("For testing purposes, of course.");

if ($s) {
  print "it was true!\n";
} else {
  print "it was false!\n";
}
