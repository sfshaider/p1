#!/bin/env perl

use dukpt;

print "bdk1: ";
$bdk1 = <stdin>;
chomp $bdk1;

my $ksn = readKsn();

while ($ksn ne "") {
  &dukpt::injectipek1("$ksn","$bdk1");
  $ksn = readKsn();
}

sub readKsn {
  print "ksn: ";
  my $ksn = <stdin>;
  chomp $ksn;
  return $ksn;
}