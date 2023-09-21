#!/bin/env perl

require 5.001;

use lib '/home/p/pay1/perl_lib';
use billing;

#print "Content-Type: text/html\n\n";

$billing = new billing();

%query = %billing::data;
$mode = $query{'mode'};


#print "AAAAA<br>\n";
#foreach $key (sort keys %query) {
#  print "$key=$query{$key}<br>\n";
#}
#print "USER:$upsell::data{'username'}\n";
#exit;

if ($mode eq "addfee") {
  $billing->addfee();
}
elsif ($mode eq "updatefee") {
  $billing->updatefee();
  $billing->addfee();
}
else {
  my $message = "Invalid Operation";
  $billing->response_page($message);
}
exit;
