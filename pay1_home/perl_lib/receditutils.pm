package receditutils;

use rsautils;
use CGI;
use DBI;
use miscutils;
use Net::FTP;
use mckutils_strict;
use sysutils;
use smpsutils;
require plusutils;
use PlugNPay::CreditCard;
use PlugNPay::Email;
use PlugNPay::GatewayAccount;
use PlugNPay::InputValidator;
use PlugNPay::Logging::DataLog;

sub new {
  my $type = shift;
  ( $merchant, $from_email, $host, $user1, $user2, $user3, $user4 ) = @_;

  local ( $ssec, $mmin, $hhour, $dday, $mmonth, $yyear, $wday, $yday, $isdst ) = gmtime(time);
  $dday   = $dday;
  $mmonth = $mmonth + 1;
  $yyear  = $yyear + 1900;

  $database = $merchant;
  $database =~ s/[^a-zA-Z0-9]//g;

  $dbh_cust = &miscutils::dbhconnect("pnpmisc");

  my $gatewayAccount = new PlugNPay::GatewayAccount($merchant);
  $custstatus    = $gatewayAccount->getStatus();
  $custreason    = $gatewayAccount->getStatusReason();
  $reseller      = $gatewayAccount->getReseller();
  $merch_company = $gatewayAccount->getMainContact()->getCompany();

  if ( $custstatus eq "cancelled" ) {
    print "Your account is closed. Reason: $custreason<br>\n";
    exit;
  }

  $sth_merchants = $dbh_cust->prepare(
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

  $sth_customer = $dbh_cust->prepare(
    q{
      SELECT ftphost,installbilling
      FROM pnpsetups
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth_customer->execute("$merchant") or die "Can't execute: $DBI::errstr";
  ( $ftphost, $installbilling ) = $sth_customer->fetchrow;
  $sth_customer->finish;

  $dbh_cust->disconnect;

  if ( $host eq "" ) {
    $host = $ftphost;
  }

  $dbh = &miscutils::dbhconnect("$database");

  $query = new CGI;

  $function = &CGI::escapeHTML( $query->param('function') );
  $function =~ s/[^a-zA-Z0-9\_\-]//g;

  $username = &CGI::escapeHTML( $query->param('username') );
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  return [], $type;
}

sub html_head {
  my ( $title, $meta_refresh_url ) = @_;

  if ( $title eq "" ) {
    $title = "Membership Administration Area - $merchant";
  }

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>$title</title>\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/css/style_recurring.css\">\n";

  if ( $meta_refresh_url ne "" ) {
    print "<meta http-equiv=\"refresh\" content=\"5; URL=$meta_refresh_url\">\n";
  }

  print "<script type=\"text/javascript\">\n";
  print "//<!-- start javascript functions\n";

  print "function results() {\n";
  print "  resultsWindow = window.open('/payment/recurring/blank.html','results','menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300');\n";
  print "}\n";

  print "function openunderconstruction() {\n";
  print "  constructionWindow = window.open('underconstruction.html','underconstruction','menubar=no,status=no,scrollbars=no,resizable=no,width=100,height=40');\n";
  print "}\n";

  print "function closeresults() {\n";
  print "  resultsWindow = window.close('results');\n";
  print "}\n";

  print "// see if this javascript function is actually required\n";
  print "function closenewWin() {\n";
  print "  resultsWindow = window.close('newWin');\n";
  print "}\n";

  print "// end javascript functions -->\n";
  print "</script>\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" onLoad=\"self.focus()\">\n";

  return;
}

sub html_tail {
  print "</body>\n";
  print "</html>\n";
}

sub remove {
  $sth = $dbh->prepare(
    q{
      DELETE FROM customer
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  $sth->finish;

  $sth2 = $dbh->prepare(
    q{
      DELETE FROM billingstatus
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth2->execute("$username") or die "Can't execute: $DBI::errstr";
  $sth2->finish;

  $sth3 = $dbh->prepare(
    q{
      DELETE FROM history
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth3->execute("$username") or die "Can't execute: $DBI::errstr";
  $sth3->finish;
  eval {
    $sth4 = $dbh->prepare(
      q{
        DELETE FROM support
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth4->execute("$username") or die "Can't execute: $DBI::errstr";
    $sth4->finish;
  };

  &response_page("USERNAME $username has been removed from the database.");
}

sub custcnt {
  $sth = $dbh->prepare(
    q{
      SELECT enddate,billcycle,status,startdate,lastbilled
      FROM customer
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  while ( my ( $end, $billcycle, $status, $start, $lastbilled ) = $sth->fetchrow ) {
    if ( ( $status =~ /cancel/i ) && ( $today <= $end ) ) {
      $termcnt++;
    } elsif ( ( $billcycle eq "0" ) && ( $today <= $end ) ) {
      $cancelcnt++;
    } elsif ( ( $today > $end ) ) {
      $expiredcnt++;
    } else {
      $j++;
    }
  }
  $sth->finish;

  &html_head("Membership Administration Area - $merchant");

  print "<div align=center>\n";
  print "<h2>Customer Count</h2>\n";
  print "<p><table border=0 cellspacing=0 cellpadding=4>\n";
  print "  <tr>\n";
  print "    <th align=left>Active:</th>\n";
  print "    <td>$j</td>\n";
  print "    <th align=left>Cancelled:</th>\n";
  print "    <td>$cancelcnt</td>\n";
  print "    <th align=left>Terminated:</th>\n";
  print "    <td>$termcnt</td>\n";
  print "    <th align=left>Expired:</th>\n";
  print "    <td>$expiredcnt</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<p><form><input type=button class=\"button\" value=\"Close Window\" onClick=\"closeresults();\"></form>\n";

  &html_tail();
  exit;
}

sub cancel {
  $billcycle = "0";
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $sth = $dbh->prepare(
    q{
      UPDATE customer
      SET billcycle=?
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$billcycle", "$username" ) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  &viewcustomer();
  $action = "Bill Cycle set to zero";
}

sub disable {
  $end = sprintf( "%04d%02d%02d", $yyear, $mmonth, $dday );
  $status = "Disabled";
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $sth = $dbh->prepare(
    q{
      UPDATE customer
      SET enddate=?
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$end", "$username" ) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  &viewcustomer();
  $action = "Account Cancelled";
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
  $cardnumber =~ s/[0-9\*\ ]//g;

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

  $exp = &CGI::escapeHTML( $query->param('exp') );
  $exp =~ s/[^0-9\/]//g;

  $monthly = &CGI::escapeHTML( $query->param('monthly') );
  $monthly =~ s/[^a-zA-Z0-9\.\ ]//g;

  $balance = &CGI::escapeHTML( $query->param('balance') );
  $balance =~ s/[^0-9\.]//g;

  $billcycle = &CGI::escapeHTML( $query->param('billcycle') );
  $billcycle =~ s/[^0-9\.]//g;

  # ACH - Online Checking Fields
  $routingnum = &CGI::escapeHTML( $query->param('routingnum') );
  $routingnum =~ s/[^0-9]//g;

  $accountnum = &CGI::escapeHTML( $query->param('accountnum') );
  $accountnum =~ s/[^0-9]//g;

  if ( ( $routingnum ne "" ) && ( $accountnum ne "" ) ) {
    $cardnumber = sprintf( "%s %s", $routingnum, $accountnum );
  }

  if ( ( $status eq "cancelled" ) && ( $billcycle ne "0" ) ) {
    $billcycle = "0";
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

  $cardlength = length $cardnumber;
  if ( ( $cardnumber !~ /\*\*/ ) && ( $cardlength > 8 ) ) {
    ( $enccardnumber, $encryptedDataLen ) = &rsautils::rsa_encrypt_card( $cardnumber, '/home/p/pay1/pwfiles/keys/key' );

    if ( ( $routingnum eq "" ) && ( $accountnum eq "" ) ) {
      $cardnumber = &CGI::escapeHTML( $query->param('cardnumber') );
      $cardnumber =~ s/[^0-9]//g;
    } else {
      $cardnumber =~ s/[^0-9_ ]//g;
    }
    $cardnumber = substr( $cardnumber, 0, 4 ) . '**' . substr( $cardnumber, length($cardnumber) - 2, 2 );
    $encryptedDataLen = "$encryptedDataLen";

    $enccardnumber = &smpsutils::storecardnumber( $database, $username, 'recedit_update', $enccardnumber, 'rec' );

    $sth = $dbh->prepare(
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

  $qstr =
    "UPDATE customer SET name=?,company=?,addr1=?,addr2=?,city=?,state=?,zip=?,country=?,phone=?,fax=?,email=?,startdate=?,enddate=?,monthly=?,cardnumber=?,exp=?,lastbilled=?,password=?,billcycle=?,shipname=?,shipaddr1=?,shipaddr2=?,shipcity=?,shipstate=?,shipzip=?,shipcountry=?";
  @placeholder = (
    "$name",      "$company",   "$addr1",    "$addr2",     "$city",       "$state", "$zip",        "$country",  "$phone",     "$fax",
    "$email",     "$start",     "$end",      "$monthly",   "$cardnumber", "$exp",   "$lastbilled", "$password", "$billcycle", "$shipname",
    "$shipaddr1", "$shipaddr2", "$shipcity", "$shipstate", "$shipzip",    "$shipcountry"
  );

  if ( $installbilling eq "yes" ) {
    $qstr .= ",balance=?";
    push( @placeholder, "$balance" );
  }

  if ( $user1 ne "" ) {
    $qstr .= ",$user1=?";
    push( @placeholder, "$user1_val" );
  }
  if ( $user2 ne "" ) {
    $qstr .= ",$user2=?";
    push( @placeholder, "$user2_val" );
  }
  if ( $user3 ne "" ) {
    $qstr .= ",$user3=?";
    push( @placeholder, "$user3_val" );
  }
  if ( $user4 ne "" ) {
    $qstr .= ",$user4=?";
    push( @placeholder, "$user4_val" );
  }
  $qstr .= " WHERE username=?";
  push( @placeholder, "$username" );

  $sth = $dbh->prepare(qq{$qstr}) or die "Can't prepare: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  &viewcustomer();

  $action = "Information Updated";
}

sub viewcustomer {
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  &html_head("Membership Administration Area - Customer Administration");

  print "<div align=center>\n";
  print "<table width=\"90%\"><tr bgcolor=\"#80c0c0\"><td align=center><font size=+1>Membership Administration Area<br>Customer Administration</font></td></table><p>\n";
  print "<table border=1 cellspacing=0 cellpadding=2>\n";

  $qstr =
    "SELECT name,orderid,company,addr1,addr2,city,state,zip,country,password,email,startdate,enddate,monthly,cardnumber,exp,lastbilled,billcycle,shipname,shipaddr1,shipaddr2,shipcity,shipstate,shipzip,shipcountry,phone,fax";

  if ( $user1 ne "" ) {
    $qstr .= ",$user1";
  }
  if ( $user2 ne "" ) {
    $qstr .= ",$user2";
  }
  if ( $user3 ne "" ) {
    $qstr .= ",$user3";
  }
  if ( $user4 ne "" ) {
    $qstr .= ",$user4";
  }
  $qstr .= " FROM customer WHERE username=?";

  $sth = $dbh->prepare(qq{$qstr}) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  ( $name,      $orderid, $company,     $addr1,      $addr2, $city,       $state,     $zip,       $country,   $password,  $email,
    $start,     $end,     $monthly,     $cardnumber, $exp,   $lastbilled, $billcycle, $shipname,  $shipaddr1, $shipaddr2, $shipcity,
    $shipstate, $shipzip, $shipcountry, $phone,      $fax,   $user1_val,  $user2_val, $user3_val, $user4_val
  )
    = $sth->fetchrow;
  $sth->finish;

  if ( $installbilling eq "yes" ) {
    my $sth_install = $dbh->prepare(
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

  if ( ( $ENV{'SEC_LEVEL'} <= 7 ) && ( $ENV{'TECH'} eq "" ) && ( $user1 eq "enccardnumber" ) && ( $user2 eq "length" ) ) {
    $passphrase = "The friends rode down the hill and then back up.";
    $cardnumber = &rsautils::rsa_decrypt_file( $user1_val, $user2_val, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

    $cardnumber = substr( $cardnumber, 0, 16 );
    $enccardnumber = "";
  }

  &write_table_entry();

  print "</table><p>\n";

  print "<form action=\"https://$admindomain/payment/recurring/$merchant/admin/index.cgi\">\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\"Go To Main Page\">\n";
  print "</form>\n";

  print "</body>\n";
  print "</html>\n";

  $dbh->disconnect;

}

sub viewcustomers {
  &html_head("Membership Administration Area - Customer Administration");

  print "<center><div align=center>\n";
  print "<table width=\"90%\"><tr bgcolor=\"#80c0c0\"><td align=center><font size=+1>Membership Administration Area<br>Customer Administration</font></td></table><p>\n";
  print "<table border=1 cellspacing=0 cellpadding=2>\n";

  $qstr =
    "SELECT username,orderid,name,company,addr1,addr2,city,state,zip,country,password,email,startdate,enddate,monthly,cardnumber,exp,lastbilled,billcycle,shipname,shipaddr1,shipaddr2,shipcity,shipstate,shipzip,shipcountry,phone,fax";

  if ( $user1 ne "" ) {
    $qstr .= ",$user1";
  }
  if ( $user2 ne "" ) {
    $qstr .= ",$user2";
  }
  if ( $user3 ne "" ) {
    $qstr .= ",$user3";
  }
  if ( $user4 ne "" ) {
    $qstr .= ",$user4";
  }
  $qstr .= " FROM customer ORDER BY username";

  $sth = $dbh->prepare(qq{$qstr}) or die "Can't prepare: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";

  if ( $user4 ne "" ) {
    $sth->bind_columns(
      undef,
      \($username, $orderid,   $name,    $company,     $addr1,      $addr2, $city,       $state,     $zip,       $country,   $password,
        $email,    $start,     $end,     $monthly,     $cardnumber, $exp,   $lastbilled, $billcycle, $shipname,  $shipaddr1, $shipaddr2,
        $shipcity, $shipstate, $shipzip, $shipcountry, $phone,      $fax,   $user1_val,  $user2_val, $user3_val, $user4_val
       )
    );
  } elsif ( $user3 ne "" ) {
    $sth->bind_columns(
      undef,
      \($username, $orderid,   $name,    $company,     $addr1,      $addr2, $city,       $state,     $zip,      $country,   $password,
        $email,    $start,     $end,     $monthly,     $cardnumber, $exp,   $lastbilled, $billcycle, $shipname, $shipaddr1, $shipaddr2,
        $shipcity, $shipstate, $shipzip, $shipcountry, $phone,      $fax,   $user1_val,  $user2_val, $user3_val
       )
    );
  } elsif ( $user2 ne "" ) {
    $sth->bind_columns(
      undef,
      \($username,   $orderid, $name,       $company,   $addr1,    $addr2,     $city,      $state,    $zip,       $country, $password,    $email, $start, $end,       $monthly,
        $cardnumber, $exp,     $lastbilled, $billcycle, $shipname, $shipaddr1, $shipaddr2, $shipcity, $shipstate, $shipzip, $shipcountry, $phone, $fax,   $user1_val, $user2_val
       )
    );
  } elsif ( $user1 ne "" ) {
    $sth->bind_columns(
      undef,
      \($username,   $orderid, $name,       $company,   $addr1,    $addr2,     $city,      $state,    $zip,       $country, $password,    $email, $start, $end, $monthly,
        $cardnumber, $exp,     $lastbilled, $billcycle, $shipname, $shipaddr1, $shipaddr2, $shipcity, $shipstate, $shipzip, $shipcountry, $phone, $fax,   $user1_val
       )
    );
  } else {
    $sth->bind_columns(
      undef,
      \($username, $orderid,    $name, $company,    $addr1,     $addr2,    $city,      $state,     $zip,      $country,   $password, $email,       $start, $end,
        $monthly,  $cardnumber, $exp,  $lastbilled, $billcycle, $shipname, $shipaddr1, $shipaddr2, $shipcity, $shipstate, $shipzip,  $shipcountry, $phone, $fax
       )
    );
  }
  $i = 0;
  while ( $sth->fetch ) {
    &write_table_entry();
    $i++;
    if ( $i > 100 ) {
      last;
    }
  }
  $sth->finish;

  print "</table><p>\n";

  print "<form action=\"https://$admindomain/payment/recurring/$merchant/admin/index.cgi\">\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\"Go To Main Page\">\n";
  print "</form>\n";

  print "</body>\n";
  print "</html>\n";

  $dbh->disconnect;
}

sub write_table_entry {
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  if ( $start ne "" ) {
    $start = sprintf( "%02d/%02d/%04d", substr( $start, 4, 2 ), substr( $start, 6, 2 ), substr( $start, 0, 4 ) );
  }
  if ( $end ne "" ) {
    $end = sprintf( "%02d/%02d/%04d", substr( $end, 4, 2 ), substr( $end, 6, 2 ), substr( $end, 0, 4 ) );
  }
  if ( $lastbilled ne "" ) {
    $lastbilled = sprintf( "%02d/%02d/%04d", substr( $lastbilled, 4, 2 ), substr( $lastbilled, 6, 2 ), substr( $lastbilled, 0, 4 ) );
  }

  print "<tr>\n";
  print "<td colspan=2><form method=post action=\"editcust.cgi\" target=\"NewWindow\">\n";
  print "<font size=-1><b>Username:</b></font> $username\n";
  print "<td><font size=-1><b>Customer Name:</b></font> $name\n";
  print "<td><font size=-1><b>Start Date:</b></font> $start\n";
  print "<tr>\n";
  print "<td><font size=-1><b>Email:</b></font> <a href=\"mailto:$email\">$email</a><input type=hidden name=\"email\" value=\"$email\">\n";
  print "<td><font size=-1><b>End Date:</b></font> $end<input type=hidden name=\"enddate\" value=\"$end\">\n";
  print "<tr>\n";
  print "<td colspan=2><font size=-1><b>Password:</b></font> $password<input type=hidden name=password value=\"$password\">\n";
  print
    "<td colspan=1><font size=-1><b>OrderID:</b></font> <a href=\"https://$admindomain/admin/smps.cgi\?function=details\&orderid=$orderid\" target=\"newwin\">$orderid</a><input type=hidden name=orderid value=\"$orderid\"></td>\n";
  print "<td><font size=-1><b>Recurring Fee:</b></font> $monthly</td>\n";
  print "<tr>\n";
  print "<td rowspan=2><font size=-1> <input type=radio name=\"function\" value=\"cancel\"> <b>Cancel Membership</b></font><br>\n";
  print "<input type=hidden name=\"username\" value=\"$username\">";
  print " <font size=-1><input type=radio name=\"function\" value=\"edit\" checked> <b>Edit Member Info</b></font><br>\n";
  print " <font size=-1><input type=radio name=\"function\" value=\"mailusername\"> <b>Mail UN & PW</b></font><br>\n";
  print " <font size=-1><input type=radio name=\"function\" value=\"viewbilling\"> <b>View Billing History</b></font><br>\n";
  print " <font size=-1><input type=radio name=\"function\" value=\"remove\"> <b>Remove Member</b></font></td>\n";
  print "<td align=center rowspan=2><input type=submit value=\"Submit Request\"></form>\n";
  print "<td rowspan=1><font size=-1><b>Address:</b></font><br>$addr1<br>$addr2<br>$city, $state $zip $country\n";
  print "<td><font size=-1><b>Last Billed:</b></font> $lastbilled\n";

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

  print "<tr bgcolor=\"#80c0c0\"><td colspan=4><hr width=75% height=3></td>\n";
}

sub search {
  ($today) = &miscutils::gendatetime_only();

  $srch_username = &CGI::escapeHTML( $query->param("srch_username") );
  $srch_username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $srch_cardnumber = &CGI::escapeHTML( $query->param("srch_cardnumber") );
  $srch_cardnumber =~ s/[^0-9]//g;

  $srch_expired = &CGI::escapeHTML( $query->param("srch_expired") );
  $srch_expired =~ s/[^a-zA-Z0-9\_\-]//g;

  $srch_exact = &CGI::escapeHTML( $query->param("srch_exact") );
  $srch_exact =~ s/[^a-zA-Z0-9\_\-]//g;

  &html_head("Membership Administration Area - Customer Administration");

  print "<center><div align=center>\n";
  print "<table width=\"90%\"><tr bgcolor=\"#80c0c0\"><td align=center><font size=+1>Membership Administration Area<br>Customer Administration</font></td></table><p>\n";
  print "<table border=1 cellspacing=0 cellpadding=2>\n";

  my @placeholder;
  my $qstr = "SELECT username,company,orderid,name,addr1,addr2,city,state,zip,country,password,email,startdate,enddate,monthly,cardnumber,exp,lastbilled";
  $qstr .= " FROM customer";

  @search_array = ( 'username', 'password', 'name', 'email', 'addr1', 'addr2', 'city', 'state', 'zip', 'orderid', 'cardnumber' );
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
  my $logger = new PlugNPay::Logging::DataLog( { 'collection' => 'receditutils_feature_usage' } );
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

  $i  = 0;
  $op = "WHERE";
  foreach my $var (@search_array) {
    if ( &CGI::escapeHTML( $query->param("srch_$var") ) ne "" ) {
      $qstr .= " $op LOWER($var) LIKE LOWER(?)";
      $op = "AND";
      push( @placeholder, "%" . &CGI::escapeHTML( $query->param("srch_$var") ) . "%" );
      $i++;
    }
  }

  if ( $srch_expired eq "yes" ) {
    $qstr .= " $op enddate<?";
    push( @placeholder, "$today" );
  }
  $qstr = " ORDER BY username";

  $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";

  $i = 0;
  while ( my ( $username, $company, $orderid, $name, $addr1, $addr2, $city, $state, $zip, $country, $password, $email, $start, $end, $monthly, $cardnumber, $exp, $lastbilled ) = $sth->fetchrow ) {
    &write_table_entry;
    $i++;
    if ( $i > 100 ) {
      last;
    }
  }
  $sth->finish;

  if ( $i == 0 ) {
    print "<tr><td>Sorry - No Records Match You Search Criteria</td></tr>\n";
  }

  print "</table><p>\n";

  print "<form action=\"https://$admindomain/payment/recurring/$merchant/admin/index.cgi\">\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\"Go To Main Page\">\n";
  print "</form>\n";

  print "</body>\n";
  print "</html>\n";

  $dbh->disconnect;
}

sub error_file {
  my ($reason) = @_;

  &html_head( "", "https://$admindomain/payment/recurring/$merchant/admin/index.cgi" );

  if ( $reason =~ /in_use/i ) {
    print "<h3>The Username is already being used. Please select a different username.</h3>\n";
  } elsif ( $reason =~ /blank/i ) {
    print "<h3>The Username field was left blank.  Please enter a username.</h3>\n";
  } elsif ( $reason eq 'not_permitted' ) {
    print "<h3>Operation not permitted.</h3>\n";
  } else {
    print "<h3>Either the Username field was left blank or the username is already being used.</h3>\n";
  }
  print "You will be automatically redirected back to your admin area within a few seconds.\n";
  print "<br>If you are not automatically redirected, please <a href=\"https://$admindomain/payment/recurring/$merchant/admin/index.cgi\">click here</a>.\n";

  print "</body>\n";
  print "</html>\n";

  $dbh->disconnect;
}

sub editusername {
  &error_file("not_permitted");
}

sub mailusername {
  $email = &CGI::escapeHTML( $query->param('email') );
  $email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $password = &CGI::escapeHTML( $query->param('password') );
  $password =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $position = index( $email, "\@" );
  if ( ( $position > 1 ) && ( length($email) > 5 ) && ( $position < ( length($email) - 5 ) ) ) {
    $email = substr( $email, 0, 50 );

    my $emailObj = new PlugNPay::Email('legacy');
    $emailObj->setFormat('text');
    $emailObj->setTo($email);
    $emailObj->setFrom($from_email);
    if ( $subject ne "" ) {
      $emailObj->setSubject($subject);
    } else {
      $emailObj->setSubject("Password Confirmation");
    }

    my $emailmessage = "";
    $emailmessage .= "This is an automated message from the membership management system.  \n\n";
    $emailmessage .= "Due to either modifications and/or additions to the membership database, \n";
    $emailmessage .= "you may have been reassigned or assigned a new password.  As a precaution \n";
    $emailmessage .= "the following information is being sent to you for your records.\n\n";
    $emailmessage .= "Your Username is: $username\n";
    $emailmessage .= "Your Password is: $password\n\n";
    if ( $from_signature ne "" ) {
      $emailmessage .= "$from_signature\n";
    } else {
      $emailmessage .= "Support Staff\n";
      $emailmessage .= "PnP Support\n";
    }

    $emailObj->setContent($emailmessage);
    $emailObj->send();
  }

  my $message = "Username and Password have been sent as requested";
  &response_page($message);

  $action = "Username and Password emailed";
  return;
}

sub viewbilling {

  my $startyear = &CGI::escapeHTML( $query->param('startyear') );
  $startyear =~ s/[^0-9]//g;
  my $startmonth = &CGI::escapeHTML( $query->param('startmonth') );
  $startmonth =~ s/[^0-9]//g;
  my $startday = &CGI::escapeHTML( $query->param('startday') );
  $startday =~ s/[^0-9]//g;

  my $endyear = &CGI::escapeHTML( $query->param('endyear') );
  $endyear =~ s/[^0-9]//g;
  my $endmonth = &CGI::escapeHTML( $query->param('endmonth') );
  $endmonth =~ s/[^0-9]//g;
  my $endday = &CGI::escapeHTML( $query->param('endday') );
  $endday =~ s/[^0-9]//g;

  my $startdate = sprintf( "%04d%02d%02d", $startyear, $startmonth, $startday );
  my $enddate   = sprintf( "%04d%02d%02d", $endyear,   $endmonth,   $endday );

  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
  if ( $username eq "" ) {
    $username = "ALL";
  }

  my ( $name, $company );
  if ( $username ne "ALL" ) {
    $sth = $dbh->prepare(
      q{
        SELECT name,company
        FROM customer
        WHERE username=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ( $name, $company ) = $sth->fetchrow;
    $sth->finish;
  }

  $total = 0;

  &html_head("Billing Area");

  if ( ( $startdate > 000000 ) && ( $enddate > 000000 ) && ( $startdate > $enddate ) ) {

    # check for proper range
    if ( $enddate < $startdate ) {
      print "<div align=center>\n";
      print "<b>ERROR: \'Start Date\' cannot be less then specified \'End Date\'.</b>\n";
      print "<br>Please try again with a proper date range.\n";
      print "</div>\n";

      print "<div align=center>\n";
      print "<p><form><input type=button class=\"button\" value=\"Close Window\" onClick=\"closeresults();\"></form>\n";
      print "</div>\n";

      print "</body>\n";
      print "</html>\n";
      exit;
    }
  }

  print "<div align=center>\n";
  print "<font size=\"+1\"><b>Billing for $username\n";
  if ( $name ne "" ) {
    print ", $name\n";
  }
  if ( $company ne "" ) {
    print ", $company\n";
  }
  print "</b></font></br>\n";

  if ( ( $startdate >= 19990101 ) && ( $enddate >= 19990101 ) ) {
    my $startdate_temp = sprintf( "%02d\/%02d\/%04d", $startmonth, $startday, $endyear );
    my $enddate_temp   = sprintf( "%02d\/%02d\/%04d", $endmonth,   $endday,   $endyear );
    print "$startdate_temp -- $enddate_temp<br> &nbsp; <br>\n";
  }

  print "<table border=0 cellspacing=0 cellpadding=4>\n";
  print "<tr>\n";
  if ( $username eq "ALL" ) {
    print "<th>Username</th>";
  }
  print "<th align=left>Billing Date</th>\n";
  print "<th align=left>Order Number</th>\n";
  print "<th align=left>Bill Description</th>\n";
  print "<th>Result</th>\n";
  print "<th>Amount</th>\n";

  my @placeholder;
  my $qstr = "SELECT username,trans_date,amount,orderid,descr,result FROM billingstatus";
  if ( $username eq "ALL" ) {

    # apply date range criteria, if necessary
    if ( ( $startdate >= 19990101 ) && ( $enddate >= 19990101 ) ) {
      $qstr .= " WHERE trans_date>=? AND trans_date<=?";
      push( @placeholder, $startdate, $enddate );
    }
    $qstr .= " ORDER BY username";
  } else {
    $qstr .= " WHERE username=?";
    push( @placeholder, $username );

    # apply date range criteria, if necessary
    if ( ( $startdate >= 19990101 ) && ( $enddate >= 19990101 ) ) {
      $qstr .= " AND trans_date>=? AND trans_date<=?";
      push( @placeholder, $startdate, $enddate );
    }
  }

  $sth_billing = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth_billing->execute(@placeholder) or die "Can't execute: $DBI::errstr";

  while ( my ( $bill_user, $bill_date, $bill_total, $payid, $bill_descr, $bill_result ) = $sth_billing->fetchrow ) {
    my $orderid = $payid;
    if ( ( substr( $orderid, 0, 2 ) eq "98" ) || ( substr( $orderid, 0, 2 ) eq "99" ) ) {
      $orderid = "19$orderid";
    }
    $bill_orderid{$payid} = $orderid;
    $bill_user{$payid}    = $bill_user;
    $bill_date{$payid}    = $bill_date;
    $bill_total{$payid}   = $bill_total;
    $bill_descr{$payid}   = $bill_descr;
    $bill_result{$payid}  = $bill_result;
  }
  $sth_billing->finish;
  $dbh->disconnect;

  foreach $payid ( sort keys %bill_user ) {
    if ( $color eq "d0d0d0" ) {
      $color = "ffffff";
    } else {
      $color = "d0d0d0";
    }
    print "<tr bgcolor=\"#$color\">\n";

    if ( $username eq "ALL" ) {
      print "<td><a href=\"editcust.cgi\?function=viewrecord\&username=$bill_user{$payid}\">$bill_user{$payid}</a></td>";
    }

    $bill_date = sprintf( "%02d/%02d/%04d", substr( $bill_date{$payid}, 4, 2 ), substr( $bill_date{$payid}, 6, 2 ), substr( $bill_date{$payid}, 0, 4 ) );
    print "<td align=left>$bill_date{$payid}</td>\n";
    print
      "<td nowrap><a href=\"https://$admindomain/admin/smps.cgi\?username=$ENV{'REMOTE_USER'}\&function=details\&orderid=$bill_orderid{$payid}\&submit=Details\">$bill_orderid{$payid}</a> &nbsp;</td>\n";

    if ( $bill_result{$payid} eq "success" ) {
      $total = $total + $bill_total{$payid};
    }
    $bill_total = sprintf( "\$%0.2f", $bill_total{$payid} );
    print "<td>$bill_descr{$payid} &nbsp;</td>\n";
    print "<td>$bill_result{$payid} &nbsp;</td>\n";
    print "<td align=right>$bill_total</td>\n";
  }

  print "<tr bgcolor=\"#80c0c0\">\n";
  if ( $username eq "ALL" ) {
    print "<th colspan=5 align=right>Total: &nbsp;</th>\n";
  } else {
    print "<th colspan=4 align=right>Total: &nbsp;</th>\n";
  }
  $total = sprintf( "\$%0.2f", $total );
  print "<th align=right>$total</th>\n";
  print "</table>\n";

  print "<div align=center><p>\n";
  print "<form action=\"editcust.cgi\" method=\"post\">\n";
  if ( $username ne "ALL" ) {
    print "<input type=hidden name=\"function\" value=\"viewrecord\">\n";
    print "<input type=hidden name=\"username\" value=\"$bill_user{$payid}\">\n";
    print "<input type=submit class=\"button\" value=\"Edit Customer\"> &nbsp;\n";
  }
  print "<input type=button class=\"button\" value=\"Close Window\" onClick=\"closeresults();\">\n";
  print "</form>\n";
  print "</div>\n";

  print "</body>\n";
  print "</html>\n";
}

sub chargeback {
  $cardnumber = &CGI::escapeHTML( $query->param('cardnumber') );
  $cardnumber =~ s/[^0-9]//g;

  my $cc            = new PlugNPay::CreditCard($cardnumber);
  my $shacardnumber = $cc->getCardHash();

  $cardnumber = &CGI::escapeHTML( $query->param('cardnumber') );
  $cardnumber =~ s/[^0-9]//g;
  $shortcard = substr( $cardnumber, 0, 4 ) . "**" . substr( $cardnumber, -2, 2 );

  $sth = $dbh->prepare(
    q{
      SELECT username,shacardnumber
      FROM customer
      WHERE cardnumber=?
      OR shacardnumber=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute( "$shortcard", "$shacardnumber" ) or die "Can't execute: $DBI::errstr";
  while ( my ( $username, $chkshacardnumber ) = $sth->fetchrow ) {
    $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
    $array{$username} = $chkshacardnumber;
    if ( $chkshacardnumber eq $shacardnumber ) {
      $exactmatchflag = 1;
    }
  }
  $sth->finish;

  &html_head("Chargeback Results");

  if ( $exactmatchflag == 1 ) {
    print "<h3>The following users were exact matches:</h3>\n";
  } else {
    print "<h3>The following users matched the first four and the last two digits";
    print " in the credit card number:</h3>\n";
  }

  foreach $username ( sort keys %array ) {
    if ( ( $exactmatchflag == 1 ) && ( $array{$username} eq $enccardnumber ) ) {
      print "<a href=\"editcust.cgi?function=viewbilling\&username=$username\">$username</a>(exact match)<br>\n";
    } elsif ( $exactmatch != 1 ) {
      print "<a href=\"editcust.cgi?function=viewbilling\&username=$username\">$username</a><br>\n";
    }
  }

  print "</body>\n";
  print "</html>\n";
}

sub adduser {
  local ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  $orderID = sprintf( "%04d%02d%02d%02d%02d%05d", $year + 1900, $mon + 1, $mday, $hour, $min, $$ );

  $username = &CGI::escapeHTML( $query->param('username') );
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  ####Create Merchant Name
  if ( $username eq "" ) {

    # attempt to generate a unique username for the profile, when one is not specified
    $username = &gen_username();
  }

  # safeguard, when no username was specified.
  if ( $username eq "" ) {
    &error_file("blank");
    return;
  }

  $mn1 = substr( "$username", 0, 19 );
  $mn = $mn1;

  $sth_customer = $dbh->prepare(
    q{
      SELECT username
      FROM customer
      WHERE LOWER(username) LIKE LOWER(?)
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth_customer->execute("$mn") or die "Can't execute: $DBI::errstr";
  ($username) = $sth_customer->fetchrow;
  $sth_customer->finish;

  if ( $username ne "" ) {
    my $message = "That Username is already in use.  Please try another.";
    &response_page($message);
  } else {
    $sth = $dbh->prepare(
      q{
        INSERT INTO customer
        (username,orderid,email)
        VALUES (?,?,?)
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( "$mn", "$orderID", "" ) or die "Can't execute: $DBI::errstr";
    $sth->finish;
    $username = $mn;

    #require plusutils;
    &plusutils::editrecord($username);
  }

  return;
}

sub cancel_member {
  $username = &CGI::escapeHTML( $query->param('username') );
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $password = &CGI::escapeHTML( $query->param('password') );
  $password =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  $publisher_email = &CGI::escapeHTML( $query->param('publisher-email') );
  $publisher_email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $from_email = &CGI::escapeHTML( $query->param('from-email') );
  $from_email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $email_message = &CGI::escapeHTML( $query->param('email-message') );

  $sth = $dbh->prepare(
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
    $sth = $dbh->prepare(
      q{
        UODATE customer
        SET billcycle='0'
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    $sth->finish;

    $position = index( $email, "\@" );
    if ( ( $position > 1 ) && ( length($email) > 5 ) && ( $position < ( length($email) - 5 ) ) ) {
      $email           = substr( $email,           0, 50 );
      $publisher_email = substr( $publisher_email, 0, 50 );

      my $emailObj = new PlugNPay::Email('legacy');
      $emailObj->setFormat('text');
      $emailObj->setTo($email);
      if ( $from_email ne "" ) {
        $emailObj->setFrom($from_email);
      } else {
        $emailObj->setFrom($publisher_email);
      }

      $emailObj->setCC($publisher_email);
      $emailObj->setSubject('Membership Cancellation Confirmation\n');

      $emailObj->setContent($email_message);
      $emailObj->send();
    }

    my $message = "The account for username: $username, has been successfully cancelled.";
    &response_page($message);
  } else {
    my $message = "The Username and Password combination entered were not found in the database.  Please try again and becareful to use the proper CAPITALIZATION.";
    &response_page($message);
  }
}

sub response_page {
  my ($message) = @_;

  &html_head("Membership Administration - System Response");

  print "<div align=center>\n";
  print "<p><font size=\"+1\">$message</font>\n";
  print "<p><form><input type=button class=\"button\" value=\"Close Window\" onClick=\"closeresults();\"></form>\n";
  print "</div>\n";

  print "</body>\n";
  print "</html>\n";

  return;
}

sub response_page_org {
  my ($message) = @_;

  &html_head("Membership Administration - System Response");

  print "<h3>$message</h3>\n";

  print "</body>\n";
  print "</html>\n";

  return;
}

sub transfer {
  $FTPun = &CGI::escapeHTML( $query->param('FTPun') );
  $FTPun =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  $FTPpw = &CGI::escapeHTML( $query->param('FTPpw') );
  $FTPpw =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  # retrieve FTP username/password when none is provided to script
  if ( ( $FTPun eq "" ) && ( $FTPpw eq "" ) ) {
    my $dbh = &miscutils::dbhconnect("pnpmisc");
    my $sth = $dbh->prepare(
      q{
        SELECT ftpun, ftppw
        FROM pnpsetups
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$merchant") or die "Can't execute: $DBI::errstr";
    ( $FTPun, $FTPpw ) = $sth->fetchrow;
    $sth->finish;
    $dbh->disconnect;
  }

  $status = &CGI::escapeHTML( $query->param('status') );
  $status =~ s/[^a-zA-Z0-9\_\-]//g;

  $acct_activity = &CGI::escapeHTML( $query->param('acct_activity') );
  $acct_activity =~ s/[^a-zA-Z0-9\_\-]//g;

  @search_names = $query->param;

  $remotedir = &CGI::escapeHTML( $query->param('remotedir') );
  $destfile  = &CGI::escapeHTML( $query->param('destfile') );
  $portion   = &CGI::escapeHTML( $query->param('portion') );

  $format = &CGI::escapeHTML( $query->param('format') );
  $format =~ s/[^a-zA-Z0-9\_\-]//g;

  $delimiter_type = &CGI::escapeHTML( $query->param('delimiter_type') );
  $delimiter_type =~ s/[^a-zA-Z0-9\_\-]//g;

  if ( $delimiter_type =~ /comma/ ) {
    $first_delimiter = "\"";
    $delimiter       = "\",\"";
  } elsif ( $delimiter_type =~ /tab/ ) {
    $first_delimiter = "";
    $delimiter       = "\t";
  } else {

    # assume comma/quote format
    $first_delimiter = "\"";
    $delimiter       = "\",\"";
  }

  $today = sprintf( "%04d%02d%02d", $yyear, $mmonth, $dday );
  ($today) = &miscutils::gendatetime_only();

  open( TEMP, '>', "tempxfer.txt" );
  print TEMP "$first_delimiter";
  print TEMP "username";

  $searchstr = "SELECT username,";

  $bindvalues[0] = "";
  $i = 1;
  foreach $var (@search_names) {
    if ( ( &CGI::escapeHTML( $query->param("$var") ) eq "export" ) && ( $var ne "username" ) ) {
      print TEMP "$delimiter$var";
      $searchstr .= "$var,";
      $bindvalues[$i] = "";
      $i++;
    }
  }
  chop $searchstr;
  $maxcount = $i;

  print TEMP "$first_delimiter\n";

  $searchstr .= " FROM customer";
  if ( $status eq 'expired' ) {
    $searchstr .= " WHERE (status = 'expired')";
  } elsif ( $acct_activity eq "active" ) {
    $searchstr .= " WHERE ((startdate <= $today) AND (enddate >= $today))";
  } elsif ( $acct_activity eq "expired" ) {
    $searchstr .= " WHERE ((startdate > $today) OR (enddate < $today))";
  }
  $searchstr .= " ORDER BY username";

  $sth = $dbh->prepare(qq{$searchstr}) or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't do: $DBI::errstr";
  while ( my @bindvalues = $sth->fetchrow ) {
    print TEMP "$first_delimiter$bindvalues[0]";
    for ( $i = 1 ; $i < $maxcount ; $i++ ) {
      $bindvalues[$i] =~ s/\"//g;
      print TEMP "$delimiter";
      print TEMP "$bindvalues[$i]";
    }
    print TEMP "$first_delimiter\n";
  }
  $sth->finish;

  close(TEMP);

  if ( $format =~ /download/i ) {

    &html_head("FTP File Transfer");

    print "<div align=center> \n";
    print "<p>To download the file, right click the link below.\n";
    print "<br>Then select the 'Save Target As...' or 'Save Link As...' option.\n";
    print "<p><a href=\"tempxfer.txt\"><font size=\"+1\" color=\"#ff0000\">Download Membership Database</font></a> \n";
    print "</div> \n";

    print "<p><div align=center>\n";
    print "<a href=\"https://$admindomain/payment/recurring/$merchant/admin/index.cgi\"><font size=+1>Click Here to Return to Main Admin Page</font></a>\n";
    print "</div></body>\n";
    print "</html>\n";
  } elsif ( $format =~ /ftp/i ) {

    &html_head("FTP File Transfer");

    $ftp = Net::FTP->new("$host");
    if ( $ftp eq "" ) {
      print "Host $host is no good<br>\n";
      return "failure";
    }

    print "<br><br>\n";

    if ( $ftp->login( "$FTPun", "$FTPpw" ) ) {
      print "<br><br>\n";
      $ftp->cwd("$remotedir");
      print "<br><br>\n";
      $ftp->type("A");
      print "<br><br>\n";
      $ftp->put( "tempxfer.txt", "$destfile" );
      print "<br><br>\n";
      $ftp->quit;
    } else {
      print "<div align=center>\n";
      print "<font size=+2>\n";
      print "Un-Authorized Access\n";
      print "</font>\n";
      print "<p>\n";
      print "<font size=+2>To Obtain Access to this private area, please register properly.</font>\n";
    }
    print "<p><div align=center>\n";
    print "<a href=\"https://$admindomain/payment/recurring/$merchant/admin/index.cgi\"><font size=+2>Click Here to Return to Main Admin Page</font></a>\n";
    print "</div></body>\n";
    print "</html>\n";
  }
  $dbh->disconnect;
  exit;
}

sub dump_billing {
  print "Content-Type: text/plain\n\n";

  $startday = &CGI::escapeHTML( $query->param('startday') );
  $startday =~ s/[^0-9]//g;
  $startmon = &CGI::escapeHTML( $query->param('startmonth') );
  $startmon =~ s/[^0-9]//g;
  $startyear = &CGI::escapeHTML( $query->param('startyear') );
  $startyear =~ s/[^0-9]//g;
  $start_date = $startyear . $startmon . $startday;

  $endday = &CGI::escapeHTML( $query->param('endday') );
  $endday =~ s/[^0-9]//g;
  $endmon = &CGI::escapeHTML( $query->param('endmonth') );
  $endmon =~ s/[^0-9]//g;
  $endyear = &CGI::escapeHTML( $query->param('endyear') );
  $endyear =~ s/[^0-9]//g;
  $end_date = $endyear . $endmon . $endday;

  $sth_billing = $dbh->prepare(
    q{
      SELECT username,trans_date,amount,orderid,descr,result
      FROM billingstatus
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth_billing->execute() or die "Can't execute: $DBI::errstr";
  while ( my ( $username, $bill_date, $bill_total, $orderid, $bill_descr, $bill_result ) = $sth_billing->fetchrow ) {
    $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
    my ( $tstmo, $tstdy, $tstyr ) = split( '/', $bill_date );
    my $tstdate = $tstyr . $tstmo . $tstdy;
    if ( ( $tstdate >= $start_date ) && ( $tstdate < $end_date ) ) {
      $$username{$orderid}   = 1;
      $bill_user{$orderid}   = $username;
      $bill_date{$orderid}   = $bill_date;
      $bill_total{$orderid}  = $bill_total;
      $bill_descr{$orderid}  = $bill_descr;
      $bill_result{$orderid} = $bill_result;
    }
  }
  $sth_billing->finish;

  $sth = $dbh->prepare(
    q{
      SELECT username,orderid
      FROM customer
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  while ( my ( $username, $orderid ) = $sth->fetchrow ) {
    $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
    $orderids{$username} = $orderid;
  }
  $sth->finish;
  $dbh->disconnect;

  $dbh = &miscutils::dbhconnect("pnpdata");    ## Trans_Log

  foreach $username ( sort keys %orderids ) {
    my $sth = $dbh->prepare(
      q{
        SELECT trans_date,finalstatus,amount
        FROM trans_log
        WHERE orderid=?
        AND trans_date>=?
        AND trans_date<?
        AND username=?
        AND operation='auth'
        AND finalstatus='success'
        AND (duplicate IS NULL OR duplicate='')
      }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query );
    $sth->execute( $orderids{$username}, $start_date, $end_date, $merchant ) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query );
    ( $trans_date, $finalstatus, $amount ) = $sth->fetchrow;
    $sth->finish;
    if ( $trans_date ne "" ) {
      $amount = substr( $amount, 3 );
      print "$username\t$orderids{$username}\t$trans_date\t$amount\tInitial Purchase\t$finalstatus\n";
    }
    foreach $orderid ( sort keys %$username ) {
      print "$username\t$orderid\t$bill_date{$orderid}\t$bill_total{$orderid}\t$bill_descr{$orderid}\t$bill_result{$orderid}\n";
    }
  }

  $dbh->disconnect;

  exit;
}

sub deleteimport {
  open( OUTFILE, '>', "importfail.txt" );
  close(OUTFILE);
}

sub web900 {
  $filename = &CGI::escapeHTML( $query->param('filename') );

  $pincost = &CGI::escapeHTML( $query->param('pin-cost') );
  $pincost =~ s/[^a-zA-Z0-9\_\-\.\ ]//g;

  $web900file    = "web900/pinfile" . $pincost;
  $web900filebac = "web900/pinfilebac" . $pincost;

  $web900file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
  $web900filebac =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
  &sysutils::filelog( "append", ">>$web900file" );
  open( WEB900, '>>', "$web900file" );
  &sysutils::filelog( "append", ">>$web900filebac" );
  open( WEB900BAC, '>>', "$web900filebac" );
  while (<$filename>) {
    s/[^0-9a-zA-Z]//g;
    print WEB900 $_ . "\n";
    print WEB900BAC $_ . "\n";
  }
  close(WEB900);
  close(WEB900BAC);

  my $message = "PIN File has been uploaded successfully";
  &response_page($message);

  exit;
}

sub update_payplans {
  open( OUTFILE, '>', "paymentplans.txt" );

  #$filename = &CGI::escapeHTML($query->param('filename'));
  $filename = $query->param('filename');

  #print "AA:$filename\n";
  while (<$filename>) {
    s/[^\w\-\t\:\/\.\!\,\|]//g;

    #print "$_\n";
    print OUTFILE "$_\n";
  }
  close(OUTFILE);
  &view_payplans();
}

sub view_payplans {

  &html_head("Edit Payment Plans");

  print "<b>Current Payment Plans</b><p>\n";
  print "<table border=1 cellspacing=0 cellpadding=2>\n";
  $path_plans = "paymentplans.txt";
  &sysutils::filelog( "read", "$path_plans" );
  open( PAYPLANS, '<', "$path_plans" ) or die "Can't open paymentplans.txt for reading. $!";
  my (@fields);
  while (<PAYPLANS>) {
    chop;
    my @data = split('\t');
    if ( substr( $data[0], 0, 1 ) eq "\!" ) {
      $parseflag = 1;
      (@fields) = (@data);
      $fields[0] = substr( $data[0], 1 );
      print "<tr>";
      foreach $var (@fields) {
        $var =~ tr/A-Z/a-z/;
        print "<th>$var</th>";
      }
      print "</tr>\n";
      next;
    }
    if ( $parseflag == 1 ) {
      $i = 0;
      print "<tr>";
      foreach $var (@fields) {
        $data{$var} = $data[$i];
        print "<td>$data[$i]</td>";
        $i++;
      }
      print "</tr>\n";
    }
  }
  print "</table>\n";

  print "<form method=post action=\"https://$admindomain/payment/recurring/$ENV{'REMOTE_USER'}\/admin/editcust.cgi\"> \n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\"Return to Main Page\" onClick=\"closeresults()\;\">\n";
  print "</form>\n";

  print "</body>\n";
  print "</html>\n";
}

sub importusers {
  my ($extrafields) = @_;

  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
  my $inputValidator = new PlugNPay::InputValidator('recurring');
  $filename = $inputValidator->filter( 'destfile', &CGI::escapeHTML( $query->param('upload-file') ) );

  &html_head("Membership Administration Area - File Import");

  print "<pre>\n";

  open( OUTFILE, '>', "importfail.txt" );
  while (<$filename>) {
    $_ =~ s/\n//g;
    $_ =~ s/\r//g;
    $line = $_;

    my $error_line = $line;
    my ( $match, $filtered );
    if ( $error_line =~ /(3|4|5|6|7\d{12,15})/ ) {
      $match = $1;
      $filtered =~ s/./X/g;
      $error_line =~ s/$match/$filtered/g;
    }

    (@fields) = split(/\t/);

    $startdate = substr( $fields[23], 6, 4 ) . substr( $fields[23], 0, 2 ) . substr( $fields[23], 3, 2 );
    $enddate   = substr( $fields[24], 6, 4 ) . substr( $fields[24], 0, 2 ) . substr( $fields[24], 3, 2 );

    $cardnumber = $fields[26];
    if ( length($cardnumber) > 4 ) {
      ( $enccardnumber, $encryptedDataLen ) = &rsautils::rsa_encrypt_card( $cardnumber, '/home/p/pay1/pwfiles/keys/key' );
    }

    $cardnumber = $fields[26];
    $cardnumber = substr( $fields[26], 0, 4 ) . "**" . substr( $fields[26], -2, 2 );

    $uname = $fields[0];
    $uname =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
    $psswd = $fields[3];
    $email = $fields[21];
    $email =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

    $insertstr = "INSERT INTO customer ";
    $insertstr .= "(username,orderid,plan,password,";
    $insertstr .= "name,company,addr1,addr2,city,state,zip,country,";
    $insertstr .= "shipname,shipaddr1,shipaddr2,shipcity,shipstate,shipzip,shipcountry,phone,";
    $insertstr .= "fax,email,billcycle,startdate,enddate,monthly,";
    $insertstr .= "cardnumber,enccardnumber,length,exp";
    $valuestr = "?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?";

    $i                = 28;
    @extrafieldvalues = ();
    foreach $var (@extrafields) {
      $insertstr .= ",$var";
      $valuestr  .= ",?";
      push( @extrafieldvalues, $fields[$i] );
      $i++;
    }

    $insertstr .= ") VALUES ($valuestr)";

    $enccardnumber = &smpsutils::storecardnumber( $database, $username, 'recedit_import', $enccardnumber, 'rec' );

    $sth = $dbh->prepare(qq{$insertstr}) or print OUTFILE "$DBI::errstr\n$error_line\r\n";
    $sth->execute(
      "$fields[0]",  "$fields[1]",  "$fields[2]",  "$fields[3]",     "$fields[4]",  "$fields[5]",  "$fields[6]",  "$fields[7]",
      "$fields[8]",  "$fields[9]",  "$fields[10]", "$fields[11]",    "$fields[12]", "$fields[13]", "$fields[14]", "$fields[15]",
      "$fields[16]", "$fields[17]", "$fields[18]", "$fields[19]",    "$fields[20]", "$fields[21]", "$fields[22]", "$startdate",
      "$enddate",    "$fields[25]", "$cardnumber", "$enccardnumber", "$length",     "$fields[27]", @extrafieldvalues
      )
      or print OUTFILE "$DBI::errstr\n$error_line\r\n";
    $sth->finish;

    if ( $installbilling eq "yes" ) {
      my $sth_install = $dbh->prepare(
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

    $sendemail = &CGI::escapeHTML( $query->param('sendemail') );
    $sendemail =~ s/[^a-zA-Z0-9\_\-]//g;
    if ( $sendemail eq "yes" ) {
      $position = index( $email, "\@" );
      if ( ( $position > 1 ) && ( length($email) > 5 ) && ( $position < ( length($email) - 5 ) ) ) {
        $email = substr( $email, 0, 50 );

        my $emailObj = new PlugNPay::Email('legacy');
        $emailObj->setTo($email);
        $emailObj->setFrom($from_email);
        if ( $subject ne "" ) {
          $emailObj->setSubject($subject);    # god i've written this same code so many times
        } else {
          $emailObj->setSubject('Password Confirmation');
        }

        my $emailmessage = "";
        $emailmessage .= "Thank you for joining $from_signature. Please retain the \n";
        $emailmessage .= "following for your records.\n\n";
        $emailmessage .= "Your Username is: $uname\n";
        $emailmessage .= "Your Password is: $psswd\n\n";
        if ( $from_signature ne "" ) {
          $emailmessage .= "$from_signature\n";
        } else {
          $emailmessage .= "Support Staff\n";
          $emailmessage .= "PnP Support\n";
        }

        $emailObj->setContent($emailmessage);
        $emailObj->send();
      }
    }
  }
  close(OUTFILE);
  $dbh->disconnect;

  print "\n</pre>\n";
  print " If this area is blank, all users were imported successfully.<br><pre>\n";

  $firstflag = 1;
  open( INFILE, '<', "importfail.txt" );
  while (<INFILE>) {
    if ( $firstflag == 1 ) {
      print "<h3>The Following records could not be imported.</h3>";
      print " Please do not retry unless the problem has been fixed.\n";
      print " Only failed records should be re-imported.";
      print " <a href=\"importfail.txt\"> importfail.txt</a> contains the failed records.";
      print " <a href=\"receditutils.cgi?function=deleteimport\">Click here</a> to remove the contents of the file.\n";
      print " If you can't figure out the problem, please use the HelpDesk and\n";
      print " let us know you\n were trying to import new customers into recurring\n";
      print " and some didn't make it.<br><pre>\n\n";
      $firstflag = 0;
    }
    ( $username, $orderid ) = split(/\t/);
    print "$username $orderid<br>\n";
  }
  close(INFILE);
  print "\n\n</pre>\n";
  print "</body>\n";
  print "</html>\n";

}

sub import_recurring {
  $extracols = &CGI::escapeHTML( $query->param('extracols') );
  $extracols =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  $proc_payments = &CGI::escapeHTML( $query->param('proc_payments') );
  $proc_payments =~ s/[^a-zA-Z0-9\_\-]//g;
  my $inputValidator = new PlugNPay::InputValidator('recurring');

  $filename = $inputValidator->filter( 'destfile', &CGI::escapeHTML( $query->param('upload-file') ) );

  local ( $ssec, $mmin, $hhour, $dday, $mmonth, $yyear, $wday, $yday, $isdst ) = gmtime(time);
  $date = sprintf( "%04d%02d%02d%02d%02d%02d", $yyear + 1900, $mmonth, $dday, $$hhour, $mmin, $ssec );
  $merchant =~ s/[^0-9a-zA-Z]//g;
  &sysutils::filelog( "write", ">/home/p/pay1/web/payment/recurring/$merchant/admin/import.txt" );
  open( FILE, '>', "/home/pay1/web/payment/recurring/$merchant/admin/import.txt" );
  print FILE "IMPORT TIME $yyear$mmonth$dday$hhour$mmin$ssec\n";

  @header_array = ();
  @error_array  = ();

  $header_line = <$filename>;

  #chomp $header_line;
  $header_line =~ s/\n//g;
  $header_line =~ s/\r//g;

  print FILE "$header_line\n";

  @header_array = split( /\t/, $header_line );

  shift(@header_array);

  for ( $i = 0 ; $i <= $#header_array ; $i++ ) {
    $header_array[$i] =~ tr/A-Z/a-z/;
  }

  @required_element_array = ('username');

  $required_error_flag = "no";
  foreach $testelement (@required_element_array) {
    if ( $header_line !~ /$testelement/i ) {
      $missed              = $testelement;
      $required_error_flag = "yes";
    }
  }

  if ( $required_error_flag eq "yes" ) {
    print "Missing $missed from header $header_line.\n";
  }

  while (<$filename>) {
    $| = 1;
    $_ =~ s/\n//g;
    $_ =~ s/\r//g;

    $linetest = $_;

    $linetest =~ s/^W//g;
    if ( length($linetest) < 1 ) {
      next;
    }

    @line_array = ();
    %linehash   = ();
    @line_array = split(/\t/);
    shift(@line_array);
    $i = 0;
    foreach $var (@header_array) {
      $var =~ tr/A-Z/a-z/;
      $var =~ s/\W//g;
      $linehash{$var} = $line_array[$i];
      $linehash{$var} =~ s/[^a-zA-Z0-9_\.\/\@:\-\ \|]//g;
      if ( $var =~ /date/i ) {
        if ( index( $linehash{$var}, "/" ) > 0 ) {
          ( $mo, $dy, $yr ) = split( '/', $linehash{$var} );
          if ( length($yr) == 2 ) {
            $yr += 2000;
          }
          $linehash{$var} = sprintf( "%04d%02d%02d", $yr, $mo, $dy );
        }
      }
      $i++;

      if ( $var =~ /(cardnum|card.num)/i ) {
        my $filteredCC = substr( $linehash{$var}, 0, 4 ) . '**' . substr( $linehash{$var}, -4, 4 );
        printf FILE ( "%s\t", $filteredCC );
      } elsif ( $var =~ /cvv|cvc/i ) {
        my $filteredCVV = $linehash{$var};
        $filteredCVV =~ s/./X/g;
        printf FILE ( "%s\t", $filteredCVV );
      } else {
        printf FILE ( "%s\t", $linehash{$var} );
      }
    }
    print FILE "\n";

    &check_hash("$extracols");

    my $username = $linehash{'username'};

    if ( exists $error{$username} ) {
      next;
    }

    if ( !exists $linehash{'orderid'} ) {
      $linehash{'orderid'} = $linehash{'username'};
    }

    if ( $proc_payments == 1 ) {
      my @array = %linehash;
      %result = &proc_payments(@array);
      if ( $result{'FinalStatus'} ne "success" ) {
        $error{$username} .= "Credit Card Declined: $result{'MErrMsg'}. $username was not imported.|";
        next;
      } else {
        $linehash{'orderid'} = $result{'order-id'};

        #foreach $key (sort keys %result) {
        #  print "$key:$result{$key}:<br>\n";
        #}
        #last;
      }
    }

    foreach $key ( keys %linehash ) {
      if ( !exists $length_hash{$key} ) {
        delete $linehash{$key};
      }
    }

    push @import_array, {%linehash};
  }
  close(FILE);
  $insert_flag = "yes";

  for ( $i = 0 ; $i <= $#import_array ; $i++ ) {
    &insert_user($i);
  }
  my @array = %error;
  &output_errors(@array);
}

sub proc_payments {
  my (%input) = @_;
  my (%query);

  my %fieldmap = (
    'name',    'card-name',    'addr1',       'card-address1', 'addr2',     'card-address2', 'city',       'card-city',   'state',    'card-state', 'zip',       'card-zip',
    'country', 'card-country', 'shipname',    'shipname',      'shipaddr1', 'address1',      'shipaddr2',  'address2',    'shipcity', 'city',       'shipstate', 'state',
    'shipzip', 'zip',          'shipcountry', 'country',       'monthly',   'card-amount',   'cardnumber', 'card-number', 'exp',      'card-exp'
  );

  foreach $key ( keys %input ) {
    if ( exists $fieldmap{$key} ) {
      $query{ $fieldmap{$key} } = $input{$key};
    } else {
      $query{$key} = $input{$key};
    }
  }

  $input{'monthly'} =~ s/[0-9\.]//g;
  $input{'card-amount'} =~ s/[0-9\.]//g;

  if ( $input{'card-amount'} < 0 ) {
    $query{'card-amount'} = $input{'monthly'};
  } elsif ( $input{'monthly'} > 0 ) {
    $query{'card-amount'} = $input{'card-amount'};
  } else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'}     = "Amount less than or equal to zero.";
    return %result;
  }

  if ( $input{'cardnumber'} =~ / / ) {
    ( $query{'routingnum'}, $query{'accountnum'} ) = split( / /, $input{'cardnumber'} );
    $query{'accttype'} = "checking";
  }

  $query{'publisher-name'} = $merchant;

  if ( exists $mckutils::query{'orderID'} ) {
    $query{'orderID'} = &miscutils::incorderid( $mckutils::query{'orderID'} );
    print "OID:$query{'orderID'}:<br>\n";
  }

  my @array = %query;
  $payment = mckutils->new(@array);

  %result = $payment->purchase("auth");

  $payment->database();

  $payment->email();

  return %result;
}

sub insert_user {
  my ($entry) = @_;

  $allow_update = &CGI::escapeHTML( $query->param('allow_update') );
  $allow_update =~ s/[^a-zA-Z0-9\_\-]//g;

  my $cardnumber = $import_array[$entry]{'cardnumber'};

  if ( $cardnumber ne "" ) {
    ( $enccardnumber, $encryptedDataLen ) = &rsautils::rsa_encrypt_card( $cardnumber, '/home/p/pay1/pwfiles/keys/key' );
    $import_array[$entry]{'cardnumber'} = substr( $import_array[$entry]{'cardnumber'}, 0, 4 ) . '**' . substr( $import_array[$entry]{'cardnumber'}, length( $import_array[$entry]{'cardnumber'} ) - 2, 2 );

    my $cc = new PlugNPay::CreditCard( $query{'card-number'} );
    $shacardnumber = $cc->getCardHash();
  }

  my $username = $import_array[$entry]{'username'};
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $dbh = &miscutils::dbhconnect($merchant);
  my $sth_merchants = $dbh->prepare(
    q{
      SELECT username
      FROM customer
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth_merchants->execute("$username") or die "Can't execute: $DBI::errstr";
  ($test) = $sth_merchants->fetchrow;
  $sth_merchants->finish;

  if ( ( $test ne "" ) && ( $allow_update == 1 ) ) {    # Update Record

    if ( $enccardnumber ne "" ) {
      $enccardnumber = &smpsutils::storecardnumber( $database, $username, 'recedit_insert', $enccardnumber, 'rec' );
    }

    my $db_query = "UPDATE customer SET ";

    my $column_string = "";
    my @value_string  = ();

    foreach $column ( keys %{ $import_array[$entry] } ) {
      $column_string .= $column . "=?\,";
      push( @value_string, $import_array[$entry]{$column} );
    }

    if ( $cardnumber ne "" ) {
      $column_string .= "enccardnumber=?, length=?, shacardnumber=?";
      push( @value_string, "$enccardnumber", "$encryptedDataLen", "$shacardnumber" );
    } else {
      chop $column_string;
    }

    $column_string .= " WHERE username=?";
    push( @value_string, "$username" );

    $db_query .= $column_string;

    $sth = $dbh->prepare(qq{$db_query}) or $error{$username} .= "failed prepare " . $username . $DBI::errstr;
    $sth->execute(@value_string) or $error{$username} .= "failed insert " . $username . $DBI::errstr;
    $sth->finish;

    if ( !exists $error{$username} ) {
      print "Username Updated:$username<br>\n";
    } else {
      print "Failed Update:$username<br>\n";
    }
  } elsif ( ( $test ne "" ) && ( $allow_update != 1 ) ) {    # Display Error
    $error{$username} = "Allow Update Disabled.  Username $username already exists in database.|";
  } else {                                                   # Insert Record

    if ( $enccardnumber ne "" ) {
      $enccardnumber = &smpsutils::storecardnumber( $database, $username, 'recedit_insert', $enccardnumber, 'rec' );
    }

    my @placeholder;
    my $db_query = "INSERT INTO customer ";

    my $col_string = "(";
    my $val_string = " VALUES (";

    foreach my $column ( keys %{ $import_array[$entry] } ) {
      my $column =~ s/[^a-zA-Z0-9\_\-]//g;
      if ( $column ne '' ) {
        $col_string .= sprintf( "%s\,", $column );
        $val_string .= "?,";
        push( @placeholder, $import_array[$entry]{$column} );
      }
    }

    $col_string .= "enccardnumber,length,shacardnumber)";
    $val_string .= "?,?,?)";
    push( @placeholder, $enccardnumber, $encryptedDataLen, $shacardnumber );

    $db_query .= $col_string . $val_string;

    $sth = $dbh->prepare(qq{$db_query}) or &error($username);
    $sth->execute(@placeholder) or &error($username);
    $sth->finish;

    if ( !exists $error{$username} ) {
      print "Username Inserted:$username<br>\n";

      # write to service history
      my $action      = "Profile Imported";
      my $reason      = "Customer profile was imported.  Merchant initiated request from $ENV{'REMOTE_ADDR'}";
      my $now         = time();
      my $sth_history = $dbh->prepare(
        q{
          INSERT INTO history
          (trans_time,username,action,descr)
          VALUES (?,?,?,?)
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_history->execute( $now, $username, $action, $reason ) or die "Can't execute: $DBI::errstr";
      $sth_history->finish;
    } else {
      print "Failed Insert:$username<br>\n";
    }
  }

  $dbh->disconnect;
}

sub check_hash {
  my ($extracols) = @_;

  if ( !scalar keys %length_hash ) {
    %length_hash = (
      'username',  '54', 'plan',        '19', 'name',     '39', 'addr1',    '39', 'addr2',     '39', 'balance',   '8',  'country',    '39', 'billcycle', '9',
      'startdate', '9',  'enddate',     '9',  'city',     '39', 'state',    '39', 'zip',       '13', 'monthly',   '8',  'cardnumber', '36', 'exp',       '10',
      'orderid',   '22', 'purchaseid',  '39', 'password', '19', 'shipname', '39', 'shipaddr1', '39', 'shipaddr2', '39', 'shipcity',   '39', 'shipstate', '39',
      'shipzip',   '13', 'shipcountry', '39', 'phone',    '15', 'fax',      '10', 'email',     '39', 'status',    '10', 'acct_code',  '15'
    );

    if ( $extracols ne "" ) {
      my @split_extracols = split( / /, $extracols );
      foreach ( my $i = 0 ; $i <= $#split_extracols ; $i++ ) {
        $length_hash{"$split_extracols[$i]"} = 256;

        #print "SET LENGTH: $split_extracols[$i] = $length_hash{$split_extracols[$i]}<br>\n";
      }
    }
  }

  my $username = $linehash{'username'};
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  foreach $testvar ( keys %length_hash ) {
    if ( length( $linehash{$testvar} ) > $length_hash{$testvar} ) {
      $error{$username} .= "$testvar to long |$linehash{$testvar}|";
      $linehash{$testvar} = substr( $linehash{$testvar}, 0, $length_hash{$testvar} );
    }
  }

  foreach $testvar (@required_element_array) {
    if ( $linehash{$testvar} eq "" ) {
      $error{$username} .= "$testvar empty but required.|";
    }
  }

  if ( $linehash{'cardnumber'} =~ / / ) {
    ( $linehash{'routingnum'}, $linehash{'accountnum'} ) = split( / /, $linehash{'cardnumber'} );
    $linehash{'cardnumber'} = "";
  }

  if ( $linehash{'cardnumber'} ne "" ) {
    $linehash{'cardnumber'} =~ s/\D//g;
    $test = &miscutils::luhn10( $linehash{'cardnumber'} );
    if ( $test eq "failure" ) {
      $error{$username} .= "Credit card number failed luhn-10 test.|";
    }
  }

  if ( $linehash{'exp'} ne "" ) {
    my $card_exp = $linehash{'exp'};
    $card_exp =~ s/[^0-9]//g;
    my $length = length($card_exp);
    my $year = substr( $card_exp, -2 );
    if ( $length == 4 ) {
      $linehash{'exp'} = substr( $card_exp, 0, 2 ) . "/" . $year;
    } elsif ( $length == 3 ) {
      $linehash{'exp'} = "0" . substr( $card_exp, 0, 1 ) . "/" . $year;
    }
  }

  if ( $linehash{'routingnum'} ne "" ) {
    $linehash{'routingnum'} =~ s/\D//g;
    $test = &miscutils::mod10( $linehash{'routingnum'} );
    if ( $test eq "failure" ) {
      $error{$username} .= "Bank routing number failed mod-10 test.|";
    }
  }
  if ( ( $linehash{'cardnumber'} eq "" ) && ( $linehash{'routingnum'} ne "" ) && ( $linehash{'accountnum'} ne "" ) ) {
    $linehash{'cardnumber'} = $linehash{'routingnum'} . " " . $linehash{'accountnum'};
  }
  if ( $linehash{'monthly'} ne "" ) {
    $linehash{'monthly'} =~ s/[^0-9\.]//g;
  }
  if ( $linehash{'balance'} ne "" ) {
    $linehash{'balance'} =~ s/[^0-9\.]//g;
  }

  delete $linehash{'routingnum'};
  delete $linehash{'accountnum'};
}

sub error {
  my ($username) = @_;
  $error{$username} = "failed prepare " . $username . " " . $DBI::errstr;

  #print "ERROR:$DBI::errstr<br>\n";
}

sub delete_user {
  my ($entry) = @_;
  my $username = $import_array[$entry]{'username'};
  $username =~ s/[^0-9a-zA-Z\@\.\-\_]//g;

  $sth = $dbh->prepare(
    qq{
       delete from customer where username=?
        }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  $sth->finish;

  $sth2 = $dbh->prepare(
    qq{
       delete from billingstatus where username=?
        }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth2->execute("$username") or die "Can't execute: $DBI::errstr";
  $sth2->finish;

  $sth3 = $dbh->prepare(
    qq{
       delete from history where username=?
        }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth3->execute("$username") or die "Can't execute: $DBI::errstr";
  $sth3->finish;

  eval {
    $sth4 = $dbh->prepare(
      qq{
         delete from support where username=?
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth4->execute("$username") or die "Can't execute: $DBI::errstr";
    $sth4->finish;
  };

  print "Username Deleted: $username<br>\n";
}

sub output_errors {
  my (%error) = @_;
  foreach $line ( sort keys %error ) {
    print "Username Failed:$line, $error{$line}<br>\n";
  }
}

sub gen_username {

  # Generate unique username for new profile in merchant's MM database

  my $attempt = 0;
  my $answer  = "";

  while (1) {
    $answer = &randomalphanum(16);    # generates random value
    $answer =~ s/[^a-zA-Z0-9]//g;
    $answer = lc( substr( $answer, 0, 8 ) );

    my $sth_merchants = $dbh->prepare(
      qq{
       select username
       from customer
       where username=?
    }
      )
      or die "Can't do: $DBI::errstr";
    $sth_merchants->execute("$answer") or die "Can't execute: $DBI::errstr";
    my ($test) = $sth_merchants->fetchrow;
    $sth_merchants->finish;

    if ( $test ne "" ) {

      # found unique username
      last;
    }

    # safeguard from looping forever
    $attempt = $attempt + 1;
    if ( $attempt > 100 ) {

      # safeguard reached, force exit of loop
      last;
    }
  }

  return "$answer";
}

sub randomalphanum {
  my ($length) = @_;
  my ( $pass, $letter, $asciicode );
  while ( $length > 0 ) {
    my $asciicode = int( rand 1 * 123 );
    if ( ( $asciicode > 48 && $asciicode < 58 )
      || ( $asciicode > 64 && $asciicode < 91 )
      || ( $asciicode > 96 && $asciicode < 123 ) ) {
      $letter = chr($asciicode);
      if ( $letter !~ /[Iijyvl10Oo]/ ) {
        $length--;
        $pass .= $letter;
      }
    }
  }
  return $pass;
}

1;
