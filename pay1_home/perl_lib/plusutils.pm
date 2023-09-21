package plusutils;

use CGI;
use DBI;
use MD5;
use LWP::UserAgent;
use rsautils;
use miscutils;
use sysutils;
use PlugNPay::ResponseLink;
use PlugNPay::CardData;
use PlugNPay::Logging::DataLog;
use PlugNPay::Email;

sub new {
  my $type = shift;
  ( $merchant, $path_passwrdremote, $path_test, $host, $user1, $user2, $user3, $user4, $merchant_db ) = @_;

  local ( $ssec, $mmin, $hhour, $dday, $mmonth, $yyear, $wday, $yday, $isdst ) = gmtime(time);
  $dday   = $dday;
  $mmonth = $mmonth + 1;
  $yyear  = $yyear + 1900;

  $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};

  if ( $merchant_db ne "" ) {
    $database = $merchant_db;
  } else {
    $database = $merchant;
  }
  $dbh_plus = &miscutils::dbhconnect("$database");

  $query = new CGI;

  $function = &CGI::escapeHTML( $query->param('function') );
  $function =~ s/[^a-zA-Z0-9\_\-]//g;

  $username = &CGI::escapeHTML( $query->param('username') );
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $password = &CGI::escapeHTML( $query->param('password') );
  $password =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  $reason = &CGI::escapeHTML( $query->param('reason') );
  $reason =~ s/\'//g;

  $acct_code = &CGI::escapeHTML( $query->param('acct_code') );
  $acct_code =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,\|]//g;

  $dbh2 = &miscutils::dbhconnect("pnpmisc");

  $sth = $dbh2->prepare(
    q{
      SELECT membership,submit_date
      FROM pnpsetups
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute("$merchant") or die "Can't execute: $DBI::errstr";
  my ( $membership, $submit_date ) = $sth->fetchrow;
  $sth->finish;

  $sth = $dbh2->prepare(
    q{
      SELECT reseller, company
      FROM customers
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute("$merchant") or die "Can't execute: $DBI::errstr";
  ( $reseller, $merch_company ) = $sth->fetchrow;
  $sth->finish;

  $sth_merchants = $dbh2->prepare(
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

  if ( $admindomain eq "" ) {
    $admindomain = "pay1.plugnpay.com";
  }

  $dbh2->disconnect;

  $goodcolor = "#000000";
  $badcolor  = "#ff0000";
  $backcolor = "#ffffff";
  $fontface  = "Arial,Helvetica,Univers,Zurich BT";

  $recurr_billonly = "no";
  if ( ( $membership ne "membership" ) && ( $submit_date >= 20050101 ) ) {
    $recurr_billonly = "yes";
  }

  return [], $type;
}

sub html_head {
  my ( $title, $sub_section ) = @_;

  if ( $title eq "" ) {
    $title = "Membership Management Administration";
  }

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>$title</title>\n";

  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/css/style_recurring.css\">\n";

  print "<script type=\"text/javascript\">\n";
  print "//<!-- Start Script\n";

  print "function edituname(chuname) {\n";
  print "  eval('document.' + chuname + '.submit();');\n";
  print "}\n";

  print "function results() {\n";
  print "  resultsWindow = window.open('/payment/recurring/blank.html','results','menubar=no,status=no,scrollbars=yes,resizable=yes,width=720,height=500');\n";
  print "}\n";

  print "function closeresults() {\n";
  print "  resultsWindow = window.close('results');\n";
  print "}\n";

  print "function change_confirm() {\n";
  print
    "  return confirm(\'By changing this customers username, you WILL affect the accuracy of the customers billing and service histories.  You assume this risk, when you change the customers username.  See QA number QA20020517163956 in the online FAQ for details.  Are you sure you want to do this\?\')\;\n";
  print "}\n";

  print "function change_win(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "function toggle_visibility(id) {\n";
  print "  var e = document.getElementById(id);\n";
  print "  if(e.style.display == 'block') {\n";
  print "    e.style.display = 'none';\n";
  print "  }\n";
  print "  else {\n";
  print "    e.style.display = 'block';\n";
  print "  }\n";
  print "}\n";

  print "//-->\n";
  print "</script>\n";

  print "<script type=\"text/javascript\" src=\"/javascript/rec_luhn10.js\"></script>\n";
  print "<script type=\"text/javascript\" src=\"/javascript/input_validation.js\"></script>\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" onLoad=\"self.focus()\">\n";

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
  print "    <td colspan=3 align=left><img src=\"/images/header_bottom_bar_gfx.gif\" width=760 alt=\"\" height=14></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=0 cellspacing=0 cellpadding=0 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=2 class=\"larger\"><h1><b><a href=\"./index.cgi\">Membership Management Administration</a>\n";
  if ( $sub_section ne "" ) {
    print " / $sub_section";
  }
  print " - $merch_company</b></h1>";

  #print "</td>\n";
  #print "  </tr>\n";
  #print "</table>\n";

  return;
}

sub html_tail {

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

sub locatepassword {
  ( $myusername, $mypassword, $addr ) = @_;

  my $ua = new LWP::UserAgent;
  $ua->agent( "AgentName/0.1 " . $ua->agent );
  $ua->timeout(1200);

  my $req = new HTTP::Request GET => $addr;
  $req->content_type('application/x-www-form-urlencoded');
  if ( ( $myusername ne "" ) && ( $mypassword ne "" ) ) {
    $req->authorization_basic( "$myusername", "$mypassword" );
  }
  my $res = $ua->request($req);
  if ( $res->is_success ) {
    $passtest = $res->content;
  } else {

    #    print $res->error_as_HTML;
    $message = $res->message;
  }

  $message =~ s/(Content-type\: text\/html)//gi;    # remove extra "Content-Type: text/html" from messages, where necessary

  if ( $passtest =~ /success/i ) {
    $message = "The Following Username and Password:\n";
    $message .= "<br>UN:$myusername\n";
    $message .= "<br>PW:$mypassword\n";
    $message .= "<br>Were found in the Password File";
  } else {
    $message = "The Password for :$myusername:, :$mypassword:, was Not Found in the Password File\n";
  }

  #  &record_history("$myusername","Password Search","Problem Resolution Request");
  #  &response_page($message);

  #  $dbh->disconnect;
  #  exit;

  return;
}

sub record_history {
  my ( $username, $action, $reason ) = @_;

  $username = substr( $username, 0, 24 );
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $action = substr( $action, 0, 20 );
  $reason .= " by $ENV{'REMOTE_ADDR'}";
  $reason = substr( $reason, 0, 255 );

  $now         = time();
  $sth_history = $dbh_plus->prepare(
    q{
      INSERT INTO history
      (trans_time,username,action,descr)
      VALUES (?,?,?,?)
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_history->execute( $now, $username, $action, $reason ) or die "Can't execute: $DBI::errstr";
  $sth_history->finish;

  return;
}

sub report_head {

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Edit Items</title>\n";

  print "<style type=\"text/css\">\n";
  print "<!--\n";
  print "th { font-family: $fontface; font-size: 75%; color: $goodcolor; textAlign: left;}\n";
  print "td { font-family: $fontface; font-size: 70%; color: $goodcolor;}\n";
  print ".badcolor { color: $badcolor }\n";
  print ".goodcolor { color: $goodcolor }\n";
  print ".larger { font-size: 100% }\n";
  print ".smaller { font-size: 50% }\n";
  print ".short { font-size: 8% }\n";
  print ".itemscolor { background-color: $goodcolor; color: $backcolor }\n";
  print ".itemrows { background-color: #d0d0d0 }\n";
  print ".divider { background-color: #4a7394 }\n";
  print ".items { position: static }\n";
  print ".info { position: static }\n";
  print "-->\n";
  print "</style>\n";

  print "<script type=\"text/javascript\">\n";
  print "//<!-- Start Script\n";

  print "function edituname(chuname) {\n";

  #print " resultsWindow = window.open('/payment/recurring/blank.html','results','menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300');\n";
  print "  eval('document.' + chuname + '.submit();\');\n";
  print "}\n";
  print "//-->\n";

  print "function results() {\n";
  print "  resultsWindow = window.open('/payment/recurring/blank.html','results','menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300');\n";
  print "}\n";
  print "//-->\n";
  print "</script>\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" onLoad=\"self.focus()\">\n";

  print "<table border=0 cellspacing=1 cellpadding=0 width=750>\n";
  print "  <tr>\n";
  print "    <td align=center colspan=3><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td>\n";
  print "  </tr>\n";

  if ( $recurr_billonly ne "yes" ) {
    print "  <tr>\n";
    print "    <td align=center colspan=3 bgcolor=\"#000000\" class=\"larger\"><font color=\"#ffffff\"><b>Membership Management Administration Area</b></font></td>\n";
    print "  </tr>\n";
  } else {
    print "  <tr>\n";
    print "    <td align=center colspan=3 bgcolor=\"#000000\" class=\"larger\"><font color=\"#ffffff\">Recurring Billing Administration Area</font></td>\n";
    print "  </tr>\n";
  }

  print "<tr>\n";
  print "  <td align=center colspan=3>\n";

  return;
}

sub report_tail {
  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";

  return;
}

sub show_history {
  my ($myusername) = @_;
  $myusername =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  &html_head( "Service History", "Service History" );

  print "<table border=0 cellpadding=2 cellspacing=0 width=760>\n";
  print "  <tr>\n";
  print "    <th colspan=3 align=left><h3>Username: $myusername</h3></th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th align=left>Date:</th>\n";
  print "    <th align=left>Action:</th>\n";
  print "    <th align=left>Reason:</th>\n";
  print "  </tr>\n";

  my ( $trans_date, $action, $reason );
  my $color = "ffffff";

  my $sth = $dbh_plus->prepare(
    q{
      SELECT trans_time,action,descr
      FROM history
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute("$myusername") or die "Can't execute: $DBI::errstr";
  while ( my ( $trans_date, $action, $reason ) = $sth->fetchrow ) {
    my $now = gmtime($trans_date);

    if ( $color eq "d0d0d0" ) {
      $color = "ffffff";
    } else {
      $color = "d0d0d0";
    }

    print "<tr bgcolor=\"#$color\">\n";
    print "    <td>$now</td>\n";
    print "    <td>$action</td>\n";
    print "    <td>$reason</td>\n";
    print "  </tr>\n";
  }
  $sth->finish;

  print "</table>\n";
  print "<p><form><input type=button class=\"button\" value=\"Close Window\" onClick=\"closeresults();\"></form>\n";
  &html_tail();

  return;
}

sub response_page {
  my ($message) = @_;

  &html_head( "", "" );

  print "<div align=center>\n";
  print "<p><table width=760>\n";
  print "  <tr>\n";
  print "    <td>$message</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><form><input type=button class=\"button\" value=\"Close Window\" onClick=\"closeresults();\"></form></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "</div>\n";

  &html_tail();
  return;
}

sub passwrdremote {
  my ( $myusername, $mypassword, $mode, $path_passwrdremote, $end, $purchaseid ) = @_;
  $myusername =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  if ( $path_passwordremote eq "http:///cgi-bin/passwrdremote.cgi" ) {
    return;
  }

  $pairs = "username=$myusername\&mode=$mode\&password=$mypassword\&end=$end\&purchaseid=$purchaseid";

  my $rl = new PlugNPay::ResponseLink( $merchant, $path_passwrdremote, $pairs, 'post', 'meta' );
  $rl->doRequest();
  $message = $rl->getResponseContent;

  #$message = &miscutils::formpostpl($path_passwrdremote,$pairs,$message);

  $message =~ s/Content-type\: text\/html//gi;    # remove extra "Content-Type: text/html" from messages, where necessary

  return;
}

sub plus_delete {
  my ($myusername) = @_;
  $myusername =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  local ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  $mypassword = sprintf( "CN%02d%05d", $min, $sec );
  $status     = "cancelled";
  $bc         = "0";

  my $sth = $dbh_plus->prepare(
    q{
      UPDATE customer
      SET password=?,status=?,billcycle=?
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$mypassword", "$status", "$bc", "$myusername" ) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  &passwrdremote( $myusername, $mypassword, "delete", $path_passwrdremote );

  $reason = "";
  &record_history( "$myusername", "Cancelled", "$reason" );

  &response_page("The Username: $myusername has been cancelled");

  $dbh_plus->disconnect;
  exit;
}

sub addtopassword {
  my $mypassword = &CGI::escapeHTML( $query->param('password') );
  $mypassword =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  my $myusername = &CGI::escapeHTML( $query->param('username') );
  $myusername =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  my $purchaseid = &CGI::escapeHTML( $query->param('purchaseid') );
  $purchaseid =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,\|]//g;

  if ( $ostype !~ /NT/i ) {
    $mypassword = crypt( $mypassword, $mypassword );
  }

  my $myend = &CGI::escapeHTML( $query->param('end') );
  $myend =~ s/[^0-9]//g;

  my $message = &passwrdremote( $myusername, $mypassword, "add", $path_passwrdremote, $myend, $purchaseid );

  $reason = "";
  &record_history( "$myusername", "Added Password", "$reason" );

  &response_page($message);
  exit;
}

sub deletefrompassword {
  my ($myusername) = @_;
  $myusername =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $message = &passwrdremote( $myusername, $mypassword, "delete", $path_passwrdremote );

  $reason = "";
  &record_history( "$myusername", "Removed Password", "$reason" );

  &response_page($message);
  exit;
}

sub addtofraud {
  my ($username) = @_;
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  my $cardnumber = &CGI::escapeHTML( $query->param('cardnumber') );
  $cardnumber =~ s/[^0-9]//g;

  my $reason = &CGI::escapeHTML( $query->param('reason') );
  $reason =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  my $other = &CGI::escapeHTML( $query->param('other') );
  $other =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  if ( $other ne "" ) {
    $reason = $other;
  }

  if ( $username ne "" ) {
    my $sth = $dbh_plus->prepare(
      q{
        SELECT orderid,enccardnumber,length
        FROM customer
        WHERE username=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ( $orderid, $enccardnumber, $length ) = $sth->fetchrow;
    $sth->finish;

    my $cd                 = new PlugNPay::CardData();
    my $ecrypted_card_data = '';
    eval { $ecrypted_card_data = $cd->getRecurringCardData( { customer => "$username", username => "$database" } ); };
    if ( !$@ ) {
      $enccardnumber = $ecrypted_card_data;
    }

    if ( $enccardnumber ne "" ) {
      $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
    }
  }

  # remove non-numeric characters - 07/26/05 - James
  $cardnumber =~ s/[^0-9]//g;

  # do luhn10 error check - 07/26/05 - James
  $luhntest = &miscutils::luhn10($cardnumber);

  if ( ( $luhntest eq "failure" ) || ( length($cardnumber) < 13 ) || ( length($cardnumber) > 20 ) ) {
    &html_head( "Fraud Prevention", "Fraud Prevention" );
    print "<h3>Invalid Credit Card Number</h3>\n";
    print "<p><form><input type=button class=\"button\" value=\"Close Window\" onClick=\"closeresults();\"></form>\n";
    &html_tail();
    return;
  }

  my $md5 = new MD5;
  $md5->add("$cardnumber");
  my $cardnumber_md5 = $md5->hexdigest();
  $cardnumber = substr( $cardnumber, 0, 4 ) . '**' . substr( $cardnumber, length($cardnumber) - 2, 2 );

  my ( $now, $trans_time ) = &miscutils::gendatetime_only();

  my $dbh_fraud = &miscutils::dbhconnect("pnpmisc");
  my $sth       = $dbh_fraud->prepare(
    q{
      SELECT enccardnumber,trans_date,card_number
      FROM fraud
      WHERE enccardnumber=?
    }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %$query );
  $sth->execute("$cardnumber_md5") or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %$query );
  my ( $test, $orgdate, $cardnumber1 ) = $sth->fetchrow;
  $sth->finish;

  if ( $test eq "" ) {
    my $sth_insert = $dbh_fraud->prepare(
      q{
        INSERT INTO fraud
        (enccardnumber,username,trans_date,descr,card_number)
        VALUES (?,?,?,?,?)
      }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %$query );
    $sth_insert->execute( "$cardnumber_md5", "$ENV{'REMOTE_USER'}", "$now", "$reason", "$cardnumber" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %$query );
    $sth_insert->finish;
    $message = "This credit card number has been successfully added to the negative database.";
    if ( $username ne "" ) {
      &record_history( "$username", "Added To Fraud", "$reason" );
    }
  } else {
    $message = "This credit card number has been previously added to the negative database.";
  }
  $dbh_fraud->disconnect;
  $dbh_plus->disconnect;

  &html_head( "Fraud Prevention", "Fraud Prevention" );
  print "$message\n";
  print "<p><form><input type=button class=\"button\" value=\"Close Window\" onClick=\"closeresults();\"></form>\n";
  &html_tail();

  return;
}

sub addtofraud2 {

  # 09/14/07 - merged the 'addtofraud2' sub-function into the existing 'addtofraud', since it does the same thing.
  &addtofraud();
  return;
}

sub viewcustomer {
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  my $sth = $dbh_plus->prepare(
    q{
      SELECT name,orderid,company,addr1,addr2,city,state,zip,country,password,email,startdate,enddate,monthly,cardnumber,exp,lastbilled,billcycle,shipname,shipaddr1,shipaddr2,shipcity,shipstate,shipzip,shipcountry,status,enccardnumber,length,purchaseid
      FROM customer
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  ( $name,      $orderid,  $company,   $addr1,   $addr2,       $city,   $state,         $zip,       $country,  $password,
    $email,     $start,    $end,       $monthly, $cardnumber,  $exp,    $lastbilled,    $billcycle, $shipname, $shipaddr1,
    $shipaddr2, $shipcity, $shipstate, $shipzip, $shipcountry, $status, $enccardnumber, $length,    $purchaseid
  )
    = $sth->fetchrow;
  $sth->finish;

  my $cd                 = new PlugNPay::CardData();
  my $ecrypted_card_data = '';
  eval { $ecrypted_card_data = $cd->getRecurringCardData( { customer => "$username", username => "$database" } ); };
  if ( !$@ ) {
    $enccardnumber = $ecrypted_card_data;
  }

  &html_head( "Customer Administration", "Customer Administration" );
  print "<table border=0 cellspacing=0 cellpadding=1 width=760>\n";

  &write_table_entry();

  print "</table><p>\n";

  print "<div align=center>\n";
  print "<form action=\"index.cgi\"><input type=submit class=\"button\" value=\"Go To Main Page\"></form>\n";
  print "<br>\n";
  print "</div>\n";

  &html_tail();
}

sub viewcustomers {

  &html_head("Membership Administration");
  print "<table border=0 cellspacing=0 cellpadding=1 width=760>\n";

  my $sth = $dbh_plus->prepare(
    q{
      SELECT username,orderid,name,company,addr1,addr2,city,state,zip,country,password,email,startdate,enddate,monthly,cardnumber,exp,lastbilled,status,billcycle,shipname,shipaddr1,shipaddr2,shipcity,shipstate,shipzip,shipcountry,purchaseid,enccardnumber,length
      FROM customer
      ORDER BY username
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";

  $i = 0;
  while (
    my (
      $username, $orderid,   $name,      $company,  $addr1,     $addr2,      $city,        $state,      $zip,           $country,
      $password, $email,     $start,     $end,      $monthly,   $cardnumber, $exp,         $lastbilled, $status,        $billcycle,
      $shipname, $shipaddr1, $shipaddr2, $shipcity, $shipstate, $shipzip,    $shipcountry, $purchaseid, $endcardnumber, $length
    )
    = $sth->fetchrow
    ) {
    $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

    my $cd                 = new PlugNPay::CardData();
    my $ecrypted_card_data = '';
    eval { $ecrypted_card_data = $cd->getRecurringCardData( { customer => "$username", username => "$database" } ); };
    if ( !$@ ) {
      $enccardnumber = $ecrypted_card_data;
    }

    &write_table_entry;
    $i++;
    if ( $i > 100 ) {
      last;
    }
  }
  $sth->finish;

  print "</table><p>\n";

  print "<div align=center>\n";
  print "<form action=\"index.cgi\"><input type=submit class=\"button\" value=\"Go To Main Page\"></form>\n";
  print "<br>\n";
  print "</div>\n";

  &html_tail();

  return;
}

sub write_table_entry {
  my ( @nows, @actions, @reasons );

  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  ## Modified DCP 20071211  -  To remove retrieving username from history table thereby overwriting search parameter.
  my $sth_history = $dbh_plus->prepare(
    q{
      SELECT trans_time,username,action,descr
      FROM history
      WHERE username=?
      ORDER BY trans_time DESC
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth_history->execute("$username") or die "Can't execute: $DBI::errstr";
  while ( my ( $trans_date, $db_username, $action, $reason ) = $sth_history->fetchrow ) {

    #print "$db_username<br>\n";
    $now = gmtime($trans_date);
    push( @nows,    "$now" );
    push( @actions, "$action" );
    push( @reasons, "$reason" );
  }
  $sth_history->finish;

  $allowe_ccsrch = "no";

  if ( ( $ENV{'SEC_LEVEL'} <= 7 ) && ( $ENV{'TECH'} eq "" ) && ( $enccardnumber ne "" ) && ( $username =~ /^(pnptest)$/ ) ) {
    $allowe_ccsrch  = "yes";
    $fullcardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
    $mylen          = length($fullcardnumber);
    if ( ( $mylen < 13 ) || ( $mylen > 40 ) ) {
      $fullcardnumber = "";
      $allowe_ccsrch  = "no";
    }
  }

  if ( $start ne "" ) {
    $startmonth = substr( $start, 4, 2 );
    $startday   = substr( $start, 6, 2 );
    $startyear  = substr( $start, 0, 4 );
    $endyear    = $startyear;
    $endmonth   = $startmonth + 3;
    if ( $endmonth > 12 ) {
      $endyear = $endyear + 1;
    }
    $endmonth = sprintf( "%02d", ( $endmonth % 12 ) );
  }

  if ( $allowe_ccsrch eq "yes" ) {
    $cc_srchstr = "<a href=\"/admin/smps.cgi?function=query\&decrypt=yes\&";

    if ( $start ne "" ) {
      $cc_srchstr .= "startmonth=$startmonth\&startday=$startday\&startyear=$startyear\&endmonth=$endmonth\&endday=$startday\&endyear=$endyear\&";
    }
    $cc_srchstr .= "cardnumber=$fullcardnumber";
    $cc_srchstr .= "\" target=\"newwin\">$cardnumber</a>";
  } else {
    $cc_srchstr = "$cardnumber";
  }

  if ( $billcycle < 1 ) {

    #$billcycle = 0;
  }
  if ( $start ne "" ) {
    $start = sprintf( "%02d/%02d/%04d", substr( $start, 4, 2 ), substr( $start, 6, 2 ), substr( $start, 0, 4 ) );
  }
  if ( $end ne "" ) {
    $end1 = $end;
    $end = sprintf( "%02d/%02d/%04d", substr( $end, 4, 2 ), substr( $end, 6, 2 ), substr( $end, 0, 4 ) );
  }
  if ( $lastbilled ne "" ) {
    $lastbilled = sprintf( "%02d/%02d/%04d", substr( $lastbilled, 4, 2 ), substr( $lastbilled, 6, 2 ), substr( $lastbilled, 0, 4 ) );
  }

  print "<!-- start table entry -->\n";
  print "  <tr>\n";
  print "    <td><fieldset style=\"width: 720; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
  print "<legend style=\"padding: 4px 8px;\"><b>Customer Info:</b></legend>\n";

  print "<table border=0 cellpadding=0 cellspacing=0>\n";
  print "  <tr>\n";
  print "    <td>&nbsp;</td>\n";
  print "    <th align=right>Username:</th>\n";
  print "    <td><a href=\"editcust.cgi\?function=edit\&username=$username\" target=\"editwin\">$username</a></td>\n";
  print "    <th align=right>New Username:</th>\n";
  print "    <td><form method=post action=\"editcust.cgi\" name=\"chuname$orderid\">\n";
  print "<input type=hidden name=\"function\" value=\"editusername\">\n";
  print "<input type=hidden name=\"username\" value=\"$username\">\n";
  print "<input type=hidden name=\"orderid\" value=\"$orderid\">\n";
  print "<input type=text name=\"newuname\" size=8 maxlength=58>\n";
  print "<a href=\"javascript:edituname('chuname$orderid');\" class=\"button\" onClick=\"return change_confirm();\">Change</a></td></form>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td rowspan=6 align=left valign=top>\n";
  print "<form method=post action=\"editcust.cgi\" target=\"results\">\n";
  print "<input type=hidden name=\"username\" value=\"$username\">\n";
  if ( $recurr_billonly ne "yes" ) {

    # for password management use only
    if ( $password ne "" )   { print "<input type=hidden name=\"password\" value=\"$password\">\n"; }
    if ( $orderid ne "" )    { print "<input type=hidden name=\"orderid\" value=\"$orderid\">\n"; }
    if ( $purchaseid ne "" ) { print "<input type=hidden name=\"purchaseid\" value=\"$purchaseid\">\n"; }
    if ( $end ne "" )        { print "<input type=hidden name=\"end\" value=\"$end1\">\n"; }
    if ( $name ne "" )       { print "<input type=hidden name=\"name\" value=\"$name\">\n"; }
    if ( $email ne "" )      { print "<input type=hidden name=\"email\" value=\"$email\">\n"; }
  }
  if ( $allow_remove ne "no" ) {
    print "<input type=radio name=\"function\" value=\"remove\">";
    print "<a href=\"/payment/recurring/membership_help.html\#remove\" onClick=\"results();\" target=\"results\">Remove Customer</a><br>\n";
  }

  if ( $recurr_billonly ne "yes" ) {
    print "<input type=radio name=\"function\" value=\"delete\">";
    print "<a href=\"/payment/recurring/membership_help.html\#terminate\" onClick=\"results();\" target=\"results\">Terminate Membership</a><br>\n";

    print "<input type=radio name=\"function\" value=\"activate\">";
    print "<a href=\"/payment/recurring/membership_help.html\#activate\" onClick=\"results();\" target=\"results\">Activate Membership</a><br>\n";
  }

  print "<input type=radio name=\"function\" value=\"cancel\">";
  print "<a href=\"/payment/recurring/membership_help.html\#cancel\" onClick=\"results();\" target=\"results\">Cancel Recurring</a><br>\n";

  print "<input type=radio name=\"function\" value=\"edit\" checked>";
  print "<a href=\"/payment/recurring/membership_help.html\#edit\" onClick=\"results();\" target=\"results\">Edit Customer Info.</a><br>\n";

  if ( $recurr_billonly ne "yes" ) {
    print "<input type=radio name=\"function\" value=\"mailusername\">";
    print "<a href=\"/payment/recurring/membership_help.html\#mail\" onClick=\"results();\" target=\"results\">Mail UN & PW</a><br>\n";

    print "<input type=radio name=\"function\" value=\"addtopassword\">";
    print "<a href=\"/payment/recurring/membership_help.html\#add\" onClick=\"results();\" target=\"results\">Add to Password Files</a><br>\n";

    print "<input type=radio name=\"function\" value=\"deletefrompassword\">";
    print "<a href=\"/payment/recurring/membership_help.html\#remove\" onClick=\"results();\" target=\"results\">Remove from Password Files</a><br>\n";

    # 12/03/04 - Note: the 'Search for Password' was removed because most web browsers don't support the way we do this test any longer
    #print "<input type=radio name=\"function\" value=\"locatepassword\">";
    #print "<a href=\"/payment/recurring/membership_help.html\#search\" onClick=\"results();\" target=\"results\">Search for Password</a><br>\n";
  }

  print "<input type=radio name=\"function\" value=\"fraud\">";
  print "<a href=\"/payment/recurring/membership_help.html\#fraud\" onClick=\"results();\" target=\"results\">Add to Fraud Database</a><br>\n";

  print "<input type=radio name=\"function\" value=\"viewbilling\">";
  print "<a href=\"/payment/recurring/membership_help.html\#billing\" onClick=\"results();\" target=\"results\">Billing History</a><br>\n";

  print "<input type=radio name=\"function\" value=\"history\">";
  print "<a href=\"/payment/recurring/membership_help.html\#history\" onClick=\"results();\" target=\"results\">Service History</a>\n";

  print "<div align=center><input type=submit class=\"button\" value=\"Submit Request\" onClick=\"results();\"></div></td>\n";

  print "    <th align=right>Password:</th>\n";
  print "    <td>$password</td>\n";
  print "    <th align=right>OrderID:</th>\n";
  print
    "    <td><a href=\"/admin/smps.cgi\?function=query\&orderid=$orderid\&decrypt=yes\&startmonth=$startmonth\&startday=$startday\&startyear=$startyear\&endmonth=$endmonth\&endday=$startday\&endyear=$endyear\" target=\"newwin\">$orderid</a></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th align=right>Customer Name:</th>\n";
  print "    <td>$name</td>\n";
  print "    <th align=right>Email:</th>\n";
  print "    <td>";
  if ( $email ne "" ) {
    print "<a href=\"mailto:$email\">$email</a>";
  } else {
    print "&nbsp;\n";
  }
  print "</td>\n";
  print "  </tr>\n";

  if ( $status eq "" ) {
    $status = "active";
  }
  print "  <tr>\n";
  print "    <th align=right>Billing Status:</th>\n";
  print "    <td>$status</td>\n";
  print "    <th align=right>Bill Cycle:</th>\n";
  print "    <td>$billcycle Month(s)</td>\n";
  print "  </tr>\n";

  if ( $ENV{'REMOTE_USER'} eq "jamest3" ) {
    print "  <tr>\n";
    print "    <th align=right>Recurring:</th>\n";
    print "    <td>$monthly</td>\n";
    print "    <th align=right>Balance:</th>\n";
    print "    <td>$balance</td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <th align=right>Next Payment:<br>(End Date)</th>\n";
  print "    <td>$end</td>\n";
  print "    <th align=right>Sign-up Date:<br>(Start Date)</th>\n";
  print "    <td>$start</td>\n";
  print "  </tr>\n";

  my $is_ach          = 0;
  my $temp_routingnum = "";
  my $temp_accountnum = "";

  if ( $enccardnumber ne "" ) {

    # decrypt card on file & see if its an Credit Card or ACH/eCheck account.
    my $temp_cc = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
    if ( $temp_cc =~ /\W/ ) {
      $is_ach = 1;
      ( $temp_routingnum, $temp_accountnum ) = split( / /, $temp_cc, 2 );

      # Account number filter
      $temp_accountnum =~ s/[^0-9]//g;
      $temp_accountnum = substr( $temp_accountnum, 0, 20 );
      my ($accountnum) = $temp_accountnum;
      my $acctlength = length($accountnum);
      my $last4 = substr( $accountnum, -4, 4 );
      $accountnum =~ s/./X/g;
      $temp_accountnum = substr( $accountnum, 0, $acctlength - 4 ) . $last4;

      # Routing number filter
      $temp_routingnum =~ s/[^0-9]//g;
      $temp_routingnum = substr( $temp_routingnum, 0, 9 );
      my ($routingnum) = $temp_routingnum;
      my $routlength = length($routingnum);
      my $first4 = substr( $routingnum, 0, 4 );
      $routingnum =~ s/./X/g;
      $temp_routingnum = $first4 . substr( $routingnum, 4, $routlength - 4 );
    }
    $temp_cc = "";    # destroy decrypted card info, since its no longer needed.
  }

  if ( $is_ach == 1 ) {
    print "  <tr>\n";
    print "    <th align=right>ACH Routing #:</th>\n";
    print "    <td>$temp_routingnum</td>\n";
    print "    <th align=right>Account #:</th>\n";
    print "    <td>$temp_accountnum</td>\n";
    print "  </tr>\n";
  } else {
    print "  <tr>\n";
    print "    <th align=right>Card Number:</th>\n";
    print "    <td>$cc_srchstr</td>\n";
    print "    <th align=right>Exp Date:</th>\n";
    print "    <td>$exp</td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <th align=right>Address:</th>\n";
  print "    <td colspan=3>";
  if ( $addr1 ne "" ) {
    print "$addr1<br>";
  }
  if ( $addr2 ne "" ) {
    print "$addr2<br>";
  }
  if ( ( $city ne "" ) || ( $state ne "" ) || ( $zip ne "" ) || ( $country ne "" ) ) {
    print "$city, $state $zip $country";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=5><b>Reason:</b>\n";
  print "<br><input type=text name=\"reason\" size=\"60\" maxlength=\"250\"></td></form>\n";
  print "  </tr>\n";

  my $service_count = scalar(@nows);
  if ( $service_count > 0 ) {
    print "  <tr>\n";
    print "    <td colspan=5><b>Service History:</b>\n";
    print "<br><form method=post action=\"editcust.cgi\"><select name=\"reason\">\n";

    foreach my $var (@nows) {
      print "<option>$var - $actions[$i]: $reasons[$i]</option>\n";
      $i++;
    }
    print "</select></form></td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td colspan=5>";

  print "<div align=right><a href=\"#\" onclick=\"toggle_visibility('billmem$username');\">Show/Hide Advanced Options</a></div>\n";
  print "<div id=\"billmem$username\" style=\"display:none;\">\n";

  print "<fieldset style=\"width: 720; position: relative; border: 1px solid; margin: none; padding: 0px 10px 10px; background: #f9f9f9; -moz-border-radius: 10px;\">\n";
  print "<form method=post action=\"/admin/smps.cgi\" name=\"bill$username\" onsubmit=\"return disableForm(this);\">\n";
  print "<input type=hidden name=\"function\" value=\"inputnew\">\n";
  print "<input type=hidden name=\"convert\" value=\"underscores\">\n";
  print "<input type=hidden name=\"merchant\" value=\"$merchant\">\n";
  print "<input type=hidden name=\"receipt_company\" value=\"$merch_company\">\n";
  print "<input type=hidden name=\"username\" value=\"$username\">\n";
  print "<input type=hidden name=\"mode\" value=\"bill_member\">\n";
  print "<input type=hidden name=\"currency\" value=\"$currency\">\n";
  print "<b>Bill Member:</b>\n";
  print "<br>Amount: $currency <input type=text name=\"card_amount\" value=\"$monthly\" size=10 maxlength=10> (example: 1200.99)\n";

  if ( $is_ach == 1 ) {
    print "<input type=hidden name=\"accttype\" value=\"checking\">\n";
    if ( $commcardtype ne "" ) {
      print "<input type=hidden name=\"checktype\" value=\"CCD\">\n";
    } else {
      print "<input type=hidden name=\"checktype\" value=\"PPD\">\n";
    }
  } else {
    print "<br>CVV: <input type=text name=\"card_cvv\" size=4 value=\"\" maxlength=4 autocomplete=\"off\">\n";
  }
  print "<br>Acct Code: <input type=text name=\"acct_code\" size=19 maxlength=26 value=\"$acct_code\">\n";
  print "<br>Email: <input type=checkbox name=\"sndemailflg\" value=\"1\"> Check to have email confirmations sent.\n";
  print
    "<br>Receipt Type: <input type=radio name=\"receipt_type\" value=\"\" checked> None &nbsp; <input type=radio name=\"receipt_type\" value=\"simple\"> Std. Printer &nbsp; <input type=radio name=\"receipt_type\" value=\"pos_simple\"> Receipt Printer\n";
  print "<p><input type=submit class=\"button\" name=\"submit\" value=\"Submit Payment\"> <input type=reset class=\"button\" value=\"Clear Form\">\n";
  print "<br>* <u>NOTE:</u> <i>Bill Member authorizations DO NOT extend the profile's Next Payment (End Date)</i>\n";
  print "</form>\n";
  print "</fieldset>\n";
  print "</div>\n";

  print "</td>\n";
  print "  </tr>\n";

  print "</table>\n";
  print "</fieldset>\n";

  print "</td>\n";
  print "  </tr>\n";
  print "<!-- end table entry -->\n";

  return;
}

sub search {
  ($today) = &miscutils::gendatetime_only();

  $srch_username = &CGI::escapeHTML( $query->param("srch_username") );
  $srch_username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $srch_cardnumber = &CGI::escapeHTML( $query->param('srch_cardnumber') );
  $srch_cardnumber =~ s/[^0-9]//g;

  $srch_email = &CGI::escapeHTML( $query->param("srch_email") );
  $srch_email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $srch_expired = &CGI::escapeHTML( $query->param("srch_expired") );
  $srch_expired =~ s/[^a-zA-Z0-9\_\-]//g;

  $srch_exact = &CGI::escapeHTML( $query->param("srch_exact") );
  $srch_exact =~ s/[^a-zA-Z0-9\_\-]//g;

  $srch_status =~ &CGI::escapeHTML( $query->param("srch_status") );
  $srch_status =~ s/[^a-zA-Z0-9\_\-]//g;

  &html_head( "Customer Administration", "Customer Search Results" );
  print "<table border=0 cellspacing=0 cellpadding=1 width=760>\n";

  # get table column names
  my $sth = $dbh_plus->prepare(
    q{
      SELECT * 
      FROM customer
      LIMIT 1
    }
    )
    or die "Can't prepare: $DBI::errstr";
  my $rv = $sth->execute() or die "Can't execute: $DBI::errstr";
  my $results = $sth->fetchrow_hashref();
  $sth->finish;

  # now do the search
  my $search_string =
    "SELECT username,company,orderid,name,addr1,addr2,city,state,zip,country,password,email,startdate,enddate,monthly,cardnumber,exp,lastbilled,status,billcycle,purchaseid,enccardnumber,length";
  if ( exists $results->{'commcardtype'} ) {
    $search_string .= ",commcardtype";
  }
  $search_string .= " FROM customer";

  $op = "WHERE";
  @search_array = ( "username", "password", "name", "email", "addr1", "addr2", "city", "state", "zip", "orderid", "status", "cardnumber", "purchaseid", "acct_code" );
  if ( $srch_cardnumber ne "" ) {
    $srch_cardnumber = substr( $srch_cardnumber, 0, 4 ) . "**" . substr( $srch_cardnumber, -2, 2 );
    $query->param( 'srch_cardnumber', $srch_cardnumber );
  }
  if ( $user1 ne "" ) {
    push( @search_array, "$user1" );
  }
  if ( $user2 ne "" ) {
    push( @search_array, "$user2" );
  }
  if ( $user3 ne "" ) {
    push( @search_array, "$user3" );
  }
  if ( $user4 ne "" ) {
    push( @search_array, "$user4" );
  }
  my $logger = new PlugNPay::Logging::DataLog( { 'collection' => 'plusutils_feature_usage' } );
  if ( $user1 ne ""
    || $user2 ne ""
    || $user3 ne ""
    || $user4 ne "" ) {
    $logger->log(
      { 'message'      => 'search contains user defined columns',
        'search_array' => \@search_array
      },
      { stackTraceEnabled => 1 }
    );
  }

  $i = 0;
  foreach my $var (@search_array) {
    if ( &CGI::escapeHTML( $query->param("srch_$var") ) ne "" ) {
      $search_string .= " $op lower($var) like lower(?)";
      $op = "AND";
      if ( $srch_exact eq "yes" ) {
        push( @bind_values, &CGI::escapeHTML( $query->param("srch_$var") ) );
      } else {
        push( @bind_values, "%" . &CGI::escapeHTML( $query->param("srch_$var") ) . "%" );
      }
      $i++;
    }
  }

  if ( $srch_expired eq "yes" ) {
    $search_string .= " $op enddate<'$today'";
  }

  $search_string .= " order by username";

  $sth = $dbh_plus->prepare(qq{ $search_string }) or die "Can't do: $DBI::errstr";
  $sth->execute(@bind_values) or die "Can't execute: $DBI::errstr";
  if ( exists $results->{'commcardtype'} ) {
    $sth->bind_columns(
      undef,
      \($username, $company, $orderid, $name,       $addr1, $addr2,      $city,   $state,     $zip,        $country,       $password, $email,
        $start,    $end,     $monthly, $cardnumber, $exp,   $lastbilled, $status, $billcycle, $purchaseid, $enccardnumber, $length,   $commcardtype
       )
    );
  } else {
    $sth->bind_columns(
      undef,
      \($username, $company, $orderid, $name,       $addr1, $addr2,      $city,   $state,     $zip,        $country,       $password, $email,
        $start,    $end,     $monthly, $cardnumber, $exp,   $lastbilled, $status, $billcycle, $purchaseid, $enccardnumber, $length
       )
    );
  }
  $i = 0;
  while ( $sth->fetch ) {

    #print "DBASE:$database, $username,$company,$orderid<br>\n";

    my $cd                 = new PlugNPay::CardData();
    my $ecrypted_card_data = '';
    eval { $ecrypted_card_data = $cd->getRecurringCardData( { customer => "$username", username => "$database" } ); };
    if ( !$@ ) {
      $enccardnumber = $ecrypted_card_data;
    }

    if ( $srch_status ne "pending" ) {
      &write_table_entry;
    } else {
      &write_table_entry_pending;
    }
    $i++;
    if ( $i > 500 ) {
      last;
    }
  }
  $sth->finish;

  if ( $i == 0 ) {
    print "  <tr>\n";
    print "    <th>Sorry - No records match your request.</th>\n";
    print "</tr>";
  }

  print "</table><p>\n";

  print "<div align=center>\n";
  print "<form action=\"index.cgi\"><input type=submit class=\"button\" value=\"Go To Main Page\"></form>\n";
  print "<br>\n";
  print "</div>\n";

  &html_tail();

  $dbh_plus->disconnect;
}

sub update {
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $name = &CGI::escapeHTML( $query->param('name') );
  $name =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  $company = &CGI::escapeHTML( $query->param('company') );
  $company =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  $addr1 = &CGI::escapeHTML( $query->param('addr1') );
  $addr1 =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  $addr2 = &CGI::escapeHTML( $query->param('addr2') );
  $addr2 =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  $city = &CGI::escapeHTML( $query->param('city') );
  $city =~ s/[^a-zA-Z0-9\.\-\' ]/ /g;

  $state = &CGI::escapeHTML( $query->param('state') );
  $state =~ s/[^a-zA-Z\' ]/ /g;

  $zip = &CGI::escapeHTML( $query->param('zip') );
  $zip =~ s/[^a-zA-Z\'0-9 ]/ /g;

  $country = &CGI::escapeHTML( $query->param('country') );
  $country =~ s/[^a-zA-Z\' ]/ /g;

  $shipname = &CGI::escapeHTML( $query->param('shipname') );
  $shipname =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  $shipaddr1 = &CGI::escapeHTML( $query->param('shipaddr1') );
  $shipaddr1 =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  $shipaddr2 = &CGI::escapeHTML( $query->param('shipaddr2') );
  $shipaddr2 =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  $shipcity = &CGI::escapeHTML( $query->param('shipcity') );
  $shipcity =~ s/[^a-zA-Z0-9\.\-\' ]/ /g;

  $shipstate = &CGI::escapeHTML( $query->param('shipstate') );
  $shipstate =~ s/[^a-zA-Z\' ]/ /g;

  $shipzip = &CGI::escapeHTML( $query->param('shipzip') );
  $shipzip =~ s/[^a-zA-Z\'0-9 ]/ /g;

  $shipcountry = &CGI::escapeHTML( $query->param('shipcountry') );
  $shipcountry =~ s/[^a-zA-Z\' ]/ /g;

  $phone = &CGI::escapeHTML( $query->param('phone') );
  $phone =~ s/[^a-zA-Z0-9\-\ ]/ /g;

  $fax = &CGI::escapeHTML( $query->param('fax') );
  $fax =~ s/[^a-zA-Z0-9\-\ ]/ /g;

  $email = &CGI::escapeHTML( $query->param('email') );
  $email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $cardnumber = &CGI::escapeHTML( $query->param('cardnumber') );
  $cardnumber =~ s/[^0-9\*]//g;

  $user1_val = &CGI::escapeHTML( $query->param("$user1") );
  $user1_val =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,\|]//g;

  $user2_val = &CGI::escapeHTML( $query->param("$user2") );
  $user2_val =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,\|]//g;

  $user3_val = &CGI::escapeHTML( $query->param("$user3") );
  $user3_val =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,\|]//g;

  $user4_val = &CGI::escapeHTML( $query->param("$user4") );
  $user4_val =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,\|]//g;

  $password = &CGI::escapeHTML( $query->param('password') );
  $password =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  $purchaseid = &CGI::escapeHTML( $query->param('purchaseid') );
  $purchaseid =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,\|]//g;

  $exp = &CGI::escapeHTML( $query->param('exp') );
  $exp =~ s/[^0-9\/]//g;

  $monthly = &CGI::escapeHTML( $query->param('monthly') );
  $monthly =~ s/[^a-zA-Z0-9\.\ ]//g;

  $balance = &CGI::escapeHTML( $query->param('balance') );
  $balance =~ s/[^0-9\.]//g;

  $billcycle = &CGI::escapeHTML( $query->param('billcycle') );
  $billcycle =~ s/[^0-9\.]//g;

  $status = &CGI::escapeHTML( $query->param('status') );
  $status =~ s/[^a-zA-Z0-9\_\-]//g;

  $acct_code = &CGI::escapeHTML( $query->param('acct_code') );
  $acct_code =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,\|]/ /g;

  # ACH - Online Checking Fields
  $routingnum = &CGI::escapeHTML( $query->param('routingnum') );
  $routingnum =~ s/[^0-9]//g;

  $accountnum = &CGI::escapeHTML( $query->param('accountnum') );
  $accountnum =~ s/[^0-9]//g;

  if ( ( $routingnum ne "" ) && ( $accountnum ne "" ) ) {
    $cardnumber = sprintf( "%s %s", $routingnum, $accountnum );
    $exp = "";    # remove CC exp data, since an ACH account was entered
  }

  if ( ( $status eq "cancelled" ) && ( $billcycle ne "0" ) ) {
    $billcycle = "0";
  }

  ## do special commcardtype work here...
  if ( ( $user1 eq "commcardtype" ) || ( $user2 eq "commcardtype" ) || ( $user3 eq "commcardtype" ) || ( $user4 eq "commcardtype" ) ) {
    my $commcardtype = &CGI::escapeHTML( $query->param('commcardtype') );
    $commcardtype =~ s/[^a-zA-Z0-9\_\-]//g;

    my $commcardtype_ach = &CGI::escapeHTML( $query->param('commcardtype_ach') );
    $commcardtype_ach =~ s/[^a-zA-Z0-9\_\-]//g;

    my $commcardtype_cc = &CGI::escapeHTML( $query->param('commcardtype_cc') );
    $commcardtype_cc =~ s/[^a-zA-Z0-9\_\-]//g;

    if ( $commcardtype_ach =~ /\w/ ) {
      $commcardtype = $commcardtype_ach;
    } elsif ( $commcardtype_cc =~ /\w/ ) {
      $commcardtype = $commcardtype_cc;
    }

    if ( $user1 eq "commcardtype" ) { $user1_val = $commcardtype; }
    if ( $user2 eq "commcardtype" ) { $user2_val = $commcardtype; }
    if ( $user3 eq "commcardtype" ) { $user3_val = $commcardtype; }
    if ( $user4 eq "commcardtype" ) { $user4_val = $commcardtype; }
  }

  $_ = &CGI::escapeHTML( $query->param('start') );
  my ( $mmonth, $dday, $yyear ) = split(/\//);
  if ( $yyear < 100 ) {

    # see if entered a 2-digit year; if necessary adjust to correct 4-digit year
    $yyear = $yyear + 2000;
  }
  if ( $_ ne "" ) {
    $start = sprintf( "%04d%02d%02d", $yyear, $mmonth, $dday );
  }

  $_ = &CGI::escapeHTML( $query->param('end') );
  ( $mmonth, $dday, $yyear ) = split(/\//);
  if ( $yyear < 100 ) {

    # see if entered a 2-digit year; if necessary adjust to correct 4-digit year
    $yyear = $yyear + 2000;
  }
  if ( $_ ne "" ) {
    $end = sprintf( "%04d%02d%02d", $yyear, $mmonth, $dday );
  }

  $_ = &CGI::escapeHTML( $query->param('lastbilled') );
  ( $mmonth, $dday, $yyear ) = split(/\//);
  if ( $yyear < 100 ) {

    # see if entered a 2-digit year; if necessary adjust to correct 4-digit year
    $yyear = $yyear + 2000;
  }
  if ( $_ ne "" ) {
    $lastbilled = sprintf( "%04d%02d%02d", $yyear, $mmonth, $dday );
  }

  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $cardlength = length $cardnumber;
  if ( ( $cardnumber !~ /\*\*/ ) && ( $cardlength > 8 ) ) {

    #($enccardnumber,$encryptedDataLen) = &rsautils::rsa_encrypt_card($cardnumber,"/home/p/pay1/web/payment/recurring/$merchant/admin/key");
    ( $enccardnumber, $encryptedDataLen ) = &rsautils::rsa_encrypt_card( $cardnumber, "/home/p/pay1/pwfiles/keys/key" );
    $encryptedDataLen = "$encryptedDataLen";

    $enccardnumber = substr( $enccardnumber, 0, 128 );
    $enccardnumber = &smpsutils::storecardnumber( $database, $username, 'plus_update', $enccardnumber, 'rec' );

    my $sth = $dbh_plus->prepare(
      q{
        UPDATE customer
        SET enccardnumber=?,length=?
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( "$enccardnumber", "$encryptedDataLen", "$username" ) or die "Can't execute: $DBI::errstr";
    $sth->finish;

  }

  $cardnumber = substr( $cardnumber, 0, 4 ) . '**' . substr( $cardnumber, length($cardnumber) - 2, 2 );

  $querystring =
    "UPDATE customer set name=?,company=?,addr1=?,addr2=?,city=?,state=?,zip=?,country=?,phone=?,fax=?,email=?,startdate=?,enddate=?,monthly=?,cardnumber=?,exp=?,lastbilled=?,password=?,purchaseid=?,billcycle=?,shipname=?,shipaddr1=?,shipaddr2=?,shipcity=?,shipstate=?,shipzip=?,shipcountry=?,status=?,acct_code=?";
  @execstring = (
    "$name",     "$company",   "$addr1",     "$addr2",    "$city",       "$state",   "$zip",         "$country",  "$phone",      "$fax",
    "$email",    "$start",     "$end",       "$monthly",  "$cardnumber", "$exp",     "$lastbilled",  "$password", "$purchaseid", "$billcycle",
    "$shipname", "$shipaddr1", "$shipaddr2", "$shipcity", "$shipstate",  "$shipzip", "$shipcountry", "$status",   "$acct_code"
  );

  if ( ( $user1 ne "" ) || ( $user2 ne "" ) || ( $user3 ne "" ) || ( $user4 ne "" ) ) {

    # hold list of standard columns to exclude from user's custom column list
    my $standard_cols =
      "name|orderid|company|addr1|addr2|city|state|zip|country|phone|fax|email|startdate|enddate|monthly|balance|cardnumber|exp|lastbilled|password|purchaseid|billcycle|shipname|shipaddr1|shipaddr2|shipcity|shipstate|shipzip|shipcountry|status|acct_code";

    # remove standard columns from user's custom column list; which prevents data mess-ups in legacy MM setups.
    if ( ( $user1 ne "" ) && ( $user1 =~ /^($standard_cols)$/ ) ) { $user1 = ""; }
    if ( ( $user2 ne "" ) && ( $user2 =~ /^($standard_cols)$/ ) ) { $user2 = ""; }
    if ( ( $user3 ne "" ) && ( $user3 =~ /^($standard_cols)$/ ) ) { $user3 = ""; }
    if ( ( $user4 ne "" ) && ( $user4 =~ /^($standard_cols)$/ ) ) { $user4 = ""; }
  }

  if ( $user1 ne "" ) {
    $querystring .= ",$user1=?";
    push( @execstring, "$user1_val" );
  }
  if ( $user2 ne "" ) {
    $querystring .= ",$user2=?";
    push( @execstring, "$user2_val" );
  }
  if ( $user3 ne "" ) {
    $querystring .= ",$user3=?";
    push( @execstring, "$user3_val" );
  }
  if ( $user4 ne "" ) {
    $querystring .= ",$user4=?";
    push( @execstring, "$user4_val" );
  }

  #print "AS:$querystring<p>\n";
  $querystring .= " WHERE username=?";
  push( @execstring, "$username" );

  $sth = $dbh_plus->prepare(qq{ $querystring }) or die "Can't prepare: $DBI::errstr";
  $sth->execute(@execstring) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  if ( $receditutils::installbilling eq "yes" ) {
    my $sth_install = $dbh_plus->prepare(
      q{
        UPDATE customer
        SET balance=?
        WHERE username=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth_install->execute( "$balance", "$username" ) or die "Can't execute: $DBI::errstr";
    $sth_install->finish;
  }

  &viewcustomer();

  $reason = "Edited";
  &record_history( "$username", "Information Updated", "$reason" );

  return;
}

sub editrecord {

  # 03/19/11 - This snipit of code, addresses situations where username must be passed
  # Username variable should not be overwritten, when username was not passed; as the username varible is already set in memory
  my ($temp_username) = @_;
  if ( $temp_username =~ /\w/ ) {
    $username = $temp_username;
  }

  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  my $sth = $dbh_plus->prepare(
    q{
      SELECT name,orderid,company,addr1,addr2,city,state,zip,country,phone,fax,email,startdate,enddate,monthly,cardnumber,exp,enccardnumber,length,lastbilled,password,purchaseid,billcycle,shipname,shipaddr1,shipaddr2,shipcity,shipstate,shipzip,shipcountry,status,acct_code
      FROM customer
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute("$username");
  my (
    $name,      $orderid,  $company,   $addr1,     $addr2,      $city,      $state,         $zip,         $country,    $phone,    $fax,
    $email,     $start,    $end,       $monthly,   $cardnumber, $exp,       $enccardnumber, $length,      $lastbilled, $password, $purchaseid,
    $billcycle, $shipname, $shipaddr1, $shipaddr2, $shipcity,   $shipstate, $shipzip,       $shipcountry, $status,     $acct_code
    )
    = $sth->fetchrow;
  $sth->finish;

  my $cd                 = new PlugNPay::CardData();
  my $ecrypted_card_data = '';
  eval { $ecrypted_card_data = $cd->getRecurringCardData( { customer => "$username", username => "$database", suppressAlert => 1, suppressError => 1 } ); };
  if ( !$@ ) {
    $enccardnumber = $ecrypted_card_data;
  }

  if ( $receditutils::installbilling eq "yes" ) {
    my $sth_install = $dbh_plus->prepare(
      q{
        SELECT balance
        FROM customer
        WHERE username=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth_install->execute("$username") or die "Can't execute: $DBI::errstr";
    ($balance) = $sth_install->fetchrow;
    $sth_install->finish;
  }

  my $is_ach          = 0;
  my $temp_routingnum = "";
  my $temp_accountnum = "";

  if ( $enccardnumber ne "" ) {

    # decrypt card on file & see if its an Credit Card or ACH/eCheck account.
    my $temp_cc = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
    if ( $temp_cc =~ /\W/ ) {
      $is_ach = 1;
      ( $temp_routingnum, $temp_accountnum ) = split( / /, $temp_cc, 2 );

      # Account number filter
      $temp_accountnum =~ s/[^0-9]//g;
      $temp_accountnum = substr( $temp_accountnum, 0, 20 );
      my ($accountnum) = $temp_accountnum;
      my $acctlength = length($accountnum);
      my $last4 = substr( $accountnum, -4, 4 );
      $accountnum =~ s/./X/g;
      $temp_accountnum = substr( $accountnum, 0, $acctlength - 4 ) . $last4;

      # Routing number filter
      $temp_routingnum =~ s/[^0-9]//g;
      $temp_routingnum = substr( $temp_routingnum, 0, 9 );
      my ($routingnum) = $temp_routingnum;
      my $routlength = length($routingnum);
      my $first4 = substr( $routingnum, 0, 4 );
      $routingnum =~ s/./X/g;
      $temp_routingnum = $first4 . substr( $routingnum, 4, $routlength - 4 );
    }
    $temp_cc = "";    # destroy decrypted card info, since its no longer needed.
  }

  my ( $dummy, $user1_val, $user2_val, $user3_val, $user4_val );

  # perform custom columns query here...
  if ( ( $receditutils::user1 ne "" ) || ( $receditutils::user2 ne "" ) || ( $receditutils::user3 ne "" ) || ( $receditutils::user4 ne "" ) ) {

    # hold list of standard columns to exclude from user's custom column list
    my $standard_cols =
      "name|orderid|company|addr1|addr2|city|state|zip|country|phone|fax|email|startdate|enddate|monthly|balance|cardnumber|exp|lastbilled|password|purchaseid|billcycle|shipname|shipaddr1|shipaddr2|shipcity|shipstate|shipzip|shipcountry|status|acct_code";

    # remove standard columns from user's custom column list; which prevents duplicate fields showing up in legacy MM setups.
    if ( ( $receditutils::user1 ne "" ) && ( $receditutils::user1 =~ /^($standard_cols)$/ ) ) { $receditutils::user1 = ""; }
    if ( ( $receditutils::user2 ne "" ) && ( $receditutils::user2 =~ /^($standard_cols)$/ ) ) { $receditutils::user2 = ""; }
    if ( ( $receditutils::user3 ne "" ) && ( $receditutils::user3 =~ /^($standard_cols)$/ ) ) { $receditutils::user3 = ""; }
    if ( ( $receditutils::user4 ne "" ) && ( $receditutils::user4 =~ /^($standard_cols)$/ ) ) { $receditutils::user4 = ""; }

    # query any remaining custom columns as necessary
    if ( $receditutils::user1 ne "" ) {
      my $querystring = "select $receditutils::user1 from customer where username=?";
      $sth = $dbh_plus->prepare(qq{ SELECT $receditutils::user1 FROM customer WHERE username=? }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$username");
      $user1_val = $sth->fetchrow;
      $sth->finish;
    }

    if ( $receditutils::user2 ne "" ) {
      $sth = $dbh_plus->prepare(qq{ SELECT $receditutils::user2 FROM customer WHERE username=? }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$username");
      $user2_val = $sth->fetchrow;
      $sth->finish;
    }

    if ( $receditutils::user3 ne "" ) {
      $sth = $dbh_plus->prepare(qq{ SELECT $receditutils::user3 FROM customer WHERE username=? }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$username");
      $user3_val = $sth->fetchrow;
      $sth->finish;
    }

    if ( $receditutils::user4 ne "" ) {
      $sth = $dbh_plus->prepare(qq{ SELECT $receditutils::user4 FROM customer WHERE username=? }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$username");
      $user4_val = $sth->fetchrow;
      $sth->finish;
    }
  }

  if ( $start ne "" ) {
    $start = sprintf( "%02d/%02d/%04d", substr( $start, 4, 2 ), substr( $start, 6, 2 ), substr( $start, 0, 4 ) );
  }
  if ( $end ne "" ) {
    $end = sprintf( "%02d/%02d/%04d", substr( $end, 4, 2 ), substr( $end, 6, 2 ), substr( $end, 0, 4 ) );
  }
  if ( $lastbilled ne "" ) {
    $lastbilled = sprintf( "%02d/%02d/%04d", substr( $lastbilled, 4, 2 ), substr( $lastbilled, 6, 2 ), substr( $lastbilled, 0, 4 ) );
  }

  # figure out if merchant should be given ACH option
  $achstatus = "";

  $dbh2 = &miscutils::dbhconnect("pnpmisc");
  my $sth2 = $dbh2->prepare(
    q{
      SELECT chkprocessor
      FROM customers
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth2->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
  my ($chkprocessor) = $sth2->fetchrow;
  $sth2->finish;

  if ( $chkprocessor eq "" ) {
    $chkprocessor = "ach";
  }

  if ( $chkprocessor =~ /^testprocessor/ ) {
    $achstatus = "enabled";
  } else {
    my $sth_ach = $dbh2->prepare(
      qq{
        SELECT status
        FROM $chkprocessor
        WHERE username=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth_ach->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
    ($achstatus) = $sth_ach->fetchrow;
    $sth_ach->finish;
  }
  $dbh2->disconnect;

  &html_head( "Membership Management - Edit Customer", "Edit Customer Information" );

  print "<!-- start edit record form -->\n";
  print "<form method=post action=\"editcust.cgi\" name=\"editcust\" onSubmit=\"return rec_luhn10(document.editcust.cardnumber.value);\">\n";
  print "<input type=hidden name=\"username\" value=\"$username\">\n";
  print "<input type=hidden name=\"function\" value=\"update\">\n";
  print "<input type=hidden name=\"lastbilled\" value=\"$lastbilled\">\n";

  print "<table border=0 cellspacing=0 cellpadding=0 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=2>Please enter the profile information below.</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th align=left colspan=2>Login Information</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Username:</td>\n";
  print "    <td>$username</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Password:</td>\n";
  print "    <td><input type=text name=\"password\" size=30 maxlength=39 value=\"$password\" autocomplete=\"off\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th align=left colspan=2>Billing Address Information</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Company:</td>\n";
  print "    <td><input type=text name=\"company\" size=30 maxlength=39 value=\"$company\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Customer Name:</td>\n";
  print "    <td><input type=text name=\"name\" size=30 maxlength=39 value=\"$name\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Address 1:</td>\n";
  print "    <td><input type=text name=\"addr1\" size=30 maxlength=39 value=\"$addr1\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Address 2:</td>\n";
  print "    <td><input type=text name=\"addr2\" size=30 maxlength=39 value=\"$addr2\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>City:</td>\n";
  print "    <td><input type=text name=\"city\" size=20 maxlength=39 value=\"$city\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>State:</td>\n";
  print "    <td><input type=text name=\"state\" size=3 maxlength=3 value=\"$state\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Zip:</td>\n";
  print "    <td><input type=text name=\"zip\" size=10 maxlength=15 value=\"$zip\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Country Code:</td>\n";
  print "    <td><input type=text name=\"country\" size=3 maxlength=20 value=\"$country\"></td>\n";
  print "  </tr>\n";

  if ( $ENV{'REMOTE_USER'} !~ /^(lp1847092)$/ ) {
    print "  <tr>\n";
    print "    <th align=left colspan=2>Shipping Address Information (optional)</th>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>Name:</td>\n";
    print "    <td><input type=text name=\"shipname\" size=30 maxlength=39 value=\"$shipname\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>Address 1:</td>\n";
    print "    <td><input type=text name=\"shipaddr1\" size=30 maxlength=39 value=\"$shipaddr1\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>Address 2:</td>\n";
    print "    <td><input type=text name=\"shipaddr2\" size=30 maxlength=39 value=\"$shipaddr2\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>City:</td>\n";
    print "    <td><input type=text name=\"shipcity\" size=20 maxlength=39 value=\"$shipcity\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>State:</td>\n";
    print "    <td><input type=text name=\"shipstate\" size=3 maxlengh=3 value=\"$shipstate\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>Zip:</td>\n";
    print "    <td><input type=text name=\"shipzip\" size=10 maxlength=15 value=\"$shipzip\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>Country Code:</td>\n";
    print "    <td><input type=text name=\"shipcountry\" size=3 maxlength=20 value=\"$shipcountry\"></td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <th align=left colspan=2>Instant Contact Information (optional)</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Phone \#:</td>\n";
  print "    <td><input type=text name=\"phone\" size=20 maxlength=20 value=\"$phone\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>FAX \#:</td>\n";
  print "    <td><input type=text name=\"fax\" size=20 maxlength=20 value=\"$fax\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Email:</td>\n";
  print "    <td><input type=text name=\"email\" size=49 maxlength=49 value=\"$email\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>&nbsp;</td>\n";
  print "    <td>&nbsp;</td>\n";
  print "  </tr>\n";

  if ( $cardnumber =~ /\d/ ) {
    print "  <tr>\n";
    print "    <td colspan=2 align=center>";
    print "<table width=500 style=\"border: 1px solid #000;\">\n";
    print "  <tr style=\"border-width: 0px;\">\n";
    print "    <th colspan=2 align=center>The profile is presently set to use following payment type:</th>\n";
    print "  </tr>\n";
    if ( $is_ach == 1 ) {
      print "  <tr style=\"border-width: 0px;\">\n";
      print "    <th width=\"35%\" align=right>ACH Routing #:</th>\n";
      print "    <td>$temp_routingnum</td>\n";
      print "  </tr>\n";
      print "  <tr style=\"border-width: 0px;\">\n";
      print "    <th align=right>Account #:</th>\n";
      print "    <td>$temp_accountnum</td>\n";
      print "  </tr>\n";
    } else {
      print "  <tr style=\"border-width: 0px;\">\n";
      print "    <th width=\"35%\" align=right>Card Number:</th>\n";
      print "    <td>$cardnumber</td>\n";
      print "  </tr>\n";
      print "  <tr style=\"border-width: 0px;\">\n";
      print "    <th align=right>Exp Date:</th>\n";
      print "    <td>$exp</td>\n";
      print "  </tr>\n";
    }
    print "</table>\n";
    print "</td>\n";
    print "  </tr>\n";
  }

  if ( $achstatus eq "enabled" ) {
    print "  <tr>\n";
    print "    <th align=left colspan=2>ACH Billing Information</th>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2>* NOTE: Routing/Account number fields are for data entry only.  Once entered, the data is stored in credit card number field.</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>Routing \#:</td>\n";
    print "    <td><input type=text name=\"routingnum\" size=9 maxlength=9 value=\"$routingnum\" autocomplete=\"off\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=right>Bank Account \#:</td>\n";
    print "    <td><input type=text name=\"accountnum\" size=9 maxlength=20 value=\"$accountnum\" autocomplete=\"off\"></td>\n";
    print "  </tr>\n";

    if ( ( $receditutils::user1 eq "commcardtype" ) || ( $receditutils::user2 eq "commcardtype" ) || ( $receditutils::user3 eq "commcardtype" ) || ( $receditutils::user4 eq "commcardtype" ) ) {
      print "  <tr>\n";
      print "    <td align=right>&nbsp;</td>";
      print "    <td><input type=checkbox name=\"commcardtype_ach\" value=\"business\"";
      if ( $is_ach == 1 ) {
        if    ( ( $receditutils::user1 eq "commcardtype" ) && ( $user1_val eq "business" ) ) { print " checked"; }
        elsif ( ( $receditutils::user2 eq "commcardtype" ) && ( $user2_val eq "business" ) ) { print " checked"; }
        elsif ( ( $receditutils::user3 eq "commcardtype" ) && ( $user3_val eq "business" ) ) { print " checked"; }
        elsif ( ( $receditutils::user4 eq "commcardtype" ) && ( $user4_val eq "business" ) ) { print " checked"; }
      }
      print "> Check when ACH account is a Commercial/Business account.</td>\n";
      print "  </tr>\n";
    }
  }

  print "  <tr>\n";
  print "    <th align=left colspan=2>Credit Card Information</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Card Number:</td>\n";
  print "    <td><input type=text id=\"cardnumber\" name=\"cardnumber\" size=20 maxlength=20 value=\"$cardnumber\" autocomplete=\"off\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Expiration Date:</td>\n";
  print "    <td><input type=text name=\"exp\" size=6 maxlength=5 value=\"$exp\" autocomplete=\"off\"> <i>MM/YY</i></td>\n";
  print "  </tr>\n";

  #if ($accttype eq "") { $accttype = "credit"; }
  #$selected{"$accttype"} = " selected";
  #print "  <tr>\n";
  #print "    <td align=right>Billing Account Type:</td>\n";
  #print "    <td><select name=\"accttype\">\n";
  #print "<option value=\"credit\" $selected{'credit'}>Credit Card</option>\n";
  #print "<option value=\"checking\"$selected{'checking'}>Checking Account</option>\n";
  #print "<option value=\"savings\" $selected{'savings'}>Savings Account</option>\n";
  #print "</select></td>\n";
  #print "  </tr>\n";

  if ( ( $receditutils::user1 eq "commcardtype" ) || ( $receditutils::user2 eq "commcardtype" ) || ( $receditutils::user3 eq "commcardtype" ) || ( $receditutils::user4 eq "commcardtype" ) ) {
    print "  <tr>\n";
    print "    <td align=right>&nbsp;</td>";
    print "    <td><input type=checkbox name=\"commcardtype_cc\" value=\"business\"";
    if ( $is_ach == 0 ) {
      if    ( ( $receditutils::user1 eq "commcardtype" ) && ( $user1_val eq "business" ) ) { print " checked"; }
      elsif ( ( $receditutils::user2 eq "commcardtype" ) && ( $user2_val eq "business" ) ) { print " checked"; }
      elsif ( ( $receditutils::user3 eq "commcardtype" ) && ( $user3_val eq "business" ) ) { print " checked"; }
      elsif ( ( $receditutils::user4 eq "commcardtype" ) && ( $user4_val eq "business" ) ) { print " checked"; }
    }
    print "> Check when Credit Card account is a Commercial/Purchase Card.</td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <th align=left colspan=2>Profile Billing Information</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Sign-up Date:<br>(start date)</td>\n";
  print "    <td><input type=text name=\"start\" size=11 maxlength=10 value=\"$start\"> <i>MM/DD/YYYY</i></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Next Scheduled Payment:<br>(end date)</td>\n";
  print "    <td><input type=text name=\"end\" size=11 maxlength=10 value=\"$end\"> <i>MM/DD/YYYY</i></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Last Billed:</td>\n";
  print "    <td>$lastbilled</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Recurring Fee:</td>\n";
  print "    <td><input type=text name=\"monthly\" size=8 maxlength=20 value=\"$monthly\"></td>\n";
  print "  </tr>\n";

  if ( $receditutils::installbilling eq "yes" ) {
    print "  <tr>\n";
    print "    <td align=right>Balance:</td>\n";
    print "    <td><input type=text name=\"balance\" size=8 maxlength=20 value=\"$balance\"></td>\n";
    print "  </tr>\n";
  }

  if ( $billcycle <= 0 ) {
    $billcycle = 0;
  }

  print "  <tr>\n";
  print "    <td align=right>Billing Cycle:</td>\n";
  print "    <td>$billcycle Month(s)\n";
  print "<br><select name=\"billcycle\">\n";

  if ( $ENV{'REMOTE_USER'} =~ /^(jamestu2|lp1847092|cosmicnexu|887thebrid|lp2207932|lp2377917|lp2382768|ams1580784|lp2066825|lp2420170|lp2488235)$/ ) {
    print "<option value=\"0.25\"";
    if ( $billcycle == .25 ) { print "selected"; }
    print ">4x Per Month [Days In Month Divisible By 4]</option>\n";

    print "<option value=\"0.333\"";
    if ( $billcycle == .333 ) { print "selected"; }
    print ">3x Per Month [Days In Month Divisible By 3]</option>\n";

    print "<option value=\"0.50\"";
    if ( $billcycle == .50 ) { print "selected"; }
    print ">2x Per Month [Days In Month Divisible By 2]</option>\n";
  }

  for ( my $i = 0 ; $i <= 36 ; $i++ ) {
    print "<option value=\"$i\" ";
    if ( $i == $billcycle ) { print "selected"; }
    if ( $i == 0 ) {
      print ">$i Months [Non-Recur Billing]</option>\n";
    } elsif ( ( $i == 12 ) || ( $i == 24 ) || ( $i == 36 ) ) {
      $j = $i / 12;
      print ">$i Months [$j Years]</option>\n";
    } else {
      print ">$i Months</option>\n";
    }
  }
  print "</select></td>\n";
  print "  </tr>\n";

  my %selected;
  if ( $status !~ /\w/ ) {
    $status = "active";
  }
  $selected{"$status"} = "checked";

  print "  <tr>\n";
  print "    <td align=right>Billing Status:</td>\n";
  print "    <td><input type=radio name=\"status\" value=\"active\" $selected{'active'}> Active\n";
  print "      <input type=radio name=\"status\" value=\"cancelled\" $selected{'cancelled'}> Cancelled";
  print "      <input type=radio name=\"status\" value=\"pending\" $selected{'pending'}> Pending</td>";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>PurchaseID\:</td>\n";
  print "    <td><input type=text name=\"purchaseid\" size=19 maxlength=39 value=\"$purchaseid\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=right>Account Code\:</td>\n";
  print "    <td><input type=text name=\"acct_code\" size=19 maxlength=39 value=\"$acct_code\"></td>\n";
  print "  </tr>\n";

  if ( ( $receditutils::user1 ne "" ) && ( $receditutils::user1 ne "commcardtype" ) ) {
    print "  <tr>\n";
    printf( "    <td align=right>%15s\:</td>", $receditutils::user1 );
    if ( $merchant =~ /(isi|infinity|mystique)/i ) {
      print "    <td><input type=text name=\"$receditutils::user1\" size=19 maxlength=254 value=\"$user1_val\"></td>\n";
    } else {
      print "    <td><input type=text name=\"$receditutils::user1\" size=19 maxlength=79 value=\"$user1_val\"></td>\n";
    }
    print "  </tr>\n";
  }

  if ( ( $receditutils::user2 ne "" ) && ( $receditutils::user2 ne "commcardtype" ) ) {
    print "  <tr>\n";
    printf( "    <td align=right>%15s\:</td>", $receditutils::user2 );
    if ( $merchant =~ /(tntclub)/i ) {
      print "    <td><input type=text name=\"$receditutils::user2\" size=19 maxlength=50 value=\"$user2_val\"></td>\n";
    } else {
      print "    <td><input type=text name=\"$receditutils::user2\" size=19 maxlength=39 value=\"$user2_val\"></td>\n";
    }
    print "  </tr>\n";
  }

  if ( ( $receditutils::user3 ne "" ) && ( $receditutils::user3 ne "commcardtype" ) ) {
    print "  <tr>\n";
    printf( "    <td align=right>%15s\:</td>\n", $receditutils::user3 );
    print "    <td><input type=text name=\"$receditutils::user3\" size=19 maxlength=39 value=\"$user3_val\"></td>\n";
    print "  </tr>\n";
  }

  if ( ( $receditutils::user4 ne "" ) && ( $receditutils::user4 ne "commcardtype" ) ) {
    print "  <tr>\n";
    printf( "    <td align=right>%15s\:</td>\n", $receditutils::user4 );
    print "    <td><input type=text name=\"$receditutils::user4\" size=19 maxlength=39 value=\"$user4_val\"></td>\n";
    print "  </tr>\n";
  }

  print "</table>\n";
  print "<br>";

  print "<div align=center>\n";
  print "<input type=submit class=\"button\" value=\"Send Info\">\n";
  print "&nbsp; <input type=reset class=\"button\" value=\"Reset Form\">\n";
  print "&nbsp; <input type=button class=\"button\" value=\"Close Window\" onClick=\"closeresults();\">\n";
  print "</div>\n";
  print "</form>\n";
  print "<br>";
  print "<!-- end edit record form -->\n";

  &html_tail();

  $dbh_plus->disconnect;
  return;
}

sub url_encode {
  foreach my $key ( keys %input ) {
    $name  = $key;
    $value = $input{$key};
    $name =~ s/([^ \w\-.*])/sprintf("%%%2.2X",ord($1))/ge;
    $value =~ s/([^ \w\-.*])/sprintf("%%%2.2X",ord($1))/ge;
    $name =~ s/ /+/g;
    $value =~ s/ /+/g;
    $sub_str .= "$name=$value";
    $sub_str .= '&';
  }
}

sub cancel {
  my $billcycle = "0";
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  my $sth = $dbh_plus->prepare(
    q{
      UPDATE customer
      SET billcycle=?
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$billcycle", "$username" ) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  my $action = "BillCycle Set To 0";
  &record_history( "$username", "$action", "$reason" );

  &response_page("The Recurring Billing for username: $username has been cancelled.");

  return;
}

sub cancel_member {
  $publisher_email = &CGI::escapeHTML( $query->param('publisher-email') );
  $publisher_email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $from_email = &CGI::escapeHTML( $query->param('from-email') );
  $from_email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $email_message = &CGI::escapeHTML( $query->param('email-message') );

  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  my $sth = $dbh_plus->prepare(
    q{
      SELECT username,password,orderid,email
      FROM customer
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  ( $uname, $pword, $orderID, $email ) = $sth->fetchrow;
  $sth->finish;

  if ( ( $uname eq $username ) && ( $password eq $pword ) ) {
    my $sth = $dbh_plus->prepare(
      q{
        UPDATE customer
        SET billcycle='0'
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    $sth->finish;
    $message = "The account for username: $username, has been successfully cancelled.";

    $position = index( $email, "\@" );
    if ( ( $position > 1 ) && ( length($email) > 5 ) && ( $position < ( length($email) - 5 ) ) ) {
      $email           = substr( $email,           0, 50 );
      $publisher_email = substr( $publisher_email, 0, 50 );

      my $emailObj = new PlugNPay::Email('legacy');
      $emailObj->setGatewayAccount($merchant);
      $emailObj->setFormat('text');
      $emailObj->setTo($email);

      if ( $from_email ne "" ) {
        $emailObj->setFrom($from_email);
      } else {
        $emailObj->setFrom($publisher_email);
      }

      $emailObj->setCC($publisher_email);
      $emailObj->setSubject("Membership Cancellation Confirmation");
      $emailObj->setContent($email_message);
    }
    &response_page;
  } else {
    $message = "The Username and Password combination entered were not found in the database.  Please try again and be careful to use the proper CAPITALIZATION.";
    &response_page($message);
  }
  return;
}

sub activate {
  ($mail_message) = @_;

  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  my $sth = $dbh_plus->prepare(
    q{
      UPDATE customer
      SET status='active'
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  $sth->finish;

  $action = "Account Activated";
  &record_history( "$username", "$action", "$reason" );

  if ( $mail_message eq "" ) {
    $mail_message = "This is an automated message from the $site_title membership management system.\n\n
      Your membership to $site_title has been activated.\n\n";
  }

  $subject = "$site_title Membership Activation";
  &email();

  &addtopassword();

  return;
}

sub mailusername {
  $email = &CGI::escapeHTML( $query->param('email') );
  $email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $password = &CGI::escapeHTML( $query->param('password') );
  $password =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $mail_message = "This is an automated message from the membership management system.\n\n
Due to either modifications and/or additions to the membership database,
you have may have been reassigned or assigned a new password.  As a precaution
the following information is being sent to you for your records.\n\n
Your Username is: $username\n
Your Password is: $password\n\n";

  &email;

  $message = "Username and Password have been sent as requested";
  &response_page($message);
  $action = "UN and PW emailed";
  return;
}

sub email {
  $email = &CGI::escapeHTML( $query->param('email') );
  $email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $password = &CGI::escapeHTML( $query->param('password') );
  $password =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  $position = index( $email, "\@" );
  if ( ( $position > 1 ) && ( length($email) > 5 ) && ( $position < ( length($email) - 5 ) ) ) {
    $email = substr( $email, 0, 50 );

    my $emailObj = new PlugNPay::Email('legacy');
    $emailObj->setGatewayAccount($merchant);
    $emailObj->setFormat('text');
    $emailObj->setTo($email);
    $emailObj->setFrom($from_email);

    if ( $subject ne "" ) {
      $emailObj->setSubject($subject);
    } else {
      $emailObj->setSubject('Password Confirmation');
    }

    $mail1 .= "$mail_message";

    if ( $from_signature ne "" ) {
      $mail1 .= "$from_signature\n";
    } else {
      $mail1 .= "Support Staff\n";
    }

    $emailObj->setContent($mail1);
    $emailObj->send();
  }
}

sub silent_delete {

  # Removes Password from WebSite Server and Marks Account as Cancelled
  # Leaves Password to make it easier to reinstate.

  my ( $myusername, $path_passwrdremote, $database, $warning_flag, $dont_encrypt ) = @_;
  $myusername =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  local ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);

  #$dbh = &miscutils::dbhconnect("$database");
  my $sth = $dbh_plus->prepare(
    q{
      SELECT password,email,enddate,purchaseid
      FROM customer
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute("$myusername") or die "Can't execute: $DBI::errstr";
  ( $password, $email, $end, $purchaseid ) = $sth->fetchrow;
  $sth->finish;

  if ( $password eq "" ) {
    return;
  }

  if ( $warning_flag ne "yes" ) {
    $password = sprintf( "CN%04d$password", $$ );
    $status   = "cancelled";
    $bc       = "0";

    my $sth = $dbh_plus->prepare(
      q{
        UPDATE customer
        SET status=?,billcycle=?,password=?
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( "$status", "$bc", "$password", "$myusername" ) or die "Can't execute: $DBI::errstr";
    $sth->finish;

    if ( $path_passwrdremote ne "" ) {
      &passwrdremote( $myusername, $password, "delete", $path_passwrdremote, $purchaseid );
    }

    $reason = "AutoTerminated - Excessive Abuse";
    &record_history( "$myusername", "Cancelled", "$reason" );

    #$dbh->disconnect;
  } else {
    $len = length($password);
    $test = substr( $password, 0, 3 );
    if ( $test eq "TRM" ) {
      $warning = substr( $password, 3, 1 );
      $warning = $warning - 1;
      if ( $warning > 0 ) {
        substr( $password, 3, 1 ) = $warning;
      } else {
        $password = sprintf( "CN%02d%02dTRM0", $min, $sec );
        $status   = "cancelled";
        $bc       = "0";

        my $sth = $dbh_plus->prepare(
          q{
            UPDATE customer
            SET status=?,billcycle=?,password=?
            WHERE username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth->execute( "$status", "$bc", "$password", "$myusername" ) or die "Can't execute: $DBI::errstr";
        $sth->finish;

        if ( $path_passwrdremote ne "" ) {
          &passwrdremote( $myusername, $password, "delete", $path_passwrdremote, $purchaseid );
        }

        $reason = "AutoTerminated - Excessive Abuse";
        &record_history( "$myusername", "Cancelled", "$reason" );

        #$dbh->disconnect;
        exit;
      }
    } else {
      $password = "TRM5$password";
    }

    $bc = "0";

    my $sth = $dbh_plus->prepare(
      q{
        UPDATE customer
        SET password=?
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( "$password", "$myusername" ) or die "Can't execute: $DBI::errstr";
    $sth->finish;

    if ( $dont_encrypt ne "yes" ) {

      #if dont_encrypt flag is set, skip encrypting password
      # - added to support local web site based encryption setups
      $password1 = crypt( $password, $password );
    } else {
      $password1 = $password;
    }

    if ( $path_passwrdremote ne "" ) {
      &passwrdremote( $myusername, $password1, "add", $path_passwrdremote, $end, $purchaseid );
    }

    $reason = "Password Changed - Account Abuse";
    &record_history( "$myusername", "Modifed Password", "$reason" );

    #$dbh->disconnect;

    $mail_message = "Your usage pattern has exceeded our preset security limits for bandwidth and/or access from multiple IP addresses.  As a security precaution your password has been changed.
\n\nYour new password is: $password\n\nWe apologize for any inconvienence this may cause.\n\n";
    &email2;
  }
}

sub email2 {
  $position = index( $email, "\@" );
  if ( ( $position > 1 ) && ( length($email) > 5 ) && ( $position < ( length($email) - 5 ) ) ) {
    if ( $email =~ /masbrands\@worldnet.att.net/ ) {
      $email = "dprice\@plugnpay.com";
    }
    $email     = substr( $email,     0, 50 );
    $bcc_email = substr( $bcc_email, 0, 50 );

    my $emailObj = new PlugNPay::Email('legacy');
    $emailObj->setGatewayAccount($merchant);
    $emailObj->setFormat('text');
    $emailObj->setTo($email);
    $emailObj->setFrom($from_email);

    if ( $cc_email ne "" ) {
      $cc_email = substr( $cc_email, 0, 50 );
      $emailObj->setCC($cc_email);
    }
    $emailObj->setBCC($bcc_email);

    if ( $subject ne "" ) {
      $emailObj->setSubject("$merchant $subject");
    } else {
      $emailObj->setSubject("$merchant Password Confirmation");
    }

    my $mail1 = "";
    $mail1 .= "$mail_message";
    $mail1 .= "\n\n";

    if ( $from_signature ne "" ) {
      $mail1 .= "$from_signature\n";
    } else {
      $mail1 .= "Support Staff\n";
    }

    $emailObj->setContent($mail1);
    $emailObj->send();
  }
}

sub write_table_entry_pending {
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  print "  <tr>\n";
  print "    <td colspan=1><font size=-1><b>Username:</b></font>$username</a></td>\n";
  print "    <td>Count: $i</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td><font size=-1><b>Customer Name:</b></font> $name</td>\n";
  print "    <td><font size=-1><b>Email:</b></font>";
  if ( $email ne "" ) {
    print " <a href=\"mailto:$email\">$email</a>";
  } else {
    print " &nbsp;";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td rowspan=1><form method=post action=\"editcust.cgi\" target=\"results\">\n";
  print "<input type=hidden name=\"username\" value=\"$username\">\n";
  print "<input type=hidden name=\"password\" value=\"$password\">\n";
  print "<input type=hidden name=\"function\" value=\"activate\">\n";
  print "<font size=-1><b><a href=\"/payment/recurring/membership_help.html\#activate\" onClick=\"results();\" target=\"results\">Activate Membership</a></b></font>\n";
  print "<br><div align=center><input type=submit class=\"button\" value=\"Submit Request\" onClick=\"results();\"></div></td></form>\n";
  print "    <td><font size=-1><b>Status:</b></font> $status</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2><hr width=75% height=3></td>\n";
  print "  </tr>\n";

  return;
}

sub dump_remote_file {
  my ( $addr, $pairs, $myusername, $mypassword ) = @_;
  $myusername =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  my $ua = new LWP::UserAgent;
  $ua->agent( "AgentName/0.1 " . $ua->agent );
  $ua->timeout(1200);
  my $req = new HTTP::Request POST => $addr;
  $req->content_type('application/x-www-form-urlencoded');
  if ( ( $myusername ne "" ) && ( $mypassword ne "" ) ) {
    $req->authorization_basic( "$myusername", "$mypassword" );
  }
  $req->content($pairs);
  $res = $ua->request($req);
  if ( $res->is_success ) {

    #print $res->content;
    #exit;
    return;

  } else {
    print $res->error_as_HTML;
  }
}

sub dump_logfile {
  my ( $addr, $pairs, $myusername, $mypassword ) = @_;
  $myusername =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  my $ua = new LWP::UserAgent;
  $ua->agent( "AgentName/0.1 " . $ua->agent );
  $ua->timeout(1200);
  my $req = new HTTP::Request POST => $addr;
  $req->content_type('application/x-www-form-urlencoded');
  if ( ( $myusername ne "" ) && ( $mypassword ne "" ) ) {
    $req->authorization_basic( "$myusername", "$mypassword" );
  }
  $req->content($pairs);
  $res = $ua->request($req);
  if ( $res->is_success ) {

    #print $res->content;
    #exit;
    &analyze_logfile;
  } else {
    print $res->error_as_HTML;
  }
}

sub sentinel_log {
  my (%sentinel) = @_;
  &dump_remote_file( $sentinel{'path_remote'} );
  $merchant           = $sentinel{'merchant'};
  $killswitch         = $sentinel{'killswitch'};
  $warning_flag       = $sentinel{'warning_flag'};
  $dont_encrypt       = $sentinel{'dont_encrypt'};
  $from_signature     = $sentinel{'from_signature'};
  $from_email         = $sentinel{'from_email'};
  $subject            = $sentinel{'subject'};
  $path_passwrdremote = $sentinel{'path_passwrdremote'};
  &analyze_sentinel_log();

}

sub analyze_sentinel_log {
  if ( $merchant_db ne "" ) {
    $database = $merchant_db;
  } else {
    $database = $merchant;
  }
  $dbh_plus = &miscutils::dbhconnect("$database");

  @lines = split( /\n/, $res->content );

  my $now = gmtime(time);
  print "MERCHANT:$merchant, $now\n\n";

  if ( $lines[0] !~ /\|/ ) {
    print "Connection Successful.  Nothing To Do.\n\n";
    foreach my $var (@lines) {
      print "$var\n";
    }
    $dbh_plus->disconnect;
    return;
  }

  $linecounter = @lines;
  foreach my $line (@lines) {
    $reason = "Excessive ";

    #print "$line \n";
    ( $myusername, $cnt, $ip, $byte ) = split( /\|/, $line );
    $myusername =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

    $kill{$myusername} = 1;
    if ( $cnt eq "1" ) {
      $reason{$myusername} .= "Downloads:";
    }
    if ( $ip eq "1" ) {
      $reason{$myusername} .= "IP:";
    }
    if ( $byte eq "1" ) {
      $reason{$myusername} .= "Byte:";
    }

    #&record_history("$myusername","Auto Delete","$reason");
  }

  foreach my $username ( sort keys %kill ) {
    print "Killed:$username\n";
    if ( $killswitch eq "on" ) {
      &silent_delete( $username, $path_passwrdremote, $merchant, $warning_flag, $dont_encrypt );
      $k++;
    } else {
      &record_history( "$myusername", "Auto Delete", "$reason{$myusername}" );
    }
  }
  $dbh_plus->disconnect;

  return;
}

sub analyze_logfile {
  if ( $merchant_db ne "" ) {
    $database = $merchant_db;
  } else {
    $database = $merchant;
  }

  @lines        = split( /\n/, $res->content );
  $linecounter  = @lines;
  %month_array  = ( 1, "Jan", 2, "Feb", 3, "Mar", 4, "Apr", 5, "May", 6, "Jun", 7, "Jul", 8, "Aug", 9, "Sep", 10, "Oct", 11, "Nov", 12, "Dec" );
  %month_array2 = ( "Jan", "01", "Feb", "02", "Mar", "03", "Apr", "04", "May", "05", "Jun", "06", "Jul", "07", "Aug", "08", "Sep", "09", "Oct", "10", "Nov", "11", "Dec", "12" );

  foreach my $line (@lines) {

    #print "$line \n";
    #print "$ipaddress,$username,$date,$gmt,$requesttype,$page,$successcode\n";

    ( $ipaddress, $username, $date, $gmt, $requesttype, $page, $successcode, $bytecnt ) = split( /\|/, $line );
    $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

    $date =~ s/\[//g;
    ( $day, $month, $year, $hour, $min, $sec ) = split( /[\/:]/, $date );
    $datestr = sprintf( "%04d%02d%02d", $year, $month_array2{"$month"}, $day );
    $log_time = sprintf( "%04d%02d%02d%02d%02d%02d", $year, $month_array2{"$month"}, $day, $hour, $min, $sec );

    $dest = substr( $line, index( $line, "\]" ) + 1 );
    $dest = substr( $dest, index( $dest, "/" ) );
    $dest = substr( $dest, 0, index( $dest, " " ) );

    if ( $page =~ /\.jpg/i ) {
      $byte{$username} = $byte{$username} + $bytecnt;
      $cntr{$username}++;
      $$username{$ipaddress}++;
      $ip{"$username:$ipaddress"}++;
      if ( $$username{$ipaddress} == 1 ) {
        $difIP{$username}++;
      }
    }
    if ( $killswitch eq "on" ) {
      if ( $cntr{$username} > ( $login_limit * $hour_window ) ) {
        $kill{$username}    = 1;
        $killcnt{$username} = 1;
      }
      if ( $difIP{$username} > ( $ip_limit * $hour_window ) ) {
        $kill{$username}   = 1;
        $killip{$username} = 1;
      }
      if ( $byte{$username} > ( $bandwidth_limit * $hour_window ) ) {
        $kill{$username}   = 1;
        $killbw{$username} = 1;
      }
    }
    $debug++;
  }
}

sub remote_kill {
  $day_window  = sprintf( "%02d", $day_window );
  $hour_window = sprintf( "%02d", $hour_window );

  my $mail_message = "";
  $mail_message .= "PlugnPay Password Sentinel - Configuration Settings:\n";
  $mail_message .= "$line[0]\n";
  $mail_message .= "$line[$linecounter-1]\n";
  $mail_message .= "Time Frame Reviewed: Days: $day_window Hours: $hour_window\n";
  $mail_message .= "Warning_flag: $warning_flag\n";
  $mail_message .= "Killswitch: $killswitch\n";
  $mail_message .= "Image limit: $login_limit images per hour\n";
  $mail_message .= "IP limit: $ip_limit per hour\n";
  $mail_message .= "Bandwidth limit: $bandwidth_limit bytes per hour\n\n";

  $mail_message .= "The Usernames with the $depth highest amount of image downloads were: \n";

  $k = 0;
  foreach my $key ( sort_hash( \%cntr ) ) {
    if ( $k < $depth ) {
      $mail_message .= "$key:$cntr{$key}\n";
      $k++;
    }
  }
  $mail_message .= "\n\nThe Usernames with the $depth highest amount of IP Addresses were: \n";
  $k = 0;
  foreach my $key ( sort_hash( \%difIP ) ) {
    if ( $k < $depth ) {
      $mail_message .= "$key:$difIP{$key}\n";
      foreach my $key1 ( keys %$key ) {
        $mail_message .= "    $key1:$$key{$key1}\n";
      }
      $k++;
    }
  }
  $k = 0;
  $mail_message .= "\n\nThe Usernames with the $depth highest amount of Bandwidth Usage were: \n";
  foreach my $key ( sort_hash( \%byte ) ) {
    if ( $k < $depth ) {
      $mail_message .= "$key:$byte{$key}\n";
      $k++;
    }
  }
  $mail_message .= "\n\nThe Usernames deleted are: \n";
  $bcc_email = "sentinel\@plugnpay.com";
  $email1    = $email;
  if ( $killswitch eq "on" ) {
    $dbh_plus = &miscutils::dbhconnect("$database");
    foreach my $username ( sort keys %kill ) {
      &silent_delete( $username, $path_passwrdremote, $merchant, $warning_flag, $dont_encrypt );
      $mail_message .= "$username  Image Cnt:$cntr{$username} IP Cnt:$difIP{$username} Bandwidth Cnt:$byte{$username}\n";
      $k++;
    }
    $dbh_plus->disconnect;
  }

  $email = $email1;
  &email2;
}

############## BEGIN AUTOMATED HELP DESK ROUTINES

sub input_scrn {

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";

  print "<title>$site_title - Customer Support</title>\n";

  print "<style type=\"text/css\">\n";
  print "<!--\n";
  print "th { font-family: $fontface; font-size: 65%; color: $goodcolor; align: left;}\n";
  print "td { font-family: $fontface; font-size: 65%; color: $goodcolor; align: right;}\n";
  print ".badcolor { color: $badcolor }\n";
  print ".goodcolor { color: $goodcolor }\n";
  print ".larger { font-size: 100% }\n";
  print ".smaller { font-size: 50% }\n";
  print ".short { font-size: 8% }\n";
  print ".itemscolor { background-color: $goodcolor; color: $backcolor }\n";
  print ".itemrows { background-color: #d0d0d0 }\n";
  print ".divider { background-color: #4a7394 }\n";
  print ".items { position: static }\n";
  print ".info { position: static }\n";
  print "-->\n";
  print "</style>\n";

  print "<style type=\"text/css\">\n";
  print "<!--  // beginning of script\n";
  print "pressed_flag = 0;\n";
  print "function mybutton(form){\n";
  print "  if (pressed_flag == 0) {\n";
  print "    pressed_flag = 1;\n";
  print "    return true;\n";
  print "  }\n";
  print "  else {\n";
  print "    return false;\n";
  print "  }\n";
  print "}\n";
  print "// end of script -->\n";
  print "</script>\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";

  print "<div align=center>\n";
  print "<table width=\"85%\"><tr>\n";
  print "<td align=left>\n";
  print "<font size=+2>User Support</font><p>\n";
  if ( ( $browser =~ /AOL/ ) && ( $browser =~ /Mozilla\/2.0/ ) ) {
    print "<div align=center><font color=\"##FF0000\" size=\"+1\">Attention: </font><br>Your browser is outdated and may be the cause of your problem. \n";
    print "Please follow this link to upgrade to the new version of Netscape.  <a href=\"http://home.netscape.com/download/selectplatform_1_41.html\">\n";
    print "<br>http://home.netscape.com/download/selectplatform_1_41.html</a>  <br>After it is installed, log onto AOL, minimize the AOL window and then run Netscape. \n";
    print "</div><p>\n";
  }

  $headerfile =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
  &sysutils::filelog( "read", "$headerfile" );
  open( MESSAGE, '<', "$headerfile" );
  while (<MESSAGE>) {
    print $_;
  }

  print "<font size=+1>Please complete the following information as completely as possible so we may resolve your problem as quickly as possible.</font>\n";
  print "<p>The more complete the information is filled in, the quicker your problem will be resolved. <p>\n";
  print "<div align=left><font size=+1>The problem resolution will be sent via EMAIL so be SURE you enter your email address CORRECTLY!</font></div><p>\n";
  print "<FORM METHOD=post ACTION=\"$path_program\">\n";
  print "\n";
  print "<INPUT TYPE=hidden name=\"function\" value=\"respond\"><INPUT TYPE=hidden name=\"site\" value=\"$database\"><INPUT TYPE=hidden name=\"ipaddress\" value=\"$remoteaddr\">\n";

  print <<EOF;
<table>
<tr><td>Email address:</td><td><input type=text name=\"email\" size=30 maxlength=40></td></tr>
<tr><td>Your username:</td><td><input type=text name=\"username\" size=8 maxlength=8></td></tr>
<tr><td>Your password:</td><td><input type=text name=\"password\" size=8 maxlength=8 autocomplete=\"off\"> </td></tr>
<tr><td colspan=2>If you believe that you may have used a different email address to signup for this service, please enter it below.</td></tr>
<tr><td>Secondary Email Address:</td><td><input type=text name=\"email1\" size=30 maxlength=40></td><tr>
<tr><td colspan=2>If you received an order confirmation email, please enter the order id number below.</td></tr>
<tr><td>Order ID:</td><td><input type=text name=\"orderid\" size=18 maxlength=17></td></tr>
</table>
</td></tr>
</table>
<div align=center>
<table width=\"85%\">
<tr><td colspan=2>Additional Comments &/or Questions:
<tr><td colspan=2><TEXTAREA NAME=\"comments\" ROWS=6 COLS=70></TEXTAREA><p>
<tr><td align=center><font size=+1><input type=submit class=\"button\" value=\"Submit Trouble Report\">

</form>
</table>

</body>
</html>

EOF

  exit;

}

sub report {
  $browser = $ENV{'HTTP_USER_AGENT'};
  local ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  $id = sprintf( "%02d%02d%02d%02d%02d%05d", $year, $mon + 1, $mday, $hour, $min, $$ );

  $email = &CGI::escapeHTML( $query->param('email') );
  $email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $email1 = &CGI::escapeHTML( $query->param('email1') );
  $email1 =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;
  if ( $email1 eq "" ) {
    $email1 = "a";
  }

  $orderid = &CGI::escapeHTML( $query->param('orderid') );
  $orderid =~ s/[^0-9]//g;
  if ( $orderid eq "" ) {
    $orderid = "1";
  }

  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
  if ( $username eq "" ) {
    $username = "unknown";
  }

  $comments = &CGI::escapeHTML( $query->param('comments') );
  $comments =~ s/\'//g;

  $resolution = &CGI::escapeHTML( $query->param('resolution') );
  $resolution =~ s/\'//g;

  my $sth = $dbh_plus->prepare(
    q{
      INSERT INTO support
      (id,username,password,email,email1,ipaddress,orderid,comments,resolution,trans_time,browser,dbname)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( $id, $username, $password, $email, $email1, $remoteaddr, $orderid, $comments, $resolution, $time, $browser, $database ) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  #print "aaaaa\n";
  $message = "<font size=\"+1\">Your request for assistance has been received.\n";
  $message .= "<p>\nWe will respond as quickly as we can.  You will receive an answer via email.  <p>\n";
  &response_page($message);
  return;
}

sub error_file {
  my ($reason) = @_;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  if ( $reason =~ /blank/i ) {
    print "<h3>The Username field was left blank.  Please enter a username.</h3>\n";
  } elsif ( $reason =~ /in_use/ ) {
    print "<h3>The Username is already being used.  Please enter a different username.</h3>\n";
  } else {
    print "<div align=center><font size=+1>Unknown Error<p>\n";
  }
  print "<p>\n";
  print "</body>\n";
  print "</html>\n";

}

sub autorespond {
  $comments = &CGI::escapeHTML( $query->param('comments') );
  $comments =~ s/']//g;

  $email = &CGI::escapeHTML( $query->param('email') );
  $email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $position = index( $email, "\@" );

  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
  if ( $username eq "" ) {
    if ( ( $position < 2 ) || ( length($email) < 6 ) || ( $position > ( length($email) - 6 ) ) ) {
      &bad_email();
      exit;
    }
  }

  $email1 = &CGI::escapeHTML( $query->param('email1') );
  $email1 =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;
  $position = index( $email1, "\@" );
  if ( ( $position < 2 ) || ( length($email1) < 6 ) || ( $position > ( length($email1) - 6 ) ) ) {
    $emailcheck = "NG";

    #    &bad_email();
    #    exit;
  }

  ##### First Search on username if present.   ##########

  if ( $username ne "" ) {
    my $sth_customer = $dbh_plus->prepare(
      q{
        SELECT username,password,email,orderid,status
        FROM customer
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_customer->execute("$username") or die "Can't execute: $DBI::errstr";
    while ( my ( $su_uname, $su_password, $su_email, $su_orderid, $status ) = $sth_customer->fetchrow ) {
      if ( ( $su_uname ne "" ) && ( $status !~ /cancel/i ) ) {

        #&locatepassword($su_uname,$su_password,$path_test);
        $passtest = "success";    ##  Added to remove Load from system.
        if ( $passtest =~ /success/i ) {
          $message = "The Username and Password associated with your username have been located in the database.  A copy is being mailed to you for your records.";
          &respond_email();
          &found_respond();
        }
      }
    }
    $sth_customer->finish;
  }

  ##### Search on Order ID if present.   ##########
  $orderid = &CGI::escapeHTML( $query->param('orderid') );
  $orderid =~ s/\'//g;

  if ( $orderid ne "" ) {
    my $sth_customer = $dbh_plus->prepare(
      q{
        SELECT username,password,email,orderid,status
        FROM customer
        WHERE orderid=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth_customer->execute("$orderid") or die "Can't execute: $DBI::errstr";
    while ( my ( $su_uname, $su_password, $su_email, $su_orderid, $status ) = $sth_customer->fetchrow ) {
      $su_uname =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
      if ( ( $su_uname ne "" ) && ( $status !~ /cancel/i ) ) {

        #&locatepassword($su_uname,$su_password,$path_test);
        $passtest = "success";    ##  Added to remove Load from system.
        if ( $passtest =~ /success/i ) {
          $message = "The Username and Password associated with your OrderID have been located in the database.  A copy is being mailed to you for your records.";
          &respond_email();
          &found_respond();
        }
      }
    }
    $sth_customer->finish;
  }

###### Next Search on Email Address
  #        where lower(email) like lower('$email')

  if ( $email ne "" ) {
    my $sth_customer = $dbh_plus->prepare(
      q{
        SELECT username,password,email,orderid,status
        FROM customer
        WHERE LOWER(email) LIKE LOWER('$email')
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth_customer->execute or die "Can't execute: $DBI::errstr";
    while ( my ( $su_uname, $su_password, $su_email, $su_orderid, $status ) = $sth_customer->fetchrow ) {
      $su_uname =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
      if ( ( $su_uname ne "" ) && ( $status !~ /cancel/i ) ) {
        $passtest = "success";
        if ( $passtest =~ /success/i ) {
          $message = "A Username and Password associated with your email address have been located in the database.  A copy is being mailed to you for your records.";
          &respond_email;
          &found_respond();
        }
      }
    }
    $sth_customer->finish;
  }

  if ( ( $email1 ne "" ) && ( $emailcheck ne "NG" ) ) {
    my $sth_customer = $dbh_plus->prepare(
      q{
        SELECT username,password,email,orderid,status
        FROM customer
        WHERE LOWER(email) LIKE LOWER('$email1')
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth_customer->execute or die "Can't execute: $DBI::errstr";
    while ( my ( $su_uname, $su_password, $su_email, $su_orderid, $status ) = $sth_customer->fetchrow ) {
      $su_uname =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
      if ( ( $su_uname ne "" ) && ( $status !~ /cancel/i ) ) {
        $passtest = "success";
        if ( $passtest =~ /success/i ) {
          $message = "A Username and Password associated with your email address have been located in the database.  A copy is being mailed to you for your records.";
          &respond_email;
          &found_respond();
        }
      }
    }
    $sth_customer->finish;
  }
  &notfound_respond();
}

sub respond_email {
  $su_uname =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $mail_message = "Your Username and Password have been located in the password database.\n";
  $mail_message .= "Please enter them EXACTLY as printed below paying close attention to the CAPITALIZATION.\n";
  $mail_message .= "Username: $su_uname\n";
  $mail_message .= "Password: $su_password\n";

  &email2;
}

sub found_respond {
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $message .= "Please attempt to access the $site_title section again with the username and password that have been emailed to you.\n";
  $message .= "<p><a href=\"$site_url/\" alt=\"Enter $site_title\" target=\"$site_title/win\">Click Here to Enter $site_title</a>\n";
  $message .= "<p>If your are still having trouble please click on the button below to submit a trouble report to our support staff.\n";

  $message .= "<form method=post action=\"$path_program\">\n";
  $message .= "<input type=hidden name=\"function\" value=\"troublereport\">\n";
  $message .= "<input type=hidden name=\"ipaddress\" value=\"$remoteaddr\">\n";
  $message .= "<input type=hidden name=\"username\" value=\"$username\">\n";
  $message .= "<input type=hidden name=\"password\" value=\"$password\">\n";
  $message .= "<input type=hidden name=\"email\" value=\"$email\">\n";
  $message .= "<input type=hidden name=\"email1\" value=\"email1\">\n";
  $message .= "<input type=hidden name=\"orderid\" value=\"$orderid\">\n";
  $message .= "<input type=hidden name=\"site\" value=\"$database\">\n";
  $message .= "<input type=hidden name=\"comments\" value=\"$comments\">\n";

  $message .= "<div align=center>\n";
  $message .= "<p><input type=submit class=\"button\" value=\"Submit Trouble Report\">\n";
  $message .= "</div>\n";
  $message .= "</form>\n";

  &response_page($message);

  exit;
}

sub notfound_respond {
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $message = "<font size=\"+1\">No Record of a registration was found under the information you submitted.</font>\n";

  $message .=
    "<p>This means that either the information you submitted in this trouble report does not match the information you registerd with, your registration attempt did not complete normally and you were not charged or your password was cancelled due to misuse.  So please check the information you entered below.  If you would like to edit it, please use the 'BACK' button on your browser to do so.\n";
  $message .=
    "Otherwise, please try to register again.  If by chance you find a double charge on your credit card statement please email us with the following information and we will issue you a refund immediately.\n";

  $message .= "<p>Username: $username\n";
  $message .= "<br>Password: $password\n";
  $message .= "<br>Email Address: $email\n";
  $message .= "<br>OrderID: $orderid\n";

  $message .= "<p>Email should contain:\n";
  $message .= "<ul>\n";
  $message .= "  <li>Date of Charge</li>\n";
  $message .= "  <li>First 4 digits and last 2 digits of your credit card number.</li>\n";
  $message .= "</ul>\n";

  $message .= "<br>Send email to here <a href=\"mailto:$from_email\">$from_email</a>.\n";
  $message .= "<p><b>If you would still like to submit a trouble report to our support staff please click on the button below.</b>\n";

  $message .= "<form method=post action=\"$path_program\">\n";
  $message .= "<input type=hidden name=\"function\" value=\"troublereport\">\n";
  $message .= "<input type=hidden name=\"ipaddress\" value=\"$remoteaddr\">\n";
  $message .= "<input type=hidden name=\"username\" value=\"$username\">\n";
  $message .= "<input type=hidden name=\"password\" value=\"$password\">\n";
  $message .= "<input type=hidden name=\"email\" value=\"$email\">\n";
  $message .= "<input type=hidden name=\"email1\" value=\"email1\">\n";
  $message .= "<input type=hidden name=\"orderid\" value=\"$orderid\">\n";
  $message .= "<input type=hidden name=\"site\" value=\"$database\">\n";
  $message .= "<input type=hidden name=\"comments\" value=\"$comments\">\n";

  $message .= "<div align=center>\n";
  $message .= "<p><input type=submit class=\"button\" value=\"Submit Trouble Report\">\n";
  $message .= "</div>\n";
  $message .= "</form>\n";

  &response_page($message);
  exit;
}

sub bad_email {
  $mssg = "The Email Address You entered is not valid.  Please hit the back button and double check your entry.<p>
    The Proper Format for an email address is:  myname\@mydomain.com.  For example, If you are from AOL, it is, screen_name\@aol.com</font</div><p>\n";

  &response_page($mssg);
  exit;
}

sub sort_hash {
  my $x     = shift;
  my %array = %$x;
  sort { $array{$b} <=> $array{$a}; } keys %array;
}

sub editusername {
  $username = &CGI::escapeHTML( $query->param('username') );
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $newuname = &CGI::escapeHTML( $query->param('newuname') );
  $newuname =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  #  print "OLD:$username, NEW:$newuname\n";
  #  exit;

  if ( $newuname ne "" ) {
    $newuname =~ s/[^0-9a-zA-Z\@\.\_\-]//g;
  } else {
    &error_file("blank");
  }

  $newuname = substr( $newuname, 0, 60 );

  my $sth_customer = $dbh_plus->prepare(
    q{
      SELECT username
      FROM customer
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth_customer->execute("$newuname") or die "Can't execute: $DBI::errstr";
  ($mn) = $sth_customer->fetchrow;
  $sth_customer->finish;

  if ( $mn ne "" ) {
    &error_file("in_use");
  } else {
    my $sth = $dbh_plus->prepare(
      q{
        UPDATE customer
        SET username=?
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( "$newuname", "$username" ) or die "Can't execute: $DBI::errstr";
    $sth->finish;
    $username = $newuname;
    &viewcustomer();
  }
}

################### BEGIN MEMBERSHIP SUPPORT SUBROUTINES #####################

sub support_index {

  print "Content-Type: text/html\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";

  print <<EOF;
<TITLE>Plug and Pay Membership Support Area</TITLE>
</HEAD>
<FRAMESET COLS="145,*" BORDER=0 FRAMEBORDER=NO>
  <FRAME SRC="support.cgi?mode=nav" NAME="nav" MARGINWIDTH=2 MARGINHEIGHT=5 SCROLLING=NO>
  <FRAME SRC="support.cgi?mode=intro" NAME="main" MARGINWIDTH=5 SCROLLING=auto>
</FRAMESET>
<NOFRAMES>
<BODY>
<font size=+2>This page may only be viewed with a browser that supports frames.</font>
</BODY>
</NOFRAMES>
</HTML>
EOF

}

sub support_nav {
  $i = 0;
  my $sth_count = $dbh_plus->prepare(
    q{
      SELECT id
      FROM support
      WHERE id>'0'
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth_count->execute or die "Can't execute: $DBI::errstr";

  #($i) = $sth_count->fetchrow;
  $rv = $sth_count->bind_columns( undef, \($id) );
  while ( $sth_count->fetch ) {
    $i++;
  }
  $sth_count->finish;

  print "Content-Type: text/html\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";

  print <<EOF;
<HTML>
<HEAD>
<TITLE>Plug and Pay Membership Support Area - Nav Bar</TITLE>
</HEAD>
<BODY>
<font face="Arial,Helvetica,Univers,Zurich BT">
<font size="2">
<div align="center">
<a href=\"$path_cgi\"><img src=\"https://www.plugnpay.com/pnp_seal.gif\" alt=\"Plug'nPay\"></a>
<p><b>Membership<br>Support Center</b>
<p>
<font size="1"><b>Support Requests $i</b></font>
<table border="1">
<tr>
<th><font face="Arial,Helvetica,Univers,Zurich BT" size="1">START</th><th><font face="Arial,Helvetica,Univers,Zurich BT" size="1">NO.</th></tr>
<td align="right"><font size="2"><form method="post" action="support.cgi" target="main">
<select name="start">
<option value="0">0</option>
<option value="5">5</option>
<option value="10">10</option>
<option value="15">15</option>
<option value="20">20</option>
<option value="25">25</option>
<option value="30">30</option>
<option value="35">35</option>
<option value="40">40</option>
<option value="45">45</option>
<option value="50">50</option>
<option value="55">55</option>
</select></font></td>
<td align="right"><font size="2">
<select name="view">
<option value="10">10</option>
<option value="20">20</option>
<option value="30">30</option>
<option value="40">40</option>
<option value="50">50</option>
</select></font></td></tr>
<td colspan="2" align="center"><input type="submit" class="button" value="View Records"></td></tr>
<tr><td><input type="hidden" name="mode" value="list"></td></form></tr>
<tr><td colspan="2" align="center"><form method="post" action="index.cgi" target="newWin"><font face="Arial,Helvetica,Univers,Zurich BT"><font size="1">MEMBERSHIP<br>
<input type="submit" class="button" value="Administration">
</form>
</font></font></td></tr>
</table>
</BODY>
</HTML>
EOF

}

sub support_intro {

  print "Content-Type: text/html\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Plug and Pay Technologies Membership Administration</title>\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<p><br><p>\n";
  print "<div align=center><img src=\"https://www.plugnpay.com/img2/mainmenu.jpg\"></div>\n";
  print "</body>\n";
  print "</html>";

}

sub support_view_records {

  $start = &CGI::escapeHTML( $query->param('start') );
  $start =~ s/[^0-9]//g;

  $end = &CGI::escapeHTML( $query->param('end') );
  $end =~ s/[^0-9]//g;

  $view = &CGI::escapeHTML( $query->param('view') );
  $view =~ s/[^0-9]//g;

  if ( $start eq "" ) {
    $start = 0;
  }
  if ( $end eq "" ) {
    $end = $start + 10;
  }
  if ( $view ne "" ) {
    $end = $start + $view;
  }

  print "Content-Type: text/html\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Plug and Pay - Technical Support</title>\n";

  print "<script type=\"text/javascript\">\n";
  print "<\!-- Start Script\n";
  print "function results() \{\n";
  print "   resultsWindow \= window.open('/payment/recurring/blank.html','results','menubar=no,status=no,scrollbars=yes,resizable=yes,width=550,height=600');\n";
  print "}\n";
  print "// end script-->\n";
  print "</script>\n\n";

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<div align=center>\n";
  print "<p>\n";

  $i = 0;
  my $sth_support = $dbh_plus->prepare(
    q{
      SELECT id,username,password,email
      FROM support
      ORDER BY id
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth_support->execute or die "Can't execute: $DBI::errstr";
  while ( my ( $id, $un, $pw, $em ) = $sth_support->fetchrow ) {
    $test   = $un . $pw . $em;
    $delete = &CGI::escapeHTML( $query->param("$id\_delete") );
    if ( ( $test eq "" ) || ( $delete eq "yes" ) ) {
      $sth_delete = $dbh_plus->prepare(
        q{
          DELETE FROM support
          WHERE id=?
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_delete->execute("$id") or die "Can't execute: $DBI::errstr";
      $sth_delete->finish;
    } else {
      $i++;
    }
  }
  $sth_support->finish;

  print "<b>Number of Support Requests on record: $i<b><p>\n";
  print "<form method=post action=\"$path_cgi\" target=\"main\">\n";
  print "<input type=submit class=\"button\" value=\"Delete Marked Records\"><p>\n";
  print "<input type=hidden name=\"start\" value=\"$start\">\n";
  print "<input type=hidden name=\"view\" value=\"$view\">\n";
  print "<input type=hidden name=\"mode\" value=\"list\">\n";
  my $sth_support2 = $dbh_plus->prepare(
    q{
      SELECT id,username,password,email,email1,ipaddress,comments,resolution,trans_time,orderid,browser,dbname
      FROM support
      ORDER BY id
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth_support2->execute or die "Can't execute: $DBI::errstr";
  $rv = $sth_support2->bind_columns( undef, \( $id, $username, $password, $email, $email1, $remoteaddr, $comments, $resolution, $time, $orderid, $browser, $database ) );

  $i = 1;
  $j = 1;
  while ( $sth_support2->fetch ) {
    if ( ( $j >= $start ) && ( $j < $end ) ) {
      print "<table width=\"95%\" border=1>\n";
      print
        "<tr><td colspan=3><font size=2>$time</font></td><td colspan=3><font size=2>$browser</font></td><td><font size=2>$j</font></td><td><font size=2><b><input type=checkbox name=\"$id\_delete\" value=\"yes\"> Delete</font></b></td></tr>\n";
      print "<tr>\n";
      print "  <th><font size=2>User Info</font></th>\n";
      print "  <td><font size=2>UN: $username</font></td>\n";
      print "  <td><font size=2>PW: $password</font></td>\n";
      print "  <td><font size=2>Email: <a href=\"mailto:$email\">$email</a></font></td>\n";
      print "  <td><font size=2>Email1: <a href=\"mailto:$email1\">$email1</a></font></td>\n";
      print "  <td colspan=3><font size=\"2\">CCID: $orderid</font></td>\n";
      print "</tr>\n";

      print "<tr><td colspan=8><font size=2><input type=hidden name=\"comments\" value=\"$comments\">$comments</font></td></tr>\n";

      if ( $email1 eq "" ) {
        $email1 = "x";
      }
      if ( $email eq "" ) {
        $email = "x";
      }
      if ( $orderid eq "" ) {
        $orderid = "x";
      }

      $sth_customer = $dbh_plus->prepare(
        q{
          SELECT username,password,email,orderid
          FROM customer
          WHERE username=?
          OR orderid=?
        }
        )
        or die "Can't do: $DBI::errstr";
      $sth_customer->execute( "$username", "$orderid" ) or die "Can't execute: $DBI::errstr";
      $rv = $sth_customer->bind_columns( undef, \( $su_uname, $su_password, $su_email, $su_orderid ) );

      while ( $sth_customer->fetch ) {
        $su_uname =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

        print
          "<tr><th><font size=2>Search Results</font></th><td><font size=2><input type=hidden name=\"su_uname\" value=\"$su_uname\">CUN: $su_uname</font></td><td><font size=2><input type=hidden name=\"su_password\" value=\"$su_password\">PW: $su_password</td>\n";

        print
          "<td colspan=2><font size=2>Email: <a href=\"mailto:$su_email\">$su_email</a></font></td><td><font size=2>CCID: $su_orderid</font></td><td colspan=2><font size=2><a href=\"$path_edit?function=viewrecord\&username=$su_uname\" target=\"results\" onClick=\"results();\">EDIT RECORD</a></font></td></tr>\n";
      }
      $sth_customer->finish;

      print "<tr><td colspan=8><hr width=\"75%\"></td>\n";

      print "</table><br>\n";
      $| = 1;
      $i++;
    }
    $j++;
  }
  $sth_support2->finish;

  print "</form>\n";
  print "</body>\n";
  print "</html>\n";

}

1;
