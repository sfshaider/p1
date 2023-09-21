#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );
use Data::Dumper;

require_ok('PlugNPay::Contact');

testGetName();

sub testGetName {
  my $c = new PlugNPay::Contact();
  $c->setFirstName('fname');
  $c->setLastName('lname');
  is($c->getName(),'fname lname', 'Verify getName returns fname lname');
  is($c->getFirstName(),'fname', 'Verify getFirstName returns fname');
  is($c->getLastName(),'lname', 'Verify getLastName returns lname');
  is($c->getFullName(),'fname lname', 'Verify getFullName returns fname lname');
}
