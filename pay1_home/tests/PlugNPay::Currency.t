#!/bin/env perl
use strict;
use warnings;
use diagnostics;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Currency;
use Test::More qw( no_plan );


sub checkData {
  my $curr = shift;
  my $numericData = $curr->{'data'}{'numeric'}{'840'};
  my $threeLetterData = $curr->{'data'}{'threeLetter'}{'USD'};
  my $status = 0;
  my $numericStatus = 0;

  if ($numericData->{'code'} eq 'USD' && $numericData->{'number'} eq '840' && $numericData->{'name'} eq 'Dollar' && $numericData->{'description'} eq 'US Dollar') {
    $numericStatus = 1;
  }

  if ($numericStatus && $threeLetterData->{'code'} eq 'USD' && $threeLetterData->{'number'} eq '840' && $threeLetterData->{'name'} eq 'Dollar' && $threeLetterData->{'description'} eq 'US Dollar') {
    $status = 1;
  }
  return $status;
}

sub testNumeric {
  my $curr = new PlugNPay::Currency(840);
  return &checkData($curr);
}

sub testThreeLetter {
  my $curr = new PlugNPay::Currency('usd');
  return &checkData($curr);
}

sub testGetField {
  my $curr = new PlugNPay::Currency('usd');
  return ($curr->getField($curr->getThreeLetter(), 'number') eq '840');
}

sub testSetGetNumeric{
  my $curr = new PlugNPay::Currency();
  $curr->setCurrencyNumber(840);
  return ($curr->getCurrencyNumber() eq '840');
}

sub testSetGetThreeLetter {
  my $curr = new PlugNPay::Currency();
  $curr->setThreeLetter('usd');
  return ($curr->getThreeLetter() eq 'USD');
}


is(&testNumeric(), 1, "test numeric constructor");
is(&testThreeLetter(), 1, "test threeLetter constructor");
is(&testGetField(), 1, "test getField function");
is(&testSetGetThreeLetter(), 1, "test set and get for threeLetter");
is(&testSetGetNumeric(), 1, "test set and get for currency number");

1;
