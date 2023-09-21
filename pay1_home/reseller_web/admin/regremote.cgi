#!/bin/env perl

require 5.001;
$|=1;

use lib '/home/p/pay1/perl_lib';
use resellerdave;

print "Content-Type: text/html\n\n";

$reseller = new reseller;

my(%security);
#my %security = &reseller::security_check($reseller::query{'publisher-name'},$reesller::query{'publisher-password'},$reseller::function'});
$security{'flag'} = 1;
if ($security{'flag'} == 1) {
  if ($reseller::function eq "updateapp") {
    $reseller::query{'client'} = "remote";
    $reseller->updateapp();
  }
  elsif ($reseller::function eq "updatefee") {
    require billing;
    $billing = new billing();
    $billing::data{'client'} = "remote";
    $billing->updatefee()
  }
  elsif ($reseller::function eq "updatefraud") {
    $reseller::query{'client'} = "remote";
    $reseller->update_fraud();
  }
  elsif ($reseller::function eq "cancel") { 
    $reseller::query{'client'} = "remote";
    $reseller->updatefraud(); 
  }
  elsif ($reseller::function eq "viewfraudtrack") {
    print "AAAAA\n";
    $reseller::query{'client'} = "remote";
    $reseller->viewfraudtrack();
  }
  else {
    print "InvalidFunction";
  }

}
else {
  print "$security{'MErrMsg'}\n";
}
exit;

