#!/bin/env perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use CGI;
use DBI;
use Time::Local qw(timegm);
use miscutils;
#use reports_dave;
use reports;

$ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};

my ($message);

if ((-e "/home/p/pay1/outagefiles/highvolume.txt") || (-e "/home/p/pay1/outagefiles/mediumvolume.txt")) {
  $message ="Sorry this program is not available right now due to unscheduled database maintenance.<p>\n";
  $message .= "Please try back in a little while.<p>\n";
}


#  my $message = "Sorry, but due to the problems we experienced last week, system activity is abnormally high. For this reason the report section is being turned off temporarily. We appreciate your patience.";

if ($ENV{'SEC_LEVEL'} > 9) {
  $message = "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
}

if ($message ne "") {
  print "Content-Type: text/html\n\n";
  print "<html>\n";
  print "<head>\n";
  print "<title>Maintenance Notice</title>\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<div align=center>\n";
  print "<p>\n";
  print "<font size=+2>$message</font>\n";
  print "</body>\n";
  print "</html>\n";

  exit;
}


#print "Content-Type: text/html\n\n";

$username = $ENV{"REMOTE_USER"};

$query = new CGI;
$format = &CGI::escapeHTML($query->param('format'));
$mode = &CGI::escapeHTML($query->param('mode'));

$report = reports->new();

if ($mode eq "billing") {
  $report->query_cust();
  if ($format eq "text") {
    print "Content-Type: text/plain\n\n";
    $report->text_head();
  }
  else {
    print "Content-Type: text/html\n\n";
    $report->billing_head();
  }
  $report->query();

  if (($ENV{'REMOTE_USER'} =~ /^(northame|stkittsn|cableand)$/) && ($reports::merchant eq "EVERY")) {
    if (exists $reports::altaccts{$ENV{'REMOTE_USER'}}) {
      foreach my $un ( @{ $reports::altaccts{$ENV{'REMOTE_USER'}} } ) {
        $reports::username = $un;
        $report->billing();
      }
    }
  }
  else {
    $report->billing();
  }

  if ($format eq "text") {

  } 
  else { 
    $report->billing_tail();
  }
  exit;
}

print "Content-Type: text/html\n\n";

if ($format eq "settled") {
  $report->report_head();
  $report->report2();
  $report->tail();
}
elsif ($format eq "recurring") {
  $report->report_head();
  $report->query();
  $report->rec_report();
  $report->tail();
}
elsif ($format eq "batch_summary") {
  $report->report_head();
  $report->query1();
  $report->batch_summary();
  $report->tail();
}
elsif ($format eq "chargeback") {
  $report->report_head();
  $t1 = gmtime(time());
  $report->query();
  $t2 = gmtime(time());
  $report->query_cback();
  $t3 = gmtime(time());
  $report->cb_report();
  $t4 = gmtime(time());
  $report->tail();
  #print "$t1<br>\n$t2<br>\n$t3<br>\n$t4<br>\n";

}
else {
  $time = gmtime(time());
  #print "TIME TEST1:$time<br>\n";

  $report->report_head();
  $report->query_cust();

  $time = gmtime(time());
  #print "TIME TEST2:$time<br>\n";

  $report->query();

  $time = gmtime(time());
  #print "TIME TEST3:$time<br>\n";

  $report->query_cback();
  $time = gmtime(time());
  #print "TIME TEST4:$time<br>\n";

  $report->sales();
  $time = gmtime(time());
  #print "TIME TEST5:$time<br>\n";

  $report->trans();
  $time = gmtime(time());
  #print "TIME TEST6:$time<br>\n";

  $report->tail();
}
exit;
