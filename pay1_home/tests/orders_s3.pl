#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use Data::Dumper;
use PlugNPay::Order::Report;

my $r = new PlugNPay::Order::Report('brytest2');
my $s = $r->saveOrderRequest({
  'query' => {
    'start_date' => '20180620',
    'end_date'   => '20180912'
  }
});

&checkStatus($r);
$r->processBatches();
&checkStatus($r);
exit;

sub checkStatus {
  my $r = shift;

  if ($r->isPending()) {
    print "PENDING\n";
  } elsif ($r->isProcessing()) {
    print "PROCESSING\n";
  } elsif ($r->isComplete()) {
    print "COMPLETE\n";
  } elsif ($r->isProblem()) {
    print "PROBLEM\n";
  } else {
    print "ERR: NO STATUS\n";
  }
}
