#!/bin/env perl

require 5.001;
$|=1;

use lib '/home/p/pay1/perl_lib';
use reseller;

print "Content-Type: text/html\n\n";

$reseller = new reseller;

$reseller::source = "registrationserver";

my(%security);
my %security = &reseller::security_check($reseller::query{'reseller'},$reseller::query{'password'},$reseller::function'});
#$security{'flag'} = 1;
if ($security{'flag'} == 1) {
  $reseller::reseller = "$reseller::query{'reseller'}";

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
    $reseller->updatefraud();
  }
  elsif ($reseller::function eq "cancel") { 
    $reseller::query{'client'} = "remote";
    $reseller->updatefraud(); 
  }
  else {
    print "InvalidFunction";
  }

}
else {
  print "$security{'MErrMsg'}\n";
}
exit;

