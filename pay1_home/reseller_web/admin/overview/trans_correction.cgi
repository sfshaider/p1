#!/bin/env perl

# Purpose: Display transaction data of batches transactions which were corected, but do not show in merchant's records correctly
# - Built by David Price's direction, to address Visanet duplicate batch issue from 05/26/2011,
#     where the original transaction [postauth/return] cannot be seen, but the reverse transaction [return/auth] to correct the matter do show in batch reports

# Last Updated: 06/25/12

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};
use pnp_environment;
use miscutils;
use CGI;
use strict;

my %query;
my $query = new CGI;

my @array = $query->param;
foreach my $key (sort @array) {
  $key =~ s/[^a-zA-Z0-9\_\-]//g;
  $query{"$key"} = &CGI::escapeHTML($query->param($key));
}

if ($ENV{'SEC_LEVEL'} > 13) {
  print "Content-Type: text/html\n\n";
  print "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
  exit;
}

my $allow_overview = "";

if (($query{'merchant'} ne "") && ($ENV{'SCRIPT_NAME'} =~ /overview/)) {
  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh->prepare(qq{
      select overview
      from salesforce
      where username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
  ($allow_overview) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;
}

my $username = $ENV{'REMOTE_USER'};
my (%altaccts);

if (($allow_overview == 1)) {
  if ($query{'merchant'} eq "ALL") {
    my @merchlist = &merchlist($ENV{'REMOTE_USER'});
    %altaccts = ($ENV{'REMOTE_USER'},[@merchlist]);
    $username = $ENV{'REMOTE_USER'};
  }
  else {
    $username = &overview($ENV{'REMOTE_USER'},$query{'merchant'});
    $ENV{'REMOTE_USER'} = $username;
  }

  #$username = &overview($ENV{'REMOTE_USER'},$query{'merchant'});
  #$ENV{'REMOTE_USER'} = $username;
}

if (($query{'merchant'} ne "") && ($allow_overview != 1)) {
  $username = &is_linked_acct("$ENV{'REMOTE_USER'}", "$query{'merchant'}");
}

my @orders;
my ($auth_count, $return_count, $count);
my ($auth_total, $return_total, $total);

&html_head("Transaction Settlement Corrections");

print "<p>On Thursday, May 26 2011, there was an issue with the program that submits transactions for settlement.  As a result, some transactions were submitted twice, thereby causing the customer to be charged twice. \n";

print "<p>To address this issue, the system submitted credits to cancel each of the duplicate transactions. No further action is required on your part. \n";

print "<p>The following transactions were corrected:\n";

print "<p><table border=1>\n";
print "  <tr>\n";
#print "    <th><nobr>Merchant</nobr></td>";
print "    <th><nobr>OrderID</nobr></th>";
print "    <th><nobr>Card Number</nobr></th>";
#print "    <th><nobr>Name</nobr></th>";
#print "    <th><nobr>Address</nobr></th>";
#print "    <th><nobr>City</nobr></th>";
#print "    <th><nobr>State</nobr></th>";
#print "    <th><nobr>Zip</nobr></th>";
#print "    <th><nobr>Country</nobr></th>";
#print "    <th><nobr>Amount</nobr></th>";
print "    <th><nobr>Reversed Amt</nobr></th>";
#print "    <th><nobr>TransFlags</nobr></th>";
#print "    <th><nobr>Operation</nobr></th>";
#print "    <th><nobr>FinalStatus</nobr></th>";
print "    <th><nobr>Reverse Operation</nobr></th>";
print "  </tr>\n";

my $path_webtxt = &pnp_environment::get('PNP_WEB_TXT');
open(INFILE, "$path_webtxt/admin/trans_correction_20110526.txt") or die "Cannot open file for reading. $!";
while(<INFILE>) {
  my $theline = $_;
  chomp $theline;
  my @data = split(/\,/, $theline);
  if ($data[0] eq "$username") {
    print "  <tr>\n";
    for (my $i = 0; $i <= $#data; $i++) {
      # only deplay entries indicated
      if ($i =~ /^(1|2|10|14)$/) {
        print "    <td><nobr>$data[$i]</nobr></td>";
      }
    }
    print "  <tr>\n";

    my $amount = $data[10];
    $amount =~ s/[^0-9\.]//g;

    $count = $count + 1;
    if ($data[14] =~ /auth/i) {
      $auth_count = $auth_count + 1;
      $auth_total = $auth_total + $amount;
    }
    else {
      $return_count = $return_count + 1;
      $return_total = $return_total + $amount;
    }
  }
}
close(INFILE);

if ($count == 0) {
  print "  <tr>\n";
  print "    <td colspan=4 align=\"center\"><nobr><b>No transactions within this account were affected.</b></br>If you have multiple accounts, please check them.</nobr></td>";
  print "  <tr>\n";
}

print "</table>\n";

$total = $auth_total - $return_total;

if ($count > 0) {
  printf("<p><b>Reversed Tally:</b> %d Transactions\n", $count);
  printf("<br>&bull; Auth: %d\n", $auth_count);
  printf("<br>&bull; Return: %d\n", $return_count);

  printf("<p><b>Reversed Total:</b> %0.2f\n", $total);
  printf("<br>&bull; Auth: %0.2f\n", $auth_total);
  printf("<br>&bull; Return: %0.2f\n", $return_total); 
}

&html_tail();

exit;

sub html_head {
  my ($title) = @_;

  my $merchant = &CGI::escapeHTML($query->param("merchant"));
  $merchant =~ s/[^a-zA-Z0-9]//g;
  $merchant =~ lc("$merchant");
  if ($merchant !~ /\w/) {
    $merchant = $ENV{'REMOTE_USER'};
  }

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth_cust = $dbh->prepare(qq{
          select company
          from customers
          where username=?
          }) or die "Can't do: $DBI::errstr";
  $sth_cust->execute("$merchant") or die "Can't execute: $DBI::errstr";
  my ($company) = $sth_cust->fetchrow;
  $sth_cust->finish;
  $dbh->disconnect;

  print "Content-Type: text/html\n\n";

  print "<html>\n";
  print "<head>\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<link href=\"/css/style_orderdb.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<title>$title UN:$ENV{'REMOTE_USER'} M:$merchant</title>\n";

  print "<script Language=\"Javascript\">\n";
  print "<!-- Start Script\n";

  print "function disableForm(theform) {\n";
  print "  if (document.all || document.getElementById) {\n";
  print "    for (i = 0; i < theform.length; i++) {\n";
  print "      var tempobj = theform.elements[i];\n";
  print "      if (tempobj.type.toLowerCase() == \"submit\" || tempobj.type.toLowerCase() == \"reset\")\n";
  print "        tempobj.disabled = true;\n";
  print "      if (tempobj.type.toLowerCase() == \"button\") \n";
  print "        tempobj.disabled = false; \n";
  print "    }\n";
  print "    return true;\n";
  print "  }\n";
  print "  else {\n";
  print "    return true;\n";
  print "  }\n";
  print "}\n";
  print "// end script-->\n";

  print "function enableForm(theform) { \n";
  print "  if (document.all || document.getElementById) { \n";
  print "    for (i = 0; i < theform.length; i++) { \n";
  print "      var tempobj = theform.elements[i]; \n";
  print "      if (tempobj.type.toLowerCase() == \"submit\" || tempobj.type.toLowerCase() == \"reset\") \n";
  print "        tempobj.disabled = false; \n";
  print "      if (tempobj.type.toLowerCase() == \"button\") \n";
  print "        tempobj.disabled = true; \n";
  print "    } \n";
  print "    return true; \n";
  print "  } \n";
  print "  else { \n";
  print "    return true; \n";
  print "  } \n";
  print "} \n";

  print "function change_win(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "</script>\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\">";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) { ## DCP 20100719 changed from Forwarded_server
    print "<img src=\"/images/global_header_gfx.gif\" width=\"760\" alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=\"44\" border=\"0\">";
  }
  else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\"><img src=\"/css/header_bottom_bar_gfx.gif\" width=\"760\" height=\"14\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"5\" width=\"760\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\"><h1><a href=\"$ENV{'SCRIPT_NAME'}\">Transaction Settlement Corrections</a> - $company</h1>\n";

  return;
}

sub html_tail {
  my @now = gmtime(time);
  my $copy_year = $now[5]+1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=\"left\"><p><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></p></td>\n";
  print "    <td align=\"right\"><p>\&copy; $copy_year, ";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "Plug and Pay Technologies, Inc.";
  }
  else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</p></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";

  return;
}

sub is_linked_acct {
  # Purpose: Check merchant name given & make sure its a linked account username
  #          Returns validated username to use (supplied merchant if linked, or login username if not linked)
  my ($username, $merchant) = @_;

  my %feature;

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth_merchants = $dbh->prepare(qq{
       select features
       from customers
       where username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth_merchants->execute("$username") or die "Can't execute: $DBI::errstr";
  my ($features) = $sth_merchants->fetchrow;
  $sth_merchants->finish;

  if ($features ne "") {
    my @array = split(/\,/,$features);
    foreach my $entry (@array) {
      my ($name, $value) = split(/\=/,$entry,2);
      if ($value =~ /\w/) {
        $feature{"$name"} = $value;
      }
    }
  }
  $dbh->disconnect;

  if ($merchant =~ /^($feature{'linked_accts'})$/) {
    return "$merchant";
  }
  else {
    return "$username";
  }
}

sub overview {
  my ($reseller, $merchant) = @_;
  my ($db_merchant);

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  if ($reseller eq "cableand") {
    my $sth = $dbh->prepare(qq{
        select username   
        from customers
        where reseller IN ('cableand','cccc','jncb','bdagov') 
        and username=? 
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$merchant") or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;
    $sth->finish;
  }
  elsif ($reseller eq "volpayin") {
    my $sth = $dbh->prepare(qq{
        select username   
        from customers
        where processor='volpay'
        and username=? 
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$merchant") or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;
    $sth->finish;
  }
  else {
    my $sth = $dbh->prepare(qq{ 
        select username 
        from customers 
        where reseller=? and username=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$reseller", "$merchant") or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;
    $sth->finish;
  }

  $dbh->disconnect;

  return $db_merchant;
}

