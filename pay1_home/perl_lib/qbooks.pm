package qbooks;

require 5.001;

use CGI;
use DBI;
use miscutils;
use rsautils;
use sysutils;
use PlugNPay::GatewayAccount;
use PlugNPay::Logging::DataLog;
use PlugNPay::Email;
#use strict;

sub new {
  my $type = shift;
  my ($source) = @_;

  ## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
  if ($ENV{'HTTP_X_FORWARDED_FOR'} ne '') {
    $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
  }

  #my (%data);
  $query = new CGI;
  my @params = $query->param;
  foreach my $param (@params) {
    $data{"$param"} = &CGI::escapeHTML($query->param($param));
    #print "KEY:$param:$data{"$param"}<br>\n";
  }

  if (($ENV{'HTTP_COOKIE'} ne "")){
    my (@cookies) = split(/\;/, $ENV{'HTTP_COOKIE'});
    foreach my $var (@cookies) {
      $var =~ /(.*?)=(.*)/;
      my ($name,$value) = ($1,$2);
      #$name = &CGI::escapeHTML($name);
      #$value = &CGI::escapeHTML($value);
      $name =~ s/ //g;
      $cookie{"$name"} = $value;
    }
  }
  ($cookie{'pnpqbend'},$cookie{'pnpqbcshacct'},$cookie{'pnpqbshpacct'},$cookie{'pnpqbtaxacct'},$cookie{'pnpqborderid'},$cookie{'pnpqbcshno'},$cookie{'pnpqbinvno'},$cookie{'pnpqbtaxitem'},$cookie{'pnpqbadjustmentitem'},$cookie{'tobeprinted'},$cookie{'exportcust'},$cookie{'showall'},$cookie{'format'},$cookie{'usecost'},$cookie{'add_recurring'},$cookie{'exclude_vt'}) = split(/\|/, $cookie{'pnpqbdata'});

  my $debugflag = 1;
  $earliest_date = "20050101";

  if ($source ne "private") {
    $data{'username'} = $ENV{"REMOTE_USER"};
  }
  $qbooks::username = $data{'username'};

  $qbooks::gatewayAccount = new PlugNPay::GatewayAccount($qbooks::username);
  $qbooks::accountFeatures = $qbooks::gatewayAccount->getFeatures();

  my ($logDate, $logTime) = &miscutils::gendatetime_only();
  if (($debugflag == 1) && (($qbooks::accountFeatures->get('logOrders') == $logDate))) {
    open (DEBUG,'>>',"/home/pay1/database/debug/qbooks.txt") or die "Cannot open qbooks.txt for appending. $!";
    my $time = gmtime(time);
    print DEBUG "DATE:$time, LOGIN:$ENV{'LOGIN'}, RU:$ENV{'REMOTE_USER'}, IP:$ENV{'REMOTE_ADDR'}, SN:$ENV{'SCRIPT_NAME'}, ";
    foreach my $key (sort keys %data) {
      my ($key1,$val) = &logfilter_in($key,$data{$key});
      print DEBUG "$key1:$val, ";
    }
    foreach my $key (sort keys %cookie) {
      print DEBUG "C:$key:$cookie{$key}, ";
    }
    print DEBUG "\n";
    close (DEBUG);

    #use Datalog
    my $logger = new PlugNPay::Logging::DataLog({collection => 'qbooks'});
    my %logdata  = ();
    $logdata{DATE}  = $time;
    $logdata{LOGIN} = $ENV{'LOGIN'};
    $logdata{RU}    = $ENV{'REMOTE_USER'};
    $logdata{IP}    = $ENV{'REMOTE_ADDR'};
    $logdata{SN}    = $ENV{'SCRIPT_NAME'};

    foreach my $key (sort keys %data) {
        $logdata{$key} = $cookie{$key};
        my ($key1,$val) = &logfilter_in($key,$data{$key});
        $logdata{$key1} = $val;
    }
    foreach my $key (sort keys %cookie) {
      $logdata{$key} = $cookie{$key};
    }
    $logger->log(\%logdata);
  }


  $data{'srchstartdate'} = $data{'startyear'} . $data{'startmon'} . $data{'startday'};
  $data{'srchenddate'} = $data{'endyear'} . $data{'endmon'} . $data{'endday'};

  if ($data{'srchstartdate'} < $earliest_date) {
    $data{'srchstartdate'} = $earliest_date;
  }

  if (($data{'srchstartdate'} ne "") && ($data{'srchenddate'} ne "")) {
    my $tststart = &miscutils::strtotime($data{'srchstartdate'});
    my $tstend = &miscutils::strtotime($data{'srchenddate'});

    my $tsttmp = $tstend - $tststart;
    if ($tsttmp > (93*24*60*60)) {
      print "Content-Type: text/html\n\n";
      print "Sorry, but no more than 3 months may be queried at one time.  Please use the back button and change your selected date range.<br>\n";
      exit;  
    }
  }

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh->prepare(q{
      SELECT reseller, company 
      FROM customers
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
  ($reseller, $merch_company) = $sth->fetchrow;
  $sth->finish();
  $dbh->disconnect;

  $goodcolor = "#000000";
  $badcolor = "#ff0000";
  $backcolor = "#ffffff";
  $fontface = "Arial,Helvetica,Univers,Zurich BT";

  #$dbh = &miscutils::dbhconnect("qbooks");

  if ($source ne "private") {
    &auth(%data);
  }
  %qbooks::data = %data;

  #if (($ENV{'HTTP_COOKIE'} ne "")){
  #  (@cookies) = split(/\;/, $ENV{'HTTP_COOKIE'});
  #  foreach my $var (@cookies) {
  #    $var =~ /(.*?)=(.*)/;
  #    ($name,$value) = ($1,$2);
  #    $name =~ s/ //g;
  #    $cookie{"$name"} = $value;
  #  }
  #}
  #($cookie{'pnpqbend'},$cookie{'pnpqbcshacct'},$cookie{'pnpqbshpacct'},$cookie{'pnpqbtaxacct'},$cookie{'pnpqborderid'},$cookie{'pnpqbcshno'},$cookie{'pnpqbinvno'},$cookie{'pnpqbtaxitem'}) = split(/\|/, $cookie{'pnpqbdata'});

  return [], $type;
}

sub report_head {
  print "Content-Type: text/html\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Edit Items</title>\n";
  print "<link href=\"/css/style_qbooks.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  print "<script type=\"text/javascript\">\n";
  print "//<!-- Start Script\n";

  print "function closeresults() {\n";
  print "  resultsWindow = window.close('results');\n";
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
  print "<body bgcolor=#ffffff>\n";

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
  print "    <td colspan=3 align=left><img src=\"/css/header_bottom_bar_gfx.gif\" width=760 height=14></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=3 valign=top align=left>\n";
  print "  <tr>\n";
  print "    <td colspan=2><h1><a href=\"index.cgi\">QuickBooks&#153; Module Administration Area - $merch_company</h1>\n";

  print "<table border=0 cellspacing=1 cellpadding=0 width=760>\n";
  print "<tr><td align=center colspan=3>\n";
}

sub report_tail {
  print "</td></tr>\n";
  print "<tr><td colspan=3 align=center><form action=\"index.cgi\">\n";
  print "<input type=submit value=\"Return To Main Administration Page\">\n";
  print "</form></td></tr>\n";
  print "</table>\n";

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

sub auth {
  my (%data) = @_;
  my $dbh_auth = &miscutils::dbhconnect("pnpmisc");
  my $sth_cust = $dbh_auth->prepare(q{
      SELECT status,reason
      FROM customers
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth_cust->execute("$data{'username'}") or die "Can't execute: $DBI::errstr";
  my ($custstatus,$custreason) = $sth_cust->fetchrow;
  $sth_cust->finish;
  $dbh_auth->disconnect;

  if ($custstatus eq "cancelled") {
    my $message = "Your account is closed. Reason: $custreason<br>\n";
    &response_page($message);
  }
}

sub add_item {
  my $dbh = &miscutils::dbhconnect("qbooks");

  my $sth = $dbh->prepare(q{
      SELECT description,acct,vendor,category
      FROM items
      WHERE username=?
      AND name=? 
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$qbooks::username","$data{'name'}") or die "Can't execute: $DBI::errstr";
  ($data{'desc'},$data{'acct'},$data{'vendor'},$data{'category'}) = $sth->fetchrow;
  $sth->finish;
  $selected{$data{'acct'}} = " selected";

  #print "Content-Type: text/html\n\n";

  &report_head();

  print "<form method=post action=\"qbooks_admin.cgi\">\n";
  print "<table>\n";
  print "<tr><td align=right>Item Name:</td><td align=left>$data{'name'}</td></tr>\n";
  print "<tr><td align=right>Account:</td><td align=left><select name=\"acct\">\n";
  print "<option value=\"\"> - No Account - </option>\n";
  my $sth_acct = $dbh->prepare(q{
      SELECT name,acctnum,description
      FROM accounts
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth_acct->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
  while (my ($name,$acctnum,$desc) = $sth_acct->fetchrow) {
    print "<option value=\"$name\"$selected{$name}>$name - $desc</option>\n";
  }
  $sth_acct->finish; 

  $dbh->disconnect;

  print "</select></td></tr>\n";
  print "<tr><td align=right>Category:</td><td align=left><select name=\"category\">\n";
  print "<option value=\"\"></option>\n";
  print "</select></td></tr>\n";
  print "<tr><td align=center><input type=hidden name=\"name\" value=\"$data{'name'}\">";
  print "<input type=hidden name=\"function\" value=\"update_item\">";
  print "<input type=submit value=\"Send Info\"> <input type=reset value=\"Reset Form\">\n";
  print "</td></tr></table>\n";
  print "</form><p>\n";

  &report_tail();
}

sub add_account {
  my $dbh = &miscutils::dbhconnect("qbooks");

  my $sth = $dbh->prepare(q{
      SELECT description,acct,vendor,category
      FROM items
      WHERE username=?
      AND name=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$qbooks::username","$data{'name'}") or die "Can't execute: $DBI::errstr";
  ($data{'desc'},$data{'acct'},$data{'vendor'},$data{'category'}) = $sth->fetchrow;
  $sth->finish;
  $selected{$data{'acct'}} = " selected";

  &report_head();

  print "<form method=post action=\"qbooks_admin.cgi\">\n";
  print "<table>\n";
  print "<tr><td align=right>Item Name:</td><td align=left>$data{'name'}</td></tr>\n";
  print "<tr><td align=right>Account:</td><td align=left><select name=\"acct\">\n";
  print "<option value=\"\"> - No Account - </option>\n";
  my $sth_acct = $dbh->prepare(q{
      SELECT name,acctnum,description
      FROM accounts
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth_acct->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
  while (my ($name,$acctnum,$desc) = $sth_acct->fetchrow) {
    print "<option value=\"$name\"$selected{$name}>$name - $desc</option>\n";
  }
  $sth_acct->finish;

  $dbh->disconnect;

  print "</select></td></tr>\n";
  print "<tr><td align=right>Category:</td><td align=left><select name=\"category\">\n";
  print "<option value=\"\"></option>\n";
  print "</select></td></tr>\n";
  print "<tr><td align=center><input type=hidden name=\"name\" value=\"$data{'name'}\">";
  print "<input type=hidden name=\"function\" value=\"update_item\">";
  print "<input type=submit value=\"Send Info\"> <input type=reset value=\"Reset Form\">\n";
  print "</td></tr></table>\n";
  print "</form><p>\n";

  &report_tail();
}

sub add_group {
  my $dbh = &miscutils::dbhconnect("qbooks");

  #my $sth = $dbh->prepare(q{
  #    SELECT name,qty
  #    FROM qbgroups
  #    WHERE username=?
  #    AND sku=? 
  #  }) or die "Can't do: $DBI::errstr";
  #$sth->execute("$qbooks::username","$data{'sku'}") or die "Can't execute: $DBI::errstr";
  #($data{'name'},$data{'qty'}) = $sth->fetchrow;
  #$sth->finish;

  if ($data{'qty'} eq "") {
    $data{'qty'} = 1;
  }

  my $sth_item = $dbh->prepare(q{
      SELECT name,description,cost,acct,vendor,category,taxable
      FROM items
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth_item->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
  while (my ($name,$desc,$cost,$acct,$vendor,$category,$taxable) = $sth_item->fetchrow) {
    push(@name,$name);
    push(@desc,$desc);
    push(@acct,$acct);
    push(@vendor,$vendor);
    push(@cost,$cost);
    push(@category,$category);
    push(@taxable,$taxable);
  }
  $sth_item->finish;
  $selected{$data{'name'}} = " selected";

  $dbh->disconnect;

  #print "<p>NAME:$data{'name'}<p>\n";

  &report_head();

  print "<form method=post action=\"qbooks_admin.cgi\">\n";
  print "<div align=center>\n";
  print "<table border=1>\n";
  print "<tr><td align=right>Sales SKU:</td><td align=left>$data{'sku'}</td></tr>\n";
  print "<tr><td align=right>QBooks Item:</td><td align=left><input type=hidden name=\"orgname\" value=\"$data{'name'}\"> <select name=\"name\">\n";
  print "<option value=\"\">Please Choose Item</option>\n";
  foreach my $var (@name) {
    print "<option value=\"$var\"$selected{$var}>$var</option>\n";
  }
  print "</select></td></tr>\n";
  print "<tr><td align=right>Quantity:</td><td align=left><input type=text name=\"qty\" size=3 maxlength=9 value=\"$data{'qty'}\"></td></tr>\n";
  print "<tr><td colspan=2>\n";
  print "<input type=hidden name=\"sku\" value=\"$data{'sku'}\">";
  print "<input type=hidden name=\"function\" value=\"update_group\">";
  print "<input type=submit value=\"Add/Edit Item\">\n";
  print "</td></tr></table>\n";
  print "</form><p></div>\n";

  &report_tail();
}

sub view_item {
#  my (%data) = @_;

  &report_head();

  print "<table border=1>\n";
  my $dbh = &miscutils::dbhconnect("qbooks");

  my $sth = $dbh->prepare(q{
      SELECT description,acct,vendor,category,cost
      FROM items
      WHERE username=?
      AND name=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$qbooks::username","$qbooks::data{'name'}") or die "Can't execute: $DBI::errstr";
  ($data{'desc'},$data{'acct'},$data{'vendor'},$data{'category'},$data{'cost'}) = $sth->fetchrow;
  $sth->finish;

  $dbh->disconnect;

  #print "NAME:$qbooks::data{'name'},DESC:$data{'desc'},ACCT:$data{'acct'},VEND:$data{'vendor'},CAT:$data{'category'},COST:$data{'cost'}\n";

  &write_item_entry(%data);

  print "</table><p>\n";

  &report_tail();
}

sub view_account {
  &report_head();

  print "<table border=1>\n";
  my $dbh = &miscutils::dbhconnect("qbooks");
  my $sth_acct = $dbh->prepare(q{
      SELECT name,type,description,acctnum,banknm,extra
      FROM accounts
      WHERE username=?
      AND name=? 
    }) or die "Can't do: $DBI::errstr";
  $sth_acct->execute("$qbooks::username","$qbooks::data{'name'}") or die "Can't execute: $DBI::errstr";
  ($data{'name'},$data{'type'},$data{'desc'},$data{'acctnum'},$data{'banknum'},$data{'extra'}) = $sth_acct->fetchrow;
  $sth_acct->finish;
  $dbh->disconnect;

  &write_account_entry(%data);

  print "</table><p>\n";

  &report_tail();
}

sub view_group {
  my (%data)= (%qbooks::data);

  &report_head();

  print "<table border=1>\n";
  my $dbh = &miscutils::dbhconnect("qbooks");
  my $sth_grp = $dbh->prepare(q{
      SELECT name,qty
      FROM qbgroups
      WHERE username=?
      AND sku=?
    }) or die "Can't do: $DBI::errstr";
  $sth_grp->execute("$qbooks::username","$qbooks::data{'sku'}") or die "Can't execute: $DBI::errstr";
  $sth_grp->bind_columns(undef,\($data{'name'},$data{'qty'}));
  while ($sth_grp->fetch) {
    &write_group_entry(%data);
  }
  $sth_grp->finish;
  print "<tr><td colspan=1><form method=post action=\"qbooks_admin.cgi\">\n";
  print "<font size=-1>QB Item:</font></td><td><select name=\"name\">\n";
  my $sth = $dbh->prepare(q{
      SELECT name,description,acct,vendor,category
      FROM items
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($data{'name'},$data{'desc'},$data{'acct'},$data{'vendor'},$data{'category'}));
  while ($sth->fetch) {
    print "<option value=\"$data{'name'}\">$data{'name'}</option>\n";
  }
  $sth->finish;
  $dbh->disconnect;
  print "</select></td><td><font size=-1>QTY:</font></td><td><input type=text name=\"qty\" value=\"1\"></td></tr>\n";
  print "<tr><td colspan=4 align=center><input type=hidden name=\"function\" value=\"update_group\"><INPUT TYPE=submit VALUE=\"Add Additional Item\">\n";
  print "<input type=hidden name=\"sku\" value=\"$data{'sku'}\"></form></td></tr>\n";
  print "</table><p>\n";

  &report_tail();
}

sub write_item_entry {
  my (%data) = @_;
  print "<tr>\n";
  print "<td colspan=1><form method=post action=\"qbooks_admin.cgi\" target=\"NewWindow\">\n";
  print "<font size=-1><b>Item:</b></font> $data{'name'}<input type=hidden name=\"name\" value=\"$data{'name'}\"></td>\n";
  print "<td><font size=-1><b>Account:</b></font> $data{'acct'}</td>\n";
  print "<td><font size=-1><b>Vendor:1</b></font> $data{'vendor'}</td></tr>\n";
  print "<tr colspan=2><td><font size=-1><b>Description:</b></font> $data{'desc'}</td><td><font size=-1><b>Category:</b></font> $data{'category'}</td><td><font size=-1><b>Cost</b> $data{'cost'}</font></td></tr>\n";
  print "<tr><td><!--<font size=-1><input type=radio name=\"function\" value=\"edit_item\" checked> <b>Edit Account Info</b></font><br>-->\n";
  print " <font size=-1><input type=checkbox name=\"function\" value=\"delete_item\"> <b>Delete Item</b></font></td>\n";
  print "<td align=center rowspan=2 colspan=2><INPUT TYPE=submit VALUE=\"Submit Request\"></form></td></tr>\n";
  print "<tr><td colspan=3 class=\"divider\"><hr width=75% height=3></td>\n";
}

sub write_account_entry {
  my (%data) = @_;
  print "<tr>\n";
  print "<td colspan=2><form method=post action=\"qbooks_admin.cgi\" target=\"NewWindow\">\n";
  print "<font size=-1><b>Account:</b></font> $data{'name'}<input type=hidden name=\"name\" value=\"$data{'name'}\"></td>\n";
  print "<td><font size=-1><b>Type:</b></font> $data{'type'}</td></tr>\n";

  print "<tr><td colspan=3><font size=-1><b>Description:</b></font> $data{'desc'}</td></tr>\n";
  print "<tr><td><font size=-1><b>Account Num:</b></font> $data{'acctnum'}</td><td><font size=-1><b>Bank Num:</b></font> $data{'banknum'}</td>\n";
  print "<td><font size=-1><b>Extra:</b></font> $data{'extra'}</td></tr>\n";
  print "<tr><td><font size=-1><!--<input type=radio name=\"function\" value=\"edit_account\" checked> <b>Edit Account Info</b></font><br>-->\n";
  print " <font size=-1><input type=checkbox name=\"function\" value=\"delete_account\"> <b>Delete Account</b></font></td>\n";
  print "<td align=center rowspan=2 colspan=2><INPUT TYPE=submit VALUE=\"Submit Request\"></form></td></tr>\n";
  print "<tr><td colspan=3 class=\"divider\"><hr width=75% height=3></td>\n";
}

sub write_group_entry {
  my (%data) = @_;
  #my (%data) = (%qbooks::data);
 # foreach my $key (sort keys %data) {
 # print "<tr><td>$key = $data{$key}</td></tr>\n";
 # }
  print "\n";
  print "<tr><td colspan=1><form method=post action=\"qbooks_admin.cgi\">\n";
  print "<font size=-1><b>Sales SKU:</b></font> $data{'sku'}<input type=hidden name=\"sku\" value=\"$data{'sku'}\"></td>\n";
  print "<td colspan=2><font size=-1><b>QB Item:</b></font> $data{'name'}<input type=hidden name=\"name\" value=\"$data{'name'}\"></td>\n";
  print "<td><font size=-1><b>Quantity:</b></font> $data{'qty'}<input name=\"qty\" type=hidden value=\"$data{'qty'}\"></td></tr>\n";
  print "<tr><td colspan=2><input name=\"orgname\" type=hidden value=\"$data{'name'}\"><font size=-1><input type=radio name=\"function\" value=\"edit_group\" checked> <b>Edit Account Info</b></font><br>\n"; 
  print " <font size=-1><input type=radio name=\"function\" value=\"delete_group\"> <b>Delete Account</b></font></td>\n";
  print "<td align=center rowspan=1 colspan=2><INPUT TYPE=\"submit\" VALUE=\"Submit Request\"></form></td></tr>\n";
  print "<tr><td colspan=\"4\" class=\"divider\"><hr width=75% height=3></td>\n";
}


sub response_page {
  my ($message) = @_;

  &report_head();
  print "<div align=center><p>\n";
  print "<font size=+1>$message</font><p>\n";
  print "<p>\n";
  print "<form><input type=button value=\"Close\" onClick=\"closeresults();\"></form>\n";
  print "</div>\n";
  &report_tail();
}

sub remove_item {
  my $dbh = &miscutils::dbhconnect("qbooks");
  my $sth = $dbh->prepare(q{
      DELETE FROM items
      WHERE username=?
      AND name=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$qbooks::username","$qbooks::data{'name'}") or die "Can't execute: $DBI::errstr";
  $sth->finish;
  $dbh->disconnect;
  &response_page("ITEM $data{'name'} has been removed from the database.");
}

sub remove_all_items {
  my $dbh = &miscutils::dbhconnect("qbooks");
  my $sth = $dbh->prepare(q{
      DELETE FROM items
      WHERE username=? 
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
  $sth->finish;
  $dbh->disconnect;
  print "Location: /admin/qbooks/index.cgi\n\n";
  exit;
  #&response_page("All items have been removed from the database.");
}


sub remove_account {
  my $dbh = &miscutils::dbhconnect("qbooks");
  my $sth = $dbh->prepare(q{
      DELETE FROM accounts
      WHERE username=?
      AND name=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$qbooks::username","$qbooks::data{'name'}") or die "Can't execute: $DBI::errstr";
  $sth->finish;
  $dbh->disconnect;
  &response_page("ACCOUNT $data{'name'} has been removed from the database.");
}

sub remove_all_accounts {
  my $dbh = &miscutils::dbhconnect("qbooks");
  my $sth = $dbh->prepare(q{
      DELETE FROM accounts
      WHERE username=? 
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
  $sth->finish;
  $dbh->disconnect;
  print "Location: /admin/qbooks/index.cgi\n\n";
  exit;
  #&response_page("All accounts have been removed from the database.");
}

sub remove_group {
  my (%data) = (%qbooks::data);

   #print "START:  ";
   #foreach my $key (sort keys %qbooks::data) {
   #  print "$key:$qbooks::data{$key}, ";
   #}

  $deletestring = "DELETE FROM qbgroups WHERE username=? AND sku=? AND qty=?";
  @array = ("$qbooks::username","$data{'sku'}","$data{'qty'}");
  if ($data{'name'} ne "") {
    $deletestring .= " AND name=?";
    push(@array,"$data{'name'}");
  }
  #print "DSTRING:$deletestring\n";
  #exit;

  my $dbh = &miscutils::dbhconnect("qbooks");
  my $sth = $dbh->prepare(qq{$deletestring}) or die "Can't prepare: $DBI::errstr";
  $sth->execute(@array) or die "Can't execute: $DBI::errstr";
  $sth->finish;
  $dbh->disconnect;

  &view_group();
}

sub remove_all_groups {
  my $dbh = &miscutils::dbhconnect("qbooks");
  my $sth = $dbh->prepare(q{
      DELETE FROM qbgroups 
      WHERE username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
  $sth->finish;
  $dbh->disconnect;

  print "Location: /admin/qbooks/index.cgi\n\n";
  exit;
  #&response_page("All groups have been removed from the database.");
}


sub remove_vendor {
  my $dbh = &miscutils::dbhconnect("qbooks");
  my $sth = $dbh->prepare(q{
      DELETE FROM vendors
      WHERE username=?
      AND name=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$qbooks::username","$data{'name'}") or die "Can't execute: $DBI::errstr";
  $sth->finish;
  $dbh->disconnect;

  &response_page("VENDOR $data{'name'} has been removed from the database.");
}

sub remove_all_vendors {
  my $dbh = &miscutils::dbhconnect("qbooks");
  my $sth = $dbh->prepare(q{
      DELETE FROM vendors
      WHERE username=? 
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
  $sth->finish;
  $dbh->disconnect;

  print "Location: /admin/qbooks/index.cgi\n\n";
  exit;
  #&response_page("All vendors have been removed from the database.");
}

sub import_data {
  #if ($ENV{'REMOTE_ADDR'} ne "96.56.10.12") {
  #  my $message = "Import Function Currently Unavailable";
  #  &response_page($message);
  #  exit;
  #}

  my $insert_acct_flg = 0;
  my @acct_array = ();
  my @item_array = ();
  my @vendor_array = ();

  &report_head();
  print "<div align=center><p>\n";

  #my $filename = $data{'upload-file'};
  my $filename = &CGI::escapeHTML($query->param('flname'));
  $filename =~ s/[^a-zA-Z0-9\_\-\.\ \:\\]//g;
  #print "FN:<br>\n$filename\n";
  my (@fields);
  my $remoteuser = $ENV{'REMOTE_USER'};
  $remoteuser =~ s/[^0-9a-zA-Z]//g;

  #&sysutils::filelog("write",">/home/pay1/webtxt/admin/qbooks/debug/$remoteuser\.txt");
  #open (DEBUG,'>',"/home/pay1/webtxt/admin/qbooks/debug/$remoteuser\.txt") or die "Cannot open $remoteuser\.txt for writing. $!";
  while(<$filename>) {
    my $theline = $_;
    #print DEBUG "$theline"; # disabled for PCI reasons.
    $kkkk++; 
    if (substr($kkkk,-2) eq "00") {
      print "... ";
    }
    chop $theline;
    $theline =~ s/\"//g;
    my (@data) = split(/\t/, $theline);
    if ($data[0] =~ /^ENDGRP/i) {
      next;
    }
    if (substr($data[0],0,1) eq "\!") {
      $group_flag = 0;
      my $aaaa = $data[0];
      #print "MARK:$aaaa:<br>\n";
      if ($data[0] =~ /^\!ENDGRP/i) {
        $group_flag = 1;
        #print "FLAG:$group_flag<br>\n";
        next;
      }
      $parseflag = 1;
      (@fields) = (@data);
      $fields[0] = substr($data[0],1);
      #print "FF0:$fields[0]<br>\n"; 
      next;
    }
    #print "F0:$fields[0]:$data[0]:$parseflag<br>\n";
    if ($parseflag == 1) {
      my %data = ();
      my $i = 0;
      foreach my $var (@fields) {
        $var =~ tr/A-Z/a-z/;
        #print "$var:$data[$i], ";
        $data{"$var"} = $data[$i];
        $i++;
      }
      #foreach my $key (sort keys %data) {
      #  print "&bull; $key = \'$data{$key}\'<br>\n";
      #}
      #print "INV:$data{'invitem'}<br>\n";
      if ($group_flag == 1) {
        #print "AAA:$data{'invitemtype'}<br>\n";
        if ($data{'invitemtype'} =~ /^grp$/i) {
          $master_sku = $data{'name'}; 
          &insert_item(%data);
          next; 
        }
        else {
          $qbooks::data{'sku'} = $master_sku;
          $qbooks::data{'orgname'} = $data{'name'};
          if ($data{'qnty'} < 1) {
            $data{'qnty'} = 1;
          }
          $qbooks::data{'qty'} = $data{'qnty'};
          #print "START:  ";
          #foreach my $key (sort keys %qbooks::data) {
          #  print "$key:$qbooks::data{$key}, ";
          #}
          #print " MASTERSKU:$master_sku<br>\n";
          &insert_group(%qbooks::data);
        }
      }
      elsif ($fields[0] eq "invitem") {
        &insert_item(%data);
      }
      elsif ($fields[0] eq "accnt") {
        $insert_acct_flg = 1;
        $acct_array[++$#acct_array] = {%data};
        #if ($ENV{'REMOTE_ADDR'} !~ /^(96\.56\.10\.1)/) {
        #  &insert_coa(%data);
        #}
      }
      elsif ($fields[0] eq "vend") {
        &insert_vendor(%data);
      }  
    }
  }
  #close(DEBUG);

  #print "IAF: $insert_acct_flg<br>\n";
  if ($insert_acct_flg == 1) {
    my $dbh = &miscutils::dbhconnect("qbooks");
    my $sth = $dbh->prepare(q{
        DELETE FROM accounts
        WHERE username=? 
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
    $sth->finish;

    foreach my $href (@acct_array) {
      my @array = %$href;
      &import_coa(@array);
    }
    $dbh->disconnect;
  }

  my ($message);
  if ($parseflag == 1) {
    $message = "File Has Been Uploaded and Imported into Database";
  }
  else {
    $message = "Sorry Improper File Format";
  }
  print "<p>\n";
  print "<font size=+1>$message</font><p>\n";
  print "<p>\n";
  print "<form><input type=button value=\"Close\" onClick=\"closeresults();\"></form>\n";
  print "</div>\n";

  &report_tail();
  exit;
}


sub insert_group {
  #my (%data) = @_;
  my (%data) = (%qbooks::data);
  #print "Inserting Group:$qbooks::username, SKU:$data{'sku'}, NAME:$data{'name'}, ORGNAME:$data{'orgname'}, QTY:$data{'qty'}<br>\n";
  my ($test);
  if (($data{'sku'} ne "") && ($data{'orgname'} ne "")) {   ### Update Function
    #print "Inserting Group:$qbooks::username, $data{'sku'}, $data{'name'}, $data{'orgname'}, $data{'qty'}<br>\n";
    my $dbh = &miscutils::dbhconnect("qbooks");
    my $sth = $dbh->prepare(q{
        SELECT sku
        FROM qbgroups
        WHERE username=?
        AND sku=?
        AND name=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$qbooks::username", "$data{'sku'}","$data{'orgname'}") or die "Can't execute: $DBI::errstr";
    my $test = $sth->fetchrow;
    $sth->finish;

    if ($test ne "") {
      $sth = $dbh->prepare(q{
          UPDATE qbgroups
          SET qty=?, name=? 
          WHERE username=?
          AND name=?
          AND sku=?
      }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$data{'qty'}","$data{'name'}","$qbooks::username","$data{'orgname'}","$data{'sku'}") or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
    else {
      $sth = $dbh->prepare(q{
          INSERT INTO qbgroups
          (username,sku,name,qty)
          VALUES (?,?,?,?)
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$qbooks::username","$data{'sku'}","$data{'orgname'}","$data{'qty'}") or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
    $dbh->disconnect;
  }
  elsif (($data{'sku'} ne "") && ($data{'name'} ne "")) {   ### Add Item to SKU
    #print "Inserting Group:$qbooks::username, $data{'sku'}, $data{'name'}, $data{'orgname'}, $data{'qty'}<br>\n";
    my $dbh = &miscutils::dbhconnect("qbooks");
    my $sth = $dbh->prepare(q{
        SELECT sku
        FROM qbgroups
        WHERE username=?
        AND sku=?
        AND name=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$qbooks::username","$data{'sku'}","$data{'name'}") or die "Can't execute: $DBI::errstr";
    my $test = $sth->fetchrow;
    $sth->finish;
 
    if ($test ne "") {
      $sth = $dbh->prepare(q{
          UPDATE qbgroups
          SET qty=?
          WHERE username=?
          AND name=?
          AND sku=?
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$data{'qty'}","$qbooks::username","$data{'name'}","$data{'sku'}") or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
    else {
      $sth = $dbh->prepare(q{
          INSERT INTO qbgroups
          (username,sku,name,qty)
          VALUES (?,?,?,?)
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$qbooks::username","$data{'sku'}","$data{'name'}","$data{'qty'}") or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
    $dbh->disconnect;
  }
}

sub insert_item {
  my (%data) = @_;

  #print "$data{'name'}<br>\n";

  #foreach my $key (sort keys %data) {
  #  print "$key:$data{$key}, ";
  #}
  #print "<p>\n";
  #exit;

  if ($data{'taxvend'} ne "") {
    $data{'prefvend'} = $data{'taxvend'};
  }
  my ($test);
  if ($data{'invitem'} ne "") {
    my $dbh = &miscutils::dbhconnect("qbooks");
    my $sth = $dbh->prepare(q{
        SELECT name
        FROM items
        WHERE username=?
        AND name=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute ("$qbooks::username","$data{'name'}") or die "Can't execute: $DBI::errstr";
    my $test = $sth->fetchrow;
    $sth->finish;

    if ($test ne "") {
      $sth = $dbh->prepare(q{
          UPDATE items
          SET description=?,cost=?,acct=?,vendor=?,category=?,taxable=?
          WHERE username=?
          AND name=?
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$data{'desc'}","$data{'price'}","$data{'accnt'}","$data{'prefvend'}","$data{'category'}","$data{'taxable'}","$qbooks::username","$data{'name'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%data); 
      $sth->finish;
    }
    else {
      $sth = $dbh->prepare(q{
          INSERT INTO items
          (username,name,description,cost,acct,vendor,category,taxable)
          VALUES (?,?,?,?,?,?,?,?)
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$qbooks::username","$data{'name'}","$data{'desc'}","$data{'price'}","$data{'accnt'}","$data{'prefvend'}","$data{'category'}","$data{'taxable'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%data);
      $sth->finish;
    }
    $dbh->disconnect;
  }
}

sub insert_coa {
  my (%data) = @_;
  my ($test);
  if (($data{'accnt'} ne "") && (($data{'accnttype'} eq "INC") || 
      ($data{'accnttype'} eq "EXP") || ($data{'accnttype'} eq "OCASSET") ||  
      ($data{'accnttype'} eq "OCLIAB") || ($data{'accnttype'} eq "BANK") ||
      ($data{'accnttype'} eq "AR") || ($data{'accnttype'} eq "AP")
      ))  {
    my $dbh = &miscutils::dbhconnect("qbooks");
    my $sth = $dbh->prepare(q{
        SELECT name
        FROM accounts
        WHERE username=?
        AND name=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$qbooks::username","$data{'name'}") or die "Can't execute: $DBI::errstr";
    my $test = $sth->fetchrow;
    $sth->finish;

    if ($test ne "") {
      $sth = $dbh->prepare(q{
          UPDATE accounts
          SET type=?,description=?,acctnum=?,banknm=?,extra=?
          WHERE username=?
          AND name=?
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$data{'accnttype'}","$data{'desc'}","$data{'accnum'}","$data{'banknum'}","$data{'extra'}","$qbooks::username","$data{'name'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%data);
      $sth->finish;
    }
    else {
      $sth = $dbh->prepare(q{
          INSERT INTO accounts
          (username,name,type,description,acctnum,banknm,extra)
          VALUES (?,?,?,?,?,?,?)
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$qbooks::username","$data{'name'}","$data{'accnttype'}","$data{'desc'}","$data{'accnum'}","$data{'banknum'}","$data{'extra'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%data);
      $sth->finish;
    }
    $dbh->disconnect;
  }
}

sub insert_vendor {
  my (%data) = @_;
  my ($test);
  if ($data{'vend'} ne "") {
    $data{'addr1'} = substr($data{'addr1'},0,24);
    $data{'addr2'} = substr($data{'addr2'},0,24);
    $data{'addr3'} = substr($data{'addr3'},0,24);
    $data{'email'}  = substr($data{'email'},0,49);
    $data{'taxid'}  = substr($data{'taxid'},0,14);

    my $dbh = &miscutils::dbhconnect("qbooks");
    my $sth = $dbh->prepare(q{
        SELECT name
        FROM vendors
        WHERE username=?
        AND name=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$qbooks::username","$data{'name'}") or die "Can't execute: $DBI::errstr";
    my $test = $sth->fetchrow;
    $sth->finish;

    if ($test ne "") {
      $sth = $dbh->prepare(q{
          UPDATE vendors
          SET company=?,addr1=?,addr2=?,city=?,state=?,zip=?,email=?,taxid=?
          WHERE username=?
          AND name=?
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$data{'addr1'}","$data{'addr2'}","$data{'addr3'}","$data{'city'}","$data{'state'}","$data{'zip'}","$data{'email'}","$data{'taxid'}","$qbooks::username","$data{'NAME'}") or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
    else {
      $sth = $dbh->prepare(q{
          INSERT INTO vendors
          (username,name,company,addr1,addr2,city,state,zip,email,taxid)
          VALUES (?,?,?,?,?,?,?,?,?,?)
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$qbooks::username","$data{'name'}","$data{'addr1'}","$data{'addr2'}","$data{'addr3'}","$data{'city'}","$data{'state'}","$data{'zip'}","$data{'email'}","$data{'taxid'}") or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
    $dbh->disconnect;
  }
}


sub import_coa {
  my (%data) = @_;

  #print "AAA: ";
  #foreach my $key (sort keys %data) {
  #  print "<br>K:$key:$data{$key}, ";
  #}
  #print "<br>\n";

  if (($data{'accnt'} ne "") && ($data{'accnttype'} =~ /^(INC|EXP|OCASSET|OCLIAB|BANK|AR|AP)$/)) { 
    my $dbh = &miscutils::dbhconnect("qbooks");
    my $sth = $dbh->prepare(q{
        INSERT INTO accounts
        (username,name,type,description,acctnum,banknm,extra)
        VALUES (?,?,?,?,?,?,?)
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute("$qbooks::username","$data{'name'}","$data{'accnttype'}","$data{'desc'}","$data{'accnum'}","$data{'banknum'}","$data{'extra'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%data);
    $sth->finish;
    $dbh->disconnect;
  }

  return;
}

sub qbooks_admin {
  #if ($ENV{'REMOTE_ADDR'} =~ /^(96\.56\.10\.1)/) {
  #  print "Content-Type: text/html\n\n<br>";
  #}

  if (($data{'report'} eq "sales") || ($data{'report'} eq "both")) {
    &qbooks_sales();  
  }
  if (($data{'report'} eq "bank") || ($data{'report'} eq "both")) {
    &qbooks_bank();
  }
}

sub report {
  my $dbh = &miscutils::dbhconnect("qbooks");

  my $sth = $dbh->prepare(q{
      SELECT acctbank,acctrec,acctundep,acctsalestax,acctcharges,axasset,dsasset,mvasset,otasset
      FROM rules
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
  my ($acctbank,$acctrec,$acctundep,$acctsalestax,$acctcharges,$axasset,$dsasset,$mvasset,$otasset) = $sth->fetchrow;
  $sth->finish;

  $splacct{'undeposited_funds'} = $acct{$acctundep};
  $splacct{'bank_acct'} = $acct{$acctbank};
  $splacct{'AcctRec'} = $acct{$acctrec};
  $splacct{'expense_acct'} = $acct{$acctcharges};
  $splacct{'SalesTax'} = $acct{$acctsalestax};
  $splacct{'amex_asset'} = $acct{$axasset};
  $splacct{'disc_asset'} = $acct{$dsasset};
  $splacct{'visa_asset'} = $acct{$mvasset};
  $splacct{'other_asset'} = $acct{$otasset};

  if ($splacct{'AcctRec'} eq "") {
    $splacct{'AcctRec'} = "Accounts Receivable";
  }
  if ($splacct{'undeposited_funds'} eq "") {
    $splacct{'undeposited_funds'} = "Undeposited Funds";
  }
  if ($splacct{'bank_acct'} eq "") {
    $splacct{'bank_acct'} = "Checking";
  }
  if ($splacct{'SalesTax'} eq "") {
    $splacct{'SalesTax'} = "$data{'salestaxacct'}";
  }
  if ($splacct{'Shipping'} eq "") {
    $splacct{'Shipping'} = "$data{'shippingacct'}";
  }

  my $sth_item = $dbh->prepare(q{
      SELECT vendor
      FROM items
      WHERE username=?
      AND name=?
    }) or die "Can't do: $DBI::errstr";
  $sth_item->execute("$qbooks::username","$data{'salestaxitem'}") or die "Can't execute: $DBI::errstr";
  ($tax_vendor) = $sth_item->fetchrow;
  $sth_item->finish;

  $dbh->disconnect;

  &qbooks_admin();

  if ($data{'SaleType'} =~ /INVOICE/i) {
    $invno = $data{'InvNo'}; 
    $cshno = $cookie{'pnpqbcshno'};
  }
  else {
    $cshno = $data{'InvNo'}; 
    $invno = $cookie{'pnpqbinvno'};
  }

  #my $pnpqbdata = "$data{'srchenddate'}\|$data{'depositacct'}\|$data{'shippingacct'}\|$data{'salestaxacct'}\|$db{'orderid'}\|$cshno\|$invno\|$data{'salestaxitem'}\|$data{'pnpqbadjustmentitem'}\|$data{'tobeprinted'}\|$data{'exportcust'}\|$data{'showall'}\|$data{'format'}\|$data{'usecost'}\|$cookie{'add_recurring'}\|$cookie{'exclude_vt'}";

  if ($data{'format'} eq "download") {
    print "Set-Cookie: pnpqbdata=$data{'srchenddate'}\|$data{'depositacct'}\|$data{'shippingacct'}\|$data{'salestaxacct'}\|$db{'orderid'}\|$cshno\|$invno\|$data{'salestaxitem'}\|$data{'pnpqbadjustmentitem'}\|$data{'tobeprinted'}\|$data{'exportcust'}\|$data{'showall'}\|$data{'format'}\|$data{'usecost'}\|$data{'add_recurring'}\|$data{'exclude_vt'}; path=/; expires=Wednesday, 01-Jan-25 23:00:00 GMT; host=.plugnpay.com; secure; \n";
  }

  if ($data{'format'} eq "display") {
    print "Content-Type: text/html\n\n";
    print "<!DOCTYPE html>\n";
    print "<html lang=\"en-US\">\n";
    print "<head>\n";
    print "<meta charset=\"utf-8\">\n";
    print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
    print "</head>\n"; 
    print "<body bgcolor=#ffffff>\n";
    print "<pre>\n";
  }
  else {
    print "Content-Type: application/iif\n";
    print "Content-Disposition: inline; filename=qbooks.iif\n\n";
  }

  # Print Report Output
  if ($data{'exportcust'} eq "yes") {
    foreach my $var (@custoutput) {
      print "$var\n";
    }
  }
  foreach my $var (@output) {
    #$var =~ s/[^a-zA-Z0-9_\.\\\/ \@:\-\#\,\?\t\!\"]/X/g;
    $var =~ s/CRL36/CRL 36/g;
    $var =~ s/crl36/crl 36/g;
    print "$var\n";
  }

  if ($data{'format'} eq "display") {
    print "\n</pre>\n";
    print "</table>\n";
    print "</div>\n";
    print "</body>\n";
    print "</html>\n";
  }
  else {
    print "\n";
  }
}

sub qbooks_sales {

  #print "Content-Type: text/html\n\n";
  my @executeArray = ();
  my $srchstr = "SELECT t.trans_time,o.orderid,o.card_name,o.card_addr,";
  $srchstr .= "o.card_city,o.card_state,o.card_zip,o.card_country,";
  $srchstr .= "o.amount,o.tax,o.shipping,o.trans_date,o.trans_time,";
  $srchstr .= "o.result,o.acct_code,o.acct_code4,";
  $srchstr .= "o.morderid,o.shipname,o.shipaddr1,o.shipaddr2,";
  $srchstr .= "o.shipcity,o.shipstate,o.shipzip,o.shipcountry,o.phone,";
  $srchstr .= "o.fax,o.email,o.easycart,";
  $srchstr .= "o.ipaddress,o.card_number,";
  $srchstr .= "o.card_exp,o.card_company";
  $srchstr .= " FROM trans_log t FORCE INDEX(tlog_tdateuname_idx), ordersummary o";

  my $starttranstime = &miscutils::strtotime($data{'srchstartdate'});
  my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime($starttranstime - (3600 * 24 * 7));
  $starttransdate = sprintf("%04d%02d%02d",$year+1900,$month+1,$day);
 
  $starttime = $data{'srchstartdate'} . "000000";
  $endtime = $data{'srchenddate'} . "000000";

  $srchstr .= " WHERE t.trans_date>=?";
  push (@executeArray,$starttransdate);
  $srchstr .= " AND t.trans_date<?";
  push(@executeArray,$data{'srchenddate'});

  $srchstr .= " AND t.username=?";
  push(@executeArray,$data{'username'});

  if ($data{'srchstatus'} eq "settled") {
    $srchstr .= " AND t.trans_time BETWEEN ? AND ?";
    push(@executeArray,$starttime,$endtime);

    $srchstr .= " AND t.operation=?";
    $srchstr .= " AND t.finalstatus=?";
    push(@executeArray,'postauth','success');
  }
  else {
    $srchstr .= " AND t.trans_time>=?";
    $srchstr .= " AND t.operation=?";
    $srchstr .= " AND t.finalstatus=?";
    push(@executeArray,$starttime,'auth','success');
  }


  $srchstr .= " AND (t.duplicate IS NULL OR t.duplicate='') ";
  $srchstr .= " AND o.orderid=t.orderid ";
  $srchstr .= " AND o.username=t.username ";
  $srchstr .= " AND o.result=? ";
  $srchstr .= " AND (o.duplicate IS NULL OR o.duplicate='') ";

  push(@executeArray,'success');

  $srchstr .= " ORDER BY t.orderid";

  $db{'splid'} = 1;
  $db{'trnsid'} = 1;

  push(@custoutput,"\!CUST\tNAME\tBADDR1\tBADDR2\tBADDR3\tBADDR4\tBADDR5\tSADDR1\tSADDR2\tSADDR3\tSADDR4\tSADDR5\tPHONE1\tFAXNUM\tEMAIL");

  if ($data{'inc_paymethod'} eq "yes") {
    push(@output,"\!TRNS\tTRNSID\tTRNSTYPE\tDATE\tACCNT\tAMOUNT\tNAME\tDOCNUM\tMEMO\tSADDR1\tSADDR2\tSADDR3\tSADDR4\tSADDR5\tADDR1\tADDR2\tADDR3\tADDR4\tADDR5\tTOPRINT\tPAYMETH");
  }
  else {
    push(@output,"\!TRNS\tTRNSID\tTRNSTYPE\tDATE\tACCNT\tAMOUNT\tNAME\tDOCNUM\tMEMO\tSADDR1\tSADDR2\tSADDR3\tSADDR4\tSADDR5\tADDR1\tADDR2\tADDR3\tADDR4\tADDR5\tTOPRINT");
  }
  push(@output,"\!SPL\tSPLID\tTRNSTYPE\tDATE\tACCNT\tNAME\tAMOUNT\tDOCNUM\tINVITEM\tQNTY\tPRICE\tMEMO\tEXTRA");
  push(@output,"\!ENDTRNS");

  $dbh_pnp = &miscutils::dbhconnect("pnpdata");
  my $sth = $dbh_pnp->prepare(qq{$srchstr}) or die "Can't do: $DBI::errstr";
  $sth->execute(@executeArray) or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($db{'tltrans_time'},$db{'orderid'},$db{'card_name'},$db{'card_addr'},
      $db{'card_city'},$db{'card_state'},$db{'card_zip'},$db{'card_country'},
      $db{'amount'},$db{'tax'},$db{'shipping'},$db{'trans_date'},$db{'trans_time'},
      $db{'result'},$db{'acct_code'},$db{'acct_code4'},
      $db{'morderid'},$db{'shipname'},$db{'shipaddr1'},$db{'shipaddr2'},
      $db{'shipcity'},$db{'shipstate'},$db{'shipzip'},$db{'shipcountry'},$db{'phone'},
      $db{'fax'},$db{'email'},$db{'easycart'},
      $db{'ipaddress'},$db{'card_number'},
      $db{'card_exp'},$db{'card_company'}
    ));

  local $dbh = &miscutils::dbhconnect("qbooks");

  while ($sth->fetch) {
    if (($data{'exclude_vt'} eq "yes") && ($db{'acct_code4'} =~ /Virtual Terminal/i)) {
      next;
    }

    if (($data{'showall'} eq "no") && ($cookie{'pnpqborderid'} > 0)) {
      if ($db{'orderid'} <= $cookie{'pnpqborderid'}) {
        next;
      }
    }

    $cardtype = &miscutils::cardtype($db{'card_number'});
    if (($cardtype =~ /visa/i) || ($cardtype =~ /mstr/i)) {
      $paymethod = "V/MC";
    }
    elsif ($cardtype =~ /dscr/i) {
      $paymethod = "Discover";
    }
    elsif ($cardtype =~ /amex/i) {
      $paymethod = "American Express";
    }
    elsif ($cardtype =~ /checking/i) {
      $paymethod = "ACH";
    }

    if ($db{'card_name'} =~ /   /) {
      $db{'card_name'} =~ s/   / /;
    }
    if ($db{'card_name'} =~ /  /) {
      $db{'card_name'} =~ s/  / /;
    }

    $db{'card_name'} =~ /(.*) (.+)$/;
    if ($data{'nameformat'} eq "lastfirst") {
      $db{'card_name'} = "$2, $1";
    }

    if ($db{'card_number'} =~ /^3/) {
      $ct = "A";
    }
    elsif ($db{'card_number'} =~ /^4/) {
      $ct = "V";
    }
    elsif($db{'card_number'} =~ /^5/) {
      $ct = "M";
    }
    elsif($db{'card_number'} =~ /^6/) {
      $ct = "D";
    }
    if ($data{'srchstatus'} eq "settled") {
      $db{'trans_date'} = substr($db{'tltrans_time'},0,8);
    }
    $orderIDs{$db{'orderid'}} = 1;

    $db{'amount'} =~ s/[^0-9\.]//g;
    $totalamt += $db{'amount'};
    &sales_iif(%db);
  }
  $sth->finish;

  if ($data{'add_recurring'} eq "yes") {

    @executeArray = ();

    my $srchstr = "SELECT t.orderid,t.card_name,t.card_addr,";
    $srchstr .= "t.card_city,t.card_state,t.card_zip,t.card_country,";
    $srchstr .= "t.amount,t.trans_date,t.trans_time,";
    $srchstr .= "t.result,t.acct_code,t.card_number";
    $srchstr .= " FROM trans_log t FORCE INDEX(tlog_tdateuname_idx)";
    $srchstr .= " WHERE t.trans_date>=?";
    $srchstr .= " AND t.trans_date<?";
    $srchstr .= " AND t.username=?";
    $srchstr .= " AND t.trans_time>=?";
    push (@executeArray,$starttransdate, $data{'srchenddate'}, $data{'username'}, $starttime);
 
    if (($data{'showall'} eq "no") && ($cookie{'pnpqborderid'} > 0)) {
      $srchstr .= " AND t.orderid>?";
      push (@executeArray,$cookie{'pnpqborderid'});
    }
 
    if ($data{'srchstatus'} eq "settled") {
      $srchstr .= " AND t.trans_time<? ";
      $srchstr .= " AND t.operation=?";
      $srchstr .= " AND t.finalstatus=?";
      push (@executeArray,$endtime,'postauth','success');
    }
    else {
      $srchstr .= " AND t.operation=?";
      $srchstr .= " AND t.finalstatus=?";
      push (@executeArray,'auth','success');
    }

    $srchstr .= " AND (t.duplicate IS NULL OR t.duplicate='')";
    $srchstr .= " ORDER BY t.orderid";


    %db = ();
    my $sth = $dbh_pnp->prepare(qq{$srchstr}) or die "Can't do: $DBI::errstr";
    $sth->execute(@executeArray) or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($db{'orderid'},$db{'card_name'},$db{'card_addr'},
        $db{'card_city'},$db{'card_state'},$db{'card_zip'},$db{'card_country'},
        $db{'amount'},$db{'trans_date'},$db{'trans_time'},
        $db{'result'},$db{'acct_code'},$db{'card_number'}
      ));
 
    while ($sth->fetch) {
      $cardtype = &miscutils::cardtype($db{'card_number'});
      if (($cardtype =~ /visa/i) || ($cardtype =~ /mstr/i)) {
        $paymethod = "V/MC";
      }
      elsif ($cardtype =~ /dscr/i) {
        $paymethod = "Discover";
      }
      elsif ($cardtype =~ /amex/i) {
        $paymethod = "American Express";
      }
      elsif ($cardtype =~ /checking/i) {
        $paymethod = "ACH";
      }

      if (exists $orderIDs{$db{'orderid'}}) {
        next;
      }
      if ($db{'card_number'} =~ /^3/) {
        $ct = "A";
      }
      elsif ($db{'card_number'} =~ /^4/) {
        $ct = "V";
      }
      elsif($db{'card_number'} =~ /^5/) {
        $ct = "M";
      }
      elsif($db{'card_number'} =~ /^6/) {
        $ct = "D";
      }
      if ($data{'username'} =~ /^mentorfin/) {
        $db{'orderid'} = "$ct$db{'orderid'}";
      }
      #delete $db{'card_number'};

      $db{'amount'} =~ s/[^0-9\.]//g;
      $totalamt += $db{'amount'};
      $db{'recurring'} = "yes";
      &sales_iif(%db);
    }
    $sth->finish;
  }

  #if ($data{'format'} eq "display") {
  #  print "TOTAL SALES:$totalamt<br>\n";
  #}
  $dbh_pnp->disconnect;
  $dbh->disconnect();

}

sub sales_iif {
  #print "AAA\n";
  my (%db) = @_;
  #my $dbh = &miscutils::dbhconnect("qbooks");
  $inv_no++;
  $qb_date = substr($db{'trans_date'},4,2) . "/" . substr($db{'trans_date'},6,2) . "/" . substr($db{'trans_date'},2,2);
  if ($data{'SaleType'} =~ /CASH SALE/i) {
    $transacct = $data{'depositacct'};
  }
  else {
    $transacct = $splacct{'AcctRec'};
  }

  if ($db{'shipaddr2'} ne "") {
    $customerstr = "CUST\t$db{'card_name'}\t$db{'card_name'}\t$db{'card_addr'}\t$db{'card_city'}, $db{'card_state'}  $db{'card_zip'}\t$db{'card_country'}\t\t$db{'shipname'}\t$db{'shipaddr1'}\t$db{'shipaddr2'}\t$db{'shipcity'},$db{'shipstate'}  $db{'shipzip'}\t$db{'shipcountry'}\t$db{'phone'}\t$db{'fax'}\t$db{'email'}";
  }
  else {
    $customerstr = "CUST\t$db{'card_name'}\t$db{'card_name'}\t$db{'card_addr'}\t$db{'card_city'}, $db{'card_state'}  $db{'card_zip'}\t$db{'card_country'}\t\t$db{'shipname'}\t$db{'shipaddr1'}\t$db{'shipcity'},$db{'shipstate'}  $db{'shipzip'}\t$db{'shipcountry'}\t\t$db{'phone'}\t$db{'fax'}\t$db{'email'}";
  }
  #@custoutput = (@custoutput,"$customerstr");
  if($customerlist{$db{'card_name'}} != 1) {
    $custoutput[++$#custoutput] = "$customerstr";
    $customerlist{$db{'card_name'}} = 1;
  }

  if ($data{'username'} =~ /^mentorfin/) {
    #$output = (@output,"TRNS\t$db{'trnsid'}\t$data{'SaleType'}\t$qb_date\t$transacct\t$db{'amount'}\t$db{'card_name'}\t$data{'InvNo'}\t$ct$db{'orderid'}\t$db{'shipname'}\t$db{'shipaddr1'}\t$db{'shipaddr2'}\t$db{'shipcity'},$db{'shipstate'}  $db{'shipzip'}\t$db{'shipcountry'}\t$db{'card_name'}\t$db{'card_addr'}\t$db{'card_city'}, $db{'card_state'}  $db{'card_zip'}\t$db{'card_country'}\t\t$data{'tobeprinted'}");

  $output[++$#output] = "TRNS\t$db{'trnsid'}\t$data{'SaleType'}\t$qb_date\t$transacct\t$db{'amount'}\t$db{'card_name'}\t$data{'InvNo'}\t$ct$db{'orderid'}\t$db{'shipname'}\t$db{'shipaddr1'}\t$db{'shipaddr2'}\t$db{'shipcity'},$db{'shipstate'}  $db{'shipzip'}\t$db{'shipcountry'}\t$db{'card_name'}\t$db{'card_addr'}\t$db{'card_city'},$db{'card_state'}  $db{'card_zip'}\t$db{'card_country'}\t\t$data{'tobeprinted'}";
  }
  else {
    #@output = (@output,"TRNS\t$db{'trnsid'}\t$data{'SaleType'}\t$qb_date\t$transacct\t$db{'amount'}\t$db{'card_name'}\t$data{'InvNo'}\t$db{'orderid'}\t$db{'shipname'}\t$db{'shipaddr1'}\t$db{'shipaddr2'}\t$db{'shipcity'},$db{'shipstate'}  $db{'shipzip'}\t$db{'shipcountry'}\t$db{'card_name'}\t$db{'card_addr'}\t$db{'card_city'}, $db{'card_state'}  $db{'card_zip'}\t$db{'card_country'}\t\t$data{'tobeprinted'}");

    $output[++$#output] = "TRNS\t$db{'trnsid'}\t$data{'SaleType'}\t$qb_date\t$transacct\t$db{'amount'}\t$db{'card_name'}\t$data{'InvNo'}\t$db{'orderid'}\t$db{'shipname'}\t$db{'shipaddr1'}\t$db{'shipaddr2'}\t$db{'shipcity'},$db{'shipstate'}  $db{'shipzip'}\t$db{'shipcountry'}\t$db{'card_name'}\t$db{'card_addr'}\t$db{'card_city'}, $db{'card_state'}  $db{'card_zip'}\t$db{'card_country'}\t\t$data{'tobeprinted'}";

    if ($data{'inc_paymethod'} eq "yes") {
      $output[$#output] .= "\t$paymethod";
    }
  }

  $check_total = $db{'amount'};
  $check_totalx = $db{'amount'};

#print "OID:$db{'orderid'}, UN:$data{'username'}, EC:$db{'easycart'}<p>\n";
  if ($db{'easycart'} == 1) {
    if ($data{'modelnum'} ne ""){
      $sth_details = $dbh_pnp->prepare(q{
          SELECT DISTINCT item,quantity,cost,description,customa,customb,customc,customd,custome
          FROM orderdetails 
          WHERE orderid=?
          AND username=?
          AND (item=? OR description=?) 
      }) or die "Can't do: $DBI::errstr";
      $sth_details->execute("$db{'orderid'}","$data{'username'}","$modelnum","$modelnum") or die "Can't execute: $DBI::errstr";
    }
    else {
      $sth_details = $dbh_pnp->prepare(q{
          SELECT DISTINCT item,quantity,cost,description,customa,customb,customc,customd,custome
          FROM orderdetails 
          WHERE orderid=?
          AND username=? 
       }) or die "Can't do: $DBI::errstr";
      $sth_details->execute("$db{'orderid'}","$data{'username'}") or die "Can't execute: $DBI::errstr";
    }

    while (my ($item,$quantity,$cost,$description,$customa,$customb,$customc,$customd,$custome) = $sth_details->fetchrow) {
      #if ($ENV{'REMOTE_ADDR'} =~ /^(96\.56\.10\.1)/) {
      #  print "$item,$quantity, CST:$cost, DESC:$description,$customa,$customb,$customc,$customd,$custome<br>\n";
      #}
      #if ($ENV{'REMOTE_ADDR'} =~ /^(96\.56\.10\.1)/) {
      #  print "A:$item,$quantity, CST:$cost, DESC:$description, QBCOST:$qb_cost CTOTAL:$check_total<br>\n";
      #}

      $group_found = 0;
      $details_found = 0;
      $items_found = 0;
      my $sth_grp = $dbh->prepare(q{
          SELECT name,qty
          FROM qbgroups
          WHERE username=?
          AND sku=?
        }) or die "Can't do: $DBI::errstr";
      $sth_grp->execute("$qbooks::username","$item") or die "Can't execute: $DBI::errstr";

      while (my ($name,$qty) = $sth_grp->fetchrow) {
        $details_found = 1;
        $group_found = 1;
        $items_found++;
      
        my $sth_item = $dbh->prepare(q{
            SELECT description,acct,vendor,taxable,cost
            FROM items
            WHERE username=?
            AND name=?
          }) or die "Can't do: $DBI::errstr";
        $sth_item->execute("$qbooks::username","$name") or die "Can't execute: $DBI::errstr";
        my ($qb_desc,$qb_acct,$qb_vendor,$qb_taxable,$qb_cost) = $sth_item->fetchrow;
        $sth_item->finish;
        $qb_cost =~ s/[^0-9\.]//g;

#print "NAMEA:$name\n";

        if ($qb_desc eq "") {
          $qb_desc = $description;
        }
        if ($qb_cost eq "") {
          $qb_cost = "0";
        }
        ##  DCP  In situations where there is a 1:1 relationship in the group.  Merchant can use submitted data to replace Qbooks Item Cost.
        if (($data{'usecost'} eq "yes") && ($qty == 1)){
          $check_totalx = $check_total;
          $spl_qty = $quantity;
          $spl_amount = sprintf("%.2f",$cost * $spl_qty * (-1));
          $check_totalx += $spl_amount;
          if ($splacct{$qb_acct} eq "") {
            $splacct{$qb_acct} = "Fees";
          }
          $temp = "SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc";
#if ($ENV{'REMOTE_ADDR'} =~ /^(96\.56\.10\.1)/) {
#  print "CC: CTX:$check_totalx <Br>\n";
#}
        }
        $spl_qty = $quantity * $qty;
        $spl_amount = sprintf("%.2f",$qb_cost * $spl_qty * (-1));
        $check_total = $check_total + $spl_amount; 
        if ($splacct{$qb_acct} eq "") {
          $splacct{$qb_acct} = "Fees";
        }
        #@output = (@output,"SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc");
        $output[++$#output] = "SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc";
        $db{'splid'}++;
      }
      $sth_grp->finish;

      ##  DCP  In situations where there is a 1:1 relationship in the group.  Merchant can use submitted data to replace Qbooks Item Cost.
      if ( ($group_found == 1) && ($items_found == 1) && ($data{'usecost'} eq "yes") && ($qty == 1)) {
        $check_total = $check_totalx;
        #print "CAMT:$check_total<Br>\n";
        pop @output;
        #@output = (@output,"$temp");
        $output[++$#output] = "$temp";
#if ($ENV{'REMOTE_ADDR'} =~ /^(96\.56\.10\.1)/) { 
#  print "AAAA:TEMP2:$temp, QTY:$qty, CT:$check_total, CTX:$check_totalx<Br>\n";
#}
      }
      if ($group_found != 1) {
        $name = $item;

#print "NAME:$name:\n";

        my $sth_item = $dbh->prepare(q{
            SELECT description,acct,vendor,taxable,cost
            FROM items
            WHERE username=?
            AND name=?
          }) or die "Can't do: $DBI::errstr";
        $sth_item->execute("$qbooks::username","$name") or die "Can't execute: $DBI::errstr";
        my ($qb_desc,$qb_acct,$qb_vendor,$qb_taxable,$qb_cost) = $sth_item->fetchrow;
        $sth_item->finish;
        $qb_cost =~ s/[^0-9\.]//g;

        if ($data{'usecost'} eq "yes") {
          $qb_cost = $cost;
        }

        if (($qb_desc ne "") || ($qb_acct ne "")) {
          ###  Added DCP  20080129
          if ($qb_desc eq "") {
            $qb_desc = $description;
          }
          $details_found = 1;
          $spl_qty = $quantity;
          $spl_amount = sprintf("%.2f",$qb_cost * $spl_qty * (-1));
          $check_total = $check_total + $spl_amount;
          if ($qb_acct eq "") {
            $qb_acct = "Fees";
          }
          if ($qbooks::data{'longitem'} ne "yes") {
            $name = substr($name,0,12);
          }
          #@output = (@output,"SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc");
          $output[++$#output] = "SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc";
          $db{'splid'}++;

        }
      }
      if ($details_found != 1) {
        $name = $item;
        $qb_desc = $description;
        $qb_cost = $cost;
        $spl_qty = $quantity;
        $spl_amount = sprintf("%.2f",$qb_cost * $spl_qty * (-1));
        $check_total = $check_total + $spl_amount;
        if ($splacct{$qb_acct} eq "") {
          $splacct{$qb_acct} = "Fees";
        }
        if ($qbooks::data{'longitem'} ne "yes") {
          $name = substr($name,0,12);
        }
        #@output = (@output,"SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc");
        $output[++$#output] = "SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc";
        $db{'splid'}++;
      }
    }
    $sth_details->finish;
  }
  #elsif (($db{'recurring'} eq "yes") || ($qbooks::username =~ /^(oregonbusi|oregonmuni|csmfoconf)$/))  {
  elsif (($db{'recurring'} eq "yes") || (($qbooks::username =~ /^(oregonbusi|oregonmuni|csmfoconf)$/) && ($db{'acct_code'} ne "")) ) {  #### DCP 20111014
    if ($qbooks::username =~ /^(oregonbusi|oregonmuni|csmfoconf)$/) {
      $item = $db{'acct_code'};
    }
    else {
      $item = 'recurring';
    }

    $quantity = 1;
    $group_found = 0;
    $details_found = 0;
    my $sth_grp = $dbh->prepare(q{
        SELECT name,qty
        FROM qbgroups
        WHERE username=?
        AND sku=?
      }) or die "Can't do: $DBI::errstr";
    $sth_grp->execute("$qbooks::username","$item") or die "Can't execute: $DBI::errstr";
 
    while (my ($name,$qty) = $sth_grp->fetchrow) {
      $details_found = 1;
      $group_found = 1;
      my $sth_item = $dbh->prepare(q{
          SELECT description,acct,vendor,taxable,cost
          FROM items
          WHERE username=?
          AND name=?
        }) or die "Can't do: $DBI::errstr";
      $sth_item->execute("$qbooks::username","$name") or die "Can't execute: $DBI::errstr";
      my ($qb_desc,$qb_acct,$qb_vendor,$qb_taxable,$qb_cost) = $sth_item->fetchrow;
      $sth_item->finish;
      $qb_cost =~ s/[^0-9\.]//g;

      if ($qb_desc eq "") {
        $qb_desc = $description;
      }
      if ($qb_cost eq "") {
        $qb_cost = "0";
      }
      if ($qb_cost == 0) {
        $qb_cost = $db{'amount'};
      }
      $spl_qty = $quantity * $qty;
      $spl_amount = sprintf("%.2f",$qb_cost * $spl_qty * (-1));
      $check_total = $check_total + $spl_amount;
      if ($splacct{$qb_acct} eq "") {
        $splacct{$qb_acct} = "Fees";
      }
      #@output = (@output,"SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc");
      $output[++$#output] = "SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc";
      $db{'splid'}++;

    }
    $sth_grp->finish;
    if ($group_found != 1) {
      $name = $item;
      my $sth_item = $dbh->prepare(q{
          SELECT description,acct,vendor,taxable,cost
          FROM items
          WHERE username=?
          AND name=?
        }) or die "Can't do: $DBI::errstr";
      $sth_item->execute("$qbooks::username","$name") or die "Can't execute: $DBI::errstr";
      my ($qb_desc,$qb_acct,$qb_vendor,$qb_taxable,$qb_cost) = $sth_item->fetchrow;
      $sth_item->finish;
      $qb_cost =~ s/[^0-9\.]//g;
      if (($qb_desc ne "") || ($qb_acct ne "")) {
        if ($qb_cost eq "") {
          $qb_cost = "0";
        }
        if ($qb_cost == 0) {
          $qb_cost = $db{'amount'};
        }
        $details_found = 1;
        $spl_qty = $quantity;
        $spl_amount = sprintf("%.2f",$qb_cost * $spl_qty * (-1));
        $check_total = $check_total + $spl_amount;
        if ($qb_acct eq "") {
          $qb_acct = "Fees";
        }
        $name = substr($name,0,12);
        #@output = (@output,"SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc");
        $output[++$#output] = "SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc";
        $db{'splid'}++;
      }
    }
    if ($details_found != 1) {
      $name = $item;
      $qb_desc = $description;
      $qb_cost = $cost;
      $spl_qty = $quantity;
      $spl_amount = sprintf("%.2f",$qb_cost * $spl_qty * (-1));
      $check_total = $check_total + $spl_amount;
      if ($splacct{$qb_acct} eq "") {
        $splacct{$qb_acct} = "Fees";
      }
      $name = substr($name,0,12);
      #@output = (@output,"SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc");
      $output[++$#output] = "SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t$qb_name\t$spl_amount\t$data{'InvNo'}\t$name\t-$spl_qty\t$qb_cost\t$qb_desc";
      $db{'splid'}++;
    }
  }
  #$sth_details->finish;

  $dbh->disconnect;
 
  if ($db{'shipping'} > 0) {
    $db{'orgshipping'} = $db{'shipping'};
    $db{'shipping'} = sprintf("%.2f",$db{'shipping'} * (-1));

    $check_total = $check_total + $db{'shipping'};
    #@output = (@output,"SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$splacct{'Shipping'}\t\t$db{'shipping'}\t$data{'InvNo'}\tShipping\t-1\t$db{'orgshipping'}\tShipping");
    $output[++$#output] = "SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$splacct{'Shipping'}\t\t$db{'shipping'}\t$data{'InvNo'}\tShipping\t-1\t$db{'orgshipping'}\tShipping";
    $db{'splid'}++;
  }
 
  my $taxthreshold = 0; 
  if ($data{'qb2003'} eq "yes") {
    $taxthreshold = 0.01;
  }
  else {
    $taxthreshold = 0.00;
  }
 
  if ($db{'tax'} >= $taxthreshold) {
    #$db{'orgtax'} = $db{'tax'};
    my $tax = sprintf("%.2f",$db{'tax'} * (-1));
    $check_total = $check_total + $tax;
    
    #@output = (@output,"SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$splacct{'SalesTax'}\t$tax_vendor\t$db{'tax'}\t$data{'InvNo'}\tSalesTax\t-1\t$db{'orgtax'}\tSales Tax\tAUTOSTAX");
    #@output = (@output,"SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$splacct{'SalesTax'}\t$tax_vendor\t$db{'tax'}\t$data{'InvNo'}\t$data{'salestaxitem'}\t-1\t$db{'orgtax'}\tSales Tax\tAUTOSTAX");
    #$db{'splid'}++;
  }

  $check_total = sprintf("%.2f",$check_total * (-1));
  if ($check_total != 0) {
    my $sth_item = $dbh->prepare(q{
        SELECT description,acct,vendor,taxable,cost
        FROM items
        WHERE username=?
        AND name=?
      }) or die "Can't do: $DBI::errstr";
    $sth_item->execute("$qbooks::username","$data{'adjustmentitem'}") or die "Can't execute: $DBI::errstr";
    my ($qb_desc,$qb_acct,$qb_vendor,$qb_taxable,$qb_cost) = $sth_item->fetchrow;
    $sth_item->finish;

    #print "Content-Type: text/html\n\n";
    #print "<p>$data{'adjustmentitem'}:AAA:$qb_desc,$qb_acct,$qb_vendor,$qb_taxable,$qb_cost<p>\n";

    #@output = (@output,"SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t\t$check_total\t$data{'InvNo'}\t$data{'adjustmentitem'}\t1\t$check_total\t$qb_desc");
    $output[++$#output] = "SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$qb_acct\t\t$check_total\t$data{'InvNo'}\t$data{'adjustmentitem'}\t1\t$check_total\t$qb_desc";
    $db{'splid'}++;
  }

  if ($db{'tax'} >= $taxthreshold) {
    $db{'orgtax'} = $db{'tax'};
    $db{'tax'} = sprintf("%.2f",$db{'tax'} * (-1));
    #$check_total = $check_total + $db{'tax'};
    #@output = (@output,"SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$splacct{'SalesTax'}\t$tax_vendor\t$db{'tax'}\t$data{'InvNo'}\t$data{'salestaxitem'}\t-1\t$db{'orgtax'}\tSales Tax\tAUTOSTAX");
    $output[++$#output] = "SPL\t$db{'splid'}\t$data{'SaleType'}\t$qb_date\t$splacct{'SalesTax'}\t$tax_vendor\t$db{'tax'}\t$data{'InvNo'}\t$data{'salestaxitem'}\t-1\t$db{'orgtax'}\tSales Tax\tAUTOSTAX";
    $db{'splid'}++;
  }

#  $sth_details->finish;
  #@output = (@output,"ENDTRNS");
  $output[++$#output] = "ENDTRNS";
#  $dbh->disconnect;
  $data{'InvNo'}++;
}

sub qbooks_billing {  ########   PlugnPay Montly Billing Program, NOT for use by merchants
  #my (%data) = @_;
  if ($data{'format'} eq "display") {
    print "Content-Type: text/html\n\n";  
    print "<!DOCTYPE html>\n";
    print "<html lang=\"en-US\">\n";
    print "<head>\n";
    print "<meta charset=\"utf-8\">\n";
    print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
    print "</head>\n";
    print "<body bgcolor=#ffffff>\n";
    print "<pre>\n";
  }
  else {
    print "Content-Type: application/iif\n";
    print "Content-Disposition: inline; filename=qbooks.iif\n\n";
  }
  my $splid = 1;
  my $trnsid = 1;
  my $srchstr = "SELECT username,orderid,card_number,exp_date,amount,avs,card_type,descr,result,trans_date,avs,paidamount";
  $srchstr .=  " FROM quickbooks";

  my $op = 'WHERE';
  if ($data{'srchstartdate'} ne "") {
    $srchstr .= " $op trans_date>='$data{'srchstartdate'}'";
    $op = 'AND';
  }

  if ($data{'srchenddate'} ne "") {
    $srchstr .= " $op trans_date<'$data{'srchenddate'}'";
    $op = 'AND';
  }

  if ($data{'srchusername'} ne "") {
    $srchstr .= " $op username='$data{'srchusername'}'";
    $op = 'AND';
  }

  $srchstr .= " ORDER BY trans_date";

  print "\!TRNS\tTRNSID\tTRNSTYPE\tDATE\tACCNT\tAMOUNT\tNAME\tMEMO\tDOCNUM\tADDR1\tADDR2\tADDR3\tADDR4\tADDR5\n";
  print "\!SPL\tSPLID\tTRNSTYPE\tDATE\tACCNT\tAMOUNT\tMEMO\tDOCNUM\tPRICE\tINVITEM\n";
  print "\!ENDTRNS\n";
  $dbh_pnp = &miscutils::dbhconnect("pnpdata");
  $dbh_cust = &miscutils::dbhconnect("pnpmisc");

  $sth = $dbh_pnp->prepare(qq{$srchstr}) or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  while (my ($username,$orderid,$card_number,$exp_date,$amount,$avs,$card_type,$descr,$result,$trans_date,$avs,$paidamount) = $sth->fetchrow) {
    $sth_cust = $dbh_cust->prepare(q{
        SELECT name,company,addr1,addr2,city,state,zip,country,enccardnumber,length,card_number,exp_date
        FROM customers
        WHERE username=?
      }) or die "Can't prepare: $DBI::errstr";
    $sth_cust->execute("$username") or die "Can't execute: $DBI::errstr";
    ($card_name,$company,$card_addr1,$card_addr2,$card_city,$card_state,$card_zip,$card_country,$enccardnumber,$length,$card_number,$exp_date) = $sth_cust->fetchrow;
    $sth_cust->finish;

    $card_addr = $card_addr1 . $card_addr2;

    #$qb_date = substr($trans_date,4,2) . "/" . substr($trans_date,6,2) . "/" . substr($trans_date,2,2);
    $qb_date = $data{'invdate'};

    if ($descr =~ /setup/i) {
      $splacct = "Fees:Setup:Core";
      $invitem = "Core Setup";
    }
    elsif ($descr =~ /monthly/i) {
      $splacct = "Fees:Monthly:Core";
      $invitem = "PnPMonthly";
    }
    else {
      $splacct = "Fees";
      $invitem = "Custom Program";
    }
    if ($amount > 0) {
      print "TRNS\t$trnsid\t$data{'SaleType'}\t$qb_date\t$data{'AcctRec'}\t$amount\t$username\t$data{'Memo'}\t$data{'InvNo'}\t$card_name\t$card_addr\t$card_city, $card_state  $card_zip\t$card_country\n";

      if ($tax > 0) {
        $tax = sprintf("%.2f",$tax);
        print "SPL\t$splid\t$data{'SaleType'}\t$qb_date\t$splacct{'SalesTax'}\t-$tax\t$data{'InvNo'}\tSales Tax\t1\t$tax\tSales Tax\n";
        $spl++;
      }
      $quantity = 1;
      print "SPL\t$splid\t$data{'SaleType'}\t$qb_date\t$splacct\t-$amount\t$descr\t$data{'InvNo'}\t$amount\t$invitem\n";
    #print "SPL\t$splid\t$data{'SaleType'}\t$qb_date\t$data{'splAcct'}\t-$amount\t$data{'InvNo'}\t$descr\t$amount\n";

      if ($data{'format'} ne "display") {
        $sth_pay = $dbh_cust>prepare(q{
            UPDATE quickbooks
            SET inv_no=?
            WHERE orderid=?
            AND username=?
          }) or die "Can't prepare: $DBI::errstr";
        $sth_pay->execute("$data{'InvNo'}","$orderid","$username") or die "Can't execute: $DBI::errstr";
        $sth_pay->finish;
      }

      $spl++;
#    last if($data{'InvNo'} > 10);
  
      $data{'InvNo'}++;
      print "ENDTRNS\n";
    }
  }
  $sth->finish;
  $dbh_pnp->disconnect;
  $dbh_cust->disconnect;

  if ($data{'format'} eq "display") {
    print "\n</pre>\n";
    print "</table>\n";
    print "</div>\n";
    print "</body>\n";
    print "</html>\n";
  }
  else {
    print "\n\n";
  }
}

sub qbooks_receive_payments {  ########   PlugnPay Montly Billing Program, NOT for use by merchants
  #my (%data) = @_;
  if ($data{'format'} eq "display") {
    print "Content-Type: text/html\n\n";
    print "<!DOCTYPE html>\n";
    print "<html lang=\"en-US\">\n";
    print "<head>\n";
    print "<meta charset=\"utf-8\">\n";
    print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
    print "</head>\n";
    print "<body bgcolor=#ffffff>\n";
    print "<pre>\n";
  }
  else {
    print "Content-Type: application/iif\n";
    print "Content-Disposition: inline; filename=qbooks.iif\n\n";
  }
  my $splid = 1;
  my $trnsid = 1;

  my $srchstr = "SELECT username,orderid,card_number,exp_date,amount,card_type,descr,result,trans_date,avs,paidamount,inv_no";
  $srchstr .= " FROM quickbooks";

  my $op = 'WHERE';
  if ($data{'srchstartdate'} ne "") {
    $srchstr .= " $op trans_date>='$data{'srchstartdate'}'";
    $op = 'AND';
  }

  if ($data{'srchenddate'} ne "") {
    $srchstr .= " $op trans_date<'$data{'srchenddate'}'";
    $op = 'AND';
  }

  if ($data{'srchusername'} ne "") {
    $srchstr .= " $op username='$data{'srchusername'}'";
    $op = 'AND';
  }

  if ($data{'accounts'} eq "ach") {
    $srchstr .= " $op card_type='checking'";
    $op = 'AND';
  }
  else {
    $srchstr .= " $op card_type='credit'";
    $op = 'AND';
  }

  $srchstr .= " ORDER BY trans_date";

  print "\!TRNS\tTRNSID\tTRNSTYPE\tDATE\tACCNT\tAMOUNT\tNAME\tDOCNUM\n";
  print "\!SPL\tSPLID\tTRNSTYPE\tDATE\tACCNT\tAMOUNT\tDOCNUM\tPAYMETH\n";
  print "\!ENDTRNS\n";

  $dbh_pnp = &miscutils::dbhconnect("pnpmisc");

  $sth = $dbh_pnp->prepare(qq{$srchstr}) or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  while (my ($username,$orderid,$card_number,$exp_date,$amount,$card_type,$descr,$result,$trans_date,$avs,$paidamount,$inv_no) = $sth->fetchrow) {
    #print "$username,$orderid,$card_number,$exp_date,$amount,$card_type,$descr,$result,$trans_date,$avs,$paidamount,$inv_no\n";
    #print "$username,$orderid,$card_number,$card_type\n";

    my $cardbin = substr($card_number,0,6);
    if ($cardbin =~ /^(4)/) {
      $cardtype = "VISA";
    }
    elsif ($cardbin =~ /^(51|52|53|54|55)/) {
      $cardtype = "MSTR";
    }
    elsif ($cardbin =~ /^(37|34)/) {
      $cardtype = "AMEX";
    }
    elsif ($cardbin =~ /^(30|36|38[0-8])/) {
      $cardtype = "DNRS";
    }
    elsif ($cardbin =~ /^(389)/) {
      $cardtype = "CRTB";
    }
    elsif ($cardbin =~ /^(6011)/) {
      $cardtype = "DSCR";
    }
    elsif ($cardbin =~ /^(3528[0-9][0-9])/) {
      $cardtype = "JCB";
    }
    elsif ($cardbin =~ /^(1800|2131)/) {
      $cardtype = "JAL";
    }
    elsif ($cardbin =~ /^(7)/) {
      $cardtype = "MYAR";
    }
    elsif (($card_number =~ / /) || ($card_type =~ /checking/i)) {
      $cardtype = "CHECKING";
    }

    if (($cardtype =~ /visa/i) || ($cardtype =~ /mstr/i)) {
      $paymethod = "V/MC";
      $deposit_acct = "Visa/MC";
    }
    elsif ($cardtype =~ /dscr/i) {
      $paymethod = "Discover";
      $deposit_acct = "Discover";
    }
    elsif ($cardtype =~ /amex/i) {
      $paymethod = "American Express";
      $deposit_acct = "Amex";
    }
    elsif ($cardtype =~ /checking/i) {
      $paymethod = "ACH";
      $deposit_acct = "Undeposited Funds";
    }

    $qb_date = substr($trans_date,4,2) . "/" . substr($trans_date,6,2) . "/" . substr($trans_date,2,2);
    $splacct = "Accounts Receivable";

    if (($amount > 0) && ($result eq "success")) {
      print "TRNS\t$trnsid\tPAYMENT\t$qb_date\t$deposit_acct\t$amount\t$username\t$inv_no\n";

      $quantity = 1;
      print "SPL\t$splid\tPAYMENT\t$qb_date\t$splacct\t-$amount\t$inv_no\t$paymethod\n";
      $spl++;
      print "ENDTRNS\n";
    }
  }
  $sth->finish;
  $dbh_pnp->disconnect;
  if ($data{'format'} eq "display") {
    print "\n</pre>\n";
    print "</table>\n";
    print "</div>\n";
    print "</body>\n";
    print "</html>\n";
  }
  else {
    print "\n\n";
  }
}


######  BANK RECONCILIATION PORTION - NEEDS WORK

# The purpose of this program is create an import file for quickbooks.
# It functions by unrolling each batch and separating the transactions into individual card types,
# as well as keeping track of both returns and charges.

sub qbooks_bank {
if ($afdfdddfd eq "dfadfdfdfdfdf") {
  my $dbh = &miscutils::dbhconnect("qbooks");
  my $sth_acct = $dbh->prepare(q{
      SELECT name,acct,description
      FROM accounts
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth_acct->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
  while (my ($name,$splacct,$desc) = $sth_acct->fetchrow) {
    $acct{$name} = $splacct;
  }
  $sth_acct->finish;

  my $sth = $dbh->prepare(q{
      SELECT acctbank,acctrec,acctundep,acctsalestax,acctcharges,axasset,dsasset,mvasset,otasset 
      FROM rules
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
  my ($acctbank,$acctrec,$acctundep,$acctsalestax,$acctcharges,$axasset,$dsasset,$mvasset,$otasset) = $sth_cust->fetchrow;
  $sth->finish;

  $splacct{'undeposited_funds'} = $acct{$acctundep};
  $splacct{'bank_acct'} = $acct{$acctbank};
  $splacct{'AcctRec'} = $acct{$acctrec};
  $splacct{'expense_acct'} = $acct{$acctcharges};
  $splacct{'SalesTax'} = $acct{$acctsalestax};
  $splacct{'amex_asset'} = $acct{$axasset};
  $splacct{'disc_asset'} = $acct{$dsasset};
  $splacct{'visa_asset'} = $acct{$mvasset};
  $splacct{'other_asset'} = $acct{$otasset};
}

  my $sth = $dbh->prepare(q{
      SELECT username,axqual,axmid,axnon,dsqual,dsmid,dsnon,mcqual,mcmid,mcnon,vsqual,vsmid,vsnon,otqual,otmid,otnon
      FROM rates
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$qbooks::username") or die "Can't execute: $DBI::errstr";
  my ($axqual,$axmid,$axnon,$dsqual,$dsmid,$dsnon,$mcqual,$mcmid,$mcnon,$vsqual,$vsmid,$vsnon,$otqual,$otmid,$otnon) = $sth_cust->fetchrow;
  $sth->finish;

  $rate{'vs'} = $vsqual;
  $rate{'mc'} = $mcqual;
  $rate{'ax'} = $axqual;
  $rate{'ds'} = $dsqual;
  $rate{'ot'} = $otqual;

  $mid{'vs'} = $vsmid;
  $mid{'mc'} = $mcmid;
  $mid{'ax'} = $axmid;
  $mid{'ds'} = $dsmid;
  $mid{'ot'} = $otmid;

  $non{'vs'} = $vsnon;
  $non{'mc'} = $mcnon;
  $non{'ax'} = $axnon;
  $non{'ds'} = $dsnon;
  $non{'ot'} = $otnon;

  $start_time = $data{'srchstartdate'} . "000000";
  $end_time = $data{'srchenddate'} . "000000";

#### These are hardcoded vales for testing only #######
  $hours_non{'vs'} = 72;
  $non{'vs'} = 0.0325;
  $hours_mid{'vs'} = 48;
  $mid{'vs'} = 0.0245;

  $hours_non{'mc'} = 72;
  $non{'mc'} = 0.0325;
  $hours_mid{'mc'} = 48;
  $mid{'mc'} = 0.0245;

  $hours_non{'ax'} = 0;
  $non{'ax'} = 0.035;
  $hours_mid{'ax'} = 0;
  $mid{'ax'} = 0.035;

  $hours_non{'ds'} = 0;
  $non{'ds'} = 0.0225;
  $hours_mid{'ds'} = 0;
  $mid{'ds'} = 0.0225;

  $hours_non{'ot'} = 0;
  $non{'ot'} = 0.0225;
  $hours_mid{'ot'} = 0;
  $mid{'ot'} = 0.0225;

  &bank_calc();
  $dbh->disconnect;
}

sub bank_calc {
  $batch_count = 0;
  $batch_subtotal = 0;

  %result1 = &miscutils::sendmserver("$data{'username'}",'query',
            'txn-status', "success",
            'start-time', "$start_time",
            'end-time', "$end_time",
            'txn-type', "batch");
  
  my @values = values %result1;
  foreach my $var1 (sort @values) {
#print "VAR:$var1<br>\n";
    %res1 = ();
    @nameval = split(/\&/, $var1);
    foreach my $temp (@nameval) {
      ($name,$value) = split(/\=/, $temp);
      $res1{$name} = $value;
    }
    $batchcnt++;
#    print "BCNT:$batchcnt<br>\n";
    if (($res1{'time'} ne "") && (($batchstatusin eq "") || ($res1{'batch-status'} eq $batchstatusin))) {
#print "AAAAAAAA:$batchcnt<br>\n";
      $time = $res1{"time"};
      $timestr = substr($time,4,2) . "/" . substr($time,6,2) . "/" . substr($time,0,4) . " ";
      $timestr = $timestr . substr($time,8,2) . ":" . substr($time,10,2) . ":" . substr($time,12,2);

      $txntype = $res1{"txn-type"};
      $status = $res1{"txn-status"};
      $batch_id = $res1{"batch-id"};
      $gateid = $res1{"gw-batch-id"};
      $batchstatus = $res1{"batch-status"};
      $amount = $res1{"amount"};

      $filedate = substr($time,0,8);
      $filehour = substr($time,8,2);
 
#print "\n<p>ST:$status:FD:$filedate:TI:$time:BID:$batch_id<p>\n";
 
    # Now we take each batch that has a status of success and unroll it.
      if(($status = ~/success/) && ($filedate ne "")) {
        &unroll_batch($filedate,$batch_id);
#print "<p><p><p>UNROLL COMPLETE<p><p>\n";
      }
    }
  }

  #$i = 1;
  #foreach my $filedate (sort keys %ttotal) { 
  #  if ($filedate ne ""){
  #    print "\!TRNS	TRNSTYPE	DATE	ACCNT	AMOUNT	DOCNUM	ADDR1	ADDR2	ADDR3	INVMEMO	INVTITLE	MEMO\n";
  #    print "\!SPL	TRNSTYPE	DATE	ACCNT	AMOUNT	DOCNUM	INVITEM	TAXABLE	EXTRA	MEMO\n";
  #    print "\!ENDTRNS	\n";
  #    foreach my $batch_id (sort keys %total) { 
  #      if($filedate{$batch_id} eq $filedate){;
  #        $b = $total{$batch_id}-$rtotal{$batch_id};
  #        $b1 = (-1) * $b;
  #        if($b < 0){
  #          $transtype = "CASH REFUND";
  #        }
  #        else {
  #          $transtype = "CASH SALE";
  #        }
  #        print "TRNS	$transtype	$date{$batch_id}	$splacct{'undeposited_funds'}	$b	$batch_id	Plug and Pay Technologies, Inc.	1363-26 Veterans Hwy	Hauppauge, NY  11788	Plug and Pay - Your E-Commerce Solution	Batch Statement\n";
  #        print "SPL	$transtype	$date{$batch_id}	$splacct{'income_acct'}	$b1	$batch_id	Pnp	N		Web Site Sales Batch \# $batch_id\n";
  #        print "SPL	$transtype	$date{$batch_id}	$splacct{'SalesTax'}	0	$batch_id	Out of State	N	AUTOSTAX\n";
  #        print "ENDTRNS	\n";								
  #      }
  #    }
  #    $date = substr($filedate,4,2) . "\/" . substr($filedate,6,2) . "\/" . substr($filedate,2,2);
  &close_day();
  #  }
  #}
}

sub unroll_batch {
  my($filedate,$batch_id) = @_;

# initialize all sum values to 0
  %total = ();
  %sale = ();
  # unroll batch

  #print "DDDD:$batch_id:UN:$data{'username'}<p>\n";

  %result2 = &miscutils::sendmserver("$data{'username'}",'batch-unroll',
            'batch-id', "$batch_id");

#  print "<p>RES:\n";
#  print %result;

  my @values = values %result2;
  foreach my $var2 (sort @values) {
    %res2 = ();
    @nameval = split(/\&/, $var2);
    foreach my $temp (@nameval) {
      ($name,$value) = split(/\=/, $temp);
      $res2{$name} = $value;
    }

    if ($res2{'time'} ne "") {
      $time = $res2{"time"};
      $timestr = substr($time,4,2) . "/" . substr($time,6,2) . "/" . substr($time,0,4) . " ";
      $timestr = $timestr . substr($time,8,2) . ":" . substr($time,10,2) . ":" . substr($time,12,2);

      $txn_type = $res2{"txn-type"};
      $origin = $res2{"origin"};
      $status = $res2{"txn-status"};
      $order_id = $res2{"order-id"};
      $time = $res2{"time"};
      $cardnumber = $res2{"card-number"};
      $amount = $res2{"amount"};
      $card_type = $res2{"card-type"};
     
      $cardnumber = substr($cardnumber,0,2) . "**" . substr($cardnumber,2,4);

      if ($order_id ne ""){
        &transauth_date($order_id);
      }
      # if txn is a settlement, check for time difference between auth and settlement date and add 
      # appropriate discount rate modifiers.
      $delta = ($filedate - $date{$order_id}) * 24;
      $hours = ($filehour - $hour{$order_id});
      $hour_delta = $delta + $hours;

     #print "$hour_delta:$filedate:$filehour:$date{$order_id}:$hour{$order_id}<br>\n";
     # print "AMT:$amount,CT:$card_type,OID:$order_id,TT:$txn_type:<br>\n";
      my ($dummy, $cost) = split(/ /, "$amount");
      if($txn_type eq "settled"){
        $qual = &discount_rate($card_type);
        $total{"$card_type"} =  $total{"$card_type"} + $cost;
        $total{$card_type . "c"} = $total{$card_type . "c"} + ($cost * ($rate{$card_type} + $qual));
 #       print "CT:$card_type,SA:$cost,TOT:$total{$card_type},TOTC:$total{$card_type . \"c\"}<br>\n";
        #&sum_charges();
        &order_details($order_id);
      }
      elsif ($txn_type eq "setlret") {
        $total{"$card_type\r"} =   $total{"$card_type\r"} + $cost;
        $total{"$card_type\rc"} =   $total{"$card_type\rc"} + ($cost * $rate{$card_type});
        #&sum_returns();
      }
      if (($txn_type eq "settled") && ($status eq "success")) {
        $cardtotal{$cardtype} = $cardtotal{$cardtype} + $cost;
        $charges = $charges + $cost;
      }
      elsif ($status eq "success") {
        $cardtotal{$cardtype} = $cardtotal{$cardtype} - $cost;
        $credits = $credits + $cost;
      }

      #print "VTOTAL: $vtotal, $atotal, $dtotal, $ototal, $input{'order-id'}<br>\n";
      $amount = 0;
    }
  }
  #print "TBID:$total{$batch_id}, VS:$total{'vs'}  MC:$total{'mc'}  AX:$total{'ax'}  DS:$total{'ds'}  OT:$total{'ot'}<br>\n";
  #print "VS:$vtotal{$filedate} VR:$vrtotal{$filedate} MC:$mtotal{$filedate} MR:$mrtotal{$filedate}<br>\n";

  $filedate{$batch_id} = $filedate;
  $total{$batch_id} = $total{'vs'} + $total{'mc'} + $total{'ax'} + $total{'ds'} + $total{'ot'};
  $ctotal{$batch_id} = $total{'vsc'} + $total{'mcc'} + $total{'axc'} + $total{'dsc'} + $total{'otc'};
  $rtotal{$batch_id} = $total{'vsr'} + $total{'mcr'} + $total{'axr'} + $total{'dsr'} + $total{'otr'};
  $rctotal{$batch_id} = $total{'vsrc'} + $total{'mcrc'} + $total{'axrc'} + $total{'dsrc'} + $total{'otrc'};

  $date{$batch_id} = substr($time,4,2) . "\/" . substr($time,6,2) . "\/" . substr($time,2,2);

  $ttotal{$filedate} = $ttotal{$filedate} + $total{$batch_id};
  $vtotal{$filedate} = $vtotal{$filedate} + $total{'vs'};
  $mtotal{$filedate} = $mtotal{$filedate} + $total{'mc'};
  $atotal{$filedate} = $atotal{$filedate} + $total{'ax'};
  $dtotal{$filedate} = $dtotal{$filedate} + $total{'ds'};
  $ototal{$filedate} = $ototal{$filedate} + $total{'ot'};

  $tctotal{$filedate} = $tctotal{$filedate} + $ctotal{$batch_id};
  $vctotal{$filedate} = $vctotal{$filedate} + $total{'vsc'};
  $mctotal{$filedate} = $mctotal{$filedate} + $total{'mcc'};
  $actotal{$filedate} = $actotal{$filedate} + $total{'axc'};
  $dctotal{$filedate} = $dctotal{$filedate} + $total{'dsc'};
  $octotal{$filedate} = $octotal{$filedate} + $total{'otc'};

  $trtotal{$filedate} = $trtotal{$filedate} + $rtotal{$batch_id};
  $vrtotal{$filedate} = $vrtotal{$filedate} + $total{'vsr'};
  $mrtotal{$filedate} = $mrtotal{$filedate} + $total{'mcr'};
  $artotal{$filedate} = $artotal{$filedate} + $total{'axr'};
  $drtotal{$filedate} = $drtotal{$filedate} + $total{'dsr'};
  $ortotal{$filedate} = $ortotal{$filedate} + $total{'otr'};

  $trctotal{$filedate} = $trctotal{$filedate} + $trctotal{$batch_id};
  $vrctotal{$filedate} = $vrctotal{$filedate} + $total{'vsrc'};
  $mrctotal{$filedate} = $mrctotal{$filedate} + $total{'mcrc'};
  $arctotal{$filedate} = $arctotal{$filedate} + $total{'axrc'};
  $drctotal{$filedate} = $drctotal{$filedate} + $total{'dsrc'};
  $orctotal{$filedate} = $orctotal{$filedate} + $total{'otrc'};

  #print "TBID:$total{$batch_id}, VS:$total{'vs'}  MC:$total{'mc'}  AX:$total{'ax'}  DS:$total{'ds'}  OT:$total{'ot'}<br>\n";
  #print "VS:$vtotal{$filedate} VR:$vrtotal{$filedate} MC:$mtotal{$filedate} MR:$mrtotal{$filedate}<br>\n";
}

sub order_detail {
  my ($orderid) = @_;

  my $srchstr = "SELECT o.orderid,o.card_name,o.card_addr,";
  $srchstr .= "o.card_city,o.card_state,o.card_zip,o.card_country,";
  $srchstr .= "o.amount,o.tax,o.shipping,o.trans_date,o.trans_time,";
  $srchstr .= "o.result,o.descr,o.acct_code,";
  $srchstr .= "o.morderid,o.shipname,o.shipaddr1,o.shipaddr2,";
  $srchstr .= "o.shipcity,o.shipstate,o.shipzip,o.shipcountry,o.phone,";
  $srchstr .= "o.fax,o.email,o.plan,o.billcycle,o.easycart,";
  $srchstr .= "o.ipaddress,o.useragent,o.referrer,o.card_number,";
  $srchstr .= "o.card_exp,o.successlink,o.shipinfo,";
  $srchstr .= "o.publisheremail,o.avs,o.duplicate,o.enccardnumber,o.length";
  $srchstr .= " FROM ordersummary o";
  #$srchstr .= " WHERE LOWER(o.orderid) LIKE LOWER('\%$orderid\%')";
  $srchstr .= " WHERE o.orderid=?";
  $srchstr .= " AND o.username=?";

  $dbh_pnp = &miscutils::dbhconnect("pnpdata");
  $sth_orders = $dbh->prepare(qq{$srchstr}) or die "Can't do: $DBI::errstr";
  $sth_orders->execute("$orderid", "$data{'username'}") or die "Can't execute: $DBI::errstr";
  
  ($db{'orderid'},$db{'card_name'},$db{'card_addr'},
  $db{'card_city'},$db{'card_state'},$db{'card_zip'},$db{'card_country'},
  $db{'amount'},$db{'tax'},$db{'shipping'},$db{'trans_date'},$db{'trans_time'},
  $db{'result'},$db{'descr'},$db{'acct_code'},
  $db{'morderid'},$db{'shipname'},$db{'shipaddr1'},$db{'shipaddr2'},
  $db{'shipcity'},$db{'shipstate'},$db{'shipzip'},$db{'shipcountry'},$db{'phone'},
  $db{'fax'},$db{'email'},$db{'plan'},$db{'billcycle'},$db{'easycart'},
  $db{'ipaddress'},$db{'useragent'},$db{'referrer'},$db{'card_number'},
  $db{'card_exp'},$db{'successlink'},$db{'shipinfo'},
  $db{'publisheremail'},$db{'avs'},$db{'duplicate'},$db{'enccardnumber'},$db{'length'}) = $sth_orders->fetchrow;

  &sales_iif(%db);
}

sub close_day {
  print "!TRNS	TRANSFER	DATE	ACCNT	AMOUNT	NAME\n";
  print "!SPL	TRANSFER	DATE	ACCNT	AMOUNT	NAME		DOCNUM\n";
  print "!ENDTRNS	\n";

  if(($vtotal{$filedate} > 0)||($vtotal{$filedate} < 0)||($mtotal{$filedate} > 0)||($mtotal{$filedate} < 0)) {
    $a = $vtotal{$filedate} - $vrtotal{$filedate} + $mtotal{$filedate} - $mrtotal{$filedate};
    $a1 = (-1) * $a;
    print "TRNS	TRANSFER	$date	$splacct{'undeposited_funds'}	$a1	Plug and Pay Technologies, Inc.\n";
    print "SPL	TRANSFER	$date	$splacct{'visa_asset'}	$a	Plug and Pay Technologies, Inc.		$batch_id\n";		 
    print "ENDTRNS	\n";
  }
  if(($atotal{$filedate} > 0)||($atotal{$filedate} < 0)) {
    $a = $atotal{$filedate} - $artotal{$filedate} + 0;
    $a1 = (-1) * $a;
    print "TRNS	TRANSFER	$date	$splacct{'undeposited_funds'}	$a1	Plug and Pay Technologies, Inc.\n";
    print "SPL	TRANSFER	$date	$splacct{'amex_asset'}	$a	Plug and Pay Technologies, Inc.		$batch_id\n";		
    print "ENDTRNS	\n";
  }
  if(($dtotal{$filedate} > 0)||($dtotal{$filedate} < 0)) {
    $a = $dtotal{$filedate} - $drtotal{$filedate};
    $a1 = (-1) * $a;
    print "TRNS	TRANSFER	$date	$splacct{'undeposited_funds'}	$a1	Plug and Pay Technologies, Inc.\n";
    print "SPL	TRANSFER	$date	$splacct{'disc_asset'}	$a	Plug and Pay Technologies, Inc.		$batch_id\n";		
    print "ENDTRNS	\n";
  }
  if(($ototal{$filedate} > 0)||($ototal{$filedate} < 0)) {
    $a = $ototal{$filedate} - $ortotal{$filedate};
    $a1 = (-1) * $a;
    print "TRNS	TRANSFER	$date	$splacct{'undeposited_funds'}	$a1	Plug and Pay Technologies, Inc.\n";
    print "SPL	TRANSFER	$date	$splacct{'other_asset'}	$a	Plug and Pay Technologies, Inc.		$batch_id\n";		
    print "ENDTRNS	\n";
  }

  print "\!TRNS	TRANSFER	DATE	ACCNT	AMOUNT	NAME		\n";
  print "\!SPL	TRANSFER	DATE	ACCNT	AMOUNT	NAME		DOCNUM\n";
  print "\!ENDTRNS	\n";


  if (($vtotal{$filedate} > 0)||($mtotal{$filedate} > 0)){
    $a = $vtotal{$filedate} + $mtotal{$filedate} - $vrtotal{$filedate} - $mrtotal{$filedate};
    $fee1 = $vrctotal{$filedate} + $mrctotal{$filedate} + $vctotal{$filedate} + $mctotal{$filedate};
    $fee = sprintf("%.2f",$fee1);
    $cash1 = $a - $fee;
    $cash = sprintf("%.2f",$cash1);
    $a1 = (-1) * $a;
    print "TRNS	TRANSFER	$date	$splacct{'visa_asset'}	$a1	Plug and Pay Technologies, Inc.\n";
    print "SPL	TRANSFER	$date	$splacct{'expense_acct'}	$fee	Plug and Pay Technologies, Inc.		$batch_id\n";
    print "SPL	TRANSFER	$date	$splacct{'bank_acct'}	$cash	Plug and Pay Technologies, Inc.		$batch_id\n";
    print "ENDTRNS	\n";
  }
  if ($atotal{$filedate} > 0){
    $a = $atotal{$filedate} - $artotal{$filedate};
    $fee1 = $arctotal{$filedate} + $actotal{$filedate};
    $fee = sprintf("%.2f",$fee1);
    $cash1 = $a - $fee;
    $cash = sprintf("%.2f",$cash1);
    $a1 = (-1) * $a;
    print "TRNS	TRANSFER	$date	$splacct{'amex_asset'}	$a1	Plug and Pay Technologies, Inc.\n";
    print "SPL	TRANSFER	$date	$splacct{'expense_acct'}	$fee	Plug and Pay Technologies, Inc.		$batch_id\n";
    print "SPL	TRANSFER	$date	$splacct{'bank_acct'}	$cash	Plug and Pay Technologies, Inc.		$batch_id\n";
    print "ENDTRNS	\n";
  }
  if ($dtotal{$filedate} > 0){
    $a = $dtotal{$filedate} - $drtotal{$filedate};
    $fee1 = $drctotal{$filedate} + $dctotal{$filedate};
    $fee = sprintf("%.2f",$fee1);
    $cash1 = $a - $fee;
    $cash = sprintf("%.2f",$cash1);
    $a1 = (-1) * $a;
    print "TRNS	TRANSFER	$date	$splacct{'disc_asset'}	$a1	Plug and Pay Technologies, Inc.\n";
    print "SPL	TRANSFER	$date	$splacct{'expense_acct'}	$fee	Plug and Pay Technologies, Inc.		$batch_id\n";
    print "SPL	TRANSFER	$date	$splacct{'bank_acct'}	$cash	Plug and Pay Technologies, Inc.		$batch_id\n";
    print "ENDTRNS	\n";
  }
  if ($ototal{$filedate} > 0){
    $a = $ototal{$filedate} - $ortotal{$filedate};
    $fee1 = $orctotal{$filedate} + $octotal{$filedate};
    $fee = sprintf("%.2f",$fee1);
    $cash1 = $a - $fee;
    $cash = sprintf("%.2f",$cash1);
    $a1 = (-1) * $a;
    print "TRNS	TRANSFER	$date	$splacct{'other_asset'}	$a1	Plug and Pay Technologies, Inc.\n";
    print "SPL	TRANSFER	$date	$splacct{'expense_acct'}	$fee	Plug and Pay Technologies, Inc.		$batch_id\n";
    print "SPL	TRANSFER	$date	$splacct{'bank_acct'}	$cash	Plug and Pay Technologies, Inc.		$batch_id\n";
    print "ENDTRNS	\n";
   }
}

sub input {
  &report_head();
  print <<EOF;
<b>Please read the following information carefully.</b>
<p> Welcome to the Plug and Pay QuickBooks Module.  This module is designed to facilitate reconciliation of your bank statement by allowing you to import your batch history directly into your QuickBooks accounting package.  This will allow you to more quickly reconcile your bank account on a monthly basis by making it easier to match actual bank deposits with you batch submittals.  Any fees deducted from your bank account after the deposit is made is not accounted for by this module.
<p> Running this module will create a separate file for each day that a batch was submitted during the selected time period.  These files can then be saved to your local system and imported into QuickBooks.  Upon importing, the file will create the following transactions:
<ol>
<li>Create a Cash Sale for each batch and Log the amount as income to the \"Income Account\" Specified Below.
<li>Consolidate all Sales for the day and deposit the \"Sale Amount\" into the account \"Undeposited Funds\"
<li>Withdraw the \"Sale Amount\" from \"Undeposited Funds\", separate it based upon payment method and deposit the 
appropriate amounts into \"Asset Accounts\" associated with each card type.
<li>Deduct the \"Discout Rate\" from each of the above deposits as a \"Merchant Account Charges\" expense.
<li>Transfer the remaining balance to your checking account
</ol>
<p> Because these files are created from your Batch Histories, there are several things it does not do, yet\!.
<ol>
<li>Account for any transaction fees deducted from your account after the deposit has been made, i.e. \$0.40/transaction.
<li>Account for any statement fee.
<li>Acount for any monthly minimum charge.
<li>Account for your monthly Plug and Pay fees.
<li>Track Sales Tax expenses.
<li>Track which product was purchased.
</ol>
<p> In order for this module to work properly you will need to have the proper accounts set up in QuickBooks for your company.  This can either be done manually or you can <a href=\"accts.iif\">\"CLICK HERE\"</a> and download a file which you can import into QuickBooks which will create the appropriate accounts for you. The names and types of accounts required are as follows:
<table border=1>
<tr><th>Account Name<th>Type<th>Description
<tr><td>Checking<td>bank<td>This is you bank account into which your merchant account provider currently deposits your funds.
<tr><td>Undeposited Funds<td>Other Current Asset<td>This is a \"Holding Account\" where funds are held until transfered to the appropriate accout.
<tr><td>Visa/MC Merchant Account<td>Other Current Asset<td rowspan=4>These are \"Asset Accounts\" where deposits for each card type are held until they can be transferred to the appropriate account.
<tr><td>Amex Merchant Account<td>Other Current Asset
<tr><td>Discover Merchant Account<td>Other Current Asset
<tr><td>Other Merchant Account<td>Other Current Asset
<tr><td>Web Site Sales<td>Income<td>Income Account used to track sales from your web site
<tr><td>Merchant Account Charges<td>Expense<td>Expense Account used to track expenses associated with your merchant account fees.
<tr><td>Sales Tax Payable<td>Other Current Libility<td>This account would normally be used to track sales tax which is owed the state. This is included due to requirements of the QuickBooks program.  No dollar values deposits will be made to this account.
</table>
<p> Due to the way you would import the transaction data, we encourage you to either make a copy of you current company records under a different name and try importing the files into that company first or import the data first into the \"Sample\" company that was created by QuickBooks upon installation.
<p> We also plan on expanding the capability of this module based upon customer requirements.  We therefore stongly request that you submit feedback on what additional capabilites you would like to see or problems you are having.
<p> Please Edit the Following Account information if you are using a configuration other than the default and select the dates you wish to create import files for.
<p> <b><font size=+1>NOTE:  Please be careful to avoid importing a file twice.  A separate deposit will be recorded each time a file is imported</font>
<p> <form method=\"post\" action=\"qbooks.cgi\">
<pre>  
          Publisher Name: <input type=text name=\"username\"  size=8 max=8>
  Bank Acct for Deposits: <input type=text name=\"checking_acct\" value=\"Checking\" size=25 max=30>
  Undeposited Funds Acct: <input type=text name=\"undeposited_funds\" value=\"Undeposited Funds\" size=25 max=30>
   Visa/MC Asset Account: <input type=text name=\"visa_asset\" value=\"Visa/MC Merchant Account\" size=25 max=30>
      AMEX Asset Account: <input type=text name=\"amex_asset\" value=\"Amex Merchant Account\" size=25 max=30>
  Discover Asset Account: <input type=text name=\"disc_asset\" value=\"Discover Merchant Account\" size=25 max=30>
     Other Asset Account: <input type=text name=\"other_asset\" value=\"Other Merchant Account\" size=25 max=30>
          Income Account: <input type=text name=\"income_acct\" value=\"Web Site Sales\" size=25 max=30>
  Merchant Acct Expenses: <input type=text name=\"expense_acct\" value=\"Merchant Account Charges\" size=25 max=30>
          Sales Tax Acct: <input type=text name=\"tax_acct\" value=\"Sales Tax Payable\">
<br>
      Visa Discount Rate: <input type=text name=\"visa_rate\" value=\"0.025\" size=5 max=6>
MasterCard Discount Rate: <input type=text name=\"mast_rate\" value=\"0.025\" size=5 max=6>
      AMEX Discount Rate: <input type=text name=\"amex_rate\" value=\"0.0375\" size=5 max=6>
  Discover Discount Rate: <input type=text name=\"disc_rate\" value=\"0.025\" size=5 max=6>
     Other Discount Rate: <input type=text name=\"other_rate\" value=\"0.025\" size=5 max=6>

Start Date:
<select name=\"start_month\"> <option value=\"01\" selected> Jan
<option value=\"02\"> Feb
<option value=\"03\"> Mar
<option value=\"04\"> Apr
<option value=\"05\"> May
<option value=\"06\"> Jun
<option value=\"07\"> Jul
<option value=\"08\"> Aug
<option value=\"09\"> Sep
<option value=\"10\"> Oct
<option value=\"11\"> Nov
<option value=\"12\"> Dec
</select> <select name=\"start_day\"> 

EOF

  for($i=1; $i<=9; $i++) {
    print "<option value=\"0$i\" selected> $i\n";
  }
  for($i=10; $i<=31; $i++) {
    print "<option value=\"$i\" selected> $i\n";
  }
  print "</select> ";
  print <<EOF;
<select name=\"start_year\"><option value=\"1997\" selected> 1997
<option  value=\"1998\"> 1998
</select>
<br>
<option value=\"03\"> Mar
<option value=\"04\"> Apr
<option value=\"05\"> May
<option value=\"06\"> Jun
<option value=\"07\"> Jul
<option value=\"08\"> Aug
<option value=\"09\"> Sep
<option value=\"10\"> Oct
<option value=\"11\"> Nov
<option value=\"12\"> Dec
</select> <select name=\"end_day\"> 
EOF

  for($i=1; $i<=9; $i++) {
    print "<option value=\"0$i\" selected> $i\n";
  }
  for($i=10; $i<=31; $i++) {
    print "<option value=\"$i\" selected> $i\n";
  }
  print "</select> ";

  print <<EOF;
<select name=\"end_year\"><option value=\"1997\" selected> 1997
<option  value=\"1998\"> 1998
</select>  </pre><br>
EOF

  print "<input type=hidden name=\"publisher-name\" value=\"$username\">\n";

  print <<EOF;
<input type=hidden name=\"mode\" value=\"calculate\">
<div align=center><center>
<input TYPE=submit VALUE=\"Create Import Files\"> <INPUT TYPE=reset VALUE=\"Reset Form\">
</center></div>
EOF
  &report_tail();
}

sub discount_rate{
  my ($card_type) = @_;
  if ($hour_delta > $hours_non{$card_type}){
    $qual = $rate{$card_type} - $non{$card_type};
  }
  elsif ($hour_delta > $hours_mid{$card_type}){
    $qual = $rate{$card_type} - $mid{$card_type};
  }
  else {
    $qual = 0;
  }
  return $qual;
}

sub sum_charges { ###  Possible Obsolete
  my (%input) = @_;
  my($i,$qual,$sale);
  $i = $i + 1;
  $qual = 0;
  $qual = &discount_rate($input{'card_type'});
  $sale = substr($input{'amount'},4);
  $total{"$input{'card_type'}"} =  $total{"$input{'card_type'}"} + $sale;
  $total{"$input{'card_type'}c"} = $total{"$input{'card_type'}c"} + ($sale * ($visa_rate + $qual));
}

sub sum_returns {  ###  Possible Obsolete
  my (%input) = @_;
  my $return = substr($input{'amount'},4);
  $total{"$input{'card_type'}r"} =   $total{"$input{'card_type'}r"} + $return;
  $total{"$input{'card_type'}rc"} =   $total{"$input{'card_type'}rc"} + ($return * $rate{$input{'card_type'}});
  return %total;
}

sub transauth_date {
  %txnresult = &miscutils::sendmserver('query',
    'txn-type', "auth",
    'order-id', "$order_id");
  $_ = $txnresult{'a1'};

  foreach my $pair (split('&')) {
    if ($pair =~ /(.*)=(.*)/){ 
      ($key,$value) = ($1,$2);  
      $value =~ s/\+/ /g; 
      $txn{$key} = $value;
    }
  }
  $date{$order_id} = substr($txn{'time'},0,8);
  $hour{$order_id} = substr($txn{'time'},8,2);
}

sub logfilter_in {
  my ($key, $val) = @_;

  if ($key =~ /([3-7]\d{13,19})/) {
    $key =~ s/([3-7]\d{13,19})/&logfilter_sub($1)/ge;
  }

  if ($val =~ /([3-7]\d{12,19})/) {
    $val =~ s/([3-7]\d{13,19})/&logfilter_sub($1)/ge;
  }

  return ($key,$val);
}

sub logfilter_sub {
  my ($data) = @_;

  my $luhntest = &miscutils::luhn10($data);
  if ($luhntest eq "success") {
    $data =~ s/./X/g;
  }

  return $data;
}


