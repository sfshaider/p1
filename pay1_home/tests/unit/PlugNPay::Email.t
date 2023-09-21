#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );
use Data::Dumper;

require_ok('PlugNPay::Email');

test_insertLegacyMissingTo();
test_insertLegacyMissingFrom();
test_insertLegacyMissingSubject();
test_insertLegacyMissingContent();

sub test_insertLegacyMissingTo {
  my $e = setupEmail();
  # unset to
  $e->setTo(undef);
  my$ref = $e->_insertLegacy();
  my $error = 'Missing data: To';
  is($ref->{'error'},$error, 'Expected: ' . $error);
}

sub test_insertLegacyMissingFrom {
  my $e = setupEmail();
  # unset from
  $e->setFrom(undef);
  my $ref = $e->_insertLegacy();
  my $error = 'Missing data: From';
  is($ref->{'error'},$error, 'Expected: ' . $error);
}

sub test_insertLegacyMissingSubject {
  my $e = setupEmail();
  # unset subject 
  $e->setSubject(undef);
  my $ref = $e->_insertLegacy();
  my $error = 'Missing data: Subject';
  is($ref->{'error'},$error, 'Expected: ' . $error);
}

sub test_insertLegacyMissingContent {
  my $e = setupEmail();
  # unset Content 
  $e->setContent(undef);
  my $ref = $e->_insertLegacy();
  my $error = 'Missing data: Content'; 
  is($ref->{'error'},$error, 'Expected: ' . $error);
}

sub setupEmail {
  my $e = new PlugNPay::Email();
  $e->setTo('to+trash@plugnpay.com');
  $e->setFrom('from+trash@plugnpay.com');
  $e->setSubject('test subject');
  $e->setContent('test content');
  return $e;
}
