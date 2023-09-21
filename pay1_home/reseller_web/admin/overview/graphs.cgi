#!/bin/env perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use CGI;
use strict;

my %query;
my $query = new CGI;

my @array = $query->param;
foreach my $var (@array) {
  $query{"$var"} = &CGI::escapeHTML($query->param($var));
}

$ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};

my $dbh = &miscutils::dbhconnect("pnpmisc");
my $sth = $dbh->prepare(q{
    SELECT reseller, company
    FROM customers
    WHERE username=?
  }) or die "Can't do: $DBI::errstr";
$sth->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
my ($reseller, $merch_company) = $sth->fetchrow;
$sth->finish();
$dbh->disconnect;

print "Content-Type: text/html\n\n";

&html_head();

if ($ENV{'SEC_LEVEL'} > 9) {
  print "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
  &html_tail();
  exit;
}

if (($query{'subacct'} ne "") || ($query{'merchant'} =~ /icommerceg|icgoceanba|icgcrossco/)) {
  print "<form method=post action=\"reports.cgi\" onSubmit=\"return disableForm(this);\">\n";
  print "<input type=hidden name=\"subacct\" value=\"$query{'subacct'}\">\n";
}
else {
  print "<form method=post action=\"reports.cgi\" onSubmit=\"return disableForm(this);\">\n";
}

if ($query{'merchant'} ne "") {
  print "<input type=hidden name=\"merchant\" value=\"$query{'merchant'}\">\n";
}

print "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
print "  <tr class=\"menusection_title\">\n";
print "    <td colspan=2>Graphs (\$)</td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <td class=\"menuleftside\">Start Date:</td>\n";
print "    <td class=\"menurightside\">" . &miscutils::start_date() . "</td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <td class=\"menuleftside\">End Date:</td>\n";
print "    <td class=\"menurightside\">" . &miscutils::end_date() . "</td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <td class=\"menuleftside\">Period:</td>\n";
print "    <td  class=\"menurightside\"><input type=radio name=\"function\" value=\"daily\"> Daily\n";
print "&nbsp; <input type=radio name=\"function\" value=\"monthly\" checked> Monthly</td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <td class=\"menuleftside\">Group By:</td>\n";
print "    <td class=\"menurightside\"><input type=radio name=\"sortorder\" value=\"\" checked> None\n";
print "&nbsp; <input type=radio name=\"sortorder\" value=\"acctcode\"> Acct Code\n";
print "&nbsp; <input type=radio name=\"sortorder\" value=\"acctcode2\" > Acct Code 2\n";
print "&nbsp; <input type=radio name=\"sortorder\" value=\"acctcode3\" > Acct Code 3</td>\n";
print "  </tr>\n";

if (($query{'subacct'} ne "") || ($query{'merchant'} =~ /icommerceg|icgoceanba|icgcrossco/)) {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Report:</td>\n";
  print "    <td class=\"menurightside\"><input type=radio name=\"format\" value=\"\"> Sales/Transactions\n";
  print "&nbsp; <input type=radio name=\"format\" value=\"chargeback\"> Chargebacks</td>\n";
  print "  </tr>\n";
}

if ($ENV{'REMOTE_ADDR'} eq "96.56.10.12") {
  if ($ENV{'REMOTE_USER'} =~ /^(cableand)$/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">Billing:</td>\n";
    print "    <td class=\"menurightside\"><input type=checkbox name=\"format\" value=\"billing\"> Billing</td>\n";
    print "  </tr>\n";
  }
}
if ($ENV{'REMOTE_ADDR'} eq "96.56.10.12") {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Recurring:</td>\n";
  print "    <td class=\"menurightside\"><input type=checkbox name=\"recurring\" value=\"yes\"> Recurring</td>\n";
  print "  </tr>\n";
}

print "  <tr>\n";
print "    <td class=\"menuleftside\">&nbsp;</td>\n";
print "    <td class=\"menurightside\"><input type=submit name=\"submit\" value=\" Generate Graph \"></td></form>\n";
print "  </tr>\n";
print "</table>\n";

if ($ENV{"REMOTE_USER"} =~ /^(dietsmar|dietsmar2|vfinance|nutricisec|friendfinde|friendfinde1|friendfinde2)$/) {
  print "<form method=post action=\"reports.cgi\" onSubmit=\"return disableForm(this);\">\n";
  if ($query{'merchant'} ne "") {
    print "<input type=hidden name=\"merchant\" value=\"$query{'merchant'}\">\n";
  }

  print "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr class=\"menusection_title\">\n";
  print "    <td colspan=2>Reports</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Start Date:</td>\n";
  print "    <td class=\"menurightside\">" . &miscutils::start_date() . "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">End Date:</td>\n";
  print "    <td class=\"menurightside\">" . &miscutils::end_date() . "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Format:</td>\n";
  print "    <td class=\"menurightside\"><input type=radio name=\"format\" value=\"settled\" checked> Settled Transactions</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\"><input type=submit name=\"submit\" value=\" Generate Report \"></td></form>\n";
  print "  </tr>\n";

  print "</table>\n";
}

&html_tail();
exit;

sub html_head {

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Graphs/Reports</title>\n";
  print "<link href=\"/css/style_graphs.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  # js logout prompt
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery_ui/jquery-ui.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery_cookie.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/_js/admin/autologout.js\"></script>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/javascript/jquery_ui/jquery-ui.css\">\n";

  print "<script type='text/javascript'>\n";
  print "  /** Run with defaults **/\n";
  print "    \$(document).ready(function(){\n";
  print "    \$(document).idleTimeout();\n";
  print "  });\n";
  print "</script>\n";
  # end logout js

  print "<script type=\"text/javascript\">\n";
  print "//<!-- Start Script\n";

  print "function disableForm(theform) {\n";
  print "  if (document.all || document.getElementById) {\n";
  print "    for (i = 0; i < theform.length; i++) {\n";
  print "      var tempobj = theform.elements[i];\n";
  print "      if (tempobj.type.toLowerCase() == 'submit' || tempobj.type.toLowerCase() == 'reset')\n";
  print "        tempobj.disabled = true;\n";
  print "    }\n";
  print "    return true;\n";
  print "  }\n";
  print "  else {\n";
  print "    return true;\n";
  print "  }\n";
  #print "  alert('Please be patient, creating the report may take several minutes.');\n";
  #print "  notice();\n";
  print "}\n";

  print "function notice() {\n";
  print "  alert('Please be patient, creating the report may take several minutes.');\n";
  print "}\n";

  print "function change_win(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "//-->\n";
  print "</script>\n";

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=2 align=left>";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "<img src=\"/images/global_header_gfx.gif\" width=760 alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=44 border=0>";
  }
  else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2 align=left><img src=\"/css/header_bottom_bar_gfx.gif\" width=760 height=14></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=2><h1><a href=\"$ENV{'SCRIPT_NAME'}\">Graphs/Reports</a> - $merch_company</h1>\n";
}

sub html_tail {

  my @now = gmtime(time);
  my $copy_year = $now[5]+1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=left><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></td>\n";
  print "    <td align=right>\&copy; $copy_year, ";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "Plug and Pay Technologies, Inc.";
  }
  else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
}
