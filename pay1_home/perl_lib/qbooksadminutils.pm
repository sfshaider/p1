package qbooksadminutils;

require 5.001;

use CGI;
use DBI;
use miscutils;

sub new {
  my $type = shift;

  $query = new CGI;

  $month = &CGI::escapeHTML($query->param('month'));
  $year = &CGI::escapeHTML($query->param('year'));
  $billingflag = &CGI::escapeHTML($query->param('billing'));
  $function = &CGI::escapeHTML($query->param('function'));
  $username = &CGI::escapeHTML($ENV{'REMOTE_USER'});
  $dropdown = &CGI::escapeHTML($query->param('dropdown'));

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sth = $dbh->prepare(q{
      SELECT reseller, company
      FROM customers
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  ($reseller, $merch_company) = $sth->fetchrow;
  $sth->finish();
  $dbh->disconnect;

  ($sec,$min,$hour,$mday,$mon,$yyear,$wday,$yday,$isdst) = gmtime(time);
  $time = sprintf("%02d%02d%02d%02d%02d%05d",$yyear+1900,$mon+1,$mday,$hour,$min,$sec);
  $dday = $mday;
  $mmonth = $mon + 1;
  $yyear = $yyear + 1900;

  $now = sprintf("%04d%02d%02d",$yyear,$mmonth,$dday);
  %month_array = (1,"Jan",2,"Feb",3,"Mar",4,"Apr",5,"May",6,"Jun",7,"Jul",8,"Aug",9,"Sep",10,"Oct",11,"Nov",12,"Dec");
  %month_array2 = ("Jan","01","Feb","02","Mar","03","Apr","04","May","05","Jun","06","Jul","07","Aug","08","Sep","09","Oct","10","Nov","11","Dec","12");

  $yearmonth = $year . $month_array2{$month};
  $month_due = sprintf("%02d", substr($yearmonth,4,2) + 2);
  $billdate = $yearmonth . "31";

  ($sec,$min,$hour,$mday,$mon,$yyear,$wday,$yday,$isdst) = gmtime(time()+(24*3600));
  $dday = $mday;
  $mmonth = $mon + 1;
  $yyear = $yyear + 1900;
  $tomorrow = sprintf("%04d%02d%02d",$yyear,$mmonth,$dday);

  if (($ENV{'HTTP_COOKIE'} ne "")){
    (@cookies) = split(/\;/, $ENV{'HTTP_COOKIE'});
    foreach my $var (@cookies) {
      $var =~ /(.*?)=(.*)/;
      ($name,$value) = ($1,$2);
      #$name = &CGI::escapeHTML($name);
      #$value = &CGI::escapeHTML($value);
      $name =~ s/ //g;
      $cookie{"$name"} = $value;
    }
  }
  #$cookie{'pnpqbinvno'} = "1001";
  #$cookie{'pnpqbcsvno'} = "1200";
  ($cookie{'pnpqbend'},$cookie{'pnpqbcshacct'},$cookie{'pnpqbshpacct'},$cookie{'pnpqbtaxacct'},$cookie{'pnpqborderid'},$cookie{'pnpqbcshno'},$cookie{'pnpqbinvno'},$cookie{'pnpqbtaxitem'},$cookie{'pnpqbadjustmentitem'},$cookie{'tobeprinted'},$cookie{'exportcust'},$cookie{'showall'},$cookie{'format'},$cookie{'usecost'},$cookie{'add_recurring'},$cookie{'exclude_vt'}) = split(/\|/, $cookie{'pnpqbdata'});


  if ($cookie{'pnpqbinvno'} eq "") {
    $cookie{'pnpqbinvno'} = "1";
  }
  if ($cookie{'pnpqbcshno'} eq "") {
    $cookie{'pnpqbcshno'} = "1";
  }

  $dbh = &miscutils::dbhconnect("qbooks");

###   SKU's
  $sth = $dbh->prepare(q{
      SELECT sku,name
      FROM qbgroups
      WHERE username=?
      ORDER BY sku
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  while(my ($sku,$name) = $sth->fetchrow) {
    $qbgroups{$sku} = $name;
  }
  $sth->finish;

###  QBook Items
  my $sth_item = $dbh->prepare(q{
      SELECT name,description,acct,vendor,category
      FROM items
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth_item->execute("$username") or die "Can't execute: $DBI::errstr";
  while (my ($name,$description,$acct,$vendor,$category) = $sth_item->fetchrow) {
    $items{$name} = "$description";
  }
  $sth_item->finish;

### QBook Accounts
  my $sth_acct = $dbh->prepare(q{
      SELECT name,description
      FROM accounts
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth_acct->execute("$username") or die "Can't execute: $DBI::errstr";
  while (my ($name,$description) = $sth_acct->fetchrow) {
    $accounts{$name} = $description;
  }
  $sth_acct->finish;
  $dbh->disconnect;

### Perform Test to see if poper steps have been taken and enough data has been uploaded.
  if ($splidacct{'AcctRec'} eq "") {
    # Insert Test Here
  }

  return [], $type;
}


sub head {
  $i = 0;
  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<link href=\"/css/style_qbooks.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<title>QuickBooks Administration Area</title>\n";

  # js logout prompt
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery_ui/jquery-ui.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery_cookie.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/_js/admin/autologout.js\"></script>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/javascript/jquery_ui/jquery-ui.css\">\n";

  print "<script type='text/javascript'>\n";
  print "/** Run with defaults **/\n";
  print "\$(document).ready(function(){\n";
  print "  \$(document).idleTimeout();\n";
  print "});\n";
  print "</script>\n";
  # end logout js

  print "<script type=\"text/javascript\">\n";
  print "//<!-- Start Script\n";

  print "function results() {\n";
  print "  resultsWindow = window.open('/payment/recurring/blank.html','results','menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300');\n";
  print "}\n";

  print "function invno() {\n";
  print "  if (document.qb_iif.SaleType[1].checked) {\n";
  print "    document.qb_iif.InvNo.value=$cookie{'pnpqbinvno'}\;\n";
  print "  } else {\n";
  print "    document.qb_iif.InvNo.value=$cookie{'pnpqbcshno'}\;\n";
  print "  }\n";
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
  print "    <td colspan=2><h1><a href=\"index.cgi\">QuickBooks\&\#153; Module Administration Area</a> - $merch_company</h1>\n";

  print "<table border=0 cellspacing=1 cellpadding=0 width=600>\n";
}

sub iif {
    my @now = gmtime(time);
    my $current_year = $now[5]+1900;
    my $begin_year = $current_year - 3; # to comply with data storage policy)

    print  "<tr><td>&nbsp;</td><td><hr width=\"80%\"></td>\n";

    print  "<tr>\n";
    print  "<td class=\"menuleftside\">Generate<br>QBooks File</td>\n";
    print  "<td class=\"menurightside\">\n";

    print "<form method=post action=\"qbooks_admin.cgi\" name=\"qb_iif\">\n"; # /qbooks.iif
    print "<input type=hidden name=\"function\" value=\"iif\">\n";

    print "<table border=0 cellspacing=0 cellpadding=4>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Start Date (required):</td>\n";
    print "    <td><select name=\"startmon\">\n";
    print "<option value=\"\">Month</option>\n";
    @months = ("01","02","03","04","05","06","07","08","09","10","11","12");
    foreach my $var (@months) {
      if ($var eq substr($cookie{'pnpqbend'},4,2)) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select> ";
    print "<select name=\"startday\">\n";
    print "<option value=\"\">Day</option>\n";
    @days = ("01","02","03","04","05","06","07","08","09","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24","25","26","27","28","29","30","31");
    foreach my $var (@days) {
      if ($var eq substr($cookie{'pnpqbend'},6,2)) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select> ";
    print "<select name=\"startyear\">\n";
    print "<option value=\"\">Year</option>\n";
    #print "<option value=\"1999\">1999</option>\n";
    #@years = ("2005","2006","2007","2008","2009","2010");
    @years = ();
    for (my $i = $begin_year; $i <= $current_year; $i++) {
      push(@years, $i);
    }
    foreach my $var (@years) {
      if ($var eq substr($cookie{'pnpqbend'},0,4)) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">End Date (required):</td><td>\n";

    print "<select name=\"endmon\">\n";
    print "<option value=\"\">Month</option>\n";
    foreach my $var (@months) {
      if ($var eq substr($tomorrow,4,2)) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select> ";
    print "<select name=\"endday\">\n";
    print "<option value=\"\">Day</option>\n";
    foreach my $var (@days) {
      if ($var eq substr($tomorrow,6,2)) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select> ";
    print "<select name=\"endyear\">\n";
    print "<option value=\"\">Year</option>\n";
    foreach my $var (@years) {
      if ($var eq substr($tomorrow,0,4)) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select>\n";
    print "</td></tr>\n";

  print<<EOF;

  <tr>
    <td class="leftside">Type of Sale:</td>
    <td><input type=radio name="SaleType" value="CASH SALE" checked onClick="invno();"> Cash Sale
      <input type=radio name="SaleType" value="INVOICE" onClick="invno();"> Invoice</td>
  </tr>

  <tr>
    <td class="leftside">Deposit To Account:
      <br><font size="1">For Cash Sale Only</font></td>
    <td><select name="depositacct">
EOF
%selected = ();
if ($cookie{'pnpqbcshacct'} eq "") {
  $selected{'Undeposited Funds'} = "selected";
}
else {
  $selected{"$cookie{'pnpqbcshacct'}"} = "selected";
}
foreach my $name (sort keys %accounts) {
  print "<option value=\"$name\" $selected{$name}>$name - $accounts{$name}</option>\n";
}
print <<EOF;
</select></td>
  </tr>

  <tr>
    <td class="leftside">Shipping Account:</td>
    <td><select name="shippingacct">
EOF
%selected = ();
if ($cookie{'pnpqbshpacct'} eq "") {
  $selected{'Shipping'} = "selected";
}
else {
  $selected{"$cookie{'pnpqbshpacct'}"} = "selected";
}
foreach my $name (sort keys %accounts) {
  print "<option value=\"$name\" $selected{$name}>$name - $accounts{$name}</option>\n";
}
print <<EOF;
</select></td>
  </tr>

  <tr>
    <td class="leftside">Sales Tax Account:</td>
    <td><select name="salestaxacct">
EOF
%selected = ();
if ($cookie{'pnpqbtaxacct'} eq "") {
  $selected{'Sales Tax'} = "selected";
}
else {
  $selected{"$cookie{'pnpqbtaxacct'}"} = "selected";
}
foreach my $name (sort keys %accounts) {
  print "<option value=\"$name\" $selected{$name}>$name - $accounts{$name}</option>\n";
}
print <<EOF;
</select></td>
  </tr>

  <tr>
    <td class="leftside">Sales Tax Item:</td>
    <td><select name="salestaxitem">
EOF
%selected = ();
if ($cookie{'pnpqbtaxitem'} eq "") {
  $selected{'Sales Tax'} = "selected";
}
else {
  $selected{"$cookie{'pnpqbtaxitem'}"} = "selected";
}
foreach my $name (sort keys %items) {
  print "<option value=\"$name\" $selected{$name}>$name - $items{$name}</option>\n";
}
print <<EOF;
</select></td>
  </tr>

  <tr>
    <td class="leftside">Adjustment Item:</td>
    <td><select name="adjustmentitem">
EOF
%selected = ();
if ($cookie{'pnpqbadjustmentitem'} eq "") {
  $selected{'Discount'} = "selected";
}
else {
  $selected{"$cookie{'pnpqbadjustmentitem'}"} = "selected";
}
foreach my $name (sort keys %items) {
  print "<option value=\"$name\" $selected{$name}>$name - $items{$name}</option>\n";
}

%selected = ();
if (($cookie{'tobeprinted'} eq 'Y') || (($cookie{'tobeprinted'} eq "") && (!defined $cookie{'tobeprinted'}))) {
  $selected{'tobeprinted'} = " checked";
}

if (($cookie{'showall'} eq 'yes') || ($cookie{'showall'} eq "")) {
  $selected{'yesshowall'} = "checked";
}
else {
  $selected{'noshowall'} = "checked";
}

if (($cookie{'exportcust'} eq 'yes')) {
  $selected{'exportcust'} = "checked";
}

if (($cookie{'usecost'} eq 'yes')) {
  $selected{'usecost'} = "checked";
}

if (($cookie{'format'} eq 'display') || ($cookie{'format'} eq "")) {
  $selected{'displayformat'} = "checked";
}
else {
  $selected{'dwnldformat'} = "checked";
}

print <<EOF;
</select></td>
  </tr>

  <tr>
    <td class="leftside">Memo:</td>
    <td><input type=text size=23 name="Memo" value=""></td>
  </tr>
  <tr>
    <td class="leftside">Beg. Invoice No:</td>
    <td><input type=text size=6 name="InvNo" value="$cookie{'pnpqbcshno'}"></td>
  </tr>

  <tr>
    <td class="leftside">Misc. Options:</td>
    <td><input type=checkbox name="tobeprinted" value="Y" $selected{'tobeprinted'}> Mark Invoices/Receipts for Printing
      <input type=checkbox name="exportcust" value="yes" $selected{'exportcust'}> Include Customer Data in Export</td>
  </tr>

  <tr>
    <td class="leftside">Which Records:</td>
    <td><input type=radio name="showall" value="yes" $selected{'yesshowall'}> Get All Records
      <input type=radio name="showall" value="no" $selected{'noshowall'}> Get Records Since Last Download.</td>
  </tr>

  <tr>
    <td class="leftside">Record Types:</td>
    <td><input type=checkbox name="srchstatus" value="settled"> Check for settled orders only.</td>
  </tr>

<!--
  <tr bgcolor="#C0C0C0">
    <td colspan=2 align="left">Search Criteria - <font size=2>Optional</font></td>
  </tr>
  <tr bgcolor="#C0C0C0">
    <td align="left">Order ID:</td>
    <td><input type=text size=23 name="srchorderid"></td>
  </tr>
  <tr bgcolor="#C0C0C0">
    <td align="left">MOrder ID:</td>
    <td><input type=text size=23 name="srchmorderid"></td>
  </tr>
  <tr bgcolor="#C0C0C0">
    <td align="left">Model/Item Number:</td>
    <td><select name="srchmodel">
<option value="">None</option>
EOF
  foreach my $sku (sort keys %splidacct) {
    print "<option value=$sku>$sku</option>\n";
  }
  print <<EOF;
    </td>
  </tr>

  <tr bgcolor="#C0C0C0">
    <td align="left">Name:</td>
    <td><input type=text size=32 name="srchname"></td>
  </tr>

  <tr bgcolor="#C0C0C0">
    <td align="left">Acct Code:</td>
    <td><input type=text name="srchacctcode"></td>
  </tr>

  <tr>
    <td class="leftside">Accts Receivable:</td>
    <td><input type=text size=23 name="AcctRec" value="$splidacct{'AcctRec'}"></td>
  </tr>

  <tr>
    <td class="leftside">Sales Tax:</td>
    <td><input type=text size=23 name="SalesTax" value="$splidacct{'SalesTax'}"></td>
  </tr>
-->

  <tr>
    <td class="leftside">Output Type:</td>
    <td><input type=radio name="format" value="download" $selected{'dwnldformat'}> Download <input type=radio name="format" value="display" $selected{'displayformat'}> Display</td>
  </tr>

  <tr>
    <td class="leftside">Report Type:</td>
    <td><input type=radio name="report" value="sales" checked> Sales Only
      <!--<input type=radio name="report" value="bank"> Bank-->
      <!--<input type=radio name="report" value="both"> Both-->
      </td>
  </tr>
EOF

  print "  <tr>\n";
  print "    <td class=\"leftside\">Include Recurring:</td>\n";
  print "    <td><input type=checkbox name=\"add_recurring\" value=\"yes\"";
  if ($cookie{'add_recurring'} =~ /yes/i) { print " checked"; }
  print "> Include Recurring Billing Charges</td>\n";
  print "</tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside\">Exclude Virtual Terminal:</td>\n";
  print "    <td><input type=checkbox name=\"exclude_vt\" value=\"yes\"";
  if ($cookie{'exclude_vt'} =~ /yes/i) { print " checked"; }
  print "> Exclude Virtual Terminal Charges</td>\n";
  print "  </tr>\n";

print <<EOF;
  <tr>
    <td class="leftside">Name Format:</td>
    <td><input type=checkbox name="nameformat" value="lastfirst"> Check to have customer name formatted as \"LASTNAME, FIRSTNAME\"</td>
  </tr>
EOF

#  if ($ENV{'REMOTE_USR'} =~ /^insite/) {
  print <<EOF;
  <tr>
    <td class="leftside">Cost Data:</td>
    <td><input type=checkbox name="usecost" value="yes" $selected{'usecost'}> Use Submitted Cost Data, NOT imported Cost Data</td>
  </tr>
  <tr>
    <td class="leftside">Long Item Names:</td>
    <td><input type=checkbox name="longitem" value="yes"> Do not truncate long item names.</td>
  </tr>
  <tr>
    <td class="leftside">QBooks Version 2003/2004:</td>
    <td><input type=checkbox name="qb2003" value="yes"> Check if using QBooks Version 2003/2004 or experience import problems related to Sales Tax.</td>
  </tr>
  <tr>
    <td class="leftside">Payment Method:</td>
    <td><input type=checkbox name="inc_paymethod" value="yes"> Check if you wish to include Payment Method in file. (BETA)</td>
  </tr>
EOF
#  }

  print <<EOF;
  <tr>
    <td class="leftside"> &nbsp; </td>
    <td><input type=submit name="submit" value="Get Report"></td>
  </tr>
</table>
</form>
</td></tr>
EOF

}

sub bank_iif {
    my @now = gmtime(time);
    my $current_year = $now[5]+1900;
    my $begin_year = $current_year - 3; # to comply with data storage policy

    print  "<tr><td>&nbsp;</td><td><hr width=\"80%\"></td>\n";

    print  "<tr>\n";
    print  "<td class=\"menuleftside\">Generate<br>QBooks File</td>\n";
    print  "<td class=\"menurightside\">\n";

    print "<form method=post action=\"qbooks_admin.cgi\">\n"; # /qbooks.iif
    print "<input type=hidden name=\"function\" value=\"iif\">\n";
    print "<table border=0 cellspacing=0 cellpadding=4>\n";
    print "<tr><td class=\"leftside\">Start Date (required):</td><td>\n";

    print "<select name=\"startmon\">\n";
    print "<option value=\"\">Month</option>\n";
    @months = ("01","02","03","04","05","06","07","08","09","10","11","12");
    foreach my $var (@months) {
      if ($var eq $data{'startmon'}) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select> ";
#    print "<td align=left>\n";
    print "<select name=\"startday\">\n";
    print "<option value=\"\">Day</option>\n";
    @days = ("01","02","03","04","05","06","07","08","09","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24","25","26","27","28","29","30","31");
    foreach my $var (@days) {
      if ($var eq $data{'startdays'}) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select> ";
    print "<select name=\"startyear\">\n";
    print "<option value=\"\">Year</option>\n";
    print "<option value=\"1999\">1999</option>\n";
    #@years = ("2005","2006","2007","2008","2009","2010");
    @years = ();
    for (my $i = $begin_year; $i <= $current_year; $i++) {
      push(@years, $i);
    }
    foreach my $var (@years) {
      if ($var eq $data{'startyear'}) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select>\n";
    print "</td></tr>\n";
    print "<tr><td class=\"leftside\">End Date (required):</td><td>\n";

    print "<select name=\"endmon\">\n";
    print "<option value=\"\">Month</option>\n";
    foreach my $var (@months) {
      if ($var eq $data{'endmon'}) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select> ";
#    print "<td align=left>\n";
    print "<select name=\"endday\">\n";
    print "<option value=\"\">Day</option>\n";
    foreach my $var (@days) {
      if ($var eq $data{'enddays'}) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select> ";
    print "<select name=\"endyear\">\n";
    print "<option value=\"\">Year</option>\n";
    foreach my $var (@years) {
      if ($var eq $data{'endyear'}) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select>\n";
    print "</td></tr>\n";
#    print "</table></td></tr>\n";

  print<<EOF;

<tr><td class="leftside">Type of Sale:</td><td><input type=radio name="SaleType" value="CASH SALE" checked> Cash <input type=radio name="SaleType" value="INVOICE"> Invoice</td></tr>
<tr><td class="leftside">Memo:</td><td><input type=text size=23 name="Memo" value=""></td></tr>
<tr><td class="leftside">Beg. Invoice No:</td><td><input type=text size=6 name="InvNo"></td></tr>

<tr><td class="leftside" colspan=2>Search Criteria - <font size="-1">Optional</font></td></tr>
<tr><td class="leftside">Order ID:</td><td><input type=text size=23 name="srchorderid"></td>
<tr><td class="leftside">MOrder ID:</td><td><input type=text size=23 name="srchmorderid"></td>
<tr><td class="leftside">Model/Item Number:</td><td><select name="srchmodel">
<option value="">None</option>
EOF
  foreach my $sku (sort keys %splidacct) {
    print "<option value=$sku>$sku</option>\n";
  }
  print <<EOF;
<tr><td class="leftside">Name:</td><td><input type=text size=32 name="srchname"></td>
<tr><td class="leftside">Acct Code:</td><td><input type=text name="srchacctcode"></td>

<!--<tr><td class="leftside">Accts Receivable:</td><td><input type=text size=23 name="AcctRec" value="$splidacct{'AcctRec'}"></td></tr>
<tr><td class="leftside">Sales Tax:</td><td><input type=text size=23 name="SalesTax" value="$splidacct{'SalesTax'}"></td></tr>-->

<tr><td class="leftside">Output Type:</td><td><input type=radio name="format" value="download"> Download <input type=radio name="format" value="display" checked> Display</td></tr>

<tr><td class="leftside">Report Type:</td><td><input type=radio name="report" value="sales" checked> Sales Only <input type=radio name="report" value="bank"> Bank <input type=radio name="report" value="both"> Both</td></tr>

<tr><td class="leftside">Get Report:</td><td>
<input type=submit name="submit" value="Get Report"></td></tr>
</table>
</form>
</td></tr>

<tr><th colspan=2>Bank Reconciliation  Information- <font size="-1">Optional</font></th></tr>
<tr><td class="leftside">Visa Discount Rate:</td><td> <input type=text name=\"visa_rate\" value=\"0.025\" size=5 max=6></td></tr>
<tr><td class="leftside">MasterCard Discount Rate:</td><td> <input type=text name=\"mast_rate\" value=\"0.025\" size=5 max=6></td></tr>
<tr><td class="leftside">AMEX Discount Rate:</td><td> <input type=text name=\"amex_rate\" value=\"0.0375\" size=5 max=6></td></tr>
<tr><td class="leftside">Discover Discount Rate:</td><td> <input type=text name=\"disc_rate\" value=\"0.025\" size=5 max=6></td></tr>
<tr><td class="leftside">Other Discount Rate:</td><td> <input type=text name=\"other_rate\" value=\"0.025\" size=5 max=6></td></tr>
EOF

}

sub droplist {
  print "<tr><td>&nbsp;</td><td><hr width=\"80%\"></td>\n";
  print  "<tr>\n";
  print  "<td class=\"menuleftside\">Sales SKU's</td>\n";
  print  "<td class=\"menurightside\"><form method=post action=\"qbooks_admin.cgi\">\n";
  print  "<select name=\"sku\">\n";
  foreach my $sku (sort keys %qbgroups) {
    print "<option value=\"$sku\">$sku - $qbgroups{$sku}</option>\n";
  }
  print "</select><br>\n";
  print "<input type=hidden name=\"function\" value=\"view_group\">\n";
  print "<pre><input type=submit name=\"submit\" value=\"   Edit SKU List   \"></pre></form></td></tr>\n";

  print "<tr><td>&nbsp;</td><td><hr width=\"80%\"></td>\n";
  print  "<tr>\n";
  print  "<td class=\"menuleftside\">QBook Items</td>\n";
  print  "<td class=\"menurightside\"><form method=post action=\"qbooks_admin.cgi\">\n";
  print  "<select name=\"name\">\n";
  foreach my $name (sort keys %items) {
    print "<option value=\"$name\">$name - $items{$name}</option>\n";
  }
  print "</select><br>\n";
  print "<input type=hidden name=\"function\" value=\"view_item\">\n";
  print "<pre><input type=submit name=\"submit\" value=\"   Edit QBook Items   \"></pre></form></td></tr>\n";

  print "<tr><td>&nbsp;</td><td><hr width=\"80%\"></td>\n";
  print  "<tr>\n";
  print  "<td class=\"menuleftside\">QBook Accounts</td>\n";
  print  "<td class=\"menurightside\"><font size=\"-1\"><form method=post action=\"qbooks_admin.cgi\">\n";
  print  "<select name=\"name\">\n";
  foreach my $name (sort keys %accounts) {
    print "<option value=\"$name\">$name - $accounts{$name}</option>\n";
  }
  print "</select><br>\n";
  print "<input type=hidden name=\"function\" value=\"view_account\">\n";
  print "<pre><input type=submit name=\"submit\" value=\"   Edit Accounts   \"></pre></form></font></td></tr>\n";

}

sub search {
  print "<tr><td>&nbsp;</td><td><hr width=\"80%\"></td>\n";
  print "<tr>\n";
  print "<td class=\"menuleftside\">Search</td>\n";
  print "<td class=\"menurightside\"><br>\n";
  print "<form method=post action=\"qbooks_admin.cgi\">\n";
  print "<table>\n";
  print "<tr><td class=\"leftside\">SKU:</td><td><input type=text name=\"srch_sku\" size=20></td></tr>\n";
  print "<tr><td class=\"leftside\">Account:</td><td><input type=text name=\"srch_acct\" size=10></td></tr>\n";
  print "<tr><td class=\"leftside\">Exact Match:</td><td><input type=checkbox name=\"search-exact\" value=\"yes\"></td></tr>\n";
  print "</table>\n";
  print "<input type=hidden name=\"function\" value=\"search\">\n";
  print "<input type=submit name=\"submit\" value=\"Search Account Database\"> <input type=reset value=\"Reset Search Fields\"></form>\n";
  print "</td></tr>\n";
}

sub addnew {
  print "<tr><td>&nbsp;</td><td><hr width=\"80%\"></td>\n";
  print "<tr><td class=\"menuleftside\">Add</td>\n";
  print "<td class=\"menurightside\">\n";
  print "<form method=post action=\"qbooks_admin.cgi\">\n";
  print "<table>\n";
  print "<tr><td class=\"leftside\">Sales SKU:</td><td><input type=text name=\"sku\" size=20 max=20></td></tr>\n";
  print "<tr><td colspan=2><input type=hidden name=\"function\" value=\"add_group\">\n";
  print "<input type=submit value=\"      Add New SKU      \"></td></tr></table>\n";
  print "</form>\n";
  print "</td></tr>\n";
}


sub import_data {

print <<EOF;
<tr>
<td>&nbsp;</td>
<td><hr width=80%></td>

<tr>
<td class="menuleftside">Import<br>QBooks Data</td>
<td class="menurightside">
<form method=post enctype="multipart/form-data" action="qbooks_admin.cgi" target="newWin">
<table>
<tr><td class=\"leftside\">File:</td><td> <input type=file name="flname"></td></tr>
<tr><td colspan="2" align="left"><input type=hidden name="function" value="import">
<input type=submit name=submit value=\"Upload QBooks Data\"></td></tr></table>
</form>
</td>

EOF
}

sub delete_data {

print <<EOF;
<tr>
<td>&nbsp;</td>
<td><hr width=80%></td>

<tr>
<td class="menuleftside">Delete<br>QBooks Data</td>
<td class="menurightside">
<form method=post action="qbooks_admin.cgi">
<table>
<tr><td colspan="2" align="left">
<input type=radio name="function" value="delete_all_items">  Delete Item List <br>
<input type=radio name="function" value="delete_all_groups">  Delete SKU List <br>
<input type=radio name="function" value="delete_all_accounts">  Delete Account List <br>
<input type=submit name=submit value=\"Delete QBooks Data\"></td></tr>
</table>
</form>
</td>

EOF
}

sub export {
print <<EOF;
<tr>
<td>&nbsp;</td>
<td><hr width=80%></td>

<tr>
<td class="menuleftside">Export<br>Database</td>
<td class="menurightside">FTP Host Login Information
<form method=post action=\"qbooks_admin.cgi\">
<table>
<tr><td class=\"leftside\">Username:</td><td> <input type=text name="FTPun" size=10 max=15></td></tr>
<tr><td class=\"leftside\">Password:</td><td> <input type=password name="FTPpw" size=10 max=15></td></tr>
<tr><td class=\"leftside\" colspan=2>Destination of Uploaded File:</td></tr>
<tr><td class=\"leftside\">File Directory:</td><td> <input type=text name="remotedir" value="database" size=30 max=50></td></tr>
<tr><td class=\"leftside\">File Name:</td><td> <input type=text name="destfile" value="account.txt" size=30 max=30></td></tr>
<tr><td class=\"leftside\" colspan=2><input type=hidden name="function" value="export">
<input type=submit name=submit value=\"Export & Upload Account Database\"></td></tr>
</table>
</form>
</td></tr>
EOF
}

sub helpdesk {
  print  "<tr><td>&nbsp;</td><td><hr width=\"80%\"></td>\n";
  print  "<tr><td class=\"menuleftside\">Help Desk</td>\n";
  print  "<td><form method=\"post\" action=\"helpdesk.cgi\" target=\"ahelpdesk\">\n";
  print  "<input type=submit name=\"submit\" value=\"Help Desk\" onClick=\"window.open('','ahelpdesk','width=550,height=520,toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes');return(true);\">\n";
  print  "</form>\n";
  print  "</td></tr>\n";
}

sub documentation {
  print  "<tr><td>&nbsp;</td><td><hr width=\"80%\"></td>\n";
  print  "<tr><td class=\"menuleftside\">Help</td>\n";
  print  "<td class=\"menurightside\"><a href=\"/new_docs/QuickBooks_Module.htm\" target=\"helpWin\">Documentation</a>\n";
  print  "</td></tr>\n";
}


sub tail {
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
