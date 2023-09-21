#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );
use Data::Dumper;

use lib $ENV{'PNP_PERL_LIB'};

require_ok('PlugNPay::Recurring::PaymentSource');

my $merchant = $ARGV[0];
my $customer = $ARGV[1];

TestLoadPaymentSourceRecurringLoadWithoutError();

sub TestLoadPaymentSourceRecurringLoadWithoutError {
  my $ps = new PlugNPay::Recurring::PaymentSource();
  eval {
    $ps->loadPaymentSource($merchant,$customer);
  };
  is($@,'');
}
