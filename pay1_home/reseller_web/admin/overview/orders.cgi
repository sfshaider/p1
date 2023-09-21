#!/bin/env perl

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};
use orders;
use strict;

#  my $message = "Due to maintenance this area is not currently available.  Access to this area will restored by 6PM EDT, May 30, 2016.";
#
#  print "Content-Type: text/html\n\n";
#  print "<html>\n";
#  print "<head>\n";
#  print "<title>Maintenance Notice</title>\n";
#  print "</head>\n";
#  print "<body bgcolor=\"#ffffff\">\n";
#  print "<div align=center>\n";
#  print "<p>\n";
#  print "<font size=+2>$message</font>\n";
#  print "</body>\n";
#  print "</html>\n";
#  exit;

my ($message);

if (-e "/home/p/pay1/outagefiles/highvolume.txt") {
  $message ="Sorry this program is not available right now due to unscheduled database maintenance.<p>\n";
  $message .= "Please try back in a little while.<p>\n";
}
#  $message ="Sorry this program is not available right now.<p>\n";

# my $message = "Sorry, but due to the problems we experienced last week, system activity is abnormally high. For this reason this report section is being turned off temporarily. We expect to have it back shortly.  We appreciate your patience.";

if ($ENV{'SEC_LEVEL'} > 9) {
  $message = "<span style=\"font-size:10px\">Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error.</span>";
}

if ($message ne "") {
  &orders::response_page("$message");
}

my $orders = new orders;

if ($orders::query{'function'} eq "") {
  $orders->search_form();
}
elsif ($orders::query{'function'} eq "receipt") {
  my %receipt_data1 = $orders->receipt_info();
  $orders->generate_receipt(%receipt_data1);
}
else {
  $orders->main();
}

exit;

