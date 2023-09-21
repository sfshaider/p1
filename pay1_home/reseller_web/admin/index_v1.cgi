#!/bin/env perl

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'}; 
use reseller;

if ($ENV{'HTTP_X_FORWARDED_SERVER'} ne "") {
  $ENV{'SERVER_NAME'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_SERVER'}))[0];
}

$ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};

my $reseller = new reseller;


if (($ENV{'SEC_LEVEL'} eq "") && ($ENV{'REDIRECT_SEC_LEVEL'} ne "")) {
  $ENV{'SEC_LEVEL'} = $ENV{'REDIRECT_SEC_LEVEL'};
}
 
if (($ENV{'LOGIN'} eq "") && ($ENV{'REDIRECT_LOGIN'} ne "")) {
  $ENV{'LOGIN'} = $ENV{'REDIRECT_LOGIN'};
}

if ($ENV{'REMOTE_USER'} eq "sftman") {
  print "Location: https://$ENV{'SERVER_NAME'}/admin/overview/index.cgi\n\n";
  exit;
}

if ($reseller::query{'format'} eq "text") {
  print "Content-Type: text/plain\n\n"
}
else {
  my $servername = $ENV{'SERVER_NAME'};
  $servername =~ /(\w+)\.(\w+)\.(\w+)/;
  my $cookiehost = "\.$2\.$3";
  print "Set-Cookie: loginattempts=; path=/; expires=Fri, 01-Jul-11 23:00:00 GMT; domain=$cookiehost;\n";
  print "Content-Type: text/html\n\n"
}

if (($reseller::function eq "editcust") || ($reseller::function eq "Edit Account Info")) {
  &reseller::editcust();
}
elsif ($reseller::function eq "viewbuyrates") {
  # view reseller buy rates
  &reseller::viewbuyrates();
}
elsif ($reseller::function eq "commission") {
  if ($reseller::srchreseller ne "epenzio") {
    &reseller::commission();
  }
  #if ($ENV{'REMOTE_USER'} =~ /^(karin|cprice|dcprice|michelle|barbara|scaldero|drew|scottm|jamest)$/) {
  #  $reseller = $ENV{"REMOTE_USER"};
  #  &reseller::commission("new");
  #}
}
elsif ($reseller::function eq "comments") {
  &reseller::comments();
}
elsif ($reseller::function eq "updatecust") {
  &reseller::updatecust();
}
#elsif ($reseller::function eq "editstatus") {
elsif (($reseller::function eq "Edit Status") || ($reseller::function eq "editstatus")) {
  &reseller::editstatus();
}
elsif ($reseller::function eq "updatestatus") {
  &reseller::updatestatus();
}
elsif ($reseller::function eq "editapp") {
#  #print "Content-Type: text/html\n\n";
#  print "<html>\n";
#  print "<head></head>\n";
#  print "<body>\n";
#  print "This function has been temporally disabled.\n";
#  print "<br>It will be restored as soon as possible.\n";
#  print "</body>\n";
#  print "</html>\n";
#  exit;
  &reseller::editapp();
}
elsif ($reseller::function eq "updateapp") {
  &reseller::updateapp();
}
elsif ($reseller::function eq "status") {
  &reseller::status();
}
elsif ($reseller::function eq "search") {
  &reseller::search();
}
elsif ($reseller::function eq "batch") {
  &reseller::import_data();
}
elsif ($reseller::function eq "updatepaid") {
  &reseller::updatepaid();
}
elsif ($reseller::function eq "viewtransactions") {
  &reseller::viewtransactions();
}
elsif ($reseller::function eq "autochangepw") {
  &reseller::autochangepw();
}
elsif ($reseller::function eq "View Password File") {
  &reseller::viewpwfile();
}
elsif ($reseller::function eq "Delete Password File") {
  &reseller::deletepwfile();
}
elsif ($reseller::function eq "chargeback_import") {
  &reseller::chargeback_import();
}
else {
  &reseller::main("login.html");
}

exit;

