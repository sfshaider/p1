package recutils;

use LWP::UserAgent;
use Net::FTP;
use DBI;
use miscutils;
use rsautils;
use mckutils_strict;
use smpsutils;
use PlugNPay::Transaction::TransactionProcessor;
use CGI;
use PlugNPay::Sys::Time;

sub new {
  my $type = shift;
  ($merchant) = @_;

  $query = new CGI;

  $name = &CGI::escapeHTML( $query->param('name') );
  $name =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  $username = &CGI::escapeHTML( $query->param('username') );
  $username =~ s/[^0-9a-zA-Z\_\-\@\.]//g;    # remove all non-allowed characters

  $password = &CGI::escapeHTML( $query->param('password') );
  $password =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  $from_email = &CGI::escapeHTML( $query->param('from-email') );
  $from_email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $publisher_email = &CGI::escapeHTML( $query->param('publisher-email') );
  $publisher_email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $email_message = &CGI::escapeHTML( $query->param('email-message') );

  $subject = &CGI::escapeHTML( $query->param('subject') );
  $subject =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  $site = &CGI::escapeHTML( $query->param('site') );
  $site =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  $mode = &CGI::escapeHTML( $query->param('mode') );
  $mode =~ s/[^a-zA-Z0-9\_\-\ ]//g;

  $email = &CGI::escapeHTML( $query->param('email') );
  $email =~ s/[^a-zA-Z0-9\_\-\@\.\,]//g;

  $success_link = &CGI::escapeHTML( $query->param('success-link') );

  $dbh = &miscutils::dbhconnect("$merchant");

  $goodcolor   = "#2020a0";
  $backcolor   = "#ffffff";
  $badcolor    = "#ff0000";
  $badcolortxt = "RED";
  $linkcolor   = $goodcolor;
  $textcolor   = $goodcolor;
  $alinkcolor  = "#187f0a";
  $vlinkcolor  = "#0b1f48";
  $fontface    = "Arial,Helvetica,Univers,Zurich BT";
  $itemrow     = "#d0d0d0";

  return [], $type;
}

sub recftp {
  local ( $host, $FTPun, $FTPpw, $remotedir, $sourcefile, $destfile, $port, $mode, $passive, $chmod ) = @_;

  if ( $mode eq 'sftp' ) {
    require Net::SFTP;
  }

  if ( ( $mode eq 'sftp' ) && ( $port eq "" ) ) {
    $port = "22";
  } elsif ( $port eq "" ) {
    $port = "21";
  }

  if ( $passive eq '' ) {
    $passive = '1';
  }

  if ( $chmod ne 'yes' ) {
    $chmod = '';
  }

  $| = 1;

  print "In recftp<br>\n";
  if ( $host eq "" ) {
    print "Host name is blank<br>\n";
    return "failure";
  }
  if ( $FTPun eq "" ) {
    print "FTP username is blank<br>\n";
    return "failure";
  }
  if ( $FTPpw eq "" ) {
    print "FTP password is blank<br>\n";
    return "failure";
  }
  if ( $remotedir eq "" ) {
    print "Remote directory is blank<br>\n";
    return "failure";
  }
  if ( $sourcefile eq "" ) {
    print "Source file is blank<br>\n";
    return "failure";
  }
  if ( $destfile eq "" ) {
    print "Destination file is blank<br>\n";
    return "failure";
  }

  my @sss;

  if ( $mode eq 'sftp' ) {
    my $destfile = $remotedir . "/" . $destfile;

    my %args = (
      'user'     => $FTPun,
      'password' => $FTPpw,
      'port'     => $port,
      'timeout'  => 2400
    );

    my $sftp = Net::SFTP->new( "$host", %args );

    if ( $sftp eq "" ) {
      print "Host $host is no good<br>\n";
      return "failure";
    }

    print "<pre>\n";
    print "Successful SFTP login<br>\n";

    $sftp->put( "$sourcefile", "$destfile" );

    my @xxxx = $sftp->ls("$remotedir");

    for ( my $i = 0 ; $i <= $#xxxx ; $i++ ) {
      my $your_hash = $xxxx[$i];
      my $aa        = ${$your_hash}{'longname'};
      push( @sss, $aa );
    }
  } else {
    my %ftp_options = (
      'Timeout' => 2400,
      'Debug'   => 1,
      'Port'    => $port,
      'Passive' => $passive
    );

    my $ftp = Net::FTP->new( "$host", %ftp_options );

    if ( $ftp eq "" ) {
      print "Host $host is no good<br>\n";
      return "failure";
    }

    if ( $ftp->login( "$FTPun", "$FTPpw" ) eq "" ) {
      print "Username $FTPun and password don't work<br>\n";
      return "failure";
    }

    print "<pre>\n";
    print "Successful login<br>\n";

    if ( $mode eq '' ) {
      $mode = "A";
    }

    $ftp->cwd("$remotedir");
    $ftp->pwd();
    $ftp->type("$mode");
    $ftp->put( "$sourcefile", "$destfile" );

    if ( $chmod eq "yes" ) {
      $ftp->quot( "site", "chmod 666 $destfile" );
    }

    @sss = $ftp->dir("pnp*.*");
    $ftp->quit;
  }

  foreach my $ttt (@sss) {
    print "$ttt\n";
  }

  print "</pre>\n";

}

sub recftp_ss {
  local ( $host, $FTPun, $FTPpw, $remotedir, $sourcefile, $destfile, $port, $mode, $passive, $chmod ) = @_;

  if ( $mode eq 'sftp' ) {
    require Net::SFTP;
  }

  if ( ( $mode eq 'sftp' ) && ( $port eq "" ) ) {
    $port = "22";
  } elsif ( $port eq "" ) {
    $port = "21";
  }

  if ( $passive eq '' ) {
    $passive = '1';
  }

  if ( $chmod ne 'yes' ) {
    $chmod = '';
  }

  $| = 1;

  print "In recftp<br>\n";
  if ( $host eq "" ) {
    print "Host name is blank<br>\n";
    return "failure";
  }
  if ( $FTPun eq "" ) {
    print "FTP username is blank<br>\n";
    return "failure";
  }
  if ( $FTPpw eq "" ) {
    print "FTP password is blank<br>\n";
    return "failure";
  }
  if ( $remotedir eq "" ) {
    print "Remote directory is blank<br>\n";
    return "failure";
  }
  if ( $sourcefile eq "" ) {
    print "Source file is blank<br>\n";
    return "failure";
  }
  if ( $destfile eq "" ) {
    print "Destination file is blank<br>\n";
    return "failure";
  }

  my @sss;

  if ( $mode eq 'sftp' ) {
    my $destfile = $remotedir . "/" . $destfile;

    my %args = (
      'user'     => $FTPun,
      'password' => $FTPpw,
      'port'     => $port,
      'timeout'  => 2400
    );

    my $sftp = Net::SFTP->new( "$host", %args );

    if ( $sftp eq "" ) {
      print "Host $host is no good<br>\n";
      return "failure";
    }

    print "<pre>\n";
    print "Successful SFTP login<br>\n";

    $sftp->put( "$sourcefile", "$destfile" );

    my @xxxx = $sftp->ls("$remotedir");

    for ( my $i = 0 ; $i <= $#xxxx ; $i++ ) {
      my $your_hash = $xxxx[$i];
      my $aa        = ${$your_hash}{'longname'};
      push( @sss, $aa );
    }
  } else {
    my %ftp_options = (
      'Timeout' => 2400,
      'Debug'   => 1,
      'Port'    => $port,
      'Passive' => $passive
    );

    my $ftp = Net::FTP->new( "$host", %ftp_options );

    if ( $ftp eq "" ) {
      print "Host $host is no good<br>\n";
      return "failure";
    }

    if ( $ftp->login( "$FTPun", "$FTPpw" ) eq "" ) {
      print "Username $FTPun and password don't work<br>\n";
      return "failure";
    }

    print "<pre>\n";
    print "Successful login<br>\n";

    if ( $mode eq '' ) {
      $mode = "A";
    }

    $ftp->cwd("$remotedir");
    $ftp->pwd();
    $ftp->type("$mode");
    $ftp->put( "$sourcefile", "$destfile" );

    if ( $chmod eq "yes" ) {
      $ftp->quot( "site", "chmod 666 $destfile" );
    }

    @sss = $ftp->dir("pnp*.*");
    $ftp->quit;
  }

  foreach my $ttt (@sss) {
    print "$ttt\n";
  }

  print "</pre>\n";

}

sub getftp {
  local ( $host, $FTPun, $FTPpw, $remotedir, $sourcefile, $destfile, $port, $mode, $passive ) = @_;

  if ( $port eq "" ) {
    $port = "21";
  }

  if ( $passive eq '' ) {
    $passive = '1';
  }

  $| = 1;

  print "In recftp<br>\n";
  if ( $host eq "" ) {
    print "Host name is blank<br>\n";
    return "failure";
  }
  if ( $FTPun eq "" ) {
    print "FTP username is blank<br>\n";
    return "failure";
  }
  if ( $FTPpw eq "" ) {
    print "FTP password is blank<br>\n";
    return "failure";
  }
  if ( $remotedir eq "" ) {
    print "Remote directory is blank<br>\n";
    return "failure";
  }
  if ( $sourcefile eq "" ) {
    print "Source file is blank<br>\n";
    return "failure";
  }
  if ( $destfile eq "" ) {
    print "Destination file is blank<br>\n";
    return "failure";
  }

  my %ftp_options = (
    'Timeout' => 20,
    'Debug'   => 1,
    'Port'    => $port,
    'Passive' => $passive
  );

  my $ftp = Net::FTP->new( "$host", %ftp_options );

  if ( $ftp eq "" ) {
    print "Host $host is no good<br>\n";
    return "failure";
  }

  if ( $ftp->login( "$FTPun", "$FTPpw" ) eq "" ) {
    print "Username $FTPun and password don't work<br>\n";
    return "failure";
  }

  print "<pre>\n";
  print "Successful login<br>\n";

  if ( $mode eq '' ) {
    $mode = "A";
  }

  $ftp->cwd("$remotedir");
  $ftp->type("$mode");
  $ftp->get( "$sourcefile", "$destfile" );
  my @sss = $ftp->dir();
  foreach my $ttt (@sss) {
    print "$ttt\n";
  }
  $ftp->quit;

  print "</pre>\n";

}

sub cancel_member {
  my ($message);
  ( $myusername, $mypassword, $merchant, $publisher_email, $from_email, $email_message, $subject, $termflag, $voidflag ) = @_;

  if ( $voidflag == 1 ) {
    $void = "yes";
  }

  $dbh = &miscutils::dbhconnect("$merchant");
  $sth = $dbh->prepare(
    q{
      SELECT username,password,orderid,email,enddate,billcycle
      FROM customer
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute("$myusername") or die "Can't execute: $DBI::errstr";
  ( $uname, $pword, $orderID, $email, $end, $billcycle ) = $sth->fetchrow;
  $sth->finish;

  @current_date    = gmtime(time);
  $current_date[4] = $current_date[4] + 1;                                                              # for currect month number
  $current_date[5] = $current_date[5] + 1900;                                                           # for correct 4-digit year
  $todays_date     = sprintf( "%04d%02d%02d", $current_date[5], $current_date[4], $current_date[3] );
  if ( $todays_date > $end ) {
    $expired = 1;
  }

  $end1 = sprintf( "%02d/%02d/%04d", substr( $end, 4, 2 ), substr( $end, 6, 2 ), substr( $end, 0, 4 ) );

  if ( ( $uname eq $myusername ) && ( $pword eq $mypassword ) ) {
    if ( $expired == 1 ) {
      $message    = "The account for username: $myusername, has already expired. No cancellation is required.";
      $page_title = "Cancel Subscription";
      &response_page( $message, $page_title );
    } elsif ( $billcycle > 0 ) {
      if ( $termflag == 1 ) {
        my @current_date = gmtime( time - 86400 );
        $current_date[4] = $current_date[4] + 1;       # for currect month number
        $current_date[5] = $current_date[5] + 1900;    # for correct 4-digit year
        my $todays_date = sprintf( "%04d%02d%02d", $current_date[5], $current_date[4], $current_date[3] );

        $sth = $dbh->prepare(
          q{
            UPDATE customer
            SET billcycle='0',status='cancelled', enddate=?
            WHERE username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth->execute( "$todays_date", "$myusername" ) or die "Can't execute: $DBI::errstr";
        $sth->finish;
        $end = $todays_date;
        $end1 = sprintf( "%02d/%02d/%04d", substr( $end, 4, 2 ), substr( $end, 6, 2 ), substr( $end, 0, 4 ) );
      } else {
        $sth = $dbh->prepare(
          q{
            UPDATE customer
            SET billcycle='0',status='cancelled'
            WHERE username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth->execute("$myusername") or die "Can't execute: $DBI::errstr";
        $sth->finish;
      }
      $message = "The account for username: $myusername, has been successfully cancelled and will not be rebilled.<p>
                  The Username and Password will continue to be valid until $end1.";
      &email;
      $page_title = "Cancel Subscription";
      &response_page( $message, $page_title );
    } else {
      $message = "The account for username: $myusername, has already been cancelled.<p>
                  The Username and Password will continue to be valid until $end1.";
      $page_title = "Cancel Subscription";
      &response_page( $message, $page_title );
    }
  } else {
    $message    = "Sorry, the Username and Password combination entered was not found in the database.  Please try again and be careful to use the proper CAPITALIZATION.";
    $page_title = "Cancel Subscription";
    &response_page( $message, $page_title );
  }
  if ( $void eq "yes" ) {
    &voidtrans;
  }
}

sub response_page {
  if ( $goodcolor eq "" )   { $goodcolor   = "#2020a0"; }
  if ( $backcolor eq "" )   { $backcolor   = "#ffffff"; }
  if ( $badcolor eq "" )    { $badcolor    = "#ff0000"; }
  if ( $badcolortxt eq "" ) { $badcolortxt = "RED"; }
  if ( $linkcolor eq "" )   { $linkcolor   = $goodcolor; }
  if ( $textcolor eq "" )   { $textcolor   = $goodcolor; }
  if ( $alinkcolor eq "" )  { $alinkcolor  = "#187f0a"; }
  if ( $vlinkcolor eq "" )  { $vlinkcolor  = "#0b1f48"; }
  if ( $fontface eq "" )    { $fontface    = "Arial,Helvetica,Univers,Zurich BT"; }
  if ( $itemrow eq "" )     { $itemrow     = "#d0d0d0"; }

  my ( $message, $page_title ) = @_;
  print "Content-Type: text/html\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";

  print "<script type=\"text/javascript\">\n";
  print "<\!-- Start Script\n";
  print "function closeresults() \{\n";
  print "  resultsWindow = window.close('results')\;\n";
  print "\}\n";
  print "// end script-->\n";
  print "</script>\n";

  print "<style type=\"text/css\">\n";
  print "<!--\n";
  print "th { font-family: $fontface; font-size: 10pt; color: $goodcolor }\n";
  print "td { font-family: $fontface; font-size: 9pt; color: $goodcolor }\n";
  print ".badcolor { color: $badcolor }\n";
  print ".goodcolor { color: $goodcolor }\n";
  print ".larger { font-size: 12pt }\n";
  print ".smaller { font-size: 9pt }\n";
  print ".short { font-size: 8% }\n";
  print ".itemscolor { background-color: $goodcolor; color: $backcolor }\n";
  print ".itemrows { background-color: $itemrow }\n";
  print ".info { position: static }\n";
  print "#tail { position: static }\n";
  print "-->\n";
  print "</style>\n";

  if ( $page_title eq "" ) {
    $page_title = "Attendant";
  }
  print "<title>$page_title</title>\n";

  print "</head>\n";
  print "<body bgcolor=\"$backcolor\" link=\"$goodcolor\" text=\"$goodcolor\" alink=\"$alinkcolor\" vlink=\"$vlinkcolor\">\n";

  print "<div align=center>\n";
  print "<table>\n";
  print "  <tr>\n";
  print "    <th align=center colspan=2>$message</th>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "</div>\n";

  print "<div align=center>\n";
  print "<p><form><input type=button class=\"button\" value=\"Close\" onClick=\"closeresults()\;\"></form>\n";
  print "</div>\n";

  print "</body>\n";
  print "</html>\n";
}

sub email {
  $position = index( $email, "\@" );
  if ( ( $position > 1 ) && ( length($email) > 5 ) && ( $position < ( length($email) - 5 ) ) ) {

    my $emailObj = new PlugNPay::Email('legacy');
    $emailObj->setGatewayAccount($merchant);
    $emailObj->setFormat('text');
    $emailObj->setTo($email);
    $emailObj->setCC($publisher_email);

    if ( $from_email ne "" ) {
      $emailObj->setFrom($from_email);
    } else {
      $emailObj->setFrom($publisher_email);
    }

    if ( $subject ne "" ) {
      $emailObj->setSubject($subject);
    } else {
      $emailObj->setSubject("$site - Membership Cancellation Confirmation");
    }

    my $emailmessage = "";
    $emailmessage .= "The following account has been successfully cancelled and will not be rebilled.\n\n";
    $emailmessage .= "Username: $myusername\n\n";
    $emailmessage .= "The Username and Password may still be used until $end.\n\n";
    $emailmessage .= $email_message;                                                                          # wtf is this
    $emailmessage .= "\n";

    $emailObj->setContent($emailmessage);
    $emailObj->send();
  }
}

sub voidtrans {

  # Contact the credit server to do void
  my $acct_code4 = "Cancel Member";
  %result = &miscutils::sendmserver( "$merchant", 'void', 'txn-type', 'marked', 'order-id', "$orderID", 'acct_code4', "$acct_code4" );
}

sub cancel_member_plus {
  my ($message);
  ( $myusername, $mypassword, $database, $publisher_email, $from_email, $email_message, $subject, $remoteaddr ) = @_;
  my $dbh = DBI->connect("DBI:mSQL:$database") or die "Can't connect: $DBI::errstr";

  my $sth = $dbh->prepare(
    q{
      SELECT username,password,orderid,email,end,billcycle
      FROM customer
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute("$myusername") or die "Can't execute: $DBI::errstr";
  ( $uname, $pword, $orderID, $email, $end, $billcycle ) = $sth->fetchrow;
  $sth->finish;

  $end = sprintf( "%02d/%02d/%04d", substr( $end, 4, 2 ), substr( $end, 6, 2 ), substr( $end, 0, 4 ) );

  if ( ( $uname eq $myusername ) && ( $pword eq $mypassword ) ) {
    if ( $billcycle > 0 ) {
      $sth = $dbh->prepare(
        q{
          UPDATE customer
          SET billcycle=?
          WHERE username=?
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth->execute( "0", "$myusername" ) or die "Can't execute: $DBI::errstr";
      $sth->finish;

      $message = "The account for username: $myusername, has been successfully cancelled and will not be rebilled.<p>
                  The Username and Password will continue to be valid until $end.";
      &email;

      # write to service history
      $action = "Self Cancelled";
      $reason = "User initiated Cancel from $remoteaddr, merchant confirmation sent to $from_email";
      my $now         = time();
      my $sth_history = $dbh->prepare(
        q{
          INSERT INTO history
          (trans_time,username,action,descr)
          VALUES (?,?,?,?)
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_history->execute( $now, $myusername, $action, $reason ) or die "Can't execute: $DBI::errstr";
      $sth_history->finish;

      $page_title = "Cancel Subscription";
      &response_page( $message, $page_title );
      exit;
    } else {
      $message = "The account for username: $myusername, has already been cancelled.<p>
                  The Username and Password will continue to be valid until $end.";
      $page_title = "Cancel Subscription";
      &response_page( $message, $page_title );
      exit;
    }
  } else {
    $message    = "Sorry, the Username and Password combination entered was not found in the database.  Please try again and be careful to use the proper CAPITALIZATION.";
    $page_title = "Cancel Subscription";
    &response_page( $message, $page_title );
    exit;
  }
}

sub remind_member {
  my ($message);
  my ($today) = &miscutils::gendatetime_only();
  ( $merchant, $publisher_email, $from_email, $email_message, $subject, $email, $success_link ) = @_;

  $email =~ s/[^_0-9a-zA-Z\-\@\.]//g;    # remove all non-allowed characters

  $dbh = &miscutils::dbhconnect("$merchant");
  $sth = $dbh->prepare(
    q{
      SELECT username,password,enddate,status,billcycle
      FROM customer
      WHERE LOWER(email) LIKE lower(?)
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute("\%$email\%") or die "Can't execute: $DBI::errstr";
  $sth->bind_columns( undef, \( $uname, $pword, $end, $status, $billcycle ) );
  while ( $sth->fetch ) {
    push( @uname, $uname );
    push( @pword, $pword );

    # figure out if username is active or expired
    if ( $end < $today ) {
      $expired_flag = 1;
    } else {
      $expired_flag = 0;
    }
    if ( ( $status =~ /cancelled/ ) && ( $pword =~ /^CN\d\d\d\d/ ) ) {
      $expired_flag = 1;
    }
    push( @expired,   $expired_flag );
    push( @status,    $status );
    push( @billcycle, $billcycle );

    # track number of active & expired usernames
    if ( $expired_flag == 0 ) {
      $active_count = $active_count + 1;
    } else {
      $expired_count = $expired_count + 1;
    }

    $end = sprintf( "%02d/%02d/%04d", substr( $end, 4, 2 ), substr( $end, 6, 2 ), substr( $end, 0, 4 ) );
    push( @end, $end );
  }
  $sth->finish;
  $dbh->disconnect;

  $message = "";

  if ( $uname ne "" ) {
    if ( $active_count > 0 ) {
      $message .= "A username and password have been found for the email address entered.  A copy is being emailed to you.";
      &email1;
    } else {
      $message .= "Username and password found are no longer active.<br>Your subscription has expired.";
      $message .= "<p>A copy is being emailed to you for renewal purposes.";
      &email1;
    }
    if ( $success_link ne "" ) {
      $message .= "<p><a href=\"$success_link\">Click Here to Continue</a><p>";
    }
    $page_title = "Subscription Reminder";
    &response_page( $message, $page_title );
  } else {
    $message .= "Sorry, the Email address entered was not found in the database.";
    $page_title = "Subscription Reminder";
    &response_page( $message, $page_title );
  }
}

sub email1 {
  $position = index( $email, "\@" );
  if ( ( $position > 1 ) && ( length($email) > 5 ) && ( $position < ( length($email) - 5 ) ) ) {
    my $emailObj = new PlugNPay::Email('legacy');
    $emailObj->setGatewayAccount($merchant);
    $emailObj->setFormat('text');
    $emailObj->setTo($email);

    if ( $from_email ne "" ) {
      $emailObj->setFrom($from_email);
    } else {
      $emailObj->setFrom($publisher_email);
    }

    if ( $subject ne "" ) {
      $emailObj->setSubject($subject);
    } else {
      $emailObj->setSubject("Your Membership");
    }

    my $emailmessage = "";
    $emailmessage .= "Your Username(s) and Password(s) are as follows:\n\n";

    for ( $i = 0 ; $i <= $#uname ; $i++ ) {
      $emailmessage .= "Username: $uname[$i]\n";
      if ( $expired[$i] == 1 ) {
        if ( ( $status[$i] !~ /cancelled/ ) && ( $pword[$i] !~ /^CN\d\d\d\d/ ) ) {
          $emailmessage .= "Password: $pword[$i]\n";
        }
        $emailmessage .= "\n";
        $emailmessage .= "This username has expired.\n\n";
      } else {
        $emailmessage .= "Password: $pword[$i]\n\n";
        if ( $billcycle[$i] > 0 ) {
          $emailmessage .= "This username is set to rebill next by $end[$i].\n\n";
        } else {
          $emailmessage .= "This username is set to expire on $end[$i].\n\n";
        }
      }
    }

    $emailmessage .= $email_message;    # wtf is this

    $emailObj->setContent($emailmessage);
    $emailObj->send();
  }
}

sub update {
  my ($message);
  $mode = $main::mode;

  # safeguard account against hacks - 08/15/05
  $main::username =~ s/[^_0-9a-zA-Z\-\@\.]//g;    # remove all non-allowed characters
  if ( $main::username eq "" ) {

    # reject usernames which do not contain at least 1 alphanumeric character
    print "Content-Type: text/html\n\n";
    print "Invalid Username\n";
    exit;
  }

  $result = &checkunpw();
  if ( $result ne "success" ) {
    $message    = "Sorry, the Username and Password combination entered was not found in the database.  Please try again and be careful to use the proper CAPITALIZATION.";
    $page_title = "Edit Account Information";
    &response_page( $message, $page_title );
    return "failure";
  }

  $dbh = &miscutils::dbhconnect("$main::merchant");

  $cardnumber = &CGI::escapeHTML( $main::query->param('cardnumber') );
  $cardnumber =~ s/[^0-9\*]//g;
  $cardlength = length $cardnumber;
  if ( ( $cardnumber !~ /\*\*/ ) && ( $cardlength > 8 ) ) {
    ( $enccardnumber, $encryptedDataLen ) = &rsautils::rsa_encrypt_card( $cardnumber, '/home/pay1/pwfiles/keys/key' );
    $cardnumber = &CGI::escapeHTML( $main::query->param('cardnumber') );
    $cardnumber =~ s/[^0-9]//g;
    $cardnumber = substr( $cardnumber, 0, 4 ) . '**' . substr( $cardnumber, length($cardnumber) - 2, 2 );
    $encryptedDataLen = "$encryptedDataLen";

    $enccardnumber = &smpsutils::storecardnumber( $main::merchant, $main::username, 'recutils_update', $enccardnumber, 'rec' );

    $sth = $dbh->prepare(
      q{
        UPDATE customer
        SET enccardnumber=?,length=?,cardnumber=?
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( "$enccardnumber", "$encryptedDataLen", "$cardnumber", "$main::username" ) or die "Can't execute: $DBI::errstr";
    $sth->finish;

    $chkcardnumber = 1;
    $chkexp        = 1;
  }

  @execstring   = ();
  $updatestring = "UPDATE customer SET ";
  $querystring  = "SELECT ";
  foreach $var (@editfields) {
    if ( $var ne "cardnumber" ) {

      #if (($var ne "username") && (($dontview != 1) || (($dontview == 1) && (&CGI::escapeHTML($main::query->param("upd_$var")) eq "yes")))) {
      if ( ( $var ne "username" ) && ( $dontview != 1 ) && ( $var ne "" ) ) {
        $updatestring .= "$var=?,";
        $querystring  .= "$var,";
        if ( $var eq "password" ) {
          if ( length( &CGI::escapeHTML( $main::query->param('passwd1') ) ) < 4 ) {
            $message = "The password must be at least 4 characters long, please re-enter.";
            $dbh->disconnect;
            &edit();
            return "failure";
          }
          if ( &CGI::escapeHTML( $main::query->param('passwd1') ) ne &CGI::escapeHTML( $main::query->param('passwd2') ) ) {
            $message = "The passwords do not match, please re-enter.";
            $dbh->disconnect;
            &edit();
            return "failure";
          }

          $value = &CGI::escapeHTML( $main::query->param('passwd1') );
        } elsif ( $var eq "exp" ) {
          $exp_month = &CGI::escapeHTML( $main::query->param('exp_month') );
          $exp_month =~ s/[^0-9]//g;

          $exp_year = &CGI::escapeHTML( $main::query->param('exp_year') );
          $exp_year =~ s/[^0-9]//g;

          $exp   = "$exp_month/$exp_year";
          $value = $exp;
        } else {
          $value = &CGI::escapeHTML( $main::query->param($var) );
          $value =~ s/[^_0-9a-zA-Z\-\@\.\ ]//g;    # remove all non-allowed characters
        }
        push( @execstring, "$value" );
      }
    }
  }
  chop $updatestring;
  $updatestring .= " WHERE username=?";
  push( @execstring, "$main::username" );

  chop $querystring;
  $querystring .= " FROM customer WHERE username=?";

  my ( undef, $message_time ) = &miscutils::gendatetime_only();
  open( DEBUG, '>>', "/home/pay1/database/recurring_debug.txt" );
  print DEBUG "Time: $message_time, Merchant: $main::merchant, IP: $ENV{'REMOTE_ADDR'}, Script: $ENV{'SCRIPT_FILENAME'}\n";
  print DEBUG "Update: $updatestring\n";
  print DEBUG "Query: $querystring\n";
  close DEBUG;

  $sth = $dbh->prepare(qq{$querystring}) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$main::username") or die "Can't execute: $DBI::errstr";
  (@chkfields) = $sth->fetchrow;
  $sth->finish;

  $sth = $dbh->prepare(qq{$updatestring}) or die "Can't prepare: $DBI::errstr";
  $sth->execute(@execstring) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  # write to service history
  my $action      = "Customer Update";
  my $reason      = "User updated profile info from $ENV{'REMOTE_ADDR'}, merchant confirmation sent to $from_email";
  my $now         = time();
  my $sth_history = $dbh->prepare(
    q{
      INSERT INTO history
      (trans_time,username,action,descr)
      VALUES (?,?,?,?)
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_history->execute( $now, $main::username, $action, $reason ) or die "Can't execute: $DBI::errstr";
  $sth_history->finish;

  $dbh->disconnect;

  $dontupdate = 1;
  &edit();
}

sub edit {
  my ($message);

  # safeguard account against hacks - 08/15/05
  $main::username =~ s/[^_0-9a-zA-Z\-\@\.]//g;    # remove all non-allowed characters
  if ( $main::username eq "" ) {

    # reject usernames which do not contain at least 1 alphanumeric character
    print "Content-Type: text/html\n\n";
    print "Invalid Username\n";
    exit;
  }

  if ( $nooutputflag eq "yes" ) {
    return;
  }

  if ( $dontupdate != 1 ) {
    $result = &checkunpw();

    if ( $result eq "cancel" ) {
      $message    = "Sorry, your account has been previously cancelled and may not be updated through this interface.";
      $page_title = "Edit Account Information";
      &response_page( $message, $page_title );
      return "failure";
    } elsif ( $result ne "success" ) {
      $message    = "Sorry, the Username and Password combination entered was not found in the database.  Please try again and be careful to use the proper CAPITALIZATION.";
      $page_title = "Edit Account Information";
      &response_page( $message, $page_title );
      return "failure";
    }
  }

  @execstring  = ();
  $querystring = "SELECT  ";
  $i           = 0;
  foreach my $var (@editfields) {
    $querystring .= "$var,";
    $value = &CGI::escapeHTML( $main::query->param($var) );
    $bindvalues[$i] = "";
    $i++;
  }
  chop $querystring;
  $querystring .= " FROM customer WHERE username=?";

  $dbh = &miscutils::dbhconnect("$main::merchant");
  $sth = $dbh->prepare(qq{$querystring}) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$main::username") or die "Can't execute: $DBI::errstr";
  (@bindvalues) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  if ( ( $mode eq "update" ) && ( ( &CGI::escapeHTML( $main::query->param('email') ) !~ /\@/ ) || ( &CGI::escapeHTML( $main::query->param('email') ) !~ /\./ ) ) ) {
    $message = "Invalid Email Address.";
    $message .= "<br>Please try again and click on the \'Send Info\' button when finished.";
    $message .= "<br><form><input type=button class=\"button\" value=\"Back To Previous Screen\" onClick=\"javascript:history.go(-1)\"></form>";
    $page_title = "Edit Account Information";
    &response_page( $message, $page_title );
    return "failure";
  } elsif ( ( $mode eq "update" ) && ( &CGI::escapeHTML( $main::query->param('passwd1') ) eq &CGI::escapeHTML( $main::query->param('passwd2') ) ) ) {
    $message = "Your Information has been changed.\n";
    $message .= "<br>Password changes will take up to 24 hours before the new password takes effect.\n";
    $message .= "<br>To return, please hit the \'Close Window\' button at the bottom.";
  } elsif ( ( $mode eq "update" ) && ( &CGI::escapeHTML( $main::query->param('passwd1') ) ne &CGI::escapeHTML( $main::query->param('passwd2') ) ) ) {
    $message = "Passwords do not match.<br>Please try again and click on the \'Send Info\' button when finished.";
  }

  if ( $goodcolor eq "" )   { $goodcolor   = "#2020a0"; }
  if ( $backcolor eq "" )   { $backcolor   = "#ffffff"; }
  if ( $badcolor eq "" )    { $badcolor    = "#ff0000"; }
  if ( $badcolortxt eq "" ) { $badcolortxt = "RED"; }
  if ( $linkcolor eq "" )   { $linkcolor   = $goodcolor; }
  if ( $textcolor eq "" )   { $textcolor   = $goodcolor; }
  if ( $alinkcolor eq "" )  { $alinkcolor  = "#187f0a"; }
  if ( $vlinkcolor eq "" )  { $vlinkcolor  = "#0b1f48"; }
  if ( $fontface eq "" )    { $fontface    = "Arial,Helvetica,Univers,Zurich BT"; }
  if ( $itemrow eq "" )     { $itemrow     = "#d0d0d0"; }

  print "Content-Type: text/html\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";

  print "<script type=\"text/javascript\">\n";
  print "<\!-- Start Script\n";
  print "function closeresults() \{\n";
  print "  resultsWindow = window.close('results')\;\n";
  print "\}\n";
  print "// end script-->\n";
  print "</script>\n";

  print "<style type=\"text/css\">\n";
  print "<!--\n";
  print "th { font-family: $fontface; font-size: 10pt; color: $goodcolor }\n";
  print "td { font-family: $fontface; font-size: 9pt; color: $goodcolor }\n";
  print ".badcolor { color: $badcolor }\n";
  print ".goodcolor { color: $goodcolor }\n";
  print ".larger { font-size: 12pt }\n";
  print ".smaller { font-size: 9pt }\n";
  print ".short { font-size: 8% }\n";
  print ".itemscolor { background-color: $goodcolor; color: $backcolor }\n";
  print ".itemrows { background-color: $itemrow }\n";
  print ".info { position: static }\n";
  print "#tail { position: static }\n";
  print "-->\n";
  print "</style>\n";

  if ( $page_title eq "" ) {
    $page_title = "Edit Account Information";
  }
  print "<title>$page_title</title>\n";

  print "</head>\n";
  print "<body bgcolor=\"$backcolor\" link=\"$goodcolor\" text=\"$goodcolor\" alink=\"$alinkcolor\" vlink=\"$vlinkcolor\">\n";

  print "<div align=center>\n";
  print "<br><table border=0>\n";
  if ( $message ne "" ) {
    print "  <tr>\n";
    print "    <th><font size=3>$message</font></th>\n";
    print "  </tr>\n";
  } else {
    print "  <tr>\n";
    print "    <th><font size=3><b>Please edit the information you wish changed and click on the \'Send Info\' button when finished.</b></font></th>\n";
    print "  </tr>\n";
  }
  print "</table>\n";
  print "</div>\n";

  if ( $dontupdate != 1 ) {
    print "<form method=post action=\"attendant.cgi\">\n";
  }
  print "<div align=center>\n";
  print "<table border=0>\n";
  $i = 0;
  foreach $var (@editfields) {
    $length = length( $bindvalues[$i] ) + 4;
    if ( $length < 20 ) {
      $length = 20;
    }

    if ( $dontupdate == 1 ) {
      if ( $var ne "password" ) {
        print "  <tr>\n";
        print "    <th align=right>$titlefields[$i]:</th>\n";
        print "    <td>$bindvalues[$i]</td>\n";
        print "  </tr>\n";
      }
    } elsif ( $dontview == 1 ) {
      print "  <tr>\n";
      print "    <th align=right>$titlefields[$i]:</th>\n";
      print "    <td><input type=text name=\"$var\" size=24 max=40></td>\n";
      print "    <td><input type=checkbox name=\"upd_$var\" value=\"yes\"> Update</td>\n";
      print "  </tr>\n";
    } else {
      if ( $var eq "password" ) {
        print "  <tr>\n";
        print "    <th align=right>$titlefields[$i]:</th>\n";
        print "    <td><input type=password name=\"passwd1\" size=11 max=19 value=\"$bindvalues[$i]\"></td>\n";
        print "  </tr>\n";
        print "  <tr>\n";
        print "    <th align=right>$titlefields[$i] again:</th>\n";
        print "    <td><input type=password name=\"passwd2\" size=11 max=19 value=\"$bindvalues[$i]\"></td>\n";
        print "  </tr>\n";
      } elsif ( $var eq "exp" ) {
        $exp_month = substr( $bindvalues[$i], 0, 2 );
        $exp_year  = substr( $bindvalues[$i], 3, 2 );
        print "  <tr>\n";
        print "    <th align=right>$titlefields[$i]:</th>\n";
        print "    <td><select name=\"exp_month\">";
        $selected{$exp_month} = " selected";
        for ( $j = 1 ; $j <= 12 ; $j++ ) {
          $month = sprintf( "%02d", $j );
          printf( "<option value=\"%02d\"$selected{$month}> %02d", $j, $j );
        }
        print "</select> <select name=\"exp_year\">";
        %selected = ();
        $selected{$exp_year} = " selected";

        #Fix time
        my $time        = new PlugNPay::Sys::Time();
        my $currentYear = 2000 + $time->nowInFormat('year2');
        my $startYear   = $currentYear - 2;
        my $futureYear  = $currentYear + 18;

        for ( $j = $startYear ; $j <= $futureYear ; $j++ ) {
          $year = sprintf( "%02d", substr( $j, 2, 2 ) );
          printf( "<option value=\"%02d\"$selected{$year}> %04d", $year, $j );
        }
        print "</select></td>\n";
        print "</tr>\n";
      } else {
        print "  <tr>\n";
        print "    <th align=right>$titlefields[$i]:</th>\n";
        print "    <td><input type=text name=\"$var\" size=$length max=40 value=\"$bindvalues[$i]\"></td>\n";
        print "  </tr>\n";
      }
    }
    $i++;
  }
  print "</table>\n";
  print "</div><br>\n";

  if ( $dontupdate != 1 ) {
    print "<input type=hidden name=\"mode\" value=\"update\">\n";
    print "<input type=hidden name=\"username\" value=\"$main::username\">\n";
    print "<input type=hidden name=\"password\" value=\"$main::password\">\n";
    print "<div align=center>\n";
    print "<input type=submit class=\"button\" value=\"Send Info\"> <input type=reset class=\"button\" value=\"Reset Form\">\n";
    print "</div>\n";
    print "</form><p>\n";
  }
  if ( ( $path_home eq "" ) || ( $path_home eq "http:///" ) ) {
    $path_home = "http://" . $ENV{'SERVER_NAME'} . $ENV{'SCRIPT_NAME'};

    #$path_home = "attendant.html";
  }
  if ( $desc_home eq "" ) {
    $desc_home = "Return Home";
  }
  print "<div align=center>\n";
  print "<form><input type=button class=\"button\" name=\"submit\" value=\"Close Window\" onClick=\"self.close();\"></form></div>\n";

  print "</body>\n";
  print "</html>\n";
}

sub checkunpw {
  $username = &CGI::escapeHTML( $main::query->param('username') );
  $username =~ s/[^_0-9a-zA-Z\-\@\.]//g;

  $password = &CGI::escapeHTML( $main::query->param('password') );
  $password =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  if ( $username eq "" ) {

    # reject usernames which do not contain at least 1 alphanumeric character
    print "Content-Type: text/html\n\n";
    print "Invalid Username\n";
    exit;
  }

  if ( ( $username eq "" ) || ( $password eq "" ) ) {
    return "failure";
  }

  $dbh = &miscutils::dbhconnect("$main::merchant");
  $sth = $dbh->prepare(
    q{
      SELECT username,status
      FROM customer
      WHERE username=?
      AND password=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$username", "$password" ) or die "Can't execute: $DBI::errstr";
  ( $chkusername, $chkstatus ) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  if ( $chkusername eq "" ) {
    return "failure";
  } elsif ( ( $chkstatus =~ /cancel/i ) ) {
    return "canelled";
  } else {
    return "success";
  }
}

sub renewal {
  my ($message);
  $username = &CGI::escapeHTML( $main::query->param('username') );
  $username =~ s/[^_0-9a-zA-Z\-\@\.]//g;

  $password = &CGI::escapeHTML( $main::query->param('password') );
  $password =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  $cardnumber = &CGI::escapeHTML( $main::query->param('cardnumber') );
  $cardnumber =~ s/[^0-9]//g;

  $exp_month = &CGI::escapeHTML( $main::query->param('exp_month') );
  $exp_month =~ s/[0-9]//g;

  $exp_year = &CGI::escapeHTML( $main::query->param('exp_year') );
  $exp_year =~ s/[^0-9]//g;

  $submode = &CGI::escapeHTML( $main::query->param('submode') );
  $submode =~ s/[^a-zA-Z0-9\_\-]//g;

  ($today) = &miscutils::gendatetime_only();

  $dbh = &miscutils::dbhconnect("$main::merchant");
  $sth = $dbh->prepare(
    q{
      SELECT username,enddate
      FROM customer
      WHERE username=?
      AND password=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$username", "$password" ) or die "Can't execute: $DBI::errstr";
  ( $chkusername, $enddate ) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;
  if ( $chkusername eq "" ) {
    $message    = "Sorry, the Username and Password combination entered was not found in the database.  Please try again and be careful to use the proper CAPITALIZATION.";
    $page_title = "Subscription Renewal";
    &recutils::response_page( $message, $page_title );
    exit;
  } elsif ( ( $enddate >= $today + 5 ) && ( $submode ne "confirmrenewal" ) ) {
    $enddatestr = sprintf( "%02d/%02d/%04d", substr( $enddate, 4, 2 ), substr( $enddate, 6, 2 ), substr( $enddate, 0, 4 ) );
    $message = "Your subscription is set to expire on $enddatestr.  You cannot renew your account while it is still active. ";

    #$message = "Your subscription is not set to expire until $enddatestr.  Do you still wish to renew ? ";
    #$message = "Your subscription expires or has already expired on $enddatestr. Press \'Confirm Renewal\' to complete the renewal or reactivation of your account. ";
    $page_title = "Subscription Renewal";
    &recutils::response_page( $message, $page_title );
    exit;
  } elsif ( length($cardnumber) < 12 ) {
    $message    = "Please input a Credit Card Number so that we can renew your membership.";
    $page_title = "Subscription Renewal";
    &recutils::response_page( $message, $page_title );
    exit;
  }

  $dbh_renewal = &miscutils::dbhconnect("$main::merchant");

  $cardnumber = &CGI::escapeHTML( $main::query->param('cardnumber') );
  $cardnumber =~ s/[^0-9\*]//g;
  $cardlength = length $cardnumber;
  if ( ( $cardnumber !~ /\*\*/ ) && ( $cardlength > 8 ) ) {
    ( $enccardnumber, $encryptedDataLen ) = &rsautils::rsa_encrypt_card( $cardnumber, '/home/pay1/pwfiles/keys/key' );
    $cardnumber = &CGI::escapeHTML( $main::query->param('cardnumber') );
    $cardnumber =~ s/[^0-9]//g;
    $cardnumber = substr( $cardnumber, 0, 4 ) . '**' . substr( $cardnumber, length($cardnumber) - 2, 2 );
    $encryptedDataLen = "$encryptedDataLen";

    $enccardnumber = &smpsutils::storecardnumber( $main::merchant, $username, 'recutils_renewals', $enccardnumber, 'rec' );

    $exp_month = &CGI::escapeHTML( $main::query->param('exp_month') );
    $exp_month =~ s/[^0-9]//g;
    $exp_year = &CGI::escapeHTML( $main::query->param('exp_year') );
    $exp_year =~ s/[^0-9]//g;
    $exp = "$exp_month/$exp_year";

    $time = time();
    ( $dummy1, $dummy2, $dummy3, $eday, $emonth, $eyear ) = gmtime( $time + ( 3 * 3600 * 24 ) );
    $enddate = sprintf( "%04d%02d%02d", $eyear + 1900, $emonth + 1, $eday );

    $sth = $dbh_renewal->prepare(
      q{
        UPDATE customer
        SET enccardnumber=?,length=?,cardnumber=?,exp=?,enddate=?
        WHERE username=?
        AND password=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( "$enccardnumber", "$encryptedDataLen", "$cardnumber", "$exp", "$enddate", "$username", "$password" ) or die "Can't execute: $DBI::errstr";
    $sth->finish;
    $dbh_renewal->disconnect;

  }

  $message    = "Thank you for renewing your subscription. ";
  $page_title = "Subscription Renewal";
  &recutils::response_page( $message, $page_title );

  return "success";
}

sub renewal_confirm {
  my ( $message, $page_title ) = @_;
  print "Content-Type: text/html\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Subscription Renewal</title>\n";

  print "<script type=\"text/javascript\">\n";
  print "<\!-- Start Script\n";
  print "function closeresults() \{\n";
  print "  resultsWindow = window.close('results')\;\n";
  print "\}\n";
  print "// end script-->\n";
  print "</script>\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<br>\n";
  print "<div align=center>\n";
  print "<h3>$message</h3>\n";
  print "</div>\n";

  print "<br>\n";
  print "<div align=center><form method=post action=\"attendant.cgi\">\n";
  print "<input type=hidden name=\"username\" value=\"$username\">\n";
  print "<input type=hidden name=\"password\" value=\"$password\">\n";
  print "<input type=hidden name=\"cardnumber\" value=\"$cardnumber\">\n";
  print "<input type=hidden name=\"exp_month\" value=\"$exp_month\">\n";
  print "<input type=hidden name=\"exp_year\" value=\"$exp_year\">\n";
  print "<input type=hidden name=\"mode\" value=\"renewal\">\n";
  print "<input type=hidden name=\"submode\" value=\"confirm\">\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\"Confirm Renewal\"></form>\n";
  print "<p><form>\n";
  print "<input type=button class=\"button\" value=\"Cancel Renewal\" onClick=\"closeresults()\;\">\n";
  print "</div></form>\n";
  print "</body>\n";
  print "</html>\n";
}

sub attresponse {
  my ($message) = @_;
  print "Content-Type: text/html\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Subscription Renewal</title>\n";

  #print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/payment/recurring/stylesheet.css\">\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<br>\n";
  print "<div align=center>\n";
  print "<h3>$message</h3>\n";
  print "</div>\n";
  print "<br>\n";
  print "<div align=center><form action=\"attendant.html\">\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\"$desc_home\">\n";
  print "</div></form>\n";
  print "</body>\n";
  print "</html>\n";
}

sub paid_renewal {
  my ($message);
  ($discount) = @_;

  $username = &CGI::escapeHTML( $main::query->param('username') );
  $username =~ s/[^_0-9a-zA-Z\-\@\.]//g;

  $password = &CGI::escapeHTML( $main::query->param('password') );
  $password =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  $query{'card-number'} = &CGI::escapeHTML( $main::query->param('cardnumber') );
  $query{'card-number'} =~ s/[^0-9]//g;

  $exp_month = &CGI::escapeHTML( $main::query->param('exp_month') );
  $exp_month =~ s/[^0-9]//g;

  $exp_year = &CGI::escapeHTML( $main::query->param('exp_year') );
  $exp_year =~ s/[^0-9]//g;

  $query{'card-exp'} = "$exp_month/$exp_year";

  $submode = &CGI::escapeHTML( $main::query->param('submode') );
  $submode =~ s/[^a-zA-Z0-9\_\-]//g;

  $cardnumber = $query{'card-number'};
  $cardnumber =~ s/[^0-9]//g;

  $luhntest = &miscutils::luhn10($cardnumber);

  $dbh = &miscutils::dbhconnect("$main::merchant");
  $sth = $dbh->prepare(
    q{
      SELECT username,enddate
      FROM customer
      WHERE username=?
      AND password=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$username", "$password" ) or die "Can't execute: $DBI::errstr";
  ( $chkusername, $enddate ) = $sth->fetchrow;
  $sth->finish;

  if ( $chkusername eq "" ) {
    $message    = "Sorry, the Username and Password combination entered was not found in the database.  Please try again and be careful to use the proper CAPITALIZATION.";
    $page_title = "Subscription Renewal";
    &recutils::response_page( $message, $page_title );
    return "failure";
  } elsif ( ( length( $query{'card-number'} ) < 12 ) || ( $luhntest ne "success" ) ) {
    $message    = "The Credit Card entered is not a valid credit card number. Please check the number and resubmit.";
    $page_title = "Subscription Renewal";
    &recutils::response_page( $message, $page_title );
    return "failure";
  } elsif ( ( $enddate >= $today + 5 ) && ( $submode ne "confirm" ) ) {
    $enddatestr = sprintf( "%02d/%02d/%04d", substr( $enddate, 4, 2 ), substr( $enddate, 6, 2 ), substr( $enddate, 0, 4 ) );
    $message = "Your subscription expires or has already expired on $enddatestr.";
    $message .= " Press \'Confirm Renewal\' to complete the renewal or reactivation of your account. ";
    $dbh->disconnect;
    $page_title = "Subscription Renewal";
    &recutils::renewal_confirm( $message, $page_title );
    exit;
  } else {
    $query{'orderID'} = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
    ($today) = &miscutils::gendatetime_only();
    $sth = $dbh->prepare(
      q{
        SELECT username,purchaseid,name,addr1,addr2,city,state,zip,country,email,enddate,monthly,billcycle,lastbilled,status,acct_code
        FROM customer
        WHERE username=?
        AND password=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( "$username", "$password" ) or die "Can't execute: $DBI::errstr";
    ( $chkusername,         $query{'order-id'}, $query{'card-name'},    $query{'card-address1'}, $query{'card-address2'}, $query{'card-city'},
      $query{'card-state'}, $query{'card-zip'}, $query{'card-country'}, $query{'email'},         $end,                    $query{'card-amount'},
      $query{'billcycle'},  $start,             $query{'status'},       $query{'acct_code'}
    )
      = $sth->fetchrow;
    $sth->finish;

    $query{'card-amount'} = $query{'card-amount'} - $discount;

    &purchase();

    if ( $result{'FinalStatus'} eq "success" ) {
      $time = &miscutils::strtotime($end);

      ( $dummy1, $dummy2, $dummy3, $eday, $emonth, $eyear ) = gmtime($time);
      $emonth = $emonth + $query{'billcycle'};
      $eyear  = $eyear + 1900 + ( ( $emonth - ( $emonth % 12 ) ) / 12 );
      $emonth = ( $emonth % 12 ) + 1;
      $expire = sprintf( "%04d%02d%02d", $eyear, $emonth, $eday );

      ( $dummy1, $dummy2, $dummy3, $eday, $emonth, $eyear ) = gmtime(time);
      $emonth  = $emonth + $query{'billcycle'};
      $eyear   = $eyear + 1900 + ( ( $emonth - ( $emonth % 12 ) ) / 12 );
      $emonth  = ( $emonth % 12 ) + 1;
      $expire1 = sprintf( "%04d%02d%02d", $eyear, $emonth, $eday );

      if ( $expire1 > $expire ) {
        $expire = $expire1;
      }

      &update_cust_record();
      &update_billstatus();
      $message = "Thank you for renewing your subscription.<p>If your Username has previously expired it will be reactivated within 24 hours.";
    } else {
      &update_billstatus();
      $message = "The Credit Card entered has failed for the following reason:\n<p> $result{'message'}<p>\n\nPlease check the number and resubmit.";
    }
    $dbh->disconnect;
    $page_title = "Subscription Renewal";
    &recutils::response_page( $message, $page_title );
    return "success";
  }
}

sub update_cust_record {

  $cardnumber = $query{'card-number'};
  $cardlength = length $cardnumber;
  ( $enccardnumber, $encryptedDataLen ) = &rsautils::rsa_encrypt_card( $cardnumber, '/home/pay1/pwfiles/keys/key' );

  $cardnumber       = $query{'card-number'};
  $cardnumber       = substr( $cardnumber, 0, 4 ) . '**' . substr( $cardnumber, length($cardnumber) - 2, 2 );
  $encryptedDataLen = "$encryptedDataLen";

  $enccardnumber = &smpsutils::storecardnumber( $main::merchant, $username, 'recutils_update', $enccardnumber, 'rec' );

  $sth = $dbh->prepare(
    q{
      UPDATE customer
      SET enccardnumber=?,length=?,cardnumber=?,exp=?,enddate=?
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$enccardnumber", "$encryptedDataLen", "$cardnumber", "$query{'card-exp'}", "$expire", "$username" ) or die "Can't execute: $DBI::errstr";
  $sth->finish;
}

sub update_billstatus {
  if ( $result{'MStatus'} eq "success" ) {
    $amount = $query{'card-amount'};
  } else {
    $amount = "0.00";
  }

  $sth_billing = $dbh->prepare(
    q{
      INSERT INTO billingstatus
      (username,trans_date,amount,orderid,descr,result)
      VALUES (?,?,?,?,?,?)
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_billing->execute( "$username", "$today", "$amount", "$query{'orderID'}", "Manual Renewal", "$result{'MStatus'}" ) or die "Can't execute: $DBI::errstr";
  $sth_billing->finish;
}

sub purchase {
  $query{'publisher-name'} = $main::merchant;

  @array   = %query;
  $payment = mckutils->new(@array);
  %result  = $payment->purchase("mauthonly");
  $payment->database();

  $result{'message'} = $result{'aux-msg'} . $result{'MErrMsg'};
  $result{'message'} =~ s/[\n]//g;
}

sub extend {

  $mode = $main::mode;

  my ( $trans_date, $trans_time ) = &miscutils::gendatetime_only();

  $result = &checkunpw();

  if ( $result ne "success" ) {
    my $message = "Sorry, the Username and Password combination entered was not found in the database.  Please try again and be careful to use the proper CAPITALIZATION.";
    $page_title = "Subscription Renewal";
    &response_page( $message, $page_title );
    return "failure";
  }

  my $dbh = &miscutils::dbhconnect("$main::merchant");

  my $sth = $dbh->prepare(
    qq{
      SELECT enddate,billcycle,monthly,status,balance
      FROM customer
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  my ( $enddate, $billcycle, $monthly, $status, $balance ) = $sth->fetchrow;
  $sth->finish;

  if ( ( $enddate >= $trans_date ) && ( $submode ne "confirmrenewal" ) ) {
    $enddatestr = sprintf( "%02d/%02d/%04d", substr( $enddate, 4, 2 ), substr( $enddate, 6, 2 ), substr( $enddate, 0, 4 ) );
    my $message = "Your service expires or has already expired on $enddatestr. Press \'Confirm Renewal\' to complete the renewal or reactivation of your account. ";
    $page_title = "Subscription Renewal";
    &recutils::response_page( $message, $page_title );
    exit;
  } elsif ( $balance > 0 ) {
    my $message = "Your service appears to have already been marked for renewal and is scheduled to charge your account \$$monthly on or about $enddatestr.";
    $page_title = "Subscription Renewal";
    &recutils::response_page( $message, $page_title );
    exit;
  }

  my $sth2 = $dbh->prepare(
    q{
      UPDATE customer
      SET balance=?, billcycle='1', status='active'
      WHERE username=? 
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth2->execute( "$monthly", "$username" ) or die "Can't execute: $DBI::errstr";
  $sth2->finish;

  my $message = "Your service has been marked for renewal and is scheduled to charge your account \$$monthly on or about $enddatestr.";
  $page_title = "Subscription Renewal";
  &recutils::response_page( $message, $page_title );
  exit;

}

sub isMerchantCancelled {
  my ($merchant) = @_;

  ## Prevent script from running, when account is cancelled.
  my $dbh      = &miscutils::dbhconnect('pnpmisc');
  my $sth_cust = $dbh->prepare(
    q{
      SELECT status
      FROM customers
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth_cust->execute("$merchant") or die "Can't execute: $DBI::errstr";
  my ($status) = $sth_cust->fetchrow;
  $sth_cust->finish;
  $dbh->disconnect;

  if ( $status eq "cancelled" ) {
    return '1';
  }
  return '0';
}

1;
