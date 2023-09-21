#!/usr/local/bin/perl

$| = 1;

use lib '/home/p/pay1/perl_lib';
use Net::FTP;
use miscutils;
use Net::SSLeay qw(get_https post_https sslcat make_headers make_form);
use IO::Socket;
use Socket;
use rsautils;
use isotables;
use smpsutils;
use Time::Local;

# test ip 206.175.128.3

# visa net DirectLink-visanetemv version 1.7

my $mygroup = $ARGV[0];
if ( $mygroup eq "" ) {
  $mygroup = "0";
}
print "group: $mygroup\n";

# xxxx
$usevnetsslflag = 1;    # do not comment this line

if ( ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/p/pay1/batchfiles/visanetemv/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'visanetemv/genfiles.pl $mygroup'`;
if ( $cnt > 1 ) {
  print "genfiles.pl already running, exiting...\n";

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: visanetemv - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

$mytime  = time();
$machine = `uname -n`;
$pid     = $$;

chop $machine;
open( outfile, ">/home/p/pay1/batchfiles/visanetemv/pid$mygroup.txt" );
$pidline = "$mytime $$ $machine";
print outfile "$pidline\n";
close(outfile);

&miscutils::mysleep(2.0);

open( infile, "/home/p/pay1/batchfiles/visanetemv/pid$mygroup.txt" );
$chkline = <infile>;
chop $chkline;
close(infile);

if ( $pidline ne $chkline ) {
  print "genfiles.pl $mygroup already running, pid alterred by another program, exiting...\n";
  print "$pidline\n";
  print "$chkline\n";

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: visanetemv - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl $mygroup already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

$time = time();
( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $d8, $d9, $modtime ) = stat "/home/p/pay1/batchfiles/visanetemv/genfiles$mygroup.txt";

$delta = $time - $modtime;

if ( $delta < ( 3600 * 12 ) ) {
  umask 0033;
  open( checkin, "/home/p/pay1/batchfiles/visanetemv/genfiles$mygroup.txt" );
  $checkuser = <checkin>;
  chop $checkuser;
  close(checkin);
}

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>='$checkuser'";
}
$checkstring = "and t.username='testvisaemv'";

#$checkstring = "and t.username in ('aaaa','aaaa')";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 2 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 * 2 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

#print "two months ago: $twomonthsago\n";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $dummy, $today, $ttime ) = &miscutils::genorderid();
$todaytime = $ttime;

#$runtime = substr($ttime,8,2);

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/p/pay1/batchfiles/visanetemv/logs/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/p/pay1/batchfiles/visanetemv/logs/$fileyearonly");
  chmod( 0700, "/home/p/pay1/batchfiles/visanetemv/logs/$fileyearonly" );
}
if ( !-e "/home/p/pay1/batchfiles/visanetemv/logs/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/p/pay1/batchfiles/visanetemv/logs/$filemonth");
  chmod( 0700, "/home/p/pay1/batchfiles/visanetemv/logs/$filemonth" );
}
if ( !-e "/home/p/pay1/batchfiles/visanetemv/logs/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/p/pay1/batchfiles/visanetemv/logs/$fileyear");
  chmod( 0700, "/home/p/pay1/batchfiles/visanetemv/logs/$fileyear" );
}
if ( !-e "/home/p/pay1/batchfiles/visanetemv/logs/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: visanetemv - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory visanetemv/logs/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;

#$dbh = &miscutils::dbhconnect("pnpmisc");
$dbh2 = &miscutils::dbhconnect("pnpdata");

$sthtrans = $dbh2->prepare(
  qq{
        select t.username,count(t.username),min(o.trans_date)
        from operation_log o, trans_log t
        where t.trans_date>='$onemonthsago'
        and t.trans_date<='$today'
        and t.operation in ('postauth','return')
        $checkstring
        and t.finalstatus='pending'
        and (t.accttype is NULL or t.accttype='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.processor='visanetemv'
        and o.lastoptime>='$onemonthsagotime'
        and o.lastopstatus='pending'
        group by t.username
  }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthtrans->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthtrans->bind_columns( undef, \( $user, $usercount, $usertdate ) );
while ( $sthtrans->fetch ) {
  if ( $user ne "downgrape" ) {
    @userarray = ( @userarray, $user );
  }
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}
$sthtrans->finish;

$dbh2->disconnect;

foreach $username ( sort @userarray ) {
  &processbatch();
}

if ( $usercountarray{"downgrape"} ne "" ) {
  $username = "downgrape";
  &processbatch();
}

#$dbh->disconnect;
#$dbh2->disconnect;

unlink "/home/p/pay1/batchfiles/visanetemv/batchfile.txt";

if ( ( !-e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) && ( !-e "/home/p/pay1/batchfiles/visanetemv/stopgenfiles.txt" ) ) {
  umask 0033;
  open( checkin, ">/home/p/pay1/batchfiles/visanetemv/genfiles$mygroup.txt" );
  close(checkin);
}

exit;

sub pidcheck {
  open( infile, "/home/p/pay1/batchfiles/visanetemv/pid$mygroup.txt" );
  $chkline = <infile>;
  chop $chkline;
  close(infile);

  if ( $pidline ne $chkline ) {
    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
    print logfile "genfiles.pl $mygroup already running, pid alterred by another program, exiting...\n";
    print logfile "$pidline\n";
    print logfile "$chkline\n";
    close(logfile);

    print "genfiles.pl $mygroup $mygroup already running, pid alterred by another program, exiting...\n";
    print "$pidline\n";
    print "$chkline\n";

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: visanetemv - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl $mygroup $mygroup already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

sub processbatch {
  if ( ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/p/pay1/batchfiles/visanetemv/stopgenfiles.txt" ) ) {
    unlink "/home/p/pay1/batchfiles/visanetemv/batchfile.txt";
    last;
  }

  umask 0033;
  open( batchfile, ">/home/p/pay1/batchfiles/visanetemv/batchfile.txt" );
  print batchfile "$username\n";
  close(batchfile);

  $dontallowamexflag = 0;
  $dontallowdiscflag = 0;

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  $dbh2 = &miscutils::dbhconnect("pnpdata");

  if ( $usercountarray{$username} > 2000 ) {
    $batchcntuser = 500;    # visanetemv has trouble doing more than 500 records in a batch
  } elsif ( $usercountarray{$username} > 1000 ) {
    $batchcntuser = 300;
  } elsif ( $usercountarray{$username} > 600 ) {
    $batchcntuser = 200;
  } elsif ( $usercountarray{$username} > 300 ) {
    $batchcntuser = 100;
  } else {
    $batchcntuser = 100;
  }

  if ( $username =~ /^(thearenasa|agencyinsu1|agencyinsu|agencyserv|agencyserv1|streamrayc|friendfind7|mariobades3|mariobade4|friendfind9)$/ ) {
    $batchcntuser = 1200;
  }

  $dbh = &miscutils::dbhconnect("pnpmisc");
  local $sthcust = $dbh->prepare(
    qq{
        select c.merchant_id,c.pubsecret,c.proc_type,c.company,c.addr1,c.city,c.state,c.zip,c.tel,c.status,c.currency,
		c.switchtime,c.features,
		v.agentbank,v.agentchain,v.storenum,v.categorycode,v.bin,v.terminalnum,v.industrycode,v.track,v.batchtime,v.capabilities
        from customers c, visanet v
        where c.username='$username'
        and c.processor='visanetemv'
        and v.username=c.username
        }
    )
    or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthcust->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $merchant_id, $terminal_id, $proc_type,  $company,  $address,      $city, $state,       $zip,          $tel,   $status,     $currency, $switchtime,
    $features,    $agentbank,   $agentchain, $storenum, $categorycode, $bin,  $terminalnum, $industrycode, $track, $batchgroup, $capabilities
  )
    = $sthcust->fetchrow;
  $sthcust->finish;

  $mvv = "2222222222";

  $dbh->disconnect;

  if ( $status ne "test" ) {
    return;
  }

  #if (($mygroup eq "4") && ($batchgroup ne "4")) {
  #  return;
  #}
  #elsif (($mygroup eq "3") && ($batchgroup ne "3")) {
  #  return;
  #}
  #elsif (($mygroup eq "2") && ($batchgroup ne "2")) {
  #  return;
  #}
  #elsif (($mygroup eq "1") && ($batchgroup ne "1")) {
  #  return;
  #}
  #elsif (($mygroup eq "0") && ($batchgroup ne "")) {
  #  return;
  #}
  #elsif ($mygroup !~ /^(0|1|2|3|4)$/) {
  #  return;
  #}

  umask 0033;
  open( checkin, ">/home/p/pay1/batchfiles/visanetemv/genfiles$mygroup.txt" );
  print checkin "$username\n";
  close(checkin);

  #if (($runtime =~ /(20|21|22|23|00|01|02|03|04|05|06)/) && ($batchtime eq "2")) {
  #  return;
  #}
  #elsif (($runtime !~ /(20|21|22|23|00|01|02|03|04|05|06)/) && ($batchtime ne "2")) {
  #  return;
  #}

  umask 0077;
  open( logfile, ">/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
  print "$username $starttransdate\n";
  print logfile "$username\n";
  close(logfile);

  # sweeptime
  my %feature = ();
  if ( $features ne "" ) {
    my @array = split( /\,/, $features );
    foreach my $entry (@array) {
      my ( $name, $value ) = split( /\=/, $entry );
      $feature{$name} = $value;
    }
  }

  # sweeptime
  $sweeptime = $feature{'sweeptime'};    # sweeptime=1:EST:19   dstflag:timezone:time
  print "sweeptime: $sweeptime\n";
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
      print logfile "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      close(logfile);
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
      print logfile "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      close(logfile);
      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  print "gmt today: $todaytime\n";
  print "est today: $esttime\n";
  print "est yesterday: $yesterday\n";
  print "settletime: $settletime\n";
  print "sweeptime: $sweeptime\n";

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
  print "$username\n";
  print logfile "$username  sweeptime: $sweeptime  settletime: $settletime\n";
  print logfile "$features\n";
  close(logfile);

  $redobatch = 1;
  $firstredo = 0;
  while ( $redobatch == 1 ) {

    $batch_flag = 0;
    $netamount  = 0;
    $hashtotal  = 0;
    $batchcnt   = 1;
    $recseqnum  = 0;
    $redobatch  = 0;

    print "starttransdate: $starttransdate\n";
    print "today: $today\n";
    print "onemonthsagotime: $onemonthsagotime\n";
    print "username: $username\n";

    $sthtrans = $dbh2->prepare(
      qq{
          select orderid
          from operation_log
          where trans_date>='$starttransdate'
          and trans_date>='20150911'
          and trans_date<='$today'
          and lastoptime>='$onemonthsagotime'
          and username='$username'
          and lastopstatus='pending'
          and lastop in ('postauth','return')
          and (voidstatus is NULL or voidstatus='')
          and (accttype is NULL or accttype='' or accttype='credit')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthtrans->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthtrans->bind_columns( undef, \($orderid) );

    %orderidarray = ();
    while ( $sthtrans->fetch ) {

      #print "$orderid\n";
      $orderidarray{"$orderid"} = 1;
    }
    $sthtrans->finish;

    print "bbbb\n";

    $mintrans_date      = $today;
    $postauthtrans_date = $today;
    foreach $orderid ( sort keys %orderidarray ) {

      $sthtrans2 = $dbh2->prepare(
        qq{
            select lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,transflags,refnumber,lastopstatus,acct_code4
            from operation_log
            where orderid='$orderid'
            and username='$username'
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthtrans2->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      ( $operation, $trans_date, $trans_time, $enccardnumber, $enclength, $exp, $amount, $auth_code, $avs_code, $transflags, $refnumber, $finalstatus, $acct_code4 ) = $sthtrans2->fetchrow;
      $sthtrans2->finish;
      print "transflags: $transflags\n";

      if ( ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/p/pay1/batchfiles/visanetemv/stopgenfiles.txt" ) ) {
        unlink "/home/p/pay1/batchfiles/visanetemv/batchfile.txt";
        last;
      }

      if ( $operation eq "void" ) {
        $orderidold = $orderid;
        next;
      }
      if ( ( $orderid eq $orderidold ) || ( $finalstatus ne "pending" ) ) {
        $orderidold = $orderid;
        next;
      }

      $orderidold = $orderid;

      if ( ( $sweeptime ne "" ) && ( $trans_time > $sweeptime ) ) {
        $orderidold = $orderid;
        next;    # transaction is newer than sweeptime
      }

      if ( ( $trans_date < $mintrans_date ) && ( $trans_date >= '19990101' ) ) {
        $mintrans_date = $trans_date;
      }
      if ( ( $operation eq "postauth" ) && ( $trans_date < $postauthtrans_date ) && ( $trans_date >= '19990101' ) ) {
        $postauthtrans_date = $trans_date;
      }

      #select amount,operation
      #from trans_log
      #where orderid='$orderid'
      #and trans_date>='$twomonthsago'
      #and operation in ('auth','forceauth')
      #and username='$username'
      #and (accttype is NULL or accttype='credit')
      $sthamt = $dbh2->prepare(
        qq{
          select authtime,authstatus,forceauthtime,forceauthstatus,reauthtime,reauthstatus,origamount
          from operation_log
          where orderid='$orderid'
          and username='$username'
          and lastoptime>='$onemonthsagotime'
          and (accttype is NULL or accttype='' or accttype='credit')
          }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthamt->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      ( $authtime, $authstatus, $forceauthtime, $forceauthstatus, $reauthtime, $reauthstatus, $origamount ) = $sthamt->fetchrow;
      $sthamt->finish;

      if ( $switchtime ne "" ) {
        $switchtime = substr( $switchtime . "0" x 14, 0, 14 );
        if ( ( $operation eq "postauth" ) && ( $authtime ne "" ) && ( $authtime < $switchtime ) ) {
          next;
        }
      }

      if ( ( $authtime ne "" ) && ( $authstatus eq "success" ) ) {

        #$trans_time = $authtime;
        $origoperation = "auth";
      } elsif ( ( $forceauthtime ne "" ) && ( $forceauthstatus eq "success" ) ) {

        #$trans_time = $forceauthtime;
        $origoperation = "forceauth";
      } else {

        #$trans_time = "";
        $origoperation = "";
        $origamount    = "";
      }

      if ( ( $reauthtime ne "" ) && ( $reauthstatus eq "success" ) ) {
        $reauthflag = 1;
      } else {
        $reauthflag = 0;
      }

      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
      print logfile "$orderid $operation\n";
      close(logfile);
      print "$orderid $operation\n";

      $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

      #$card_type = &smpsutils::checkcard($cardnumber);
      $card_type = substr( $auth_code, 185, 2 );
      print "enccardnumber: $enccardnumber\n";
      print "cardnumber: $cardnumber\n";

      $errorflag = &errorchecking();
      if ( $errorflag == 1 ) {
        next;
      }
      print "dddd\n";

      if ( ( $dontallowamexflag == 1 ) && ( $card_type eq "ax" ) ) {
        next;
      } elsif ( ( $dontallowdiscflag == 1 ) && ( $card_type eq "ds" ) ) {
        next;
      }

      if ( $batchcnt == 1 ) {
        if ( $usevnetsslflag == 0 ) {

          #&socketopen("208.224.251.11",23);	# production
          &socketopen( "208.224.251.10", 23 );    # test
          recv( SOCK, $respenc, 2048, 0 );

          umask 0077;
          open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
          $temp = unpack "H*", $respenc;
          print "recva: $temp\n";
          print logfile "recva: $temp\n";
          close(logfile);

          if ( $respenc !~ /\x05/ ) {
            recv( SOCK, $respenc, 2048, 0 );

            umask 0077;
            open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
            $temp = unpack "H*", $respenc;
            print "recvb: $temp\n";
            print logfile "recvb: $temp\n";
            close(logfile);
          }
        }

        print "\nsocketopen\n";
        $errorflag       = 0;
        $startbatchflag  = 1;
        $returnsincluded = 0;

        &pidcheck();

        &batchheader();
        $startbatchflag = 0;
        if ( $merchanterrorflag == 1 ) {
          last;
        } elsif ( $errorflag == 1 ) {
          $batchcnt = 1;
          next;
        }
      }

      if ( $operation eq "return" ) {
        $returnsincluded = 1;
      }

      my $sthlock = $dbh2->prepare(
        qq{
            update trans_log set finalstatus='locked',result='$time$batchnum'
	    where orderid='$orderid'
	    and username='$username'
	    and trans_date>='$onemonthsago'
	    and finalstatus='pending'
            and operation in ('postauth','return')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthlock->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthlock->finish;

      $operationstatus = $operation . "status";
      $operationtime   = $operation . "time";
      my $sthop = $dbh2->prepare(
        qq{
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending'
          where orderid='$orderid'
          and username='$username'
          and $operationstatus='pending'
          and (voidstatus is NULL or voidstatus='')
          and (accttype is NULL or accttype='' or accttype='credit')
          }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthop->execute("$time$batchnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthop->finish;

      &batchdetail();
      if ( $errorcnt{$username} > 5 ) {
        last;
      }
      if ( $errorflag == 1 ) {
        $batchcnt = 1;
        next;
      }

      if ( $batchcnt >= $batchcntuser ) {
        $endbatchflag = 1;
        &batchtrailer();
        &sslsend();
        $batchcnt     = 1;
        $endbatchflag = 0;
      }
    }

    if ( $batchcnt > 1 ) {
      $endbatchflag = 1;
      &batchtrailer();
      &sslsend();
      $endbatchflag = 0;
    }

  }
  $dbh2->disconnect;
}

sub batchheader {
  $cashbacktotal     = 0;
  $netamount         = 0;
  $hashtotal         = 0;
  $recseqnum         = 0;
  $batch_flag        = 0;
  $batchsalescnt     = 0;
  $batchsalesamt     = 0;
  $batchretcnt       = 0;
  $batchretamt       = 0;
  %errorderid        = ();
  $bigmessage        = "";
  $merchanterrorflag = 0;

  $batchcount++;

  $dbh = &miscutils::dbhconnect("pnpmisc");
  local $sthinfo = $dbh->prepare(
    qq{
          select batchnum,authen
          from visanet
          where username='$username'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $batchnum, $authencode ) = $sthinfo->fetchrow;
  $sthinfo->finish;

  #$authencode = "2F826C0C2A04380C11566E9D";

  $batchnum = $batchnum + 1;
  if ( $batchnum >= 998 ) {
    $batchnum = 1;
  }

  local $sthinfo = $dbh->prepare(
    qq{
          update visanet set batchnum=?
          where username='$username'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute("$batchnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthinfo->finish;

  $dbh->disconnect;

  $batchreccnt = 1;
  $filereccnt++;
  $recseqnum++;

  @bh = ();
  $bh[0] = pack "H2", "02";    # stx
  $bh[1] = 'K';                # record format (1a)
  $bh[2] = '1';                # application type 0 = single, 4 = multiple interleaved(1a)
  $bh[3] = '.';                # message delimiter (1a)
  $bh[4] = 'Z';                # X.25 Routing ID (1a)
  if ( $industrycode !~ /^(retail|grocery|restaurant)$/ ) {
    $bh[5] = 'H@@@R';          # record type (5a)
  } elsif ( $authencode ne "" ) {
    $bh[5] = 'H@@@X';          # record type (5a)
  } else {
    $bh[5] = 'H@@@P';          # record type (5a)
  }
  $bin = substr( "0" x 6 . $bin, -6, 6 );
  $bh[6] = $bin;               # acquirer bin (6n) 999295
  $agentbank = substr( "0" x 6 . $agentbank, -6, 6 );
  $bh[7] = $agentbank;         # agent bank number (6n)
  $agentchain = substr( "0" x 6 . $agentchain, -6, 6 );
  $bh[8] = $agentchain;        # agent chain number (6n)
  $mid = substr( "0" x 12 . $merchant_id, -12, 12 );
  $bh[9] = $mid;               # merchant number (12n)
  $storenum = substr( "0" x 4 . $storenum, -4, 4 );
  $bh[10] = $storenum;         # store number (4n)
  $terminalnum = substr( "0" x 4 . $terminalnum, -4, 4 );
  $bh[11] = $terminalnum;      # terminal number (4n)
                               #if ($usevnetsslflag == 1) {
                               #  $bh[12] = 'E';                    # device code (1a) E - electronic cash register 4.33
                               #}
                               #else {
  $bh[12] = 'Q';               # device code (1a) Q - third party developer 4.33
                               #}

  if ( $industrycode eq "retail" ) {
    $bh[13] = "R";             # industry code (1a) D - direct marketing, R - retail, F - restaurant, G - grocery 4.40
  } elsif ( $industrycode eq "restaurant" ) {
    $bh[13] = "F";             # industry code (1a) D - direct marketing, R - retail, F - restaurant, G - grocery 4.40
  } elsif ( $industrycode eq "grocery" ) {
    $bh[13] = "G";             # industry code (1a) D - direct marketing, R - retail, F - restaurant, G - grocery 4.40
  } else {
    $bh[13] = 'D';             # industry code (1a) D - direct marketing 4.40
  }
  if ( $currency eq "" ) {
    $currency = "usd";
  }
  $currency =~ tr/a-z/A-Z/;
  $currencycode = $isotables::currencyUSD840{$currency};
  $bh[14]       = $currencycode;                           # currency code (3n)
  $bh[15]       = '00';                                    # language indicator (2n) 00 - english 4.45
  $bh[16]       = '705';                                   # time zone differential (3n) - 705 = using EST (not sure if correct)
  $batchdate    = substr( $today, 4, 4 );
  $bh[17]       = $batchdate;                              # batch transmission date (4n)
  $batchnum     = substr( "000" . $batchnum, -3, 3 );
  $bh[18]       = $batchnum;                               # batch number (3n)
  $bh[19]       = '0';                                     # blocking indicator (1n)

  # group 2
  if ( $industrycode !~ /^(retail|grocery|restaurant)$/ ) {
    $tel =~ s/^1//;
    $tel =~ s/[^0-9A-Z]//g;
    $tel = substr( $tel, 0, 3 ) . '-' . substr( $tel, 3, 7 );
    $tel = substr( $tel . " " x 11, 0, 11 );
    $bh[20] = $tel;                                        # 999-9999999
    $bh[21] = $tel;                                        # 999-9999999
  } else {

    # group 4
    if ( $authencode ne "" ) {
      $bh[20] = $authencode;                               # authentication code
    }
  }

  # group 5
  $bh[22] = '000325';                                      # developer id
  $bh[23] = 'B018';                                        # version id

  $bh[25] = pack "H2", "17";                               # etb

  $message = "";
  foreach $var (@bh) {
    $message = $message . $var;
  }
  &sendrecord($message);
  if ( ( $usevnetsslflag == 0 ) && ( ( length($response) != 1 ) || ( $response !~ /^(\x05|\x06|\x07)$/ ) ) ) {
    $errorcnt{$username}++;
    &error("header");
  }

  $recseqnum++;

  @bp = ();
  $bp[0]       = pack "H2", "02";    # stx
  $bp[1]       = 'K';                # record format (1a)
  $bp[2]       = '1';                # application type 0 = single, 4 = multiple interleaved(1a)
  $bp[3]       = '.';                # message delimiter (1a)
  $bp[4]       = 'Z';                # X.25 Routing ID (1a)
  $bp[5]       = 'P@@@@';            # record type (5a)
  $countrycode = "840";              # 084 = US
  $bp[6]       = $countrycode;       # country code (3n)
  $zip =~ s/[^0-9]//g;
  $zip = substr( $zip . " " x 9, 0, 9 );
  $bp[7] = $zip;                     # city code (9a)
  $bp[8] = $categorycode;            # merchant category code (4n)
  $company =~ tr/a-z/A-Z/;
  $company = substr( $company . " " x 25, 0, 25 );
  $bp[9] = $company;                 # merchant name (25a)
  my $data = "";

  if ( $industrycode =~ /^(retail|grocery|restaurant)$/ ) {
    $city =~ tr/a-z/A-Z/;
    $data = substr( $city . " " x 13, 0, 13 );
  } else {
    $tel =~ s/[^0-9A-Z]//g;
    $tel = substr( $tel, 0, 3 ) . '-' . substr( $tel, 3, 7 );
    $data = substr( $tel . " " x 13, 0, 13 );
  }
  $bp[10] = $data;                   # merchant city or tel (13a)
  $state =~ tr/a-z/A-Z/;
  $state = substr( $state . "  ", 0, 2 );
  $bp[11] = $state;                  # merchant state (2a)
  $bp[12] = '00001';                 # merchant location number (5a)
  $tid = substr( "0" x 8 . $terminal_id, -8, 8 );
  $bp[13] = $tid;                    # terminal id number (8n)
  $bp[14] = pack "H2", "17";         # etb

  $message = "";
  foreach $var (@bp) {
    $message = $message . $var;
  }
  &sendrecord($message);

  if ( ( $usevnetsslflag == 0 ) && ( ( length($response) != 1 ) || ( $response !~ /^(\x05|\x06|\x07)$/ ) ) ) {
    &error("parameter");
  }

}

sub batchdetail {

  $transamt = substr( $amount, 4 );
  $transamt = $transamt * 100;
  $transamt = sprintf( "%0d", $transamt + .0001 );
  if ( $operation eq "postauth" ) {
    $netamount = $netamount + $transamt;
  } else {
    $netamount = $netamount - $transamt;
  }

  $hashtotal = $hashtotal + $transamt;

  $batchcnt++;
  $batchreccnt++;
  $recseqnum++;

  $commcardtype = "";
  if ( $operation eq "postauth" ) {
    $commcardtype = substr( $auth_code, 29, 10 );
    $commcardtype =~ s/ //g;
  }
  print "commcardtype: $commcardtype\n\n";

  print "auth_code: $auth_code\n";
  if ( ( $operation eq "postauth" ) && ( ( length($auth_code) == 8 ) || ( length($auth_code) == 20 ) || ( $origoperation eq "forceauth" ) ) ) {
    $authcode         = substr( $auth_code . " " x 6, 0, 6 );
    $aci              = " ";
    $auth_src         = substr( $auth_code, 7, 1 );
    $auth_src         = substr( $auth_src . " ", 0, 1 );
    $resp_code        = "  ";
    $trans_id         = "0" x 15;
    $val_code         = "    ";
    $trandate         = substr( $trans_time, 4, 4 );
    $trantime         = substr( $trans_time, 8, 6 );
    $transseqnum      = "0001";
    $tax              = "0" x 12;
    $ponumber         = "";
    $cardholderidcode = "";
    $acctdatasrc      = "";
    $requestedaci     = "";
    if ( $transflags =~ /debit/ ) {
      $cardholderidcode = substr( $auth_code, 88, 1 );
      $acctdatasrc      = substr( $auth_code, 89, 1 );
      $trandate         = substr( $auth_code, 41, 4 );    # MMDD
      $trantime         = substr( $auth_code, 45, 6 );
    }
    if ( length($auth_code) == 20 ) {
      $gratuity = substr( $auth_code, 8, 12 );
    } elsif ( length($auth_code) > 91 ) {
      $gratuity = substr( $auth_code, 91, 12 );
    } else {
      $gratuity = "0" x 12;
    }
    $restorigamount = "0" x 12;

    $dbh = &miscutils::dbhconnect("pnpmisc");
    my $sth = $dbh->prepare(
      qq{
        select transseqnum
        from visanet
        where username='$username'
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ($transseqnum) = $sth->fetchrow;
    $sth->finish;

    $transseqnum = ( $transseqnum % 9999 ) + 1;

    my $sth = $dbh->prepare(
      qq{
        update visanet set transseqnum=?
        where username='$username'
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth->execute("$transseqnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sth->finish;
    $dbh->disconnect;

    $transseqnum = substr( "0000" . $transseqnum, -4, 4 );
  } elsif ( ( $operation eq "postauth" ) || ( ( $operation eq "return" ) && ( $transflags =~ /debit/ ) ) ) {
    $authcode  = substr( $auth_code . " " x 6, 0,  6 );
    $aci       = substr( $auth_code,           6,  1 );
    $aci       = substr( $aci . " ",           0,  1 );
    $auth_src  = substr( $auth_code,           7,  1 );
    $auth_src  = substr( $auth_src . " ",      0,  1 );
    $resp_code = substr( $auth_code,           8,  2 );
    $resp_code = substr( $resp_code . "  ",    0,  2 );
    $trans_id  = substr( $auth_code,           10, 15 );
    $trans_id  = substr( $trans_id . "0" x 15, 0,  15 );
    $val_code  = substr( $auth_code,           25, 4 );
    $val_code  = substr( $val_code . " " x 4,  0,  4 );
    $trandate  = substr( $auth_code,           39, 4 );
    $trantime  = substr( $auth_code,           45, 6 );

    #if ($username eq "taketoau2") {}
    if ( ( $industrycode !~ /^(retail|grocery|restaurant)$/ ) || ( $transflags =~ /moto/ ) ) {
      my $ltime = &miscutils::strtotime($trans_time);
      if ( $ltime ne "" ) {
        my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($ltime);
        $year     = $year + 1900;
        $year     = substr( $year, 2, 2 );
        $trantime = sprintf( "%04d%02d%02d%02d%02d%02d", $year, $month + 1, $day, $hour, $min, $sec );
      } else {
        $trantime = $trans_time;
      }
      $trandate = substr( $trantime, 4, 4 );
      $trantime = substr( $trantime, 8, 6 );
    }
    $trandate    = substr( $trandate . " " x 4,    0,   4 );
    $trantime    = substr( $trantime . " " x 6,    0,   6 );
    $transseqnum = substr( $auth_code,             51,  4 );
    $transseqnum = substr( $transseqnum . " " x 4, 0,   4 );
    $tax         = substr( $auth_code,             55,  8 );
    $tax         = substr( "0" x 12 . $tax,        -12, 12 );
    $ponumber    = substr( $auth_code,             63,  25 );
    $ponumber =~ s/ //g;
    $cardholderidcode = substr( $auth_code, 88,  1 );
    $acctdatasrc      = substr( $auth_code, 89,  1 );
    $requestedaci     = substr( $auth_code, 90,  1 );
    $gratuity         = substr( $auth_code, 91,  12 );
    $restorigamount   = substr( $auth_code, 103, 12 );

    if ( ( $operation eq "return" ) && ( $transflags =~ /reenter/ ) ) {
      $cardholderidcode = substr( $auth_code, 88, 1 );
      $acctdatasrc      = substr( $auth_code, 89, 1 );
      $trandate         = substr( $auth_code, 41, 4 );    # MMDD
      $trantime         = substr( $auth_code, 45, 6 );
      $trans_id         = "0" x 15;
      $val_code         = " " x 4;
    }
  } else {
    $authcode  = " " x 6;
    $aci       = " ";
    $auth_src  = "9";
    $resp_code = "  ";
    $trans_id  = "0" x 15;
    $val_code  = "    ";

    #$trandate = substr($trans_time,4,4);
    #$trantime = substr($trans_time,8,6);
    my $ltime = &miscutils::strtotime($trans_time);
    if ( $ltime ne "" ) {
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($ltime);
      $year     = $year + 1900;
      $year     = substr( $year, 2, 2 );
      $trantime = sprintf( "%04d%02d%02d%02d%02d%02d", $year, $month + 1, $day, $hour, $min, $sec );
    } else {
      $trantime = $trans_time;
    }
    $trandate = substr( $trantime, 4, 4 );
    $trantime = substr( $trantime, 8, 6 );

    $tax              = "0" x 12;
    $ponumber         = "";
    $cardholderidcode = "";
    $acctdatasrc      = "";
    $requestedaci     = "";
    $gratuity         = "0" x 12;
    $restorigamount   = "0" x 12;

    $dbh = &miscutils::dbhconnect("pnpmisc");
    my $sth = $dbh->prepare(
      qq{
        select transseqnum
        from visanet
        where username='$username'
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ($transseqnum) = $sth->fetchrow;
    $sth->finish;

    $transseqnum = ( $transseqnum % 9999 ) + 1;

    my $sth = $dbh->prepare(
      qq{
        update visanet set transseqnum=?
        where username='$username'
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth->execute("$transseqnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sth->finish;
    $dbh->disconnect;

    $transseqnum = substr( "0000" . $transseqnum, -4, 4 );
  }

  if ( $transseqnum =~ / / ) {
    $transseqnum = "0001";
  }

  $cardlevelresults = substr( $auth_code, 115, 2 );
  $cardlevelresults =~ s/ //g;

  @bd = ();
  $bd[0] = pack "H2", "02";    # stx
  $bd[1] = 'K';                # record format (1a)
  $bd[2] = '1';                # application type 0 = single, 4 = multiple interleaved(1a)
  $bd[3] = '.';                # message delimiter (1a)
  $bd[4] = 'Z';                # X.25 Routing ID (1a)

  if ( ( $cardlevelresults ne "" ) || ( ( $card_type eq "vi" ) && ( $transflags =~ /(recurring|install|bill|debt)/ ) ) ) {
    if ( $commcardtype ne "" ) {
      $bd1 = 'DX';
    } else {
      $bd1 = 'DP';             # `
    }
  } else {
    if ( $commcardtype ne "" ) {
      $bd1 = 'DH';
    } else {
      $bd1 = 'D@';
    }
  }

  $ucafind = substr( $auth_code, 122, 1 );
  $ucafind =~ s/ //g;
  if ( $ucafind ne "" ) {
    $bd2 = "P";    # ucaf collection indicator
  } elsif ( ( $card_type eq "vi" ) && ( $transflags =~ /debt/ ) ) {
    $bd2 = "H";    # existing debt indicator
  } else {
    $bd2 = "@";
  }
  print "$industrycode $transflags\n";

  if ( ( $industrycode =~ /^(retail|grocery)$/ ) && ( $transflags =~ /debit/ ) ) {
    $bd3 = 'H@';
  } elsif ( ( $industrycode eq "restaurant" ) && ( $transflags =~ /debit/ ) ) {
    $bd3 = 'HB';
  } elsif ( $industrycode eq "restaurant" ) {
    $bd3 = '@B';
  } elsif ( $industrycode =~ /^(retail|grocery)$/ ) {
    $bd3 = '@@';
  } else {
    $bd3 = '`D';    # `
  }
  $bd[5] = $bd1 . $bd2 . $bd3;    # record type (5a)

  print "$industrycode $transflags\n";
  if ( ( $transflags =~ /debit/ ) && ( $operation eq "return" ) ) {
    $tcode = '94';
  } elsif ( $transflags =~ /debit/ ) {
    $tcode = '93';
  } elsif ( $operation eq "return" ) {
    $tcode = 'CR';
  } elsif ( ( $card_type eq "vi" ) && ( $transflags =~ /(recurring|install|bill|debt)/ ) ) {
    $tcode = '5B';
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $operation eq "postauth" ) ) {
    $tcode = '54';
  } elsif ( $operation eq "postauth" ) {
    $tcode = '56';
  }
  $bd[6] = $tcode;    # transaction code (2a)
  print "$tcode\n";

  if ( $cardholderidcode ne "" ) {
    $bd[7] = "$cardholderidcode";    # cardholder id code (1a)
  } elsif ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) {
    $bd[7] = '@';                    # cardholder id code (1a)
  } else {
    $bd[7] = 'N';                    # cardholder id code (1a)
  }

  if ( $acctdatasrc ne "" ) {
    $bd[8] = $acctdatasrc;           # account data source (1a)
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $transflags =~ /emvctls/ ) ) {
    $bd[8] = 'R';                    # account data source (1a)
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $transflags =~ /ctls/ ) ) {
    $bd[8] = 'Q';                    # account data source (1a)
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $track eq "2" ) ) {
    $bd[8] = 'S';                    # account data source (1a)
                                     #$bd[8] = 'T';                     # account data source (1a)
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $track eq "1" ) ) {
    $bd[8] = 'X';                    # account data source (1a)
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $transflags =~ /emv/ ) && ( $aaaa eq "fallback" ) ) {
    $bd[8] = 'Z';                    # account data source (1a)
  } else {
    $bd[8] = 'P';                    # account data source (1a)
                                     #$bd[8] = '@';                     # account data source (1a)
  }

  $cardnumber = substr( $cardnumber . " " x 22, 0, 22 );
  $bd[9] = $cardnumber;              # cardholder acct num (22a)

  if ( ( $requestedaci ne "" ) && ( $requestedaci ne " " ) ) {
    $bd[10] = $requestedaci;         # requested ACI (1a)
  } elsif ( $transflags =~ /(install|bill|recurring)/ ) {
    $bd[10] = 'R';                   # requested ACI (1a)
  } else {
    $bd[10] = 'Y';                   # requested ACI (1a)
  }
  $bd[11] = $aci;                    # returned ACI (1a)
  $bd[12] = $auth_src;               # authorization source code (1a)
  $bd[13] = $transseqnum;            # trans seq num (4n)
  $bd[14] = $resp_code;              # response code (2a)
  $bd[15] = $authcode;               # authorization code (6a)
  $bd[16] = $trandate;               # local trans date MMDD (4n)
  $bd[17] = $trantime;               # local trans time HHMMSS (6n)
  $avs_code = substr( $avs_code . "0", 0, 1 );
  $bd[18] = $avs_code;               # avs result code (1a)
  $bd[19] = $trans_id;               # trans id (15a)
  $bd[20] = $val_code;               # validation code (4a)
  $bd[21] = ' ';                     # void indicator (1a)

  if ( ( $reauthflag == 1 ) && ( $card_type eq "vi" ) ) {
    $bd[22] = '10';                  # transaction status code (2n)
  } else {
    $bd[22] = '00';                  # transaction status code (2n)
  }
  $bd[23] = '0';                     # reimbursement attr (1a)
  $amt = substr( "0" x 12 . $transamt, -12, 12 );
  $bd[24] = $amt;                    # settlement amount (12n)
  if ( $industrycode eq "restaurant" ) {
    $authamt = $restorigamount;
  } elsif ( $origamount ne "" ) {
    $authamt = substr( $origamount, 4 );
    $authamt = sprintf( "%d", ( $authamt * 100 ) + .0001 );
    $authamt = substr( "0" x 12 . $authamt, -12, 12 );
  } else {
    $authamt = $amt;
  }

  if ( ( $origoperation eq "forceauth" ) || ( $operation eq "return" ) ) {
    $bd[25] = "0" x 12;              # authorized amount (12n)
  } else {
    $bd[25] = $authamt;              # authorized amount (12n)
  }

  my @group = ();

  # group 1 for retail, grocery cashback
  $cashback = substr( $auth_code, 169, 12 );
  $cashback =~ s/ //g;
  if ( ( $industrycode =~ /^(retail|grocery)$/ ) && ( $cashback > 0 ) ) {
    $cashbacktotal = $cashbacktotal + $cashback;
    $group[1] = $cashback;    # group 1 - cashback (12n)
  }

  # group 2 for restaurant
  if ( ( $industrycode eq "restaurant" ) && ( $operation eq "postauth" ) ) {
    $group[2] = $gratuity;    # group 2 - gratuity (12n)
  }

  if ( ( ( $card_type eq "vi" ) && ( $transflags =~ /bill|debt/ ) ) || ( $industrycode !~ /^(retail|grocery|restaurant)$/ ) ) {
    if ( ( $origoperation eq "forceauth" ) || ( $operation eq "return" ) ) {
      $group3amt = "0" x 12;    # group 3 - total auth amount (12n)
    } else {
      $group3amt = $authamt;    # group 3 - total auth amount (12n)
    }

    #if ($ponumber ne "") {
    #  $purchaseid = substr($ponumber . " " x 25,0,25);
    #}
    #else {
    #  $purchaseid = substr($orderid . " " x 25,0,25);
    #}
    if ( $ponumber ne "" ) {
      $purchaseid = substr( $ponumber, -17, 17 );
      $purchaseid = substr( $purchaseid . " " x 25, 0, 25 );
    } else {
      $purchaseid = substr( $orderid, -17, 17 );
      $purchaseid = substr( $purchaseid . " " x 25, 0, 25 );
    }

    # group 3 for moto/ecom
    $group[3] = $group3amt . '1' . $purchaseid;    # group 3 - purchase id (25a)

    # group 12
    $eci = substr( $auth_code, 121, 1 );
    $eci =~ s/ //g;
    if ( $transflags =~ /(install)/ ) {
      $installinfo = substr( $auth_code, 117, 4 );
      $installinfo =~ s/ //g;
      $installinfo = substr( "0" x 4 . $installinfo, -4, 4 );
      $group[12] = $installinfo . '3';             # group 12 - 7 = ecom, 2 = recurring (5a)
    } elsif ( $transflags =~ /(recurring)/ ) {
      $group[12] = '00002';                        # group 12 - 7 = ecom, 2 = recurring (5a)
    } elsif ( ( $industrycode eq "retail" ) || ( $transflags =~ /(moto)/ ) ) {
      $group[12] = '00001';                        # group 12 - 7 = ecom, 2 = recurring (5a)
    } elsif ( $eci ne "" ) {
      $group[12] = '0000' . $eci;                  # group 12 - 7 = ecom, 2 = recurring (5a)
    } else {
      $group[12] = '00007';                        # group 12 - 7 = ecom, 2 = recurring (5a)
    }
  }

  # group 10 for debit
  if ( $transflags =~ /debit/ ) {
    $refnumber = substr( $refnumber . " " x 12, 0, 12 );

    #$bd[26] = $refnumber;           # retrieval reference number (12n)
    my $stan = substr( $refnumber, -6, 6 );

    #$bd[27] = $stan;           	    # system trace audit number (6n)
    $networkid = substr( $auth_code,       164, 1 );
    $networkid = substr( $networkid . " ", 0,   1 );

    #$bd[28] = $networkid;           # network identification code (1n)
    $settledate = substr( $auth_code,            165, 4 );
    $settledate = substr( $settledate . " " x 4, 0,   4 );

    #$bd[29] = $settledate;          # settlement date (4n) MMDD
    $group[10] = $refnumber . $stan . $networkid . $settledate;    # group 10 - debit data
  }

  if ( ( $card_type eq "vi" ) && ( $transflags =~ /debt/ ) ) {
    $group[16] = '9';                                              # group 16 - existing debt indicator
  }

  $ucafind = substr( $auth_code, 122, 1 );
  $ucafind =~ s/ //g;
  if ( ( $card_type eq "mc" ) && ( $ucafind ne "" ) ) {
    $group[17] = $ucafind;                                         # group 17 - ucaf collection indicator
  }

  # group 20
  if ( ( $transflags =~ /hsa/ ) && ( $mvv ne "" ) ) {
    $group[20] = $mvv;                                             # group 20 - merchant verification value
  }

  # group 21 or 22
  if ( $commcardtype ne "" ) {
    if ( ( $capabilities =~ /ax/ ) && ( $card_type eq "ax" ) ) {    # ax purchase card data only sent if merch is setup at Tsys for it and it's required by ax
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() );
      my $juliantime = sprintf( "%03d%02d%02d%02d", $yday, $hour, $min, $sec );
      $newauthcode = substr( $auth_code . " " x 133, 0, 133 ) . $juliantime . substr( $auth_code, 142 );
      my $newauthcode = substr( $auth_code, 0, 133 ) . $juliantime . substr( $auth_code, 142 );

      my $sthlock = $dbh2->prepare(
        qq{
              update trans_log set auth_code=?
	      where orderid='$orderid'
	      and username='$username'
	      and trans_date>='$onemonthsago'
	      and finalstatus='locked'
              and (accttype is NULL or accttype='' or accttype='credit')
              }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthlock->execute("$newauthcode") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthlock->finish;

      my $sthop = $dbh2->prepare(
        qq{
            update operation_log set auth_code=?
            where orderid='$orderid'
            and username='$username'
            and lastopstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthop->execute("$newauthcode") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthop->finish;

      if ( $ponumber ne "" ) {
        $purchaseid = substr( $ponumber . " " x 17, 0, 17 );
      } else {
        $purchaseid = substr( $orderid, -17, 17 );
        $purchaseid = substr( $purchaseid . " " x 17, 0, 17 );
      }
      my $suppliernum = $juliantime;
      my $shipzip = substr( $auth_code, 123, 10 );
      $shipzip =~ s/ //g;
      if ( length($shipzip) == 9 ) {
        $shipzip = substr( $shipzip, 0, 5 );
      }
      $shipzip = substr( $shipzip . " " x 6, 0, 6 );
      my $tax = substr( $tax, -6, 6 );
      my $chargedescriptor = "purchase";
      $chargedescriptor =~ tr/a-z/A-Z/;
      $chargedescriptor = substr( $chargedescriptor . " " x 40, 0, 40 );
      $group[21] = $suppliernum . $purchaseid . $shipzip . $tax . $chargedescriptor;
    } elsif ( $card_type eq "vi" ) {
      if ( $tax > 0 ) {
        $optamtid = '1';     # optional amount identifier (1a)
        $optamt   = $tax;    # optional amount (12n)
      } elsif ( ( $transflags =~ /exempt/ ) && ( $transflags !~ /notexempt/ ) ) {
        $optamtid = '2';         # optional amount identifier (1a)
        $optamt   = '0' x 12;    # optional amount (12n)
      } else {
        $optamtid = '0';         # optional amount identifier (1a)
        $optamt   = '0' x 12;    # optional amount (12n)
      }

      #$purchaseid = substr($orderid . " " x 17,0,17);
      if ( $ponumber ne "" ) {
        $purchaseid = substr( $ponumber . " " x 17, 0, 17 );
      } else {
        $purchaseid = substr( $orderid, -17, 17 );
        $purchaseid = substr( $purchaseid . " " x 17, 0, 17 );
      }
      $group[22] = $optamtid . $optamt . $purchaseid;    # purchase order number (17a)
    }
  }

  my $posentry = substr( $auth_code, 151, 12 );
  if ( $posentry ne "            " ) {
    $group[32] = $posentry;
  }

  $cardlevelresults = substr( $auth_code, 115, 2 );
  $cardlevelresults =~ s/ //g;
  if ( ( $cardlevelresults ne "" ) || ( $transflags =~ /hsa/ ) || ( ( $card_type eq "vi" ) && ( $transflags =~ /recurring|install|bill|debt/ ) ) ) {

    # group 23 group map extension
    #my $bd1 = '@';
    #my $bd2 = '@';

    # group 31
    if ( ( $card_type eq "vi" ) && ( $transflags =~ /(recurring|install|bill|debt)/ ) ) {

      #$bd1 = 'A';
      $group[31] = 'B';    # bill payment indicator
    } elsif ( ( $card_type =~ /^(vi|mc)$/ ) && ( $transflags =~ /hsa/ ) ) {
      $group[31] = 'M';    # bill payment indicator
    }

    # group 38
    if ( $cardlevelresults ne "" ) {

      #$bd2 = 'B';
      $cardlevelresults = substr( $auth_code, 115, 2 );
      $cardlevelresults = substr( $cardlevelresults . " " x 2, 0, 2 );
      $group[38] = '001' . $cardlevelresults;    # card level results
    }

    #$bd[34] = '@' . $bd2 . $bd1 . '@';		# group 23     group extension map groups 25 - 48
  }

  #elsif ($card_type eq "mc") {
  #  # group 37 mastercard misc
  #  $group[37] = '001' . $xxxx;
  #}
  elsif ( ( $commcardtype ne "" ) && ( $capabilities =~ /ax/ ) && ( $card_type eq "ax" ) ) {    # ax purchase card data only sent if merch is setup at Tsys for it and it's required by ax
                                                                                                # group 39 ax capn corporate purchase cards
                                                                                                # ax purchase card data only sent if merch is setup at Tsys for it and it's required by ax
    my $requester   = " " x 38;                                                                 # requester name  38a 4.223
    my $totaltax    = substr( "0" x 12 . $tax, -12, 12 );                                       # 12n 4.276
    my $taxtypecode = "056";                                                                    # 3n 4.262
    $group[39] = $requester . $totaltax . $taxtypecode;
  } elsif ( $card_type eq "ds" ) {

    # group 40 discover misc
    if ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $transflags !~ /moto/ ) ) {
      $posdevattend    = "0";
      $poscardpres     = "0";
      $poscardinputcap = "7";
    } else {
      $posdevattend    = "1";
      $poscardpres     = "1";
      $poscardinputcap = "U";
    }

    if ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $transflags !~ /moto/ ) ) {
      $posdevloc         = "0";
      $poscardholderpres = "0";
    } elsif ( $origoperation eq "forceauth" ) {
      $posdevloc         = "3";
      $poscardholderpres = "1";
    } elsif ( $transflags =~ /recurring/ ) {
      $posdevloc         = "2";
      $poscardholderpres = "4";
    } elsif ( $transflags =~ /moto/ ) {
      $posdevloc         = "2";
      $poscardholderpres = "3";
    } else {
      $posdevloc         = "2";
      $poscardholderpres = "5";
    }
    if ( $transflags =~ /partial/ ) {
      $partial = "1";
    } else {
      $partial = "0";
    }
    $poscardcap = "1";
    if ( $origoperation eq "forceauth" ) {
      $postransstatus = "0";
    } else {
      $postransstatus = "0";
    }
    $postranssecurity = "9";
    $partshipind      = "N";

    $group[40] = '001' . $posdevattend . $partial . $posdevloc . $poscardholderpres . $poscardpres . $poscardcap . $postransstatus . $postranssecurity . '00' . $poscardinputcap . '00' . $partshipind;
    print "group40: $group[40]\n";
  }

  print "aaaa $card_type aaaa\n";
  my $tags = "";

  $iiasind = substr( $auth_code, 150, 1 );
  $iiasind =~ s/ //g;
  if ( ( $card_type eq "mc" ) && ( $transflags =~ /hsa/ ) && ( $iiasind ne "" ) ) {
    $tags .= "IIA01$iiasind";
  }

  if ( $card_type eq "vi" ) {
    my $sqi = substr( $auth_code, 163, 1 );
    my $tmpstr = unpack "H*", $sqi;
    print "sqi: $tmpstr aa\n";
    $sqi = substr( $sqi . " ", 0, 1 );
    my $tmpstr = unpack "H*", $sqi;
    print "sqi: $tmpstr bb\n";
    $tags .= "SQI01$sqi";
    print "tags: $tags aa\n";
  }
  if ( $commcardtype ne "" ) {
    if ( $card_type eq "mc" ) {
      if ( $ponumber ne "" ) {
        $purchaseid = substr( $ponumber . " " x 25, 0, 25 );
      } else {
        $purchaseid = substr( $orderid, -25, 25 );
        $purchaseid = substr( $purchaseid . " " x 25, 0, 25 );
      }
      if ( $tax > 0 ) {
        $optamtid = '1';     # optional amount identifier (1a)
        $optamt   = $tax;    # optional amount (12n)
      } elsif ( ( $transflags =~ /exempt/ ) && ( $transflags !~ /notexempt/ ) ) {
        $optamtid = '2';         # optional amount identifier (1a)
        $optamt   = '0' x 12;    # optional amount (12n)
      } else {
        $optamtid = '0';         # optional amount identifier (1a)
        $optamt   = '0' x 12;    # optional amount (12n)
      }
      $tags .= "OAI01$optamtid" . "OA 12$optamt" . "PON25$purchaseid";

      #$group[41] = "0057" . "OAI01$optamtid" . "OA 12$optamt" . "PON25$purchaseid";
    }
  }

  my $devtype = substr( $auth_code, 181, 4 );
  $devtype =~ s/ //g;
  if ( ( $card_type eq "mc" ) && ( $transflags =~ /ctls/ ) ) {
    $devtype = substr( "00" . $devtype, -2, 2 );
    $tags .= "MDE02$devtype";
  }

  print "tags: $tags\n";
  if ( $tags ne "" ) {
    my $taglen = length($tags) + 4;
    $taglen = substr( "0000" . $taglen, -4, 4 );
    $group[41] = $taglen . $tags;
  }
  print "group41: $group[41]\n";

  print "origbd5: $bd[5]\n";
  ( $mainbitmap, $group[23] ) = &gengroupbitmap(@group);
  $bd[5] = 'D' . $mainbitmap;
  print "newbd5: $bd[5]\n";

  $recseqnum = substr( "0000" . $recseqnum, -4, 4 );
  $errorderid{$recseqnum} = $orderid;

  $message = "";
  foreach $var (@bd) {
    $message = $message . $var;
  }
  foreach $var (@group) {
    if ( $var ne "" ) {
      print "group: $var\n";
    }
    $message = $message . $var;
  }
  $etb = pack "H2", "17";       # etb
  $message = $message . $etb;

  &sendrecord($message);

  if ( $usevnetsslflag == 0 ) {
    if ( $response =~ /\x02.+RB/ ) {
      &sslsend();
      $errorflag = 1;
    } elsif ( ( length($response) != 1 ) || ( $response !~ /^(\x05|\x06|\x07)$/ ) ) {
      &error("detail");
    }
  }

  my $emvtagschk = substr( $auth_code, 203, 224 );
  $emvtagschk =~ s/ //g;
  if ( ( $transflags =~ /emv/ ) && length( $emvtagschk > 20 ) ) {

    # chip card addendum record
    $recseqnum++;

    @bd = ();
    $bd[0] = pack "H2", "02";    # stx
    $bd[1] = 'K';                # record format (1a)
    $bd[2] = '1';                # application type 0 = single, 4 = multiple interleaved(1a)
    $bd[3] = '.';                # message delimiter (1a)
    $bd[4] = 'Z';                # X.25 Routing ID (1a)
    if ( $operation eq "postauth" ) {
      $bd[5] = 'C@@@A';          # record type (5a) includes group 1
    } else {
      $bd[5] = 'C@@@@';          # record type (5a)
    }

    $emvtags      = substr( $auth_code, 203, 224 );
    $cryptoamount = substr( $auth_code, 427, 12 );
    if ( length($cryptoamount) < 12 ) {
      $cryptoamount = substr( $acct_code4, 0, 12 );
    }

    #print "auth_code: $auth_code\n";
    #print "emvtags: $emvtags\n";
    #print "cryptoamount: $cryptoamount\n";
    #exit;
    $bd[16] = $emvtags;

    #$bd[16] = $yyyy;              # 9c transaction type (2a)
    #$bd[16] = $yyyy;              # 9a terminal transaction date (6a) YYMMDD
    #$bd[17] = $yyyy;              # 95 terminal verification results tvr (10a)
    #$bd[17] = $yyyy;              # 9f1a or 5f2a terminal currency code (3a)
    #$bd[17] = $yyyy;              # 9f36 application transaction counter (4a)
    #$bd[17] = $yyyy;              # 82 application interchange profile (4a)
    #$bd[17] = $yyyy;              # 9f26 application cryptogram (16a)
    #$bd[17] = $yyyy;              # 9f37 unpredictable number (8a)
    #$bd[17] = $yyyy;              # 9f10 issuer application data(64a)
    #$bd[17] = $yyyy;              # 9f27 cryptogram information data (2a)
    #$bd[17] = $yyyy;              # 9f33 terminal capability profile (6a)
    #$bd[17] = $yyyy;              # 5f34 card sequence number (3a)
    #$bd[17] = $yyyy;              # 91 issuer authentication data (32a)
    #$bd[17] = $yyyy;              # in 9f10 cvm results (6a)
    #$bd[17] = $yyyy;              # 71 and 72 issuer script results (50a)
    #$bd[17] = $yyyy;              # 9f6e form factor identifier (8a)

    my @group = ();
    if ( $operation eq "postauth" ) {
      $group[1] = $cryptoamount;    # cryptogram amount (12)
    }

    $recseqnum = substr( "0000" . $recseqnum, -4, 4 );
    $errorderid{$recseqnum} = $orderid;

    $message = "";
    foreach $var (@bd) {
      $message = $message . $var;
    }
    foreach $var (@group) {
      if ( $var ne "" ) {
        print "group: $var\n";
      }
      $message = $message . $var;
    }
    $etb = pack "H2", "17";       # etb
    $message = $message . $etb;

    &sendrecord($message);

    if ( $usevnetsslflag == 0 ) {
      if ( $response =~ /\x02.+RB/ ) {
        &sslsend();
        $errorflag = 1;
      } elsif ( ( length($response) != 1 ) || ( $response !~ /^(\x05|\x06|\x07)$/ ) ) {
        &error("detail");
      }
    }
  }

}

sub batchtrailer {
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

  @bt = ();
  $bt[0] = pack "H2", "02";    # stx
  $bt[1] = 'K';                # record format (1a)
  $bt[2] = '1';                # application type 0 = single, 4 = multiple interleaved(1a)
  $bt[3] = '.';                # message delimiter (1a)
  $bt[4] = 'Z';                # X.25 Routing ID (1a)
  $bt[5] = 'T@@@@';            # record type (5a)
  $bdate = substr( $today, 4, 4 );
  $bt[6] = $bdate;             # batch trans date (4n)
  $batchnum = substr( "0" x 3 . $batchnum, -3, 3 );
  $bt[7] = $batchnum;          # batch number (3n)
  $recseqnum = substr( "0" x 9 . $recseqnum, -9, 9 );
  $bt[8] = $recseqnum;         # batch record count (9n)
  $hashtotal = sprintf( "%d", $hashtotal + .0001 );
  $hashtotal = substr( "0" x 16 . $hashtotal, -16, 16 );
  $bt[9] = $hashtotal;         # batch hashing total (16n)
  $cashbacktotal = substr( "0" x 16 . $cashbacktotal, -16, 16 );
  $bt[10] = $cashbacktotal;    # cashback total (16n)

  if ( $netamount < 0 ) {
    $netamount = 0 - $netamount;
  }
  $netamount = sprintf( "%d", $netamount + .0001 );
  $netamount = substr( "0" x 16 . $netamount, -16, 16 );
  $bt[11] = $netamount;         # batch net depost (16n)
  $bt[12] = pack "H2", "03";    # stx

  $message = "";
  foreach $var (@bt) {
    $message = $message . $var;
  }
  &sendrecord($message);
}

sub sendrecord {
  ($message) = @_;

  print "\n";

  $rlen     = length($message);
  $message2 = $message;
  $cardnumber =~ s/ //g;
  $cnumlen = length($cardnumber);
  if ( ( $cnumlen >= 13 ) && ( $cnumlen <= 19 ) ) {
    $xs = "x" x $cnumlen;
    $message2 =~ s/$cardnumber/$xs/;
  }
  $message2 =~ s/\x1c/\[1c\]/g;
  $message2 =~ s/\x02/\[STX\]/g;
  $message2 =~ s/\x17/\[ETB\]/g;
  $message2 =~ s/\x03/\[ETX\]/g;
  my $mytime = gmtime( time() );
  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
  print logfile "$mytime send: $rlen $message2  $orderid\n";
  print "send: $rlen $message2\n";
  close(logfile);

  # do the parity thing
  $mess = "";
  $lrc  = "";
  $len  = length($message);
  for ( $i = 0 ; $i < $len ; $i++ ) {
    $byte = substr( $message, $i, 2 );
    $setbits = unpack( "%8b8", $byte );
    $byte = unpack "H2", $byte;
    $byte = hex($byte);

    $setbits    = ( $setbits % 2 ) * 128;
    $newmessage = $byte + $setbits;

    $mess2 = sprintf( "%02X", $newmessage );

    $mess = $mess . $mess2;

    if ( $i != 0 ) {
      $lbin = pack "H2", $mess2;
      $lrc  = $lbin ^ $lrc;
      $temp = unpack "H*", $lrc;

      #print "lrc: $temp\n";
    }
  }

  #print "$mess\n";
  $message = pack "H*", $mess;
  $message = $message . $lrc;

  $bigmessage = $bigmessage . $message;

  if ( $usevnetsslflag == 0 ) {
    print "socketwrite\n";
    &socketwrite($message);
  }

  return;
}

sub printrecord {
  my ($printmessage) = @_;

  $temp = length($printmessage);
  print "$temp\n";
  ($message2) = unpack "H*", $printmessage;
  print "$message2\n\n";

  $message1 = $printmessage;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;

  #print "$message1\n$message2\n\n";
}

sub sslsend {
  $message = $bigmessage;
  if ( $usevnetsslflag == 1 ) {
    &vnetsslsend();
  } else {
    close(SOCK);
    print "socketclose\n";
  }

  $index = index( $response, "\x02" );
  if ( $index > 0 ) {
    $extradata = substr( $response, 0, $index );
    $temp = unpack "H*", $extradata;
    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
    print logfile "extra data: $temp\n";
    close(logfile);
  }
  $response = substr( $response, $index );

  $errorflag = 0;
  ( $d1, $recordformat, $apptype, $d2, $routingid, $recordtype, $batchreccnt, $batchnetdep, $respcode, $d3, $batchnum ) = unpack "H2A1A1A1A1A5A9A16A2A2A3", $response;

  $resp = substr( $response, 42 );

  #print "d1   $d1\n";
  #print "recordformat   $recordformat\n";
  #print "apptype   $apptype\n";
  #print "d2   $d2\n";
  #print "routingid   $routingid\n";
  #print "recordtype   $recordtype\n";
  #print "batchreccnt   $batchreccnt\n";
  #print "batchnetdep   $batchnetdep\n";
  print "respcode   $respcode\n";

  #print "d3   $d3\n";
  print "batchnum   $batchnum\n";

  if ( $respcode eq "GB" ) {
    ( $resptext, $d1 ) = unpack "A9A16", $resp;
    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
    print logfile "resptext   $resptext\n";
    print logfile "d1   $d1\n";
    print "resptext   $resptext\n";
    print "d1   $d1\n";
    close(logfile);

    ( $d1, $ptoday, $ptime ) = &miscutils::genorderid();

    $mytime = gmtime( time() );
    print "$mytime before update trans_log\n";

    my $sthpass = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='success',trans_time=?
	    where trans_date>='$onemonthsago'
            and trans_date<='$today'
	    and username='$username'
	    and result='$time$batchnum'
	    and finalstatus='locked'
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpass->execute("$ptime") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpass->finish;

    $hint = "/*+ INDEX(OPLOG_OPTIMEUN_IDX) */";

    #if ($username eq "friendfind7") {
    $usetransdate = $postauthtrans_date;

    #}
    #else {
    #  $usetransdate = $mintrans_date;
    #}

    $mytime = gmtime( time() );
    print "$mytime after update trans_log\n";
    open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
    print logfile "$mytime after update trans_log\n";
    print logfile "using trans_date $usetransdate\n";
    close(logfile);

    #where trans_date>='$mintrans_date'
    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop1 = $dbh2->prepare(
      qq{
            update $hint operation_log set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
            where trans_date>='$usetransdate'
            and trans_date<='$today'
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop1->execute( "$ptime", "$ptime" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop1->finish;

    $mytime = gmtime( time() );
    print "$mytime after update operation_log postauth\n";
    open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
    print logfile "$mytime after update operation_log postauth\n";
    close(logfile);

    if ( $returnsincluded == 1 ) {
      %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
      if ( $username eq "friendfind7" ) {
        my $sthop = $dbh2->prepare(
          qq{
            update operation_log set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
            where lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sthop->execute( "$ptime", "$ptime" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sthop->finish;
      } else {
        my $sthop = $dbh2->prepare(
          qq{
            update operation_log set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
            where trans_date>='$mintrans_date'
            and trans_date<='$today'
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sthop->execute( "$ptime", "$ptime" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sthop->finish;
      }

      $mytime = gmtime( time() );
      print "$mytime after update operation_log\n";
      open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
      print logfile "$mytime after update operation_log return\n";
      close(logfile);
    } else {
      $mytime = gmtime( time() );
      print "$mytime no returns in batch, update operation_log return not done\n";
      open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
      print logfile "$mytime no returns in batch, update operation_log return not done\n";
      close(logfile);
    }

    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
    print logfile "$mytime\n";
    close(logfile);

  } elsif ( $respcode eq "RB" ) {
    ( $errortype, $errorrecseqnum, $errorrectype, $errordatafieldnum, $errordata ) = unpack "A1A4A1A2A30", $resp;

    $errordata =~ s/\x03./\[ETX\]/g;

    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
    print logfile "orderid   $errorderid{$errorrecseqnum}\n";
    print logfile "errortype   $errortype\n";
    print logfile "errorrecseqnum   $errorrecseqnum\n";
    print logfile "errorrectype   $errorrectype\n";
    print logfile "errordatafieldnum   $errordatafieldnum\n";
    print logfile "errordata   $errordata\n";
    print "orderid   $errorderid{$errorrecseqnum}\n";
    print "errortype   $errortype\n";
    print "errorrecseqnum   $errorrecseqnum\n";
    print "errorrectype   $errorrectype\n";
    print "errordatafieldnum   $errordatafieldnum\n";
    print "errordata   $errordata\n";
    close(logfile);

    if ( $errordata =~ /(AMEX|DISC)/ ) {
      $dontallowamexflag = 1;
      $dontallowdiscflag = 1;
    }

    if ( $errordata =~ /^ZH/ ) {
      $errorcnt{$username}++;
    }

    if ( ( $errortype eq "S" ) && ( $errorrectype eq "X" ) ) {
      if ( $username ne "$usernameold" ) {
        if ( $firstredo == 0 ) {
          $redobatch = 1;
          $firstredo = 1;
          umask 0077;
          open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
          print logfile "redo batch\n\n";
          close(logfile);
        }
      }
      $usernameold = $username;
    } else {
      my $sthfail = $dbh2->prepare(
        qq{
            update trans_log set finalstatus='problem',descr=?
	    where orderid='$errorderid{$errorrecseqnum}'
	    and username='$username'
	    and trans_date>='$onemonthsago'
	    and result='$time$batchnum'
            and (accttype is NULL or accttype='' or accttype='credit')
	    and finalstatus='locked'
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthfail->execute("$errorrecseqnum, $errorrectype, $errordatafieldnum, $errordata") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthfail->finish;

      %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $sthop1 = $dbh2->prepare(
        qq{
            update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?
            where orderid='$errorderid{$errorrecseqnum}'
            and username='$username'
            and batchfile='$time$batchnum'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthop1->execute("$errorrecseqnum, $errorrectype, $errordatafieldnum, $errordata") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthop1->finish;

      %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $sthop = $dbh2->prepare(
        qq{
            update operation_log set returnstatus='problem',lastopstatus='problem',descr=?
            where orderid='$errorderid{$errorrecseqnum}'
            and username='$username'
            and batchfile='$time$batchnum'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthop->execute("$errorrecseqnum, $errorrectype, $errordatafieldnum, $errordata") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthop->finish;

    }

    my $sthpending = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='pending'
	    where trans_date>='$onemonthsago'
            and trans_date<='$today'
	    and username='$username'
	    and result='$time$batchnum'
	    and finalstatus='locked'
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpending->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpending->finish;

    my $sthop1 = $dbh2->prepare(
      qq{
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where trans_date>='$mintrans_date'
            and trans_date<='$today'
        and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop1->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop1->finish;

    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where trans_date>='$mintrans_date'
            and trans_date<='$today'
        and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dprice\@plugnpay.com\n";
    print MAILERR "Cc: barbara\@plugnpay.com\n";
    print MAILERR "Cc: michelle\@plugnpay.com\n";
    print MAILERR "Subject: visanetemv - RB INV DATA\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $time\n";
    print MAILERR "file: $username$time$pid.txt\n\n";
    print MAILERR "orderid: $errorderid{$errorrecseqnum}\n";
    print MAILERR "errorrecseqnum: $errorrecseqnum\n";
    print MAILERR "errorrectype: $errorrectype\n";
    print MAILERR "errordatafieldnum: $errordatafieldnum\n";
    print MAILERR "errordata: $errordata\n";
    close MAILERR;
  } elsif ( $respcode eq "DB" ) {
    ( $batchtransdate, $d4 ) = unpack "A4A21", $resp;
    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
    print logfile "batchtransdate   $batchtransdate\n";
    print logfile "d4   $d4\n";
    print "batchtransdate   $batchtransdate\n";
    print "d4   $d4\n";
    close(logfile);

    my $sthfail = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='problem',descr=?
	    where trans_date>='$onemonthsago'
            and trans_date<='$today'
	    and username='$username'
	    and result='$time$batchnum'
	    and finalstatus='locked'
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthfail->execute("Duplicate Batch: $batchtransdate") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthfail->finish;

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop1 = $dbh2->prepare(
      qq{
            update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?
            where trans_date>='$mintrans_date'
            and trans_date<='$today'
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop1->execute("Duplicate Batch: $batchtransdate") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop1->finish;

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set returnstatus='problem',lastopstatus='problem',descr=?
            where trans_date>='$mintrans_date'
            and trans_date<='$today'
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute("Duplicate Batch: $batchtransdate") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dprice\@plugnpay.com\n";
    print MAILERR "Subject: visanetemv - duplicate batch\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: duplicate batch\n\n";
    print MAILERR "batchtransdate: $batchtransdate\n";
    close MAILERR;
  } elsif ( $response =~ /^failure/ ) {

    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
    print logfile "orderid   $errorderid{$errorrecseqnum}\n";
    print logfile "error   $response\n";
    close(logfile);

    my $sthpending = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='pending'
	    where trans_date>='$onemonthsago'
            and trans_date<='$today'
	    and username='$username'
	    and result='$time$batchnum'
	    and finalstatus='locked'
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpending->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpending->finish;

    my $sthop1 = $dbh2->prepare(
      qq{
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where trans_date>='$mintrans_date'
            and trans_date<='$today'
        and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop1->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop1->finish;

    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where trans_date>='$mintrans_date'
            and trans_date<='$today'
        and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dprice\@plugnpay.com\n";
    print MAILERR "Subject: visanetemv - vnetssl no response\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $time\n";
    print MAILERR "file: $username$time$pid.txt\n\n";
    print MAILERR "orderid: $errorderid{$errorrecseqnum}\n";
    print MAILERR "error: $response\n";
    close MAILERR;

    exit;
  } else {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dprice\@plugnpay.com\n";
    print MAILERR "Subject: visanetemv - unkown error\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $resp\n";
    print MAILERR "file: $username$time$pid.txt\n";
    close MAILERR;
  }

}

sub errorchecking {
  if ( ( $username =~ /^(golinte1|homeclip|pocketbr)$/ ) && ( $cardnumber =~ /^3/ ) ) {
    return 1;
  }
  if ( $enclength > 1024 ) {
    &errormsg( $username, $orderid, $operation, 'could not decrypt' );
    return 1;
  }
  $temp = substr( $amount, 4 );
  if ( $temp == 0 ) {
    &errormsg( $username, $orderid, $operation, 'amount = 0.00' );
    return 1;
  }

  if ( $cardnumber eq "411111111111111" ) {
    &errormsg( $username, $orderid, $operation, 'test card number' );
    return 1;
  }

  $clen = length($cardnumber);
  $cabbrev = substr( $cardnumber, 0, 4 );
  if ( $card_type eq "" ) {
    print "$cardnumber\n";
    &errormsg( $username, $orderid, $operation, 'bad card number' );
    return 1;
  }
  return 0;
}

sub error {
  my ($group) = @_;

  if ( $group =~ /^(header|parameter)$/ ) {
    $merchanterrorflag = 1;
  } else {

    my $sthpending = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='pending'
	    where trans_date>='$onemonthsago'
            and trans_date<='$today'
	    and username='$username'
	    and result='$time$batchnum'
	    and finalstatus='locked'
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpending->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpending->finish;

    my $sthop1 = $dbh2->prepare(
      qq{
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where trans_date>='$mintrans_date'
            and trans_date<='$today'
        and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop1->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop1->finish;

    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where trans_date>='$mintrans_date'
            and trans_date<='$today'
        and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;
  }

  $errorflag = 1;

  close(SOCK);
  print "socketclose\n";
}

sub errormsg {
  my ( $username, $orderid, $operation, $errmsg ) = @_;

  my $sthtest = $dbh2->prepare(
    qq{
            update trans_log set finalstatus='problem',descr=?
            where orderid='$orderid'
            and username='$username'
            and trans_date>='$onemonthsago'
            and finalstatus='pending'
            and (accttype is NULL or accttype='' or accttype='credit')
            }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthtest->execute("$errmsg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthtest->finish;

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";
  %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
  my $sthop = $dbh2->prepare(
    qq{
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid='$orderid'
            and username='$username'
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
            }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthop->execute("$errmsg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthop->finish;

}

sub socketopen {
  ( $addr, $port ) = @_;
  print "aaaa: $addr  $port\n";

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) or die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) or die "socket: $!";

  my $host     = "processor-host";
  my $iaddr    = inet_aton($host);
  my $sockaddr = sockaddr_in( 0, $iaddr );
  bind( SOCK, $sockaddr ) || die "bind: $!\n";

  connect( SOCK, $paddr ) or die "connect: $!";
}

sub socketwrite {
  $temp = unpack "H*", $message;
  print "send: $temp\n";

  send( SOCK, $message, 0, $paddr );
  recv( SOCK, $respenc, 2048, 0 );

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
  $temp = unpack "H*", $respenc;
  print "recvc: $temp\n";
  print logfile "recvc: $temp\n";
  close(logfile);

  if ( $respenc eq "\x05" ) {
    recv( SOCK, $respenc, 2048, 0 );

    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
    $temp = unpack "H*", $respenc;
    print "recvg: $temp\n";
    print logfile "recvg: $temp\n";
    close(logfile);
  }

  if ( $endbatchflag == 1 ) {
    my $i = 0;
    while ( ( $respenc =~ /(\x12|\x05|\x06)$/ ) && ( length($respenc) < 15 ) ) {
      select undef, undef, undef, 4.0;
      recv( SOCK, $respenc, 2048, 0 );

      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
      $temp = unpack "H*", $respenc;
      print "recvd: $temp\n";
      print logfile "recvd: $temp\n";
      close(logfile);
      $i++;
      if ( $i >= 10 ) {
        last;
      }
    }
  } else {
    my $i = 0;
    while ( $respenc eq "\x12" ) {
      select undef, undef, undef, 4.0;
      recv( SOCK, $respenc, 2048, 0 );

      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
      $temp = unpack "H*", $respenc;
      print "recve: $temp\n";
      print logfile "recve: $temp\n";
      close(logfile);
      $i++;
      if ( $i >= 10 ) {
        last;
      }
    }
  }

  $respdec = "";
  $rlen    = length($respenc);
  print "len2: $rlen\n";
  for ( $i = 0 ; $i < $rlen ; $i++ ) {
    $resp1   = substr( $respenc, $i, 1 );
    $newresp = $resp1 & "\x7f";
    $respdec = $respdec . $newresp;
  }
  $response = $respdec;

  $message2 = $response;
  $message2 =~ s/\x1c/\[1c\]/g;
  $message2 =~ s/\x02/\[STX\]/g;
  $message2 =~ s/\x17/\[ETB\]/g;
  $message2 =~ s/\x03/\[ETX\]/g;
  $rlen = length($response);
  if ( $rlen == 1 ) {
    $message2 = unpack "H*", $message2;
  } else {
    $message2 = substr( $message2, 0, -1 );
  }
  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
  print logfile "recv: $rlen $message2\n";
  print "recv: $rlen $message2\n";
  close(logfile);

  return;

  print "read socket $message\n";
  vec( $rin, $temp = fileno(S), 1 ) = 1;
  $count   = 2;
  $respenc = "";
  print "waiting for recv...\n";
  while ( $count && select( $rout = $rin, undef, undef, 10.0 ) ) {
    recv( SOCK, $got, 2048, 0 );
    $respenc = $respenc . $got;

    #if ($respenc =~ /\x03/) {
    last;

    #}
    $count--;
  }

  print "done waiting\n";
  $temp = unpack "H*", $respenc;
  print "recva: $temp\n";

  #return($response);
}

sub vnetsslsend {
  $msg      = $bigmessage;
  $message  = $bigmessage;
  $response = "";

  Net::SSLeay::load_error_strings();
  Net::SSLeay::SSLeay_add_ssl_algorithms();
  Net::SSLeay::randomize('/etc/passwd');

  #($dest_serv, $port, $msg) = @ARGV;      # Read command line
  #$site = "ssl1.tsysacquiring.net";		# production
  #$dest_serv = "ssl1.tsysacquiring.net";

  $site      = "ssltest.tsysacquiring.net";    # test
  $dest_serv = "ssltest.tsysacquiring.net";

  #$site = "209.154.200.213";
  #$dest_serv = "209.154.200.213";
  #$site = "209.154.200.218";
  #$dest_serv = "209.154.200.218";
  $port = "443";

  my $path = "/scripts/gateway.dll\?transact";
  my $len  = length($msg);

  my $postLink = "https://" . $site . ":$port" . $path;

  my $rl = new PlugNPay::ResponseLink( 'processor_visanetemv', $postLink, $msg, 'post', 'meta' );
  $rl->setRequestContentType('x-Visa-II/x-settle');
  $rl->addRequestHeader( 'Accept',         '*/*\r\n' );
  $rl->addRequestHeader( 'Host',           "$site:$port" );
  $rl->addRequestHeader( 'Content-Length', $len );

  $rl->doAPIRequest();

  my $response = $rl->getResponseContent;
  my %headers  = $rl->getResponseHeaders;

  my $headerstr = "";
  foreach my $key ( sort keys %headers ) {
    $headerstr = $headerstr . $key . ": " . $headers{"$key"} . "\r\n";
  }

  $respenc = $headerstr . "\r\n" . $response;

  $respdec = "";
  my $rlen = length($respenc);
  for ( $i = 0 ; $i < $rlen ; $i++ ) {
    $resp1   = substr( $respenc, $i, 1 );
    $newresp = $resp1 & "\x7f";
    $respdec = $respdec . $newresp;
  }
  $response = $respdec;

  my $head1;
  ( $head1, $response ) = split( /\r\n\r\n/, $response );

  $message2 = $response;
  $message2 =~ s/\x1c/\[1c\]/g;
  $message2 =~ s/\x02/\[STX\]/g;
  $message2 =~ s/\x17/\[ETB\]/g;
  $message2 =~ s/\x03/\[ETX\]/g;
  $rlen = length($response);
  if ( $rlen == 1 ) {
    $message2 = unpack "H*", $message2;
  } else {
    $message2 = substr( $message2, 0, -1 );
  }
  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
  print logfile "recv: $rlen $message2\n";
  print "recv: $rlen $message2\n";
  close(logfile);
  exit;

  #if ($head1 =~ /x-data\/xact-error/) {
  #  $result{'MStatus'} = "problem";
  #  $result{'FinalStatus'} = "problem";
  #  $rmessage = "$response";
  #  return;
  #}

  #if ($response eq "") {
  #  $result{'MStatus'} = "problem";
  #  $result{'FinalStatus'} = "problem";
  #  $rmessage = "b: Processor did not respond in a timely manner.";
  #  return;
  #}

}

sub vnetsslsendold {
  $msg      = $bigmessage;
  $message  = $bigmessage;
  $response = "";

  Net::SSLeay::load_error_strings();
  Net::SSLeay::SSLeay_add_ssl_algorithms();
  Net::SSLeay::randomize('/etc/passwd');

  #($dest_serv, $port, $msg) = @ARGV;      # Read command line
  #$site = "ssl1.tsysacquiring.net";		# production
  #$dest_serv = "ssl1.tsysacquiring.net";

  $site      = "ssltest.tsysacquiring.net";    # test
  $dest_serv = "ssltest.tsysacquiring.net";

  #$site = "209.154.200.213";
  #$dest_serv = "209.154.200.213";
  #$site = "209.154.200.218";
  #$dest_serv = "209.154.200.218";
  $port = "443";
  $msg  = "$message";

  my $len = length($msg);

  my $req = "POST /scripts/gateway.dll\?transact HTTP/1.0\r\n";
  $req = $req . "Host: $site:443\r\n";
  $req = $req . "Accept: */*\r\n";
  $req = $req . "Content-Type: x-Visa-II/x-settle\r\n";
  $req = $req . "Content-Length: $len\r\n\r\n";
  $req = $req . "$message";

  print "aaaa $dest_serv  $port\n";
  $dest_ip = gethostbyname($dest_serv);
  print "bbbb $dest_ip\n";
  $dest_serv_params = sockaddr_in( $port, $dest_ip );
  print "cccc\n";

  $flag = "success";
  socket( S, &AF_INET, &SOCK_STREAM, 0 ) or return ( &errmssg( "failure socket: $!", 1 ) );
  print "dddd\n";

  my $host     = "processor-host";
  my $iaddr    = inet_aton($host);
  my $sockaddr = sockaddr_in( 0, $iaddr );
  bind( S, $sockaddr ) || die "bind: $!\n";
  print "eeee\n";

  connect( S, $dest_serv_params ) or $flag = &retry();
  print "ffff\n";
  if ( $flag ne "success" ) {
    return "failure connect: $!";
  }
  select(S);
  $| = 1;
  select(STDOUT);    # Eliminate STDIO buffering
  print "gggg\n";

  # The network connection is now open, lets fire up SSL
  $ctx = Net::SSLeay::CTX_new() or die_now("Failed to create SSL_CTX $!");
  Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL )
    and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
  $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
  Net::SSLeay::set_fd( $ssl, fileno(S) );    # Must use fileno
  $res = Net::SSLeay::connect($ssl) or return "failure sslconnect: $!";

  #$res = Net::SSLeay::connect($ssl) and Net::SSLeay::die_if_ssl_error("ssl connect");

  umask 0077;
  open( TMPFILE, ">>/home/p/pay1/logfiles/ciphers.txt" );
  print TMPFILE __FILE__ . ": " . Net::SSLeay::get_cipher($ssl) . "\n";
  close(TMPFILE);

  print "eeee before write\n";

  # Exchange data
  $res = Net::SSLeay::ssl_write_all( $ssl, $req );    # Perl knows how long $msg is
  print "ffff after write\n";
  Net::SSLeay::die_if_ssl_error("ssl write");

  #shutdown S, 1;  # Half close --> No more output, sends EOF to server

  $respenc = "";

  my ( $rin, $rout, $temp );
  vec( $rin, $temp = fileno(S), 1 ) = 1;
  $count = 8;
  while ( $count && select( $rout = $rin, undef, undef, 60.0 ) ) {

    #$respenc = Net::SSLeay::ssl_read_all($ssl);         # Perl returns undef on failure
    $got     = Net::SSLeay::read($ssl);    # Perl returns undef on failure
                                           #umask 0011;
                                           #open(tmpfile,">>/home/p/pay1/batchfiles/visanetemv/bserverlogmsg.txt");
                                           #print tmpfile "$mytime got: $len $got\n";
                                           #close(tmpfile);
    $respenc = $respenc . $got;
    if ( $respenc =~ /\x03/ ) {
      last;
    }
    Net::SSLeay::die_if_ssl_error("ssl read");
    $count--;
  }
  if ( $count == 1 ) {
    return "no response";
  }
  Net::SSLeay::free($ssl);                 # Tear down connection
  Net::SSLeay::CTX_free($ctx);
  close S;

  $respdec = "";
  my $rlen = length($respenc);
  for ( $i = 0 ; $i < $rlen ; $i++ ) {
    $resp1   = substr( $respenc, $i, 1 );
    $newresp = $resp1 & "\x7f";
    $respdec = $respdec . $newresp;
  }
  $response = $respdec;

  my $head1;
  ( $head1, $response ) = split( /\r\n\r\n/, $response );

  $message2 = $response;
  $message2 =~ s/\x1c/\[1c\]/g;
  $message2 =~ s/\x02/\[STX\]/g;
  $message2 =~ s/\x17/\[ETB\]/g;
  $message2 =~ s/\x03/\[ETX\]/g;
  $rlen = length($response);
  if ( $rlen == 1 ) {
    $message2 = unpack "H*", $message2;
  } else {
    $message2 = substr( $message2, 0, -1 );
  }
  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/visanetemv/logs/$fileyear/$username$time$pid.txt" );
  print logfile "recv: $rlen $message2\n";
  print "recv: $rlen $message2\n";
  close(logfile);

  #if ($head1 =~ /x-data\/xact-error/) {
  #  $result{'MStatus'} = "problem";
  #  $result{'FinalStatus'} = "problem";
  #  $rmessage = "$response";
  #  return;
  #}

  #if ($response eq "") {
  #  $result{'MStatus'} = "problem";
  #  $result{'FinalStatus'} = "problem";
  #  $rmessage = "b: Processor did not respond in a timely manner.";
  #  return;
  #}

}

sub retry {
  socket( S, &AF_INET, &SOCK_STREAM, 0 ) or return ( &errmssg( "socket: $!", 1 ) );

  my $iaddr = inet_aton($host);
  my $sockaddr = sockaddr_in( 0, $iaddr );
  bind( S, $sockaddr ) || die "bind: $!\n";

  connect( S, $dest_serv_params ) or return ( &errmssg( "connect: $!", 1 ) );

  return "success";
}

sub errmssg {
  my ( $mssg, $level ) = @_;

  if ( $level != 1 ) {
    Net::SSLeay::free($ssl);    # Tear down connection
    Net::SSLeay::CTX_free($ctx);
  }
  close S;

  return $mssg;
}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  print "origtime: $origtime $timezone1\n";

  if ( length($origtime) != 14 ) {
    return $origtime;
  }

  # timezone  hours  week of month  day of week  month  time   hours  week of month  day of week  month  time
  %timezonearray = (
    'EST', '-4,2,0,3,02:00, -5,1,0,11,02:00',    # 4 hours starting 2nd Sunday in March at 2am, 5 hours starting 1st Sunday in November at 2am
    'CST', '-5,2,0,3,02:00, -6,1,0,11,02:00',    # 5 hours starting 2nd Sunday in March at 2am, 6 hours starting 1st Sunday in November at 2am
    'MST', '-6,2,0,3,02:00, -7,1,0,11,02:00',    # 6 hours starting 2nd Sunday in March at 2am, 7 hours starting 1st Sunday in November at 2am
    'PST', '-7,2,0,3,02:00, -8,1,0,11,02:00',    # 7 hours starting 2nd Sunday in March at 2am, 8 hours starting 1st Sunday in November at 2am
    'GMT', ''
  );

  if ( ( $timezone1 eq $timezone2 ) || ( ( $timezone1 ne "GMT" ) && ( $timezone2 ne "GMT" ) ) ) {
    return $origtime;
  } elsif ( $timezone1 eq "GMT" ) {
    $timezone = $timezone2;
  } else {
    $timezone = $timezone1;
  }

  if ( $timezonearray{$timezone} eq "" ) {
    return $origtime;
  }

  my ( $hours1, $times1, $wday1, $month1, $time1, $hours2, $times2, $wday2, $month2, $time2 ) = split( /,/, $timezonearray{$timezone} );

  my $origtimenum =
    timegm( substr( $origtime, 12, 2 ), substr( $origtime, 10, 2 ), substr( $origtime, 8, 2 ), substr( $origtime, 6, 2 ), substr( $origtime, 4, 2 ) - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $newtimenum = $origtimenum;
  if ( $timezone1 eq "GMT" ) {
    $newtimenum = $origtimenum + ( 3600 * $hours1 );
  }

  my $timenum = timegm( 0, 0, 0, 1, $month1 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month1 happens on wday $wday\n";

  if ( $wday1 < $wday ) {
    $wday1 = 7 + $wday1;
  }
  my $mday1 = ( 7 * ( $times1 - 1 ) ) + 1 + ( $wday1 - $wday );
  my $timenum1 = timegm( 0, substr( $time1, 3, 2 ), substr( $time1, 0, 2 ), $mday1, $month1 - 1, substr( $origtime, 0, 4 ) - 1900 );

  #print "time1: $time1\n\n";

  print "The $times1 Sunday of month $month1 happens on the $mday1\n";

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month2 happens on wday $wday\n";

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  print "The $times2 Sunday of month $month2 happens on the $mday2\n";

  #print "origtimenum: $origtimenum\n";
  #print "newtimenum:  $newtimenum\n";
  #print "timenum1:    $timenum1\n";
  #print "timenum2:    $timenum2\n";
  my $zoneadjust = "";
  if ( $dstflag == 0 ) {
    $zoneadjust = $hours1;
  } elsif ( ( $newtimenum >= $timenum1 ) && ( $newtimenum < $timenum2 ) ) {
    $zoneadjust = $hours1;
  } else {
    $zoneadjust = $hours2;
  }

  if ( $timezone1 ne "GMT" ) {
    $zoneadjust = -$zoneadjust;
  }

  print "zoneadjust: $zoneadjust\n";
  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  print "newtime: $newtime $timezone2\n\n";
  return $newtime;

}

sub gengroupbitmap {
  my (@msg) = @_;

  my $groupdataflag = 0;
  my $tempdata      = "";
  my $message       = "";
  my $tempstr       = "";
  my $bitmap1       = "";
  my $bitmap2       = "";
  my @bitmap        = ();

  my $bytenum = 7;
  for ( my $i = 48 ; $i >= 0 ; $i-- ) {
    if ( ( $i % 6 == 0 ) && ( $i != 48 ) ) {
      $tempdata = 64 + $tempdata;
      $tempdata = pack "C", $tempdata;

      #$tmpstr = unpack "H*", $tempdata;
      #print "tmpstr: $tempdata\n";
      #$tempdata = \x40 | $tempdata;
      $bitmap[$bytenum] = $tempdata;
      print "bitmap: $bytenum  $i  $tempdata\n";
      $tempdata = "";
      $bytenum--;
    } else {
      $tempdata = $tempdata << 1;

      #$tmpstr = unpack "H*", $tempdata;
      #print "tmpstr: $tempdata\n";
    }
    if ( $i <= 0 ) {
      last;
    }
    if ( $msg[$i] ne "" ) {
      print "$i\n";
      $tempdata = $tempdata | 1;
      if ( $i > 23 ) {
        $groupdataflag = 1;
      }
    }

    #$tempstr = pack "L", $tempdata;
    #$tempstr = unpack "H32", $tempstr;
  }

  if ( $groupdataflag == 1 ) {
    print "groupdataflag == 1\n";
    $tempdata = unpack "H2", $bitmap[3];
    $tempdata = $tempdata + 10;
    $bitmap[3] = pack "H2", $tempdata;
    print "bitmap3 $bitmap[3]\n";
    $bitmap1 = $bitmap[3] . $bitmap[2] . $bitmap[1] . $bitmap[0];
    $bitmap2 = $bitmap[7] . $bitmap[6] . $bitmap[5] . $bitmap[4];
  } else {
    $bitmap1 = $bitmap[3] . $bitmap[2] . $bitmap[1] . $bitmap[0];
    $bitmap2 = "";
  }

  print "mainbitmap: $bitmap1\n";
  print "groupbitmap: $bitmap2\n";

  return $bitmap1, $bitmap2;

}

