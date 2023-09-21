#!/bin/env perl

# Purpose: provide interface to allow resellers to self-view & link multiple PnP accounts together which belong to the same company

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};
use CGI;
use miscutils;
use PlugNPay::InputValidator;
use strict;

my %query;
my $query = new CGI;

my @array = $query->param;
foreach my $var (@array) {
  $var =~ s/[^a-zA-Z0-9\_\-]//g;
  $query{$var} = &CGI::escapeHTML($query->param($var));
}

my $iv = new PlugNPay::InputValidator();
$iv->changeContext('link_accounts');
%query = $iv->filterHash(%query);

if (($ENV{'HTTP_X_FORWARDED_SERVER'} ne '') && ($ENV{'HTTP_X_FORWARDED_FOR'} ne '')) {
  $ENV{'HTTP_HOST'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_HOST'}))[0];
  $ENV{'SERVER_NAME'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_SERVER'}))[0];
}

## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
if ($ENV{'HTTP_X_FORWARDED_FOR'} ne '') {
  $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
}

my $allowed_staff = 'unplugged|jamest'; # pipe delimited username list of staff, which is permitted to make changes to all accounts

# apply basic input filters to query data
if ($query{'username'} ne '') {
  $query{'username'} = lc($query{'username'});
}

my $dbh_misc = &miscutils::dbhconnect('pnpmisc');

print "Content-Type: text/html\n\n";

my $script = "https://" . $ENV{'HTTP_HOST'} . $ENV{'SCRIPT_NAME'};

# Select Mode
if ($query{'mode'} eq 'edit_link') {
  &edit_link(%query);
}
elsif ($query{'mode'} eq 'quick_link') {
  &quick_link(%query);
}
elsif ($query{'mode'} eq 'update_link') {
  &update_link(%query);
  &view_account(%query);
}
elsif ($query{'mode'} eq 'remove_link') {
  &remove_link(%query);
  &show_menu();
}
elsif ($query{'mode'} eq 'remove_one') {
  &remove_one(%query);
  &show_menu();
}
elsif ($query{'mode'} eq 'global_remove') {
  &global_remove_link(%query);
  &show_menu();
}
elsif ($query{'mode'} eq 'view_account') {
  &view_account(%query);
}
elsif ($query{'mode'} eq 'list_accounts') {
  &list_accounts(%query);
}
elsif ($query{'mode'} eq 'search_accounts') {
  &search_accounts(%query);
}
else {
  &show_menu(%query);
}

$dbh_misc->disconnect;

exit;

sub html_head {
  my %query = @_;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Linked Payment Gateway Accounts</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/css/style_green_beta.css\">\n";

  # css for tablesorter
  print "<style type=\"text/css\">\n";
  print "th.header {\n";
  print "  background-image: url(https://pay1.plugnpay.com/images/bg.gif);\n";
  print "  cursor: pointer;\n";
  print "  background-repeat: no-repeat;\n";
  print "  background-position: center left;\n";
  print "  padding-left: 20px;\n";
  print "  font-family: Verdana, Arial, sans-serif;\n";
  print "  font-size: 13px;\n";
  print "  font-weight: bold;\n";
  print "  color: #333333;\n";
  print "  text-align: left;\n";
  print "  vertical-align: bottom;\n";
  print "  background-color: #dddddd;\n";
  print "}\n";
  print "th.headerSortUp {\n";
  print "  background-image: url(https://pay1.plugnpay.com/images/asc.gif);\n";
  print "}\n";
  print "th.headerSortDown {\n";
  print "  background-image: url(https://pay1.plugnpay.com/images/desc.gif);\n";
  print "}\n";
  print "table.tablesorter tbody tr.odd td {\n";
  print "  background-color: #ffffff;\n";
  print "}\n";
  print "table.tablesorter tbody tr.even td {\n";
  print "  background-color: #eeeeee;\n";
  print "}\n";

  print ".button {\n";
  print "  border-radius: 7px;\n";
  print "  -moz-border-radius: 7px;\n";
  print "  -webkit-border-radius: 7px;\n";
  print "  border: 2px solid #777777;\n";
  print "  border-top: #FFFFFF;\n";
  print "  border-left: #FFFFFF;\n";
  print "  font-size: 12px;\n";
  print "  font-weight: bold;\n";
  print "  font: Arial;\n";
  print "  color: #333333;\n";
  print "  background-color: #EEEEEE;\n";
  print "  height: 19px;\n";
  print "  padding: 0px 10px;\n";
  print "}\n";
  print ".button:hover {\n";
  print "  color: #339900;\n";
  print "  text-decoration: none;\n";
  print "}\n";
  print "</style>\n";

  # js logout prompt
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"https://pay1.plugnpay.com/javascript/jquery.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"https://pay1.plugnpay.com/javascript/jquery_ui/jquery-ui.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"https://pay1.plugnpay.com/javascript/jquery_cookie.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"https://pay1.plugnpay.com/_js/admin/autologout.js\"></script>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/javascript/jquery_ui/jquery-ui.css\">\n";

  print "<script type='text/javascript'>\n";
  print "  /** Run with defaults **/\n";
  print "  \$(document).ready(function(){\n";
  print "    \$(document).idleTimeout();\n";
  print "  });\n";
  print "</script>\n";
  # end logout js

  print "<script type=\"text/javascript\" src=\"https://pay1.plugnpay.com/javascript/tablesorter/jquery.metadata.js\"></script>\n";
  print "<script id=\"sortscript\" src=\"https://pay1.plugnpay.com/javascript/tablesorter/jquery.tablesorter.js\"></script>\n";

  print "<script Language=\"Javascript\">\n";
  print "<!-- // Begin Script \n";

  print "// tablesorter //\n";
  print "\$(document).ready(function() {\n";
  print "  \$(\"#sortabletable\").tablesorter({\n";
  print "      widgets: ['zebra'],\n";
  print "      textExtraction: function(node) {\n";
  print "          return node.getAttribute('sortvalue') || node.innerHTML;\n";
  print "      }\n";
  print "  });\n";
  print "});\n";
  print "// end tablesorter //\n";


  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";
  print "// end script -->\n";
  print "</script>\n";

  if (($query{'mode'} eq '') || ($query{'mode'} =~ /^(quick_link)$/)) {
    my @merch_username = ();
    my @merch_name = ();
    my @merch_company = ();
    my @merch_status = ();

    my @placeholder = ();
    my $qstr = "SELECT username, name, company, status";
    $qstr .= " FROM customers";
    $qstr .= " WHERE status IN (?,?)";
    push (@placeholder, 'debug', 'live');
    if ($ENV{'TECH'} !~ /^($allowed_staff)$/) {
      $qstr .= " AND reseller=?";
      push(@placeholder, $ENV{'REMOTE_USER'});
    }
    $qstr .= " ORDER BY username";

    my $dbh = &miscutils::dbhconnect("pnpmisc");
    my $sth = $dbh->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
    $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
    while (my ($db_username, $db_name, $db_company, $db_status) = $sth->fetchrow) {
      push(@merch_username, $db_username);
      push(@merch_name, $db_name);
      push(@merch_company, $db_company);
      push(@merch_status, $db_status);
    }
    $sth->finish;
    $dbh->disconnect;

    print "<script type = \"text/javascript\">\n";
    print "  \$(function() {\n";
    print "    var availableAccts = [\n";
    for (my $i = 0; $i <= $#merch_username; $i++) {
      print " \'$merch_username[$i]\',";
    }
    print " ];\n";
    print "  \$( \"#autocomplete\" ).autocomplete({\n";
    print "    source: availableAccts\n";
    print "  });\n";
    print "});\n";
    print "</script>\n";

    if ($query{'mode'} =~ /^(quick_link)$/) {
      print "<script type=\"text/javascript\">\n";

      # hosts list of usernames added to the link list
      print "  var AcctsAdded = [ \n";
      print "\'$query{'username'}\',";
      print " ]; \n\n";

      # holds list of merchant usernames allowed to be linked
      print "  var MerchUsername = [ ";
      for (my $i = 0; $i <= $#merch_username; $i++) {
        print " \'$merch_username[$i]\',";
      }
      print " ]; \n\n";

      # holds list of contact names for given merchant usernames
      print "  var MerchName = [ ";
      for (my $i = 0; $i <= $#merch_name; $i++) {
        print " \'$merch_name[$i]\',";
      }
      print " ]; \n\n";

      # holds list of company names for given merchant usernames
      print "  var MerchCompany = [ ";
      for (my $i = 0; $i <= $#merch_company; $i++) {
        print " \'$merch_company[$i]\',";
      }
      print " ]; \n\n";

      # holds list of status for given merchant usernames
      print "  var MerchStatus = [ ";
      for (my $i = 0; $i <= $#merch_status; $i++) {
        print " \'$merch_status[$i]\',";
      }
      print " ]; \n\n";

      # this keeps track of what the next 'account_#' field name should be.
      print "  var cnt = 1; \n\n";

print<<EOF;
function appendUser(list) {
  var tmpList = list.split('\|');

  outmostloop: // outer most loop label name
  for (var a = 0; a < tmpList.length; a++) {
    var uname = tmpList[a];

    var allowUN = 0; // is set when username is allowed.
    var existUN = 0; // is set when usernames is listed.
    var idx = 0; // array's index number, so we can get merchant's name, company and status info

    outerloop: // outer loop label name
    for (var i = 0; i < MerchUsername.length; i++) {
      if (MerchUsername[i] === uname) {
        allowUN = 1;
        idx = i;

        innerloop: // inner loop label name
        for (var j = 0; j < AcctsAdded.length; j++) {
          if (AcctsAdded[j] == uname) {
            existUN = 1;
            break outerloop;
          }
        }
      }
    }

    if (allowUN === 1) {
      if (existUN === 0) {
        // add username, since its allowed and not listed.
        var entry = '<table width=760 border=1 cellpadding=0 cellspacing=0>';
        entry += ' <tr>';
        entry += '    <td align=center width=95><input type=checkbox name=account_' + cnt + ' value=' + uname + ' checked></td>';
        entry += '    <td width=115>' + uname + '</td>';
        entry += '    <td width=115>' + MerchName[idx] + '</td>';
        entry += '    <td>' + MerchCompany[idx] + '</td>';
        entry += '    <td width=75>' + MerchStatus[idx] + '</td>';
        entry += '  </tr>';
        entry += '</table>';

        document.getElementById('acctlist').innerHTML += entry;
        AcctsAdded.push(uname);
        cnt++;
      }
      else {
        alert('Username \"' + uname + '\" is already listed.');
      }
    }
    else {
      alert('Username \"' + uname + '\" does not exist or does not belong to reseller.');
    }
  }
}
EOF
      print "</script>\n";
    }
  }
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\" text=\"#000000\"";
  if ($query{'mode'} =~ /^(search_accounts|list_accounts|edit_link|quick_link)$/) {
    print " onLoad=\"hideit.style.display='none';\"";
  }
  print ">\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"header\">\n";
  print "  <tr>\n";
  print "    <td><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Payment Gateway Logo\"></td>\n";
  print "    <td class=right>&nbsp;</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=2><img src=\"/adminlogos/masthead_background.gif\" alt=\"Corp. Logo\" width=750 height=16></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=3 valign=top align=left><h1><b><a href=\"$script\">Linked Payment Gateway Accounts</a></b></h1></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0>\n";
  print "  <tr>\n";
  print "    <td valign=top align=left>";

  return;
}

sub html_tail {

  my @now = gmtime(time);
  my $year = $now[5] + 1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=left><a href=\"/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"mailto:support\@plugnpay.com\">Contact Support</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></td>\n";
  print "    <td align=right>\&copy; $year, ";
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
  return;
}

sub show_menu {
  my %query = @_;

  &html_head(%query);

  print "<p>This portion of the site has been constructed to permit resellers to manage linking between multiple payment gateway accounts, which are owned & operated by the same merchant.  Below you should find all the tools necessary to handle the management of these linked accounts.</p>\n";

  print "<p>&bull; <font color=\"#ff0000\"><b><u>IMPORTANT NOTE:</u></b></font> <i>Please be very careful when linking accounts.  Linking of accounts not owned & operated by the same merchant will result in said merchant(s) being able to access the other's transactions.  Contact us immediately in the event of an account linking problem.</i></p>\n";

  print "<p>If you have any problems linking multiple accounts, please contact us via normal support channels or email <a href=\"mailto:support\@plugnpay.com\">support\@plugnpay.com</a>.  When submitting your support request, please be as specific as possible & provide examples where necessary.  Please also remember to include your contact information (name, email address &amp; phone number) & reseller userame.</p>\n";

  print "<p>Thank you,\n";
  print "<br>Plug 'n Pay Staff.</p>\n";

  print "<hr>\n";

  print "<table border=0 cellspacing=0 cellpadding=0 width=760>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">List Accounts</td>\n";
  print "    <td class=\"menurightside\"><form action=\"$script\" method=post>\n";
  print "<input type=hidden name=\"mode\" value=\"list_accounts\">\n";
  print "<input type=radio name=\"type\" value=\"all\" checked> All Accounts\n";
  print "<br><input type=radio name=\"type\" value=\"linked\"> Linked Accounts Only\n";
  print "<br><input type=radio name=\"type\" value=\"unlinked\"> Unlinked Accounts Only\n";
  print "<br><input type=submit class=\"button\" value=\"List Accounts\"></form>\n";
  print "  </td>\n";
  print "</tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menurightside\" colspan=2><hr></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Manage Account</td>\n";
  print "    <td class=\"menurightside\"><form action=\"$script\" method=post>\n";
  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <th class=\"leftside\">Operation:</th>\n";
  print "    <td class=\"rightside\"><input type=radio name=\"mode\" value=\"view_account\" checked> View Account\n";
  print "<input type=radio name=\"mode\" value=\"edit_link\"> Edit Account\n";
  print "<input type=radio name=\"mode\" value=\"quick_link\"> Quick Link</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"leftside\">Username:</th>\n";
  print "    <td class=\"rightside\"><input id=\"autocomplete\" type=text name=\"username\" value=\"\" size=20 maxlength=20></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "<input type=submit class=\"button\" value=\"Submit\"></form>\n";
  print "  </td>\n";
  print "</tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menurightside\" colspan=2><hr></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Search Accounts</td>\n";
  print "    <td class=\"menurightside\"><form action=\"$script\" method=post>\n";
  print "<input type=hidden name=\"mode\" value=\"search_accounts\">\n";
  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <th class=\"leftside\">Username:</th>\n";
  print "    <td class=\"rightside\"><input type=text name=\"srch_username\" value=\"\" size=20></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"leftside\">Email:</th>\n";
  print "    <td class=\"rightside\"><input type=email name=\"srch_email\" value=\"\" size=30></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"leftside\">Phone:</th>\n";
  print "    <td class=\"rightside\"><input type=tel name=\"srch_phone\" value=\"\" size=20></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"leftside\">Name:</th>\n";
  print "    <td class=\"rightside\"><input type=text name=\"srch_name\" value=\"\" size=30></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"leftside\">Company:</th>\n";
  print "    <td class=\"rightside\"><input type=text name=\"srch_company\" value=\"\" size=30></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"leftside\">Exact Match:</th>\n";
  print "    <td class=\"rightside\"><input type=checkbox name=\"srch_exact\" value=\"yes\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "<input type=submit class=\"button\" value=\"Submit\"> &nbsp; <input type=reset class=\"button\" value=\"Reset\"></form>\n";
  print "  </td>\n";
  print "</tr>\n";

  print "</table>\n";

  &html_tail();
  return;
}

sub show_error {
  my ($message) = @_;

  $query{'mode'} = "";

  &html_head(%query);
  print "<div align=center>\n";
  print "<font class=\"error_text\">$message</font>\n";
  print "<p><a href=\"$script\"><b>Click here to return to the main menu</b></a></p>\n";
  print "</div>\n";
  &html_tail();

  exit;
}

sub list_accounts {
  ## list reseller's accounts
  my %query = @_;

  my %selected;
  if ($query{'sort_by'} !~ /^(username|name|company|status)$/) {
    $query{'sort_by'} = "username";
  }
  $selected{"$query{'sort_by'}"} = "<font size=\"+1\">&raquo;</font>&nbsp;";

  &html_head(%query);

  if ($query{'type'} eq 'linked') {
    print "<p><b>This report lists the master accounts, which permit linking to other payment gateway accounts.</b>\n";
  }
  elsif ($query{'type'} eq 'unlinked') {
    print "<p><b>This report lists the master accounts, which are not linked to any other payment gateway accounts.</b>\n";
  }
  else {
    print "<p><b>This report lists all of your payment gateway accounts.</b>\n";
  }

  print "<br><b>Click on the Username of the account you wish to see additional details of.</b>\n";
  print "<br>&bull; To re-organize the list, click on the column's title you wish to sort by.</p>\n";

  print "<div id=\"hideit\">\n";
  print "<h2>Please wait for the list to complete.  Depending upon many factors, this may take a while...</h2>\n";
  print "</div>\n";

  print "<table class=\"tablesorter {sortlist: [[3,0]]}\" id=\"sortabletable\" width=760 border=1 cellpadding=0 cellspacing=0>\n";
  print "<thead>\n";
  print "  <tr>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Username</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Name</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Company</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Status</th>\n";
  print "  </tr>\n";
  print "</thead>\n";
  print "<tbody>\n";

  my $count = 0;
  my $color = 1;

  my @placeholder = ();
  my $qstr .= "SELECT username, name, company, status";
  $qstr .= " FROM customers";
  $qstr .= " WHERE status IN (?,?)";
  push (@placeholder, "debug", "live");
  if ($ENV{'TECH'} !~ /^($allowed_staff)$/) {
    $qstr .= " AND reseller=?";
    push(@placeholder, $ENV{'REMOTE_USER'});
  }
  $qstr .= " ORDER BY $query{'sort_by'}";

  my $sth = $dbh_misc->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  while (my ($username, $name, $company, $status) = $sth->fetchrow) {
    if ($query{'type'} eq 'linked') {
      my $linked = &is_linked("$username");
      if ($linked eq 'yes') {
        if ($color == 1) {
          print "  <tr class=\"listrow_color1\">\n";
        }
        else {
          print "  <tr class=\"listrow_color0\">\n";
        }
        print "    <td><a href=\"$script\?mode=view_account\&username=$username\">$username</a></td>\n";
        print "    <td>$name</td>\n";
        print "    <td>$company</td>\n";
        print "    <td>$status</td>\n";
        print "  </tr>\n";

        $count = $count + 1;
        $color = ($color + 1) % 2;
      }
    }
    elsif ($query{'type'} eq 'unlinked') {
      my $linked = &is_linked("$username");
      if ($linked ne 'yes') {
        if ($color == 1) {
          print "  <tr class=\"listrow_color1\">\n";
        }
        else {
          print "  <tr class=\"listrow_color0\">\n";
        }
        print "    <td><a href=\"$script\?mode=view_account\&username=$username\">$username</a></td>\n";
        print "    <td>$name</td>\n";
        print "    <td>$company</td>\n";
        print "    <td>$status</td>\n";
        print "  </tr>\n";

        $count = $count + 1;
        $color = ($color + 1) % 2;
      }
    }
    else {
      if ($color == 1) {
        print "  <tr class=\"listrow_color1\">\n";
      }
      else {
        print "  <tr class=\"listrow_color0\">\n";
      }

      print "    <td><a href=\"$script\?mode=view_account\&username=$username\">$username</a></td>\n";
      print "    <td>$name</td>\n";
      print "    <td>$company</td>\n";
      print "    <td>$status</td>\n";
      print "  </tr>\n";

      $count = $count + 1;
      $color = ($color + 1) % 2;
    }
  }
  $sth->finish;

  if ($count == 0) {
    print "  <tr class=\"listrow_color1\">\n";
    print "    <td colspan=4 align=\"center\"><b>No Matching Accounts Available.</b></td>\n";
    print "  </tr>\n";
  }

  print "</tbody>\n";
  print "</table>\n";
  &html_tail();

  return;
}

sub search_accounts {
  ## search reseller's accounts
  my %query = @_;

  my %selected;
  $query{'sort_by'} =~ s/\W//g;
  if ($query{'sort_by'} !~ /^(username|name|company|email|phone|status)$/) {
    $query{'sort_by'} = "username";
  }
  $selected{"$query{'sort_by'}"} = "<font size=\"+1\">&raquo;</font>&nbsp;";

  &html_head(%query);

  if ($query{'type'} eq 'linked') {
    print "<p><b>This report lists the master accounts, which permit linking to other payment gateway accounts.</b>\n";
  }
  elsif ($query{'type'} eq 'unlinked') {
    print "<p><b>This report lists the master accounts, which are not linked to any other payment gateway accounts.</b>\n";
  }
  else {
    print "<p><b>This report lists all of your payment gateway accounts, which matches your search criteria.</b>\n";
  }
  #print "<br>&nbsp;\n";
  print "<br><b>Click on the Username of the account you wish to see additional details of.</b>\n";
  print "<br>&bull; To re-organize the list, click on the column's title you wish to sort by.\n";
  if ($ENV{'TECH'} ne '') {
    print "<br>&bull; The <font color=\"#ff0000\" size=\"+1\"><b>*</b></font> indicates username is currently linked to 1 or more payment gateway accounts.\n";
  }
  print "</p>\n";

  print "<div id=\"hideit\">\n";
  print "<h2>Please wait for the list to complete.  Depending upon many factors, this may take a while...</h2>\n";
  print "</div>\n";

  if ($query{'srch_exact'} eq 'yes') {
    print "<h3>The following accounts are exact matches to your search:</h3>\n";
  }
  else {
    print "<h3>The following accounts are partial matches to your search:</h3>\n";
  }

  if ($ENV{'TECH'} ne '') {
    print "<form action=\"$script\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"update_link\">\n";
    print "<input type=checkbox name=\"crosslink\" value=\"1\"> Cross Link Selected As Master Linking Accounts.\n";
  }

  print "<table class=\"tablesorter {sortlist: [[3,0]]}\" id=\"sortabletable\" width=760 border=1 cellpadding=0 cellspacing=0>\n";
  print "<thead>\n";
  print "  <tr>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Master</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Link</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Username</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Name</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Company</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Email</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Phone</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Status</th>\n";
  print "  </tr>\n";
  print "</thead>\n";
  print "<tbody>\n";

  my $count = 0;
  my $color = 1;

  my @placeholder = ();
  my $qstr .= "SELECT username, name, company, email, tel, status";
  $qstr .= " FROM customers";
  $qstr .= " WHERE (status=? OR status=?)";
  push (@placeholder, "debug", "live");

  if ($query{'srch_username'} =~ /\w/) {
    $qstr .= " AND LOWER(username) LIKE LOWER(?)";
    if ($query{'srch_exact'} eq 'yes') {
      push(@placeholder, "$query{'srch_username'}");
    }
    else {
      push(@placeholder, "\%$query{'srch_username'}\%");
    }
  }
  if ($query{'srch_email'} =~ /\w/) {
    $qstr .= " AND LOWER(email) LIKE LOWER(?)";
    if ($query{'srch_exact'} eq 'yes') {
      push(@placeholder, "$query{'srch_email'}");
    }
    else {
      push(@placeholder, "\%$query{'srch_email'}\%");
    }
  }
  if ($query{'srch_phone'} =~ /\w/) {
    $qstr .= " AND LOWER(tel) LIKE LOWER(?)";
    if ($query{'srch_exact'} eq 'yes') {
      push(@placeholder, "$query{'srch_phone'}");
    }
    else {
      push(@placeholder, "\%$query{'srch_phone'}\%");
    }
  }
  if ($query{'srch_name'} =~ /\w/) {
    $qstr .= " AND LOWER(name) LIKE lower(?)";
    if ($query{'srch_exact'} eq 'yes') {
    push(@placeholder, "$query{'srch_name'}");
    }
    else {
      push(@placeholder, "\%$query{'srch_name'}\%");
    }
  }
  if ($query{'srch_company'} =~ /\w/) {
    $qstr .= " AND LOWER(company) LIKE LOWER(?)";
    if ($query{'srch_exact'} eq 'yes') {
      push(@placeholder, "$query{'srch_company'}");
    }
    else {
      push(@placeholder, "\%$query{'srch_company'}\%");
    }
  }

  if ($ENV{'TECH'} !~ /^($allowed_staff)$/) {
    $qstr .= " AND reseller=?";
    push(@placeholder, $ENV{'REMOTE_USER'});
  }
  $qstr .= " ORDER BY $query{'sort_by'}";

  my $sth = $dbh_misc->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  while (my ($username, $name, $company, $email, $phone, $status) = $sth->fetchrow) {
    if ($query{'type'} eq 'linked') {
      my $linked = &is_linked("$username");
      if ($linked eq 'yes') {
        if ($color == 1) {
          print "  <tr class=\"listrow_color1\">\n";
        }
        else {
          print "  <tr class=\"listrow_color0\">\n";
        }
        if ($ENV{'TECH'} ne '') {
          print "    <td align=center><input type=radio name=\"username\" value=\"$username\"></td>\n";
          print "    <td align=left><input type=checkbox name=\"account_$count\" value=\"$username\" $selected{$username}> ";
          if ($linked eq 'yes') { print " <font color=\"#ff0000\" size=\"+1\"><b>*</b></font>"; }
          print "</td>\n";
        }
        print "    <td><a href=\"$script\?mode=view_account\&username=$username\">$username</a></td>\n";
        print "    <td>$name</td>\n";
        print "    <td>$company</td>\n";
        print "    <td>$email</td>\n";
        print "    <td>$phone</td>\n";
        print "    <td>$status</td>\n";
        print "  </tr>\n";

        $count = $count + 1;
        $color = ($color + 1) % 2;
      }
    }
    elsif ($query{'type'} eq 'unlinked') {
      my $linked = &is_linked("$username");
      if ($linked ne 'yes') {
        if ($color == 1) {
          print "  <tr class=\"listrow_color1\">\n";
        }
        else {
          print "  <tr class=\"listrow_color0\">\n";
        }
        if ($ENV{'TECH'} ne '') {
          print "    <td align=center><input type=radio name=\"username\" value=\"$username\"></td>\n";
          print "    <td align=left><input type=checkbox name=\"account_$count\" value=\"$username\" $selected{$username}> ";
          if ($linked eq 'yes') { print " <font color=\"#ff0000\" size=\"+1\"><b>*</b></font>"; }
          print "</td>\n";
        }
        print "    <td><a href=\"$script\?mode=view_account\&username=$username\">$username</a></td>\n";
        print "    <td>$name</td>\n";
        print "    <td>$company</td>\n";
        print "    <td>$email</td>\n";
        print "    <td>$phone</td>\n";
        print "    <td>$status</td>\n";
        print "  </tr>\n";

        $count = $count + 1;
        $color = ($color + 1) % 2;
      }
    }
    else {
      my $linked = &is_linked("$username");
      if ($color == 1) {
        print "  <tr class=\"listrow_color1\">\n";
      }
      else {
        print "  <tr class=\"listrow_color0\">\n";
      }
      if ($ENV{'TECH'} ne '') {
        print "    <td align=center><input type=radio name=\"username\" value=\"$username\"></td>\n";
        print "    <td align=left><input type=checkbox name=\"account_$count\" value=\"$username\" $selected{$username}> ";
        if ($linked eq 'yes') { print " <font color=\"#ff0000\" size=\"+1\"><b>*</b></font>"; }
        print "</td>\n";
      }
      print "    <td><a href=\"$script\?mode=view_account\&username=$username\">$username</a></td>\n";
      print "    <td>$name</td>\n";
      print "    <td>$company</td>\n";
      print "    <td>$email</td>\n";
      print "    <td>$phone</td>\n";
      print "    <td>$status</td>\n";
      print "  </tr>\n";

      $count = $count + 1;
      $color = ($color + 1) % 2;
    }
  }
  $sth->finish;

  if ($count == 0) {
    print "  <tr class=\"listrow_color1\">\n";
    print "    <td colspan=4 align=center><b>No Matching Accounts Available.</b></td>\n";
    print "  </tr>\n";
  }

  print "</tbody>\n";
  print "</table>\n";

  if ($ENV{'TECH'} ne '') {
    print "<br><input type=submit class=\"button\" value=\"Link Accounts\">\n";
    print "</form>\n";
  }

  &html_tail();

  return;
}

sub get_features {
  my ($username) = @_;

  my %feature;

  my @placeholder = ();
  my $qstr = "SELECT features";
  $qstr .= " FROM customers";
  $qstr .= " WHERE username=?";
  push(@placeholder, $username);
  if ($ENV{'TECH'} !~ /^($allowed_staff)$/) {
    $qstr .= " AND reseller=?";
    push(@placeholder, $ENV{'REMOTE_USER'});
  }

  my $sth = $dbh_misc->prepare(qq{ $qstr }) or die "Can't prepare: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  my ($features) = $sth->fetchrow;
  $sth->finish;

  if ($features ne '') {
    my @array = split(/\,/,$features);
    foreach my $entry (@array) {
      my ($name, $value) = split(/\=/,$entry, 2);
      $feature{"$name"} = $value;
    }
  }

  return %feature;
}

sub view_account {
  ## view a single reseller's account
  my %query = @_;

  if ($query{'username'} !~ /\w/) {
    &show_error("Account Username Required");
  }

  # only let reseller view accounts which belong to them
  my $is_ok = &is_reseller_account("$query{'username'}");
  if ($is_ok ne 'yes') {
    &show_error("Account Does Not Exist Or Does Not Belong To Reseller");
  }

  &html_head(%query);

  print "<table width=760 border=1 cellpadding=0 cellspacing=0>\n";
  print "  <tr class=\"listsection_title\">\n";
  print "    <td>Username</td>\n";
  print "    <td>Name</td>\n";
  print "    <td>Company</td>\n";
  print "    <td>Status</td>\n";
  print "    <td>&nbsp;</td>\n";
  print "  </tr>\n";

  my @placeholder = ();
  my $qstr = "SELECT username, name, company, status";
  $qstr .= " FROM customers";
  $qstr .= " WHERE username=?";
  push (@placeholder, $query{'username'});
  if ($ENV{'TECH'} !~ /^($allowed_staff)$/) {
    $qstr .= " AND reseller=?";
    push (@placeholder, $ENV{'REMOTE_USER'});
  }

  my $sth = $dbh_misc->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  my ($username1, $name1, $company1, $status1) = $sth->fetchrow;
  $sth->finish;

  if ($username1 ne '') {
    print "  <tr class=\"listrow_color2\">\n";
    print "    <td>$username1</td>\n";
    print "    <td>$name1</td>\n";
    print "    <td>$company1</td>\n";
    print "    <td>$status1</td>\n";
    print "    <td>&nbsp;</td>\n";
    print "  </tr>\n";

    my $cnt_linked = 0;

    my %features = &get_features("$username1");
    if ($features{'linked_accts'} ne '') {
      my $srchstr = "SELECT username, name, company, status";
      $srchstr .= " FROM customers";

      my @placeholder;
      my $op = "WHERE";

      #$srchstr .= " $op reseller=?";
      #push(@placeholder, $ENV{'REMOTE_USER'});

      my $tmp = "";
      my @linked = split(/\|/, $features{'linked_accts'});
      for (my $i = 0; $i <= $#linked; $i++) {
        $linked[$i] =~ s/[^a-zA-Z0-9]//g; # remove non-allowed characters
        $linked[$i] = lc("$linked[$i]"); # force username lower case
        if (($linked[$i] =~ /\w/) && ($linked[$i] ne "$username1")) {
          if ($tmp ne '') {
            $tmp .= ",";
          }
          $tmp .= "\?";
          push(@placeholder, "$linked[$i]");
        }
      }
      if ($tmp ne '') {
        $srchstr .= " $op username IN ($tmp)";
        $op = "OR";
      }
      $srchstr .= " ORDER BY username";

      my $color = 1;

      my $sth2 = $dbh_misc->prepare(qq{ $srchstr }) or die "Can't do: $DBI::errstr";
      $sth2->execute(@placeholder) or die "Can't execute: $DBI::errstr";
      while (my ($username, $name, $company, $status) = $sth2->fetchrow) {
        if ($color == 1) {
          print "  <tr class=\"listrow_color1\">\n";
        }
        else {
          print "  <tr class=\"listrow_color0\">\n";
        }
        print "    <td><a href=\"$script\?mode=view_account\&username=$username\">$username</a></td>\n";
        print "    <td>$name</td>\n";
        print "    <td>$company</td>\n";
        print "    <td>$status</td>\n";
        print "    <td><a href=\"$script\?mode=remove_one\&username=$username1\&account_0\=$username\">[unlink]</a></td>\n";
        print "  </tr>\n";

        $color = ($color + 1) % 2;
        $cnt_linked = $cnt_linked + 1;
      }
      $sth2->finish;
    }
    else {
      print "  <tr class=\"listrow_color1\">\n";
      print "    <td colspan=4 align=center><i>Not Setup As Master Linking Account.</i></td>\n";
      print "  </tr>\n";
    }

    print "  <tr class=\"listrow_color1\">\n";
    print "    <td colspan=4 align=center><form action=\"$script\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"edit_link\">\n";
    print "<input type=hidden name=\"username\" value=\"$username1\">\n";
    print "<input type=submit class=\"button\" value=\"Edit Account Linking\">\n";
    print "</td></form>\n";
    print "  </tr>\n";

    if ($cnt_linked >= 1) {
      print "  <tr class=\"listrow_color1\">\n";
      print "    <td colspan=4 align=center><form action=\"$script\" method=post>\n";
      print "<input type=hidden name=\"mode\" value=\"remove_link\">\n";
      print "<input type=hidden name=\"username\" value=\"$username1\">\n";
      print "<input type=submit class=\"button\" value=\"Unlink All Accounts\">\n";
      print "</td></form>\n";
      print "  </tr>\n";

    if ($ENV{'TECH'} =~ /^($allowed_staff)$/) {
        print "    <td colspan=5 align=right><hr width=\"100\%\"><form action=\"$script\" method=post>\n";
        print "<input type=hidden name=\"mode\" value=\"global_remove\">\n";
        print "<input type=hidden name=\"username\" value=\"$username1\">\n";
        print "<input type=submit class=\"button\" value=\"Global Unlink Account\">\n";
        print "</td></form>\n";
        print "  </tr>\n";
      }
    }

  }
  else {
    print "  <tr class=\"listrow_color1\">\n";
    print "    <td colspan=4 align=center><b>No Matching Account Available.</b></td>\n";
    print "  </tr>\n";
  }
  print "</table>\n";
  &html_tail();

  return;
}

sub is_linked {
  ## checks to see if given username is linked to other accounts
  my ($username) = @_;

  if ($username !~ /\w/) {
    &show_error("Account Username Required");
  }

  # get feature settings
  my %features = &get_features("$username");

  # this code simply gives back a 'yes' or 'no' answer
  if ($features{'linked_accts'} ne '') {
    return "yes";
  }
  else {
    return "no";
  }
}

sub quick_link {
  my %query = @_;

  if ($query{'username'} !~ /\w/) {
    &show_error("Account Username Required");
  }

  # only let reseller update links to accounts which belong to them
  my $is_ok = &is_reseller_account("$query{'username'}");
  if ($is_ok ne 'yes') {
    &show_error("Account Does Not Exist Or Does Not Belong To Reseller");
  }

  &html_head(%query);

  print "<p><b>Quick linking is an avdvanced to allow you to expressly link accounts together by username only.</b></p>\n";

  print "<p><i>If you are unsure or don't know the exact usernames of the accounts you want to link together, <b>DO NOT GUESS THEIR USERNAME</b>.\n";
  print "<br>Instead, please use our <a href=\"$script?mode=edit_link\&username=$query{'username'}\"><b>Edit Account</b></a> feature; which offers more account information.</i></p>\n";

  print "<div id=\"hideit\">\n";
  print "<h2>Please wait for the list to complete.  Depending upon many factors, this may take a while...</h2>\n";
  print "</div>\n";

  print "<div align=right><form name=\"addUserForm\" onSubmit=\"return false;\">";
  print "Username: ";
  if ($ENV{'TECH'} =~ /^($allowed_staff)$/) {
    print "<input type=text id=\"autocomplete\" name=\"username\" value=\"\" size=20 maxlength=250>";
  }
  else {
    print "<input type=text id=\"autocomplete\" name=\"username\" value=\"\" size=20 maxlength=20>";

  }
  print " <input type=button class=\"button\" value=\"Add\" onClick=\"appendUser(document.addUserForm.username.value);document.addUserForm.username.value='';\"> </form></div>\n";

  print "<form action=\"$script\" method=post>\n";
  print "<input type=hidden name=\"mode\" value=\"update_link\">\n";
  print "<input type=hidden name=\"username\" value=\"$query{'username'}\">\n";
  print "<input type=checkbox name=\"crosslink\" value=\"1\"> Cross Link Selected As Master Linking Accounts.\n";

  print "<table width=760 border=1 cellpadding=0 cellspacing=0>\n";
  print "  <tr class=\"listsection_title\">\n";
  print "    <td align=center>Link</td>\n";
  print "    <td>Username</td>\n";
  print "    <td>Name</td>\n";
  print "    <td>Company</td>\n";
  print "    <td>Status</td>\n";
  print "  </tr>\n";

  my @placeholder = ();
  my $qstr = "SELECT username, name, company, status";
  $qstr .= " FROM customers";
  $qstr .= " WHERE username=?";
  push(@placeholder, $query{'username'});
  if ($ENV{'TECH'} !~ /^($allowed_staff)$/) {
    $qstr .= " AND reseller=?";
    push(@placeholder, $ENV{'REMOTE_USER'});
  }

  my $sth = $dbh_misc->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  my ($username1, $name1, $company1, $status1) = $sth->fetchrow;
  $sth->finish;

  # list master account
  print "  <tr class=\"listrow_color2\">\n";
  print "    <td align=center><i>MASTER</i></td>\n";
  print "    <td><b>$username1</b></td>\n";
  print "    <td><b>$name1</b></td>\n";
  print "    <td><b>$company1</b></td>\n";
  print "    <td><b>$status1</b></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<span id=\"acctlist\"></span>\n";

  my %features = &get_features("$username1");
  if ($features{'linked_accts'} ne '') {
    my @linked = split(/\|/, $features{'linked_accts'});
    for (my $i = 0; $i <= $#linked; $i++) {
      $linked[$i] =~ s/[^a-zA-Z0-9]//g; # remove non-allowed characters
      if (($linked[$i] =~ /\w/) && ($linked[$i] ne "$query{'username'}") && ($linked[$i] ne 'MASTER')) {

        print "<script type=\"text/javascript\">\n";
        print "  appendUser(\"$linked[$i]\");\n";
        print "</script>\n";
      }
    }
  }

  print "<br><input type=submit class=\"button\" value=\"Link Accounts\">\n";
  print "</form>\n";

  &html_tail();
  return;
}

sub edit_link {
  my %query = @_;

  if ($query{'username'} !~ /\w/) {
    &show_error("Account Username Required");
  }

  # only let reseller update links to accounts which belong to them
  my $is_ok = &is_reseller_account("$query{'username'}");
  if ($is_ok ne 'yes') {
    &show_error("Account Does Not Exist Or Does Not Belong To Reseller");
  }

  &html_head(%query);

  print "<p><b>Select which usernames you would like to link to this account.</b></p>\n";

  print "<div id=\"hideit\">\n";
  print "<h2>Please wait for the list to complete.  Depending upon many factors, this may take a while...</h2>\n";
  print "</div>\n";

  print "<form action=\"$script\" method=post>\n";
  print "<input type=hidden name=\"mode\" value=\"update_link\">\n";
  print "<input type=hidden name=\"username\" value=\"$query{'username'}\">\n";
  print "<input type=checkbox name=\"crosslink\" value=\"1\"> Cross Link Selected As Master Linking Accounts.\n";

  print "<table class=\"tablesorter {sortlist: [[3,0]]}\" id=\"sortabletable\" width=760 border=1 cellpadding=0 cellspacing=0>\n";
  print "<thead>\n";
  print "  <tr>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\" align=center>Link</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Username</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Name</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Company</th>\n";
  print "    <th class=\"{sorter: 'text'}\" id=\"zebrasort\">Status</th>\n";
  print "  </tr>\n";

  my @placeholder = ();
  my $qstr = "SELECT username, name, company, status";
  $qstr .= " FROM customers";
  $qstr .= " WHERE username=?";
  push(@placeholder, $query{'username'});
  if ($ENV{'TECH'} !~ /^($allowed_staff)$/) {
    $qstr .= " AND reseller=?";
    push(@placeholder, $ENV{'REMOTE_USER'});
  }

  my $sth = $dbh_misc->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  my ($username1, $name1, $company1, $status1) = $sth->fetchrow;
  $sth->finish;

  # list master account
  print "  <tr class=\"listrow_color2\">\n";
  print "    <td align=center><i>MASTER</i></td>\n";
  print "    <td><b>$username1</b></td>\n";
  print "    <td><b>$name1</b></td>\n";
  print "    <td><b>$company1</b></td>\n";
  print "    <td><b>$status1</b></td>\n";
  print "  </tr>\n";
  print "</thead>\n";
  print "<tbody>\n";

  my %selected;
  my %features = &get_features("$username1");
  if ($features{'linked_accts'} ne '') {
    my @linked = split(/\|/, $features{'linked_accts'});
    for (my $i = 0; $i <= $#linked; $i++) {
      $linked[$i] =~ s/[^a-zA-Z0-9]//g; # remove non-allowed characters
      $linked[$i] = lc("$linked[$i]"); # force username lower case
      if (($linked[$i] =~ /\w/) && ($linked[$i] ne "$query{'username'}")) {
        $selected{"$linked[$i]"} = "checked";
      }
    }
  }

  my $count = 0;
  my $color = 1;

  my @placeholder2 = ();
  my $qstr2 = "SELECT username, name, company, status";
  $qstr2 .= " FROM customers";
  $qstr2 .= " WHERE status IN (?,?)";
  push (@placeholder2, "debug", "live");
  if ($ENV{'TECH'} !~ /^($allowed_staff)$/) {
    $qstr2 .= " AND reseller=?";
    push(@placeholder2, $ENV{'REMOTE_USER'});
  }
  $qstr2 .= " ORDER BY username";

  my $sth2 = $dbh_misc->prepare(qq{ $qstr2 }) or die "Can't do: $DBI::errstr";
  $sth2->execute(@placeholder2) or die "Can't execute: $DBI::errstr";
  while (my ($username, $name, $company, $status) = $sth2->fetchrow) {
    if ($username ne "$query{'username'}") {
      if ($color == 1) {
        print "  <tr class=\"listrow_color1\">\n";
      }
      else {
        print "  <tr class=\"listrow_color0\">\n";
      }
      print "    <td align=center><input type=checkbox name=\"account_$count\" value=\"$username\" $selected{$username}></td>\n";
      print "    <td>$username</td>\n";
      print "    <td>$name</td>\n";
      print "    <td>$company</td>\n";
      print "    <td>$status</td>\n";
      print "  </tr>\n";

      $count = $count + 1;
      $color = ($color + 1) % 2;
    }
  }
  $sth2->finish;

  if ($count == 0) {
    print "  <tr class=\"listrow_color1\">\n";
    print "    <td colspan=4 align=center><b>No Accounts Available.</b></td>\n";
    print "  </tr>\n";
  }

  print "</tbody>\n";
  print "</table>\n";

  print "<br><input type=submit class=\"button\" value=\"Link Accounts\">\n";
  print "</form>\n";

  &html_tail();
  return;
}

sub update_link {
  my %query = @_;

  if ($query{'username'} !~ /\w/) {
    &show_error("Account Username Required");
  }

  # only let reseller update links to accounts which belong to them
  my $is_ok = &is_reseller_account($query{'username'});
  if ($is_ok ne 'yes') {
    &show_error("Account Does Not Exist Or Does Not Belong To Reseller");
  }

  # get the features list from the database
  my %features = &get_features("$query{'username'}");

  if ($query{'mode'} eq 'update_link') {
    # write the change request to the debug log file
    my %log_data = %query;
    $log_data{'LINKED_ACCTS'} = "$features{'linked_accts'}";
    &log_changes(%log_data);
  }

  # build exempt username list (so we can preserve non-reseller linked accounts, if necessary)
  my %exempt_list;
  my @linked = split(/\|/, $features{'linked_accts'});
  for (my $i = 0; $i <= $#linked; $i++) {
    $linked[$i] =~ s/[^a-zA-Z0-9]//g; # remove non-allowed characters
    if ($linked[$i] ne 'MASTER') {
      $linked[$i] = lc("$linked[$i]"); # force username lower case
    }
    if (($linked[$i] =~ /\w/) && ($linked[$i] ne "$query{'username'}")) {
      $exempt_list{"$linked[$i]"} = "exempt";
    }
  }

  # now rebuild the linked account list
  $features{'linked_accts'} = ""; # reset linked account value

  if ($query{'crosslink'} != 1) {
    $features{'linked_accts'} = "MASTER|$query{'username'}"; # for master only linked account setups
  }

  my $accounts = &count_accounts();
  my $cnt_linked = 0;
  for (my $i = 0; $i <= $accounts; $i++) {
    if ($query{"account_$i"} =~ /\w/) {
      # clean up given username
      $query{"account_$i"} = lc($query{"account_$i"});

      if ($query{"account_$i"} !~ /\w/) {
        next;
      }

      # validate its a reseller's accout
      my $is_ok = &is_reseller_account("$query{\"account_$i\"}");
      if (($is_ok eq 'yes') || ($exempt_list{"$query{\"account_$i\"}"} eq 'exempt')) {
        # if resellers account, permit linking of the account.
        if ($features{'linked_accts'} =~ /\w/) {
          $features{'linked_accts'} .= "\|";
        }
        $features{'linked_accts'} .= $query{"account_$i"};
        $cnt_linked = $cnt_linked + 1;
      }
    }
  }

  # perform final validation check, to ensure the master account will be linked to 1 or more accounts
  # also adjust for situations where this will be a master only setup (not cross linked situation)
  if (($cnt_linked >= 1) && ($features{'linked_accts'} !~ /^(MASTER\|)/)) {
    $features{'linked_accts'} .= "\|" . $query{'username'};
  }
  else {
    &remove_link(%query);
    #&show_error("No Accounts Defined");
  }

  # preserve for later usage, when updating cross linked accounts
  my $new_linked_accts = $features{'linked_accts'};

  # reset features list, so we can create new one from the features hash
  my $features_new = "";

  # create new features list from the updated features hash
  foreach my $key (keys %features) {
    if ($features{$key} ne '') {
      $features_new .= "$key=$features{$key},";
    }
  }

  #$features_new =~ s/^\,+//g; # strip leading commas
  #$features_new =~ s/\,+$//g; # strip tailing commas

  # update the features list in the database
  &update_features("$query{'username'}", "$features_new");

  # cross link selected accounts as master linked accounts, if necesary
  if ($query{'crosslink'} == 1) {
    for (my $i = 0; $i <= $accounts; $i++) {
      if ($query{"account_$i"} =~ /\w/) {
        # validate its a reseller's accout
        my $is_ok = &is_reseller_account("$query{\"account_$i\"}");

        if ($is_ok eq 'yes') {
          # get features list from crosslinked account
          my %la_features = &get_features("$query{\"account_$i\"}");

          # merge in new crosslinked account listing
          $la_features{'linked_accts'} = $new_linked_accts;

          # reset features list, so we can create new one from the features hash
          my $la_features_new = "";

          # create new features list from the updated features hash
          foreach my $key (keys %la_features) {
            if ($la_features{$key} ne '') {
              $la_features_new .= "$key=$la_features{$key},";
            }
          }

          #$la_features_new =~ s/^\,+//g; # strip leading commas
          #$la_features_new =~ s/\,+$//g; # strip tailing commas

          # update the features list in the database for the crosslinked account
          &update_features("$query{\"account_$i\"}", "$la_features_new");
        }
      }
    }
  }

  return;
}

sub is_reseller_account {
  # checks to see if username belongs to the given reseller
  my ($username) = @_;

  if ($username !~ /\w/) {
    return "no";
  }

  my @placeholder = ();
  my $qstr = "SELECT username";
  $qstr .= " FROM customers";
  $qstr .= " WHERE username=?";
  push(@placeholder, $username);
  if ($ENV{'TECH'} !~ /^($allowed_staff)$/) {
    $qstr .= " AND reseller=?";
    push(@placeholder, $ENV{'REMOTE_USER'});
  }

  my $sth = $dbh_misc->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  my ($test) = $sth->fetchrow;
  $sth->finish;

  # this code simply gives back a 'yes' or 'no' answer
  if ($test eq $username) {
    return "yes";
  }
  else {
    return "no";
  }
}

sub count_accounts {
  # count number of accounts which belong to the reseller

  my @placeholder = ();
  my $qstr = "SELECT COUNT(username)";
  $qstr .= " FROM customers";
  $qstr .= " WHERE status IN (?,?)";
  push (@placeholder, "debug", "live");
  if ($ENV{'TECH'} !~ /^($allowed_staff)$/) {
    $qstr .= " AND reseller=?";
    push(@placeholder, $ENV{'REMOTE_USER'});
  }

  my $sth = $dbh_misc->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  my ($count) = $sth->fetchrow;
  $sth->finish;

  return $count;
}

sub remove_link {
  # unlink all accounts from the master username
  my %query = @_;

  if ($query{'username'} !~ /\w/) {
    &show_error("Account Username Required");
  }

  # only let reseller view accounts which belong to them
  my $is_ok = &is_reseller_account("$query{'username'}");
  if ($is_ok ne 'yes') {
    &show_error("Account Does Not Exist Or Does Not Belong To Reseller");
  }

  # get current features list
  my %features = &get_features("$query{'username'}");

  if ($query{'mode'} eq 'remove_link') {
    # write the change request to the debug log file
    my %log_data = %query;
    $log_data{'LINKED_ACCTS'} = "$features{'linked_accts'}";
    &log_changes(%log_data);
  }

  # reset features list, so we can create new one from the features hash
  my $features_new = "";

  # create new features list from the updated features hash
  foreach my $key (keys %features) {
    if (($features{$key} ne '') && ($key ne 'linked_accts')) {
      $features_new .= "$key=$features{$key},";
    }
  }

  #$features_new =~ s/^\,+//g; # strip leading commas
  #$features_new =~ s/\,+$//g; # strip tailing commas

  # update the features list in the database
  &update_features("$query{'username'}", "$features_new");

  return;
}

sub remove_one {
  # unlinks single account from the master username
  my %query = @_;

  if ($query{'username'} !~ /\w/) {
    &show_error("Account Username Required");
  }

  if ($query{'account_0'} !~ /\w/) {
    &show_error("Uncouple Account Username Required");
  }

  # only let reseller view accounts which belong to them
  my $is_ok = &is_reseller_account("$query{'username'}");
  if ($is_ok ne 'yes') {
    &show_error("Account Does Not Exist Or Does Not Belong To Reseller");
  }

  # get current features list
  my %features = &get_features("$query{'username'}");

  if ($query{'mode'} eq 'remove_one') {
    # write the change request to the debug log file
    my %log_data = %query;
    $log_data{'LINKED_ACCTS'} = "$features{'linked_accts'}";
    &log_changes(%log_data);
  }

  if ($query{'account_0'} =~ /^($features{'linked_accts'})$/) {
    # rebuilt accounts linked list, without given username
    my $linked = "";
    my @temp = split(/\|/, $features{'linked_accts'});
    for (my $i = 0; $i <= $#temp; $i++) {
      $temp[$i] =~ s/[^a-zA-Z0-9]//g; # remove non-allowed characters
      if (($temp[$i] =~ /\w/) && ($temp[$i] ne "$query{'account_0'}")) {
        if ($linked ne '') {
          $linked .= "\|";
        }
        $linked .= $temp[$i];
      }
    }
    $features{'linked_accts'} = $linked;
  }

  # reset features list, so we can create new one from the features hash
  my $features_new = "";

  # create new features list from the updated features hash
  foreach my $key (keys %features) {
    if ($features{$key} ne '') {
      $features_new .= "$key=$features{$key},";
    }
  }

  #$features_new =~ s/^\,+//g; # strip leading commas
  #$features_new =~ s/\,+$//g; # strip tailing commas

  # update the features list in the database
  &update_features("$query{'username'}", "$features_new");

  return;
}

sub global_remove_link {
  # global unlink username from all accounts
  my %query = @_;

  if ($query{'username'} !~ /\w/) {
    &show_error("Account Username Required");
  }

  if ($ENV{'TECH'} !~ /^($allowed_staff)$/) {
    &show_error("Access Denied: Approved Gateway Staff Only.");
  }

  # get current features list
  my %features = &get_features("$query{'username'}");

  # write the change request to the debug log file
  my %log_data = %query;
  $log_data{'LINKED_ACCTS'} = "$features{'linked_accts'}";
  &log_changes(%log_data);

  # remove username linking to other accounts
  &remove_link(%query);

  # remove username from all other accounts
  my @placeholder = ();
  my $qstr = "SELECT username, features";
  $qstr .= " FROM customers";
  $qstr .= " WHERE features LIKE ?";
  push(@placeholder, "\%linked_accts\%");
  $qstr .= " AND features LIKE ?";
  push(@placeholder, "\%$query{'username'}\%");
  $qstr .= " ORDER BY username";

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  while (my ($db_username, $db_features) = $sth->fetchrow) {

    # parse account's feature settings
    my %features = ();
    my @array = split(/\,/,$db_features);
    foreach my $entry (@array) {
      my ($name, $value) = split(/\=/,$entry, 2);
      $features{"$name"} = $value;
    }

    # remove username from the given accounts linked list, if necessary
    if ($query{'username'} =~ /^($features{'linked_accts'})$/) {
      # rebuilt accounts linked list, without given username
      my $linked = "";
      my @temp = split(/\|/, $features{'linked_accts'});
      for (my $i = 0; $i <= $#temp; $i++) {
        $temp[$i] =~ s/[^a-zA-Z0-9]//g; # remove non-allowed characters
        if (($temp[$i] =~ /\w/) && ($temp[$i] ne "$query{'username'}")) {
          if ($linked ne '') {
            $linked .= "\|";
          }
          $linked .= $temp[$i];
        }
      }
      $features{'linked_accts'} = $linked;

      # reset features list, so we can create new one from the features hash
      my $features_new = "";

      # create new features list from the updated features hash
      foreach my $key (keys %features) {
        if ($features{$key} ne '') {
          $features_new .= "$key=$features{$key},";
        }
      }

      #$features_new =~ s/^\,+//g; # strip leading commas
      #$features_new =~ s/\,+$//g; # strip tailing commas

      # update the features list in the database
      &update_features("$db_username", "$features_new");
    }
  }
  $sth->finish;
  $dbh->disconnect;

  return;
}

sub log_changes {
  my %query = @_;

  my $time = gmtime(time);
  open(DEBUG,'>>',"/home/p/pay1/database/debug/linked_accts.txt");
  print DEBUG "TIME:$time, RA:$ENV{'REMOTE_ADDR'}, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, ";
  print DEBUG "PORT:$ENV{'SERVER_PORT'}, PID:$$, RM:$ENV{'REQUEST_METHOD'}, LINKED_ACCTS:$query{'LINKED_ACCTS'}";
  foreach my $key (sort keys %query) {
    if ($key ne 'LINKED_ACCTS') {
      print DEBUG ", $key:$query{$key}";
    }
  }
  print DEBUG "\n";
  close(DEBUG);

  return;
}

sub update_features {
  # update the features list in the database
  my ($username, $features_new) = @_;

  my $sth = $dbh_misc->prepare(q{
      UPDATE customers
      SET features=?
      WHERE username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$features_new", "$username") or die "Can't execute: $DBI::errstr";
  $sth->finish;

  return;
}
