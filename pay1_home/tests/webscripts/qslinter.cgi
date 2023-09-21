#!/usr/bin/perl

use strict;
use URI::Escape;
use CGI;

my $query = new CGI();
my @qs = $query->param;
print "content-type:text/plain\n\n";
foreach my $pair (@qs) {
   print $pair . ' - ' . $query->param($pair) . "\n";
}

exit;
