#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );
use Data::Dumper;

use lib $ENV{'PNP_PERL_LIB'};


require_ok('PlugNPay::OnlineCheck'); # test that we can load the module!

TestSetEncryptedAccount();
TestSetEncryptedNumber();

sub TestSetEncryptedAccount {
  my $encrypted = '202003 aes256 b93c8c35f7fa2410fbb9f9b5d7eceab504f67857739699cec0a1bed227551cc6';
  my $expected = '999999992 1234567890';
  my $oc = new PlugNPay::OnlineCheck();
  $oc->setAccountFromEncryptedNumber($encrypted);
  is(sprintf('%s %s', $oc->getRoutingNumber(), $oc->getAccountNumber()),$expected);
}

sub TestSetEncryptedNumber {
  my $encrypted = '202003 aes256 b93c8c35f7fa2410fbb9f9b5d7eceab504f67857739699cec0a1bed227551cc6';
  my $expected = '999999992 1234567890';
  my $oc = new PlugNPay::OnlineCheck();
  $oc->setNumberFromEncryptedNumber($encrypted);
  is(sprintf('%s %s', $oc->getRoutingNumber(), $oc->getAccountNumber()),$expected);
}
