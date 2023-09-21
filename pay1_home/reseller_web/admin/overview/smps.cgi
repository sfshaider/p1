#!/bin/env perl

require 5.001;
local $|=0;

use lib $ENV{'PNP_PERL_LIB'};
use smps;
use CGI qw/:standard/;
use PlugNPay::Environment;
use PlugNPay::GatewayAccount;
use strict;

# Redirect to /admin/orders if feature is set or is new processor!!!
BEGIN {
  my $env = new PlugNPay::Environment();
  my $gatewayAccountUsername = $env->get('PNP_ACCOUNT');
  my $gatewayAccount = new PlugNPay::GatewayAccount($gatewayAccountUsername);
  my $features = $gatewayAccount->getFeatures();

  if ($features->get('useOrders') eq '1' || $gatewayAccount->usesUnifiedProcessing()) {
    my $cgi = new CGI();
    $cgi->redirect( -uri => '/admin/orders/' );
  }
}

$ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};


my $smpsnew = smps->new();

if (($ENV{'SEC_LEVEL'} >= 11) && ($ENV{'SEC_LEVEL'} != 13)) {
  my $message = "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
  &smps::response_message($message);
}

foreach my $key (keys %smps::cookie_out) {
  #if ($ENV{'REMOTE_ADDR'} =~ /^96\.56\.10\.1/) {
  my(@cookie);
  my $i = 0;
  foreach my $key (keys %smps::cookie_out) {
    $cookie[$i] = cookie(-name => "$key", -value => "$smps::cookie_out{$key}");
  }
  print header(-cookie => [@cookie]);
}

my $receipt_type = &CGI::escapeHTML($smps::query->param('receipt_type'));

if (($smps::function eq "return") && ($smps::format !~ /^(text|download|iphone)$/)) {
  print header( -type  => 'text/html'); #### DCP 20101208
  $smps::header_printed = "yes";
}
elsif (($smps::format !~ /^(text|download|iphone)$/) && ($receipt_type eq "")) {
  print header( -type  => 'text/html'); #### DCP 20100712
  $smps::header_printed = "yes";
  #print "Content-Type: text/html\n\n";
  #print "<UN:$ENV{'REMOTE_USER'}, LOGIN:$ENV{'LOGIN'}, FUNC:$smps::function>\n";
  &smps::head("Transaction");
}
elsif ($smps::format eq "text") {
  print header(-type  => 'text/plain', -attachment => 'querydata.txt'); #### DCP 20100712
  $smps::header_printed = "yes";
  #print "Content-Type: text/plain\n\n";
  #print "Content-Disposition: inline; filename=querydata.txt\n\n";
}
elsif ($smps::format eq "download") {
  print header( -type  => 'application/x-download', -attachment => 'querydata.txt'); #### DCP 20100712
  $smps::header_printed = "yes";
  #print "Content-Type: application/x-download\n\n";
  #print "Content-Disposition: attachment; filename=querydata.txt\n\n";
}

if ($smps::function eq "query") {
 &smps::query();
}
elsif ($smps::function eq "input") {
 &smps::input();
}
elsif ($smps::function eq "inputnew") {
 &smps::input_new();
}
elsif ($smps::function eq "return") {
 &smps::return();
}
elsif ($smps::function eq "batchretry") {
 &smps::batchretry();
}
#elsif ($smps::function eq "carddetails") {   ## Added for comparision purposes to old smps.cgi script
# &smps::carddetails();
#}
elsif ($smps::function eq "details") {
 &smps::details();
}
elsif ($smps::function eq "dailyreport") {
 &smps::daily_report_query();
}
elsif ($smps::function eq "batchquery") {
 &smps::batchquery();
}
elsif ($smps::function eq "batchdetails") {
 &smps::batchdetails();
}
#elsif ($smps::function eq "batchunroll") {  ## Added for comparision purposes to old smps.cgi script
# &smps::batchunroll();
#}
elsif ($smps::function eq "assemble") {
 &smps::assemble();
}
elsif ($smps::function eq "submit") {
 &smps::submit();
}
elsif ($smps::function eq "mark") {
 &smps::mark();
}
elsif ($smps::function eq "retry") {
 &smps::retry();
}
elsif ($smps::function eq "unmark") {
 &smps::unmark();
}
elsif ($smps::function eq "batchupload") {
  &smps::storebatchfile();
}
elsif ($smps::function eq "chargeback") {
  &smps::chargeback();
}
elsif ($smps::function eq "chrgbckdetails") {
  &smps::chrgbckdetails();
}
elsif ($smps::function eq "chargeback_review") {
  &smps::chargeback_review();
}
elsif ($smps::function eq "chargeback_import") {
  &smps::chargeback_import();
}
elsif ($smps::function eq "dccoptout") {
  &smps::dccoptout();
}
elsif ($smps::function eq "orders") {
  &smps::orders();
}
else {
  &smps::main();
}

if (($smps::function ne "") && ($smps::format !~ /^(text|download)$/) && ($receipt_type eq "")) {
  &smps::tail();
}

1;
