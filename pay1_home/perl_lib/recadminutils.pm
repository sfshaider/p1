package recadminutils;

$| = 1;

use CGI;
use DBI;
use miscutils;
use PlugNPay::Util::CardFilter;

sub new {
  my $type = shift;
  ($merchant) = @_;

  $query = new CGI;

  $month = &CGI::escapeHTML( $query->param('month') );
  $month =~ s/[^a-zA-Z0-9]//g;

  $year = &CGI::escapeHTML( $query->param('year') );
  $year =~ s/[^0-9]//g;

  $billingflag = &CGI::escapeHTML( $query->param('billing') );
  $billingflag =~ s/[^a-zA-Z0-9\_\-]//g;

  $function = &CGI::escapeHTML( $query->param('function') );
  $function =~ s/[^a-zA-Z0-9\_\-]//g;

  $username = &CGI::escapeHTML( $query->param('username') );
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $dropdown = &CGI::escapeHTML( $query->param('dropdown') );
  $dropdown =~ s/[^a-zA-Z0-9\_\-]//g;

  ( $sec, $min, $hour, $mday, $mon, $yyear, $wday, $yday, $isdst ) = gmtime(time);
  $time   = sprintf( "%02d%02d%02d%02d%02d%05d", $yyear + 1900, $mon + 1, $mday, $hour, $min, $sec );
  $dday   = $mday;
  $mmonth = $mon + 1;
  $yyear  = $yyear + 1900;

  $now          = sprintf( "%04d%02d%02d", $yyear, $mmonth, $dday );
  $today        = $now;
  %month_array  = ( 1, 'Jan', 2, 'Feb', 3, 'Mar', 4, 'Apr', 5, 'May', 6, 'Jun', 7, 'Jul', 8, 'Aug', 9, 'Sep', 10, 'Oct', 11, 'Nov', 12, 'Dec' );
  %month_array2 = ( 'Jan', '01', 'Feb', '02', 'Mar', '03', 'Apr', '04', 'May', '05', 'Jun', '06', 'Jul', '07', 'Aug', '08', 'Sep', '09', 'Oct', '10', 'Nov', '11', 'Dec', '12' );

  $yearmonth = $year . $month_array2{$month};
  $month_due = sprintf( "%02d", substr( $yearmonth, 4, 2 ) + 2 );
  $billdate  = $yearmonth . "31";

  my $dbh  = &miscutils::dbhconnect('pnpmisc');
  my $sth1 = $dbh->prepare(
    q{
      SELECT installbilling,membership,submit_date
      FROM pnpsetups
      WHERE username=?
    }
  );
  $sth1->execute("$merchant");
  ( $installbilling, $membership, $submit_date ) = $sth1->fetchrow;
  $sth1->finish;

  my $sth2 = $dbh->prepare(
    q{
      SELECT reseller, company
      FROM customers
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth2->execute("$merchant") or die "Can't execute: $DBI::errstr";
  ( $reseller, $merch_company ) = $sth2->fetchrow;
  $sth2->finish;

  $sth_merchants = $dbh->prepare(
    q{
      SELECT admindomain
      FROM privatelabel
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_merchants->execute("$reseller") or die "Can't execute: $DBI::errstr";
  ($admindomain) = $sth_merchants->fetchrow;
  $sth_merchants->finish;

  if ( $admindomain eq '' ) {
    $admindomain = 'pay1.plugnpay.com';
  }

  $recurr_billonly = 'no';
  if ( ( $membership ne 'membership' ) && ( $submit_date >= 20050101 ) ) {
    $recurr_billonly = 'yes';
  }

  return [], $type;
}

sub head {
  $i = 0;

  #$showcnt = 'no';
  if ( $showcnt ne 'no' ) {

    my $dbh = &miscutils::dbhconnect("$merchant");

    # calculate number of members requested to be 'cancelled'
    my $sth1 = $dbh->prepare(
      q{
        SELECT COUNT(username)
        FROM customer
        WHERE enddate>?
        AND status=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth1->execute( $today, 'cancelled' ) or die "Can't execute: $DBI::errstr";
    ($cancelcnt) = $sth1->fetchrow;
    $sth1->finish;

    # calculate number of currently 'pending' members
    my $sth2 = $dbh->prepare(
      q{
        SELECT COUNT(username)
        FROM customer
        WHERE enddate>?
        AND status=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth2->execute( $today, 'pending' ) or die "Can't execute: $DBI::errstr";
    ($opencnt) = $sth2->fetchrow;
    $sth2->finish;

    # calculate total number of 'active' members
    my $sth3 = $dbh->prepare(
      q{
        SELECT COUNT(username)
        FROM customer
        WHERE enddate>?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth3->execute($today) or die "Can't execute: $DBI::errstr";
    ($activecnt) = $sth3->fetchrow;
    $sth3->finish;

    # calculate total number of 'active & recurring' members
    my $sth4 = $dbh->prepare(
      q{
        SELECT COUNT(username)
        FROM customer
        WHERE enddate>?
        AND (status IS NULL or status='' OR status NOT IN ('cancelled','pending'))
        AND billcycle>?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth4->execute( $today, '0' ) or die "Can't execute: $DBI::errstr";
    ($recurrcnt) = $sth4->fetchrow;
    $sth4->finish;

    # calculate total number of 'expired' members
    my $sth5 = $dbh->prepare(
      q{
        SELECT COUNT(username)
        FROM customer
        WHERE enddate<?
        OR (enddate IS NULL or enddate ='')
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth5->execute($today) or die "Can't execute: $DBI::errstr";
    ($expcnt) = $sth5->fetchrow;
    $sth5->finish;

    # calculate 'renewal' members
    my $sth6 = $dbh->prepare(
      q{
        SELECT COUNT(username)
        FROM customer
        WHERE enddate>?
        AND status=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth6->execute( $today, 'renewal' ) or die "Can't execute: $DBI::errstr";
    ($renewal) = $sth6->fetchrow;
    $sth6->finish;

    # calculate number of members which have an unsure status (where enddate = today)
    my $sth7 = $dbh->prepare(
      q{
        SELECT COUNT(username)
        FROM customer
        WHERE enddate=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth7->execute($today) or die "Can't execute: $DBI::errstr";
    ($unsurecnt) = $sth7->fetchrow;
    $sth7->finish;
  }

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Membership Management Administration</title>\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/css/style_recurring.css\">\n";

  print "<script type=\"text/javascript\">\n";
  print "//<!-- Start Script\n";

  print "function results() \{\n";
  print "  resultsWindow = window.open('/payment/recurring/blank.html','results','menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300');\n";
  print "\}\n";

  print "function results1() \{\n";
  print "  resultsWindow = window.open('/payment/recurring/blank.html','results1','menubar=no,status=no,scrollbars=yes,resizable=yes,width=600,height=400');\n";
  print "\}\n";

  print "function onlinehelp(url) \{\n";
  print "  resultsWindow = window.open(url,'results','menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300');\n";
  print "\}\n";

  print "function change_win(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  # File Upload Filter - 08/12/01
  print "function check() {\n";
  print "  var ext = document.paymentplans.filename.value;\n";
  print "  ext = ext.substring(ext.length-3,ext.length);\n";
  print "  ext = ext.toLowerCase();\n";
  print "  if (ext != 'txt') {\n";
  print "    alert('Invalid File Type: You selected a .'+ext+' file; You may only upload .txt files!');\n";
  print "    return false;\n";
  print "  }\n";
  print "  else {\n";
  print "    return true;\n";
  print "  }\n";
  print "}\n";

  print "//-->\n";
  print "</script>\n";

  print "</head>\n";
  print "<body>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=3>";
  if ( $admindomain =~ /plugnpay\.com/i ) {
    print "<img src=\"/images/global_header_gfx.gif\" width=760 alt=\"Corporate Logo\" border=0>";
  } else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\" border=0>";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=3 align=left><img src=\"/images/header_bottom_bar_gfx.gif\" width=760 alt=\"\"  height=14></td>\n";
  print "  </tr>\n";

  print "  <tr bgcolor=\"#f4f4f4\">\n";
  if ( $showcnt ne 'no' ) {
    print "    <th colspan=3 align=left>Customer Database - Total Active: $activecnt [Recurring: $recurrcnt, Pending: $opencnt, Cancelled: $cancelcnt] Expired: $expcnt ";
    if ( $unsurecnt > 0 ) {
      $unsurecnt = sprintf( "%01d", $unsurecnt );
      print "Awaiting Status: $unsurecnt ";
    }
    if ( $renewal > 0 ) {
      print "Renewals: $renewal ";
    }
    print "</th>\n";
  } else {
    print "    <th colspan=3 align=left>Customer Database</th>\n";
  }
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=0 cellspacing=0 cellpadding=0 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=2 class=larger><h1><b><a href=\"index.cgi\">Membership Management Administration</a> - $merch_company</b></h1>";

  return;
}

sub custcnt {
  if ( $showcnt eq 'no' ) {
    print "<!-- start customer count section -->\n";
    print "  <tr>\n";
    print "    <td colspan=2><hr width=80%></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th valign=top align=left>Customer Count</th>\n";
    print "    <td align=left><form method=post action=\"editcust.cgi\" target=\"results\">\n";
    print "<input type=hidden name=\"function\" value=\"custcnt\">\n";
    print "<input type=submit class=button value=\"Customer Count\" onClick=\"results();\"></form></td>\n";
    print "  </tr>\n";
    print "<!-- end customer count section -->\n";
  }

  return;
}

sub droplist {
  print "<table>\n";

  if ( $dropdown eq 'yes' ) {
    my $cf = new PlugNPay::Util::CardFilter();

    print "<!-- start drop list section -->\n";
    print "  <tr>\n";
    print "    <th valign=top>Edit</th>\n";
    print "    <td align=left><form method=post action=\"editcust.cgi\">\n";
    print "<input type=hidden name=\"function\" value=\"viewrecord\">\n";
    print "<select name=\"username\">\n";
    if ( $droplist eq 'activeonly' ) {
      foreach my $username ( sort keys %name ) {
        $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
        $username = $cf->filterSingle( $username, 1 );
        print "<option value=\"$username\">$name{$username}</option>\n";
      }
    } else {
      my $dbh = &miscutils::dbhconnect("$merchant");
      my $sth = $dbh->prepare(
        q{
          SELECT username,name,status
          FROM customer
          ORDER BY name
        }
        )
        or die "Can't do: $DBI::errstr";
      $sth->execute or die "Can't execute: $DBI::errstr";
      while ( my ( $username, $name, $status ) = $sth->fetchrow ) {
        $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
        $username = $cf->filterSingle( $username, 1 );
        $name     = $cf->filterSingle( $name,     1 );
        if ( $name eq '' ) {
          print "<option value=\"$username\">[username: $username]</option>\n";
        } else {
          print "<option value=\"$username\">$name</option>\n";
        }
      }
      $sth->finish;
    }
    print "</select>\n";

    print "<input type=submit class=button value=\"Edit Customer Database\"></form></td>\n";
    print "  </tr>\n";
    print "<!-- end drop list section ->\n";
  } else {
    print "<!-- start show list section -->\n";
    print "  <tr>\n";
    print "    <th valign=top>Edit</th>\n";
    print "    <td align=left><form method=post action=\"index.cgi\">\n";
    print "<input type=hidden name=\"dropdown\" value=\"yes\">\n";
    print "<input type=submit class=button value=\"Show List\"></form></td>\n";
    print "  </tr>\n";
    print "<!-- end show list section -->\n";
  }

  return;
}

sub search {
  print "<!-- start search section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Search</th>\n";
  print "    <td align=left><form method=post action=\"editcust.cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"search\">\n";

  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td align=right>Name:</td>\n";
  print "    <td><input type=text name=\"srch_name\" size=20></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=right>Username:</td>\n";
  print "    <td><input type=text name=\"srch_username\" size=10></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=right>Password:</td>\n";
  print "    <td><input type=text name=\"srch_password\" size=10 autocomplete=\"off\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=right>Card Number:</td>\n";
  print "    <td><input type=text name=\"srch_cardnumber\" size=20 autocomplete=\"off\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=right>Email:</td>\n";
  print "    <td><input type=text name=\"srch_email\" size=20></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=right>OrderID:</td>\n";
  print "    <td><input type=text name=\"srch_orderid\" size=20></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=right>Address:</td>\n";
  print "    <td><input type=text name=\"srch_addr1\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=right>&nbsp;</td>\n";
  print "    <td><input type=text name=\"srch_addr2\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=right>City, State, Zip:</td>\n";
  print "    <td><input type=text name=\"srch_city\">, <input type=text name=\"srch_state\" size=2> <input type=text name=\"srch_zip\" size=10></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=right>PurchaseID:</td>\n";
  print "    <td><input type=text name=\"srch_purchaseid\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=right>Account Code:</td>\n";
  print "    <td><input type=text name=\"srch_acct_code\"></td>\n";
  print "  </tr>\n";

  foreach my $fieldname ( sort keys %searchlist ) {
    print "  <tr>\n";
    print "    <td align=right>$fieldname :</td>\n";
    print "    <td><input type=text name=\"$searchlist{$fieldname}\" size=20></td>\n";
    print "  </tr>\n";
  }
  print "  <tr>\n";
  print "    <td align=right>Status:</td>\n";
  print "    <td><input type=radio name=\"srch_status\" value=\"\" checked> Any Status\n";
  print "      <input type=radio name=\"srch_status\" value=\"pending\"> Pending\n";
  print "      <input type=radio name=\"srch_status\" value=\"cancelled\"> Cancelled\n";
  print "    </td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=right>Expired:</td>\n";
  print "    <td><input type=checkbox name=\"srch_expired\" value=\"yes\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=right>Exact Match:</td>\n";
  print "    <td><input type=checkbox name=\"srch_exact\" value=\"yes\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<input type=submit class=button value=\"Search Customer Database\"> <!--<input type=reset class=button value=\"Reset Search Fields\">--></form></td>\n";
  print "  </tr>\n";
  print "<!-- end search section -->\n";
  return;
}

sub fraud {
  print "<!-- start fraud section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Fraud<br>Database</th>\n";
  print "    <td align=left><form method=post action=\"editcust.cgi\" target=\"newwin\">\n";
  print "<input type=hidden name=\"function\" value=\"fraud\">\n";

  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td align=right>Credit Card \#:</td>\n";
  print "    <td><input type=text name=\"cardnumber\" size=16 maxlength=16 autocomplete=\"off\">\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Reason:</td>\n";
  print "    <td><select name=\"reason\">\n";
  print "<option value=\"Card Reported as Stolen\">Card Reported as Stolen</option>\n";
  print "<option value=\"Chargeback\">Chargeback</option>\n";
  print "</select></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<input type=submit class=button value=\"Add to Fraud Database\"></form></td>\n";
  print "  </tr>\n";
  print "<!-- end fraud section -->\n";

  return;
}

sub addnew {
  my $type = shift;
  my ($size) = @_;
  if ( $size < 15 ) {
    $size = 15;
  }

  print "<!-- start add new section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Add</th>\n";
  print "    <td align=left><form method=post action=\"editcust.cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"add\">\n";

  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td align=right>Username:</td>\n";
  print "    <td><input type=text name=\"username\" size=\"$size\" maxlength=19>\n";
  print "      <br>If not defined, one will be generated for you.</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<input type=submit class=button value=\"Add New Customer\"></form></td>\n";
  print "  </tr>\n";
  print "<!-- end add new section -->\n";

  return;
}

sub payplans {
  print "<!-- start payment plans section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Payment<br>Plans</th>\n";
  print "    <td align=left>";

  print "<form method=post name=\"paymentplans\" action=\"/payment/recurring/$merchant/admin/editcust.cgi\" enctype=\"multipart/form-data\" target=\"newWin\" onsubmit=\"return check();\">\n";
  print "<input type=hidden name=\"function\" value=\"update_payplans\">\n";
  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td align=right>File:</td>\n";
  print "    <td><input type=file name=\"filename\" value=\"File\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=2><input type=submit class=button value=\"Upload Payment Plans\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "</form>\n";

  print "<br><table border=0>\n";
  print "  <tr>\n";
  print "    <td colspan><form method=post action=\"/payment/recurring/$merchant/admin/editcust.cgi\" target=\"newWin\">\n";
  print "<input type=hidden name=\"function\" value=\"view_payplans\">\n";
  print "<input type=submit class=button value=\"View Current Payment Plans\"></form></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><form method=post action=\"/admin/wizards/payment_plans_wizard.cgi\">\n";
  print "<input type=hidden name=\"mode\" value=\"export\">\n";
  print "<input type=submit class=\"button\" value=\"Download Payment Plans\"></form></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><form method=post action=\"/admin/wizards/payment_plans_wizard.cgi\" target=\"wizard\">\n";
  print "<input type=submit class=button value=\"Payment Plans Wizard\"></form></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><form method=post action=\"/admin/wizards/joinpage_wizard.cgi\" target=\"wizard\">\n";
  print "<input type=submit class=button value=\"Join Page Wizard\"></form></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "    </td>\n";
  print "  </tr>\n";
  print "<!-- end payment plans section -->\n";

  return;
}

sub update {
  if ( $recurr_billonly ne 'yes' ) {
    print "<!-- start update section -->\n";
    print "  <tr>\n";
    print "    <td colspan=2><hr width=80%></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th valign=top>Update</th>\n";
    print "    <td align=left><b>FTP Host Login Information</b>\n";
    print "<br>&bull; Leave username/password blank to use FTP host login info on file.\n";

    print "<form method=post action=\"refresh.cgi\">\n";

    print "<table border=0>\n";
    print "  <tr>\n";
    print "    <td align=right>Username:</td>\n";
    print "    <td><input type=text name=\"FTPun\" size=10 maxlength=40 AUTOCOMPLETE=OFF></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>Password:</td>\n";
    print "    <td><input type=password name=\"FTPpw\" size=10 maxlength=40 AUTOCOMPLETE=OFF></td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "<input type=submit class=button value=\"Update Password Access Files\"></form></td>\n";
    print "  </tr>\n";
    print "<!-- end update section -->\n";
  }

  return;
}

sub ip_block {
  if ( $recurr_billonly ne 'yes' ) {
    print "<!-- start ip block section -->\n";
    print "  <tr>\n";
    print "    <td colspan=2><hr width=80%></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th valign=top>IP/Domain<br>Blocking</th>\n";
    print "    <td align=left>\n";

    print "<form method=post action=\"editcust.cgi\">\n";
    print "<input type=hidden name=\"function\" value=\"ip_block\">\n";

    print "<table border=0>\n";
    print "  <tr>\n";
    print "    <td align=right>IP/Domain:</td>\n";
    print "    <td><input type=text name=\"ip_address\" size=30></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td colspan=2><input type=radio name=\"mode\" value=\"add_ip\" checked> Add\n";
    print "      <input type=radio name=\"mode\" value=\"remove_ip\"> Remove</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td colspan=2>&bull; To unblock ALL IPs/domains, enter a '<font size=+1>*</font>' \& select the 'Remove' option,\n";
    print "<br>Then click the 'Update IP/Domain Block List' button.</td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "<input type=submit class=button value=\"Update IP/Domain Block List\"></form></td>\n";
    print "  </tr>\n";

    print "<form method=post action=\"editcust.cgi\">\n";
    print "<input type=hidden name=\"mode\" value=\"view_ip\"> ";
    print "<input type=hidden name=\"function\" value=\"ip_block\"> ";
    print "  <tr>\n";
    print "    <th valign=top>&nbsp;</th>\n";
    print "    <td align=left><input type=submit class=button value=\"View IP/Domain Block List\"></form></td>\n";
    print "  </tr>\n";

    print "<form method=post action=\"editcust.cgi\">\n";
    print "<input type=hidden name=\"mode\" value=\"rebuild_htaccess\"> ";
    print "<input type=hidden name=\"function\" value=\"ip_block\"> ";
    print "  <tr>\n";
    print "    <th valign=top>&nbsp;</th>\n";
    print "    <td align=left><input type=submit class=button value=\"Rebuild .htaccess Files\"></form></td>\n";
    print "  </tr>\n";

    print "</td>\n";
    print "  </tr>\n";
    print "<!-- end ip block section -->\n";
  }

  return;
}

sub web900 {
  print "<!-- start web900 section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "<form method=post action=\"/payment/recurring/$merchant/admin/editcust.cgi\" enctype=\"multipart/form-data\" target=\"results\">\n";
  print "<input type=hidden name=\"function\" value=\"web900\">\n";

  print "  <tr>\n";
  print "    <th valign=top>Web900</th>\n";
  print "    <td align=left>\n";

  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td align=right>Choose File:</td>\n";
  print "    <td><input type=file name=\"filename\" value=\"File\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Pin Cost no \$:</td>\n";
  print "    <td><input type=text name=\"pin-cost\" maxlength=6 size=6></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<input type=submit class=button value=\"Upload Pre-Paid PIN \#\'s\" onClick=\"results();\"></form></td>\n";
  print "  </tr>\n";
  print "<!-- end web900 section -->\n";

  return;
}

sub import_data1 {
  my ( $junk, $extracols ) = @_;

  print "<!-- start import user data section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Import</th>\n";
  print "    <td align=left>\n";

  print "<form method=post enctype=\"multipart/form-data\" action=\"editcust.cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"importusers\">\n";
  if ( $extracols ne '' ) {
    print "<input type=hidden name=\"extracols\" value=\"$extracols\">\n";
  }

  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td align=right>File:</td>\n";
  print "    <td><input type=file name=\"upload-file\"> <a href=\"javascript:onlinehelp('/online_help/MemberUploadFormat.html');\">Required Format</a></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2><input type=checkbox name=\"allow_update\" value=\"1\"> Check to allow update if record already exists.</td>\n";
  print "  </tr>\n";

  if ( $merchant eq 'fdc32tes' ) {
    print "  <tr>\n";
    print "    <td colspan=2><input type=checkbox name=\"proc_payments\" value=\"1\"> Check to process payments prior to import.</td>\n";
    print "  </tr>\n";
  }

  print "</table>\n";

  print "<input type=submit class=button value=\"Upload User Database\"></form></td>\n";
  print "  </tr>\n";
  print "<!-- end import user data section -->\n";

  return;
}

sub import_data {
  my ( $junk, $extracols ) = @_;

  print "<!-- start import user data section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Import</th>\n";
  print "    <td align=left>\n";

  print "<form method=post enctype=\"multipart/form-data\" action=\"editcust.cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"importusers\">\n";
  if ( $extracols ne '' ) {
    print "<input type=hidden name=\"extracols\" value=\"$extracols\">\n";
  }

  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td align=right>File:</td>\n";
  print "    <td><input type=file name=\"upload-file\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2><input type=checkbox name=\"sendemail\" value=\"yes\"> Check to send confirmation emails.</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<input type=submit class=button value=\"Upload User Database\"></form></td>\n";
  print "  </tr>\n";
  print "<!-- end import user data section -->\n";

  return;
}

sub export {
  my ( $junk, $extracols ) = @_;

  print "<!-- start database export section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "<tr>\n";
  print "  <th valign=top>Database<br>Export</th>\n";
  print "  <td align=left>\n";

  print "<form method=post action=\"editcust.cgi\" target=\"results\">\n";
  print "<input type=hidden name=\"function\" value=\"transfer\">\n";
  print "<input type=hidden name=\"username\" value=\"export\">\n";

  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td align=right>Output Format:</td>\n";
  print "    <td><input type=radio name=\"format\" value=\"download\" checked> Download\n";
  if ( $recurr_billonly ne 'yes' ) {
    print "      <input type=radio name=\"format\" value=\"ftp\"> FTP";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Data Delimiter:</td>\n";
  print "    <td><input type=radio name=\"delimiter_type\" value=\"tab\" checked> Tab\n";
  print "      <input type=radio name=\"delimiter_type\" value=\"comma\"> Quote/Comma</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Profile Standing:</td>\n";
  print "    <td><input type=radio name=\"acct_activity\" value=\"\" checked> All Profiles\n";
  print "      <input type=radio name=\"acct_activity\" value=\"active\"> Active Only\n";
  print "      <input type=radio name=\"acct_activity\" value=\"expired\"> Expired Only</td>\n";
  print "  </tr>\n";

  if ( $recurr_billonly ne 'yes' ) {
    print "  <tr>\n";
    print "    <td colspan=2><b>FTP Host Login Information:</b>\n";
    print "      <br>&bull; Leave username/password blank to use FTP host login info on file.\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>Username:</td>\n";
    print "    <td><input type=text name=\"FTPun\" size=10 maxlength=40 autocomplete=\"off\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>Password:</td>\n";
    print "    <td><input type=password name=\"FTPpw\" size=10 maxlength=40 autocomplete=\"off\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2><b>Destination of FTP File Upload:</b></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>File Directory:</td>\n";
    print "    <td><input type=text name=\"remotedir\" value=\"database\" size=30 maxlength=50></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>File Name:</td>\n";
    print "    <td><input type=text name=\"destfile\" value=\"memberinfo.txt\" size=30 maxlength=30></td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td colspan=2><b>Select Fields to Export:</b></td>\n";
  print "  </tr>\n";

  my @standardcols = (
    "orderid",  "plan",      "purchaseid", "password",   "name",      "company",    "addr1",       "addr2", "city", "state", "zip",       "country",
    "shipname", "shipaddr1", "shipaddr2",  "shipcity",   "shipstate", "shipzip",    "shipcountry", "phone", "fax",  "email", "billcycle", "startdate",
    "enddate",  "monthly",   "balance",    "cardnumber", "exp",       "lastbilled", "status",      "acct_code"
  );

  my %column_titles = (
    "orderid",  "OrderID",          "plan",      "Plan",             "purchaseid", "PurchaseID",        "password",    "Password",          "name",       "Billing Name",
    "company",  "Billing Company",  "addr1",     "Billing Address1", "addr2",      "Billing Address2",  "city",        "Billing City",      "state",      "Billing State",
    "zip",      "Billing Zip Code", "country",   "Billing Country",  "shipname",   "Shipping Name",     "shipaddr1",   "Shipping Address1", "shipaddr2",  "Shipping Address 2",
    "shipcity", "Shipping City",    "shipstate", "Shipping State",   "shipzip",    "Shipping Zip Code", "shipcountry", "Shipping Country",  "phone",      "Phone",
    "fax",      "Fax",              "email",     "Email",            "billcycle",  "Billing Cycle",     "startdate",   "Start Date",        "enddate",    "End Date",
    "monthly",  "Recurring Fee",    "balance",   "Balance",          "cardnumber", "Card Number",       "exp",         "Exp Date",          "lastbilled", "Last Billed",
    "status",   "Status",           "acct_code", "Account Code",     "accttype",   "Acct Type"
  );

  my @extracolsarray = split( / /, $extracols );
  foreach my $columnname (@extracolsarray) {
    if ( $columnname =~ /^(acct_code|purchaseid|balance)$/ ) {

      # These columns are now standarized & should always be inclued now.
      # Do not include columns again, if they were defined again as a custom column name
      next;
    }
    push( @standardcols, "$columnname" );
  }

  my $i = 0;
  print "  <tr>\n";
  print "    <td align=left colspan=2>\n";

  print "      <table border=0>\n";
  print "        <tr>\n";
  foreach my $var (@standardcols) {
    if ( ( $var eq 'balance' ) && ( $installbilling ne 'yes' ) ) {
      next;
    }

    if ( $column_titles{$var} eq '' ) {
      $column_titles{$var} = $var;
    }

    print "          <td><input type=checkbox name=\"$var\" value=\"export\" checked> $column_titles{$var} </td>\n";
    $i++;
    if ( $i > $#standardcols ) {
      print "        </tr>\n";
    } elsif ( $i % 4 == 0 ) {
      print "        </tr>\n";
      print "        <tr>\n";
    }
  }
  print "      </table>\n";

  print "    </td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<input type=submit class=button value=\"Export & Upload Member Database\" onClick=\"results();\"></form></td>\n";
  print "  </tr>\n";

  print "<!-- end database export section -->\n";
  return;
}

sub dump_billing {
  print "<!-- start dump billing section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Export Billing Table</th>\n";
  print "    <td align=left>\n";

  print "<form method=post action=\"/payment/recurring/$merchant/admin/editcust.cgi\" enctype=\"multipart/form-data\" target=\"new_Win\">\n";
  print "<input type=hidden name=\"function\" value=\"dump_billing\">\n";

  print "<table border=0>\n";
  my ( $select_mo, $select_dy, $select_yr ) = split( '/', $startdate );
  $html = &miscutils::start_date( $select_yr, $select_mo, $select_dy );
  print "  <tr>\n";
  print "    <td align=right>First Day:</td>\n";
  print "    <td>$html GMT</td>\n";
  print "  </tr>\n";

  ( $select_mo, $select_dy, $select_yr ) = split( '/', $enddate );
  $html = &miscutils::end_date( $select_yr, $select_mo, $select_dy );
  print "  <tr>\n";
  print "    <td align=right>Last Day:</td>\n";
  print "    <td>$html GMT</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<input type=submit class=button value=\"Export Billing Table\"></form></td>\n";
  print "  </tr>\n";
  print "<!-- end dump billing section -->\n";

  return;
}

sub prevbills {
  print "<!-- start previous bills section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th>View Billing</th>\n";
  print "    <td align=left>\n";

  print "<form method=post action=\"sendbill.cgi\">\n";
  print "<input type=hidden name=\"billing\" value=\"no\">\n";

  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td align=right>Passphrase:</td>\n";
  print "    <td><input type=text size=60 name=\"passphrase\" autocomplete=\"off\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Show All:</td>\n";
  print "    <td><input type=checkbox name=\"showall\" value=\"yes\"></td>\n";
  print "  </tr>\n";

  print "<input type=submit class=button value=\"View Previous Bills\"></form></td>\n";
  print "  </tr>\n";
  print "<!-- end previous bills section -->\n";

  return;
}

sub monthbills {
  print "<!-- start monthly bills section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Monthly</th>\n";
  print "    <td align=left>\n";

  print "<form method=post action=\"sendbill.cgi\">\n";

  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td align=right>Username:</td>\n";
  print "    <td><input type=text name=\"FTPun\" size=10 maxlength=40 autocomplete=\"off\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Password:</td>\n";
  print "    <td><input type=password name=\"FTPpw\" size=10 maxlength=40 autocomplete=\"off\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Passphrase:</td>\n";
  print "    <td><input type=text size=60 name=\"passphrase\" autocomplete=\"off\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Show All:</td>\n";
  print "    <td><input type=checkbox name=\"showall\" value=\"yes\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<input type=submit class=button value=\"Monthly Billing\"></form></td>\n";
  print "  </tr>\n";
  print "<!-- end previous bills section -->\n";

  return;
}

sub logs {
  my @month_names = ( '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' );

  my @todays_date = gmtime(time);
  $todays_date[5] += 1900;    # adjust for correct 4-digit year
  $todays_date[4] += 1;       # adjust for correct 2-digit month

  print "<!-- start logs section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Logs</th>\n";
  print "    <td align=left>\n";

  print "<form method=post action=\"editcust.cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"viewbilling\">";

  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td align=right>Username:</td>\n";
  print "    <td><input type=text name=\"username\" size=10 maxlength=24> &nbsp; (Leave blank to specify all usernames)<td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Start Date:</td>\n";
  print "    <td><select name=\"startmonth\">\n";
  for ( my $i = 1 ; $i <= $#month_names ; $i++ ) {
    print "<option value=\"$i\"";
    if ( $i == $todays_date[4] ) { print " selected"; }
    print ">$month_names[$i]</option>\n";
  }
  print "</select>\n";
  print "<select name=\"startday\">\n";
  for ( my $i = 1 ; $i <= 31 ; $i++ ) {
    print "<option value=\"$i\"";

    #if ($i == $todays_date[3]) { print " selected"; }
    print ">$i</option>\n";
  }
  print "</select>\n";
  print "<select name=\"startyear\">\n";
  for ( my $i = 1999 ; $i <= $todays_date[5] ; $i++ ) {
    print "<option value=\"$i\"";
    if ( $i == $todays_date[5] ) { print " selected"; }
    print ">$i</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>End Date:</td>\n";
  print "    <td><select name=\"endmonth\">\n";
  for ( my $i = 1 ; $i <= $#month_names ; $i++ ) {
    print "<option value=\"$i\"";
    if ( $i == $todays_date[4] ) { print " selected"; }
    print ">$month_names[$i]</option>\n";
  }
  print "</select>\n";
  print "<select name=\"endday\">\n";
  for ( my $i = 1 ; $i <= 31 ; $i++ ) {
    print "<option value=\"$i\"";
    if ( $i == $todays_date[3] ) { print " selected"; }
    print ">$i</option>\n";
  }
  print "</select>\n";
  print "<select name=\"endyear\">\n";
  for ( my $i = 1999 ; $i <= $todays_date[5] ; $i++ ) {
    print "<option value=\"$i\"";
    if ( $i == $todays_date[5] ) { print " selected"; }
    print ">$i</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<input type=submit class=button value=\"View Customer Logs\"></form></td>\n";
  print "  </tr>\n";
  print "<!-- end logs section -->\n";

  print "<!-- start documentation section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Documentation</th>\n";
  print "    <td align=left><ul>\n";
  print "      <li><a href=\"/admin/doc_replace.cgi?doc=Membership_Management_Administration_Area_Instructions.htm\">Administration Area Instructions</a></li>\n";
  print "      <li><a href=\"/admin/doc_replace.cgi?doc=Membership_Management_Attendant_Web_Page_Setup.htm\">Attendant Setup Instructions</a></li>\n";
  print "      <li><a href=\"/admin/doc_replace.cgi?doc=Membership_Management_Database_Export.htm\">Database Export Documentation</a></li>\n";
  print "      <li><a href=\"/admin/doc_replace.cgi?doc=Membership_Management_Database_Import_Specifications.htm\">Database Import Specifications</a></li>\n";
  print "      <li><a href=\"/admin/doc_replace.cgi?doc=Membership_Management_Join_Web_Page_Wizard.htm\">Join Page Wizard Instructions</a></li>\n";
  print "      <li><a href=\"/admin/doc_replace.cgi?doc=Membership_Management_Overview.htm\">Overview Documentation</a></li>\n";
  print "      <li><a href=\"/admin/doc_replace.cgi?doc=Membership_Management_Payment_Plans_Setup_Instructions.htm\">Payment Plans Setup Instructions</a></li>\n";
  print "    </ul></td>\n";
  print "  </tr>\n";

  print "<!-- end documentation section -->\n";

  return;
}

sub helpdesk {
  print "<!-- start helpdesk section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Help Desk</th>\n";
  print "    <td><form method=post action=\"/admin/helpdesk.cgi\" target=\"ahelpdesk\">\n";
  print
    "<input type=submit class=button value=\"Help Desk\" onClick=\"window.open('','ahelpdesk','width=550,height=520,toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes'); return(true);\"></form></td>\n";
  print "  <tr>\n";
  print "<!-- end helpdesk section -->\n";

  return;
}

sub graphs {
  my @month_names = ( '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' );

  my @todays_date = gmtime(time);
  $todays_date[5] += 1900;    # adjust for correct 4-digit year
  $todays_date[4] += 1;       # adjust for correct 2-digit month

  print "<!-- start graphs section -->\n";
  print "  <tr>\n";
  print "    <td colspan=2><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Graphs</th>\n";
  print "    <td align=left>\n";

  print "<form method=post action=\"graph.cgi\" target=\"graph\">\n";

  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td align=right>Type:</td>\n";
  print "    <td><input type=radio name=\"function\" value=\"daily\" checked> Daily\n";
  print "      <input type=radio name=\"function\" value=\"monthly\"> Monthly</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Database:</td>\n";
  print "    <td><input type=radio name=\"graphtype\" value=\"billing\" checked> Billing\n";
  print "      <input type=radio name=\"graphtype\" value=\"customers\"> Customers</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Start Date:</td>\n";
  print "    <td><select name=\"startmonth\">\n";
  for ( my $i = 1 ; $i <= $#month_names ; $i++ ) {
    print "<option value=\"$month_names[$i]\"";
    if ( $i == $todays_date[4] ) { print " selected"; }
    print ">$month_names[$i]</option>\n";
  }
  print "</select>\n";
  print "<select name=\"startyear\">\n";
  for ( my $i = 1999 ; $i <= $todays_date[5] ; $i++ ) {
    print "<option value=\"$i\"";
    if ( $i == $todays_date[5] ) { print " selected"; }
    print ">$i</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>End Date:</td>\n";
  print "    <td><select name=\"endmonth\">\n";
  for ( my $i = 1 ; $i <= $#month_names ; $i++ ) {
    print "<option value=\"$month_names[$i]\"";
    if ( $i == $todays_date[4] ) { print " selected"; }
    print ">$month_names[$i]</option>\n";
  }
  print "</select>\n";
  print "<select name=\"endyear\">\n";
  for ( my $i = 1999 ; $i <= $todays_date[5] ; $i++ ) {
    print "<option value=\"$i\"";
    if ( $i == $todays_date[5] ) { print " selected"; }
    print ">$i</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Format:</td>\n";
  print "    <td><input type=radio name=\"format\" value=\"html\" checked> Table\n";
  print "      <input type=radio name=\"format\" value=\"text\"> Text</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<input type=submit class=button value=\"Generate Graph\"></form></td>\n";
  print "  </tr>\n";
  print "<!-- end graphs section -->\n";

  return;
}

sub tail {

  #print "</table>\n";

  my @now       = gmtime(time);
  my $copy_year = $now[5] + 1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"footer\">\n";
  print "  <tr>\n";
  print
    "    <td align=left><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></td>\n";
  print "    <td align=right>\&copy; $copy_year, ";
  if ( $ENV{'SERVER_NAME'} =~ /plugnpay\.com/i ) {
    print "Plug and Pay Technologies, Inc.";
  } else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";

  return;
}
