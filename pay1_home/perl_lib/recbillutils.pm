package recbillutils;

require 5.001;
$| = 1;

use CGI;
use DBI;

#use CCLibMCK;
use rsautils;
use Time::Local qw(timegm);
use miscutils;
use Math::BigInt;
use PlugNPay::CardData;

sub new {
  my $type = shift;
  ( $merchant, $merchant_type, $processor_type, $mode ) = @_;

  local ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  $orderID = sprintf( "%04d%02d%02d%02d%02d%05d", $year + 1900, $mon + 1, $mday, $hour, $min, $$ );

  print "Content-Type: text/html\n\n";

  &html_head( "Graphs", "Merchant: $merchant" );
  $| = 1;

  $dbh = &miscutils::dbhconnect("pnpmisc");

  $sth = $dbh->prepare(
    qq{
        select email,company
        from customers
        where username=?
        }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute("$merchant") or die "Can't execute: $DBI::errstr";
  ( $merchant_email, $mcompany ) = $sth->fetchrow;
  $sth->finish;

  $sth_pnpsetup = $dbh->prepare(
    qq{
        select fromemail,recmessage
        from pnpsetups
        where username=?
        }
    )
    or die "Can't do: $DBI::errstr";
  $sth_pnpsetup->execute("$merchant") or die "Can't execute: $DBI::errstr";
  ( $fromemail, $recmessage ) = $sth_pnpsetup->fetchrow;
  $sth_pnpsetup->finish;

  $dbh->disconnect;

  $query = new CGI;

  $billingflag = &CGI::escapeHTML( $query->param('billing') );
  $billingflag =~ s/[^a-zA-Z0-9\_\-]//g;

  $function = &CGI::escapeHTML( $query->param('function') );
  $function =~ s/[^a-zA-Z0-9\_\-]//g;

  $form_username = &CGI::escapeHTML( $query->param('username') );
  $form_username =~ s/[^_0-9a-zA-Z\-\@\.]//g;

  $passphrase = &CGI::escapeHTML( $query->param('passphrase') );
  $passphrase =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  $showall = &CGI::escapeHTML( $query->param('showall') );
  $showall =~ s/[^a-zA-Z0-9\_\-]//g;

  $FTPun = &CGI::escapeHTML( $query->param('FTPun') );
  $FTPun =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  $FTPpw = &CGI::escapeHTML( $query->param('FTPpw') );
  $FTPpw =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  %month_array  = ( 1,     "Jan", 2,     "Feb", 3,     "Mar", 4,     "Apr", 5,     "May", 6,     "Jun", 7,     "Jul", 8,     "Aug", 9,     "Sep", 10,    "Oct", 11,    "Nov", 12,    "Dec" );
  %month_array2 = ( "Jan", "01",  "Feb", "02",  "Mar", "03",  "Apr", "04",  "May", "05",  "Jun", "06",  "Jul", "07",  "Aug", "08",  "Sep", "09",  "Oct", "10",  "Nov", "11",  "Dec", "12" );

  ( $sec, $min, $hour, $mday, $mon, $yyear, $wday, $yday, $isdst ) = gmtime(time);
  $gm_month     = $mon + 1;
  $gm_day       = $mday;
  $gm_year      = $yyear + 1900;
  $today        = sprintf( "%04d%02d%02d", $gm_year, $gm_month, $gm_day );
  $lookahead    = 6;
  $fixlookahead = $lookahead;

  return [], $type;
}

sub main {
  $dbh = &miscutils::dbhconnect("$merchant");

  $emailmessage = "";

  if ( $function ne "sendbill" ) {
    &gen_html();
    exit;
  }

  $total   = 0;
  $orderID = &GenerateOrderID;
  &initialize_batch();

  $billmonths = ( $gm_year * 12 ) + ( $gm_month - 1 );
  $billdays = $gm_day;

  my $cd = new PlugNPay::CardData();

  $sth = $dbh->prepare(
    qq{
      select username,name,addr1,addr2,city,state,zip,country,phone,fax,email,startdate,enddate,billcycle,monthly,cardnumber,exp,lastbilled,enccardnumber,length,lastattempted
      from customer
      order by username
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  $rv = $sth->bind_columns( undef,
    \( $username, $name, $addr1, $addr2, $city, $state, $zip, $country, $phone, $fax, $email, $start, $end, $billcycle, $monthly, $cardnumber, $exp, $lastbilled, $enccardnumber, $length, $lastattempted )
  );

  # emailobj
  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFromat('text');
  $emailObj->setGatewayAccount($merchant);
  $emailObj->setTo($merchant_email);
  $emailObj->setFrom('support@plugnpay.com');
  $emailObj->setSubject('Plug and Pay Recurring Payment Failure Notification');

  while ( $sth->fetch ) {

    my $cd                 = new PlugNPay::CardData();
    my $ecrypted_card_data = '';
    eval { $ecrypted_card_data = $cd->getRecurringCardData( { customer => "$username", username => "$merchant" } ); };
    if ( !$@ ) {
      $enccardnumber = $ecrypted_card_data;
    }

    if ( ( $billcycle > 0 ) && ( $lastattempted < $today ) ) {
      if ( $merchant_type eq "email_on_failure" ) {
        $emailmessage .= &calculate_amountdue_email();
      } else {
        $emailmessage .= &calculate_amountdue();
      }

      if ( ( $function eq "sendbill" ) && ( $amountdue > 0 ) && ( $billcycle > 0 ) ) {
        $passphrase = &CGI::escapeHTML( $query->param('passphrase') );
        $passphrase =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

        $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
        $cardnumber =~ s/[^0-9]//g;

        $orderID = Math::BigInt->new("$orderID");
        $orderID = $orderID + 1;
        $orderID =~ s/\+//;

        $price   = sprintf( "%3s %.2f", "usd", $amountdue );
        $country = "USA";
        $addr    = $addr1 . " " . $addr2;

        ( $exp_month, $exp_year ) = split( /\//, $exp );

        if ( $exp_year > 90 ) {
          $exp_year = 1900 + $exp_year;
        } else {
          $exp_year = 2000 + $exp_year;
        }
        $exp_date2 = $exp_year . $exp_month;
        while ( substr( $today, 0, 6 ) > $exp_date2 ) {
          $exp_date2 = $exp_date2 + 100;
        }
        $exp_date3 = substr( $exp_date2, 4, 2 ) . '/' . substr( $exp_date2, 2, 2 );

        $sth_customer2 = $dbh->prepare(
          qq{
              update customer
              set lastattempted=?
              where username=?
        }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_customer2->execute( "$today", "$username" ) or die "Can't execute: $DBI::errstr";
        $sth_customer2->finish;

        print "t";
        $| = 1;

        # Contact the credit server
        %result = &miscutils::sendmserver(
          $merchant,   "auth", 'order-id',   $orderID, 'amount',   $price, 'card-number',  $cardnumber, 'card-name', $name, 'card-address', $addr,
          'card-city', $city,  'card-state', $state,   'card-zip', $zip,   'card-country', $country,    'card-exp',  $exp_date3
        );
        print "t";
        $| = 1;

        $bill_descr = sprintf( "%02d/%02d/%04d Payment", $gm_month, $gm_day, $gm_year );

        # changed 'Monthly Billing' to 'Payment' as per David's request - 02/28/05

        $sth_billing = $dbh->prepare(
          qq{
 	        insert into billingstatus
                (username,trans_date,amount,orderid,descr,result)
                values (?,?,?,?,?,?)
        }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_billing->execute( "$username", "$today", "$amountdue", "$orderID", "$bill_descr", "$result{'MStatus'}" ) or die "Can't execute: $DBI::errstr";
        $sth_billing->finish;

        if ( $result{'MStatus'} eq "success" ) {
          if ( $processor_type eq "postauth" ) {
            %result2 = &miscutils::sendmserver( $merchant, 'postauth', 'order-id', $orderID, 'amount', $price );
          }

          $sth_customer = $dbh->prepare(
            qq{
                update customer
                set lastbilled=?,enddate=?
                where username=?
          }
            )
            or die "Can't prepare: $DBI::errstr";
          $sth_customer->execute( "$today", "$expire", "$username" ) or die "Can't execute: $DBI::errstr";
          $sth_customer->finish;

          if ( $processor_type ne "postauth" ) {
            &process_result();
          }
        }
      }

      $total = $total + $amountdue;

      if ( $form_username ne "" ) {
        $username = $form_username;
        last;
      }
    }
  }
  $sth->finish;

  $emailObj->setContent($emailmessage);
  $emailObj->send();

  if ( ( $batch_count > 0 ) && ( $processor_type ne "postauth" ) ) {
    &process_batch();
  }

  $total = sprintf( "\$%0.2f", $total );

  &gen_html();

  $dbh->disconnect;
}

sub GenerateOrderID {
  ( $sec, $min, $hour, $mday, $mon, $yyear, $wday, $yday, $isdst ) = gmtime(time);
  $ID = sprintf( "%04d%02d%02d%02d%02d%05d", $yyear + 1900, $mon + 1, $mday, $hour, $min, $sec );
  return $ID;
}

sub process_result {
  &add_to_batch();
  if ( $batch_count == 50 ) {
    &process_batch();
    &initialize_batch();
  }
}

sub initialize_batch {
  @pairs          = ();
  $batch_count    = 0;
  $batch_subtotal = 0;
}

sub add_to_batch {
  $batch_count    = $batch_count + 1;
  @pairs          = ( @pairs, "order\-id\-$batch_count", "$orderID" );
  @pairs          = ( @pairs, "txn\-type\-$batch_count", "marked" );
  @pairs          = ( @pairs, "amount\-$batch_count", "$price" );
  $batch_subtotal = $batch_subtotal + $amount;
}

sub process_batch {
  @pairs = ( "num\-txns", "$batch_count", @pairs );
  %batch_result  = &miscutils::sendmserver( $merchant, 'batch-commit', @pairs );
  $batch_results = $batch_results . "Result of batch submittal: $batch_result{'MStatus'} $batch_result{'batch-status'}\n";
  $batch_results = $batch_results . "Total: $batch_result{'total-amount'}\n";
  $batch_results = $batch_results . "Message: $batch_result{'MErrMsg'}\n";
  for ( $i = 1 ; $i <= $batch_count ; $i++ ) {
    $batch_results = $batch_results . $batch_result{"order\-id\-$i"} . " " . $batch_result{"response\-code\-$i"} . "\n";
  }
}

sub gen_html {

  &html_head( "Billing Area", "Payment: $gm_month/$gm_day/$gm_year" );

  print "<div align=center>\n";

  print "<table border=0 cellspacing=0 cellpadding=4>\n";
  print "  <tr bgcolor=\"#80c0c0\">\n";
  print "    <th valign=bottom align=left>Name</th>\n";
  print "    <th valign=bottom>Start Date</th>\n";
  print "    <th valign=bottom>End Date</th>\n";
  print "    <th valign=bottom>Last Billed</th>\n";
  print "    <th valign=bottom>Monthly</th>\n";
  print "    <th valign=bottom>Billing<br>Cycle</th>\n";
  print "    <th valign=bottom>Amount<br>Due</th>\n";
  print "  </tr>\n";

  $billmonths = ( $gm_year * 12 ) + ( $gm_month - 1 );
  $billdays = $gm_day;

  $sth = $dbh->prepare(
    qq{
      select username,name,addr1,addr2,city,state,zip,country,phone,fax,email,startdate,enddate,billcycle,monthly,lastbilled,enccardnumber,length,lastattempted
      from customer
      order by name
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  $rv = $sth->bind_columns( undef,
    \( $username, $name, $addr1, $addr2, $city, $state, $zip, $country, $phone, $fax, $email, $start, $end, $billcycle, $monthly, $lastbilled, $enccardnumber, $length, $lastattempted ) );

  $total  = 0;
  $maxnum = 0;
  while ( $sth->fetch ) {
    my $cd                 = new PlugNPay::CardData();
    my $ecrypted_card_data = '';
    eval { $ecrypted_card_data = $cd->getRecurringCardData( { customer => "$username", username => "$merchant" } ); };
    if ( !$@ ) {
      $enccardnumber = $ecrypted_card_data;
    }

    if ( $billcycle > 0 ) {
      if ( $merchant_type eq "email_on_failure" ) {
        &calculate_amountdue_email();
      } else {
        &calculate_amountdue();
      }

      if ( ( $amountdue > 0 ) || ( $showall eq "yes" ) ) {
        $passphrase = "Advanced payment systems for the future of ecommerce";
        $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

        $start = sprintf( "%02d/%02d/%04d", substr( $start, 4, 2 ), substr( $start, 6, 2 ), substr( $start, 0, 4 ) );
        if ( $end ne "" ) {
          $end = sprintf( "%02d/%02d/%04d", substr( $end, 4, 2 ), substr( $end, 6, 2 ), substr( $end, 0, 4 ) );
        }
        if ( $lastbilled ne "" ) {
          $lastbilled = sprintf( "%02d/%02d/%04d", substr( $lastbilled, 4, 2 ), substr( $lastbilled, 6, 2 ), substr( $lastbilled, 0, 4 ) );
        }

        $cardlength = length $cardnumber;
        if ( ( $cardlength > 20 ) || ( $cardlength < 8 ) ) {
          $color = "ff8080";
        } elsif ( $color eq "d0d0d0" ) {
          $color = "ffffff";
        } else {
          $color = "d0d0d0";
        }

        print "  <tr bgcolor=\"#$color\">\n";
        print "    <th align=left bgcolor=\"#c080c0\">$name</th>\n";
        print "    <td><font size=-1>$start</font></td>\n";
        print "    <td><font size=-1>$end&nbsp;</font></td>\n";
        print "    <td><font size=-1>$lastbilled&nbsp;</font></td>\n";
        if ( $monthly =~ /usd/ ) {
          ( $dummy, $monthly ) = split( / /, $monthly );
        }
        $monthly = sprintf( "\$%0.2f", $monthly );
        print "    <td align=right><font size=-1>$monthly&nbsp;</font></td>\n";
        print "    <td align=right><font size=-1>$billcycle&nbsp;</font></td>\n";
        $total = $total + $amountdue;
        $amountdue = sprintf( "\$%0.2f", $amountdue );
        print "    <td align=right><font size=-1>$amountdue</font></td>\n";
        print "  </tr>\n";

        if ( $form_username ne "" ) {
          $username = $form_username;
          last;
        }

        $maxnum++;
        if ( $maxnum > 400 ) {
          last;
        }
      }
    }
  }
  $sth->finish;

  $total = sprintf( "\$%0.2f", $total );
  print "  <tr bgcolor=\"#80c0c0\">";
  print "    <th align=left>Total:</th>\n";
  print "    <td colspan=5>&nbsp;</td>\n";
  print "    <th align=right>$total</th>\n";
  print "  </tr>\n";
  print "</table>\n";

  if ( $billingflag ne "no" ) {
    print "<form method=post action=\"sendbill.cgi\">\n";
    $passphrase = &CGI::escapeHTML( $query->param('passphrase') );
    $passphrase =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

    #if ($function ne "sendbill") {
    #  print "<input type=\"hidden\" name=\"FTPun\" value=\"$FTPun\">\n";
    #  print "<input type=\"hidden\" name=\"FTPpw\" value=\"$FTPpw\">\n";
    #  print "<input type=\"hidden\" name=\"passphrase\" value=\"$passphrase\">\n";
    #  print "<input type=\"hidden\" name=\"function\" value=sendbill>\n";
    #}
    print "<input type=\"hidden\" name=\"username\" value=\"$form_username\">\n";
    print "<input type=\"submit\" name=\"submit\" value=\"Send Bills\">\n";
    print "</form>\n";
  }

  print "<p><a href=\"index.html\"><img src=\"/css/buttons/recurring/main_menu.gif\" border=\"0\" align=\"absmiddle\" alt=\"Main Menu\"></a>\n";
  print "</div>\n";

  &html_tail();
}

sub calculate_amountdue {
  my $emailmessage = '';

  # goof proofing
  if ( $end < 19970101 ) {
    $end = "19970101";
  }
  $chkmonth = substr( $end, 4, 2 );
  $chkday   = substr( $end, 6, 2 );
  if ( ( $chkmonth < 1 ) || ( $chkmonth > 12 ) || ( $chkday < 1 ) || ( $chkday > 31 ) ) {
    $end = "19970101";
  }

  $period_end = timegm( 0, 0, 0, substr( $end, 6, 2 ), substr( $end, 4, 2 ) - 1, substr( $end, 0, 4 ) - 1900 );
  ( $dummy1, $dummy2, $dummy3, $day1, $month1, $year1, $dummy4 ) = gmtime( $period_end - ( $lookahead * 3600 * 24 ) );
  $enddate = sprintf( "%04d%02d%02d", $year1 + 1900, $month1 + 1, $day1 );
  $today   = sprintf( "%04d%02d%02d", $gm_year,      $gm_month,   $gm_day );

  $enddatedays = timegm( 0, 0, 0, substr( $enddate, 6, 2 ), substr( $enddate, 4, 2 ) - 1, substr( $enddate, 0, 4 ) - 1900 ) / ( 3600 * 24 );
  $todaydays   = timegm( 0, 0, 0, substr( $today,   6, 2 ), substr( $today,   4, 2 ) - 1, substr( $today,   0, 4 ) - 1900 ) / ( 3600 * 24 );

  $delta = $todaydays - $enddatedays;

  if ( $monthly =~ /usd/ ) {
    ( $dummy, $monthly ) = split( / /, $monthly );
  }

  if ( ( ( $today - $enddate ) >= 0 ) && ( $delta <= $fixlookahead ) ) {
    $amountdue = $monthly;
    $expire = substr( $end, 4, 2 ) + $billcycle;
    if ( $expire > 12 ) {
      $expire = sprintf( "%04d%02d%02d", substr( $end, 0, 4 ) + 1, $expire - 12, substr( $end, 6, 2 ) );
    } else {
      $expire = sprintf( "%04d%02d%02d", substr( $end, 0, 4 ), $expire, substr( $end, 6, 2 ) );
    }
  } else {
    $amountdue = 0;
    if ( ( $merchant_type =~ /email_/ )
      && ( ( $today - $enddate ) > 0 )
      && ( $delta > $fixlookahead )
      && ( $lastattempted !~ /x/ )
      && ( $function eq "sendbill" ) ) {
      $lastattempted = $lastattempted . "x";

      $sth_customer2 = $dbh->prepare(
        qq{
              update customer
              set lastattempted=?
              where username=?
              }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_customer2->execute( "$lastattempted", "$username" ) or die "Can't execute: $DBI::errstr";    # dieing here seems like a bad idea.  just sayin'.
      $sth_customer2->finish;

      if ( ( $merchant_type eq "email_on_failure" ) || ( $merchant_type eq "email_merchant" ) || ( $merchant_type eq "email_both" ) ) {
        $emailmessage = $emailmessage . "$username       $name   $today  $monthly\n";
      }

      if ( ( $merchant_type eq "email_customer" ) || ( $merchant_type eq "email_both" ) ) {
        my $emailmessage2 = "";

        my $emailObj = new PlugNPay::Email('legacy');
        $emailObj->setTo($email);
        $emailmessage2 = $emailmessage2 . "To: $email\n";

        if ( $fromemail ne "" ) {
          $emailObj->setFrom($fromemail);
        } else {
          $emailObj->setFrom($merchant_email);
        }

        $emailObj->setSubject("$mcompany - Payment Failure Notification");

        if ( $recmessage ne "" ) {
          $emailmessage2 = $emailmessage2 . "$recmessage";
        } else {
          $emailmessage2 = $emailmessage2 . "An attempt to renew your subscription to $mcompany has failed\n";
          $emailmessage2 = $emailmessage2 . "because the charge was rejected by your credit card company.  To\n";
          $emailmessage2 = $emailmessage2 . "continue your subscription to our site please contact us and\n";
          $emailmessage2 = $emailmessage2 . "provide us with a different credit card number.\n";
        }

        $emailObj->setContent($emailmessage2);
        $emailObj->send();
      }
    }
  }
  return $emailmessage;
}

sub calculate_amountdue_email {
  my $emailmessage = '';

  $period_end = timegm( 0, 0, 0, substr( $end, 6, 2 ), substr( $end, 4, 2 ) - 1, substr( $end, 0, 4 ) - 1900 );
  ( $dummy1, $dummy2, $dummy3, $day1, $month1, $year1, $dummy4 ) = gmtime( $period_end - ( $lookahead * 3600 * 24 ) );
  $enddate = sprintf( "%04d%02d%02d", $year1 + 1900, $month1 + 1, $day1 );

  $enddatedays = timegm( 0, 0, 0, substr( $enddate, 6, 2 ), substr( $enddate, 4, 2 ) - 1, substr( $enddate, 0, 4 ) - 1900 ) / ( 3600 * 24 );
  $todaydays   = timegm( 0, 0, 0, substr( $today,   6, 2 ), substr( $today,   4, 2 ) - 1, substr( $today,   0, 4 ) - 1900 ) / ( 3600 * 24 );

  $delta = $todaydays - $enddatedays;

  if ( $monthly =~ /usd/ ) {
    ( $dummy, $monthly ) = split( / /, $monthly );
  }

  if ( ( ( $today - $enddate ) > 0 ) && ( $delta <= $fixlookahead ) ) {
    $amountdue = $monthly;
    $expire = substr( $end, 4, 2 ) + $billcycle;
    if ( $expire > 12 ) {
      $expire = sprintf( "%04d%02d%02d", substr( $end, 0, 4 ) + 1, $expire - 12, substr( $end, 6, 2 ) );
    } else {
      $expire = sprintf( "%04d%02d%02d", substr( $end, 0, 4 ), $expire, substr( $end, 6, 2 ) );
    }
  } else {
    $amountdue = 0;
    if ( ( ( $today - $enddate ) > 0 ) && ( $delta > $fixlookahead ) ) {
      if ( $lastattempted !~ /x/ ) {
        $lastattempted = $lastattempted . "x";

        $sth_customer2 = $dbh->prepare(
          qq{
          update customer
          set lastattempted=?
          where username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_customer2->execute( "$lastattempted", "$username" ) or die "Can't execute: $DBI::errstr";
        $sth_customer2->finish;

        $emailmessage = $emailmessage . "$username       $name   $today  $monthly\n";
      }
    }
  }
  return $emailmessage;
}

sub graph {
  ($merchant) = @_;

  my @now          = gmtime(time);
  my $current_year = $now[5] + 1900;

  %month_array2 = ( "Jan", "01", "Feb", "02", "Mar", "03", "Apr", "04", "May", "05", "Jun", "06", "Jul", "07", "Aug", "08", "Sep", "09", "Oct", "10", "Nov", "11", "Dec", "12" );

  $query = new CGI;

  $graphtype = &CGI::escapeHTML( $query->param('graphtype') );
  $graphtype =~ s/[^a-zA-Z0-9\_\-]//g;

  $startmonth = &CGI::escapeHTML( $query->param('startmonth') );
  $startmonth =~ s/[^a-zA-Z0-9]//g;

  $startyear = &CGI::escapeHTML( $query->param('startyear') );
  $startyear =~ s/[^0-9]//g;

  $endmonth = &CGI::escapeHTML( $query->param('endmonth') );
  $endmonth =~ s/[^a-zA-Z0-9]//g;

  $endyear = &CGI::escapeHTML( $query->param('endyear') );
  $endyear =~ s/[^0-9]//g;

  $function = &CGI::escapeHTML( $query->param('function') );
  $function =~ s/[^a-zA-Z0-9\-\-]//g;

  $format = &CGI::escapeHTML( $query->param('format') );
  $format =~ s/[^a-zA-Z0-9\_\-]//g;

  # scrub start month & year selection
  if ( $startmonth !~ /^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)$/ ) { $startmonth = "Jan"; }
  $startyear = sprintf( "%4d", $startyear );
  if ( $startyear < 1999 )          { $startyear = 1999; }
  if ( $startyear > $current_year ) { $startyear = $current_year; }

  # scrub end month & year selection
  if ( $endmonth !~ /^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)$/ ) { $endmonth = "Jan"; }
  $endyear = sprintf( "%4d", $endyear );
  if ( $endyear < 1999 )          { $endyear = 1999; }
  if ( $endyear > $current_year ) { $endyear = $current_year; }

  if ( $format eq "text" ) {
    print "Content-Type: text/plain\n\n";
  } else {
    print "Content-Type: text/html\n\n";
  }

  if ( $graphtype eq "customers" ) {
    &triplegraph();
    exit;
  }

  $start = $startyear . $month_array2{$startmonth};
  $end   = $endyear . $month_array2{$endmonth};

  $dbh = &miscutils::dbhconnect("$merchant");

  $sth = $dbh->prepare(
    qq{
	select name,company
	from customer
	where username=?
        }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  ( $name, $company ) = $sth->fetchrow;
  $sth->finish;

  $total = 0;

  if ( $format ne "text" ) {
    &html_head( "Graphs", "Graph Data Type: $graphtype" );
  }

  $start1   = $start . "01";
  $end1     = $end . "31";
  $max      = 200;
  $maxmonth = 200;

  $period_start = timegm( 0, 0, 0, 01, substr( $start, 4, 2 ) - 1, substr( $start, 0, 4 ) - 1900 );
  $end_mon = substr( $end, 4, 2 ) + 1;
  if ( $end_mon > 12 ) {
    $end_mon = $end_mon - 12;
    $end_yr = substr( $end, 0, 4 ) + 1;
  } else {
    $end_yr = substr( $end, 0, 4 );
  }
  $period_end = timegm( 0, 0, 0, 01, $end_mon - 1, $end_yr - 1900 ) - ( 3600 * 24 );
  $period_end2 = time();
  if ( $period_end2 < $period_end ) {
    $period_end = $period_end2;
  }

  $sth_billing = $dbh->prepare(
    qq{
        select username,trans_date,amount,descr
        from billingstatus
	where trans_date>='$start1' and trans_date<='$end1'
        and result='success'
        order by orderid
        }
    )
    or die "Can't do: $DBI::errstr";
  $sth_billing->execute or die "Can't execute: $DBI::errstr";
  $rv = $sth_billing->bind_columns( undef, \( $bill_user, $bill_date, $bill_total, $bill_descr ) );
  while ( $sth_billing->fetch ) {

    $total{$bill_date} = $total{$bill_date} + $bill_total;
    $date2 = substr( $bill_date, 0, 6 );
    $total_month{$date2} = $total_month{$date2} + $bill_total;
    $grandtotal = $grandtotal + $bill_total;

    if ( $total{$bill_date} > $max ) {
      $max = $total{$bill_date};
    }

    if ( $total_month{$date2} > $maxmonth ) {
      $maxmonth = $total_month{$date2};
    }

  }

  $sth_billing->finish;
  $dbh->disconnect;

  if ( $format eq "text" ) {
    print "Date\t";
    print "Total\n";
  } else {
    print "<table border=0>\n";
  }

  if ( $function eq "daily" ) {
    for ( $i = $period_start ; $i <= $period_end ; $i = $i + ( 3600 * 24 ) ) {

      ( $dummy1, $dummy2, $dummy3, $day1, $month1, $year1, $dummy4 ) = gmtime($i);
      $date = sprintf( "%04d%02d%02d", ( $year1 + 1900 ), ( $month1 + 1 ), $day1 );
      $datestr = sprintf( "%02d/%02d/%04d", ( $month1 + 1 ), $day1, ( $year1 + 1900 ) );
      $width = sprintf( "%d", $total{$date} * 500 / $max );

      if ( $format eq "text" ) {
        print "$datestr\t";
        printf( "%.2f\n", $total{$date} );
      } else {
        print "  <tr>\n";
        print "    <th align=left><font size=-1>$datestr</font></th>\n";
        printf( "    <td align=right><font size=-1>%.2f</font></td>\n", $total{$date} );
        print "    <td align=left><img src=\"/images/blue.gif\" height=5 width=$width></td>\n";
        print "  </tr>\n";
      }
    }

    if ( $format ne "text" ) {
      print "  <tr>\n";
      print "    <th align=left><font size=-1>TOTAL:</font></th>\n";
      printf( "    <td align=right><font size=-1>%.2f</font></td>\n", $grandtotal );
      print "    <td></td>\n";
      print "  </tr>\n";
    }
  } else {
    foreach $key ( sort keys %total_month ) {

      $datestr = sprintf( "%02d/%04d", substr( $key, 4, 2 ), substr( $key, 0, 4 ) );
      $width = sprintf( "%d", $total_month{$key} * 500 / $maxmonth );

      if ( $format eq "text" ) {
        print "$datestr\t";
        printf( "%.2f\n", $total_month{$key} );
      } else {
        print "  <tr>\n";
        print "    <th align=left><font size=-1>$datestr</font></th>\n";
        printf( "    <td align=right><font size=-1>%.2f</font></td>\n", $total_month{$key} );
        print "    <td align=left><img src=\"/images/blue.gif\" height=5 width=$width></td>\n";
        print "  </tr>\n";
      }
    }

    if ( $format ne "text" ) {
      print "  <tr>\n";
      print "    <th align=left><font size=-1>TOTAL:</font></th>\n";
      printf( "    <td align=right><font size=-1>%.2f</font></td>\n", $grandtotal );
      print "    <td></td>\n";
      print "  <tr>\n";
    }
  }

  if ( $format ne "text" ) {
    print "</table>\n";

    print "<p><img src=\"/css/buttons/recurring/close_window.gif\" border=\"0\" align=\"absmiddle\" alt=\"Close Window\" onclick=\"window.close()\;\">\n";
    print "</div>\n";

    &html_tail();
  }
}

sub triplegraph {

  #($merchant) = @_;

  #print "Content-Type: text/html\n\n";

  my @now          = gmtime(time);
  my $current_year = $now[5] + 1900;

  %month_array2 = ( "Jan", "01", "Feb", "02", "Mar", "03", "Apr", "04", "May", "05", "Jun", "06", "Jul", "07", "Aug", "08", "Sep", "09", "Oct", "10", "Nov", "11", "Dec", "12" );

  #$query = new CGI;

  $graphtype = &CGI::escapeHTML( $query->param('graphtype') );
  $graphtype =~ s/[^a-zA-Z0-9\_\-]//g;

  $startmonth = &CGI::escapeHTML( $query->param('startmonth') );
  $startmonth =~ s/[^a-zA-Z0-9]//g;

  $startyear = &CGI::escapeHTML( $query->param('startyear') );
  $startyear =~ s/[^0-9]//g;

  $endmonth = &CGI::escapeHTML( $query->param('endmonth') );
  $endmonth =~ s/[^a-zA-Z0-9]//g;

  $endyear = &CGI::escapeHTML( $query->param('endyear') );
  $endyear =~ s/[^0-9]//g;

  $function = &CGI::escapeHTML( $query->param('function') );
  $function =~ s/[^a-zA-Z0-9\_\-]//g;

  $format = &CGI::escapeHTML( $query->param('format') );
  $format =~ s/[^a-zA-Z0-9\_\-]//g;

  # scrub start month & year selection
  if ( $startmonth !~ /^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)$/ ) { $startmonth = "Jan"; }
  $startyear = sprintf( "%4d", $startyear );
  if ( $startyear < 1999 )          { $startyear = 1999; }
  if ( $startyear > $current_year ) { $startyear = $current_year; }

  # scrub end month & year selection
  if ( $endmonth !~ /^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)$/ ) { $endmonth = "Jan"; }
  $endyear = sprintf( "%4d", $endyear );
  if ( $endyear < 1999 )          { $endyear = 1999; }
  if ( $endyear > $current_year ) { $endyear = $current_year; }

  local ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  $today = sprintf( "%04d%02d%02d", $year + 1900, $mon + 1, $mday );

  $start = $startyear . $month_array2{$startmonth};
  $end   = $endyear . $month_array2{$endmonth};

  $dbh = &miscutils::dbhconnect("$merchant");

  if ( $merchant ne "sirens" ) {
    $sth = $dbh->prepare(
      qq{
	select name,company
	from customer
	where username=?
        }
      )
      or die "Can't do: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ( $name, $company ) = $sth->fetchrow;
    $sth->finish;
  } else {
    $sth = $dbh->prepare(
      qq{
	select name
	from customer
	where username=?
        }
      )
      or die "Can't do: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($name) = $sth->fetchrow;
    $sth->finish;
  }

  $total = 0;

  if ( $format ne "text" ) {
    &html_head( "Graphs", "Graph Data Type: $graphtype" );
  }

  $start1   = $start . "01";
  $end1     = $end . "31";
  $max      = 200;
  $maxmonth = 200;

  $period_start = timegm( 0, 0, 0, 01, substr( $start, 4, 2 ) - 1, substr( $start, 0, 4 ) - 1900 );
  $end_mon = substr( $end, 4, 2 ) + 1;
  if ( $end_mon > 12 ) {
    $end_mon = $end_mon - 12;
    $end_yr = substr( $end, 0, 4 ) + 1;
  } else {
    $end_yr = substr( $end, 0, 4 );
  }
  $period_end = timegm( 0, 0, 0, 01, $end_mon - 1, $end_yr - 1900 ) - ( 3600 * 24 );
  $period_end2 = time();
  if ( $period_end2 < $period_end ) {
    $period_end = $period_end2;
  }

  $sth_billing = $dbh->prepare(
    qq{
        select trans_date
        from billingstatus
	where trans_date>='$start1' and trans_date<='$end1'
        and result='success'
        order by trans_date
        }
    )
    or die "Can't do: $DBI::errstr";
  $sth_billing->execute or die "Can't execute: $DBI::errstr";
  $rv = $sth_billing->bind_columns( undef, \($bill_date) );

  while ( $sth_billing->fetch ) {
    $total{$bill_date} = $total{$bill_date} + 1;
    $date2 = substr( $bill_date, 0, 6 );
    $total_month{$date2} = $total_month{$date2} + 1;
    $grandtotal = $grandtotal + 1;

    if ( $total{$bill_date} > $max ) {
      $max = $total{$bill_date};
    }

    if ( $total_month{$date2} > $maxmonth ) {
      $maxmonth = $total_month{$date2};
    }
  }

  $sth_billing->finish;

  $sth_billing = $dbh->prepare(
    qq{
        select startdate,enddate,lastbilled,billcycle,status
        from customer
        }
    )
    or die "Can't do: $DBI::errstr";
  $sth_billing->execute or die "Can't execute: $DBI::errstr";
  $sth_billing->bind_columns( undef, \( $gstart, $gend, $glastbilled, $gbillcycle, $status ) );

  while ( $sth_billing->fetch ) {
    if ( ( $status eq "pending" ) || ( $status eq "cancelled" ) ) {
      next;
    }

    $gdate2 = substr( $gstart, 0, 6 );
    if ( ( $gstart >= $start1 ) && ( $gstart <= $end1 ) ) {
      $gtotal{$gstart}       = $gtotal{$gstart} + 1;
      $gtotal_month{$gdate2} = $gtotal_month{$gdate2} + 1;
      if ( ( $gstart >= $start1 ) && ( $gstart <= $end1 ) ) {
        $ggrandtotal = $ggrandtotal + 1;
      }

      if ( $gtotal{$gstart} > $max ) {
        $max = $gtotal{$gstart};
      }

      if ( $gtotal_month{$gdate2} > $gmaxmonth ) {
        $gmaxmonth = $gtotal_month{$gdate2};
      }
    }

    if ( ( $gend < $today ) && ( $gend >= $start1 ) && ( $gend <= $end1 ) ) {
      $etotal{$gend} = $etotal{$gend} + 1;
      $edate2 = substr( $gend, 0, 6 );
      $etotal_month{$edate2} = $etotal_month{$edate2} + 1;
      if ( ( $gend >= $start1 ) && ( $gend <= $end1 ) && ( $gend <= $today ) ) {
        $egrandtotal = $egrandtotal + 1;
      }

      if ( $etotal{$gend} > $max ) {
        $max = $etotal{$gend};
      }

      if ( $etotal_month{$edate2} > $emaxmonth ) {
        $emaxmonth = $etotal_month{$edate2};
      }
    }

  }

  $sth_billing->finish;
  $dbh->disconnect;

  if ( $format ne "text" ) {
    print "<table border=0>\n";
  } else {
    print "Date\t";
    print "Rebills\t";
    print "New\t";
    print "Ended\n";
  }

  if ( $function eq "daily" ) {
    for ( $i = $period_start ; $i <= $period_end ; $i = $i + ( 3600 * 24 ) ) {

      ( $dummy1, $dummy2, $dummy3, $day1, $month1, $year1, $dummy4 ) = gmtime($i);
      $date = sprintf( "%04d%02d%02d", ( $year1 + 1900 ), ( $month1 + 1 ), $day1 );
      $datestr = sprintf( "%02d/%02d/%04d", ( $month1 + 1 ), $day1, ( $year1 + 1900 ) );
      $width   = sprintf( "%d",                              $total{$date} * 500 / $max );
      $gwidth  = sprintf( "%d",                              $gtotal{$date} * 500 / $max );
      $ewidth  = sprintf( "%d",                              $etotal{$date} * 500 / $max );

      if ( $format eq "text" ) {
        print "$datestr\t";
        printf( "%.0f\t", $total{$date} );
        printf( "%.0f\t", $gtotal{$date} );
        printf( "%.0f\n", $etotal{$date} );
      } else {
        print "  <tr>\n";
        print "    <th align=left><font size=-1>$datestr</font></th>\n";
        printf( "    <td align=right><font size=-2>%.0f</font><br>", $total{$date} );
        printf( "<font size=-2>%.0f</font><br>",                     $gtotal{$date} );
        printf( "<font size=-2>%.0f</font></td>\n",                  $etotal{$date} );
        print "    <td align=left><img src=\"/images/red.gif\" height=7 width=$width><br>";
        print "<img src=\"/images/green.gif\" height=7 width=$gwidth><br>";
        print "<img src=\"/images/blue.gif\" height=7 width=$ewidth></td>\n";
        print "  </tr>\n";
      }
    }

    if ( $format ne "text" ) {
      print "  <tr>\n";
      print "    <th align=left><font size=-1>Total Rebills:</font></th>\n";
      printf( "    <td align=right><font size=-1>%.0f</font></td>\n", $grandtotal );
      print "    <td><img src=\"/images/red.gif\" height=7 width=20></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <th align=left><font size=-1>Total New:</font></th>\n";
      printf( "    <td align=right><font size=-1>%.0f</font></td>\n", $ggrandtotal );
      print "    <td><img src=\"/images/green.gif\" height=7 width=20></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <th align=left><font size=-1>Total Ended:</font></th>\n";
      printf( "    <td align=right><font size=-1>%.0f</font></td>\n", $egrandtotal );
      print "    <td><img src=\"/images/blue.gif\" height=7 width=20></td>\n";
      print "  </tr>\n";
    }
  } else {
    %temp = ( %total_month, %gtotal_month, %etotal_month );
    foreach $key ( sort keys %temp ) {

      $datestr = sprintf( "%02d/%04d", substr( $key, 4, 2 ), substr( $key, 0, 4 ) );
      $width   = sprintf( "%d",        $total_month{$key} * 500 / $maxmonth );
      $gwidth  = sprintf( "%d",        $gtotal_month{$key} * 500 / $gmaxmonth );
      $ewidth  = sprintf( "%d",        $etotal_month{$key} * 500 / $gmaxmonth );

      if ( $format eq "text" ) {
        print "$datestr\t";
        printf( "%.0f\t", $total{$date} );
        printf( "%.0f\t", $gtotal{$date} );
        printf( "%.0f\n", $etotal{$date} );
      } else {
        print "  <tr>\n";
        print "    <th align=left><font size=-1>$datestr</font></th>\n";
        printf( "    <td align=right><font size=-2>%.0f</font><br>", $total_month{$key} );
        printf( "<font size=-2>%.0f</font><br>",                     $gtotal_month{$key} );
        printf( "<font size=-2>%.0f</font></td>\n",                  $etotal_month{$key} );
        print "    <td align=left><img src=\"/images/red.gif\" height=7 width=$width><br>";
        print "<img src=\"/images/green.gif\" height=7 width=$gwidth><br>";
        print "<img src=\"/images/blue.gif\" height=7 width=$ewidth></td>\n";
        print "  </tr>\n";
      }
    }

    if ( $format ne "text" ) {
      print "  <tr>\n";
      print "    <th align=left><font size=-1>Total Rebills:</font></th>\n";
      printf( "    <td align=right><font size=-1>%.0f</font></td>\n", $grandtotal );
      print "    <td><img src=\"/images/red.gif\" height=7 width=20></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <th align=left><font size=-1>Total New:</font></th>\n";
      printf( "    <td align=right><font size=-1>%.0f</font></td>\n", $ggrandtotal );
      print "    <td><img src=\"/images/green.gif\" height=7 width=20></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <th align=left><font size=-1>Total Ended:</font></th>\n";
      printf( "    <td align=right><font size=-1>%.0f</font></td>\n", $egrandtotal );
      print "    <td><img src=\"/images/blue.gif\" height=7 width=20></td>\n";
      print "  </tr>\n";
    }
  }

  if ( $format ne "text" ) {
    print "</table>\n";

    print "<p><img src=\"/css/buttons/recurring/close_window.gif\" border=\"0\" align=\"absmiddle\" alt=\"Close Window\" onclick=\"window.close()\;\">\n";
    print "</div>\n";

    &html_tail();
  }
}

sub html_head {
  my ( $page_title, $section_title ) = @_;

  print "<html>\n";
  print "<head>\n";
  if ( $page_title ne "" ) {
    print "<title>$page_title</title>\n";
  }
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<link href=\"/css/style_recurring.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\">";
  if ( $ENV{'SERVER_NAME'} =~ /plugnpay\.com/i ) {
    print "<img src=\"/images/global_header_gfx.gif\" width=\"760\" alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=\"44\" border=\"0\">";
  } else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
  }
  print "</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\"><img src=\"/images/header_bottom_bar_gfx.gif\" width=\"760\" height=\"14\"></td>\n";
  print "  </tr>\n";
  if ( $section_title ne "" ) {
    print "  <tr>\n";
    print "    <td colspan=\"3\" valign=\"top\" align=\"left\"><h1>$section_title</h1></td>\n";
    print "  </tr>\n";
  }
  print "</table>\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\">\n";
  print "  <tr>\n";
  print "    <td valign=\"top\" align=\"left\">";

  return;
}

sub html_tail {

  my @now  = gmtime(time);
  my $year = $now[5] + 1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"footer\">\n";
  print "  <tr>\n";
  print
    "    <td align=\"left\"><p><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></p></td>\n";
  print "    <td align=\"right\"><p>\&copy; $year, ";
  if ( $ENV{'SERVER_NAME'} =~ /plugnpay\.com/i ) {
    print "Plug and Pay Technologies, Inc.";
  } else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</p></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";

  return;
}

