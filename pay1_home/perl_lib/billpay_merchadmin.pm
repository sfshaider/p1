package billpay_merchadmin;

require 5.001;

use pnp_environment;
use miscutils;
use CGI;
use sysutils;
use PlugNPay::InputValidator;
use PlugNPay::Email;
use PlugNPay::Features;
use constants qw(%countries %USstates %USterritories %CNprovinces %USCNprov %timezones);
use strict;

# Purpose: Merchant side of Billing Presement service
#          This lib is for all merchant billpay admin area menus, interfaces, response screens & related functions
#          For all customer billpay stuff, use the other billpay_xxxxxx.pm libs.

sub new {
  my $type = shift;
  %billpay_merchadmin::query = @_;

  # filter query data, as we don't know where it came from (i.e. from a upload file, API request or POST from BillPay admin area)
  my $iv = new PlugNPay::InputValidator();
  $iv->changeContext('billpay_merchadmin');
  %billpay_merchadmin::query = $iv->filterHash(%billpay_merchadmin::query);

  ## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
  if ($ENV{'HTTP_X_FORWARDED_FOR'} ne '') {
    $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
  }

  # initialize database handle here:
  $billpay_merchadmin::dbh = &miscutils::dbhconnect('billpres');

  # initialize params here:
  %billpay_merchadmin::count = ();

  $billpay_merchadmin::merchant = ''; 
  if ($ENV{'REMOTE_USER'} =~ /\w/) {
    $billpay_merchadmin::merchant = $ENV{'REMOTE_USER'};
  }
  elsif (($billpay_merchadmin::query{'publisher-name'} =~ /\w/) || ($billpay_merchadmin::query{'publisher_name'} =~ /\w/)) {
    if ($billpay_merchadmin::query{'publisher-name'} =~ /\w/) {
      $billpay_merchadmin::merchant = $billpay_merchadmin::query{'publisher-name'};
    }
    elsif ($billpay_merchadmin::query{'publisher_name'} =~ /\w/) {
      $billpay_merchadmin::merchant = $billpay_merchadmin::query{'publisher_name'};
    }
  }

  my $db_features;

  # get merchant's company name
  my $dbh_misc = &miscutils::dbhconnect('pnpmisc');
  my $sth2 = $dbh_misc->prepare(q{
      SELECT company
      FROM customers
      WHERE username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth2->execute($billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
  ($billpay_merchadmin::query{'merch_company'}) = $sth2->fetchrow;
  $sth2->finish;
  $dbh_misc->disconnect;

  my $accountFeatures = new PlugNPay::Features("$billpay_merchadmin::merchant",'general');
  $db_features = $accountFeatures->getFeatureString();

  # parse feature list into hash
  %billpay_merchadmin::feature_list = ();
  if ($db_features =~ /(.*)=(.*)/) {
    my @array = split(/\,/,$db_features);
    foreach my $entry (@array) {
      my ($name, $value) = split(/\=/, $entry);
      $billpay_merchadmin::feature_list{"$name"} = "$value";
    }
  }

  # grab default email options
  $billpay_merchadmin::query{'merch_email_cust'} = $billpay_merchadmin::feature_list{'billpay_email_cust'};   # default email customer setting
  $billpay_merchadmin::query{'merch_express_pay'} = $billpay_merchadmin::feature_list{'billpay_express_pay'}; # default express pay setting
  $billpay_merchadmin::query{'merch_overwrite'} = $billpay_merchadmin::feature_list{'billpay_overwrite'};     # default overwrite setting

  # grab Email Management's publisher-email address
  if ($billpay_merchadmin::feature_list{'pubemail'} ne '') {
    $billpay_merchadmin::query{'merch_pubemail'} = lc($billpay_merchadmin::feature_list{'pubemail'});
  }

  return [], $type;
}

sub html_head {
  my $type = shift;
  my ($title) = @_;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Billing Presentment</title>\n";
  print "<link href=\"/css/style_billpay_merch.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<meta http-equiv=\"CACHE-CONTROL\" content=\"NO-CACHE\">\n";
  print "<meta http-equiv=\"PRAGMA\" content=\"NO-CACHE\">\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<script type=\"text/javascript\" src=\"/css/vt.js\"></script>\n";
  #print "<!-- MU: $billpay_merchadmin::merchant, LU: $ENV{'REMOTE_USER'}, SL: $ENV{'SEC_LEVEL'}, MO: $billpay_merchadmin::query{'mode'}-->\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=3 align=left>";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "<img src=\"/images/global_header_gfx.gif\" width=760 alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=44 border=0>";
  }
  else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
  }
  print "</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=3 align=left><img src=\"/images/header_bottom_bar_gfx.gif\" width=760 height=14></td>\n";
  print "  </tr>\n";

  if ($ENV{'SEC_LEVEL'} <= 4) {
    if ($billpay_merchadmin::query{'mode'} eq '') {
      my $total_invoices = &count_total_invoices();
      my $open_invoices = &count_open_invoices();
      my $closed_invoices = &count_closed_invoices();
      my $hidden_invoices = &count_hidden_invoices();
      my $merged_invoices = &count_merged_invoices();
      my $paid_invoices = &count_paid_invoices();
      my $expired_invoices = &count_expired_invoices();
  
      print "  <tr bgcolor=\"#f4f4f4\">\n";
      print "    <td colspan=3><b>Invoice Database - Total Invoices $total_invoices \[Open: $open_invoices, Closed: $closed_invoices, Hidden: $hidden_invoices, Merged: $merged_invoices, Paid: $paid_invoices, Expired: $expired_invoices\]</b></td>\n";
      print "  </tr>\n";
    }
    elsif ($billpay_merchadmin::query{'mode'} eq 'manage_clients_menu') {
      my $total_clients = &count_total_clients();
 
      print "  <tr bgcolor=\"#f4f4f4\">\n";
      print "    <td colspan=3><b>Contact Database - Total Contacts: $total_clients</b></td>\n";
      print "  </tr>\n";
    }
  }
  print "  <tr>\n";
  print "    <td colspan=3 valign=top class=\"larger\"><h1><b><a href=\"$ENV{'SCRIPT_NAME'}\">Billing Presentment Administration</a>";
  if ($title ne '') {
    print " / $title";
  }
  print "</b> - $billpay_merchadmin::query{'merch_company'}</h1></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0>\n";
  print "  <tr>\n";
  print "    <td valign=top align=left>";

  return;
}

sub html_tail {

  my @now = gmtime(time);
  my $copy_year = $now[5]+1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=left><p><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></p></td>\n";
  print "    <td align=right><p>\&copy; $copy_year, ";
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

sub sort_hash {
  my $x = shift;
  my %array=%$x;
  sort { $array{$a} cmp $array{$b}; } keys %array;
}

sub count_total_invoices {
  # counts total number of invoices in invoice database

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT COUNT(invoice_no)
      FROM bills2
      WHERE merchant=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($billpay_merchadmin::merchant) or die "Can't execute: $DBI::errstr";
  my ($count) = $sth->fetchrow;
  $sth->finish;

  return $count;
}

sub count_open_invoices {
  # counts number of open invoices in invoice database

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT COUNT(invoice_no)
      FROM bills2
      WHERE merchant=?
      AND expire_date>?
      AND (status IS NULL or status='' OR status='open')
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($billpay_merchadmin::merchant, $today) or die "Can't execute: $DBI::errstr";
  my ($count) = $sth->fetchrow;
  $sth->finish;

  return $count;
}

sub count_closed_invoices {
  # counts number of closed invoices in invoice database

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT COUNT(invoice_no)
      FROM bills2
      WHERE merchant=?
      AND status='closed'
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($billpay_merchadmin::merchant) or die "Can't execute: $DBI::errstr";
  my ($count) = $sth->fetchrow;
  $sth->finish;

  return $count;
}

sub count_merged_invoices {
  # counts number of merged invoices in invoice database

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT COUNT(invoice_no)
      FROM bills2
      WHERE merchant=?
      AND status='merged'
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($billpay_merchadmin::merchant) or die "Can't execute: $DBI::errstr";
  my ($count) = $sth->fetchrow;
  $sth->finish;

  return $count;
}

sub count_paid_invoices {
  # counts number of paid invoices in invoice database

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT count(invoice_no)
      FROM bills2
      WHERE merchant=?
      AND status='paid'
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($billpay_merchadmin::merchant) or die "Can't execute: $DBI::errstr";
  my ($count) = $sth->fetchrow;
  $sth->finish;

  return $count;
}

sub count_hidden_invoices {
  # counts number of hidden invoices in invoice database

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT COUNT(invoice_no)
      FROM bills2
      WHERE merchant=?
      AND status='hidden'
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($billpay_merchadmin::merchant) or die "Can't execute: $DBI::errstr";
  my ($count) = $sth->fetchrow;
  $sth->finish;

  return $count;
}

sub count_expired_invoices {
  # counts number of expired invoices in invoice database

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT COUNT(invoice_no)
      FROM bills2
      WHERE merchant=?
      AND expire_date<=?
      AND (status IS NULL OR status='' OR status='open')
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($billpay_merchadmin::merchant, $today) or die "Can't execute: $DBI::errstr";
  my ($count) = $sth->fetchrow;
  $sth->finish;
  
  return $count;
}

sub count_total_clients {
  # counts total number of contacts in client database

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT COUNT(username)
      FROM client_contact
      WHERE merchant=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($billpay_merchadmin::merchant) or die "Can't execute: $DBI::errstr";
  my ($count) = $sth->fetchrow;
  $sth->finish;

  return $count;
}

sub get_client_contact_list {
  my %client_list;

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT username, clientcompany, clientname, clientid, alias
      FROM client_contact
      WHERE merchant=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($billpay_merchadmin::merchant) or die "Can't execute: $DBI::errstr";
  while (my $results = $sth->fetchrow_hashref()) {
    if (($results->{'clientname'} ne '') || ($results->{'clientcompany'} ne '')) {
      $client_list{"$results->{'username'}"} = "$results->{'clientcompany'} - $results->{'clientname'}";
    }
    else {
      $client_list{"$results->{'username'}"} = "\[Email: $results->{'username'}\]";
    }
    if ($results->{'username'} =~ /(\.pnp)$/) {
      $client_list{"$results->{'username'}"} = "\?\? " . $client_list{"$results->{'username'}"};
    }
  }
  $sth->finish;

  return %client_list;
}

sub main_menu {
  my $type = shift;
  my %query = @_;

  my %client_list = &get_client_contact_list();

  print "<table width=760 border=0 cellpadding=0 cellspacing=0>\n";

  if ($ENV{'SEC_LEVEL'} <= 4) {
    #print "<!-- start upload invoice form -->\n";
    print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post enctype=\"multipart/form-data\">\n";
    print "<input type=hidden name=\"mode\" value=\"upload\">\n";

    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">Upload Invoices</th>\n";
    print "    <td class=\"menu_rightside\">\n";
    print "<table border=0 cellpadding=0 cellspacing=0>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">File To Upload:</td>\n";
    print "    <td class=\"rightside\"><input type=file class=\"button\" name=\"upload_file\"></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Invoice File Type:</td>\n";
    print "    <td class=\"rightside\"><input type=radio name=\"filetype\" value=\"billpay\" checked> Billing Presentment File\n";
    print "&nbsp; <input type=radio name=\"filetype\" value=\"baystate\"> BayState QB Invoice File\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Overwrite:</td>\n";
    print "    <td class=\"rightside\"><select name=\"overwrite\">\n";
    my %selected;
    if ($query{'merch_overwrite'} ne '') {
      $selected{"$query{'merch_overwrite'}"} = "selected";
    }
    else {
      $selected{"$billpay_merchadmin::feature_list{'billpay_overwrite'}"} = "selected";
    }
    print "<option value=\"none\" $selected{'none'}> None - Allow only new unique invoices </option>\n";
    print "<option value=\"same\" $selected{'same'}> Same - Allow overwrite of existing client invoice </option>\n";
    print "<option value=\"match\" $selected{'match'}> Match - Closes specific invoices of client, then add new invoice </option>\n";
    print "<option value=\"all\" $selected{'all'}> All - Closes all invoices of client, then add new invoice </option>\n";
    if ($billpay_merchadmin::feature_list{'billpay_remove_invoice'} == 1) {
      print "<option value=\"purge\" $selected{'purge'}> Purge - Removes all invoices of client, then add new invoice </option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td colspan=2 class=\"rightside\"><input type=checkbox name=\"email_cust\" value=\"yes\"";
    if ($query{'merch_email_cust'} =~ /y/i) { print " checked"; }
    print "> Email customer notification of uploaded invoice.</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td colspan=2 class=\"rightside\">&nbsp; &nbsp; &nbsp; <input type=checkbox name=\"express_pay\" value=\"yes\"";
    if ($query{'merch_express_pay'} =~ /y/i) { print " checked"; }
    print "> Include express pay link in email notifications.</td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "<input type=submit class=\"button\" value=\"Upload Invoices\">\n";
    print "&nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp;  <a href=\"https://$ENV{'SERVER_NAME'}/admin/doc_replace.cgi?doc=Billing_Presentment_-_Upload_Format.htm\" target=\"docs\">Upload File Format</a>\n";
    print "</td></form>\n";
    print "  </tr>\n";
    #print "<!-- end upload invoice form -->\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr width=\"80%\"></td>\n";
    print "  </tr>\n";
  }

  if ($ENV{'SEC_LEVEL'} <= 4) {
    #print "<!-- start export invoices form -->\n";
    print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"export\">\n";

    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">Export Invoices</th>\n";
    print "    <td class=\"menu_rightside\">";
    print "<table border=0 cellpadding=0 cellspacing=0>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Format:</td>\n";
    print "    <td class=\"rightside\"><input type=radio name=\"format\" value=\"table\"> Table\n";
    print "&nbsp; <input type=radio name=\"format\" value=\"text\"> Text\n";
    print "&nbsp; <input type=radio name=\"format\" value=\"download\" checked> Download</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Status:</td>\n";
    print "    <td class=\"rightside\"><input type=radio name=\"status\" value=\"\" checked> All Invoices \n";
    print "&nbsp; <input type=radio name=\"status\" value=\"open\"> Open\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"expired\"> Expired\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"closed\"> Closed\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"hidden\"> Hidden\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"merged\"> Merged\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"paid\"> Paid\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"unpaid\"> Unpaid</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Restrict To:</td>\n";
    print "    <td class=\"rightside\"><input type=radio name=\"invoices\" value=\"\" checked> All Invoices\n";
    print "&nbsp; <input type=radio name=\"invoices\" value=\"enter_date\"> Enter Date [Set Below]\n";
    print "&nbsp; <input type=radio name=\"invoices\" value=\"expire_date\"> Expire Date [Set Below]</td>\n";
    print "  </tr>\n";

    my @month_names = ('', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

    my @todays_date = gmtime(time);
    $todays_date[5] += 1900; # adjust for correct 4-digit year
    $todays_date[4] += 1;    # adjust for correct 2-digit month

    print "  <tr>\n";
    print "    <td class=\"leftside\">&nbsp;</td>\n";
    print "    <td class=\"rightside\">\n";

    print "<table>\n"; 
    print "  <tr>\n";
    print "    <td class=\"leftside\">From:</td>\n";
    print "    <td class=\"rightside\"><select name=\"startmonth\">\n";
    for (my $i = 1; $i <= $#month_names; $i++) {
      print  "<option value=\"$i\"";
      if ($i == $todays_date[4]) {
        print " selected";
      }
      print ">$month_names[$i]</option>\n";
    }
    print "</select>\n";
    print "<select name=\"startday\">\n";
    for (my $i = 1; $i <= 31; $i++) {
      print  "<option value=\"$i\"";
      #if ($i == $todays_date[3]) {
      #  print " selected";
      #}
      print ">$i</option>\n";
    }
    print "</select>\n";
    print "<select name=\"startyear\">\n";
    for (my $i = 2006; $i <= $todays_date[5]; $i++) {
      print  "<option value=\"$i\"";
      if ($i == $todays_date[5]) {
        print " selected";
      }
      print ">$i</option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">To:</td>\n";
    print "    <td class=\"rightside\"><select name=\"endmonth\">\n";
    for (my $i = 1; $i <= $#month_names; $i++) {
      print  "<option value=\"$i\"";
      if ($i == $todays_date[4]) {
        print " selected";
      }
      print ">$month_names[$i]</option>\n";
    }
    print "</select>\n";
    print "<select name=\"endday\">\n";
    for (my $i = 1; $i <= 31; $i++) {
      print  "<option value=\"$i\"";
      if ($i == $todays_date[3]) {
        print " selected";
      }
      print  ">$i</option>\n";
    }
    print "</select>\n";
    print "<select name=\"endyear\">\n";
    for (my $i = 2006; $i <= $todays_date[5]; $i++) {
      print  "<option value=\"$i\"";
      if ($i == $todays_date[5]) {
        print " selected";
      }
      print ">$i</option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "</td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "<input type=submit class=\"button\" value=\"Export Invoices\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
    #print "<!-- end export invoices form-->\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr width=\"80%\"></td>\n";
    print "  </tr>\n";
  }

  if ($ENV{'SEC_LEVEL'} <= 4) {
    #print "<!-- start add invoice form -->\n";
    print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"new_invoice\">\n";
    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">Add New Invoice</th>\n";
    print "    <td class=\"menu_rightside\">\n";
    print "<table border=0 cellpadding=0 cellspacing=0>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Customer:</td>\n";
    print "    <td class=\"rightside\"><select name=\"email\">\n";
    print "<option value=\"\">-- New Customer --</option>\n";
    foreach my $key1 (sort { $client_list{$a} cmp $client_list{$b}; } keys %client_list) {
      printf ("<option value=\"%s\">%s</option>\n", $key1, $client_list{"$key1"});
    }
    print "</select></td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "<input type=submit class=\"button\" value=\"Add New Invoice\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
    #print "<!-- end add invoice form -->\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr width=\"80%\"></td>\n";
    print "  </tr>\n";
  }

  if ($billpay_merchadmin::feature_list{'billpay_unknown_email'} ne 'yes') {
    if ($ENV{'SEC_LEVEL'} <= 4) {
      #print "<!-- start edit invoice form -->\n";
      print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
      print "<input type=hidden name=\"mode\" value=\"edit_invoice\">\n";
      print "  <tr>\n";
      print "    <th class=\"menu_leftside\">Edit Invoice</th>\n";
      print "    <td class=\"menu_rightside\">";
      print "<table border=0 cellpadding=0 cellspacing=0>\n";
      print "  <tr>\n";
      print "    <td class=\"leftside\">Email:</td>\n";
      print "    <td class=\"rightside\"><input type=text name=\"email\" value=\"\"></td>\n";
      print "  </tr>\n";
      print "  <tr>\n";
      print "    <td class=\"leftside\">Invoice \#:</td>\n";
      print "    <td class=\"rightside\"><input type=text name=\"invoice_no\" value=\"\"></td>\n";
      print "  </tr>\n";
      print "</table>\n";
      print "<input type=submit class=\"button\" value=\"Edit Invoice\">\n";
      print "</td></form>\n";
      print "  </tr>\n";
      #print "<!-- end edit invoice form -->\n";

      print "  <tr>\n";
      print "    <td colspan=2><hr width=\"80%\"></td>\n";
      print "  </tr>\n";
    }
  }

  if ($billpay_merchadmin::feature_list{'billpay_remove_invoice'} == 1) {
    if ($ENV{'SEC_LEVEL'} <= 4) {
      #print "<!-- start remove invoice form -->\n";
      print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
      print "<input type=hidden name=\"mode\" value=\"delete_invoice\">\n";
      print "  <tr>\n";
      print "    <th class=\"menu_leftside\">Remove Invoice</th>\n";
      print "    <td class=\"menu_rightside\">";
      print "<table border=0 cellpadding=0 cellspacing=0>\n";
      print "  <tr>\n";
      print "    <td class=\"leftside\">Email:</td>\n";
      print "    <td class=\"rightside\"><input type=text name=\"email\" value=\"\"></td>\n";
      print "  </tr>\n";
      print "  <tr>\n";
      print "    <td class=\"leftside\">Invoice \#:</td>\n";
      print "    <td class=\"rightside\"><input type=text name=\"invoice_no\" value=\"\"></td>\n";
      print "  </tr>\n";
      print "</table>\n";
      print "<input type=submit class=\"button\" value=\"Remove Invoice\">\n";
      print "</td></form>\n";
      print "  </tr>\n";
      #print "<!-- end remove invoice form -->\n";

      print "  <tr>\n";
      print "    <td colspan=2><hr width=\"80%\"></td>\n";
      print "  </tr>\n";
    }
  }

  if ($ENV{'SEC_LEVEL'} <= 8) {
    #print "<!-- start express pay invoice form -->\n";
    print "<form method=post action=\"/billpay_express.cgi\" target=\"billpay\">\n";
    print "<input type=hidden name=\"merchant\" value=\"$billpay_merchadmin::merchant\">\n";
    print "<input type=hidden name=\"cobrand\" value=\"$billpay_merchadmin::query{'merch_company'}\">\n";
    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">Express Pay<br>Invoice</th>\n";
    print "    <td class=\"menu_rightside\">";
    print "<table border=0 cellpadding=0 cellspacing=0>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Email:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"email\" value=\"\"></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Invoice \#:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"invoice_no\" value=\"\"></td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "<input type=submit class=\"button\" value=\"Express Pay\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
    #print "<!-- end express pay invoice form -->\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr width=\"80%\"></td>\n";
    print "  </tr>\n";
  }

  if ($billpay_merchadmin::feature_list{'billpay_unknown_email'} eq 'yes') {
    if ($ENV{'SEC_LEVEL'} <= 7) {
      print "<!-- start assign invoices form -->\n";
      print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
      print "<input type=hidden name=\"mode\" value=\"assign_invoices\">\n";
      print "  <tr>\n";
      print "    <th class=\"menu_leftside\">Assign Invoices</th>\n";
      print "    <td class=\"menu_rightside\">";
      print "<table border=0 cellpadding=0 cellspacing=0>\n";
      print "  <tr>\n";
      print "    <td class=\"leftside\">Assign Invoices<br>For Account \#:</td>\n";
      print "    <td class=\"rightside\"><input type=text name=\"account_no\" value=\"\"></td>\n";
      print "  </tr>\n";
      print "  <tr>\n";
      print "    <td class=\"leftside\">To Client's Real Email:</td>\n";
      print "    <td class=\"rightside\"><input type=text name=\"email\" value=\"\"></td>\n";
      print "  </tr>\n";
      print "</table>\n";
      print "<input type=submit class=\"button\" value=\"Assign Invoices\">\n";
      print "</td></form>\n";
      print "  </tr>\n";
      print "<!-- end assign invoices form -->\n";

      print "  <tr>\n";
      print "    <td colspan=2><hr width=\"80%\"></td>\n";
      print "  </tr>\n";
    }
  }

  if ($ENV{'SEC_LEVEL'} <= 9) {
    # print "<!-- start search invoices form -->\n";
    print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"search_invoices\">\n";
    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">Search Invoices</th>\n";
    print "    <td class=\"menu_rightside\">";

    print "<table border=0 cellpadding=0 cellspacing=0>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Email:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"email\" value=\"\"></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Invoice \#:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"invoice_no\" value=\"\"></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Account \#:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"account_no\" value=\"\"></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">OrderID \#:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"orderid\" value=\"\"></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Amount Between:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"amount_min\" value=\"\" size=8> and <input type=text name=\"amount_max\" value=\"\" size=8></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Status:</td>\n";
    print "    <td class=\"rightside\"><input type=radio name=\"status\" value=\"\" checked> Any Status\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"open\"> Open\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"expired\"> Expired\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"closed\"> Closed\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"hidden\"> Hidden\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"merged\"> Merged\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"paid\"> Paid\n";
    print "&nbsp; <input type=radio name=\"status\" value=\"unpaid\"> Unpaid</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Restrict To:</td>\n";
    print "    <td class=\"rightside\"><input type=radio name=\"invoices\" value=\"\" checked> All Invoices\n";
    print "&nbsp; <input type=radio name=\"invoices\" value=\"enter_date\">Enter Date [Set Below]\n";
    print "&nbsp; <input type=radio name=\"invoices\" value=\"expire_date\">Expire Date [Set Below]</td>\n";
    print "  </tr>\n";

    my @month_names = ('', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

    my @todays_date = gmtime(time);
    $todays_date[5] += 1900; # adjust for correct 4-digit year
    $todays_date[4] += 1;    # adjust for correct 2-digit month

    print "  <tr>\n";
    print "    <td class=\"leftside\">&nbsp;</td>\n";
    print "    <td class=\"rightside\">\n";

    print "<table>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">From:</td>\n";
    print "    <td class=\"rightside\"><select name=\"startmonth\">\n";
    for (my $i = 1; $i <= $#month_names; $i++) {
      print  "<option value=\"$i\"";
      if ($i == $todays_date[4]) {
        print " selected";
      }
      print ">$month_names[$i]</option>\n";
    }
    print "</select>\n";
    print "<select name=\"startday\">\n";
    for (my $i = 1; $i <= 31; $i++) {
      print  "<option value=\"$i\"";
      #if ($i == $todays_date[3]) {
      #  print " selected";
      #}
      print ">$i</option>\n";
    }
    print "</select>\n";
    print "<select name=\"startyear\">\n";
    for (my $i = 2006; $i <= $todays_date[5]; $i++) {
      print  "<option value=\"$i\"";
      if ($i == $todays_date[5]) {
        print " selected";
      }
      print ">$i</option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">To:</td>\n";
    print "    <td class=\"rightside\"><select name=\"endmonth\">\n";
    for (my $i = 1; $i <= $#month_names; $i++) {
      print  "<option value=\"$i\"";
      if ($i == $todays_date[4]) {
        print " selected";
      }
      print ">$month_names[$i]</option>\n";
    }
    print "</select>\n";
    print "<select name=\"endday\">\n";
    for (my $i = 1; $i <= 31; $i++) {
      print  "<option value=\"$i\"";
      if ($i == $todays_date[3]) {
        print " selected";
      }
      print  ">$i</option>\n";
    }
    print "</select>\n";
    print "<select name=\"endyear\">\n";
    for (my $i = 2006; $i <= $todays_date[5]; $i++) {
      print  "<option value=\"$i\"";
      if ($i == $todays_date[5]) {
        print " selected";
      }
      print ">$i</option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "</td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "<input type=submit class=\"button\" value=\"Search Invoices\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
    #print "<!-- end search invoices form -->\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr width=\"80%\"></td>\n";
    print "  </tr>\n";
  }

  if ($ENV{'SEC_LEVEL'} <= 9) {
    #print "<!-- start manage clients section -->\n";
    print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"manage_clients_menu\">\n";
    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">Manage Contacts</th>\n";
    print "    <td class=\"menu_rightside\"><input type=submit class=\"button\" value=\"Manage Contacts\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
    #print "<!-- end manage clients section -->\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr width=\"80%\"></td>\n";
    print "  </tr>\n";
  }

  if (($ENV{'SEC_LEVEL'} < 11) || ($ENV{'SEC_LEVEL'} == 15)) {
    #print "<!-- start invoice payment review section -->\n";
    my $earliest_date = "20040101";
    if ((-e "/home/p/pay1/outagefiles/mediumvolume.txt") || (-e "/home/p/pay1/outagefiles/highvolume.txt")) {
      my @early = gmtime(time() - (3600 * 24 * 2));
      $earliest_date = sprintf("%04d%02d%02d", $early[5]+1900, $early[4]+1, $early[3]);
    }

    my @past = gmtime(time() - 86400);
    my $startdate = sprintf("%02d/%02d/%04d", $past[4]+1, $past[3], $past[5]+1900);

    my $chkstartdate = sprintf("%04d%02d%02d",$past[5]+1900, $past[4]+1, $past[3]);
    if ($chkstartdate < $earliest_date) {
      $startdate = substr($earliest_date,4,2) . "/" . substr($earliest_date,6,2) . "/" . substr($earliest_date,0,4);
    }

    my @soon = gmtime(time() + 86400);
    my $enddate = sprintf("%02d/%02d/%04d", $soon[4]+1, $soon[3], $soon[5]+1900);

    print "<form action=\"/admin/smps.cgi\" method=post>";
    print "<input type=hidden name=\"function\" value=\"query\">\n";
    print "<input type=hidden name=\"merchant\" value=\"$billpay_merchadmin::merchant\">\n";
    if ($ENV{'SUBACCT'} ne '') {
      print "<input type=hidden name=\"subacct\" value=\"$ENV{'SUBACCT'}\">\n";
    }
    print "<input type=hidden name=\"acct_code3\" value=\"billpay\"></td>\n";
    print "<input type=hidden name=\"display_acct\" value=\"yes\">\n";
    print "<input type=hidden name=\"display_errmsg\" value=\"yes\">\n";

    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">Review Invoice Payments</th>\n";
    print "    <td class=\"menu_rightside\">\n";

    if (-e "/home/p/pay1/outagefiles/highvolume.txt") {
      print "Sorry, this program is not available at this time.<p>\n";
      print "Please try back in a little while.<p>\n";
      return;
    }

    print "<table border=0 cellpadding=0 cellspacing=0>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Transaction:</td>\n";
    print "    <td class=\"rightside\"><select name=\"txntype\">\n";
    print "<option value=\"\">All Transactions</option>\n";
    print "<option value=\"invoice\">Invoiced</option>\n";
    print "<option value=\"auth\">Authorized</option>\n";
    print "<option value=\"anm\">Authorized but never marked</option>\n";
    print "<option value=\"marked\">Marked for batching</option>\n";
    print "<option value=\"settled\">Settled Auths</option>\n";
    print "<option value=\"forceauth\">Forced Auth</option>\n";
    print "<option value=\"markret\">Returns</option>\n";
    print "<option value=\"setlret\">Settled Returns</option>\n";
    print "<option value=\"voidmark\">Voided Marks</option>\n";
    print "<option value=\"voidreturn\">Voided Returns</option>\n";
    print "<option value=\"batch\">Batches</option>\n";
    print "</select></td>\n";
    print "  </tr>\n";

    my ($select_mo,$select_dy,$select_yr) = split('/',$startdate);
    my $html = &miscutils::start_date($select_yr,$select_mo,$select_dy);
    print "  <tr>\n";
    print "    <td class=\"leftside\">First Day:</td>\n";
    print "    <td class=\"rightside\">$html Time: <select name=\"starthour\">\n";
    for (my $i=0; $i<=23; $i++) {
      my $time = sprintf("%02d", $i);
      print "<option value=\"$i\">$time</option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";

    ($select_mo,$select_dy,$select_yr) = split('/',$enddate);
    $html = &miscutils::end_date($select_yr,$select_mo,$select_dy);
    print "  <tr>\n";
    print "    <td class=\"leftside\">Last Day:</td>\n";
    print "    <td class=\"rightside\">$html Time: <select name=\"endhour\">\n";
    for (my $i=0; $i<=23; $i++) {
      my $time = sprintf("%02d", $i);
      print "<option value=\"$i\">$time</option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";

    my %timezonehash = ();
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());
    %timezonehash = %constants::timezones;

    print "  <tr>\n";
    print "    <td class=\"leftside\">Time Zone:</td>\n";
    print "    <td class=\"rightside\"><select name=\"settletimezone\">\n";
    print "<option value=\"\"> Select Time Zone </option>\n";
    foreach my $timeshift (sort numerically keys %timezonehash) {
      print "<option value=\"$timeshift\" ";
      if ($timeshift == $billpay_merchadmin::feature_list{'settletimezone'}) {
        print "selected";
      }
      print "> $timezonehash{$timeshift} </option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Account No:</td>\n";
    print "    <td class=\"rightside\"><input type=text size=12 maxlength=25 name=\"acct_code\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Invoice No:</td>\n";
    print "    <td class=\"rightside\"><input type=text size=12 maxlength=25 name=\"acct_code2\"> \n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Partial Match:</td>\n";
    print "    <td class=\"rightside\"><input type=checkbox name=\"partial\" value=\"1\"> Check to Display Partial Matches on Account Number &/or Invoice Number.</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Format:</td>\n";
    print "    <td class=\"rightside\"><input type=radio name=\"format\" value=\"table\" checked> Table <input type=radio name=format value=\"text\"> Text <input type=radio name=\"format\" value=\"download\"> Download</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Summary Only:</td>\n";
    print "    <td class=\"rightside\"><input type=checkbox name=\"summaryonly\" value=\"yes\"> Check to Display Report Summary Only</td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "<input type=submit class=\"button\" name=submit value=\"Submit Query\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
    #print "<!-- start invoice payment review section -->\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr width=\"80%\"></td>\n";
    print "  </tr>\n";
  }

  #print "<!-- start documentation section -->\n";
  print "  <tr>\n";
  print "    <th class=\"menu_leftside\">Documentation</th>\n";
  print "    <td class=\"menu_rightside\">";
  print "&bull; <a href=\"https://$ENV{'SERVER_NAME'}/admin/doc_replace.cgi?doc=Billing_Presentment_-_Overview.htm\" target=\"docs\">Billing Presentment - Service Overview</a>\n";
  print "<br>&bull; <a href=\"https://$ENV{'SERVER_NAME'}/admin/doc_replace.cgi?doc=Billing_Presentment_-_Upload_Format.htm\" target=\"docs\">Billing Presentment - Upload File Format</a>\n";
  print "  </tr>\n";
  # print "<!-- end documentation section -->\n";

  print "</table>\n";

  return;
}

sub manage_clients_menu {
  my $type = shift;
  my %query = @_;

  my %client_list = &get_client_contact_list();

  print "<table width=760 border=0 cellpadding=0 cellspacing=0>\n";

  if ($ENV{'SEC_LEVEL'} <= 4) {
    #print "<!-- start add new client form -->\n";
    print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"new_client\">\n";
    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">Add New Contact</th>\n";
    print "    <td class=\"menu_rightside\"><input type=submit class=\"button\" value=\"Add New Contact\"></td></form>\n";
    print "  </tr>\n";
    #print "<!-- end add new client form -->\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr width=\"80%\"></td>\n";
    print "  </tr>\n";
  }

  if ($ENV{'SEC_LEVEL'} <= 4) {
    #print "<!-- start edit client form -->\n";
    print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"edit_client\">\n";
    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">Edit Contact</th>\n";
    print "    <td class=\"menu_rightside\">\n";
    print "<table border=0 cellpadding=0 cellspacing=0>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Customer:</td>\n";
    print "    <td class=\"rightside\"><select name=\"email\">\n";
    foreach my $key1 (sort { $client_list{$a} cmp $client_list{$b}; } keys %client_list) {
      printf ("<option value=\"%s\">%s</option>\n", $key1, $client_list{"$key1"});
    }
    print "</select></td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "<input type=submit class=\"button\" value=\"Edit Contact\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
    #print "<!-- end edit client form -->\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr width=\"80%\"></td>\n";
    print "  </tr>\n";
  }

  if ($ENV{'SEC_LEVEL'} <= 4) {
    #print "<!-- start delete client form -->\n";
    print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"delete_client\">\n";
    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">Remove Contact</th>\n";
    print "    <td class=\"menu_rightside\">\n";
    print "<table border=0 cellpadding=0 cellspacing=0>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Customer:</td>\n";
    print "    <td class=\"rightside\"><select name=\"email\">\n";
    foreach my $key1 (sort { $client_list{$a} cmp $client_list{$b}; } keys %client_list) {
      printf ("<option value=\"%s\">%s</option>\n", $key1, $client_list{"$key1"});
    }
    print "</select></td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "<input type=submit class=\"button\" value=\"Remove Contact\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
    #print "<!-- end delete client form -->\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr width=\"80%\"></td>\n";
    print "  </tr>\n";
  }

  if ($ENV{'SEC_LEVEL'} <= 9) {
    #print "<!-- start list contacts section -->\n";
    print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"list_clients\">\n";
    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">List Contacts</th>\n";
    print "    <td class=\"menu_rightside\"><input type=submit class=\"button\" value=\"List Contacts\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
    #print "<!-- end list contacts section -->\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr width=\"80%\"></td>\n";
    print "  </tr>\n";
  }

  if ($ENV{'SEC_LEVEL'} <= 9) {
    #print "<!-- start search clients form -->\n";
    print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"search_clients\">\n";
    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">Search Contacts</th>\n";
    print "    <td class=\"menu_rightside\">";

    print "<table border=0 cellpadding=0 cellspacing=0>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Email:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"email\" value=\"\"></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Company:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"clientcompany\" value=\"\"></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Name:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"clientname\" value=\"\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Address Line 1:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"clientaddr1\" value=\"\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Address Line 2:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"clientaddr2\" value=\"\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">City:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"clientcity\" value=\"\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">State:</td>\n";
    print "    <td class=\"rightside\">";
    my %temp = &get_appendix_hash('USstates');
    print "<select name=\"clientstate\">\n";
    print "<option value=\"\"> </option>\n";
    foreach my $key1 (&sort_hash(\%temp)) {
      printf ("<option value=\"%s\"> %s </option>\n", $key1, $temp{$key1});
    }
    print "</select></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Zip/Postal Code:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"clientzip\" value=\"\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Country:</td>\n";
    print "    <td class=\"rightside\">";
    my %temp2 = &get_appendix_hash('countries');
    print "<select name=\"clientcountry\">\n";
    print "<option value=\"\"> </option>\n";
    foreach my $key1 (&sort_hash(\%temp2)) {
      printf ("<option value=\"%s\"> %s </option>\n", $key1, $temp2{$key1});
    }
    print "</select></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Phone:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"clientphone\" value=\"\" size=10 maxlength=15></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Fax:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"clientfax\" value=\"\" size=10 maxlength=15></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Client ID:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"clientid\" value=\"\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Alias:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"alias\" value=\"\"></td>\n";
    print "  </tr>\n";

    if ($billpay_merchadmin::feature_list{'billpay_showconsolidate'} eq 'yes') {
      print "  <tr>\n";
      print "    <td class=\"leftside\">Consolidate:</td>\n";
      print "    <td class=\"rightside\"><input type=checkbox name=\"consolidate\" value=\"yes\"> Limit results to contacts which are allowed consolidation.</td>\n";
      print "  </tr>\n";
    }

    print "</table>\n";
    print "<input type=submit class=\"button\" value=\"Search Contacts\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
    #print "<!-- end search clients form -->\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr width=\"80%\"></td>\n";
    print "  </tr>\n";
  }

  if ($ENV{'SEC_LEVEL'} <= 4) {
    #print "<!-- start export clients form -->\n";
    print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"export_clients\">\n";

    print "  <tr>\n";
    print "    <th class=\"menu_leftside\">Export Contacts</th>\n";
    print "    <td class=\"menu_rightside\">";
    print "<table border=0 cellpadding=0 cellspacing=0>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Format:</td>\n";
    print "    <td class=\"rightside\"><input type=radio name=\"format\" value=\"table\"> Table\n";
    print "&nbsp; <input type=radio name=\"format\" value=\"text\"> Text\n";
    print "&nbsp; <input type=radio name=\"format\" value=\"download\" checked> Download</td>\n";
    print "  </tr>\n";

    print "</td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "<input type=submit class=\"button\" value=\"Export Contacts\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
    #print "<!-- end export clients form-->\n";
  }

  print "</table>\n";

  return;
}

sub deny_access {
  &html_head("Restricted Access");
  print "<p><font color=\"#CC0000\" size=\"+1\">Your current security level is not cleared for this section/operation.</font>\n";
  print "<br><font size=\"+1\">Please contact your manager if you believe this to be in error.</font></p>\n";
  &html_tail();
  return;
}

sub upload_invoice {
  #my $type = shift;
  my ($dummy, $email_cust, $merch_company, $overwrite, $express_pay, $filetype) = @_;

  my $query = new CGI;
  my %query;
  my @array = $query->param;
  foreach my $key (@array) {
    $key =~ s/[^a-zA-Z0-9\_\-]//g;
    $query{"$key"} = &CGI::escapeHTML($query->param($key));
  }

  # If you want to restrict the upload file size (in bytes), uncomment the next line and change the number
  $CGI::POST_MAX = 1048576 * 2; # set to 2 Megs max file size
  # Converion Notes: 1K = 1024 bytes, 1Meg = 1048576 bytes.

  my $webtxt = &pnp_environment::get('PNP_WEB_TXT');
  my $upload_dir = $webtxt . "/admin/billpay/data"; # absolute path to folder where uploaded files will reside

  # set filename
  my $remoteuser = $billpay_merchadmin::merchant;
  $remoteuser =~ s/[^0-9a-zA-Z]//g;
  my $filename = $remoteuser . ".txt";

  # grab the file uploaded
  my $upload_file = $query->upload('upload_file');

  # look for uploads that exceed $CGI::POST_MAX
  if (!$upload_file && $query->cgi_error) {
    my $error = $query->cgi_error();
    $error .= "\n\nThe file you are attempting to upload exceeds the maximum allowable file size.\n";
    &error_form("$error");
    return;
  }

  # open target file on harddisk
  my $filteredname = &sysutils::filefilter("$upload_dir","$filename") or die "FileFilter Rejection";
  &sysutils::filelog('write',">$filteredname");

  # Upgrade the handle to one compatible with IO::Handle:
  my $io_handle = $upload_file->handle;
  open (UPLOADFILE,'>',"$filteredname");
  while (my $bytesread = $io_handle->read(my $buffer,1024)) {
    print UPLOADFILE $buffer;
  }
  close(UPLOADFILE);

  # force 666 file permissions - to ensure files cannot be executed
  chmod(0666, "$upload_dir/$filename");

  # sent file upload notification
  #&send_email($filename);

  # display thank you response to the end user
  print "<p><b>Your Billing Presentment invoice file has been accepted.</b></p>\n";

  print "<p><b>Processing Uploaded File - Please Wait...</b>\n";
  print "<br>&nbsp;\n";

  if ($filetype eq 'baystate') {
    &import_data_baystate("$upload_dir", "$filename", "$email_cust", "$merch_company", "$overwrite", "$express_pay");
  }
  else {
    &import_data("$upload_dir", "$filename", "$email_cust", "$merch_company", "$overwrite", "$express_pay");
  }

  print "<br>&nbsp;\n";
  print "<br><b>Upload Completed...<b></p>\n";

  print "<table border=1 cellpadding=2 cellspacing=0>\n";
  print "  <tr>\n";
  print "    <th colspan=7 bgcolor=\"#dddddd\">Invoice Upload Stats</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td bgcolor=\"#eeeeee\"></td>\n";
  print "    <td bgcolor=\"#eeeeee\">Total</td>\n";
  print "    <td bgcolor=\"#eeeeee\">Open</td>\n";
  print "    <td bgcolor=\"#eeeeee\">Closed</td>\n";
  print "    <td bgcolor=\"#eeeeee\">Hidden</td>\n";
  print "    <td bgcolor=\"#eeeeee\">Merged</td>\n";
  print "    <td bgcolor=\"#eeeeee\">Paid</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td bgcolor=\"#eeeeee\">Added</td>\n";
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'add_cnt'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'add_open'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'add_closed'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'add_hidden'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'add_merged'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'add_paid'});
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td bgcolor=\"#eeeeee\">Updated</td>\n";
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'update_cnt'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'update_open'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'update_closed'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'update_hidden'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'update_merged'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'update_paid'});
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td bgcolor=\"#eeeeee\">Rejected</td>\n";
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'reject_cnt'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'reject_open'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'reject_closed'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'reject_hidden'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'reject_merged'});
  printf ("    <td align=center>%01d</td>\n", $billpay_merchadmin::count{'reject_paid'});
  print "  </tr>\n";
  print "</table>\n";

  print "<p><form action=\"$ENV{'SCRIPT_NAME'}\" method=post><input type=submit class=\"button\" value=\"Main Menu\"></form>\n";
 
  return;
}

sub error_form {
  my ($error) = @_;
  print "<p>UPLOAD ERROR: $error</p>\n";
  return;
}

sub import_data {
  # this is the import function for billpay specific invoice upload files
  my ($filepath, $filename, $email_cust, $merch_company, $overwrite, $express_pay) = @_;

  my @header;
  my %header;

  # assign unique starting invoice_no, to be used later if necessary
  my @now = gmtime(time);
  my $invoice_no = sprintf("%04d%02d%02d%02d%02d%02d%05d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0], 00000);
  sleep(2);

  # open database file for reading
  my $filteredname = &sysutils::filefilter("$filepath","$filename") or die "FileFilter Rejection";
  &sysutils::filelog("read","$filteredname");
  open(INFILE,'<',"$filteredname") or die "Cannot open $filename for reading. $!";

  # read file into memory
  while(<INFILE>) {
    my $theline = $_;
    chop $theline;

    my %row_data;
    $row_data{'express_pay'} = $express_pay;

    # find out 1st letter
    my $letter = substr($theline, 0, 1);
    #print "LETTER: $letter \n";

    if ($letter eq '!') {
      # if 1st letter is a "!" then find out header and put the values in an array
      @header = split(/\t/, $theline); # grab contents of header
      $header[0] =~ s/\!//g; # remove "!" from first character
      $header[$#header] =~ s/\s//g; # remove white space characters
      for ($a = 0; $a <= $#header; $a++) {
        $header[$a] =~ s/^\s+//g; # remove leading whitespace
        $header[$a] =~ s/\s+$//g; # remove trailing whitespace
      }
    }
    else {
      my @temp = split(/\t/, $theline);  # grab contents of row
      for ($a = 0; $a <= $#header; $a++) {
        # put row's data into row_data hash
        $temp[$a] =~ s/^\s+//g; # remove leading whitespace
        $temp[$a] =~ s/\s+$//g; # remove trailing whitespace
        $row_data{"$header[$a]"} = $temp[$a];
        #print "<!-- row_data -- \'$header[$a]\' -- \'$temp[$a]\'>\n";
      }

      if ($row_data{'BATCH'} eq 'billpay_invoice') {
        # assign unique invoice_no, if when not already defined
        if ($row_data{'invoice_no'} eq '') {
          $row_data{'invoice_no'} = $invoice_no;
          $invoice_no = $invoice_no + 1; # incriment invoice number for next order
        }

        # pass on certain fields
        $row_data{'email_cust'} = $email_cust;
        $row_data{'merch_company'} = $merch_company;
        $row_data{'overwrite'} = $overwrite;

        # add invoice to database
        &update_bill(%row_data);
      }
    }
  }
  close(INFILE);

  return;
}

sub import_data_baystate {
  # this is the import function for baystate QB specific invoice upload files
  my ($filepath, $filename, $email_cust, $merch_company, $overwrite, $express_pay) = @_;

  my @header;
  my %header;

  # assign unique starting invoice_no, to be used later if necessary
  my @now = gmtime(time);
  my $invoice_no = sprintf("%04d%02d%02d%02d%02d%02d%05d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0], 00000);
  sleep(2);

  # open database file for reading
  my $filteredname = &sysutils::filefilter("$filepath","$filename") or die "FileFilter Rejection";
  &sysutils::filelog("read","$filteredname");
  open(INFILE,'<',"$filteredname") or die "Cannot open $filename for reading. $!";

  # first line in the file is the header line, so read it & create the header
  my $theline = <INFILE>;
  chop $theline;
  $theline =~ s/[^a-zA-Z0-9\_\-\t]//g; # remove anything that is not alphanumeric, dash, underscore or tab character
  @header = split(/\t/, $theline); # grab contents of header
  $header[$#header] =~ s/\s//g; # remove white space characters

  my %HoH = (); # this is a hash of hashes, which holds all the merged QB invoice data.
  my %HoH_count; # this a hash that track of how many items are each QB invoice, so we can incriment X in the itemX, costX, qtyX & descrX as we go along.

  # read rest of file into memory
  while(<INFILE>) {
    my $theline = $_;
    chop $theline;

    my %row_data;

    my @temp = split(/\t/, $theline);  # grab contents of row
    for ($a = 0; $a <= $#header; $a++) {
      # put row's data into row_data hash
      $row_data{"$header[$a]"} = $temp[$a];
      #print "<!-- row_data -- \'$header[$a]\' -- \'$temp[$a]\'>\n";
    }

    # start building the billpay invoices here
    # NOTE: commented $HoH lines below are listed for possible future usage, but are not needed at this time for basic invoice usage)
    my $invoice = $row_data{'TxnId'};

    if ($HoH{"$invoice"}->{'invoice_no'} !~ /\w/) {
      $HoH{"$invoice"}{'invoice_no'} = $row_data{'TxnId'};

      my ($customer, $project) = split(/\:/, $row_data{'Customer'}, 2); # example: "customer_last, customer_first:project_name"
      #my ($customer_last, $customer_first) = split(/\, /, $customer, 2);
      #$HoH{"$invoice"}{'clientname'} = "$customer_first $customer_last";
      $HoH{"$invoice"}{'account_no'} = "$project";

      $HoH{"$invoice"}{'email'} = &get_client_email("$row_data{'CustomerAccountNumber'}"); # lookup email address, using clientID number

      my @enter_date = split(/\//, $row_data{'TxnDate'}, 3); # example: "01/31/2008"
      $HoH{"$invoice"}{'enter_date'} = sprintf("%04d%02d%02d", $enter_date[2], $enter_date[0], $enter_date[1]);

      #$HoH{"$invoice"}{''} = $row_data{'RefNumber'};
      #$HoH{"$invoice"}{''} = $row_data{'Class'};
      #$HoH{"$invoice"}{''} = $row_data{'ARAccount'};

      $HoH{"$invoice"}{'balance'} = $row_data{'BalanceRemaining'};
      $HoH{"$invoice"}{'percent'} = '';
      $HoH{"$invoice"}{'monthly'} = '';
      $HoH{"$invoice"}{'remnant'} = '';
      $HoH{"$invoice"}{'billcycle'} = '0';

      $HoH{"$invoice"}{'clientname'} = $row_data{'BillToLine1'};
      $HoH{"$invoice"}{'clientcompany'} = $row_data{'BillToLine2'};
      $HoH{"$invoice"}{'clientaddr1'} = $row_data{'BillToLine3'};
      $HoH{"$invoice"}{'clientaddr2'} = $row_data{'BillToLine4'};
      $HoH{"$invoice"}{'clientcity'} = $row_data{'BillToCity'};
      $HoH{"$invoice"}{'clientstate'} = $row_data{'BillToState'};
      $HoH{"$invoice"}{'clientzip'} = $row_data{'BillToPostalCode'};
      $HoH{"$invoice"}{'clientcountry'} = $row_data{'BillToCountry'};
      $HoH{"$invoice"}{'clientphone'} = $row_data{'BillToPhone'};
      $HoH{"$invoice"}{'clientfax'} = $row_data{'BillToFax'};

      #$HoH{"$invoice"}{''} = $row_data{'ShipToLine1'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToLine2'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToLine3'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToLine4'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToCity'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToState'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToPostalCode'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToCountry'};

      #$HoH{"$invoice"}{''} = $row_data{'PONumber'};
      #$HoH{"$invoice"}{''} = $row_data{'Terms'};
      #$HoH{"$invoice"}{''} = $row_data{'SalesRep'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipDate'};

      my @expire_date = split(/\//, $row_data{'DueDate'}, 3); # example: "01/31/2008"
      $HoH{"$invoice"}{'expire_date'} = sprintf("%04d%02d%02d", $expire_date[2], $expire_date[0], $expire_date[1]);

      #$HoH{"$invoice"}{''} = $row_data{'ShipMethod'};
      #$HoH{"$invoice"}{''} = $row_data{'FOB'};
      #$HoH{"$invoice"}{''} = $row_data{'Class'};
      $HoH{"$invoice"}{'private_notes'} = $row_data{'Memo'};

      #$HoH{"$invoice"}{''} = $row_data{'SalesTaxCode'};
      #$HoH{"$invoice"}{''} = $row_data{'SalesTaxItem'};
      #$HoH{"$invoice"}{''} = $row_data{'SalesTaxPercentage'};

      $row_data{'SalesTaxTotal'} =~ s/[^0-9\.]//g;
      $HoH{"$invoice"}{'tax'} = sprintf("%0.02f", $row_data{'SalesTaxTotal'});

      #$HoH{"$invoice"}{''} = $row_data{'Other'};
      #$HoH{"$invoice"}{''} = $row_data{'TxnLineServiceDate'};
    }

    # incriment item X counter for the given TxnID
    $HoH_count{"$invoice"} = $HoH_count{"$invoice"} + 1;
    my $x = $HoH_count{"$invoice"};

    $row_data{'TxnLineQuantity'} =~ s/[^0-9\.]//g;
    $HoH{"$invoice"}{"qty$x"} = $row_data{'TxnLineQuantity'};

    $row_data{'TxnLineItem'} =~ s/[^a-zA-Z_0-9\.\_\-]//g;
    $HoH{"$invoice"}{"item$x"} = $row_data{'TxnLineItem'};

    $row_data{'TxnLineDescription'} =~ s/[^a-zA-Z_0-9\ \_\-\.\,\+\/\(\)]//g;
    $HoH{"$invoice"}{"descr$x"} = $row_data{'TxnLineDescription'};
    #$HoH{"$invoice"}{''} = $row_data{'TxnLineOther1'};
    #$HoH{"$invoice"}{''} = $row_data{'TxnLineOther2'};

    $row_data{'TxnLineCost'} =~ s/[^0-9\.\-]//g;
    $HoH{"$invoice"}{"cost$x"} = sprintf("%0.02f", $row_data{'TxnLineCost'});

    $row_data{'TxnLineAmount'} =~ s/[^0-9\.\-]//g;
    $HoH{"$invoice"}{'amount'} = sprintf("%0.02f", $HoH{"$invoice"}->{'amount'} + $row_data{'TxnLineAmount'});

    #$HoH{"$invoice"}{''} = $row_data{'TxnLineSalesTaxCode'};
    #$HoH{"$invoice"}{''} = $row_data{'TxnLineClass'};
    #$HoH{"$invoice"}{''} = $row_data{'TxnLineTaxCode'};
    #$HoH{"$invoice"}{''} = $row_data{'TxnLineCDNTaxCode'};

    #print "<br>KEY: $HoH{$invoice}->{'invoice_no'}, Amount: $HoH{$invoice}->{'amount'} , Count: $HoH_count{$invoice}\n";
    #print "<hr>\n";
  }
  close(INFILE);

  # now loop through the completed QB invoice & add it to the database.

  foreach my $key (sort keys %HoH) {
    # this 1st loop gets the KEY for each QB invoice.
    if ($key =~ /\w/) {
      my %row_data;
      #print "<p>Invoice \#: $key, Email: $HoH{$key}->{'email'}, Amount: $HoH{$key}->{'amount'}\n";

      my $deref = $HoH{"$key"};
      foreach my $key2 (sort keys %$deref) {
        # this 2nd loop refferences the specfic fields related to the single QB invoice.
        if ($key =~ /\w/) {
          $row_data{"$key2"} = $$deref{"$key2"};
          #print "<br>&bull; $key2 --> $$deref{"$key2"}\n";
        }
      }

      # pass on certain fields
      $row_data{'express_pay'} = $express_pay;
      $row_data{'email_cust'} = $email_cust;
      $row_data{'merch_company'} = $merch_company;
      $row_data{'overwrite'} = $overwrite;

      # add invoice to database
      &update_bill(%row_data);
    }
  }

  return;
}

sub update_bill {
  if ($billpay_merchadmin::query{'mode'} !~ /upload/) {
    my $type = shift;
  }
  my %query = @_;

  # filter query data, as we don't know where it came from (i.e. from a upload file, API request or POST from BillPay admin area)
  my $iv = new PlugNPay::InputValidator();
  $iv->changeContext('billpay_merchadmin');
  %query = $iv->filterHash(%query); 

  my ($data, $stored_invoice);

  if ($query{'old_email'} =~ /(\.pnp)$/) {
    $query{'email'} = $query{'old_email'}
  }

  # create placeholder email address for when unknown email feature is enabled; but now make account number required.
  if (($billpay_merchadmin::feature_list{'billpay_unknown_email'} eq 'yes') && ($query{'email'} eq '')) {
    if ($query{'account_no'} =~ /\w/) {
      $query{'email'} = sprintf("%s\@%s\.%s", $query{'account_no'}, $billpay_merchadmin::merchant, "pnp");
    }
    else {
      print "<p><font color=\"#CC0000\" size=\"+1\">Invalid account number. Please try again.</font></p>\n";
      if ($query{'mode'} eq 'update_invoice') {
        print "<br><form><input type=button name=\"back_button\" value=\"Return To Previous Page\" onClick=\"javascript:history.go(-1);\"></form>\n";
      }
      return;
    }
  }

  # do data filtering & other checks
  # login email address filter
  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} = lc($query{'email'});
  my ($is_ok, $reason) = &is_email("$query{'email'}");
  if ($is_ok eq 'problem') {
    if ($query{'mode'} eq 'remote_update_invoice') {
      return ('problem', "Invalid Email Address");
    }
    else {
      print "<p><font color=\"#CC0000\" size=\"+1\">Invalid email address. Please try again.</font></p>\n";
      if ($query{'mode'} eq 'update_invoice') {
        print "<br><form><input type=button name=\"back_button\" value=\"Return To Previous Page\" onClick=\"javascript:history.go(-1);\"></form>\n"; 
      }
      return;
    }
  }

  if ( ($query{'enter_date_year'} >= 2000) &&
       (($query{'enter_date_month'} >= 1) && ($query{'enter_date_month'} <= 12)) &&
       (($query{'enter_date_day'} >= 1) && ($query{'enter_date_day'} <= 31)) ) {
    $query{'enter_date'} = sprintf("%04d%02d%02d", $query{'enter_date_year'}, $query{'enter_date_month'}, $query{'enter_date_day'});
  }

  if (($query{'enter_date'} eq '') || ($query{'enter_date'} < 20000101)) {
    my @now = gmtime(time);
    $query{'enter_date'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);
  }

  if ( ($query{'expire_date_year'} >= 2000) &&
       (($query{'expire_date_month'} >= 1) && ($query{'expire_date_month'} <= 12)) &&
       (($query{'expire_date_day'} >= 1) && ($query{'expire_date_day'} <= 31)) ) {
    $query{'expire_date'} = sprintf("%04d%02d%02d", $query{'expire_date_year'}, $query{'expire_date_month'}, $query{'expire_date_day'});
  }

  if (($query{'expire_date'} eq '') || ($query{'expire_date'} < 20000101)) {
    my @future = gmtime(time);
    $future[4] = $future[4] + 1; # sets 1 month into future
    if ($future[4] >= 12) {
      $future[4] = $future[4] - 12;
      $future[5] = $future[5] + 1;
    }
    $query{'expire_date'} = sprintf("%04d%02d%02d", $future[5]+1900, $future[4]+1, $future[3]);
  }

  # reject enter dates with "/" or "-" in it.
  if (($query{'enter_date'} =~ /(\/|\-)/) || (length($query{'enter_date'}) != 8)) {
    $billpay_merchadmin::count{'reject_cnt'} = $billpay_merchadmin::count{'reject_cnt'} + 1;
    $billpay_merchadmin::count{"reject_$query{'status'}"} = $billpay_merchadmin::count{"reject_$query{'status'}"} + 1;
    if ($query{'mode'} eq 'remote_update_invoice') {
      return ('problem', "Invalid Enter Date");
    }
    elsif ($query{'mode'} eq 'update_invoice') {
      print "<h3>Invoice \'$query{'invoice_no'}\' rejected. Enter Date must in format of 'YYYYMMDD'.</h3>\n";
    }
    else {
      print "<br>Invoice \'$query{'invoice_no'}\' rejected. Enter Date must be in format of 'YYYYMMDD'.\n";
      return;
    }
  }

  # reject expire_dates with "/" in it.
  if (($query{'expire_date'} =~ /(\/|\-)/) || (length($query{'expire_date'}) != 8)) {
    $billpay_merchadmin::count{'reject_cnt'} = $billpay_merchadmin::count{'reject_cnt'} + 1;
    $billpay_merchadmin::count{"reject_$query{'status'}"} = $billpay_merchadmin::count{"reject_$query{'status'}"} + 1;
    if ($query{'mode'} eq 'remote_update_invoice') {
      return ('problem', "Invalid Expire Date")
    }
    elsif ($query{'mode'} eq 'update_invoice') {
      print "<h3>Invoice \'$query{'invoice_no'}\' rejected. Expire Date must in format of 'YYYYMMDD'.</h3>\n";
    }
    else {
      print "<br>Invoice \'$query{'invoice_no'}\' rejected. Expire Date must be in format of 'YYYYMMDD'.\n";
      return;
    }
  }

  # assign unique invoice_no, if when not already defined
  if ($query{'invoice_no'} eq '') {
    my @now = gmtime(time);
    $query{'invoice_no'} = sprintf("%04d%02d%02d%02d%02d%02d%05d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0], $$);
    sleep(1);
  }

  if ($query{'invoice_no'} !~ /\w/) {
    $billpay_merchadmin::count{'reject_cnt'} = $billpay_merchadmin::count{'reject_cnt'} + 1;
    $billpay_merchadmin::count{"reject_$query{'status'}"} = $billpay_merchadmin::count{"reject_$query{'status'}"} + 1;
    if ($query{'mode'} eq 'remote_update_invoice') {
      return ('problem', "Invalid Invoice Number");
    }
    elsif ($query{'mode'} eq 'update_invoice') {
      #print "<h3>Invoice \'$query{'invoice_no'}\' rejected. Invoice No must be alphanumeric only.</h3>\n";
    }
    else {
      print "<br>Invoice \'$query{'invoice_no'}\' rejected. Invoice No must be alphanumeric only.\n";
      return;
    }
  }

  if ($query{'enter_date'} eq '') {
    my @now = gmtime(time);
    $query{'enter_date'} = sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1]);
  } 
  #$query{'enter_date'} = sprintf("%08d", $query{'enter_date'});
  #$query{'expire_date'} = sprintf("%08d", $query{'enter_date'});

  $query{'amount'} = sprintf("%0.02f", $query{'amount'});

  $query{'status'} = lc($query{'status'});
  if ($query{'status'} !~ /^(open|closed|hidden|merged|paid)$/) {
    $query{'status'} = "open";
  }

  $query{'tax'} = sprintf("%0.02f", $query{'tax'});
  $query{'shipping'} = sprintf("%0.02f", $query{'shipping'});
  $query{'handling'} = sprintf("%0.02f", $query{'handling'});
  $query{'discount'} = sprintf("%0.02f", $query{'discount'});

  if (($query{'billcycle'} > 0) && (($query{'monthly'} ne '') || ($query{'percent'} ne ''))) {
    if ($query{'percent'} ne '') {
      $query{'percent'} = sprintf("%f", $query{'percent'});
    }

    if ($query{'monthly'} ne '') {
      $query{'monthly'} = sprintf("%0.02f", $query{'monthly'});
    }

    if ($query{'remnant'} ne '') {
      $query{'remnant'} = sprintf("%0.02f", $query{'remnant'});
    }
  }
  else {
    $query{'billcycle'} = '';
    $query{'percent'} = '';
    $query{'monthly'} = '';
    $query{'remnant'} = '';
  }

  if (($query{'balance'} > 0) || (($query{'balance'} < 0) && ($billpay_merchadmin::feature_list{'billpay_allow_nbalance'} eq 'yes'))) {
    $query{'balance'} = sprintf("%0.02f", $query{'balance'});
  }
  else {
    $query{'balance'} = '';
  }

  if ($query{'shipsame'} eq 'yes') {
    $query{'shipcompany'} = "$query{'clientcompany'}";
    $query{'shipname'} = "$query{'clientname'}";
    $query{'shipaddr1'} = "$query{'clientaddr1'}";
    $query{'shipaddr2'} = "$query{'clientaddr2'}";
    $query{'shipcity'} = "$query{'clientcity'}";
    $query{'shipstate'} = "$query{'clientstate'}";
    $query{'shipzip'} = "$query{'clientzip'}";
    $query{'shipcountry'} = "$query{'clientcountry'}";
    $query{'shipphone'} = "$query{'clientphone'}";
    $query{'shipfax'} = "$query{'clientfax'}";
  }

  ## clean-up & update shipping address info, as necessary 
  if (exists $query{'shipstate'}) {
    $query{'shipstate'} = substr($query{'shipstate'},0,2);
    $query{'shipstate'} = uc($query{'shipstate'});
  }
  if (exists $query{'shipcountry'}) {
    $query{'shipcountry'} = substr($query{'shipcountry'},0,2);
    $query{'shipcountry'} = uc($query{'shipcountry'});
  }

  # perform special overwrite operations, before trying to add the new invoice
  if (($query{'overwrite'} eq 'match') && ($query{'previnvoice_no'} =~ /\w/)) {
    my @invoices = split(/\,/, $query{'previnvoice_no'});

    # now limit the previous invoice #s to 50 per SQL update, to prevent possible sql errors

    # predefine query stuff here
    my $qstr_head .= " UPDATE bills2 SET status=? WHERE username=? AND merchant=? AND invoice_no IN (";
    my @placeholder_head = ("closed", "$query{'email'}", "$billpay_merchadmin::merchant");

    # initialize some stuf here
    my $qstr_tmp = '';
    my @placeholder_tmp = ();
    my $in_cnt = 0;

    if ($#invoices >= 50) {
      ## process when 50 or more previous invoices are defined.
      my $qstr = $qstr_head . "?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
      my $sth_match = $billpay_merchadmin::dbh->prepare(qq{ $qstr }) or die "Cannot prepare: $DBI::errstr";

      for (my $i = 0; $i <= $#invoices; $i++) {
        my $previnvoice_no = shift(@invoices);
        $previnvoice_no =~ s/[^a-zA-Z0-9\-\_]//g;

        if ($previnvoice_no ne '') {
          push(@placeholder_tmp, $previnvoice_no);
          $qstr_tmp .= "?,";
          $in_cnt++;
        }

        # close the specified group of invoices, when 50 is reached
        if ($in_cnt == 50) {
          my @placeholder = (@placeholder_head, @placeholder_tmp);
          $sth_match->execute(@placeholder) or die "Cannot execute: $DBI::errstr";
          $qstr_tmp = '';
          $in_cnt = 0;
        }

        if (scalar @invoices == 0) {
          ## correct SQL statement of last group, to carry forward previous invoice remainder, if necessary.
          chop $qstr_tmp; # removes trailing ',' character
        }
      } # end of loop
      $sth_match->finish;
    } # end if
    else {
      ## process when less then 50 previous invoices are defined
      for (my $i = 0; $i <= $#invoices; $i++) {
        my $previnvoice_no = shift(@invoices);
        $previnvoice_no =~ s/[^a-zA-Z0-9\-\_]//g;

        if ($previnvoice_no ne '') {
          push(@placeholder_tmp, $previnvoice_no);
          $qstr_tmp .= "?,";
          $in_cnt++;
        }
      }
    }

    if ($qstr_tmp ne '') {
      # close the remaining specific invoices, when group is less then 50
      my $qstr = $qstr_head . $qstr_tmp . ")";
      my @placeholder = (@placeholder_head, @placeholder_tmp);
      my $sth_match = $billpay_merchadmin::dbh->prepare(qq{ $qstr }) or die "Cannot prepare: $DBI::errstr";
      $sth_match->execute(@placeholder) or die "Cannot execute: $DBI::errstr";
      $sth_match->finish;
    }
  }
  elsif ($query{'overwrite'} eq 'all') {
    # close all invoices related to given client
    my $sth_all = $billpay_merchadmin::dbh->prepare(q{
        UPDATE bills2
        SET status=?
        WHERE username=?
        AND merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth_all->execute('closed', $query{'email'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
    $sth_all->finish;
  }
  elsif (($query{'overwrite'} eq 'purge') && ($billpay_merchadmin::feature_list{'billpay_remove_invoice'} == 1)) {
    # remove all invoices related to given client
    my $sth_purge = $billpay_merchadmin::dbh->prepare(q{
        DELETE FROM bills2
        WHERE username=?
        AND merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth_purge->execute($query{'email'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
    my ($test) = $sth_purge->finish;

    if ($test ne '') {
      my $sth2_purge2 = $billpay_merchadmin::dbh->prepare(q{
          DELETE FROM billdetails2
          WHERE username=?
          AND merchant=?
        }) or die "Cannot prepare: $DBI::errstr";
      $sth2_purge2->execute($query{'email'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
      $sth2_purge2->finish;
    }
  }

  # check for invoice_no existance
  my $sth1 = $billpay_merchadmin::dbh->prepare(q{
      SELECT invoice_no 
      FROM bills2
      WHERE username=?
      AND invoice_no=?
      AND merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth1->execute($query{'email'}, $query{'invoice_no'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
  my ($db_invoice_no) = $sth1->fetchrow;
  $sth1->finish;

  if (($db_invoice_no eq "$query{'invoice_no'}") && ($query{'overwrite'} =~ /^(yes|same|match|all|purge)$/)) {
    # if match was found, allow the update to happen
    my $sth2 = $billpay_merchadmin::dbh->prepare(q{
        UPDATE bills2
        SET enter_date=?, expire_date=?, account_no=?, amount=?, status=?, orderid=?, tax=?, shipping=?, handling=?, discount=?, billcycle=?, percent=?, monthly=?, remnant=?, balance=?, public_notes=?, private_notes=?, shipname=?, shipcompany=?, shipaddr1=?, shipaddr2=?, shipcity=?, shipstate=?, shipzip=?, shipcountry=?, shipphone=?, shipfax=?, datalink_url=?, datalink_pairs=?
        WHERE username=?
        AND invoice_no=?
        AND merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute($query{'enter_date'}, $query{'expire_date'}, $query{'account_no'}, $query{'amount'}, $query{'status'}, $query{'orderid'}, $query{'tax'}, $query{'shipping'}, $query{'handling'}, $query{'discount'}, $query{'billcycle'}, $query{'percent'}, $query{'monthly'}, $query{'remnant'}, $query{'balance'}, $query{'public_notes'}, $query{'private_notes'}, $query{'shipname'}, $query{'shipcompany'}, $query{'shipaddr1'}, $query{'shipaddr2'}, $query{'shipcity'}, $query{'shipstate'}, $query{'shipzip'}, $query{'shipcountry'}, $query{'shipphone'}, $query{'shipfax'}, $query{'datalink_url'}, $query{'datalink_pairs'}, $query{'email'}, $query{'invoice_no'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    my $sth3 = $billpay_merchadmin::dbh->prepare(q{
        DELETE FROM billdetails2
        WHERE username=?
        AND invoice_no=?
        AND merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth3->execute($query{'email'}, $query{'invoice_no'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
    $sth3->finish;

    for (my $i = 1; $i <= 50; $i++) {
      # filter out unwanted characters from product data
      $query{"cost$i"} = sprintf("%0.02f", $query{"cost$i"});

      if (($query{"item$i"} ne '') && ($query{"cost$i"} =~ /\d/) && ($query{"qty$i"} > 0) && ($query{"descr$i"} ne '')) {
        my $sth4 = $billpay_merchadmin::dbh->prepare(q{
            INSERT INTO billdetails2
            (merchant, username, invoice_no, item, cost, qty, descr, weight, descra, descrb, descrc, amount)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
          }) or die "Cannot prepare: $DBI::errstr";
        $sth4->execute($billpay_merchadmin::merchant, $query{'email'}, $query{'invoice_no'}, $query{"item$i"}, $query{"cost$i"}, $query{"qty$i"}, $query{"descr$i"}, $query{"weight$i"}, $query{"descra$i"}, $query{"descrb$i"}, $query{"descrc$i"}, $query{'amount'}) or die "Cannot execute: $DBI::errstr";
        $sth4->finish;
      }
    }

    $billpay_merchadmin::count{'update_cnt'} = $billpay_merchadmin::count{'update_cnt'} + 1;
    $billpay_merchadmin::count{"update_$query{'status'}"} = $billpay_merchadmin::count{"update_$query{'status'}"} + 1;
    if ($query{'mode'} eq 'remote_update_invoice') {
      #return ('success', "Invoice Updated");
    }
    elsif ($query{'mode'} eq 'update_invoice') {
      print "<h3>Invoice \'$query{'invoice_no'}\' updated.</h3>\n";
    }
    else {
      print "<br>Invoice \'$query{'invoice_no'}\' updated.\n";
    }
    $stored_invoice = "yes";
  }
  elsif (($db_invoice_no eq "$query{'invoice_no'}") && ($query{'overwrite'} !~ /^(yes|same|match|all|purge)$/)) {
    $billpay_merchadmin::count{'reject_cnt'} = $billpay_merchadmin::count{'reject_cnt'} + 1;
    $billpay_merchadmin::count{"reject_$query{'status'}"} = $billpay_merchadmin::count{"reject_$query{'status'}"} + 1;
    if ($query{'mode'} eq 'remote_update_invoice') {
      return ('problem', "Invoice Already Exists");
    }
    elsif ($query{'mode'} eq 'update_invoice') {
      print "<h3>Invoice \'$query{'invoice_no'}\' rejected. Invoice already exists in database...</h3>\n";
    }
    else {
      print "<br>Invoice \'$query{'invoice_no'}\' rejected. Invoice already exists in database...\n";
    }
    $stored_invoice = "no";
  }
  else {
    # if no match was found, allow the insert to happen
    my $sth2 = $billpay_merchadmin::dbh->prepare(q{
        INSERT INTO bills2
        (merchant, username, invoice_no, enter_date, expire_date, account_no, amount, status, orderid, tax, shipping, handling, discount, billcycle, percent, monthly, remnant, balance, public_notes, private_notes, shipname, shipcompany, shipaddr1, shipaddr2, shipcity, shipstate, shipzip, shipcountry, shipphone, shipfax, datalink_url, datalink_pairs)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute($billpay_merchadmin::merchant, $query{'email'}, $query{'invoice_no'}, $query{'enter_date'}, $query{'expire_date'}, $query{'account_no'}, $query{'amount'}, $query{'status'}, $query{'orderid'}, $query{'tax'}, $query{'shipping'}, $query{'handling'}, $query{'discount'}, $query{'billcycle'}, $query{'percent'}, $query{'monthly'}, $query{'remnant'}, $query{'balance'}, $query{'public_notes'}, $query{'private_notes'}, $query{'shipname'}, $query{'shipcompany'}, $query{'shipaddr1'}, $query{'shipaddr2'}, $query{'shipcity'}, $query{'shipstate'}, $query{'shipzip'}, $query{'shipcountry'}, $query{'shipphone'}, $query{'shipfax'}, $query{'datalink_url'}, $query{'datalink_pairs'}) or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    for (my $i = 1; $i <= 50; $i++) {
      # filter out unwanted characters from product data
      $query{"cost$i"} = sprintf("%0.02f", $query{"cost$i"});

      if (($query{"item$i"} ne '') && ($query{"cost$i"} =~ /\d/) && ($query{"qty$i"} > 0) && ($query{"descr$i"} ne '')) {
        my $sth = $billpay_merchadmin::dbh->prepare(q{
            INSERT INTO billdetails2
            (merchant, username, invoice_no, item, cost, qty, descr, weight, descra, descrb, descrc, amount)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
          }) or die "Cannot prepare: $DBI::errstr";
        $sth->execute($billpay_merchadmin::merchant, $query{'email'}, $query{'invoice_no'}, $query{"item$i"}, $query{"cost$i"}, $query{"qty$i"}, $query{"descr$i"}, $query{"weight$i"}, $query{"descra$i"}, $query{"descrb$i"}, $query{"descrc$i"}, $query{'amount'}) or die "Cannot execute: $DBI::errstr";
        $sth->finish;
      }
    }

    $billpay_merchadmin::count{'add_cnt'} = $billpay_merchadmin::count{'add_cnt'} + 1;
    $billpay_merchadmin::count{"add_$query{'status'}"} = $billpay_merchadmin::count{"add_$query{'status'}"} + 1;
    if ($query{'mode'} eq 'remote_update_invoice') {
      #return ('success', "Invoice Successfully Added");
    }
    elsif ($query{'mode'} eq 'update_invoice') {
      print "<h3>Invoice \'$query{'invoice_no'}\' added.</h3>\n";
    }
    else {
      print "<br>Invoice \'$query{'invoice_no'}\' added.\n";
    }
    $stored_invoice = "yes";
  }

  if ($stored_invoice eq 'yes') {
    ## clean-up & update client contact info, as necessary 
    if (exists $query{'clientstate'}) {
      $query{'clientstate'} = substr($query{'clientstate'},0,2);
      $query{'clientstate'} = uc($query{'clientstate'});
    }
    if (exists $query{'clientcountry'}) {
      $query{'clientcountry'} = substr($query{'clientcountry'},0,2);
      $query{'clientcountry'} = uc($query{'clientcountry'});
    }
    if (exists $query{'alias'}) {
      $query{'alias'} = lc($query{'alias'});
    }
    if (exists $query{'consolidate'}) {
      $query{'consolidate'} =~ s/^(yes)$//g;
    }

    # start by checking for client existance
    my $sth1a = $billpay_merchadmin::dbh->prepare(q{
        SELECT username
        FROM client_contact
        WHERE username=?
        AND merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    my $rc = $sth1a->execute($query{'email'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
    my ($db_username) = $sth1a->fetchrow;
    $sth1a->finish;

    if ($db_username eq "$query{'email'}") {
      if (($query{'clientname'} ne '') || ($query{'clientcompany'} ne '')) {
        # if match was found, allow the update to happen
        # * Notes: - Only allow update to happen, when clientname or clientcompany is defined
        #          - We don't want to overwrite existing client contact info, when the details are undefined.
        #          - We do however want to update the contact info if it's defined, as we assume all the details were provided 
        #          - Bascially it's an all or nothing update process.
        my $sth2a = $billpay_merchadmin::dbh->prepare(q{
            UPDATE client_contact
            SET clientname=?, clientcompany=?, clientaddr1=?, clientaddr2=?, clientcity=?, clientstate=?, clientzip=?, clientcountry=?, clientphone=?, clientfax=?, alias=?
            WHERE username=?
            AND merchant=?
          }) or die "Cannot prepare: $DBI::errstr";
        $sth2a->execute($query{'clientname'}, $query{'clientcompany'}, $query{'clientaddr1'}, $query{'clientaddr2'}, $query{'clientcity'}, $query{'clientstate'}, $query{'clientzip'}, $query{'clientcountry'}, $query{'clientphone'}, $query{'clientfax'}, $query{'alias'}, $query{'email'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
        $sth2a->finish;
      }
    }
    else {
      # if no match was found, allow the insert to happen
      my $sth2a = $billpay_merchadmin::dbh->prepare(q{
          INSERT INTO client_contact
          (merchant, username, clientname, clientcompany, clientaddr1, clientaddr2, clientcity, clientstate, clientzip, clientcountry, clientphone, clientfax, alias, consolidate)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        }) or die "Cannot prepare: $DBI::errstr";
      $sth2a->execute($billpay_merchadmin::merchant, $query{'email'}, $query{'clientname'}, $query{'clientcompany'}, $query{'clientaddr1'}, $query{'clientaddr2'}, $query{'clientcity'}, $query{'clientstate'}, $query{'clientzip'}, $query{'clientcountry'}, $query{'clientphone'}, $query{'clientfax'}, $query{'alias'}, $query{'consolidate'}) or die "Cannot execute: $DBI::errstr";
      $sth2a->finish;
    }
  }

  if (($query{'email_cust'} eq 'yes') && ($query{'status'} ne 'hidden') && ($stored_invoice eq 'yes')) {
    if ($billpay_merchadmin::feature_list{'billpay_email_format'} eq 'text') {
      &email_customer_text(%query);
    }
    else {
      &email_customer_html(%query);
    }
  }

  if ($query{'mode'} eq 'remote_update_invoice') {
    return ('success', "Invoice Successfully Stored");
  }
  elsif ($query{'mode'} eq 'update_invoice') {
    print "<p><form action=\"$ENV{'SCRIPT_NAME'}\" method=post><input type=submit class=\"button\" value=\"Main Menu\"></form>\n";
  }
}

sub email_customer_text {
  my %query = @_;

  # prevent email from being sent to sudo email addresses
  if ($query{'email'} =~ /(\.pnp)$/) {
    return;
  }

  # TODO: Implement way to detect/filter sensitive data (such as full CC#s) when performing field substitutions.

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setGatewayAccount($billpay_merchadmin::merchant);

  # send email to customer

  $emailObj->setTo($query{'email'});

  if ($billpay_merchadmin::feature_list{'billpay_email_merch'} eq 'yes') {
    if ($query{'merch_pubemail'} ne '') {
      $emailObj->setBCC($query{'merch_pubemail'});
    } else {
      $emailObj->setBCC($billpay_merchadmin::feature_list{'pubemail'});
    }
  }

  if ($query{'merch_pubemail'} ne '') {
    $emailObj->setFrom($query{'merch_pubemail'});
  } elsif ($billpay_merchadmin::feature_list{'pubemail'} ne '') {
    $emailObj->setFrom(billpay_merchadmin::feature_list{'pubemail'});
  } else {
    $emailObj->setFrom('billpaysupport@plugnpay.com');
  }

  my $subject = $billpay_language::lang_titles{'emailcust_text_subject'};
  $subject =~ s/\[pnp_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
  $emailObj->setSubject($subject);

  my $emailmessage = '';

  if ($billpay_language::template{'emailcust_text_emailmessage'} =~ /\w/) {
    # Use this to replace our default message with a custom formatted email notification.
    $emailmessage .= "$billpay_language::template{'emailcust_text_emailmessage'}\n";
  } else {    
    $emailmessage .= "$billpay_language::lang_titles{'emailcust_text_new_invoice'}\n";
    $emailmessage .= "\n\n";

    $emailmessage .= "$billpay_language::lang_titles{'merchant'} [pnp_merch_company]\n";
    $emailmessage .= "$billpay_language::lang_titles{'email'} [pnp_email]\n";
    $emailmessage .= "$billpay_language::lang_titles{'invoice_no'} [pnp_invoice_no]\n";
    if ($query{'account_no'} =~ /\w/) {
      $emailmessage .= "$billpay_language::lang_titles{'account_no'} [pnp_account_no]\n"; 
    }
    #$emailmessage .= sprintf ("$billpay_language::lang_titles{'enterdate'} %02d\/%02d\/%04d\n", substr($query{'enter_date'},4,2), substr($query{'enter_date'},6,2), substr($query{'enter_date'},0,4));
    $emailmessage .= sprintf ("$billpay_language::lang_titles{'expiredate'} %02d\/%02d\/%04d\n", substr($query{'expire_date'},4,2), substr($query{'expire_date'},6,2), substr($query{'expire_date'},0,4));

    $emailmessage .= "$billpay_language::lang_titles{'amount'} [pnp_amount]\n";
    $emailmessage .= "$billpay_language::lang_titles{'status'} [pnp_status]\n";

    if (($query{'monthly'} > 0) || ($query{'percent'} > 0)) {
      if ($query{'percent'} > 0) {
        $emailmessage .= "$billpay_language::lang_titles{'percentage'} [pnp_percent]\n";
        if ($query{'monthly'} > 0) {
          $emailmessage .= "$billpay_language::lang_titles{'installment_min'} [pnp_monthly]\n";
        }
      } else {
        $emailmessage .= "$billpay_language::lang_titles{'monthly'} [pnp_monthly]\n";
      }

      if ($query{'remnant'} > 0) {
        $emailmessage .= "$billpay_language::lang_titles{'remnant'} [pnp_remnant]\n";
      }
    }

    if (($query{'balance'} > 0) || (($query{'balance'} < 0) && ($billpay_merchadmin::feature_list{'billpay_allow_nbalance'} eq 'yes'))) {
      $emailmessage .= "$billpay_language::lang_titles{'balance'} [pnp_balance]\n";
    }

    $emailmessage .= "\n";
    $emailmessage .= "$billpay_language::lang_titles{'emailcust_text_view_invoice'}\n";
    $emailmessage .= "https://$ENV{'SERVER_NAME'}/billpay/edit.cgi\?function\=view_bill_details_form\&invoice_no\=[pnp_invoice_no]\n"; 

    $emailmessage .= "\n";
    $emailmessage .= "$billpay_language::lang_titles{'emailcust_text_free_signup'}\n";
    $emailmessage .= "https://$ENV{'SERVER_NAME'}/billpay_signup.cgi\?merchant\=$billpay_merchadmin::merchant\n";

    $emailmessage .= "\n";
    $emailmessage .= "$billpay_language::lang_titles{'emailcust_text_signup_reason'}\n";

    if ($query{'express_pay'} eq 'yes') {
      $emailmessage .= "\n";
      $emailmessage .= "$billpay_language::lang_titles{'emailcust_text_expresspay'}\n";
      $emailmessage .= "https://$ENV{'SERVER_NAME'}/billpay_express.cgi\?merchant\=$billpay_merchadmin::merchant\&email\=[pnp_email]\&invoice_no\=[pnp_invoice_no]\n";
    }

    $emailmessage .= "\n";
    if ($query{'merch_pubemail'} ne '') {
      $emailmessage .= "$billpay_language::lang_titles{'emailcust_text_contact_merch2'}\n\n";
    }
    else {
      $emailmessage .= "$billpay_language::lang_titles{'emailcust_text_contact_merch1'}\n\n";
    }

    $emailmessage .= "$billpay_language::lang_titles{'emailcust_text_thankyou'}\n\n";
  }

  $emailmessage =~ s/\[pnp_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);

  $emailObj->setContent($emailmessage);
  $emailObj->send();

  return;
}

sub export_file {
  my $type = shift;
  my %query = @_;

  my $eol = ''; # set end of line break character
  if ($billpay_merchadmin::feature_list{'billpay_filetype'} eq 'dos') {
    $eol = "\r\n";
  }
  elsif ($billpay_merchadmin::feature_list{'billpay_filetype'} eq 'mac') {
    $eol = "\r";
  }
  else { # use unix default
    $eol = "\n";
  }

  if ($query{'format'} =~ /^(table)$/) {
    print "Content-Type: text/html\n";
    print "X-Content-Type-Options: nosniff\n";
    print "X-Frame-Options: SAMEORIGIN\n\n";
    &html_head('Exported Invoices');
    print "<div align=left>\n";
  }
  elsif ($query{'format'} =~ /^(text)$/) {
    print "Content-Type: text/plain\n";
    print "X-Content-Type-Options: nosniff\n";
    print "X-Frame-Options: SAMEORIGIN\n\n";
  }
  else {
    print "Content-Type: text/tab-separated-values\n";
    print "X-Content-Type-Options: nosniff\n";
    print "X-Frame-Options: SAMEORIGIN\n";
    print "Content-Disposition: attachment; filename=\"export.txt\"\n\n";
  }

  # get merchant's company name
  my $dbh_pnpmisc = &miscutils::dbhconnect("pnpmisc");
  my $sth2 = $dbh_pnpmisc->prepare(q{
      SELECT company
      FROM customers
      WHERE username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth2->execute($billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
  my ($db_merch_company) = $sth2->fetchrow;
  $sth2->finish;
  $dbh_pnpmisc->disconnect;

  my $count = 0;

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my @now2 = gmtime(time + 86400);
  my $tomorrow = sprintf("%04d%02d%02d", $now2[5]+1900, $now2[4]+1, $now2[3]);

  my $startdate = sprintf("%04d%02d%02d", $query{'startyear'}, $query{'startmonth'}, $query{'startday'});
  my $enddate = sprintf("%04d%02d%02d", $query{'endyear'}, $query{'endmonth'}, $query{'endday'});

  if ($startdate < 20060101) {
    $startdate = 20060101;
  }
  if ($enddate > $today) {
    $enddate = $tomorrow;
  }
  if ($enddate < $startdate) {
    my $old_startdate = $startdate;
    $startdate = $enddate;
    $enddate = $old_startdate;
  }

  if ($query{'status'} !~ /(open|expired|closed|hidden|merged|paid|unpaid)/) {
    $query{'status'} = '';
  }

  my $data_header = ''; # holds header line for text/download format
  my $data_max    = 0;  # holds count of max number of itemized products found within a single invoice 
  my %data_export = (); # holds exported invice data, for text/download format

  if ($query{'format'} !~ /^(table)$/) {
    $data_header .= "!BATCH\temail\tinvoice_no\tenter_date\texpire_date\taccount_no\tamount\tstatus\ttax\tshipping\thandling\tdiscount\tbillcycle\tpercent\tmonthly\tremnant\tbalance\tlastbilled\tlastattempted\torderid\tpublic_notes\tprivate_notes\tdatalink_url\tdatalink_pairs\t";

    # include shipping info in invoice export
    $data_header .= "shipname\tshipcompany\tshipaddr1\tshipaddr2\tshipcity\tshipstate\tshipzip\tshipcountry\tshipphone\tshipfax\t";

    # include contact info in invoice export
    $data_header .= "clientname\tclientcompany\tclientaddr1\tclientaddr2\tclientcity\tclientstate\tclientzip\tclientcountry\tclientphone\tclientfax\tclientid\tconsolidate\talias\t";
  }

  my @placeholder;

  my $qstr = "SELECT *";
  $qstr .= " FROM bills2";
  $qstr .= " WHERE merchant=?";
  push(@placeholder, "$billpay_merchadmin::merchant");

  if ($query{'status'} ne '') {
    if ($query{'status'} eq 'expired') {
      $query{'status'} = "open";
      $qstr .= " AND status=? AND expire_date<=?";
      push(@placeholder, "$query{'status'}", "$today");
    }
    elsif ($query{'status'} eq 'unpaid') {
      $query{'status'} = "open";
      $qstr .= " AND status=? AND expire_date>? AND (balance>0 OR orderid=?)";
      push(@placeholder, "$query{'status'}", "$today", '');
    }
    else {
      $qstr .= " AND status=?";
      push(@placeholder, "$query{'status'}");
    }
  }

  if ($query{'invoices'} eq 'enter_date') {
    # limit exported invoices to only those within the enter date range
    $qstr .= " AND enter_date>=? AND enter_date<=?";
    push(@placeholder, "$startdate", "$enddate");
  }
  elsif ($query{'invoices'} eq 'expire_date') {
    # limit exported invoices to only those within the expire date range
    $qstr .= " AND expire_date>=? AND expire_date<=?";
    push(@placeholder, "$startdate", "$enddate");
  }

  $qstr .= " ORDER BY enter_date";

  my $sth = $billpay_merchadmin::dbh->prepare(qq{ $qstr }) or die "Cannot do: $DBI::errstr";
  my $rc = $sth->execute(@placeholder) or die "Cannot execute: $DBI::errstr";
  while (my $invoice = $sth->fetchrow_hashref()) {
    my %invoice;
    foreach my $key (keys %{$invoice}) {
      $invoice{"$key"} = $invoice->{"$key"};
    }

    # get client contact info
    my %data2 = &get_client_contact_data(%invoice);
    %invoice = (%invoice, %data2);

    if ($invoice{'merchant'} eq "$billpay_merchadmin::merchant") {
      $count = $count + 1;

      $invoice{'amount'} = sprintf("%0.02f", $invoice{'amount'});
      $invoice{'tax'} = sprintf("%0.02f", $invoice{'tax'});
      $invoice{'shipping'} = sprintf("%0.02f", $invoice{'shipping'});
      $invoice{'handling'} = sprintf("%0.02f", $invoice{'handling'});
      $invoice{'discount'} = sprintf("%0.02f", $invoice{'discount'});

      if ($invoice{'account_no'} eq '') { $invoice{'account_no'} = "&nbsp;"; }

      if ($invoice{'status'} eq '') { $invoice{'status'} = "open"; }

      if ($invoice{'billcycle'} eq '') { $invoice{'billcycle'} = "&nbsp;"; }
        else { $invoice{'billcycle'} = sprintf("%d", $invoice{'billcycle'}); }

      if ($invoice{'percent'} eq '') {
        $invoice{'percent'} = "&nbsp;";
      } 
      else {
        $invoice{'percent'} = sprintf("%f", $invoice{'percent'});
      }

      if ($invoice{'monthly'} eq '') {
        $invoice{'monthly'} = "&nbsp;";
      } 
      else {
        $invoice{'monthly'} = sprintf("%0.02f", $invoice{'monthly'});
      }

      if ($invoice{'remnant'} eq '') {
        $invoice{'remnant'} = "&nbsp;";
      }
      else {
        $invoice{'remnant'} = sprintf("%0.02f", $invoice{'remnant'});
      }

      if ($invoice{'balance'} eq '') {
        $invoice{'balance'} = "&nbsp;";
      }
      else {
        $invoice{'balance'} = sprintf("%0.02f", $invoice{'balance'});
      }

      if ($invoice{'orderid'} eq '') { $invoice{'orderid'} = "&nbsp;"; } 

      if ($query{'format'} =~ /^(table)$/) {

        print "<div align=left><table border=1 cellspacing=0 cellpadding=2 width=760>\n";
        print "  <tr class=\"sectiontitle\">\n";
        print "    <th colspan=10 align=right><!-- $count -->\n";

        print "<table border=0>\n";
        print "  <tr>\n";

        print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
        print "<input type=hidden name=\"mode\" value=\"view_invoice\">\n";
        print "<input type=hidden name=\"email\" value=\"$invoice{'username'}\">\n";
        print "<input type=hidden name=\"invoice_no\" value=\"$invoice{'invoice_no'}\">\n";
        print "<input type=submit class=\"button\" value=\"View\">\n";
        print "</td></form>\n";

        if ($ENV{'SEC_LEVEL'} <= 4) {
          print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
          print "<input type=hidden name=\"mode\" value=\"edit_invoice\">\n";
          print "<input type=hidden name=\"email\" value=\"$invoice{'username'}\">\n";
          print "<input type=hidden name=\"invoice_no\" value=\"$invoice{'invoice_no'}\">\n";
          print "<input type=submit class=\"button\" value=\"Edit\">\n";
          print "</td></form>\n";
        }

        if ($billpay_merchadmin::feature_list{'billpay_remove_invoice'} == 1) {
          if ($ENV{'SEC_LEVEL'} <= 4) {
            print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
            print "<input type=hidden name=\"mode\" value=\"delete_invoice\">\n";
            print "<input type=hidden name=\"email\" value=\"$invoice{'username'}\">\n";
            print "<input type=hidden name=\"invoice_no\" value=\"$invoice{'invoice_no'}\">\n";
            print "<input type=submit class=\"button\" value=\"Remove\">\n";
            print "</td></form>\n";
          }
        }

        if (($invoice{'expire_date'} > $today) && (($invoice{'status'} eq '') || ($invoice{'status'} eq 'open'))) {
          if ($ENV{'SEC_LEVEL'} <= 8) {
            print "    <td><form method=post action=\"/billpay_express.cgi\" target=\"billpay\">\n";
            print "<input type=hidden name=\"merchant\" value=\"$billpay_merchadmin::merchant\">\n";
            print "<input type=hidden name=\"cobrand\" value=\"$billpay_merchadmin::query{'merch_company'}\">\n";
            print "<input type=hidden name=\"email\" value=\"$invoice{'username'}\">\n";
            print "<input type=hidden name=\"invoice_no\" value=\"$invoice{'invoice_no'}\">\n";
            print "<input type=submit class=\"button\" value=\"Express Pay\">\n";
            print "</td></form>\n";
          }
        }

        print "  </tr>\n";
        print "</table>\n";

        print "</th>\n";
        print "  </tr>\n";

        print "  <tr class=\"listrow_color0\">\n";
        print "    <th>Merchant</th>\n";
        print "    <th>Email</th>\n";
        print "    <th>Invoice No</th>\n";
        print "    <th>Enter Date</th>\n";
        print "    <th>Expire Date</th>\n";
        print "    <th>Account No</th>\n";
        print "    <th>Amount</th>\n";
        print "    <th>Status</th>\n";
        print "    <th colspan=2>OrderID</th>\n";
        print "  </tr>\n";

        print "  <tr>\n";
        print "    <td>$db_merch_company</td>\n";
        print "    <td>$invoice{'username'}</td>\n";
        print "    <td>$invoice{'invoice_no'}</td>\n";
        printf ("    <td>%02d\/%02d\/%04d</td>\n", substr($invoice{'enter_date'},4,2), substr($invoice{'enter_date'},6,2), substr($invoice{'enter_date'},0,4));
        printf ("    <td>%02d\/%02d\/%04d</td>\n", substr($invoice{'expire_date'},4,2), substr($invoice{'expire_date'},6,2), substr($invoice{'expire_date'},0,4));
        print "    <td>$invoice{'account_no'}</td>\n";
        print "    <td>$invoice{'amount'}</td>\n";
        print "    <td>$invoice{'status'}</td>\n";
        print "    <td colspan=2>$invoice{'orderid'}</td>\n";
        print "  </tr>\n";

        print "  <tr class=\"listrow_color0\">\n";
        print "    <th colspan=4>Client Contact</th>\n";
        print "    <th colspan=6>Shipping Contact</th>\n";
        print "  </tr>\n";

        print "  <tr>\n";
        print "    <td colspan=4>\n";
        if ($invoice{'clientcompany'} ne '') {
          print "$invoice{'clientcompany'}<br>\n";
        }
        if ($invoice{'clientname'} ne '') {
          print "$invoice{'clientname'}<br>\n";
        }
        if ($invoice{'clientaddr1'} ne '') {
          print "$invoice{'clientaddr1'}<br>\n";
        }
        if ($invoice{'clientaddr2'} ne '') {
          print "$invoice{'clientaddr2'}<br>\n";
        }
        if (($invoice{'clientcity'} ne '') || ($invoice{'clientstate'} ne '') || ($invoice{'clientzip'} ne '') || ($invoice{'clientcountry'} ne '')) {
          print "$invoice{'clientcity'} $invoice{'clientstate'} $invoice{'clientzip'} $invoice{'clientcountry'}<br>\n";
        }
        if (($invoice{'clientphone'} ne '') || ($invoice{'clientfax'} ne '')) {
          print "Phone: $invoice{'clientphone'} &nbsp; Fax: $invoice{'clientfax'}\n";
        }
        print "</td>\n";

        print "    <td colspan=6>\n";
        if ($invoice{'shipcompany'} ne '') {
          print "$invoice{'shipcompany'}<br>\n";
        }
        if ($invoice{'shipname'} ne '') {
          print "$invoice{'shipname'}<br>\n";
        }
        if ($invoice{'shipaddr1'} ne '') {
          print "$invoice{'shipaddr1'}<br>\n";
        }
        if ($invoice{'shipaddr2'} ne '') {
          print "$invoice{'shipaddr2'}<br>\n";
        }
        if (($invoice{'shipcity'} ne '') || ($invoice{'shipstate'} ne '') || ($invoice{'shipzip'} ne '') || ($invoice{'shipcountry'} ne '')) {
          print "$invoice{'shipcity'} $invoice{'shipstate'} $invoice{'shipzip'} $invoice{'shipcountry'}<br>\n";
        }
        if (($invoice{'shipphone'} ne '') || ($invoice{'shipfax'} ne '')) {
          print "Phone: $invoice{'shipphone'} &nbsp; Fax: $invoice{'shipfax'}\n";
        }
        print "</td>\n";
        print "  </tr>\n";

        print "  <tr class=\"listrow_color0\">\n";
        print "    <th>Tax</th>\n";
        print "    <th>Shipping</th>\n";
        print "    <th>Handling</th>\n";
        print "    <th>Discount</th>\n";
        print "    <th>Billing Cycle</th>\n";
        print "    <th>Percent</th>\n";
        print "    <th>Monthly</th>\n";
        print "    <th>Remnant</th>\n";
        print "    <th>Balance</th>\n";
        print "    <th>Last Billed</th>\n";
        print "    <th>Last Attempted</th>\n";
        print "  </tr>\n";

        print "  <tr>\n";
        print "    <td>$invoice{'tax'}</td>\n";
        print "    <td>$invoice{'shipping'}</td>\n";
        print "    <td>$invoice{'handling'}</td>\n";
        print "    <td>$invoice{'discount'}</td>\n";
        print "    <td>$invoice{'billcycle'}</td>\n";
        print "    <td>$invoice{'percent'}</td>\n";
        print "    <td>$invoice{'monthly'}</td>\n";
        print "    <td>$invoice{'remnant'}</td>\n";
        print "    <td>$invoice{'balance'}</td>\n";
        if ($invoice{'lastbilled'} ne '') {
          printf ("    <td>%02d\/%02d\/%04d</td>\n", substr($invoice{'lastbilled'},4,2), substr($invoice{'lastbilled'},6,2), substr($invoice{'lastbilled'},0,4));
        }
        else {
          print "    <td>&nbsp;</td>\n";
        }
        if ($invoice{'lastattempted'} ne '') {
          printf ("    <td>%02d\/%02d\/%04d</td>\n", substr($invoice{'lastattempted'},4,2), substr($invoice{'lastattempted'},6,2), substr($invoice{'lastattempted'},0,4));
        }
        else {
          print "    <td>&nbsp;</td>\n";
        }
        print "  </tr>\n";

        #print "  <tr>\n";
        #print "    <th colspan=11><hr width=\"80%\"></th>\n";
        #print "  </tr>\n";

        if ($invoice{'datalink_url'} ne '') {
          if ($billpay_merchadmin::feature_list{'billpay_datalink_type'} =~ /^(post|get)$/) {
            # use datalink form post/get format
            print "  <tr class=\"listrow_color0\">\n";
            print "    <th colspan=2>$billpay_language::lang_titles{'datalink'}</th>\n";
            print "    <td colspan=8 class=\"listrow_color1\"><form name=\"datalink\" action=\"$invoice{'datalink_url'}\" method=\"$billpay_merchadmin::feature_list{'billpay_datalink_type'}\" target=\"_blank\">\n";
            if ($invoice{'datalink_pairs'} ne '') {
              my @pairs = split(/\&/, $invoice{'datalink_pairs'});
              for (my $i = 0; $i <= $#pairs; $i++) {
                my $pair = $pairs[$i];
                $pair =~ s/\[client_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;
                $pair =~ s/\[invoice_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;
                $pair =~ s/\[query_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;
                my ($name, $value) = split(/\=/, $pair, 2);
                print "<input type=hidden name=\"$name\" value=\"$value\">\n";
              }
            }
            print "<input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_datalink'}\"></form></th>\n";
            print "  </tr>\n";
          }
          else {
            # use datalink link format
            my $url = $invoice{'datalink_url'};
            if ($invoice{'datalink_pairs'} ne '') {
              $url .= "\?" . $invoice{'datalink_pairs'};
            }
            $url =~ s/\[client_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;
            $url =~ s/\[invoice_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;
            $url =~ s/\[query_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;

            print "  <tr class=\"listrow_color0\">\n";
            print "    <th colspan=2>$billpay_language::lang_titles{'datalink'}</th>\n";
            print "    <td colspan=8 class=\"listrow_color1\"><a href=\"$url\" target=\"_blank\">$billpay_language::lang_titles{'link_datalink'}</a></td>\n";
            print "  </tr>\n";
          }
        }

        if ($invoice{'public_notes'} ne '') {
          print "  <tr class=\"listrow_color0\">\n";
          print "    <th colspan=2>Public Notes</th>\n";
          print "    <td colspan=8 class=\"listrow_color1\">$invoice{'public_notes'}</td>\n";
          print "  </tr>\n";
        }

        if ($invoice{'private_notes'} ne '') {
          print "  <tr class=\"listrow_color0\">\n";
          print "    <th colspan=2>Private Notes</th>\n";
          print "    <td colspan=8 class=\"listrow_color1\">$invoice{'private_notes'}</td>\n";
          print "  </tr>\n";
        }
      }
      else {
        if ($invoice{'datalink_pairs'} ne '') {
          $invoice{'datalink_pairs'} =~ s/\[client_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;
          $invoice{'datalink_pairs'} =~ s/\[invoice_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;
          $invoice{'datalink_pairs'} =~ s/\[query_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;
        }

        my @list = ("$invoice{'username'}", "$invoice{'invoice_no'}", "$invoice{'enter_date'}", "$invoice{'expire_date'}", "$invoice{'account_no'}", "$invoice{'amount'}", "$invoice{'status'}", "$invoice{'tax'}", "$invoice{'shipping'}", "$invoice{'handling'}", "$invoice{'discount'}", "$invoice{'billcycle'}", "$invoice{'percent'}", "$invoice{'monthly'}", "$invoice{'remnant'}", "$invoice{'balance'}", "$invoice{'lastbilled'}", "$invoice{'lastattempted'}", "$invoice{'orderid'}", "$invoice{'public_notes'}", "$invoice{'private_notes'}", "$invoice{'datalink_url'}", "$invoice{'datalink_pairs'}");

        # include shipping contact info
        push(@list, "$invoice{'shipname'}", "$invoice{'shipcompany'}", "$invoice{'shipaddr1'}", "$invoice{'shipaddr2'}", "$invoice{'shipcity'}", "$invoice{'shipstate'}", "$invoice{'shipzip'}", "$invoice{'shipcountry'}", "$invoice{'shipphone'}", "$invoice{'shipfax'}");

        # include client contact info
        push(@list, "$invoice{'clientname'}", "$invoice{'clientcompany'}", "$invoice{'clientaddr1'}", "$invoice{'clientaddr2'}", "$invoice{'clientcity'}", "$invoice{'clientstate'}", "$invoice{'clientzip'}", "$invoice{'clientcountry'}", "$invoice{'clientphone'}", "$invoice{'clientfax'}", "$invoice{'clientid'}", "$invoice{'consolidate'}", "$invoice{'alias'}");

        my $tmp = "billpay_invoice\t";
        for (my $z = 0; $z <= $#list; $z++) {
          $tmp .= "$list[$z]\t";
        }
        $tmp =~ s/\t\&nbsp\;/\t/g;
        $tmp =~ s/(\r|\n|\r\n)/  /g;

        $data_export{"$count"} = $tmp;
      }

      my $sth2 = $billpay_merchadmin::dbh->prepare(q{
          SELECT *
          FROM billdetails2
          WHERE merchant=?
          AND username=?
          AND invoice_no=?
          ORDER BY item
        }) or die "Cannot do: $DBI::errstr";
      my $rc = $sth2->execute($invoice{'merchant'}, $invoice{'username'}, $invoice{'invoice_no'}) or die "Cannot execute: $DBI::errstr";

      if ($rc >= 1) {
        if ($query{'format'} =~ /^(table)$/) {
          print "  <tr class=\"listrow_color0\">\n";
          print "    <th colspan=2>$billpay_language::lang_titles{'column_item'}</th>\n";
          print "    <th colspan=1>$billpay_language::lang_titles{'column_cost'}</th>\n";
          print "    <th colspan=1>$billpay_language::lang_titles{'column_qty'}</th>\n";
          print "    <th colspan=6>$billpay_language::lang_titles{'column_descr'}</th>\n";
          if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) {
            print "    <th>$billpay_language::lang_titles{'column_weight'}</th>\n";
          }
          if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) {
            print "    <th>$billpay_language::lang_titles{'column_descra'}</th>\n";
          }
          if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) {
            print "    <th>$billpay_language::lang_titles{'column_descrb'}</th>\n";
          }
          if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) {
            print "    <th>$billpay_language::lang_titles{'column_descrc'}</th>\n";
          }
          print "  </tr>\n";
        }
        elsif ($rc > $data_max) {
          $data_max = $rc;
        }

        while (my $product = $sth2->fetchrow_hashref()) {
          my %product;
          foreach my $key (keys %{$product}) {
            $product{"$key"} = $product->{"$key"};
          }

          if (($product{'item'} ne '') && ($product{'cost'} =~ /\d/) && ($product{'qty'} > 0) && ($product{'descr'} ne '')) {

            $product{'cost'} = sprintf("%0.02f", $product{'cost'});

            if ($query{'format'} =~ /^(table)$/) {
              print "  <tr>\n";
              print "    <td colspan=2>$product{'item'}</td>\n";
              print "    <td colspan=1>$product{'cost'}</td>\n";
              print "    <td colspan=1>$product{'qty'}</td>\n";
              print "    <td colspan=6>$product{'descr'}</td>\n";
              if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) {
                print "    <td>$product{'weight'}</td>\n";
              }
              if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) {
                print "    <td>$product{'descra'}</td>\n";
              }
              if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) {
                print "    <td>$product{'descrb'}</td>\n";
              }
              if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) {
                print "    <td>$product{'descrc'}</td>\n";
              }
              print "  </tr>\n";
            }
            else {
              $data_export{"$count"} .= "$product{'item'}\t$product{'cost'}\t$product{'qty'}\t$product{'descr'}\t";
              if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) {
                $data_export{"$count"} .= "$product{'weight'}\t";
              }
              if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) {
                $data_export{"$count"} .= "$product{'descra'}\t";
              }
              if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) {
                $data_export{"$count"} .= "$product{'descrb'}\t";
              }
              if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) {
                $data_export{"$count"} .= "$product{'descrc'}\t";
              }
            }
          }
        }
      }
      $sth2->finish;

      if ($query{'format'} =~ /^(table)$/) {
        print "</table></div>\n";
        #print "<hr width=\"75%\">\n";
        print "\n<br>&nbsp;\n\n";
      }
      else {
        chop $data_export{"$count"}; 
        $data_export{"$count"} .= "$eol";
      }
    }
  }
  $sth->finish;

  if ($query{'format'} =~ /^(table)$/) {
    print "</div>\n";
    &html_tail();
  }
  else {
    if ($data_max > 0) {
      for (my $i = 1; $i <= $data_max; $i++) {
        $data_header .= "item$i\tcost$i\tqty$i\tdescr$i\t";
        if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) {
          $data_header .= "weight$i\t";
        }
        if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) {
          $data_header .= "descra$i\t";
        }
        if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) {
          $data_header .= "descrb$i\t";
        }
        if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) {
          $data_header .= "descrc$i\t";
        }
      }
    }
    chop $data_header;
    $data_header .= "$eol";

    print $data_header;
    foreach my $key (sort keys %data_export) {
      print $data_export{"$key"};
    }
  }

  return;
}

sub get_invoice_data {
  my %query = @_;

  my %data;

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT *
      FROM bills2
      WHERE merchant=?
      AND username=?
      AND invoice_no=?
      ORDER BY invoice_no
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($billpay_merchadmin::merchant, $query{'email'}, $query{'invoice_no'}) or die "Can't execute: $DBI::errstr";
  my $ref = $sth->fetchrow_hashref();
  foreach my $key (keys %{$ref}) {
    $data{$key} = $ref->{$key};
  }
  $sth->finish;

  my $i = 1;

  my $sth2 = $billpay_merchadmin::dbh->prepare(q{
      SELECT item, cost, qty, descr, weight, descra, descrb, descrc
      FROM billdetails2
      WHERE merchant=?
      AND username=?
      AND invoice_no=?
      ORDER BY item
    }) or die "Cannot do: $DBI::errstr";
  $sth2->execute($billpay_merchadmin::merchant, $query{'email'}, $query{'invoice_no'}) or die "Cannot execute: $DBI::errstr";
  while(my ($item, $cost, $qty, $descr, $weight, $descra, $descrb, $descrc) = $sth2->fetchrow) {
    if (($item ne '') || ($cost =~ /\d/) || ($qty > 0) || ($descr ne '')) {
      $data{"item$i"} = $item;
      $data{"cost$i"} = sprintf("%0.02f", $cost);
      $data{"qty$i"} = sprintf("%1d", $qty);
      $data{"descr$i"} = $descr;
      $data{"weight$i"} = $weight;
      $data{"descra$i"} = $descra;
      $data{"descrb$i"} = $descrb;
      $data{"descrc$i"} = $descrc;
      $i++;
    }
  }
  $sth2->finish;

  $data{'email'} = $data{'username'};

  return %data;
}

sub get_client_contact_data {
  my %query = @_;

  if ($query{'email'} !~ /\w/) {
    $query{'email'} = $query{'username'};
  }

  my %data;

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT *
      FROM client_contact
      WHERE merchant=?
      AND username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($billpay_merchadmin::merchant, $query{'email'}) or die "Can't execute: $DBI::errstr";
  my $ref = $sth->fetchrow_hashref();
  foreach my $key (keys %{$ref}) {
    $data{$key} = $ref->{$key};
  }
  $sth->finish;

  if ($data{'username'} ne '') {
    $data{'email'} = $data{'username'};
  }

  delete $data{'merchant'};
  delete $data{'username'};

  return %data;
}

sub get_client_email {
  my $clientid = @_;

  $clientid =~ s/\W//g;
  $clientid = lc($clientid);

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT username
      FROM client_contact
      WHERE merchant=? AND clientid=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($billpay_merchadmin::merchant, $clientid) or die "Can't execute: $DBI::errstr";
  my $email = $sth->fetchrow;
  $sth->finish;

  return $email;
}

sub invoice_form {
  my $type = shift;
  my %query = @_;

  my %data;
  my @now = gmtime(time);

  if (($query{'invoice_no'} ne '') && ($query{'email'} ne '')) {
    %data = &get_invoice_data(%query);
  }

  if ($query{'email'} ne '') {
    my %data2 = &get_client_contact_data(%query);
    %data = (%data, %data2);
  }

  my ($enter_start, $enter_end, $expire_start, $expire_end);

  # figure out start & end year range for allowed enter dates
  if ($data{'enter_date'} eq '') {
    $data{'enter_date'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);
    $enter_start = sprintf("%04d", $now[5]+1900);
  }
  elsif (($data{'enter_date'} ne '') && ($data{'enter_date'} < 20000101)) {
    $data{'enter_date'} = sprintf("%04d%02d%02d", substr($data{'enter_date'},0,4)+2000, $now[4]+1, $now[3]);
    $enter_start = 2000;
  }
  else {
    if ($data{'enter_date'} < 20000101) {
      # fix invalid year
      substr("$data{'enter_date'}",0,4,"2000");
    }
    $enter_start = sprintf("%04d", substr("$data{'enter_date'}",0,4));
  } 
  $enter_end = sprintf("%04d", $now[5]+1900);

  # figure out start & end year range for allowed expire dates
  $expire_start = $enter_start;
  $expire_end = sprintf("%04d", $now[5]+1920); # set 20 years into future

  # figure out what the default expire date should be, when expire_date is not defined
  if (($data{'expire_date'} eq '') || ($data{'expire_date'} < 20000101)) {
    my @future = @now;
    $future[4] = $future[4] + 1; # sets 1 month into future
    if ($future[4] >= 12) {
      $future[4] = $future[4] - 12;
      $future[5] = $future[5] + 1;
    }
    $data{'expire_date'} = sprintf("%04d%02d%02d", $future[5]+1900, $future[4]+1, $future[3]);
  }
  else {
    if ($data{'expire_date'} < 20000101) {
      # fix invalid year
      substr("$data{'expire_date'}",0,4,"2000");
    }
  }

  $data{'status'} = lc($data{'status'});
  if ($data{'status'} !~ /(open|closed|hidden|merged|paid)/) {
    $data{'status'} = "open";
  }

print<<EOF;
<script language="JavaScript"><!--
function recalculate_total() {
  if ((document.invoice_form.cost1.value == null) || (document.invoice_form.cost1.value == '')) {
    alert("You must itemize at least the first product, before you may recalculate the invoice total.")
  }
  else {
    var answer = 0;

    // calculate order subtotal
    for (i=1; i<=30; i++) {
      var field_cost = "cost" + i;
      var field_qty = "qty" + i;
      if ((document.invoice_form.elements[field_cost].value != null) && (document.invoice_form.elements[field_cost].value != '')) {
        // grab unit cost of product
        document.invoice_form.elements[field_cost].value = document.invoice_form.elements[field_cost].value.replace(/[^0-9\.\-]/g,''); // filter cost field
        var cost = Number(document.invoice_form.elements[field_cost].value);
        document.invoice_form.elements[field_qty].value = document.invoice_form.elements[field_qty].value.replace(/[^0-9\.]/g,''); // filter quantity field
        var qty = Number(document.invoice_form.elements[field_qty].value);
        // now add product to the subtotal, if quantity is defined
        if ((qty > 0) && (cost != '')) {
          document.invoice_form.elements[field_cost].value = cost.toFixed(2); // format cost field
          answer += eval(Number(cost) * Number(qty));
        }
      } 
    }
    // update subtotal value
    document.invoice_form.subtotal.value = answer.toFixed(2);
  
    // add sales tax
    var tax = Number(document.invoice_form.tax.value);
    document.invoice_form.tax.value = tax.toFixed(2);
    answer += Number(tax);
    
    // add shipping fee 
    var shipping = Number(document.invoice_form.shipping.value);
    document.invoice_form.shipping.value = shipping.toFixed(2);
    answer += Number(shipping);
    
    // add handling fee
    var handling = Number(document.invoice_form.handling.value);
    document.invoice_form.handling.value = handling.toFixed(2);
    answer += Number(handling);

    // subtract order discount
    var discount = Number(document.invoice_form.discount.value);
    document.invoice_form.discount.value = discount.toFixed(2);
    answer -= Number(discount);

    // update grand total
    document.invoice_form.amount.value = answer.toFixed(2);
  }
}

function recalculate_weight() {
  if ((document.invoice_form.weight1.value == null) || (document.invoice_form.weight1.value == '')) {
    alert("You must itemize at least the first product, before you may recalculate the total weight.")
  }
  else {
    var answer = 0;

    // calculate order total weight
    for (i=1; i<=30; i++) {
      var field_weight = "weight" + i;
      var field_qty = "qty" + i;
      if ((document.invoice_form.elements[field_weight].value != null) && (document.invoice_form.elements[field_weight].value != '')) {
        // grab unit weight of product
        document.invoice_form.elements[field_weight].value = document.invoice_form.elements[field_weight].value.replace(/[^0-9\.]/g,''); // filter weight field
        var weight = Number(document.invoice_form.elements[field_weight].value);
        document.invoice_form.elements[field_qty].value = document.invoice_form.elements[field_qty].value.replace(/[^0-9\.]/g,''); // filter quantity field
        var qty = Number(document.invoice_form.elements[field_qty].value);
        // now add product to the subtotal, if quantity is defined
        if ((qty > 0) && (weight > 0)) {
          document.invoice_form.elements[field_weight].value = weight.toFixed(2); // format weight field
          answer += eval(Number(weight) * Number(qty));
        }
      } 
    }
    // update total weight value
    document.invoice_form.total_weight.value = answer.toFixed(2);
  }
}
//--></script>
EOF

  print "Minimum required fields are marked with a \'<b>*</b>\'.<br>\n";

  if (($query{'email'} ne $data{'email'}) && ($query{'invoice_no'} ne $data{'invoice_no'})) {
    print "No matching invoice found.\n";
    print "<p><form action=\"$ENV{'SCRIPT_NAME'}\" method=post><input type=submit class=\"button\" value=\"Main Menu\"></form>\n";
    return;
  }

  print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post name=\"invoice_form\">\n";
  print "<input type=hidden name=\"merchant\" value=\"$ENV{'REMOTE_USER'}\">\n";
  print "<input type=hidden name=\"mode\" value=\"update_invoice\">\n";
  if ($query{'mode'} eq 'edit_invoice') {
    print "<input type=hidden name=\"overwrite\" value=\"yes\">\n";
  }

  # format: ['field_name', 'size', 'maxlength', 'type', 'title', 'field_value|current_setting', 'comment/option(s)']
  my @fields1 = (
    ['old_email',     0,   0, 'hidden',   '',                "$data{'email'}",       ''],
    ['email',        40, 255, 'text',     'Email *',         "$data{'email'}",       "<i>[i.e. customer\@somedomain\.com]</i>"],
    ['email_cust',    0,   0, 'checkbox', '',                "yes|$query{'merch_email_cust'}",  "Check to send customer notification of this invoice."],
    ['express_pay',   0,   0, 'checkbox', '',                "yes|$query{'merch_express_pay'}", "Include express pay link in notification."],
    ['invoice_no',   24,  24, 'text',     'Invoice No.',     "$data{'invoice_no'}",  "<i>[i.e. 1234567890]<br>If not defined, one will be generated for you.</i>"],
    ['account_no',   24,  24, 'text',     'Account No.',     "$data{'account_no'}",  "<i>[i.e. 9876543210]</i>"],
  );

  my @fields2 = (
    ['enter_date',    0,   0, 'date',     'Enter Date *',    "$data{'enter_date'}",  "2000|$enter_end"],
    ['expire_date',   0,   0, 'date',     'Expire Date *',   "$data{'expire_date'}", "$expire_start|$expire_end"],
    ['status',       20,  20, 'radio',    'Status',          "$data{'status'}",      "open|closed|hidden|merged|paid"],
    ['orderid',      24,  24, 'text',     'OrderID',         "$data{'orderid'}",     "Only enter, if customer has paid the invoice."]
  );

  my @fields2a = (
    #['lastbilled',    10, 10, 'readonly', 'Last Billed',  "$data{'lastbilled'}",    "<i>[YYYYMMDD Format]</i>"],
    #['lastattempted', 10, 10, 'readonly', 'Last Attempt', "$data{'lastattempted'}", "<i>[YYYYMMDD Format]</i>"],
    ['billcycle',      10, 10, 'text',     'Bill Cycle',   "$data{'billcycle'}",     "Months to wait between installment payments.<br><i>\[0 = no installments\]</i>"],
  );
  if ($billpay_merchadmin::feature_list{'billpay_use_percent'} eq 'yes') {
    push(@fields2a, ['percent', 12, 12, 'text', 'Installment Percentage', "$data{'percent'}", "<i>[i.e. enter '8.5' for 8.5%]</i>"] );
    push(@fields2a, ['monthly', 12, 12, 'text', 'Installment Minimum',    "$data{'monthly'}", "<i>[1234.56 Format]</i>"] );
  }
  else {
    push(@fields2a, ['monthly', 12, 12, 'text', 'Installment Fee', "$data{'monthly'}", "<i>[1234.56 Format]</i>"] );
  }
  if ($billpay_merchadmin::feature_list{'billpay_allow_partial'} eq 'yes') {
    push(@fields2a, ['remnant', 12, 12, 'text', 'Installment Remnant',    "$data{'remnant'}", "<i>[1234.56 Format]</i>"] );
  }

  if ($billpay_merchadmin::feature_list{'billpay_allow_nbalance'} eq 'yes') {
    push(@fields2a, ['balance', 12, 12, 'text', 'Balance',         "$data{'balance'}", "<i>[1234.56 (owed) or -1234.56 (excess) Format]</i>"] );
  }
  else {
    push(@fields2a, ['balance', 12, 12, 'text', 'Balance',         "$data{'balance'}", "<i>[1234.56 Format]</i>"] );
  }

  my @fields3 = (
    ['clientcompany', 40,  40, 'text',        'Company',         "$data{'clientcompany'}",   ''],
    ['clientname',    40,  40, 'text',        'Name',            "$data{'clientname'}",      ''],
    ['clientaddr1',   40,  40, 'text',        'Address Line 1',  "$data{'clientaddr1'}",     ''],
    ['clientaddr2',   40,  40, 'text',        'Address Line 2',  "$data{'clientaddr2'}",     ''],
    ['clientcity',    40,  40, 'text',        'City',            "$data{'clientcity'}",      ''],
    ['clientstate',    2,   2, 'select_hash', 'State',           "$data{'clientstate'}",     'USstates'],
    ['clientzip',     14,  14, 'text',        'Zip/Postal Code', "$data{'clientzip'}",       ''],
    ['clientcountry',  2,   2, 'select_hash', 'Country',         "$data{'clientcountry'}",   'countries'],
    ['clientphone',   15,  15, 'text',        'Phone',           "$data{'clientphone'}",     ''],
    ['clientfax',     15,  15, 'text',        'Fax',             "$data{'clientfax'}",       ''],
  );

  if ($billpay_merchadmin::feature_list{'billpay_showalias'} eq 'yes') {
    push(@fields3, ['alias', 20, 20, 'text',  'Alias', "$data{'alias'}", ''] );
  }
  else {
    push(@fields3, ['alias', 0, 0, 'hidden',  '', "$data{'alias'}", ''] );
  }

  if ($billpay_merchadmin::feature_list{'billpay_showconsolidate'} eq 'yes') {
    push(@fields3, ['consolidate', 0, 0, 'checkbox', 'Consolidate', "yes|$query{'consolidate'}", "Check to permit invoice consolidation."] );
  }
  else {
    push(@fields3, ['consolidate', 0, 0, 'hidden', '', "$query{'consolidate'}", ''] );
  }

  my @fields4 = (
    ['subtotal',     10,  10, 'textro',   'Subtotal',        "$data{'subtotal'}",    "<i>(Subtotal is used for recalculation verification purposes only)</i>"],
    ['tax',          10,  10, 'text',     'Tax',             "$data{'tax'}",         "<i>[1234.56 Format]</i>"],
    ['shipping',     10,  10, 'text',     'Shipping',        "$data{'shipping'}",    "<i>[1234.56 Format]</i>"],
    ['handling',     10,  10, 'text',     'Handling',        "$data{'handling'}",    "<i>[1234.56 Format]</i>"],
    ['discount',     10,  10, 'text',     'Discount',        "$data{'discount'}",    "<i>[1234.56 Format]</i>"],
    ['amount',       10,  10, 'text',     'Total Amount *',  "$data{'amount'}",      "<i>[1234.56 Format]</i>"]
  );

  my @fields5 = (
    ['datalink_url',   70, 255, 'text',     'DataLink URL',   "$data{'datalink_url'}",   "<i>Absolute URL to your own hosted file/script, where additonal data resides.</i>"],
    ['datalink_pairs', 70, 255, 'text',     'DataLink Pairs', "$data{'datalink_pairs'}", "<i>Query string of name/value pairs to pass onto DataLink URL.</i>"],
    ['public_notes',   60,   6, 'textarea', 'Public Notes',   "$data{'public_notes'}",   "<i>Public Notes are viewible by customers, while viewing invoice.</i>"],
    ['private_notes',  60,   6, 'textarea', 'Private Notes',  "$data{'private_notes'}",  "<i>Private Notes are viewible by merchant only.</i>"]
  );

  my @fields6 = (
    ['shipsame',     0,   0, 'checkbox',    '',                "yes|$query{'shipsame'}",  "Select this, if the Shipping Address Information is same as the Customer Contact information above."],
    ['shipcompany', 40,  40, 'text',        'Company',         "$data{'shipcompany'}",   ''],
    ['shipname',    40,  40, 'text',        'Name',            "$data{'shipname'}",      ''],
    ['shipaddr1',   40,  40, 'text',        'Address Line 1',  "$data{'shipaddr1'}",     ''],
    ['shipaddr2',   40,  40, 'text',        'Address Line 2',  "$data{'shipaddr2'}",     ''],
    ['shipcity',    40,  40, 'text',        'City',            "$data{'shipcity'}",      ''],
    ['shipstate',    2,   2, 'select_hash', 'State',           "$data{'shipstate'}",     'USstates'],
    ['shipzip',     14,  14, 'text',        'Zip/Postal Code', "$data{'shipzip'}",       ''],
    ['shipcountry',  2,   2, 'select_hash', 'Country',         "$data{'shipcountry'}",   'countries'],
    ['shipphone',   15,  15, 'text',        'Phone',           "$data{'shipphone'}",     ''],
    ['shipfax',     15,  15, 'text',        'Fax',             "$data{'shipfax'}",       '']
  );

  print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Customer Info:</b></legend>\n";
  &print_fields(@fields1);
  print "</fieldset>\n";

  if ($ENV{'REMOTE_USER'} !~ /^(detailedpr)$/) {
    print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
    print "<legend style=\"padding: 4px 8px;\"><b>Invoice Details:</b></legend>\n";
    &print_fields(@fields2);
    print "</fieldset>\n";

    print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
    print "<legend style=\"padding: 4px 8px;\"><b>Installment Option:</b></legend>\n";
    print "Only fill in these fields, if you intend for the invoice to be paid in installments.<p>\n";
    &print_fields(@fields2a);
    print "</fieldset>\n";

    print "<p>\n";
  }

  print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Customer Contact:</b></legend>\n";
  &print_fields(@fields3);
  print "</fieldset>\n";

  if ($billpay_merchadmin::feature_list{'billpay_shipinfo'} == 1) {
    print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
    print "<legend style=\"padding: 4px 8px;\"><b>Shipping Address:</b></legend>\n";
    &print_fields(@fields6);
    print "</fieldset>\n";
  }

  print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Order Details:</b></legend>\n";

  print "<table border=0 cellspacing=0 cellpadding=1>\n";
  print "  <tr>\n";
  print "    <th>$billpay_language::lang_titles{'column_item'}</th>\n";
  print "    <th>$billpay_language::lang_titles{'column_descr'}</th>\n";
  print "    <th>$billpay_language::lang_titles{'column_qty'}</th>\n";
  print "    <th>$billpay_language::lang_titles{'column_cost'}</th>\n";
  if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) {
    print "    <th>Unit Weight</th>\n";
  }
  if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) {
    print "    <th>$billpay_language::lang_titles{'column_descra'}</th>\n";
  }
  if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) {
    print "    <th>$billpay_language::lang_titles{'column_descrb'}</th>\n";
  }
  if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) {
    print "    <th>$billpay_language::lang_titles{'column_descrc'}</th>\n";
  }
  print "  <tr>\n"; 

  my $subtotal = 0;
  my $total_weight = 0;
  for (my $i = 1; $i <= 30; $i++) {
    print "  <tr>\n";
    printf ("    <td><input type=text name=\"%s\" value=\"%s\" size=%d maxlength=%d></td>\n", "item$i", "$data{\"item$i\"}", 10, 23);
    printf ("    <td><input type=text name=\"%s\" value=\"%s\" size=%d maxlength=%d></td>\n", "descr$i", "$data{\"descr$i\"}", 40, 200);
    printf ("    <td><input type=text name=\"%s\" value=\"%s\" size=%d maxlength=%d></td>\n", "qty$i", "$data{\"qty$i\"}", 3, 3);
    printf ("    <td><input type=text name=\"%s\" value=\"%s\" size=%d maxlength=%d></td>\n", "cost$i", "$data{\"cost$i\"}", 8, 10);
    if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) {
      printf ("    <td><input type=text name=\"%s\" value=\"%s\" size=%d maxlength=%d></td>\n", "weight$i", "$data{\"weight$i\"}", 8, 10);
      if ($data{"weight$i"} > 0) {
        $total_weight += ($data{"weight$i"} * $data{"qty$i"});
      }
    }
    if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) {
      printf ("    <td><input type=text name=\"%s\" value=\"%s\" size=%d maxlength=%d></td>\n", "descra$i", "$data{\"descra$i\"}", 20, 200);
    }
    if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) {
      printf ("    <td><input type=text name=\"%s\" value=\"%s\" size=%d maxlength=%d></td>\n", "descrb$i", "$data{\"descrb$i\"}", 20, 200);
    }
    if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) {
      printf ("    <td><input type=text name=\"%s\" value=\"%s\" size=%d maxlength=%d></td>\n", "descrc$i", "$data{\"descrc$i\"}", 20, 200);
    }
    print "  <tr>\n"; 
    $subtotal += ($data{"cost$i"} * $data{"qty$i"});
  }

  $data{'subtotal'} = sprintf("%0.02f", $subtotal);

  if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) {
    print "  <tr>\n";
    print "    <td colspan=4 align=right><input type=button class=\"button\" value=\"Recalculate Weight\" onClick=\"recalculate_weight();\"></td>\n";
    printf ("    <td><nobr><input type=text name=\"%s\" value=\"%s\" size=%d maxlength=%d readonly> lbs.</nobr></td>\n", "total_weight", "$total_weight", 8, 10);
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td colspan=4 align=right><input type=button class=\"button\" value=\"Recalculate Total\" onClick=\"recalculate_total();\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  &print_fields(@fields4);
  print "</fieldset>\n";

  print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Invoice Memos:</b></legend>\n";
  &print_fields(@fields5);
  print "</fieldset>\n";

  if ($ENV{'REMOTE_USER'} =~ /^(detailedpr)$/) {
    print "<p>\n";

    print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
    print "<legend style=\"padding: 4px 8px;\"><b>Installment Option:</b></legend>\n";
    print "Only fill in these fields, if you intend for the invoice to be paid in installments.<p>\n";
    &print_fields(@fields2a);
    print "</fieldset>\n";

    print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
    print "<legend style=\"padding: 4px 8px;\"><b>Invoice Details:</b></legend>\n";
    &print_fields(@fields2);
    print "</fieldset>\n";
  }

  print "<p><input type=submit class=\"button\" value=\"Submit Invoice\"> &nbsp; <input type=reset class=\"button\" value=\"Reset Invoice\"></p>\n";

  print "</form>\n";

  print "<p><form action=\"$ENV{'SCRIPT_NAME'}\" method=post><input type=submit class=\"button\" value=\"Main Menu\"></form>\n";

  return;
}

sub view_invoice_form {
  my $type = shift;
  my %query = @_;

  my %data;
  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  %data = &get_invoice_data(%query);

  my %data2 = &get_client_contact_data(%query);
  %data = (%data, %data2);

  my ($enter_start, $enter_end, $expire_start, $expire_end);

  $data{'status'} = lc($data{'status'});
  if ($data{'status'} !~ /(open|closed|hidden|merged|paid)/) {
    $data{'status'} = "open";
  }

  if (($data{'email'} !~ /\w/) && ($data{'invoice_no'} !~ /\w/)) {
    print "No matching invoice found.\n";
    print "<p><form action=\"$ENV{'SCRIPT_NAME'}\" method=post><input type=submit class=\"button\" value=\"Main Menu\"></form>\n";
    return;
  }

  # format: ['field_name', 'size', 'maxlength', 'type', 'title', 'field_value|current_setting', 'comment/option(s)']
  my @fields1 = (
    ['email',         0,   0, 'justtext', 'Email',           "$data{'email'}",       ''],
    ['invoice_no',    0,   0, 'justtext', 'Invoice No.',     "$data{'invoice_no'}",  ''],
    ['account_no',    0,   0, 'justtext', 'Account No.',     "$data{'account_no'}",  '']
  );

  if ($billpay_merchadmin::feature_list{'billpay_showalias'} eq 'yes') {
    push(@fields1, ['alias', 0, 0, 'justtext', 'Alias', "$data{'alias'}", ''] );
  }

  my @fields2 = (
    ['enter_date',    0,   0, 'justtext', 'Enter Date',      "$data{'enter_date'}",  ''],
    ['expire_date',   0,   0, 'justtext', 'Expire Date',     "$data{'expire_date'}", ''],
    ['status',        0,   0, 'justtext', 'Status',          "$data{'status'}",      ''],
    ['orderid',       0,   0, 'justtext', 'OrderID',         "$data{'orderid'}",     '']
  );

  my @fields2a = (
    #['lastbilled',    0, 0, 'justtext', 'Last Billed',  "$data{'lastbilled'}",    ''],
    #['lastattempted', 0, 0, 'justtext', 'Last Attempt', "$data{'lastattempted'}", ''],
    ['billcycle',      0, 0, 'justtext', 'Bill Cycle',   "$data{'billcycle'}",     '']
  );
  if ($billpay_merchadmin::feature_list{'billpay_use_percent'} eq 'yes') {
    push(@fields2a, ['percent',  0,  0, 'justtext', 'Installment Percentage', "$data{'percent'}", ''] );
    push(@fields2a, ['monthly',  0,  0, 'justtext', 'Installment Minimum',    "$data{'monthly'}", ''] );
  }
  else {
    push(@fields2a, ['monthly',  0,  0, 'justtext', 'Installment Fee', "$data{'monthly'}", ''] );
  }
  if ($billpay_merchadmin::feature_list{'billpay_allow_partial'} eq 'yes') {
    push(@fields2a, ['remnant',  0, 0, 'justtext', 'Installment Remnant', "$data{'remnant'}", ''] );
  }
  push(@fields2a, ['balance',  0,  0, 'justtext', 'Balance',         "$data{'balance'}", ''] );

  my @fields3 = (
    ['clientcompany',  0,   0, 'justtext',    'Company',         "$data{'clientcompany'}",   ''],
    ['clientname',     0,   0, 'justtext',    'Name',            "$data{'clientname'}",      ''],
    ['clientaddr1',    0,   0, 'justtext',    'Address Line 1',  "$data{'clientaddr1'}",     ''],
    ['clientaddr2',    0,   0, 'justtext',    'Address Line 2',  "$data{'clientaddr2'}",     ''],
    ['clientcity',     0,   0, 'justtext',    'City',            "$data{'clientcity'}",      ''],
    ['clientstate',    0,   0, 'justtext',    'State',           "$data{'clientstate'}",     ''],
    ['clientzip',      0,   0, 'justtext',    'Zip/Postal Code', "$data{'clientzip'}",       ''],
    ['clientcountry',  0,   0, 'justtext',    'Country',         "$data{'clientcountry'}",   ''],
    ['clientphone',    0,   0, 'justtext',    'Phone',           "$data{'clientphone'}",     ''],
    ['clientfax',      0,   0, 'justtext',    'Fax',             "$data{'clientfax'}",       '']
  );

  my @fields4 = (
    ['subtotal',      0,   0, 'justtext', 'Subtotal',        "$data{'subtotal'}",    ''],
    ['tax',           0,   0, 'justtext', 'Tax',             "$data{'tax'}",         ''],
    ['shipping',      0,   0, 'justtext', 'Shipping',        "$data{'shipping'}",    ''],
    ['handling',      0,   0, 'justtext', 'Handling',        "$data{'handling'}",    ''],
    ['discount',      0,   0, 'justtext', 'Discount',        "$data{'discount'}",    ''],
    ['amount',        0,   0, 'justtext', 'Total Amount',    "$data{'amount'}",      '']
  );

  my @fields5 = (
    ['datalink_url',   0,   0, 'justtext', 'DataLink URL',   "$data{'datalink_url'}",   ''],
    ['datalink_pairs', 0,   0, 'justtext', 'DataLink Pairs', "$data{'datalink_pairs'}", ''],
    ['public_notes',   0,   0, 'justtext', 'Public Notes',   "$data{'public_notes'}",   ''],
    ['private_notes',  0,   0, 'justtext', 'Private Notes',  "$data{'private_notes'}",  '']
  );

  my @fields6 = (
    ['shipcompany',  0,   0, 'justtext',    'Company',         "$data{'shipcompany'}",   ''],
    ['shipname',     0,   0, 'justtext',    'Name',            "$data{'shipname'}",      ''],
    ['shipaddr1',    0,   0, 'justtext',    'Address Line 1',  "$data{'shipaddr1'}",     ''],
    ['shipaddr2',    0,   0, 'justtext',    'Address Line 2',  "$data{'shipaddr2'}",     ''],
    ['shipcity',     0,   0, 'justtext',    'City',            "$data{'shipcity'}",      ''],
    ['shipstate',    0,   0, 'justtext',    'State',           "$data{'shipstate'}",     ''],
    ['shipzip',      0,   0, 'justtext',    'Zip/Postal Code', "$data{'shipzip'}",       ''],
    ['shipcountry',  0,   0, 'justtext',    'Country',         "$data{'shipcountry'}",   ''],
    ['shipphone',    0,   0, 'justtext',    'Phone',           "$data{'shipphone'}",     ''],
    ['shipfax',      0,   0, 'justtext',    'Fax',             "$data{'shipfax'}",       '']
  );

  print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Customer Info:</b></legend>\n";
  &print_fields(@fields1);
  print "</fieldset>\n";

  if ($ENV{'REMOTE_USER'} !~ /^(detailedpr)$/) {
    print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
    print "<legend style=\"padding: 4px 8px;\"><b>Invoice Details:</b></legend>\n";
    &print_fields(@fields2);
    print "</fieldset>\n";

    print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
    print "<legend style=\"padding: 4px 8px;\"><b>Installment Option:</b></legend>\n";
    print "These fields only apply, if the invoice is to be paid in installments.<p>\n";
    &print_fields(@fields2a);
    print "</fieldset>\n";

    print "<p>\n";
  }

  print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Customer Contact:</b></legend>\n";
  &print_fields(@fields3);
  print "</fieldset>\n";

  if ($billpay_merchadmin::feature_list{'billpay_shipinfo'} == 1) {
    print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
    print "<legend style=\"padding: 4px 8px;\"><b>Shipping Address:</b></legend>\n";
    &print_fields(@fields6);
    print "</fieldset>\n";
  }

  print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Order Details:</b></legend>\n";

  my %cols = ();
  $cols{'item'} = "    <th>$billpay_language::lang_titles{'column_item'}</th>\n";
  $cols{'descr'} = "    <th>$billpay_language::lang_titles{'column_descr'}</th>\n";
  $cols{'qty'} = "    <th>$billpay_language::lang_titles{'column_qty'}</th>\n";
  $cols{'cost'} = "    <th>$billpay_language::lang_titles{'column_cost'}</th>\n";
  if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) {
    $cols{'weight'} = "    <th>$billpay_language::lang_titles{'column_weight'}</th>\n";
  }
  if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) {
    $cols{'descra'} = "    <th>$billpay_language::lang_titles{'column_descra'}</th>\n";
  }
  if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) {
    $cols{'descrb'} = "    <th>$billpay_language::lang_titles{'column_descrb'}</th>\n";
  }
  if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) {
    $cols{'descrc'} = "    <th>$billpay_language::lang_titles{'column_descrc'}</th>\n";
  }

  print "<table border=0 cellspacing=0 cellpadding=1>\n";
  print "  <tr>\n";
  if ($billpay_merchadmin::feature_list{'billpay_displayorder'} ne '') {
    my @list = split(/\|/, $billpay_merchadmin::feature_list{'billpay_displayorder'});
    for (my $l = 0; $l <= $#list; $l++) {
      if ($list[$l] =~ /\w/) {
        print $cols{"$list[$l]"};
      }
    }
  }
  else {
    print $cols{'item'};
    print $cols{'descr'};
    print $cols{'qty'};
    print $cols{'cost'};
    if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) {
      print $cols{'weight'};
    }
    if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) {
      print $cols{'descra'};
    }
    if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) {
      print $cols{'descrb'};
    }
    if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) {
      print $cols{'descrc'};
    }
  }
  print "  </tr>\n";

  my $subtotal = 0;
  my $total_weight = 0;
  for (my $i = 1; $i <= 30; $i++) {
    if (($data{"item$i"} =~ /\w/) && ($data{"descr$i"} =~ /\w/) && ($data{"qty$i"} =~ /\w/) && ($data{"cost$i"} =~ /\w/)) {

      my %cols = ();
      $cols{'item'} = sprintf ("    <td>%s</td>\n", "$data{\"item$i\"}");
      $cols{'descr'} = sprintf ("    <td>%s</td>\n", "$data{\"descr$i\"}");
      $cols{'qty'} = sprintf ("    <td>%s</td>\n", "$data{\"qty$i\"}");
      $cols{'cost'} = sprintf ("    <td>%s</td>\n", "$data{\"cost$i\"}");
      if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) {
        $cols{'weight'} = sprintf ("    <td>%s lbs.</td>\n", "$data{\"weight$i\"}");
        if ($data{"weight$i"} > 0) {
          $total_weight = $total_weight + ($data{"weight$i"} * $data{"qty$i"});
        }
      }
      if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) {
        $cols{'descra'} = sprintf ("    <td>%s</td>\n", "$data{\"descra$i\"}");
      }
      if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) {
        $cols{'descrb'} = sprintf ("    <td>%s</td>\n", "$data{\"descrb$i\"}");
      }
      if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) {
        $cols{'descrc'} = sprintf ("    <td>%s</td>\n", "$data{\"descrc$i\"}");
      }

      print "  <tr>\n";
      if ($billpay_merchadmin::feature_list{'billpay_displayorder'} ne '') {
        my @list = split(/\|/, $billpay_merchadmin::feature_list{'billpay_displayorder'});
        for (my $l = 0; $l <= $#list; $l++) {
          if ($list[$l] =~ /\w/) {
            print $cols{"$list[$l]"};
          }
        }
      }
      else {
        print $cols{'item'};
        print $cols{'descr'};
        print $cols{'qty'};
        print $cols{'cost'};
        if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) {
          print $cols{'weight'};
        }
        if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) {
          print $cols{'descra'};
        }
        if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) {
          print $cols{'descrb'};
        }
        if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) {
          print $cols{'descrc'};
        }
      }
      print "  <tr>\n";
      $subtotal += ($data{"cost$i"} * $data{"qty$i"});
    }
  }

  $data{'subtotal'} = sprintf("%0.02f", $subtotal);

  print "  <tr><td> &nbsp; </td></tr>\n";

  if ($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) {
    print "  <tr>\n";
    print "    <td colspan=4 align=right> Total Weight: </td>\n";
    printf ("    <td><nobr>%s lbs.</nobr></td>\n", "$total_weight");
    print "  </tr>\n";
  }

  print "</table>\n";

  &print_fields(@fields4);
  print "</fieldset>\n";

  print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Invoice Memos:</b></legend>\n";
  &print_fields(@fields5);
  print "</fieldset>\n";

  if ($ENV{'REMOTE_USER'} =~ /^(detailedpr)$/) {
    print "<p>\n";

    print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
    print "<legend style=\"padding: 4px 8px;\"><b>Installment Option:</b></legend>\n";
    print "These fields only apply, if the invoice is to be paid in installments.<p>\n";
    &print_fields(@fields2a);
    print "</fieldset>\n";

    print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
    print "<legend style=\"padding: 4px 8px;\"><b>Invoice Details:</b></legend>\n";
    &print_fields(@fields2);
    print "</fieldset>\n";
  }

  if (($data{'expire_date'} > $today) && (($data{'status'} eq '') || ($data{'status'} eq 'open'))) {
    if ($ENV{'SEC_LEVEL'} <= 8) {
      print "<p><form method=post action=\"/billpay_express.cgi\" target=\"billpay\">\n";
      print "<input type=hidden name=\"merchant\" value=\"$billpay_merchadmin::merchant\">\n";
      print "<input type=hidden name=\"cobrand\" value=\"$billpay_merchadmin::query{'merch_company'}\">\n";
      print "<input type=hidden name=\"email\" value=\"$data{'username'}\">\n";
      print "<input type=hidden name=\"invoice_no\" value=\"$data{'invoice_no'}\">\n";
      print "<input type=submit class=\"button\" value=\"Express Pay\">\n";
      print "</form>\n";
    }
  }

  print "<p><form action=\"$ENV{'SCRIPT_NAME'}\" method=post><input type=submit class=\"button\" value=\"Main Menu\"></form>\n";

  return;
}

sub print_fields {
  my @fields = @_;

  print "<table border=0 cellspacing=0 cellpadding=1>\n";

  for (my $i = 0; $i <= $#fields; $i++) {
    print "  <tr>\n";
    printf ("    <th valign=top width=135>%s</th>\n", $fields[$i][4]);
    print "    <td>";
    if ($fields[$i][3] eq 'textarea') {
      printf ("<textarea name=\"%s\" cols=%s rows=%s >%s</textarea>\n", $fields[$i][0], $fields[$i][1], $fields[$i][2], $fields[$i][5]);
    }
    elsif ($fields[$i][3] eq 'text') {
      printf ("<input type=text name=\"%s\" value=\"%s\" size=%d maxlength=%d>\n", $fields[$i][0], $fields[$i][5], $fields[$i][1], $fields[$i][2]);
    }
    elsif ($fields[$i][3] eq 'textro') {
      printf ("<input type=text name=\"%s\" value=\"%s\" size=%d maxlength=%d readonly>\n", $fields[$i][0], $fields[$i][5], $fields[$i][1], $fields[$i][2]);
    }
    elsif ($fields[$i][3] =~ "readonly") {
      printf ("<input type=hidden name=\"%s\" value=\"%s\" size=%d maxlength=%d>%s\n", $fields[$i][0], $fields[$i][5], $fields[$i][1], $fields[$i][2], $fields[$i][5]);
    }
    elsif ($fields[$i][3] =~ "hidden") {
      printf ("<input type=hidden name=\"%s\" value=\"%s\" size=%d maxlength=%d>\n", $fields[$i][0], $fields[$i][5], $fields[$i][1], $fields[$i][2]);
    }
    elsif ($fields[$i][3] eq 'justtext') {
      printf ("%s\n", $fields[$i][5]);
    }
    elsif ($fields[$i][3] eq 'date') {
      my @month_names = ('', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

      my ($year_start, $year_end) = split(/\|/, "$fields[$i][6]", 2);

      my $select_month = sprintf ("%02d", substr("$fields[$i][5]",4,2));
      my $select_day   = sprintf ("%02d", substr("$fields[$i][5]",6,2));
      my $select_year  = sprintf ("%04d", substr("$fields[$i][5]",0,4));

      print "<select name=\"$fields[$i][0]\_month\">\n";
      for (my $a = 1; $a <= $#month_names; $a++) {
        print  "<option value=\"$a\"";
        if ($a == $select_month) {
          print " selected";
        } 
        print ">$month_names[$a]</option>\n";
      }
      print "</select>\n";
      print "<select name=\"$fields[$i][0]\_day\">\n";
      for (my $a = 1; $a <= 31; $a++) {
        print  "<option value=\"$a\"";
        if ($a == $select_day) {
          print " selected";
        } 
        print ">$a</option>\n";
      }
      print "</select>\n";
      print "<select name=\"$fields[$i][0]\_year\">\n";
      for (my $a = $year_start; $a <= $year_end; $a++) {
        print  "<option value=\"$a\"";
        if ($a == $select_year) {
          print " selected";
        }
        print ">$a</option>\n";
      }
      print "</select>";
    }
    elsif ($fields[$i][3] eq 'select') {
      my %checked;
      my @temp = split(/\|/, $fields[$i][6]);
      printf ("<select name=\"%s\">\n", $fields[$i][0]);
      for (my $a = 0; $a <= $#temp; $a++) {
        my $checked = '';
        if ($temp[$a] eq $fields[$i][5]) { $checked = " selected"; }
        printf ("<option value=\"%s\"%s> %s </option>\n", $temp[$a], $checked, $temp[$a]);
      }
      print "</select>\n";
    }
    elsif ($fields[$i][3] eq 'select_hash') {
      my %checked;
      my %temp = &get_appendix_hash($fields[$i][6]);
      printf ("<select name=\"%s\">\n", $fields[$i][0]);
      print "<option value=\"\"> </option>\n";
      foreach my $key1 (&sort_hash(\%temp)) {
        my $checked = '';
        if ($key1 eq $fields[$i][5]) { $checked = " selected"; }
        printf ("<option value=\"%s\"%s> %s </option>\n", $key1, $checked, $temp{$key1});
      }
      print "</select>\n";
    }
    elsif ($fields[$i][3] eq 'radio') {
      my %checked;
      my @temp = split(/\|/, $fields[$i][6]);
      for (my $a = 0; $a <= $#temp; $a++) {
        my $checked = '';
        if ($temp[$a] eq $fields[$i][5]) { $checked = " checked"; }
        printf ("<input type=radio name=\"%s\" value=\"%s\"%s> %s &nbsp;", $fields[$i][0], $temp[$a], $checked, $temp[$a]);
      }
    }
    elsif ($fields[$i][3] eq 'checkbox') {
      my ($field_value, $current_setting) = split(/\|/, $fields[$i][5], 2);
      #printf ("<input type=checkbox name=\"%s\" value=\"%s\">", $fields[$i][0], $fields[$i][5]);

      if ($field_value eq "$current_setting") {
        printf ("<input type=checkbox name=\"%s\" value=\"%s\" checked>", $fields[$i][0], $field_value);
      }
      else {
        printf ("<input type=checkbox name=\"%s\" value=\"%s\">", $fields[$i][0], $field_value);
      }

    }

    if (($fields[$i][6] ne '') && ($fields[$i][3] !~ /^(radio|select|select_hash|date)$/)) {
      if ($fields[$i][3] =~ /^(textarea|text|textro|readonly|justtext)$/) {
        print "<br>";
      }
      printf (" %s", $fields[$i][6]);
    }
    print "</td>\n";
    print "  </tr>\n";
  }

  print "</table>\n";

  return;
}

sub search_invoices {
  my $type = shift;
  my %query = @_;

  my ($merchant, $username, $invoice_no, $enter_date, $expire_date, $account_no, $amount, $status, $billcycle, $percent, $monthly, $remnant, $balance, $orderid);
  my $count = 0;

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my @now2 = gmtime(time + 86400);
  my $tomorrow = sprintf("%04d%02d%02d", $now2[5]+1900, $now2[4]+1, $now2[3]);

  my $startdate = sprintf("%04d%02d%02d", $query{'startyear'}, $query{'startmonth'}, $query{'startday'});
  my $enddate = sprintf("%04d%02d%02d", $query{'endyear'}, $query{'endmonth'}, $query{'endday'});

  if ($startdate < 20060101) {
    $startdate = 20060101;
  }
  if ($enddate > $today) {
    $enddate = $tomorrow;
  }
  if ($enddate < $startdate) {
    my $old_startdate = $startdate;
    $startdate = $enddate;
    $enddate = $old_startdate;
  }

  my %selected;
  if ($query{'sort_by'} !~ /^(username|invoice_no|enter_date|expire_date|account_no|amount|status|billcycle|percent|monthly|remnant|balance|orderid)$/) {
    $query{'sort_by'} = "enter_date";
  }
  $selected{"$query{'sort_by'}"} = "<font size=\"+1\">&raquo;</font>";


  my @placeholder;
  my $qstr = "SELECT merchant, username, invoice_no, enter_date, expire_date, account_no, amount, status, billcycle, percent, monthly, remnant, balance, orderid";
  $qstr .= " FROM bills2";
  $qstr .= " WHERE merchant=?";
  push(@placeholder, "$billpay_merchadmin::merchant");

  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} = lc($query{'email'});
  if ($query{'email'} ne '') {
    $qstr .= " AND username LIKE ?";
    push(@placeholder, "\%$query{'email'}\%");
  }

  if ($query{'invoice_no'} ne '') {
    $qstr .= " AND invoice_no LIKE ?";
    push(@placeholder, "\%$query{'invoice_no'}\%");
  }

  if ($query{'account_no'} ne '') {
    $qstr .= " AND account_no LIKE ?";
    push(@placeholder, "\%$query{'account_no'}\%");
  }

  if ($query{'orderid'} ne '') {
    $qstr .= " AND orderid LIKE ?";
    push(@placeholder, "\%$query{'orderid'}\%");
  }

  if (($query{'amount_min'} ne '') && ($query{'amount_max'} ne '')) {
    $query{'amount_min'} = sprintf("%0.02f", $query{'amount_min'});
    $query{'amount_max'} = sprintf("%0.02f", $query{'amount_max'});
    $qstr .= " AND amount>=? AND amount<=?";
    push(@placeholder, "$query{'amount_min'}", "$query{'amount_max'}");
  }

  if ($query{'status'} =~ /^(open|expired|closed|hidden|merged|paid|unpaid)$/) {
    if ($query{'status'} eq 'expired') {
      $query{'status'} = "open";
      $qstr .= " AND status=? AND expire_date<=?";
      push(@placeholder, "$query{'status'}", "$today");
    }
    elsif ($query{'status'} eq 'unpaid') {
      $query{'status'} = "open";
      $qstr .= " AND status=? AND expire_date>? AND (balance>0 OR orderid=?)";
      push(@placeholder, "$query{'status'}", "$today", '');
    }
    else {
      $qstr .= " AND status=?";
      push(@placeholder, "$query{'status'}");
    }
  }

  if ($query{'invoices'} eq 'enter_date') {
    # limit exported invoices to only those within the enter date range
    $qstr .= " AND enter_date>=? AND enter_date<=?";
    push(@placeholder, "$startdate", "$enddate");
  }
  elsif ($query{'invoices'} eq 'expire_date') {
    # limit exported invoices to only those within the expire date range
    $qstr .= " AND expire_date>=? AND expire_date<=?";
    push(@placeholder, "$startdate", "$enddate");
  }

  $qstr .= " ORDER BY $query{'sort_by'}";

  my $link = "$ENV{'SCRIPT_NAME'}\?mode=$query{'mode'}\&email=$query{'email'}\&invoice_no=$query{'invoice_no'}\&account_no=$query{'account_no'}\&orderid=$query{'orderid'}\&amount_min=$query{'amount_min'}\&amount_max=$query{'amount_max'}\&status=$query{'status'}";

  print "<b>Click on the Invoice Number you wish to select for additional details.</b>\n";
  print "<br>&bull; Clicking on the email address, will allow you to email that customer.</b>\n";
  print "<br>&bull; The \'<font size=\"+1\">&raquo;</font>\' character shows what column the list is currently sorted by.\n";
  print "<br>&bull; To re-organize the list, click on the column's title you wish to sort by.\n";

  print "<table border=0 cellspacing=0 cellpadding=0 width=760 class=\"table_list\">\n";
  print "  <tr class=\"sectiontitle\">\n";
  #print "    <th>Merchant</th>\n";
  print "    <th><a href=\"$link\&sort_by=username\">$selected{'username'}Email</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=invoice_no\">$selected{'invoice_no'}Invoice No</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=account_no\">$selected{'account_no'}Account No</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=enter_date\">$selected{'enter_date'}Enter Date</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=expire_date\">$selected{'expire_date'}Expire Date</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=amount\">$selected{'amount'}Amount</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=status\">$selected{'status'}Status</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=orderid\">$selected{'orderid'}OrderID</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=billcycle\">$selected{'billcycle'}BillCycle</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=percent\">$selected{'percent'}Percent</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=monthly\">$selected{'monthly'}Monthly</a></th>\n";
  if ($billpay_merchadmin::feature_list{'billpay_allow_partial'} eq 'yes') {
    print "    <th><a href=\"$link\&sort_by=remnant\">$selected{'remnant'}Remnant</a></th>\n";
  }
  print "    <th><a href=\"$link\&sort_by=balance\">$selected{'balance'}Balance</a></th>\n";
  print "    <th> &nbsp; </th>\n";
  print "  </tr>\n";

  my $color = 1;

  my $sth = $billpay_merchadmin::dbh->prepare(qq{ $qstr }) or die "Cannot do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Cannot execute: $DBI::errstr";
  while(my ($merchant, $username, $invoice_no, $enter_date, $expire_date, $account_no, $amount, $status, $billcycle, $percent, $monthly, $remnant, $balance, $orderid) = $sth->fetchrow) {
    $count = $count + 1;

    $amount = sprintf("%0.02f", $amount);

    if ($account_no eq '') { $account_no = "&nbsp;"; }

    if ($status eq '') { $status = "open"; }

    if ($orderid eq '') { $orderid = "&nbsp;" }

    if ($billcycle eq '') { $billcycle = "&nbsp;" }
     else { $billcycle = sprintf("%d", $billcycle); }

    if ($percent eq '') {
      $percent = "&nbsp;"
    }
    else {
      $percent = sprintf("%f", $percent);
    }

    if ($monthly eq '') {
      $monthly = "&nbsp;"
    }
    else {
      $monthly = sprintf("%0.02f", $monthly);
    }

    if ($remnant eq '') {
      $remnant = "&nbsp;"
    }
    else {
      $remnant = sprintf("%0.02f", $remnant);
    }

    if ($balance eq '') { $balance = "&nbsp;" }
     else { $balance = sprintf("%0.02f", $balance); }

    if ($color == 1) {
      print "  <tr class=\"listrow_color1\">\n";
    }
    else {
      print "  <tr class=\"listrow_color0\">\n";
    }
    #print "    <td>$merchant</td>\n";
    if ($username =~ /(\.pnp)$/) {
      print "    <td> &nbsp; </td>\n";
    }
    else {
      print "    <td><a href=\"mailto:$username\"><nobr>$username</nobr></a></td>\n";
    }
    if ($ENV{'SEC_LEVEL'} <= 4) {
      print "    <td><a href=\"$ENV{'SCRIPT_NAME'}\?mode=edit_invoice\&email=$username\&invoice_no=$invoice_no\"><nobr>$invoice_no</nobr></a></td>\n";
    }
    else {
      print "    <td><a href=\"$ENV{'SCRIPT_NAME'}\?mode=view_invoice\&email=$username\&invoice_no=$invoice_no\"><nobr>$invoice_no</nobr></a></td>\n";
    }
    print "    <td><nobr>$account_no</nobr></td>\n";
    printf ("    <td>%02d\/%02d\/%04d</td>\n", substr($enter_date,4,2), substr($enter_date,6,2), substr($enter_date,0,4));
    printf ("    <td>%02d\/%02d\/%04d</td>\n", substr($expire_date,4,2), substr($expire_date,6,2), substr($expire_date,0,4));
    print "    <td align=right>$amount</td>\n";
    print "    <td>$status</td>\n";
    print "    <td>$orderid</td>\n";
    print "    <td align=right>$billcycle</td>\n";
    print "    <td align=right>$percent</td>\n";
    print "    <td align=right>$monthly</td>\n";
    if ($billpay_merchadmin::feature_list{'billpay_allow_partial'} eq 'yes') {
      print "    <td align=right>$remnant</td>\n";
    }
    print "    <td align=right>$balance</td>\n";

    print "<td>\n";

    print "<table border=0 cellpadding=0 cellspacing=0>\n";
    print "  <tr>\n";

    print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"view_invoice\">\n";
    print "<input type=hidden name=\"email\" value=\"$username\">\n";
    print "<input type=hidden name=\"invoice_no\" value=\"$invoice_no\">\n";
    print "<input type=submit class=\"button\" value=\"View\">\n";
    print "</td></form>\n";

    if ($ENV{'SEC_LEVEL'} <= 4) {
      print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
      print "<input type=hidden name=\"mode\" value=\"edit_invoice\">\n";
      print "<input type=hidden name=\"email\" value=\"$username\">\n";
      print "<input type=hidden name=\"invoice_no\" value=\"$invoice_no\">\n";
      print "<input type=submit class=\"button\" value=\"Edit\">\n";
      print "</td></form>\n";

      if ($billpay_merchadmin::feature_list{'billpay_remove_invoice'} == 1) {
        print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
        print "<input type=hidden name=\"mode\" value=\"delete_invoice\">\n";
        print "<input type=hidden name=\"email\" value=\"$username\">\n";
        print "<input type=hidden name=\"invoice_no\" value=\"$invoice_no\">\n";
        print "<input type=submit class=\"button\" value=\"Remove\">\n";
        print "</td></form>\n";
      }
    }

    if (($expire_date > $today) && (($status eq '') || ($status eq 'open'))) {
      if ($ENV{'SEC_LEVEL'} <= 8) {
        print "    <td><form method=post action=\"/billpay_express.cgi\" target=\"billpay\">\n";
        print "<input type=hidden name=\"merchant\" value=\"$billpay_merchadmin::merchant\">\n";
        print "<input type=hidden name=\"cobrand\" value=\"$billpay_merchadmin::query{'merch_company'}\">\n";
        print "<input type=hidden name=\"email\" value=\"$username\">\n";
        print "<input type=hidden name=\"invoice_no\" value=\"$invoice_no\">\n";
        print "<input type=submit class=\"button\" value=\"Express Pay\">\n";
        print "</form></td>\n";
      }
      else {
         print "    <td>&nbsp;</td>\n";
      }
    }

    print "  </tr>\n";
    print "</table>\n";

    print "</td>\n";
    print "  </tr>\n";

    $color = ($color + 1) % 2;
  } 

  $sth->finish;

  if ($count == 0) {
    print "  <tr>\n";
    print "    <td colspan=11 align=center><h3>Sorry no invoices matched your search criteria.</h3></td>\n";
    print "  </tr>\n";
  }

  print "</table>\n";

  print "<p><form action=\"$ENV{'SCRIPT_NAME'}\" method=post><input type=submit class=\"button\" value=\"Main Menu\"></form>\n";

  return;
}

sub delete_invoice {
  # used to remove a specific invoice from the merchant's invoice database.
  my $type = shift;
  my %query = @_;

  # do data filtering & other checks
  # login email address filter
  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} = lc($query{'email'});
  my ($is_ok, $reason) = &is_email("$query{'email'}");
  if ($is_ok eq 'problem') {
    print "<p><font color=\"#CC0000\" size=\"+1\">Invalid email address. Please try again.</font></p>\n";
    $query{'error'} = 1;
    &main_menu(%query);
    return;
  }

  if ($query{'invoice_no'} !~ /\w/) {
    print "<p><font color=\"#CC0000\" size=\"+1\">Invalid invoice number. Please try again.</font></p>\n";
    $query{'error'} = 1;
    &main_menu(%query);
    return;
  }

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      DELETE FROM bills2
      WHERE username=?
      AND invoice_no=?
      AND merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute($query{'email'}, $query{'invoice_no'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
  my ($test) = $sth->finish;

  if ($test ne '') {
    my $sth2 = $billpay_merchadmin::dbh->prepare(q{
        DELETE FROM billdetails2
        WHERE username=?
        AND invoice_no=?
        AND merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute($query{'email'}, $query{'invoice_no'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    print "<b>Invoice \'$query{'invoice_no'}\' has been removed from the database.</b>\n";
  }
  else {
    print "<b>Invoice \'$query{'invoice_no'}\' does not exist in the database.</b>\n";
  }

  print "<br>&nbsp;<br>\n";

  #print "<p><form action=\"$ENV{'SCRIPT_NAME'}\" method=post><input type=submit class=\"button\" value=\"Main Menu\"></form>\n";

  &main_menu();

  return;
}

sub search_clients {
  my $type = shift;
  my %query = @_;

  my %selected;
  if ($query{'sort_by'} !~ /^(username|clientcompany|clientname|clientcity|clientstate|clientcountry)$/) {
    $query{'sort_by'} = "username";
  }
  $selected{"$query{'sort_by'}"} = "<font size=\"+1\">&raquo;</font>";

  my $link = "$ENV{'SCRIPT_NAME'}\?mode=list_clients";

  print "<b>Clicking on the email address, will allow you to email that customer.</b>\n";
  if ($query{'mode'} eq 'list_clients') {
    if ($ENV{'SEC_LEVEL'} <= 4) {
      print "<br>&bull; Click on the Edit button to update their contact info.\n";
    }
    print "<br>&bull; Click on the View button to see their contact info.\n";

    if ($ENV{'SEC_LEVEL'} <= 4) {
      print "<br>&bull; Click on the Remove button to remove their contact info.\n";
    }
  }
  print "<br>&bull; The \'<font size=\"+1\">&raquo;</font>\' character shows what column the list is currently sorted by.\n";
  print "<br>&bull; To re-organize the list, click on the column's title you wish to sort by.\n";

  print "<table border=0 cellspacing=0 cellpadding=0 width=760 class=\"table_list\">\n";
  print "  <tr class=\"sectiontitle\">\n";
  print "    <th><a href=\"$link\&sort_by=username\">$selected{'username'}Email</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=clientcompany\">$selected{'clientcompany'}Company</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=clientname\">$selected{'clientname'}Name</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=clientcity\">$selected{'clientcity'}City</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=clientstate\">$selected{'clientstate'}State</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=clientcountry\">$selected{'clientcountry'}Country</a></th>\n";
  if ($billpay_merchadmin::feature_list{'billpay_showconsolidate'} eq 'yes') {
    print "    <th>Consolidate</th>\n";
  }
  if ($query{'mode'} eq 'search_clients') {
    print "    <th width=\"12%\">&nbsp;</th>\n";
  }
  print "  </tr>\n";

  my $color = 1;
  my $count = 0;

  my @placeholder = ();
  my $qstr = "SELECT *";
  $qstr .= " FROM client_contact";
  $qstr .= " WHERE merchant=?";
  push(@placeholder, $billpay_merchadmin::merchant);

  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} = lc($query{'email'});
  if ($query{'email'} ne '') {
    $qstr .= " AND username LIKE ?";
    push(@placeholder, "\%$query{'email'}\%");
  }

  if ($query{'clientcompany'} ne '') {
    $qstr .= " AND clientcompany LIKE ?";
    push(@placeholder, "\%$query{'clientcompany'}\%");
  }

  if ($query{'clientname'} ne '') {
    $qstr .= " AND clientname LIKE ?";
    push(@placeholder, "\%$query{'clientname'}\%");
  }

  if ($query{'clientaddr1'} ne '') {
    $qstr .= " AND clientaddr1 LIKE ?";
    push(@placeholder, "\%$query{'clientaddr1'}\%");
  }

  if ($query{'clientaddr2'} ne '') {
    $qstr .= " AND clientaddr2 LIKE ?";
    push(@placeholder, "\%$query{'clientaddr2'}\%");
  }

  if ($query{'clientcity'} ne '') {
    $qstr .= " AND clientcity LIKE ?";
    push(@placeholder, "\%$query{'clientcity'}\%");
  }

  $query{'clientstate'} = substr($query{'clientstate'},0,2);
  $query{'clientstate'} = uc($query{'clientstate'});
  if ($query{'clientstate'} ne '') {
    $qstr .= " AND clientstate LIKE ?";
    push(@placeholder, "\%$query{'clientstate'}\%");
  }

  if ($query{'clientzip'} ne '') {
    $qstr .= " AND clientzip LIKE ?";
    push(@placeholder, "\%$query{'clientzip'}\%");
  }

  $query{'clientcountry'} = substr($query{'clientcountry'},0,2);
  $query{'clientcountry'} = uc($query{'clientcountry'});
  if ($query{'clientcountry'} ne '') {
    $qstr .= " AND clientcountry LIKE ?";
    push(@placeholder, "\%$query{'clientcountry'}\%");
  }

  if ($query{'clientphone'} ne '') {
    $qstr .= " AND clientphone LIKE ?";
    push(@placeholder, "\%$query{'clientphone'}\%");
  }

  if ($query{'clientfax'} ne '') {
    $qstr .= " AND clientfax LIKE ?";
    push(@placeholder, "\%$query{'clientfax'}\%");
  }

  $query{'clientid'} = lc($query{'clientid'});
  if ($query{'clientid'} ne '') {
    $qstr .= " AND clientid LIKE ?";
    push(@placeholder, "\%$query{'clientid'}\%");
  }

  $query{'alias'} = lc($query{'alias'});
  if ($query{'alias'} ne '') {
    $qstr .= " AND alias LIKE ?";
    push(@placeholder, "\%$query{'alias'}\%");
  }

  $query{'consolidate'} =~ s/^(yes)$//g;
  if ($query{'consolidate'} ne '') {
    $qstr .= " AND consolidate=?";
    push(@placeholder, "yes");
  }

  $qstr .= " ORDER BY $query{'sort_by'}";

  my $sth = $billpay_merchadmin::dbh->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
  my $rc = $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  if ($rc >= 1) {
    while (my $results = $sth->fetchrow_hashref()) {
      $count = $count + 1;

      foreach my $key (keys %$results) {
        if ($results->{$key} !~ /\w/) {
          $results->{$key} = "&nbsp;";
        }
      }

      if ($color == 1) {
        print "  <tr class=\"listrow_color1\">\n";
      }
      else {
        print "  <tr class=\"listrow_color0\">\n";
      }

      if ($results->{'username'} =~ /(\.pnp)$/) {
        print "    <td><nobr> &nbsp; </nobr></td>\n";
      }
      else {
        print "    <td><nobr><a href=\"mailto:$results->{'username'}\">$results->{'username'}</a></nobr></td>\n";
      }
      print "    <td><nobr>$results->{'clientcompany'}</nobr></td>\n";
      print "    <td><nobr>$results->{'clientname'}</nobr></td>\n";
      print "    <td><nobr>$results->{'clientcity'}</nobr></td>\n";
      print "    <td><nobr>$results->{'clientstate'}</nobr></td>\n";
      print "    <td><nobr>$results->{'clientcountry'}</nobr></td>\n";
      if ($billpay_merchadmin::feature_list{'billpay_showconsolidate'} eq 'yes') {
        print "    <td><nobr>$results->{'consolidate'}</nobr></td>\n";
      }
      if ($query{'mode'} eq 'search_clients') {
        print "    <td>";

        print "<table border=0 cellpadding=0 cellspacing=0>\n";
        print "  <tr>\n";

        print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
        print "<input type=hidden name=\"mode\" value=\"view_client\">\n";
        print "<input type=hidden name=\"email\" value=\"$results->{'username'}\">\n";
        print "<input type=submit class=\"button\" value=\"View\">\n";
        print "</td></form>\n";

        if ($ENV{'SEC_LEVEL'} <= 4) {
          print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
          print "<input type=hidden name=\"mode\" value=\"edit_client\">\n";
          print "<input type=hidden name=\"email\" value=\"$results->{'username'}\">\n";
          print "<input type=submit class=\"button\" value=\"Edit\">\n";
          print "</td></form>\n";
        }

        if ($ENV{'SEC_LEVEL'} <= 4) {
          print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
          print "<input type=hidden name=\"mode\" value=\"delete_client\">\n";
          print "<input type=hidden name=\"email\" value=\"$results->{'username'}\">\n";
          print "<input type=submit class=\"button\" value=\"Remove\">\n";
          print "</td></form>\n";
        }

        print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
        print "<input type=hidden name=\"mode\" value=\"search_invoices\">\n";
        print "<input type=hidden name=\"email\" value=\"$results->{'username'}\">\n";
        print "<input type=submit class=\"button\" value=\"Invoices\">\n";
        print "</td></form>\n";

        print "  </tr>\n";
        print "</table>\n";

        print "</td>\n";
      }
      print "  </tr>\n";

      $color = ($color + 1) % 2;
    }
  }
  $sth->finish;

  if ($count == 0) {
    print "  <tr>\n";
    print "    <td colspan=7 align=center><h3>Sorry no contacts matched your search criteria.</h3></td>\n";
    print "  </tr>\n";
  }
  
  print "</table>\n";

  return;
}

sub list_clients_form {
  my $type = shift;
  my %query = @_;

  my %selected;
  if ($query{'sort_by'} !~ /^(username|clientcompany|clientname|clientcity|clientstate|clientcountry)$/) {
    $query{'sort_by'} = "username";
  }
  $selected{"$query{'sort_by'}"} = "<font size=\"+1\">&raquo;</font>";

  my $link = "$ENV{'SCRIPT_NAME'}\?mode=list_clients";

  print "<b>Clicking on the email address, will allow you to email that customer.</b>\n";
  if ($query{'mode'} eq 'list_clients') {
    if ($ENV{'SEC_LEVEL'} <= 4) {
      print "<br>&bull; Click on the Edit button to update their contact info.\n";
    }
    print "<br>&bull; Click on the View button to see their contact info.\n";
    
    if ($ENV{'SEC_LEVEL'} <= 4) {
      print "<br>&bull; Click on the Remove button to remove their contact info.\n";
    }
  }
  print "<br>&bull; The \'<font size=\"+1\">&raquo;</font>\' character shows what column the list is currently sorted by.\n";
  print "<br>&bull; To re-organize the list, click on the column's title you wish to sort by.\n";

  print "<table border=0 cellspacing=0 cellpadding=0 width=760 class=\"table_list\">\n";
  print "  <tr class=\"sectiontitle\">\n";
  print "    <th><a href=\"$link\&sort_by=username\">$selected{'username'}Email</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=clientcompany\">$selected{'clientcompany'}Company</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=clientname\">$selected{'clientname'}Name</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=clientcity\">$selected{'clientcity'}City</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=clientstate\">$selected{'clientstate'}State</a></th>\n";
  print "    <th><a href=\"$link\&sort_by=clientcountry\">$selected{'clientcountry'}Country</a></th>\n";
  if ($query{'mode'} eq 'list_clients') {
    print "    <th>Consolidate</th>\n";
    print "    <th width=\"12%\">&nbsp;</th>\n";
  }
  print "  </tr>\n";

  my $color = 1;

  my $sth = $billpay_merchadmin::dbh->prepare(qq{
      SELECT *
      FROM client_contact
      WHERE merchant=?
      ORDER BY $query{'sort_by'}
    }) or die "Can't do: $DBI::errstr";
  my $rc = $sth->execute($billpay_merchadmin::merchant) or die "Can't execute: $DBI::errstr";
  if ($rc >= 1) {
    while (my $results = $sth->fetchrow_hashref()) {

      foreach my $key (keys %$results) {
        if ($results->{$key} !~ /\w/) {
          $results->{$key} = "&nbsp;";
        }
      }

      if ($color == 1) {
        print "  <tr class=\"listrow_color1\">\n";
      }
      else {
        print "  <tr class=\"listrow_color0\">\n";
      }

      if ($results->{'username'} =~ /(\.pnp)$/) {
        print "    <td><nobr> &nbsp; </nobr></td>\n";
      }
      else {
        print "    <td><nobr><a href=\"mailto:$results->{'username'}\">$results->{'username'}</a></nobr></td>\n";
      }
      print "    <td><nobr>$results->{'clientcompany'}</nobr></td>\n";
      print "    <td><nobr>$results->{'clientname'}</nobr></td>\n";
      print "    <td><nobr>$results->{'clientcity'}</nobr></td>\n";
      print "    <td><nobr>$results->{'clientstate'}</nobr></td>\n";
      print "    <td><nobr>$results->{'clientcountry'}</nobr></td>\n";
      if ($query{'mode'} eq 'list_clients') {
        print "    <td><nobr>$results->{'consolidate'}</nobr></td>\n";
        print "    <td>";

        print "<table border=0 cellpadding=0 cellspacing=0>\n";
        print "  <tr>\n";

        print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
        print "<input type=hidden name=\"mode\" value=\"view_client\">\n";
        print "<input type=hidden name=\"email\" value=\"$results->{'username'}\">\n";
        print "<input type=submit class=\"button\" value=\"View\">\n";
        print "</td></form>\n";

        if ($ENV{'SEC_LEVEL'} <= 4) {
          print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
          print "<input type=hidden name=\"mode\" value=\"edit_client\">\n";
          print "<input type=hidden name=\"email\" value=\"$results->{'username'}\">\n";
          print "<input type=submit class=\"button\" value=\"Edit\">\n";
          print "</td></form>\n";
        }

        if ($ENV{'SEC_LEVEL'} <= 4) {
          print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
          print "<input type=hidden name=\"mode\" value=\"delete_client\">\n";
          print "<input type=hidden name=\"email\" value=\"$results->{'username'}\">\n";
          print "<input type=submit class=\"button\" value=\"Remove\">\n";
          print "</td></form>\n";
        }

        print "    <td><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
        print "<input type=hidden name=\"mode\" value=\"search_invoices\">\n";
        print "<input type=hidden name=\"email\" value=\"$results->{'username'}\">\n";
        print "<input type=submit class=\"button\" value=\"Invoices\">\n";
        print "</td></form>\n";

        print "  </tr>\n";
        print "</table>\n";

        print "</td>\n";
      }
      print "  </tr>\n";

      $color = ($color + 1) % 2;
    }
  }
  $sth->finish;

  if ($rc == 0) {
    print "  <tr>\n";
    print "    <td colspan=6 align=center><h3>Sorry you currently have no contacts on file.</h3></td>\n";
    print "  </tr>\n";
  }

  print "</table>\n";

  return;
}

sub delete_client {
  # used to remove a specific client contact from the merchant's contact list.
  my $type = shift;
  my %query = @_;

  # do data filtering & other checks
  # login email address filter
  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} = lc($query{'email'});
  my ($is_ok, $reason) = &is_email("$query{'email'}");
  if ($is_ok eq 'problem') {
    print "<p><font color=\"#CC0000\" size=\"+1\">Invalid email address. Please try again.</font></p>\n";
    $query{'error'} = 1;
    &manage_clients_menu();
    return;
  }

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      DELETE FROM client_contact
      WHERE username=?
      AND merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute($query{'email'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
  $sth->finish;

  print "<b>Contact \'$query{'email'}\' has been removed from your contact list.</b>\n";

  print "<br>&nbsp;<br>\n";
  &manage_clients_menu();

  return;
}

sub client_form {
  my $type = shift;
  my %query = @_;

  my %data;
  if (($query{'email'} ne '') && ($query{'error'} != 1)) {
    my %data2 = &get_client_contact_data(%query);
    %data = (%data, %data2);

    foreach my $key (keys %data) {
      $query{$key} = $data{$key};
    }
  }

  print "Minimum required fields are marked with a \'<b>*</b>\'.<br>\n";

  print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post name=\"client_form\">\n";
  print "<input type=hidden name=\"mode\" value=\"update_client\">\n";
  if ($query{'email'} ne '') {
    print "<input type=hidden name=\"invoice_no\" value=\"$query{'invoice_no'}\">\n";
  }

  # format: ['field_name', 'size', 'maxlength', 'type', 'title', 'field_value|current_setting', 'comment/option(s)']
  my @fields1 = (
    ['clientcompany', 40,  40, 'text',        'Company',         "$query{'clientcompany'}",   ''],
    ['clientname',    40,  40, 'text',        'Name',            "$query{'clientname'}",      ''],
    ['clientaddr1',   40,  40, 'text',        'Address Line 1',  "$query{'clientaddr1'}",     ''],
    ['clientaddr2',   40,  40, 'text',        'Address Line 2',  "$query{'clientaddr2'}",     ''],
    ['clientcity',    40,  40, 'text',        'City',            "$query{'clientcity'}",      ''],
    ['clientstate',    2,   2, 'select_hash', 'State',           "$query{'clientstate'}",     'USstates'],
    ['clientzip',     14,  14, 'text',        'Zip/Postal Code', "$query{'clientzip'}",       ''],
    ['clientcountry',  2,   2, 'select_hash', 'Country',         "$query{'clientcountry'}",   'countries'],
    ['clientphone',   15,  15, 'text',        'Phone',           "$query{'clientphone'}",     ''],
    ['clientfax',     15,  15, 'text',        'Fax',             "$query{'clientfax'}",       '']
  );

  if ($query{'email'} =~ /(\.pnp)$/) {
    unshift(@fields1, ['email', 40, 255, 'hidden', '', "$query{'email'}", ''] );
  }
  else {
    unshift(@fields1, ['email', 40, 255, 'text', 'Email *', "$query{'email'}", "<i>[i.e. customer\@somedomain\.com]</i>"] );
  }

  my @fields2 = (
    ['clientid',      40, 255, 'text',     'Client ID',      "$query{'clientid'}",        "<i>[i.e. QuickBooks Customer Account # or Unique Customer ID]</i>"],
    ['alias',         20,  20, 'text',     'Alias',          "$query{'alias'}",           "<i>Enter client alias, if applicable.</i>"]
  );

  if ($billpay_merchadmin::feature_list{'billpay_showconsolidate'} eq 'yes') {
    push(@fields2, ['consolidate', 0, 0, 'checkbox', 'Consolidate', "yes|$query{'consolidate'}", "Check to permit invoice consolidation."]);
  }

  print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Customer Contact:</b></legend>\n";
  &print_fields(@fields1);
  print "</fieldset>\n";

  print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Optional Data:</b></legend>\n";
  &print_fields(@fields2);
  print "</fieldset>\n";

  print "<p><input type=submit class=\"button\" value=\"Submit Contact\"> &nbsp; <input type=reset class=\"button\" value=\"Reset Contact\"></p>\n";

  print "</form>\n";

  return;
}

sub update_client {
  my $type = shift;
  my %query = @_;

  my $data;

  if ($query{'old_email'} =~ /(\.pnp)$/) {
    $query{'email'} = $query{'old_email'}    
  }

  # do data filtering & other checks
  # login email address filter
  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} = lc($query{'email'});
  my ($is_ok, $reason) = &is_email("$query{'email'}");
  if ($is_ok eq 'problem') {
    print "<p><font color=\"#CC0000\" size=\"+1\">Invalid email address. Please try again.</font></p>\n";
    $query{'error'} = 1;
    &client_form(%query);
    return;
  }

  if (exists $query{'clientstate'}) {
    $query{'clientstate'} = substr($query{'clientstate'},0,2);
    $query{'clientstate'} = uc($query{'clientstate'});
  }
  if (exists $query{'clientcountry'}) {
    $query{'clientcountry'} = substr($query{'clientcountry'},0,2);
    $query{'clientcountry'} = uc($query{'clientcountry'});
  }
  if (exists $query{'clientid'}) {
    $query{'clientid'} = lc($query{'clientid'});
  }
  if (exists $query{'alias'}) {
    $query{'alias'} = lc($query{'alias'});
  }

  if ($query{'consolidate'} ne 'yes') {
    $query{'consolidate'} = '';
  }

  # check for clientID existance
  if ($query{'clientid'} ne '') {
    my $sth0a = $billpay_merchadmin::dbh->prepare(q{
        SELECT username, clientname, clientcompany, clientid, alias
        FROM client_contact
        WHERE clientid=?
        AND merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    my $rc = $sth0a->execute($query{'clientid'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
    my ($db_username, $db_clientname, $db_clientcompany, $db_clientid, $db_alias) = $sth0a->fetchrow;
    $sth0a->finish;

    if (($rc >= 1) && ($query{'email'} ne "$db_username")) {
      print "<p><font color=\"#CC0000\" size=\"+1\">ClientID \'$db_clientid\' already in use by client "; 
      if (($db_clientname ne '') || ($db_clientcompany ne '')) {
        print "$db_clientcompany - $db_clientname";
      }
      else {
        print "email: $db_username";
      }
      print ". Please try again.</font></p>\n";
      $query{'error'} = 1;
      &client_form(%query);
      return;
    }
  }

  # start by checking for client existance
  my $sth1a = $billpay_merchadmin::dbh->prepare(q{
      SELECT username
      FROM client_contact
      WHERE username=?
      AND merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  my $rc = $sth1a->execute($query{'email'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
  my ($db_username) = $sth1a->fetchrow;
  $sth1a->finish;

  if ($db_username eq "$query{'email'}") {
    if (($query{'clientname'} ne '') || ($query{'clientcompany'} ne '')) {
      # if match was found, allow the update to happen
      # * Notes: - Only allow update to happen, when clientname or clientcompany is defined
      #          - We don't want to overwrite existing client contact info, when the details are undefined.
      #          - We do however want to update the contact info if it's defined, as we assume all the details were provided 
      #          - Bascially it's an all or nothing update process.
      my $sth2a = $billpay_merchadmin::dbh->prepare(q{
          UPDATE client_contact
          SET clientname=?, clientcompany=?, clientaddr1=?, clientaddr2=?, clientcity=?, clientstate=?, clientzip=?, clientcountry=?, clientphone=?, clientfax=?, clientid=?, alias=?, consolidate=?
          WHERE username=?
          AND merchant=?
        }) or die "Cannot prepare: $DBI::errstr";
      $sth2a->execute($query{'clientname'}, $query{'clientcompany'}, $query{'clientaddr1'}, $query{'clientaddr2'}, $query{'clientcity'}, $query{'clientstate'}, $query{'clientzip'}, $query{'clientcountry'}, $query{'clientphone'}, $query{'clientfax'}, $query{'clientid'}, $query{'alias'}, $query{'consolidate'}, $query{'email'}, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
      $sth2a->finish;

      print "<b>Contact \'$query{'email'}\' has been updated in your contact list.</b>\n";
    }
  }
  else {
    # if no match was found, allow the insert to happen
    my $sth2a = $billpay_merchadmin::dbh->prepare(q{
        INSERT INTO client_contact
        (merchant, username, clientname, clientcompany, clientaddr1, clientaddr2, clientcity, clientstate, clientzip, clientcountry, clientphone, clientfax, clientid, alias, consolidate)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2a->execute($billpay_merchadmin::merchant, $query{'email'}, $query{'clientname'}, $query{'clientcompany'}, $query{'clientaddr1'}, $query{'clientaddr2'}, $query{'clientcity'}, $query{'clientstate'}, $query{'clientzip'}, $query{'clientcountry'}, $query{'clientphone'}, $query{'clientfax'}, $query{'clientid'}, $query{'alias'}, $query{'consolidate'}) or die "Cannot execute: $DBI::errstr";
    $sth2a->finish;

    print "<b>Contact \'$query{'email'}\' has been added to your contact list.</b>\n";
  }

  print "<br>&nbsp;<br>\n";
  &manage_clients_menu();

  return;
}

sub export_clients {
  my $type = shift;
  my %query = @_;

  my $eol = ''; # set end of line break character
  if ($billpay_merchadmin::feature_list{'billpay_filetype'} eq 'dos') {
    $eol = "\r\n";
  }
  elsif ($billpay_merchadmin::feature_list{'billpay_filetype'} eq 'mac') {
    $eol = "\r";
  }
  else { # use unix default
    $eol = "\n";
  }

  if ($query{'format'} =~ /^(table)$/) {
    print "Content-Type: text/html\n";
    print "X-Content-Type-Options: nosniff\n";
    print "X-Frame-Options: SAMEORIGIN\n\n";
    &html_head('Exported Clients');
    print "<div align=center>\n";
  }
  elsif ($query{'format'} =~ /^(text)$/) {
    print "Content-Type: text/plain\n";
    print "X-Content-Type-Options: nosniff\n";
    print "X-Frame-Options: SAMEORIGIN\n\n";
  }
  else {
    print "Content-Type: text/tab-separated-values\n";
    print "X-Content-Type-Options: nosniff\n";
    print "X-Frame-Options: SAMEORIGIN\n";
    print "Content-Disposition: attachment; filename=\"export.txt\"\n\n";
  }

  # get merchant's company name
  my $dbh_pnpmisc = &miscutils::dbhconnect("pnpmisc");
  my $sth2 = $dbh_pnpmisc->prepare(q{
      SELECT company
      FROM customers
      WHERE username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth2->execute($billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
  my ($db_merch_company) = $sth2->fetchrow;
  $sth2->finish;
  $dbh_pnpmisc->disconnect;

  if ($query{'format'} =~ /^(table)$/) {
#    print "<table border=1 cellspacing=0 cellpadding=2 width=760>\n";
#    print "  <tr class=\"listrow_color0\">\n";

    print "<table border=0 cellspacing=0 cellpadding=0 width=760 class=\"table_list\">\n";
    print "  <tr class=\"sectiontitle\">\n";
    print "    <th>Email</th>\n";
    print "    <th>Name</th>\n";
    print "    <th>Company</th>\n";
    print "    <th>Address1</th>\n";
    print "    <th>Address2</th>\n";
    print "    <th>City</th>\n";
    print "    <th>State</th>\n";
    print "    <th>Zip</th>\n";
    print "    <th>Country</th>\n";
    print "    <th>Phone</th>\n";
    print "    <th>Fax</th>\n";
    print "    <th>ClientID</th>\n";
    print "    <th>Consolidate</th>\n";
    print "    <th>Alias</th>\n";
    print "  </tr>\n";
  }
  else {
    print "!BATCH\temail\tclientname\tclientcompany\tclientaddr1\tclientaddr2\tclientcity\tclientstate\tclientzip\tclientcountry\tclientphone\tclientfax\tclientid\tconsolidate\talias$eol";
  }

  my $color = 1;

  my $sth = $billpay_merchadmin::dbh->prepare(q{
      SELECT *
      FROM client_contact
      WHERE merchant=?
      ORDER BY username
    }) or die "Can't do: $DBI::errstr";
  my $rc = $sth->execute($billpay_merchadmin::merchant) or die "Can't execute: $DBI::errstr";
  if ($rc >= 1) {
    while (my $results = $sth->fetchrow_hashref()) {
      if ($query{'format'} =~ /^(table)$/) {

        foreach my $key (keys %$results) {
          if ($results->{$key} !~ /\w/) {
            $results->{$key} = "&nbsp;";
          }
        }

        if ($color == 1) {
          print "  <tr class=\"listrow_color1\">\n";
        }
        else {
          print "  <tr class=\"listrow_color0\">\n";
        }
        if ($results->{'username'} =~ /(\.pnp)$/) {
          print "    <td><nobr> &nbsp; </nobr></td>\n";
        }
        else {
          print "    <td><nobr><a href=\"mailto:$results->{'username'}\">$results->{'username'}</a></nobr></td>\n";
        }
        print "    <td><nobr>$results->{'clientname'}</nobr></td>\n";
        print "    <td><nobr>$results->{'clientcompany'}</nobr></td>\n";
        print "    <td><nobr>$results->{'clientaddr1'}</nobr></td>\n";
        print "    <td><nobr>$results->{'clientaddr2'}</nobr></td>\n";
        print "    <td><nobr>$results->{'clientcity'}</nobr></td>\n";
        print "    <td><nobr>$results->{'clientstate'}</nobr></td>\n";
        print "    <td><nobr>$results->{'clientzip'}</nobr></td>\n";
        print "    <td><nobr>$results->{'clientcountry'}</nobr></td>\n";
        print "    <td><nobr>$results->{'clientphone'}</nobr></td>\n";
        print "    <td><nobr>$results->{'clientfax'}</nobr></td>\n";
        print "    <td><nobr>$results->{'clientid'}</nobr></td>\n";
        print "    <td><nobr>$results->{'consolidate'}</nobr></td>\n";
        print "    <td><nobr>$results->{'alias'}</nobr></td>\n";
        print "  </tr>\n";

        $color = ($color + 1) % 2;
      }
      else {
        print "billpay_client\t$results->{'username'}\t$results->{'clientname'}\t$results->{'clientcompany'}\t$results->{'clientaddr1'}\t$results->{'clientaddr2'}\t$results->{'clientcity'}\t$results->{'clientstate'}\t$results->{'clientzip'}\t$results->{'clientcountry'}\t$results->{'clientphone'}\t$results->{'clientfax'}\t$results->{'clientid'}\t$results->{'consolidate'}\t$results->{'alias'}$eol";
      }
    }
  }
  $sth->finish;

  if ($rc == 0) {
    if ($query{'format'} =~ /^(table)$/) {
      print "  <tr>\n";
      print "    <td colspan=6 align=center><h3>Sorry you currently have no contacts on file.</h3></td>\n";
      print "  </tr>\n";
    }
    else {
      print "Sorry you currently have no contacts on file.\n";
    }
  }

  if ($query{'format'} =~ /^(table)$/) {
    print "</table>\n";
    print "<br>\n";

    print "</div>\n";
    &html_tail();
  }

  return;
}

sub view_client_form {
  my $type = shift;
  my %query = @_;

  my %data;
  if (($query{'email'} ne '') && ($query{'error'} != 1)) {
    my %data2 = &get_client_contact_data(%query);
    %data = (%data, %data2);
  }

  if (($billpay_merchadmin::feature_list{'billpay_unknown_email'} eq 'yes') && ($query{'email'} =~ /(\.pnp)$/i)) {
    $query{'email'} = " "; 
  }

  # format: ['field_name', 'size', 'maxlength', 'type', 'title', 'field_value|current_setting', 'comment/option(s)']
  my @fields1 = (
    ['email',          0, 0, 'justtext', 'Email',           "$query{'email'}",           ''],
    ['clientcompany',  0, 0, 'justtext', 'Company',         "$query{'clientcompany'}",   ''],
    ['clientname',     0, 0, 'justtext', 'Name',            "$query{'clientname'}",      ''],
    ['clientaddr1',    0, 0, 'justtext', 'Address Line 1',  "$query{'clientaddr1'}",     ''],
    ['clientaddr2',    0, 0, 'justtext', 'Address Line 2',  "$query{'clientaddr2'}",     ''],
    ['clientcity',     0, 0, 'justtext', 'City',            "$query{'clientcity'}",      ''],
    ['clientstate',    0, 0, 'justtext', 'State',           "$query{'clientstate'}",     ''],
    ['clientzip',      0, 0, 'justtext', 'Zip/Postal Code', "$query{'clientzip'}",       ''],
    ['clientcountry',  0, 0, 'justtext', 'Country',         "$query{'clientcountry'}",   ''],
    ['clientphone',    0, 0, 'justtext', 'Phone',           "$query{'clientphone'}",     ''],
    ['clientfax',      0, 0, 'justtext', 'Fax',             "$query{'clientfax'}",       '']
  );

  my @fields2 = (
    ['clientid',       0, 0, 'justtext', 'Client ID',       "$query{'clientid'}",        ''],
    ['alias',          0, 0, 'justtext', 'Alias',           "$query{'alias'}",           ''],
    ['consolidate',    0, 0, 'justtext', 'Consolidate',     "$query{'consolidate'}",     '']
  );

  print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Customer Contact:</b></legend>\n";
  &print_fields(@fields1);
  print "</fieldset>\n";

  print "<fieldset style=\"width: 97%; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Optional Data:</b></legend>\n";
  &print_fields(@fields2);
  print "</fieldset>\n";

  if ($query{'email'} =~ /\w/) {
    print "<p><form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
    print "<input type=hidden name=\"mode\" value=\"search_invoices\">\n";
    print "<input type=hidden name=\"email\" value=\"$query{'email'}\">\n";
    print "<input type=submit class=\"button\" value=\"List Invoices\">\n";
    print "</form>\n";
  }

  print "<p><form action=\"$ENV{'SCRIPT_NAME'}\" method=post><input type=submit class=\"button\" value=\"Main Menu\"></form>\n";

  return;
}

sub get_appendix_hash {
  my ($hash_name) = @_;

  my %data;

  if ($hash_name eq 'USstates') {
    # holds hash of US states
    %data = ("AL","Alabama","AK","Alaska","AZ","Arizona",
             "AR","Arkansas","CA","California","CO","Colorado","CT","Connecticut","DE","Delaware",
             "DC","District of Columbia","FL","Florida","GA","Georgia","HI","Hawaii","ID","Idaho",
             "IL","Illinois","IN","Indiana","IA","Iowa","KS","Kansas","KY","Kentucky","LA","Louisiana",
             "ME","Maine","MD","Maryland","MA","Massachusetts","MI","Michigan","MN","Minnesota","MS","Mississippi",
             "MO","Missouri","MT","Montana","NE","Nebraska","NV","Nevada","NH","New Hampshire","NJ","New Jersey",
             "NM","New Mexico","NY","New York","NC","North Carolina","ND","North Dakota","OH","Ohio","OK","Oklahoma",
             "OR","Oregon","PA","Pennsylvania","PR","Puerto Rico",
             "RI","Rhode Island","SC","South Carolina","SD","South Dakota","TN","Tennessee",
             "TX","Texas","UT","Utah","VT","Vermont","VI","Virgin Islands","VA","Virginia","WA","Washington",
             "WV","West Virginia","WI","Wisconsin","WY","Wyoming");
  }
  elsif ($hash_name eq 'countries') {
    # holds hash of world countries
    %data = ("AF","AFGHANISTAN","AL","ALBANIA","DZ","ALGERIA","AS","AMERICAN SAMOA","AD","ANDORRA",
             "AO","ANGOLA","AI","ANGUILLA","AQ","ANTARCTICA","AG","ANTIGUA AND BARBUDA","AR","ARGENTINA",
             "AM","ARMENIA","AW","ARUBA","AU","AUSTRALIA","AT","AUSTRIA","AZ","AZERBAIJAN","BS","BAHAMAS",
             "BH","BAHRAIN","BD","BANGLADESH","BB","BARBADOS","BY","BELARUS","BE","BELGIUM","BZ","BELIZE",
             "BJ","BENIN","BM","BERMUDA","BT","BHUTAN","BO","BOLIVIA","BA","BOSNIA AND HERZEGOVINA",
             "BW","BOTSWANA","BV","BOUVET ISLAND","BR","BRAZIL","IO","BRITISH INDIAN OCEAN TERRITORY",
             "BN","BRUNEI DARUSSALAM","BG","BULGARIA","BF","BURKINA FASO","BI","BURUNDI","KH","CAMBODIA",
             "CM","CAMEROON","CA","CANADA","CV","CAPE VERDE","KY","CAYMAN ISLANDS","CF","CENTRAL AFRICAN REPUBLIC",
             "TD","CHAD","CL","CHILE","CN","CHINA","CX","CHRISTMAS ISLAND","CC","COCOS (KEELING) ISLANDS",
             "CO","COLOMBIA","KM","COMOROS","CG","CONGO","CD","CONGO, THE DEMOCRATIC REPUBLIC OF THE",
             "CK","COOK ISLANDS","CR","COSTA RICA","CI","COTE D'IVOIRE","HR","CROATIA","CU","CUBA",
             "CY","CYPRUS","CZ","CZECH REPUBLIC","DK","DENMARK","DJ","DJIBOUTI","DM","DOMINICA",
             "DO","DOMINICAN REPUBLIC","TP","EAST TIMOR","EC","ECUADOR","EG","EGYPT","SV","EL SALVADOR",
             "GQ","EQUATORIAL GUINEA","ER","ERITREA","EE","ESTONIA","ET","ETHIOPIA","FK","FALKLAND ISLANDS (MALVINAS)",
             "FO","FAROE ISLANDS","FJ","FIJI","FI","FINLAND","FR","FRANCE","GF","FRENCH GUIANA",
             "PF","FRENCH POLYNESIA","TF","FRENCH SOUTHERN TERRITORIES","GA","GABON","GM","GAMBIA",
             "GE","GEORGIA","DE","GERMANY","GH","GHANA","GI","GIBRALTAR","GR","GREECE","GL","GREENLAND",
             "GD","GRENADA","GP","GUADELOUPE","GU","GUAM","GT","GUATEMALA","GN","GUINEA","GW","GUINEA-BISSAU",
             "GY","GUYANA","HT","HAITI","HM","HEARD ISLAND AND MCDONALD ISLANDS","VA","HOLY SEE (VATICAN CITY STATE)",
             "HN","HONDURAS","HK","HONG KONG","HU","HUNGARY","IS","ICELAND","IN","INDIA","ID","INDONESIA",
             "IR","IRAN, ISLAMIC REPUBLIC OF","IQ","IRAQ","IE","IRELAND","IL","ISRAEL","IT","ITALY",
             "JM","JAMAICA","JP","JAPAN","JO","JORDAN","KZ","KAZAKSTAN","KE","KENYA","KI","KIRIBATI",
             "KP","KOREA, DEMOCRATIC PEOPLE'S REPUBLIC OF","KR","KOREA, REPUBLIC OF","KW","KUWAIT",
             "KG","KYRGYZSTAN","LA","LAO PEOPLE'S DEMOCRATIC REPUBLIC","LV","LATVIA","LB","LEBANON",
             "LS","LESOTHO","LR","LIBERIA","LY","LIBYAN ARAB JAMAHIRIYA","LI","LIECHTENSTEIN",
             "LT","LITHUANIA","LU","LUXEMBOURG","MO","MACAU","MK","MACEDONIA, THE FORMER YUGOSLAV REPUBLIC OF",
             "MG","MADAGASCAR","MW","MALAWI","MY","MALAYSIA","MV","MALDIVES","ML","MALI","MT","MALTA",
             "MH","MARSHALL ISLANDS","MQ","MARTINIQUE","MR","MAURITANIA","MU","MAURITIUS","YT","MAYOTTE",
             "MX","MEXICO","FM","MICRONESIA, FEDERATED STATES OF","MD","MOLDOVA, REPUBLIC OF",
             "MC","MONACO","MN","MONGOLIA","MS","MONTSERRAT","MA","MOROCCO","MZ","MOZAMBIQUE",
             "MM","MYANMAR","NA","NAMIBIA","NR","NAURU","NP","NEPAL","NL","NETHERLANDS","AN","NETHERLANDS ANTILLES",
             "NC","NEW CALEDONIA","NZ","NEW ZEALAND","NI","NICARAGUA","NE","NIGER","NG","NIGERIA",
             "NU","NIUE","NF","NORFOLK ISLAND","MP","NORTHERN MARIANA ISLANDS","NO","NORWAY",
             "OM","OMAN","PK","PAKISTAN","PW","PALAU","PS","PALESTINIAN TERRITORY, OCCUPIED",
             "PA","PANAMA","PG","PAPUA NEW GUINEA","PY","PARAGUAY","PE","PERU","PH","PHILIPPINES",
             "PN","PITCAIRN","PL","POLAND","PT","PORTUGAL","PR","PUERTO RICO","QA","QATAR","RE","REUNION",
             "RO","ROMANIA","RU","RUSSIAN FEDERATION","RW","RWANDA","SH","SAINT HELENA","KN","SAINT KITTS AND NEVIS",
             "LC","SAINT LUCIA","PM","SAINT PIERRE AND MIQUELON","VC","SAINT VINCENT AND THE GRENADINES",
             "WS","SAMOA","SM","SAN MARINO","ST","SAO TOME AND PRINCIPE","SA","SAUDI ARABIA",
             "SN","SENEGAL","SC","SEYCHELLES","SL","SIERRA LEONE","SG","SINGAPORE","SK","SLOVAKIA",
             "SI","SLOVENIA","SB","SOLOMON ISLANDS","SO","SOMALIA","ZA","SOUTH AFRICA","GS","SOUTH GEORGIA AND THE SOUTH SANDWICH ISLANDS",
             "ES","SPAIN","LK","SRI LANKA","SD","SUDAN","SR","SURINAME","SJ","SVALBARD AND JAN MAYEN",
             "SZ","SWAZILAND","SE","SWEDEN","CH","SWITZERLAND","SY","SYRIAN ARAB REPUBLIC","TW","TAIWAN",
             "TJ","TAJIKISTAN","TZ","TANZANIA, UNITED REPUBLIC OF","TH","THAILAND","TG","TOGO",
             "TK","TOKELAU","TO","TONGA","TT","TRINIDAD AND TOBAGO","TN","TUNISIA","TR","TURKEY",
             "TM","TURKMENISTAN","TC","TURKS AND CAICOS ISLANDS","TV","TUVALU","UG","UGANDA",
             "UA","UKRAINE","AE","UNITED ARAB EMIRATES","GB","UNITED KINGDOM","US","UNITED STATES",
             "UM","UNITED STATES MINOR OUTLYING ISLANDS","UY","URUGUAY","UZ","UZBEKISTAN","VU","VANUATU",
             "VE","VENEZUELA","VN","VIET NAM","VG","VIRGIN ISLANDS, BRITISH","VI","VIRGIN ISLANDS, U.S.",
             "WF","WALLIS AND FUTUNA","EH","WESTERN SAHARA","YE","YEMEN","YU","YUGOSLAVIA","ZM","ZAMBIA",
             "ZW","ZIMBABWE");
  }
  elsif ($hash_name eq 'USterritories') {
    ## US Territories list
    %data = ("AA","Armed Forces America","AE","Armed Forces Other Areas","AS","American Samoa",
             "AP","Armed Forces Pacific","GU","Guam","MH","Marshall Islands","FM","Micronesia",
             "MP","Northern Mariana Islands","PW","Palau");
  }
  elsif ($hash_name eq 'CNprovinces') {
    # CN Provinces list
    %data = ("","-- Country other than USA or Canada --","AB","Alberta","BC","British Columbia",
             "NB","New Brunswick","MB","Manitoba","NF","Newfoundland","NT","Northwest Territories","NS","Nova Scotia","NU","Nunavit",
             "ON","Ontario","PE","Prince Edward Island","QC","Quebec","SK","Saskatchewan","YT","Yukon");
  }
  elsif ($hash_name eq 'USCNprov') {
    ## USCN Provinces list
    %data = ("AB","Alberta","BC","British Columbia",
             "NB","New Brunswick","MB","Manitoba","NF","Newfoundland","NT","Northwest Territories","NS","Nova Scotia","NU","Nunavit",
             "ON","Ontario","PE","Prince Edward Island","QC","Quebec","SK","Saskatchewan","YT","Yukon");
  }

  return %data;
}

sub email_customer_html {
  my %query = @_;

  # prevent email from being sent to sudo email addresses
  if ($query{'email'} =~ /(\.pnp)$/) {
    return;
  }

  # TODO: Implement way to detect/filter sensitive data (such as full CC#s) when performing field substitutions.

  # send email to customer
  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setGatewayAccount($billpay_merchadmin::merchant);
  $emailObj->setFormat('html');

  $emailObj->setTo($query{'email'});
  if ($billpay_merchadmin::feature_list{'billpay_email_merch'} eq 'yes') {
    if ($query{'merch_pubemail'} ne '') {
      $emailObj->setBCC($query{'merch_pubemail'});
    } else { 
      $emailObj->setBCC($billpay_merchadmin::feature_list{'pubemail'});
    }
  }

  if ($query{'merch_pubemail'} ne '') {
    $emailObj->setFrom($query{'merch_pubemail'});
  } elsif ($billpay_merchadmin::feature_list{'pubemail'} ne '') {
    $emailObj->setFrom($billpay_merchadmin::feature_list{'pubemail'});
  } else {
    $emailObj->setFrom('billpaysupport@plugnpay.com');
  }

  my $subject = $billpay_language::lang_titles{'emailcust_html_subject'};
  $subject =~ s/\[pnp_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
  $emailObj->setSubject($subject);

  my $emailmessage = '';

  $emailmessage .= "<HTML>\r\n";
  $emailmessage .= "<HEAD>\r\n";

  my $path_web = &pnp_environment::get('PNP_WEB');

  $emailmessage .= "<style type=\"text/css\">\r\n";

  my $css_file = "$path_web/css/style_billpay.css";
  if ($billpay_merchadmin::feature_list{'css-link'} ne "") {
    $css_file = "$path_web/logos/upload/css/$billpay_merchadmin::merchant\.css";
  }
  open(CSS,'<',"$css_file");
  while(<CSS>) {
    my $theline = $_;
    $emailmessage .= "$theline";
  }
  close(CSS);
  $emailmessage .= "</style>\r\n";

  $emailmessage .= "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; CHARSET=UTF-8\">\r\n";
  $emailmessage .= "</HEAD>\r\n";

  $emailmessage .= "<BODY>\r\n";

  if ($billpay_language::template{'body_html_emailmessage'} =~ /\w/) {
    # Use this to replace our default message with a custom formatted email notification.
    $emailmessage .= "$billpay_language::template{'body_html_emailmessage'}\r\n";

  }
  else {
    $emailmessage .= "<p>$billpay_language::lang_titles{'emailcust_html_new_invoice'}\r\n\r\n";

    $emailmessage .= "<p>$billpay_language::lang_titles{'emailcust_html_view_invoice'}\r\n";
    $emailmessage .= "<br><a href=\"https://$ENV{'SERVER_NAME'}/billpay/edit.cgi\?merchant\=$billpay_merchadmin::merchant\&function\=view_bill_details_form\&invoice_no\=[pnp_invoice_no]\">$billpay_language::lang_titles{'emailcust_link_viewinvoice'}</a>\r\n";

    $emailmessage .= "\r\n";
    $emailmessage .= "<p>$billpay_language::lang_titles{'emailcust_html_free_signup'}\r\n";
    $emailmessage .= "<br><a href=\"https://$ENV{'SERVER_NAME'}/billpay_signup.cgi\?merchant\=$billpay_merchadmin::merchant\">$billpay_language::lang_titles{'emailcust_link_signup'}</a>\r\n";

    $emailmessage .= "\r\n";
    $emailmessage .= "<p>$billpay_language::lang_titles{'emailcust_html_signup_reason'}\r\n";

    if ($query{'express_pay'} eq 'yes') {
      $emailmessage .= "\r\n";
      $emailmessage .= "<p>$billpay_language::lang_titles{'emailcust_html_expresspay'}\r\n";
      $emailmessage .= "<br><a href=\"https://$ENV{'SERVER_NAME'}/billpay_express.cgi\?merchant\=$billpay_merchadmin::merchant\&email\=[pnp_email]\&invoice_no\=[pnp_invoice_no]\">$billpay_language::lang_titles{'emailcust_link_expresspay'}</a>\r\n";
    }

    $emailmessage .= "\r\n";
    if ($query{'merch_pubemail'} ne '') {
      $emailmessage .= "<p>$billpay_language::lang_titles{'emailcust_html_contact_merch2'}\r\n\r\n";
    }
    else {
      $emailmessage .= "<p>$billpay_language::lang_titles{'emailcust_html_contact_merch1'}\r\n\r\n";
    }

    $emailmessage .= "<p>$billpay_language::lang_titles{'emailcust_html_thankyou'}\r\n\r\n";
  }

  if ($billpay_merchadmin::feature_list{'billpay_suppress_invoice'} ne 'yes') {
    if ($billpay_language::template{'body_html_invoice'} !~ /\w/) {
      $emailmessage .= "<br><hr><br>\r\n";
    }
    $emailmessage .= &email_bill_details(%query);
  }

  $emailmessage .= "</BODY>\r\n";
  $emailmessage .= "</HTML>\r\n";

  $emailmessage =~ s/\[pnp_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);

  $emailObj->setContent($emailmessage);
  $emailObj->send();
}

sub email_bill_details {
  my %query = @_;

  my $data;

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  $data .= "<table border=0 cellspacing=0 cellpadding=5 width=\"100%\">\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><h1>$billpay_language::lang_titles{'service_title'} / $billpay_language::lang_titles{'service_subtitle_billdetails'}</h1></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td bgcolor=\"#f4f4f4\" valign=top width=60><p>  </p></td>\n";
  $data .= "    <td>";
  $data .= "<table border=0 cellspacing=0 cellpadding=2 width=700>\n";

  $query{'amount'} = sprintf("%0.02f", $query{'amount'});
  $query{'tax'} = sprintf("%0.02f", $query{'tax'});
  $query{'shipping'} = sprintf("%0.02f", $query{'shipping'});
  $query{'handling'} = sprintf("%0.02f", $query{'handling'});
  $query{'discount'} = sprintf("%0.02f", $query{'discount'});

  if ($query{'balance'} ne '') { $query{'balance'} = sprintf("%0.02f", $query{'balance'}); }

  if ($query{'monthly'} > 0) { $query{'monthly'} = sprintf("%0.02f", $query{'monthly'}); }
  if ($query{'percent'} > 0) { $query{'percent'} = sprintf("%f", $query{'percent'}); }
  if ($query{'remnant'} > 0) { $query{'remnant'} = sprintf("%0.02f", $query{'remnant'}); }

  # calculate installment amount
  if (($query{'balance'} > 0) && (($query{'monthly'} > 0) || ($query{'percent'} > 0))) {
    if ($query{'percent'} > 0) {
      # figure out percentage installment amount
      $query{'installment'} = ($query{'percent'} / 100) * $query{'balance'};
      if (($query{'percent'} > 0) && ($query{'installment'} < $query{'monthly'})) {
        # now if installment is less then monthly minimim, charge the minimum
        $query{'installment'} = $query{'monthly'};
      }
    }
    else {
      # when invoice is only monthly based, set the monthly amount for the installment amount.
      $query{'installment'} = $query{'monthly'};
    }

    # apply remnant, if less then installment amount
    if (($query{'remnant'} > 0) && ($query{'installment'} > $query{'remnant'})) {
      $query{'installment'} = $query{'remnant'};
    }

    # now if the balenace is less then the installment amount, charge the remaining balance only
    if ($query{'installment'} > $query{'balance'}) {
      $query{'installment'} = $query{'balance'};
    }
  }

  if ($query{'installment'} > 0) {
    $query{'installment'} = sprintf("%0.02f", $query{'installment'});
  }

  my $enter = sprintf("%02d\/%02d\/%04d", substr($query{'enter_date'},4,2), substr($query{'enter_date'},6,2), substr($query{'enter_date'},0,4));
  my $expire = sprintf("%02d\/%02d\/%04d", substr($query{'expire_date'},4,2), substr($query{'expire_date'},6,2), substr($query{'expire_date'},0,4));

  if (($query{'status'} eq 'open') && ($query{'expire_date'} < $today)) {
    # change the status on screen, to show as expired
    $query{'status'} = 'expired';
  }

  ## pre-generate customer section
  my $data_cust = '';
  if (($query{'clientname'} ne '') || ($query{'clientcompany'} ne '')) {
    $data_cust .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
    $data_cust .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_customer'}</b></legend>\n";
    $data_cust .= "<p>";
    if ($query{'clientname'} ne '') {
      $data_cust .= "$query{'clientname'}<br>\n";
    }
    if ($query{'clientcompany'} ne '') {
      $data_cust .= "$query{'clientcompany'}<br>\n";
    }
    if ($query{'clientaddr1'} ne '') {
      $data_cust .= "$query{'clientaddr1'}<br>\n";
    }
    if ($query{'clientaddr2'} ne '') {
      $data_cust .= "$query{'clientaddr2'}<br>\n";
    }
    if ($query{'clientcity'} ne '') {
      $data_cust .= "$query{'clientcity'} \n";
    }
    if ($query{'clientstate'} ne '') {
      $data_cust .= "$query{'clientstate'} \n";
    }
    if ($query{'clientzip'} ne '') {
      $data_cust .= "$query{'clientzip'} \n";
    }
    if ($query{'clientcountry'} ne '') {
      $data_cust .= "$query{'clientcountry'}\n";
    }
    if ($query{'clientphone'} ne '') {
      $data_cust .= "$query{'clientphone'} \n";
    }
    if ($query{'clientfax'} ne '') {
      $data_cust .= "$query{'clientfax'} \n";
    }
    $data_cust .= "</p>\n";
    $data_cust .= "</fieldset>\n";
  }

  ## pre-generate shipping section
  my $data_ship = '';
  if (($query{'shipname'} ne '') || ($query{'shipcompany'} ne '')) {
    $data_ship .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
    $data_ship .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_shipping'}</b></legend>\n";
    $data_ship .= "<p>";
    if ($query{'shipname'} ne '') {
      $data_ship .= "$query{'shipname'}<br>\n";
    }
    if ($query{'shipcompany'} ne '') {
      $data_ship .= "$query{'shipcompany'}<br>\n";
    }
    if ($query{'shipaddr1'} ne '') {
      $data_ship .= "$query{'shipaddr1'}<br>\n";
    }
    if ($query{'shipaddr2'} ne '') {
      $data_ship .= "$query{'shipaddr2'}<br>\n";
    }
    if ($query{'shipcity'} ne '') {
      $data_ship .= "$query{'shipcity'} \n";
    }
    if ($query{'shipstate'} ne '') {
      $data_ship .= "$query{'shipstate'} \n";
    }
    if ($query{'shipzip'} ne '') {
      $data_ship .= "$query{'shipzip'} \n";
    }
    if ($query{'shipcountry'} ne '') {
      $data_ship .= "$query{'shipcountry'}\n";
    }
    if ($query{'shipphone'} ne '') {
      $data_ship .= "$query{'shipphone'} \n";
    }
    if ($query{'shipfax'} ne '') {
      $data_ship .= "$query{'shipfax'} \n";
    }
    $data_ship .= "</p>\n";
    $data_ship .= "</fieldset>\n";
  }

  ## pre-generate invoice info
  my $data_info = '';
  $data_info .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
  $data_info .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_invoiceinfo'}</b></legend>\n";
  $data_info .= "<p>$billpay_language::lang_titles{'invoice_no'} $query{'invoice_no'}\n";
  if ($query{'account_no'} =~ /\w/) {
    $data_info .= "<br>$billpay_language::lang_titles{'account_no'} $query{'account_no'}\n";
  }
  $data_info .= "<br>$billpay_language::lang_titles{'enterdate'} $enter\n";
  $data_info .= "<br>$billpay_language::lang_titles{'expiredate'} $expire\n";
  $data_info .= "<br>$billpay_language::lang_titles{'status'} $query{'status'}\n";
  if ($query{'orderid'} =~ /\w/) {
    $data_info .= "<br>$billpay_language::lang_titles{'orderid'} $query{'orderid'}\n";
  }
  if (($billpay_merchadmin::feature_list{'billpay_showalias'} eq 'yes') && ($query{'alias'} =~ /\w/)) {
    $data_info .= "<br>$billpay_language::lang_titles{'alias'} $query{'alias'}\n";
  }
  $data_info .= "</p>\n";
  $data_info .= "</fieldset>\n";

  ## start generating the actual invoice's HTML 
  $data .= "<b>$query{'merch_company'}</b>\n";

  $data .= $billpay_language::template{'body_merchcontact'};

  $data .= "<table width=700>\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=4><hr width=\"100%\"></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  if (($data_cust ne '') && ($data_ship eq '')) {
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_cust</td>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_info</td>\n";
  }
  elsif (($data_cust eq '') && ($data_ship ne '')) {
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_ship</td>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_info</td>\n";
  }
  else {
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">  </td>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_info</td>\n";
  }
  $data .= "  </tr>\n";

  if (($data_cust ne '') && ($data_ship ne '')) {
    $data .= "  <tr>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_cust</td>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_ship</td>\n";
    $data .= "  </tr>\n";
  }

  $data .= "  <tr>\n";
  $data .= "    <td colspan=4><hr width=\"100%\"></td>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  my $subtotal = 0;
  my $totalwgt = 0;

  my $i = 0;
  my ($db_item, $db_cost, $db_qty, $db_descr, $db_weight, $db_descra, $db_descrb, $db_descrc);

  my $data2 = ''; 
  for (my $j = 1; $j <= 30; $j++) {
    if (($query{"item$j"} ne '') && ($query{"descr$j"} ne '') && ($query{"qty$j"} ne '') && ($query{"cost$j"} ne '')) {
      $data2 .= "  <tr>\n";

      my %cols = ();
      $cols{'item'}  = sprintf ("    <td>%s</td>\n", $query{"item$j"});
      $cols{'descr'} = sprintf ("    <td>%s</td>\n", $query{"descr$j"});
      $cols{'qty'}   = sprintf ("    <td>%s</td>\n", $query{"qty$j"});
      $cols{'cost'}  = sprintf ("    <td>%s</td>\n", $query{"cost$j"});
      if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /weight/)) {
        $cols{'weight'} = sprintf ("    <td>%s</td>\n", $query{"weight$j"});
      }
      if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /descra/)) {
        $cols{'descra'} = sprintf ("    <td>%s</td>\n", $query{"descra$j"});
      }
      if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /descrb/)) {
        $cols{'descrb'} = sprintf ("    <td>%s</td>\n", $query{"descrb$j"});
      }
      if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /descrc/)) {
        $cols{'descrc'} = sprintf ("    <td>%s</td>\n", $query{"descrc$j"});
      }

      if ($billpay_merchadmin::feature_list{'billpay_displayorder'} ne '') {
        my @list = split(/\|/, $billpay_merchadmin::feature_list{'billpay_displayorder'});
        for (my $l = 0; $l <= $#list; $l++) {
          if ($list[$l] =~ /\w/) {
            $data2 .= $cols{"$list[$l]"};
          }
        }
      }
      else {
        if ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /item/) {
          $data2 .= $cols{'item'};
        }
        $data2 .= $cols{'descr'};
        $data2 .= $cols{'qty'};
        $data2 .= $cols{'cost'};
        if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /weight/)) {
          $data2 .= $cols{'weight'};
        }
        if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /descra/)) {
          $data2 .= $cols{'descra'};
        }
        if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /descrb/)) {
          $data2 .= $cols{'descrb'};
        }
        if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /descrc/)) {
          $data2 .= $cols{'descrc'};
        }
      }
      $data2 .= "  </tr>\n";

      $i++;
      $subtotal += ($query{"cost$j"} * $query{"qty$j"});
      $totalwgt += ($query{"weight$j"} * $query{"qty$j"});
    }
  }

  if ($data2 ne '') {
    $data .= "<table width=700 class=\"invoice\">\n";
    $data .= "  <tr>\n";
    $data .= "    <td colspan=4 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_productdetails'}</b></p></td>\n";
    $data .= "  </tr>\n";

    my %cols = ();
    $cols{'item'}  = "    <th valign=top align=left width=\"8%\"><p>$billpay_language::lang_titles{'column_item'}</p></th>\n";
    $cols{'descr'} = "    <th valign=top align=left width=\"\"><p>$billpay_language::lang_titles{'column_descr'}</p></th>\n";
    $cols{'qty'}   = "    <th valign=top align=left width=\"8%\"><p>$billpay_language::lang_titles{'column_qty'}</p></th>\n";
    $cols{'cost'}  = "    <th valign=top align=left width=\"14%\"><p>$billpay_language::lang_titles{'column_cost'}</p></th>\n";
    if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /weight/)) {
      $cols{'weight'} = "    <th valign=top align=left><p>$billpay_language::lang_titles{'column_weight'}</p></th>\n";
    }
    if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /descra/)) {
      $cols{'descra'} = "    <th valign=top align=left><p>$billpay_language::lang_titles{'column_descra'}</p></th>\n";
    }
    if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /descrb/)) {
      $cols{'descrb'} = "    <th valign=top align=left><p>$billpay_language::lang_titles{'column_descrb'}</p></th>\n";
    }
    if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /descrc/)) {
      $cols{'descrc'} = "    <th valign=top align=left><p>$billpay_language::lang_titles{'column_descrc'}</p></th>\n";
    }

    $data .= "  <tr>\n";
    if ($billpay_merchadmin::feature_list{'billpay_displayorder'} ne '') {
      my @list = split(/\|/, $billpay_merchadmin::feature_list{'billpay_displayorder'});
      for (my $l = 0; $l <= $#list; $l++) {
        if ($list[$l] =~ /\w/) {
          $data .= $cols{"$list[$l]"};
        }
      }
    }
    else {
      if ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /item/) {
        $data .= $cols{'item'};
      }
      $data .= $cols{'descr'};
      $data .= $cols{'qty'};
      $data .= $cols{'cost'};
      if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /weight/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /weight/)) {
        $data .= $cols{'weight'};
      }
      if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descra/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /descra/)) {
        $data .= $cols{'descra'};
      }
      if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrb/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /descrb/)) {
        $data .= $cols{'descrb'};
      }
      if (($billpay_merchadmin::feature_list{'billpay_extracols'} =~ /descrc/) && ($billpay_merchadmin::feature_list{'billpay_showcols'} =~ /descrc/)) {
        $data .= $cols{'descrc'};
      }
    }
    $data .= "  </tr>\n";

    $data .= $data2;

    $data .= "</table>\n";

    if ($billpay_merchadmin::feature_list{'billpay_totalwgt'} == 1) {
      $totalwgt = sprintf("%s", $totalwgt);
      $data .= "<div align=left><p><b>$billpay_language::lang_titles{'totalwgt'}</b> $totalwgt lbs.</p></div>\n";
    }
  }

  $data .= "<table width=700>\n";
  if ($i >= 1) {
    $data .= "  <tr>\n";
    $data .= "    <td colspan=4><hr width=\"100%\"></td>\n";
    $data .= "  </tr>\n";
  }

  $data .= "  <tr>\n";
  $data .= "    <td width=\"77%\" valign=top><fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
  $data .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_paymentdetails'}</b></legend>\n";

  if ($query{'balance'} > 0) {
    $data .= "<p><table border=1 class=\"invoice\">\n";

    $data .= "  <tr>\n";
    $data .= "    <th align=right><p>Current Balance</p></th>\n";
    $data .= "    <td align=right><p>$query{'balance'}</p></td>\n";
    $data .= "  </tr>\n";

    if ((($query{'percent'} > 0) || ($query{'monthly'} > 0)) && ($query{'billcycle'} > 0)) {
      if ($query{'percent'} > 0) {
        $data .= "  <tr>\n";
        $data .= "    <th align=right><p>$billpay_language::lang_titles{'percentage'}</p></th>\n";
        $data .= "    <td align=right><p>$query{'percent'}%</p></td>\n";
        $data .= "  </tr>\n";

        if ($query{'monthly'} > 0) {
          $data .= "  <tr>\n";
          $data .= "    <th align=right><p>$billpay_language::lang_titles{'installment_min'}</p></th>\n";
          $data .= "    <td align=right><p>$query{'monthly'}</p></td>\n";
          $data .= "  </tr>\n";
        }
      }
      else {
        $data .= "  <tr>\n";
        $data .= "    <th align=right><p>$billpay_language::lang_titles{'installment_fee'}</p></th>\n";
        $data .= "    <td align=right><p>$query{'monthly'}</p></td>\n";
        $data .= "  </tr>\n";
      }

      $data .= "  <tr>\n";
      if ($query{'remnant'} > 0) {
        $data .= "    <th align=right><p>$billpay_language::lang_titles{'remnant'}</p></th>\n";
      }
      else {
        $data .= "    <th align=right><p>$billpay_language::lang_titles{'monthly'}</p></th>\n";
      }
      $data .= "    <td align=right><p>$query{'installment'}</p></td>\n";
      $data .= "  </tr>\n";
    }

    #$data .= "  <tr>\n";
    #$data .= "    <th align=right><p>$billpay_language::lang_titles{'billcycle'}</p></th>\n";
    #$data .= "    <td align=right><p>$query{'billcycle'} Month(s)</p></td>\n";
    #$data .= "  </tr>\n";

    if ($query{'lastbilled'} ne '') {
      my $lastbilled = sprintf("%02d\/%02d\/%04d", substr($query{'lastbilled'},4,2), substr($query{'lastbilled'},6,2), substr($query{'lastbilled'},0,4));
      $data .= "  <tr>\n";
      $data .= "    <th align=right><p>$billpay_language::lang_titles{'lastbilled'}</p></th>\n";
      $data .= "    <td align=right><p>$lastbilled</p></td>\n";
      $data .= "  </tr>\n";
    }

    #if ($query{'lastattempted'} ne '') {
    #  my $lastattempted = sprintf("%02d\/%02d\/%04d", substr($query{'lastattempted'},4,2), substr($query{'lastattempted'},6,2), substr($query{'lastattempted'},0,4));
    #  $data .= "  <tr>\n";
    #  $data .= "    <th align=right><p>$billpay_language::lang_titles{'lastattempted'}</p></th>\n";
    #  $data .= "    <td align=right><p>$query{'lastattempted'}</p></td>\n";
    #  $data .= "  </tr>\n";
    #}

    $data .= "</table>\n";
  }

  if (($query{'status'} eq 'open') && ($query{'expire_date'} >= $today)) {
    $data .= "<p><table border=0 cellspacing=0 cellpadding=2>\n";

    $data .= "  <tr>\n";
    $data .= "    <td><p>$billpay_language::lang_titles{'statement_accepts'}\n";
    $data .= "<br><b>$billpay_merchadmin::feature_list{'billpay_cardsallowed'}</b>\n";
    $data .= "<br> </p>\n";
    $data .= "</td>\n";
    $data .= "  </tr>\n";

    # show consolidate options/status as necessary.
    if ($query{'consolidate'} eq 'yes') {
      if ($query{'consolidate'} eq 'yes') {
        $data .= "  <tr>\n";
        $data .= "    <td><p><b><i>$billpay_language::lang_titles{'statement_consolidate_flag'}</i></b></p></td>\n";
        $data .= " </tr>\n";
      }
      else {
        $data .= "  <tr>\n";
        $data .= "    <td><p>&nbsp;</p></td>\n";
        $data .= " </tr>\n";

        $data .= "  <tr>\n";
        $data .= "    <td><p><b><i>$billpay_language::lang_titles{'statement_consolidate'}</i></b></p></td>\n";
        $data .= " </tr>\n";
      }

      # outoput consolidation warning for installment based invoices, in necessary.
      if (($query{'monthly'} > 0) || ($query{'percent'} > 0) || ($query{'billcycle'} > 0)) {
        $data .= "  <tr>\n";
        $data .= "    <td><p><b>$billpay_language::lang_titles{'warn_consolidation'}</b></p></td>\n";
        $data .= " </tr>\n";
      }
    }

    $data .= "</table>\n";

    if ($billpay_language::template{'body_html_invoice'} =~ /\w/) {
      # shoehorn in replacement page, as we need to be able to re-use all the calculated values
      $data = $billpay_language::template{'body_html_invoice'}; # replace with invoice layout from template

      $data =~ s/\[paybill_form\]//g; # remove paybill submit form/button

      $data =~ s/\[frameset_cust\]/$data_cust/g; # customer information chunk
      $data =~ s/\[frameset_ship\]/$data_ship/g; # shipping information chunk
      $data =~ s/\[frameset_info\]/$data_info/g; # invoice information chunk

      $data =~ s/\[merch_company]/$query{'merch_company'}/g;
      $data =~ s/\[merch_pubemail]/$query{'merch_pubemail'}/g;

      for (my $k = 1; $k <= 30; $k++) {
        if ($query{"qty$k"} < 0.01) {
          $query{"cost$k"} = '';
        }
        $data =~ s/\[payform_item$k\]/$query{"item$k"}/g; # for SSv1 fields
        $data =~ s/\[payform_cost$k\]/$query{"cost$k"}/g; # for SSv1 fields
        $data =~ s/\[payform_quantity$k\]/$query{"qty$k"}/g; # for SSv1 fields
        $data =~ s/\[payform_description$k\]/$query{"descr$k"}/g; # for SSv1 fields
        $data =~ s/\[payform_weight$k\]/$query{"weight$k"}/g; # for SSv1 fields
        $data =~ s/\[payform_descra$k\]/$query{"descra$k"}/g; # for SSv1 fields
        $data =~ s/\[payform_descrb$k\]/$query{"descrb$k"}/g; # for SSv1 fields
        $data =~ s/\[payform_descrc$k\]/$query{"descrc$k"}/g; # for SSv1 fields
      }

      $data =~ s/\[payform_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g; # for SSv1 fields
      $data =~ s/\[payform2_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g; # for SSv2 fields

      $data =~ s/\[lang_([a-zA-Z0-9\-\_]*)\]/$billpay_language::lang_titles{$1}/g;
      $data =~ s/\[client_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
      $data =~ s/\[invoice_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
      $data =~ s/\[query_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
    }
  }
  elsif ($query{'status'} eq 'expired') {
    $data .= "<p><b>$billpay_language::lang_titles{'statement_invoice_expired'}</b>\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_merchassist1'} $query{'merch_company'} $billpay_language::lang_titles{'statement_merchassist2'}</p>\n";
  }
  elsif ($query{'status'} eq 'closed') {
    $data .= "<p><b>$billpay_language::lang_titles{'statement_invoice_closed'}</b>\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_merchassist1'} $query{'merch_company'} $billpay_language::lang_titles{'statement_merchassist2'}</p>\n";
  }
  elsif ($query{'status'} eq 'hidden') {
    $data .= "<p><b>$billpay_language::lang_titles{'statement_invoice_hidden'}</b>\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_merchassist1'} $query{'merch_company'} $billpay_language::lang_titles{'statement_merchassist2'}</p>\n";
  }
  elsif ($query{'status'} eq 'merged') {
    $data .= "<p><b>$billpay_language::lang_titles{'statement_invoice_merged'}</b>\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_merchassist1'} $query{'merch_company'} $billpay_language::lang_titles{'statement_merchassist2'}</p>\n";
  }
  elsif ($query{'status'} eq 'paid') {
    $data .= "<p><b>$billpay_language::lang_titles{'statement_invoice_paid'}</b>\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_merchassist1'} $query{'merch_company'} $billpay_language::lang_titles{'statement_merchassist2'}</p>\n";
  }

  if ($billpay_language::template{'body_html_invoice'} !~ /\w/) {
    $data .= "</p>\n";
    $data .= "</fieldset></td>\n";

    $subtotal = sprintf("%0.02f", $subtotal);

    $data .= "    <td valign=top><table width=\"100%\" class=\"invoice\">\n";
   if ($subtotal > 0) { 
      $data .= "  <tr>\n";
      $data .= "    <th width=\"50%\" align=right nowrap><p>$billpay_language::lang_titles{'subtotal'}</p></th>\n";
      $data .= "    <td width=\"50%\" align=right><p>$subtotal</p></td>\n";
      $data .= "  </tr>\n";
   }
   if ($query{'shipping'} > 0) {
      $data .= "  <tr>\n";
      $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'shipping'}</p></th>\n";
      $data .= "    <td align=right><p>$query{'shipping'}</p></td>\n";
      $data .= "  </tr>\n";
    }
    if ($query{'handling'} > 0) {
      $data .= "  <tr>\n";
      $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'handling'}</p></th>\n";
      $data .= "    <td align=right><p>$query{'handling'}</p></td>\n";
      $data .= "  </tr>\n";
    }
    if ($query{'discount'} > 0) {
      $data .= "  <tr>\n";
      $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'discount'}</p></th>\n";
      $data .= "    <td align=right><p>$query{'discount'}</p></td>\n";
      $data .= "  </tr>\n";
    }
    if ($query{'tax'} > 0) {
      $data .= "  <tr>\n";
      $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'tax'}</p></th>\n";
      $data .= "    <td align=right><p>$query{'tax'}</p></td>\n";
      $data .= "  </tr>\n";
    }
    $data .= "  <tr>\n";
    $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'amount'}</p></th>\n";
    $data .= "    <td align=right><p>$query{'amount'}</p></td>\n";
    $data .= "  </tr>\n";
    $data .= "</table></td>\n";
    $data .= "  </tr>\n";
    $data .= "</table>\n";

    $data .= "<table width=700>\n";
    $data .= "  <tr>\n";
    $data .= "    <td colspan=2><hr width=\"100%\"></td>\n";
    $data .= "  </tr>\n";

    if ($query{'datalink_url'} ne '') {
      if ($billpay_merchadmin::feature_list{'billpay_datalink_type'} =~ /^(post|get)$/) {
        # use datalink form post/get format
        $data .= "  <tr>\n";
        $data .= "    <td align=left><b>$billpay_language::lang_titles{'datalink'}</b></td>\n";
        $data .= "    <td valign=top align=left><p><form name=\"datalink\" action=\"$query{'datalink_url'}\" method=\"$billpay_merchadmin::feature_list{'billpay_datalink_type'}\" target=\"_blank\">\n";
        if ($query{'datalink_pairs'} ne '') {
          my @pairs = split(/\&/, $query{'datalink_pairs'});
         for (my $i = 0; $i <= $#pairs; $i++) {
            my $pair = $pairs[$i];
            $pair =~ s/\[client_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
            $pair =~ s/\[invoice_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
            $pair =~ s/\[query_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
            my ($name, $value) = split(/\=/, $pair, 2);
            $data .= "<input type=hidden name=\"$name\" value=\"$value\">\n";
          }
        }
        $data .= "<input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_datalink'}\"></form></p></td>\n";
        $data .= "  </tr>\n";
      }
      else {
        # use datalink link format
        my $url = $query{'datalink_url'};
        if ($query{'datalink_pairs'} ne '') {
          $url .= "\?" . $query{'datalink_pairs'};
        }
        $url =~ s/\[client_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
        $url =~ s/\[invoice_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
        $url =~ s/\[query_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;

        $data .= "  <tr>\n";
        $data .= "    <td align=left><p><b>$billpay_language::lang_titles{'datalink'}</b></p></td>\n";
        $data .= "    <td valign=top align=left><p><a href=\"$url\" target=\"_blank\">$billpay_language::lang_titles{'link_datalink'}</a></p></td>\n";
        $data .= "  </tr>\n";
      }
    }

    if ($query{'public_notes'} =~ /\w/) {
      $data .= "  <tr>\n";
      $data .= "    <td align=left><p><b>$billpay_language::lang_titles{'public_notes'}</b></p></td>\n";
      $data .= "    <td valign=top align=left><p>$query{'public_notes'}</p></td>\n";
      $data .= "  </tr>\n";
    }

    $data .= "</table>\n";

    $data .= $billpay_language::template{'body_terms'};

    $data .= "</td>\n";
    $data .= "  </tr>\n";
    $data .= "</table>\n";
  }

  return $data;
}

sub assign_invoices {
  my $type = shift;
  my %query = @_;

  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} = lc($query{'email'}); 

  my ($is_ok, $reason) = &convert_unknown_emails(%query);

  if ($is_ok eq 'problem') {
    print "<p><font color=\"#CC0000\" size=\"+1\">$reason</font></p>\n";
    print "<br><form><input type=button name=\"back_button\" value=\"Return To Previous Page\" onClick=\"javascript:history.go(-1);\"></form>\n";
  }
  else {
    print "<p><font size=\"+1\">$reason</font></p>\n";
    &main_menu(%query);
  }

  return;
}

sub convert_unknown_emails {
  # converts invoices from the unknown email address to customer's real email address.
  my %query = @_;

  my $unknown_email = '';

  # filter & check account number provided (should be clean, but double check)
  if ($query{'account_no'} =~ /\w/) {
    $unknown_email = sprintf("%s\@%s\.%s", $query{'account_no'}, $billpay_merchadmin::merchant, "pnp");
  }
  else {
    return ('problem', "Invalid Account Number");
  }

  # filter & check email address provided (should be clean, but double check)
  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} = lc($query{'email'}); 
  my ($is_ok, $reason) = &is_email("$query{'email'}");
  if ($is_ok eq 'problem') {
    return ('problem', "Invalid Email Address");
  }

  # now update invoices, as necessary.
  my $sth = $billpay_merchadmin::dbh->prepare(q{
      UPDATE bills2
      SET username=?
      WHERE username=?
      AND merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute($query{'email'}, $unknown_email, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
  $sth->finish;

  my $sth2 = $billpay_merchadmin::dbh->prepare(q{
      UPDATE bills2
      SET username=?
      WHERE username=?
      AND merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth2->execute($query{'email'}, $unknown_email, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
  $sth2->finish;

  my $sth3 = $billpay_merchadmin::dbh->prepare(q{
      UPDATE bills2
      SET username=?
      WHERE username=?
      AND merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth3->execute($query{'email'}, $unknown_email, $billpay_merchadmin::merchant) or die "Cannot execute: $DBI::errstr";
  $sth3->finish;

  return ('success', "Invoice Assignment Successful");
}

sub is_email {
  # checks to see if email address supplied is valid or not.
  my ($email) = @_;

  # do data filtering & other checks (should be clean, but double check to be safe)
  # email address filter
  $email =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $email = lc($email);

  # validiate email format
  my $position = index($email,"\@");
  my $position1 = rindex($email,"\.");
  my $elength  = length($email);
  my $pos1 = $elength - $position1;
  if (($position < 1)
     || ($position1 < $position)
     || ($position1 >= $elength - 2)
     || ($elength < 5)
     || ($position > $elength - 5)
   ) {
    return ('problem', "Invalid Email Address");
  }
  else {
    return ('success', "Email Address OK");
  }
}

# used for a numeric sort
sub numerically {$a <=> $b}

