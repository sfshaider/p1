#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use rsautils;
use smpsutils;
use IO::Socket;
use Socket;
use Time::Local;
use MIME::Base64;

$devprod = "logs";

$altdestination = "";

# 2017 fall time change, to prevent genfiles from running twice
# exit if time is between 6am gmt and 7am gmt
my $timechange = "20171105020000";    # 2am eastern on the morning of the time change (1am to 1am to 2am)

my $str6am  = $timechange + 40000;                 # str represents 6am gmt
my $str7am  = $timechange + 50000;                 # str represents 7am gmt
my $time6am = &miscutils::strtotime("$str6am");    # 6am gmt
my $time7am = &miscutils::strtotime("$str7am");    # 7am gmt
my $now     = time();

if ( ( $now >= $time6am ) && ( $now < $time7am ) ) {
  print "exiting due to fall time change\n";
  exit;
}

my $group = $ARGV[0];
if ( $group eq "" ) {
  $group = "0";
}
print "group: $group\n";

# mercury batch cutoff time 03:00am

if ( ( -e "/home/p/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/p/pay1/batchfiles/$devprod/mercury/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'mercury/genfiles.pl $group'`;
if ( $cnt > 1 ) {
  print "genfiles.pl $group already running, exiting...\n";

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: mercury - genfiles $group already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl $group because it's already running.\n\n";
  close MAILERR;

  exit;
}

$time = time();
( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $d8, $d9, $modtime ) = stat "/home/p/pay1/batchfiles/$devprod/mercury/genfiles$group.txt";

$delta = $time - $modtime;

if ( $delta < ( 3600 * 12 ) ) {
  open( checkin, "/home/p/pay1/batchfiles/$devprod/mercury/genfiles$group.txt" );
  $checkuser = <checkin>;
  chop $checkuser;
  close(checkin);
}

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and username>='$checkuser'";
}

#$checkstring = " and username='aaaa'";
#$checkstring = " and username in ('aaaa','aaaa') ";

$mytime  = time();
$machine = `uname -n`;
$pid     = $$;

chop $machine;
open( outfile, ">/home/p/pay1/batchfiles/$devprod/mercury/pid$group.txt" );
$pidline = "$mytime $$ $machine";
print outfile "$pidline\n";
close(outfile);

&miscutils::mysleep(2.0);

open( infile, "/home/p/pay1/batchfiles/$devprod/mercury/pid$group.txt" );
$chkline = <infile>;
chop $chkline;
close(infile);

if ( $pidline ne $chkline ) {
  print "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  print "$pidline\n";
  print "$chkline\n";

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: mercury - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

$host = "processor-host";    # Source IP address

#&socketopen("64.69.205.190","18582");         # test server
#&socketopen("206.227.211.195","14133");         # primary server old
#&socketopen("64.69.203.195","18582");         # secondary server

#&socketopen("64.69.201.195","14133");         # primary server
&socketopen( "64.27.243.6", "14133" );    # secondary server

%errcode = (
  "01", "Invalid Transaction Code",
  "03", "Terminal ID not setup for settlement on this Card Type",
  "04", "Terminal ID not setup for authorization on this Card Type",
  "05", "Invalid Card Expiration Date",
  "06", "Invalid Process Code, Authorization Type or Card Type",
  "07", "Invalid Transaction or Other Dollar Amount",
  "08", "Invalid Entry Mode",
  "09", "Invalid Card Present Flag",
  "10", "Invalid Customer Present Flag",
  "11", "Invalid Transaction Count Value",
  "12", "Invalid Terminal Type",
  "13", "Invalid Terminal Capability",
  "14", "Invalid Source ID",
  "15", "Invalid Summary ID",
  "16", "Invalid Mag Stripe Data",
  "17", "Invalid Invoice Number",
  "18", "Invalid Transaction Date or Time",
  "19", "Invalid bankcard merchant number in First Data database",
  "20", "File access error in First Data database",
  "26", "Terminal flagged as Inactive in First Data database",
  "27", "Invalid Merchant/Terminal ID combination",
  "30", "Unrecoverable database error from an authorization process (usually means the Merchant/Terminal ID was already in use)",
  "31", "Database access lock encountered, Retry after 3 seconds",
  "33", "Database error in summary process, Retry after 3 seconds",
  "43", "Transaction ID invalid, incorrect or out of sequence",
  "51", "Terminal flagged as violated in First Data database (Call Customer Support)",
  "54", "Terminal ID not set up on First Data database for leased line access",
  "59", "Settle Trans for Summary ID where earlier Summary ID still open",
  "60", "Invalid account number found by authorization process, See Appendix B",
  "61", "Invalid settlement data found in summary process (trans level)",
  "62", "Invalid settlement data found in summary process (summary level)",
  "80", "Invalid Payment Service data found in summary process (trans level)",
  "98", "General system error"
);

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 * 30 ) );
$sixmonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 60 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";

$starttransdate = $sixmonthsago;

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $batchid, $today, $time ) = &miscutils::genorderid();
$todaytime = $time;

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/p/pay1/batchfiles/$devprod/mercury/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/p/pay1/batchfiles/$devprod/mercury/$fileyearonly");
  chmod( 0700, "/home/p/pay1/batchfiles/$devprod/mercury/$fileyearonly" );
}
if ( !-e "/home/p/pay1/batchfiles/$devprod/mercury/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/p/pay1/batchfiles/$devprod/mercury/$filemonth");
  chmod( 0700, "/home/p/pay1/batchfiles/$devprod/mercury/$filemonth" );
}
if ( !-e "/home/p/pay1/batchfiles/$devprod/mercury/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/p/pay1/batchfiles/$devprod/mercury/$fileyear");
  chmod( 0700, "/home/p/pay1/batchfiles/$devprod/mercury/$fileyear" );
}
if ( !-e "/home/p/pay1/batchfiles/$devprod/mercury/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: mercury - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/mercury/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batchid = $time;
$borderid = substr( "0" x 12 . $batchid, -12, 12 );

$dbh2 = &miscutils::dbhconnect("pnpdata");

#and t.username='pronet'
#select distinct c.username
#from trans_log t,customers c
#where t.trans_date>='$onemonthsago'
#and t.finalstatus = 'pending'
#and (t.accttype is NULL or t.accttype='credit')
#and c.username=t.username
#and c.processor='mercury'
#and c.status='live'
$sthtrans = $dbh2->prepare(
  qq{
        select username,count(username),min(trans_date)
        from operation_log force index(oplog_tdateloptimeuname_idx)
        where trans_date>='$starttransdate'
$checkstring
        and trans_date<='$today'
        and lastoptime>='$onemonthsagotime'
        and lastopstatus='pending'
        and processor='mercury'
        and (accttype is NULL or accttype ='' or accttype='credit')
        group by username
  }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthtrans->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthtrans->bind_columns( undef, \( $user, $usercount, $usertdate ) );
while ( $sthtrans->fetch ) {
  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
  print "$user\n";
}
$sthtrans->finish;

foreach $username ( sort @userarray ) {
  if ( ( -e "/home/p/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/p/pay1/batchfiles/$devprod/mercury/stopgenfiles.txt" ) ) {
    unlink "/home/p/pay1/batchfiles/$devprod/mercury/batchfile.txt";
    last;
  }

  # every day at 5:00am est mercury goes down
  # don't send batches at these times
  my ( $mysec, $mymin, $myhour ) = localtime( time() );
  $chktime = sprintf( "%02d%02d", $myhour, $mymin );
  if ( ( $chktime >= 330 ) && ( $chktime < 350 ) ) {
    &miscutils::mysleep(720);
  }

  umask 0033;
  open( batchfile, ">/home/p/pay1/batchfiles/$devprod/mercury/genfiles$group.txt" );
  print batchfile "$username\n";
  close(batchfile);

  umask 0033;
  open( batchfile, ">/home/p/pay1/batchfiles/$devprod/mercury/batchfile.txt" );
  print batchfile "$username\n";
  close(batchfile);

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  print "$username $usercountarray{$username} $starttransdate\n";

  if ( $usercountarray{$username} > 2000 ) {
    $batchcntuser = 500;
  } elsif ( $usercountarray{$username} > 1000 ) {
    $batchcntuser = 300;
  } elsif ( $usercountarray{$username} > 500 ) {
    $batchcntuser = 200;
  } elsif ( $usercountarray{$username} > 200 ) {
    $batchcntuser = 100;
  } else {
    $batchcntuser = 100;
  }
  $batchcntuser = 100;

  $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sth = $dbh->prepare(
    qq{
        select merchant_id,pubsecret,proc_type,status,features
        from customers
        where username='$username'
        }
    )
    or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $merchant_id, $terminal_id, $proc_type, $status, $features ) = $sth->fetchrow;
  $sth->finish;

  my $sth = $dbh->prepare(
    qq{
        select bankid,industrycode,capabilities,batchtime
        from mercury
        where username='$username'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $bankid, $industrycode, $capabilities, $batchgroup ) = $sth->fetchrow;
  $sth->finish;

  $dbh->disconnect;

  if ( $status ne "live" ) {
    next;
  }

  if ( ( $group eq "4" ) && ( $batchgroup ne "4" ) ) {
    next;
  } elsif ( ( $group eq "3" ) && ( $batchgroup ne "3" ) ) {
    next;
  } elsif ( ( $group eq "2" ) && ( $batchgroup ne "2" ) ) {
    next;
  } elsif ( ( $group eq "1" ) && ( $batchgroup ne "1" ) ) {
    next;
  } elsif ( ( $group eq "0" ) && ( $batchgroup ne "" ) ) {
    next;
  } elsif ( $group !~ /^(0|1|2|3|4)$/ ) {
    next;
  }

  $switchtime = "";

  # sweeptime
  my %feature = ();
  if ( $features ne "" ) {
    my @array = split( /\,/, $features );
    foreach my $entry (@array) {
      my ( $name, $value ) = split( /\=/, $entry );
      $feature{$name} = $value;
    }
  }

  if ( $feature{"batchcnt"} > 100 ) {
    $batchcntuser = $feature{"batchcnt"};
  }

  # sweeptime
  $sweeptime = $feature{'sweeptime'};    # sweeptime=1:EST:19   dstflag:timezone:time
  print "sweeptime: $sweeptime\n";
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    if ( ( $dstflag !~ /0|1/ ) || ( $timezone !~ /EST|CST|PST/ ) || ( $settlehour > 23 ) ) {
      $sweeptime = "";
    }
  }
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
      print logfile "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      close(logfile);
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
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
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
  print "$username\n";
  print logfile "$username  sweeptime: $sweeptime  settletime: $settletime\n";
  print logfile "$features\n";
  close(logfile);

  # every day at 6:00am est mercury breaks
  # don't send batches at these times
  my ( $mysec, $mymin, $myhour ) = localtime( time() );
  $chktime = sprintf( "%02d%02d", $myhour, $mymin );
  if ( ( $chktime >= 555 ) && ( $chktime < 605 ) ) {
    &miscutils::mysleep(360);

    my ( $mysec, $mymin, $myhour ) = localtime( time() );
    $chktime2 = sprintf( "%02d%02d", $myhour, $mymin );
    $mytime = gmtime( time() );
    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/logs/$fileyear/$username$time$pid.txt" );
    print logfile "$mytime  aaaa $chktime  $chktime2\n";
    close(logfile);
  }

  &pidcheck();

  $batch_flag = 1;

  # check that previous batch has completed successfully
  #$sthcheck = $dbh2->prepare(qq{
  #      select result
  #      from trans_log
  #      where trans_date>='$onemonthsago'
  #      and finalstatus='locked'
  #      and username='$username'
  #      and (accttype is NULL or accttype='credit')
  #      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  #$sthcheck->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
  #($result) = $sthcheck->fetchrow;
  #$sthcheck->finish;

  #if ($result ne "") {
  #}

  #select orderid,operation,trans_date,trans_time,enccardnumber,length,card_exp,amount,auth_code,avs,transflags,refnumber,finalstatus,cvvresp
  #from trans_log
  #where trans_date>='$onemonthsago'
  #and username='$username'
  #and operation IN ('postauth','return','void')
  #and finalstatus IN ('pending','success')
  #and duplicate IS NULL
  #and (accttype is NULL or accttype='credit')
  #order by orderid,trans_time DESC
  $sthtrans = $dbh2->prepare(
    qq{
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,transflags,refnumber,lastopstatus,cvvresp,reauthstatus
          from operation_log force index(oplog_tdateloptimeuname_idx)
          where trans_date>='$starttransdate'
          and trans_date<='$today'
          and lastoptime>='$onemonthsagotime'
          and username='$username'
          and lastop in ('postauth','return')
          and lastopstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
          order by orderid
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthtrans->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthtrans->bind_columns( undef,
    \( $orderid, $operation, $trans_date, $trans_time, $enccardnumber, $enclength, $exp, $amount, $auth_code, $avs_code, $transflags, $refnumber, $finalstatus, $cvvresp, $reauthstatus ) );

  $detailcnt    = 0;
  @detailarray  = ();
  @orderidarray = ();
  while ( $sthtrans->fetch ) {
    if ( ( -e "/home/p/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/p/pay1/batchfiles/$devprod/mercury/stopgenfiles.txt" ) ) {
      unlink "/home/p/pay1/batchfiles/$devprod/mercury/batchfile.txt";
      last;
    }

    if ( $operation eq "void" ) {
      $orderidold = $orderid;
      next;
    }
    if ( ( $orderid eq $orderidold ) || ( $finalstatus !~ /^(pending|locked)$/ ) ) {
      $orderidold = $orderid;
      next;
    }

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "mercury", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

    $card_type = &smpsutils::checkcard($cardnumber);
    if ( $card_type eq "dc" ) {
      $card_type = "mc";
    }

    if ( $card_type eq "pl" ) {
      $orderidold = $orderid;
      next;
    }

    if ( $transflags =~ /milstar/ ) {
      $orderidold = $orderid;
      next;
    }

    $orderidold = $orderid;

    if ( ( $sweeptime ne "" ) && ( $trans_time > $sweeptime ) ) {
      $orderidold = $orderid;
      next;    # transaction is newer than sweeptime
    }

    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
    print logfile "$orderid $operation\n";
    close(logfile);

    if ( $batch_flag == 1 ) {
      $datasentflag    = 0;
      $socketerrorflag = 0;
      $batcherrorflag  = 0;
      $headererrorflag = 0;
      $batchcnt        = 0;
      $salesamt        = 0;
      $salescnt        = 0;
      $returnamt       = 0;
      $returncnt       = 0;
      $debsalesamt     = 0;
      $debsalescnt     = 0;
      $debreturnamt    = 0;
      $debreturncnt    = 0;
    }

    #select operation,amount
    #from trans_log
    #where orderid='$orderid'
    #and username='$username'
    #and trans_date>='$twomonthsago'
    #and operation in ('auth','forceauth')
    #and (accttype is NULL or accttype='credit')
    $sthamt = $dbh2->prepare(
      qq{
          select authtime,authstatus,forceauthtime,forceauthstatus,origamount
          from operation_log
          where orderid='$orderid'
          and lastoptime>='$onemonthsagotime'
          and username='$username'
          and (accttype is NULL or accttype ='' or accttype='credit')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthamt->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ( $authtime, $authstatus, $forceauthtime, $forceauthstatus, $origamount ) = $sthamt->fetchrow;
    $sthamt->finish;

    if ( $switchtime ne "" ) {
      $switchtime = substr( $switchtime . "0" x 14, 0, 14 );
      if ( ( $operation eq "postauth" ) && ( $authtime ne "" ) && ( $authtime < $switchtime ) ) {
        next;
      }
    }

    if ( ( $authtime ne "" ) && ( $authstatus eq "success" ) ) {
      if ( $operation eq "postauth" ) {
        $trans_time = $authtime;
      }
      $origoperation = "auth";
    } elsif ( ( $forceauthtime ne "" ) && ( $forceauthstatus eq "success" ) ) {
      if ( $operation eq "postauth" ) {
        $trans_time = $forceauthtime;
      }
      $origoperation = "forceauth";
    } else {

      #$trans_time = "";
      $origoperation = "";
      $origamount    = "";
    }

    if ( $batch_flag == 1 ) {

      #&batchheader();
      #$details = "";
      $batch_flag = 0;
    }

    my $sthlock = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='locked',result=?
	    where orderid='$orderid'
	    and username='$username'
	    and finalstatus='pending'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthlock->execute("$time") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthlock->finish;

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    my $sthop = $dbh2->prepare(
      qq{
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending'
          where orderid='$orderid'
          and username='$username'
          and $operationstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute("$time") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;

    &batchdetail();
    if ( $socketerrorflag == 1 ) {
      last;    # if socket error stop altogether
    }

    if ( $detailcnt >= $batchcntuser ) {
      &endbatch();
      $nomoredata   = 0;
      $batch_flag   = 1;
      $batchcnt     = 0;
      $detailcnt    = 0;
      $datasentflag = 0;
      if ( $batcherrorflag == 1 ) {
        last;    # if batch error move on to next username
      }
    }
  }
  $sthtrans->finish;

  if ( ( ( $detailcnt >= 1 ) || ( $datasentflag == 1 ) ) && ( $socketerrorflag == 0 ) ) {
    &endbatch();
    $nomoredata   = 0;
    $batch_flag   = 1;
    $batchcnt     = 0;
    $datasentflag = 0;
  }

  if ( ( $socketerrorflag == 1 ) || ( $headererrorflag == 1 ) ) {
    my $sthpending = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='pending'
	    where trans_date>='$onemonthsago'
            and trans_date<='$today'
	    and username='$username'
	    and finalstatus='locked'
	    and result='$time'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpending->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpending->finish;

    my $sthop1 = $dbh2->prepare(
      qq{
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where trans_date>='$starttransdate'
            and trans_date<='$today'
        and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop1->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop1->finish;

    my $sthop2 = $dbh2->prepare(
      qq{
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where trans_date>='$starttransdate'
            and trans_date<='$today'
        and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop2->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop2->finish;

    close(logfile);
  }

  close(logfile);

  if ( $socketerrorflag == 1 ) {
    close(SOCK);
    &miscutils::mysleep(60.0);
    &socketopen( "64.69.201.195", "14133" );    # primary server
  }
}
close(SOCK);

#$sth->finish;

$dbh2->disconnect;

unlink "/home/p/pay1/batchfiles/$devprod/mercury/batchfile.txt";

umask 0033;
open( batchfile, ">/home/p/pay1/batchfiles/$devprod/mercury/genfiles$group.txt" );
close(batchfile);

exit;

sub mysleep {
  for ( $myi = 0 ; $myi <= 60 ; $myi++ ) {
    umask 0033;
    $temptime = time();
    open( outfile, ">/home/p/pay1/batchfiles/$devprod/mercury/baccesstime.txt" );
    print outfile "$temptime\n";
    close(outfile);

    select undef, undef, undef, 60.00;
  }
}

sub senderrmail {
  my ($message) = @_;

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: mercury - batch problem\n";
  print MAILERR "\n";
  print MAILERR "Username: $username\n";
  print MAILERR "\nLocked transactions found in trans_log and summaryid's did not match.\n";
  print MAILERR " Or batch out of balance.\n\n";
  print MAILERR "$message.\n\n";
  print MAILERR "chksummaryid: $chksummaryid    summaryid: $summaryid\n";
  close MAILERR;

}

sub batchheader {

  @bh = ();
  $bh[0] = pack "H4",  '1520';                # message id (4n)
  $bh[1] = pack "H16", "202000010040002a";    # primary bit map (8n)
  if ( $nomoredata == 0 ) {
    $bh[2] = pack "H6", 'A80001';             # processing code (6a)
  } else {
    $bh[2] = pack "H6", 'A80000';             # processing code (6a)
  }
  $bh[3] = pack "H6", '000000';               # system trace number (6n)

  #$bankid = '095000';
  $len = length($bankid);
  if ( $len % 2 == 1 ) {
    $bankid = "0" . $bankid;
    $len    = $len + 1;
  }
  $len = substr( "00" . $len, -2, 2 );
  $bh[4] = pack "H2H$len", $len, $bankid;     # acquiring institution id -  bank id(12n) LLVAR

  $mid = substr( $merchant_id . " " x 15, 0, 15 );
  $bh[5] = $mid;                              # card acceptor id code - terminal/merchant id (15a)
  $oid = substr( $batchid,        -20, 20 );
  $oid = substr( $oid . " " x 20, 0,   20 );
  $bh[6] = pack "H4A20", "0020", $oid;        # transport data (20a) LLLVAR

  $bheader = "";
  foreach $var (@bh) {
    $bheader = $bheader . $var;
  }
  &printrecord( "batchheader", "$bheader" );
}

sub batchdetail {
  $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

  $datasentflag = 1;

  $commcardtype = substr( $auth_code, 16, 1 );

  $card_type = &smpsutils::checkcard($cardnumber);
  if ( $card_type eq "dc" ) {
    $card_type = "mc";
  }

  @bd = ();

  if ( $transflags eq "restaurant" ) {
    $industrycode = "restaurant";
  } elsif ( $transflags eq "retail" ) {
    $industrycode = "retail";
  }

  $magstripetrack = "";
  $magstripetrack = substr( $auth_code, 56, 1 );
  $posentry       = substr( $auth_code, 44, 12 );
  $posentry =~ s/ //g;
  print "auth_code: $auth_code\n";
  print "magstripetrack: $magstripetrack\n";
  print "posentry: $posentry\n";

  $debitflag = substr( $auth_code, 221, 1 );

  # temporary just until old auths are postauthed
  if (1) {
    if ( $posentry =~ /^.1/ ) {    # debit card
      $debitflag = 1;
    }
  }

  $cashbackind = substr( $auth_code, 222, 1 );
  print "cashbackind: $cashbackind\n";
  if ( $debitflag == 1 ) {

    # debit card
    $avs = $avs_code;
    $avs =~ s/ //g;

    if ( $operation eq "return" ) {
      $proc1 = '20';
    } elsif ( $origoperation eq "forceauth" ) {
      $proc1 = '18';
    } elsif ( $cashbackind eq "1" ) {
      $proc1 = '09';
    }

    #elsif (($amount ne $origamount) && ($reauthstatus eq "success")) {	# reauth
    #  $proc1 = '02';
    #}
    elsif ( ( ( $transflags =~ /recurring/ ) && ( $card_type =~ /^(vi|mc|ax|ds)$/ ) && ( $avs eq "" ) )
      || ( ( $industrycode =~ /retail|restaurant/ ) && ( $magstripetrack =~ /^(1|2)$/ ) ) ) {
      $proc1 = '00';    # recurring or retail
    } else {
      $proc1 = '17';    # normal ecommerce - avs included
    }

    $proc2 = '00';      # commercial

    if (
         ( $operation eq "return" )
      || ( ( ( $industrycode =~ /retail|restaurant/ ) || ( $card_type ne "vi" ) ) && ( $amount ne $origamount ) && ( $reauthstatus eq "success" ) )    # reauth
      || ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) )
      ) {
      #$proc3 = '00';
      $proc3 = '40';
    }

    #elsif ($amount ne $origamount) {	# reauth
    #  $proc3 = '60';
    #}
    else {
      $proc3 = '50';
    }

    $tcode = $proc1 . $proc2 . $proc3;    # processing code  50 = no duplicate checking (6a)

    $bd[0] = $tcode;                      # processing code (6an)

    if ( $posentry ne "" ) {              # to be certified
      $bd[1] = $posentry;
    } elsif ( $industrycode =~ /retail|restaurant/ ) {
      $posentry = '200100600000';         # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      if ( $capabilities =~ /debit/ ) {
        $posentry = substr( $posentry, 0, 1 ) . '1' . substr( $posentry, 2 );
      }
      if ( ( $capabilities =~ /partial/ ) || ( $transflags =~ /partial/ ) ) {
        $posentry = substr( $posentry, 0, 8 ) . '1' . substr( $posentry, 9 );
      }
      $bd[1] = $posentry;                 # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
    } else {
      if ( ( $transflags =~ /recurring/ ) && ( $card_type =~ /^(vi|mc|ax|ds)/ ) ) {
        $posentry = '600140620000';       # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      } elsif ( ( $origoperation eq "forceauth" ) || ( $operation eq "return" ) || ( $transflags =~ /moto/ ) ) {
        $posentry = '600110610000';       # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      } else {
        $posentry = '600550670000';       # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      }

      #if ($capabilities =~ /debit/) {
      #  $posentry = substr($posentry,0,1) . '1' . substr($posentry,2);
      #}
      if ( ( $capabilities =~ /partial/ ) || ( $transflags =~ /partial/ ) ) {
        $posentry = substr( $posentry, 0, 8 ) . '1' . substr( $posentry, 9 );
      }
      $bd[1] = $posentry;    # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
    }

    $bd[2] = $cardnumber;    # primary acct number (24n)
    $expdate = substr( $exp, 3, 2 ) . substr( $exp, 0, 2 );
    $bd[3] = $expdate;       # expiration date YYMM (4n)
    $transamt = sprintf( "%d", ( substr( $amount, 4 ) * 100 ) + .0001 );
    $transamt = substr( "0" x 10 . $transamt, -10, 10 );
    $bd[4] = $transamt;      # transaction amount - amount1 (10n)

    #if ($commcardtype eq "1") {
    $tax = substr( $auth_code,     17, 10 );
    $tax = substr( "0" x 8 . $tax, -8, 8 );
    $bd[5] = $tax;           # addtl amount   tax for commercial cards   gratuity for restaurant  - amount2 (8n)
                             #}
                             #else {
                             #  $bd[5] = "";                               # addtl amount (8n)
                             #}

    $batchdata = substr( $auth_code, 57, 20 );
    $batchdata =~ s/ //g;
    ( $itemnum, $batchnum ) = split( /,/, $batchdata );
    $itemnum = substr( "0" x 4 . $itemnum, -4, 4 );
    $bd[6] = $itemnum;       # item number (4n)
    $batchnum = substr( "0" x 4 . $batchnum, -4, 4 );
    $bd[7] = $batchnum;      # batch number (4n)

    $actcode = substr( $auth_code, 6, 3 );
    if ( $actcode eq "   " ) {
      $actcode = "";
    }
    $bd[8] = $actcode;       # action code (3an)
    $tdate = substr( $trans_time, 2, 12 );
    $bd[9] = $tdate;         # transaction date & time (12an)

    $bd[10] = "";            # routing data
    $refnum = substr( $auth_code, 77, 6 );
    $refnum =~ s/ //g;
    $bd[11] = $refnum;       # reference number
    $bd[12] = "";            # shift id (1an)
    $bd[13] = "";            # clerk id (4an)

    $marketdata = "";

    if ( ( $transflags !~ /moto/ ) && ( $industrycode =~ /restaurant/ ) ) {
      $marketdata = $marketdata . "aF";
    } elsif ( ( $transflags !~ /moto/ ) && ( $industrycode =~ /retail|restaurant/ ) ) {
      $marketdata = $marketdata . "aR";
    } else {
      $marketdata = $marketdata . "aD";
    }

    $reportdata = substr( $auth_code, 196, 25 );
    $reportdata =~ s/ +$//;
    $reportdata =~ s/[^0-9a-zA-Z\- ]//g;
    if ( ( $reportdata ne "" ) && ( $card_type =~ /vi|mc/ ) && ( ( $transflags =~ /moto/ ) || ( $industrycode !~ /retail|restaurant/ ) ) ) {
      $c = $reportdata;
      $c =~ tr/a-z/A-Z/;
      $marketdata = $marketdata . "c$c";
    } elsif ( ( $card_type eq "vi" ) && ( ( $transflags =~ /moto/ ) || ( $industrycode !~ /retail|restaurant/ ) ) ) {
      $c = substr( $orderid, -25, 25 );
      $c =~ tr/a-z/A-Z/;
      $marketdata = $marketdata . "c$c";
    }

    if ( ( $card_type =~ /vi/ ) && ( ( $transflags =~ /moto/ ) || ( $industrycode !~ /retail|restaurant/ ) ) ) {
      if ( $transflags =~ /digital/ ) {
        $j = "D";    # electronic goods ind D = digital goods, P = physical goods
      } elsif ( $transflags =~ /physical/ ) {
        $j = "P";    # electronic goods ind D = digital goods, P = physical goods
      } else {
        $j = "";     # electronic goods ind D = digital goods, P = physical goods
      }
      if ( ( $transflags !~ /(moto|recurring)/ ) && ( $j ne "" ) ) {
        $marketdata = $marketdata . "j$j";
      }
    }

    if ( ( $card_type =~ /vi|mc/ ) && ( ( $transflags =~ /moto/ ) || ( $industrycode !~ /retail|restaurant/ ) ) ) {
      $k          = $transamt + 0;
      $marketdata = $marketdata . "k$k";
    }

    if ( $card_type eq "ax" ) {
      $d = substr( $orderid, -16, 16 );
      $d =~ tr/a-z/A-Z/;
      $marketdata = $marketdata . "d$d";
    }

    if ( $commcardtype eq "1" ) {

      #if ($card_type =~ /vi|mc/) {
      # $taxind = "Y";
      #}
      $ponumber = substr( $auth_code, 27, 16 );
      $ponumber =~ s/[ ,]//g;
      $ponumber =~ tr/a-z/A-Z/;
      $marketdata = $marketdata . "m$ponumber";
    }

    $extramarketdata = $refnumber;
    $extramarketdata =~ s/ +$//g;
    if ( $extramarketdata ne "" ) {
      $extramarketdata = substr( $extramarketdata . " " x 20, 0, 20 );
      $marketdata = $marketdata . "x$extramarketdata";
    }

    $bd[14] = $marketdata;    # market data (130ans)

  } else {

    # credit card
    $avs = $avs_code;
    $avs =~ s/ //g;

    $cashbackind = substr( $auth_code, 221, 1 );
    if ( $operation eq "return" ) {
      $proc1 = '20';
    } elsif ( $origoperation eq "forceauth" ) {
      $proc1 = '18';
    }

    #elsif (($amount ne $origamount) && ($reauthstatus eq "success")) {	# reauth
    #  $proc1 = '02';
    #}
    elsif ( $cashbackind eq "1" ) {
      $proc1 = '09';
    } elsif ( ( ( $transflags =~ /recurring/ ) && ( $card_type =~ /^(vi|mc|ax|ds)$/ ) && ( $avs eq "" ) )
      || ( ( $industrycode =~ /retail|restaurant/ ) && ( $magstripetrack =~ /^(1|2)$/ ) ) ) {
      $proc1 = '00';    # recurring or retail
    } else {
      $proc1 = '17';    # normal ecommerce - avs included
    }

    if ( $commcardtype eq "1" ) {
      $proc2 = '40';    # commercial
    } elsif ( $card_type eq "jc" ) {
      $proc2 = '91';    # jcb
    } else {
      $proc2 = '30';    # normal ecommerce
    }

    if (
         ( $operation eq "return" )
      || ( ( ( $industrycode =~ /retail|restaurant/ ) || ( $card_type ne "vi" ) ) && ( $amount ne $origamount ) && ( $reauthstatus eq "success" ) )    # reauth
      || ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) )
      ) {
      #$proc3 = '00';
      $proc3 = '40';
    }

    #elsif ($amount ne $origamount) {	# reauth
    #  $proc3 = '60';
    #}
    else {
      $proc3 = '50';
    }

    $tcode = $proc1 . $proc2 . $proc3;    # processing code  50 = no duplicate checking (6a)

    $bd[0] = $tcode;                      # processing code (6an)

    # begin temporary because mercury has a bug with mc UCAF on settlement
    $cavvresp = substr( $auth_code, 102, 1 );
    $cavvresp =~ s/ //g;
    if ( ( $card_type eq "mc" ) && ( $cavvresp eq "x" ) && ( $operation eq "postauth" ) ) {
      $posentry = '600550671000';         # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      $bd[1] = $posentry;
    }    # end of temporary stuff
    elsif ( $posentry ne "" ) {    # to be certified
      $bd[1] = $posentry;
    } elsif ( $industrycode =~ /retail|restaurant/ ) {
      $posentry = '200100600000';    # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      if ( $capabilities =~ /debit/ ) {
        $posentry = substr( $posentry, 0, 1 ) . '1' . substr( $posentry, 2 );
      }
      if ( ( $capabilities =~ /partial/ ) || ( $transflags =~ /partial/ ) ) {
        $posentry = substr( $posentry, 0, 8 ) . '1' . substr( $posentry, 9 );
      }
      $bd[1] = $posentry;            # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
    } else {
      if ( ( $transflags =~ /recurring/ ) && ( $card_type =~ /^(vi|mc|ax|ds)/ ) ) {
        $posentry = '600140620000';    # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      } elsif ( ( $origoperation eq "forceauth" ) || ( $operation eq "return" ) || ( $transflags =~ /moto/ ) ) {
        $posentry = '600110610000';    # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      } else {
        $posentry = '600550670000';    # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      }

      #if ($capabilities =~ /debit/) {
      #  $posentry = substr($posentry,0,1) . '1' . substr($posentry,2);
      #}
      if ( ( $capabilities =~ /partial/ ) || ( $transflags =~ /partial/ ) ) {
        $posentry = substr( $posentry, 0, 8 ) . '1' . substr( $posentry, 9 );
      }
      $bd[1] = $posentry;    # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
    }

    $bd[2] = $cardnumber;    # primary acct number (24n)
    $expdate = substr( $exp, 3, 2 ) . substr( $exp, 0, 2 );
    $bd[3] = $expdate;       # expiration date YYMM (4n)
    $transamt = sprintf( "%d", ( substr( $amount, 4 ) * 100 ) + .0001 );
    $transamt = substr( "0" x 10 . $transamt, -10, 10 );
    $bd[4] = $transamt;      # transaction amount - amount1 (8n)

    #if ($commcardtype eq "1") {
    $tax = substr( $auth_code,     17, 10 );
    $tax = substr( "0" x 8 . $tax, -8, 8 );
    $bd[5] = $tax;           # addtl amount   tax for commercial cards   gratuity for restaurant  - amount2 (8n)
                             #}
                             #else {
                             #  $bd[5] = "";                               # addtl amount (8n)
                             #}

    $origamt = sprintf( "%d", ( substr( $origamount, 4 ) * 100 ) + .0001 );
    $origamt = substr( "0" x 8 . $origamt, -8, 8 );
    if ( $operation eq "return" ) {
      $origamt = "";
    }
    $bd[6] = $origamt;       # orig amount - amount3 (8n)

    $batchdata = substr( $auth_code, 57, 20 );
    $batchdata =~ s/ //g;
    ( $itemnum, $batchnum ) = split( /,/, $batchdata );
    $itemnum = substr( "0" x 4 . $itemnum, -4, 4 );
    $bd[7] = $itemnum;       # item number (4n)
    $batchnum = substr( "0" x 4 . $batchnum, -4, 4 );
    $bd[8] = $batchnum;      # batch number (4n)
                             #$bd[7] = "0000";                             # item number (4n)
                             #$bd[8] = "0000";                             # batch number (4n)

    $actcode = substr( $auth_code, 6, 3 );
    if ( $actcode eq "   " ) {
      $actcode = "";
    }
    $bd[9] = $actcode;       # action code (3an)
    $appcode = substr( $auth_code, 0, 6 );
    if ( $operation eq "return" ) {
      $appcode =~ s/ //g;
    }
    $bd[10] = $appcode;      # approval code (6ans)
    $tdate = substr( $trans_time, 2, 12 );
    $bd[11] = $tdate;        # transaction date & time (12an)
    $tdate = substr( $auth_code, 9, 6 );
    if ( $tdate eq "      " ) {
      $tdate = "";
    }
    $bd[12] = $tdate;        # authorized date (6an)

    $intxind2     = substr( $auth_code, 101, 1 );
    $intxcompdata = substr( $auth_code, 103, 93 );
    if ( $intxcompdata =~ /,,,.*$/ ) {
      $intxcompdata =~ s/,,,.*$//;
    } elsif ( $intxind2 eq "," ) {    # to be certified
      $intxcompdata = substr( $auth_code, 103, 63 );
    } else {
      $intxcompdata = substr( $auth_code, 57 );
    }
    if ( length($intxcompdata) < 2 ) {
      $intxcompdata = "";
    }
    if ( ( $origoperation eq "forceauth" ) && ( $operation eq "postauth" ) && ( $transflags =~ /bill/ ) ) {
      $intxcompdata = "fB";
    }
    $bd[13] = $intxcompdata;          # acquirer reference data (99ans)

    $marketdata = "";

    $marketdata = "";

    if ( ( $transflags !~ /moto/ ) && ( $industrycode =~ /restaurant/ ) ) {
      $marketdata = $marketdata . "aF";
    } elsif ( ( $transflags !~ /moto/ ) && ( $industrycode =~ /retail|restaurant/ ) ) {
      $marketdata = $marketdata . "aR";
    } else {
      $marketdata = $marketdata . "aD";
    }

    $reportdata = substr( $auth_code, 196, 25 );    # the new way
    $reportdata =~ s/ +$//;
    $reportdata =~ s/[^0-9a-zA-Z\- ]//g;
    if ( ( $reportdata ne "" ) && ( $card_type =~ /vi|mc/ ) && ( ( $transflags =~ /moto/ ) || ( $industrycode !~ /retail|restaurant/ ) ) ) {
      $c = $reportdata;
      $c =~ tr/a-z/A-Z/;
      $marketdata = $marketdata . "c$c";
    } elsif ( ( $card_type eq "vi" ) && ( ( $transflags =~ /moto/ ) || ( $industrycode !~ /retail|restaurant/ ) ) ) {
      $c = substr( $orderid, -25, 25 );
      $c =~ tr/a-z/A-Z/;
      $marketdata = $marketdata . "c$c";
    }

    if ( ( $card_type eq "vi" ) && ( ( $transflags =~ /moto/ ) || ( $industrycode !~ /retail|restaurant/ ) ) ) {
      if ( $transflags =~ /digital/ ) {
        $j = "D";    # electronic goods ind D = digital goods, P = physical goods
      } elsif ( $transflags =~ /physical/ ) {
        $j = "P";    # electronic goods ind D = digital goods, P = physical goods
      } else {
        $j = "";     # electronic goods ind D = digital goods, P = physical goods
      }
      if ( ( $transflags !~ /(moto|recurring)/ ) && ( $j ne "" ) ) {
        $marketdata = $marketdata . "j$j";
      }
    }

    if ( ( $card_type =~ /vi|mc/ ) && ( ( $transflags =~ /moto/ ) || ( $industrycode !~ /retail|restaurant/ ) ) ) {
      $k          = $transamt + 0;
      $marketdata = $marketdata . "k$k";
    }

    if ( $card_type eq "ax" ) {
      $d = substr( $orderid, -16, 16 );
      $d =~ tr/a-z/A-Z/;
      $marketdata = $marketdata . "d$d";
    }

    if ( $commcardtype eq "1" ) {
      $ponumber = substr( $auth_code, 27, 16 );
      $ponumber =~ s/ //g;
      $ponumber =~ tr/a-z/A-Z/;
      $marketdata = $marketdata . "m$ponumber";
    }

    $extramarketdata = $refnumber;
    $extramarketdata =~ s/ +$//g;
    if ( $extramarketdata ne "" ) {
      $extramarketdata = substr( $extramarketdata . " " x 20, 0, 20 );
      $marketdata = $marketdata . "x$extramarketdata";
    }

    $bd[14] = $marketdata;    # market data (130ans)

    if ( ( $operation eq "return" )
      || ( ( $industrycode =~ /retail|restaurant/ ) && ( $magstripetrack =~ /^(1|2)$/ ) )
      || ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) ) {
      $avs = $avs_code;
      $avs =~ s/ //g;
    } else {
      $avs = substr( $avs_code . " ", 0, 1 );
    }
    $bd[15] = $avs;           # avs result code (1an)
    $oid = substr( $orderid, -20, 20 );
    $bd[16] = $oid;           # routing data (20an)
    $bd[17] = "";             # merchant type (4n)
    $bd[18] = "";             # shift id (1an)
    $bd[19] = "";             # clerk id (4an)
                              #$cvv = substr($cvvresp . " ",0,1);
    $cvv    = $cvvresp;
    $cvv =~ s/ //g;
    $bd[20] = $cvv;           # cvv result (1an)
    $cavvresp = substr( $auth_code, 102, 1 );
    $cavvresp =~ s/ //g;
    $cavvresp =~ s/x//g;

    if ( $cavvresp ne "" ) {
      $bd[21] = $cavvresp;    # cvv result (1an)
    }
  }

  $details = "";
  foreach $var (@bd) {
    $details = $details . $var . ",";
  }
  chop $details;
  $fs                       = pack "H2", "1C";
  $details                  = $details . "$fs";
  $detailarray[$detailcnt]  = $details;
  $orderidarray[$detailcnt] = $orderid;

  $transamt = substr( $amount, 4 );
  $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );
  $transamt = substr( "00000000" . $transamt, -8, 8 );

  if ( ( $debitflag == 1 ) && ( $operation eq "return" ) ) {
    $debreturnamt = $debreturnamt + $transamt;
    $debreturncnt++;
  } elsif ( $debitflag == 1 ) {
    $debsalesamt = $debsalesamt + $transamt;
    $debsalescnt++;
  } elsif ( $operation eq "return" ) {
    $returnamt = $returnamt + $transamt;
    $returncnt++;
  } else {
    $salesamt = $salesamt + $transamt;
    $salescnt++;
  }
  $detailcnt++;

}

sub fileheader {
  @bt = ();
  $bt[0] = pack "H4",  '1500';                # message id (4n)
  $bt[1] = pack "H16", "2020000100400022";    # primary bit map (8n)
  $bt[2] = pack "H6",  'A70001';              # processing code (6a)

  # optional
  $bt[3] = pack "H6", '000000';               # system trace number (6n)

  #$bankid = '095000';
  $len = length($bankid);
  if ( $len % 2 == 1 ) {
    $bankid = "0" . $bankid;
    $len    = $len + 1;
  }
  $len = substr( "00" . $len, -2, 2 );
  $bt[4] = pack "H2H$len", $len, $bankid;     # acquiring institution id -  bank id(12n) LLVAR

  $mid = substr( $merchant_id . " " x 15, 0, 15 );
  $bt[5] = $mid;                              # card acceptor id code - terminal/merchant id (15a)
  $oid = substr( $batchid,        -20, 20 );
  $oid = substr( $oid . " " x 20, 0,   20 );
  $bt[6] = pack "H4A20", "0020", $oid;        # transport data (20a) LLLVAR

  @addtl    = ();
  $addtl[0] = "02";                           # version
  $addtl[1] = pack "H2", "1C";
  $addtl[2] = "MPS";                          # terminal type
  $addtl[3] = pack "H2", "1C";
  $addtl[4] = "";                             # shift id
  $addtl[5] = pack "H2", "1C";
  $addtl[6] = "";                             # clerk id
  $addtl[7] = pack "H2", "1C";
  if ( $transflags =~ /restaurant/ ) {
    $addtl[8] = "6F******";                   # app id
  } elsif ( $industrycode =~ /retail/ ) {
    $addtl[8] = "6R******";                   # app id
  } else {
    $addtl[8] = "6D******";                   # app id
  }
  $addtl[9]  = pack "H2", "1C";
  $addtl[10] = "DL00010";                     # version
  $addtl[11] = pack "H2", "1C";
  $salescnt = substr( "0" x 3 . $salescnt, -3, 3 );
  $addtl[12] = $salescnt;                     # purch count
  $addtl[13] = pack "H2", "1C";

  #$salesamt = sprintf("%d", ($salesamt * 100) + .0001);
  $salesamt = substr( "0" x 10 . $salesamt, -10, 10 );
  $addtl[14] = $salesamt;                     # purch amount
  $addtl[15] = pack "H2", "1C";
  $returncnt = substr( "0" x 3 . $returncnt, -3, 3 );
  $addtl[16] = $returncnt;                    # return count
  $addtl[17] = pack "H2", "1C";

  #$returnamt = sprintf("%d", ($returnamt * 100) + .0001);
  $returnamt = substr( "0" x 10 . $returnamt, -10, 10 );
  $addtl[18] = $returnamt;                    # return amount
  $addtl[19] = pack "H2", "1C";
  $debsalescnt = substr( "0" x 3 . $debsalescnt, -3, 3 );
  $addtl[20] = $debsalescnt;                  # debit purch count
  $addtl[21] = pack "H2", "1C";
  $debsalesamt = substr( "0" x 10 . $debsalesamt, -10, 10 );
  $addtl[22] = $debsalesamt;                  # debit purch amount
  $addtl[23] = pack "H2", "1C";
  $debreturncnt = substr( "0" x 3 . $debreturncnt, -3, 3 );
  $addtl[24] = $debreturncnt;                 # debit return count
  $addtl[25] = pack "H2", "1C";
  $debreturnamt = substr( "0" x 10 . $debreturnamt, -10, 10 );
  $addtl[26] = $debreturnamt;                                           # debit return amount
  $addtl[27] = pack "H2", "1C";
  $totalcnt  = $salescnt + $returncnt + $debsalescnt + $debreturncnt;
  $totalcnt = substr( "0" x 3 . $totalcnt, -3, 3 );
  $addtl[28] = $totalcnt;                                               # total count
  $addtl[29] = pack "H2", "1C";
  $batchnum = substr( "0" x 4 . $batchnum, -4, 4 );
  $addtl[30] = $batchnum;                                               # batch number

  $addtldata = "";
  foreach $var (@addtl) {
    $addtldata = $addtldata . $var;
  }
  $len = length($addtldata);
  if ( $len % 2 == 1 ) {
    $addtldata = "0" . $addtldata;
    $len       = $len + 1;
  }
  $len = substr( "0000" . $len, -4, 4 );
  print "addtllen: $len\n";

  #$bt[7] = pack "H4H$len",$len,$addtldata;	# mercury ecom addtl data (ANS999) LLLVAR
  $bt[7] = pack "H4", $len;    # mercury ecom addtl data (ANS999) LLLVAR
  $bt[8] = $addtldata;         # mercury ecom addtl data (ANS999) LLLVAR

  $message = "";
  foreach $var (@bt) {
    $message = $message . $var;
  }

  $len     = length($message);
  $len     = substr( "0000" . $len, -4, 4 );
  $header  = pack "H4A4A4", "0101", "    ", $len;
  $trailer = pack "H2", "03";

  #$message = $header . $message . $trailer;
  &printrecord( "fileheader", $message );
}

sub batchtrailer {

  #$recseqnum = $recseqnum + 2;
  #$recseqnum = substr($recseqnum,-8,8);

  chop $detailmsg;
  $len     = length($detailmsg);
  $len     = substr( "0000" . $len, -4, 4 );
  $len     = pack "H4", $len;
  $message = $bheader . $len . $detailmsg;
  &printrecord( "batchdetails", "$len$detailmsg" );

  @addtl = ();
  $addtl[0] = "02";    # version
  $addtl[1] = pack "H2", "1C";
  $addtl[2] = "MPS";             # terminal type
  $addtl[3] = pack "H2", "1C";
  $bcnt = substr( "000" . $batchcnt, -3, 3 );
  $addtl[4] = $bcnt;             # sequence number

  $addtldata = "";
  foreach $var (@addtl) {
    $addtldata = $addtldata . $var;
  }
  $len = length($addtldata);
  if ( $len % 2 == 1 ) {
    $addtldata = "0" . $addtldata;
    $len       = $len + 1;
  }
  $len = substr( "0000" . $len, -4, 4 );
  print "addtllen: $len\n";
  @mercuryaddtl = ();
  $mercuryaddtl[0] = pack "H4", $len;    # mercury ecom addtl data (ANS999) LLLVAR
  $mercuryaddtl[1] = $addtldata;         # mercury ecom addtl data (ANS999) LLLVAR
  foreach $var (@mercuryaddtl) {
    $message = $message . $var;
  }

  $len     = length($message);
  $len     = substr( "0000" . $len, -4, 4 );
  $header  = pack "H4A4A4", "0101", "    ", $len;
  $trailer = pack "H2", "03";

  #$message = $header . $message . $trailer;
  &printrecord( "batchmessage", "$message" );

}

sub endbatch {
  print "detailcnt: $detailcnt\n";

  # yyyy
  print "fileheader\n";
  &fileheader();

  $response = &sendrecord($message);

  my (@msgvalues) = &decodebitmap($response);

  $tracenum = $msgvalues[11];
  $batchnum = $msgvalues[12];
  $pass     = $msgvalues[39];
  $rmessage = $msgvalues[44];
  ($rmessage) = split( /1c/, $rmessage );

  #$rmessage = pack "H*", $rmessage;

  print "new data:\n";
  print "tracenum: $tracenum\n";
  print "batchnum: $batchnum\n";
  print "pass: $pass\n";
  print "rmessage: $rmessage\n";

  ( $d1, $d2, $len, $messid, $bitmap, $pcode, $restofdata ) = unpack "H4A4A4H4H16H6H*", $response;

  if (0) {
    print "<pre>\n";
    $temp = unpack "H*", $response;

    #print "response: $temp\n";

    $idx      = 0;
    $tracenum = "";
    if ( $bitmap =~ /^203000000a/ ) {
      $tracenum = substr( $restofdata, $idx, 6 );
      $idx = $idx + 6;
      print "tracenum: $tracenum\n";
    }

    $tdate = substr( $restofdata, $idx, 12 );
    $idx = $idx + 12;

    $batchnum = "";
    if ( $bitmap =~ /^20.000000a/ ) {
      $batchnum = substr( $restofdata, $idx, 24 );
      $batchnum = pack "H*", $batchnum;
      $idx = $idx + 24;
      print "batchnum: $batchnum\n";
    }

    $pass = substr( $restofdata, $idx, 6 );
    $pass = pack "H6", $pass;
    $idx = $idx + 6;
    print "pass: $pass\n";

    $addtllen  = substr( $restofdata, $idx,     2 );
    $addtldata = substr( $restofdata, $idx + 2, $addtllen * 2 );
    ($rmessage) = split( /1c/, $addtldata );
    $rmessage = pack "H*", $rmessage;
    $idx = $idx + ( $addtllen * 2 ) + 2;
    print "rmessage: $rmessage\n";
  }

  print "$pass $rmessage\n";
  if ( $pass ne "000" ) {
    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
    print logfile "header pass: $pass\n";
    print logfile "rmessage: $rmessage\n\n";
    close(logfile);

    print "bad batch\n";
    $batcherrorflag  = 1;
    $headererrorflag = 1;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: barbara\@plugnpay.com\n";
    print MAILERR "Cc: michelle\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: mercury - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Problem with genfiles.\n";
    print MAILERR "username: $username\n";
    print MAILERR "rmessage: $rmessage\n";
    close MAILERR;

    return;    # added 2/2/2016

  }

  my $i;
  $batchcnt = 0;
  for ( $i = 0 ; $i < $detailcnt ; $i++ ) {
    if ( ( $i % 3 == 0 ) && ( $i > 0 ) ) {
      print "batchtrailer()\n";
      $batchcnt++;
      &batchtrailer();
      $response = &sendrecord($message);
      chop $orderidstr;
      &processresponse();
      $batchid = &miscutils::incorderid($batchid);

      # added 8/2014
      if ( $batcherrorflag == 1 ) {
        last;    # if batch error move on to next username
      }
    }

    if ( $i % 3 == 0 ) {
      if ( $i >= $detailcnt - 3 ) {
        print "nomoredata\n";
        $nomoredata = 1;
      }
      $detailmsg  = "";
      $orderidstr = "";
      print "batchheader()\n";
      &batchheader();
    }

    print "detail\n";
    $detailmsg  = $detailmsg . $detailarray[$i];
    $orderidstr = $orderidstr . "'$orderidarray[$i]',";

    if ( $i == $detailcnt - 1 ) {
      print "batchtrailer()\n";
      $batchcnt++;
      &batchtrailer();
      $response = &sendrecord($message);
      chop $orderidstr;
      &processresponse();
      $batchid = &miscutils::incorderid($batchid);
    }
  }
  @detailarray  = ();
  @orderidarray = ();
}

sub processresponse {
  my (@msgvalues) = &decodebitmap($response);

  $tracenum = $msgvalues[11];
  $batchnum = $msgvalues[12];
  $pass     = $msgvalues[39];
  $rmessage = $msgvalues[44];
  ($rmessage) = split( /1c/, $rmessage );

  #$rmessage = pack "H*", $rmessage;

  print "new data:\n";
  print "tracenum: $tracenum\n";
  print "batchnum: $batchnum\n";
  print "pass: $pass\n";
  print "rmessage: $rmessage\n";

  ( $d1, $d2, $len, $messid, $bitmap, $pcode, $restofdata ) = unpack "H4A4A4H4H16H6H*", $response;

  if (0) {
    print "<pre>\n";
    $temp = unpack "H*", $response;
    print "response: $temp\n";
    print "messid: $messid\n";
    print "bitmap: $bitmap\n";
    print "pcode: $pcode\n";

    $idx      = 0;
    $tracenum = "";
    if ( $bitmap =~ /^203000000/ ) {
      $tracenum = substr( $restofdata, $idx, 6 );
      $idx = $idx + 6;
      print "tracenum: $tracenum\n";
    }

    $tdate = substr( $restofdata, $idx, 12 );
    $idx = $idx + 12;
    print "tdate: $tdate\n";

    $batchnum = "";
    if ( $bitmap =~ /^20.000000a/ ) {
      $batchnum = substr( $restofdata, $idx, 24 );
      $batchnum = pack "H*", $batchnum;
      $idx = $idx + 24;
      print "batchnum: $batchnum\n";
    }

    $pass = substr( $restofdata, $idx, 6 );
    $pass = pack "H6", $pass;
    $idx = $idx + 6;
    print "pass: $pass\n";

    $addtllen  = substr( $restofdata, $idx,     2 );
    $addtldata = substr( $restofdata, $idx + 2, $addtllen * 2 );
    ($rmessage) = split( /1c/, $addtldata );
    $rmessage = pack "H*", $rmessage;
    $idx = $idx + ( $addtllen * 2 ) + 2;
    print "rmessage: $rmessage\n";

    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
    print logfile "orderidstr: $orderidstr\n\n";
    print logfile "pass: $pass\n";
    print logfile "rmessage: $rmessage\n\n";
    close(logfile);
  }

  if ( $pass eq "000" ) {
    my $sthpass = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='success',trans_time=?
	    where orderid in ($orderidstr)
	    and username='$username'
	    and trans_date>='$onemonthsago'
            and trans_date<='$today'
	    and result='$time'
	    and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpass->execute("$time") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpass->finish;

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop1 = $dbh2->prepare(
      qq{
            update operation_log set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
	    where orderid in ($orderidstr)
            and trans_date>='$starttransdate'
            and trans_date<='$today'
        and lastoptime>='$onemonthsagotime'
            and batchfile='$time'
            and username='$username'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop1->execute( "$time", "$time" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop1->finish;

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop2 = $dbh2->prepare(
      qq{
            update operation_log set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
	    where orderid in ($orderidstr)
            and trans_date>='$starttransdate'
            and trans_date<='$today'
        and lastoptime>='$onemonthsagotime'
            and batchfile='$time'
            and username='$username'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop2->execute( "$time", "$time" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop2->finish;

  } else {
    if (0) {
      my $sthpending = $dbh2->prepare(
        qq{
            update trans_log set finalstatus='problem'
	    where orderid in ($orderidstr)
	    and username='$username'
	    and trans_date>='$onemonthsago'
	    and finalstatus='locked'
	    and result='$time'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthpending->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthpending->finish;

      %datainfo = ( "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $sthop1 = $dbh2->prepare(
        qq{
            update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?
	    where orderid in ($orderidstr)
            and batchfile='$time'
            and username='$username'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthop1->execute("") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthop1->finish;

      %datainfo = ( "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $sthop2 = $dbh2->prepare(
        qq{
            update operation_log set returnstatus='problem',lastopstatus='problem',descr=?
	    where orderid in ($orderidstr)
            and batchfile='$time'
            and username='$username'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthop2->execute("") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthop2->finish;
    }

    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
    print logfile "Batch Problem: $pass $rmessage\n";
    close(logfile);

    $batcherrorflag = 1;
  }
}

sub sendrecord {
  my ($message) = @_;

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
  $message2 = $message;
  $message3 = substr( $message2, 59 );
  (@fields) = split( /,/, $message3 );
  if ( ( length( $fields[2] ) >= 13 ) && ( length( $fields[2] ) <= 19 ) ) {
    $xs = "x" x length( $fields[2] );
    $message2 =~ s/$fields[2]/$xs/;
  }
  if ( ( length( $fields[22] ) >= 13 ) && ( length( $fields[22] ) <= 19 ) ) {
    $xs = "x" x length( $fields[22] );
    $message2 =~ s/$fields[22]/$xs/;
  }
  if ( ( length( $fields[42] ) >= 13 ) && ( length( $fields[42] ) <= 19 ) ) {
    $xs = "x" x length( $fields[42] );
    $message2 =~ s/$fields[42]/$xs/;
  }
  $message2 =~ s/([^0-9A-Za-z \n,])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] \n,])/unpack("H2",$1)/ge;
  $mytime = gmtime( time() );
  print logfile "$mytime message: $message2" . "\n\n";

  #print "message: $message2" . "\n";
  #($message2) = unpack "H*", $message;
  #print logfile "message: $message2\n";
  #print logfile "\n";
  close(logfile);

  $mytime = gmtime( time() );
  my $chkmessage = $message2;

  #$chkmessage =~ s/></>\n</g;
  #$chkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  #$chkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  #if ($username =~ /^(testmercury|pnpdemo)$/) {
  #  open(logfile,">>/home/p/pay1/batchfiles/$devprod/mercury/serverlogmsgtest.txt");
  #}
  #else {
  #  open(logfile,">>/home/p/pay1/batchfiles/$devprod/mercury/serverlogmsg.txt");
  #}
  #print logfile "$username  $datainfo{'order-id'}\n";
  #print logfile "$mytime send:\n$chkmessage\n\n";
  #print "$mytime send:\n$chkmessage\n\n";
  #close(logfile);

  $message = encode_base64("$message");
  $message =~ s/\n//g;

  my $newmessage = "<BinaryMsgReq>";
  $newmessage = $newmessage . "<Version>1.0</Version>";
  $newmessage = $newmessage . "<MsgSet>ISO-EAST</MsgSet>";
  $newmessage = $newmessage . "<ProcessMode></ProcessMode>";

  #my $seqnum = &gettransid("$username");
  my $seqnum = &smpsutils::gettransid( "$username", "mercury", $orderid );
  $seqnum     = substr( "0" x 6 . $seqnum, -6, 6 );
  $newmessage = $newmessage . "<ClientRefNumber>$seqnum</ClientRefNumber>";
  $newmessage = $newmessage . "<IsPayloadBase64>1</IsPayloadBase64>";
  $newmessage = $newmessage . "<Payload>$message</Payload>";
  $newmessage = $newmessage . "</BinaryMsgReq>";

  my $destination = "";
  my $port        = "9403";
  if ( $username =~ /^(testmercury|mercurydem)/ ) {
    $destination    = "fe1.mercurydev.net";    # test
    $altdestination = "fe1.mercurydev.net";    # test
  } else {
    if ( !-e "/home/p/pay1/batchfiles/$devprod/mercury/secondary.txt" ) {
      $destination    = "fe1.mercurypay.com";    # production
      $altdestination = "63.111.40.11";          # production
    } else {

      #$destination = "fe2.backuppay.com";
      $destination    = "fe1.backuppay.com";
      $altdestination = "74.120.159.34";         # production
    }
  }

  my $dnserrorflag = "";
  my $dest_ip      = gethostbyname($destination);
  if ( $dest_ip eq "" ) {
    $destination  = $altdestination;
    $dnserrorflag = " dns error";
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
    print logfile "$destination dns error\n";
    close(logfile);
  }

  $mytime = gmtime( time() );
  my $chkmessage = $newmessage;
  $chkmessage =~ s/\<Payload\>.*<\/Payload\>/\<Payload\>...\<\/Payload\>/;
  print "$mytime send: $destination$dnserrorflag\n$chkmessage\n\n";

  print "base64: $newmessage\n";

  $response = &socketwritessl( "$destination", "$port", "/", $newmessage );
  if ( $response eq "" ) {
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
    print logfile "No response, resending transaction\n";
    close(logfile);
    $response = &socketwritessl( "$destination", "$port", "/", $newmessage );
  }

  $response =~ s/[\r\n]//g;
  $response =~ s/^.*<Payload>(.*)<\/Payload>.*$/$1/;
  $response = decode_base64("$response");

  $mytime = gmtime( time() );
  my $chkmessage = $response;

  #$chkmessage =~ s/></>\n</g;
  $chkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $chkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;

  #if ($username =~ /^(testmercury|pnpdemo)$/) {
  #  open(logfile,">>/home/p/pay1/batchfiles/$devprod/mercury/serverlogmsgtest.txt");
  #}
  #else {
  #  open(logfile,">>/home/p/pay1/batchfiles/$devprod/mercury/serverlogmsg.txt");
  #}
  #print logfile "$username  $datainfo{'order-id'}\n";
  #print logfile "$mytime recv: $chkmessage\n\n";
  print "$mytime recv: $chkmessage\n\n";

  #close(logfile);

  #&socketwrite($message);
  #my $response = &socketread();

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
  $message2 = $response;
  $message2 =~ s/([^0-9A-Za-z \n,])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] \n,])/unpack("H2",$1)/ge;
  $mytime = gmtime( time() );
  print logfile "$mytime response: $message2" . "\n";
  print "response: $message2" . "\n\n";

  #($message2) = unpack "H*", $response;
  #print logfile "response: $message2\n";
  #print logfile "\n";
  close(logfile);

  $borderid = &miscutils::incorderid($borderid);
  $borderid = substr( "0" x 12 . $borderid, -12, 12 );

  return $response;

}

sub socketopen {
  my ( $addr, $port ) = @_;
  my ( $iaddr, $paddr, $proto );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  #$iaddr = inet_aton($host);
  #my $sockaddr = sockaddr_in(0, $iaddr);
  #bind(SOCK, $sockaddr)    || die "bind: $!\n";
  connect( SOCK, $paddr ) || die "connect: $!";
}

sub socketwrite {
  ($message) = @_;

  $line = `netstat -an | grep 14133`;
  print "aaaa $line\n\n";

  send( SOCK, $message, 0, $paddr );
}

sub socketread {
  my $response;

  #print "aaaa $line\n\n";

  vec( $rin, $temp = fileno(SOCK), 1 ) = 1;
  $count    = 4;
  $response = "";
  $respdata = "";
  while ( $count && select( $rout = $rin, undef, undef, 80.0 ) ) {

    #open(logfile,">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt");
    #($d1,$d2,$temptime) = &miscutils::genorderid();
    #print logfile "while $temptime\n";
    #close(logfile);
    recv( SOCK, $response, 2048, 0 );
    print "response: $response\n\n";

    $respdata = $respdata . $response;

    ( $d1, $d2, $resplength ) = unpack "H4A4A4", $respdata;
    $resplength = $resplength + 11;

    $rlen = length($respdata);

    #open(logfile,">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt");
    #print logfile "rlen: $rlen, resplength: $resplength\n";
    #print "rlen: $rlen, resplength: $resplength\n";
    #close(logfile);

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      if ( $resplength > 17 ) {
        $response = substr( $respdata, 0, $resplength );
        return $response;
      } else {
        print "null message found\n\n";
      }
      $respdata = substr( $respdata, $resplength );

      $resplength = unpack "n", $respdata;
      $resplength = $resplength + 6;
      $rlen       = length($respdata);

      umask 0033;
      $temptime = time();
      open( outfile, ">/home/p/pay1/batchfiles/$devprod/mercury/baccesstime.txt" );
      print outfile "$temptime\n";
      close(outfile);
    }

    $count--;
  }
  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
  print logfile "no response a$response" . "b\n";
  close(logfile);
  return $response;

}

sub printrecord {
  my ( $type, $message ) = @_;

  my $len = length($message);
  $message2 = $message;
  $message2 =~ s/([^0-9A-Za-z \n,])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] \n,])/unpack("H2",$1)/ge;
  print "$type	$len: $message2" . "\n";

  #$message2 = unpack "H*", $message;
  #$message2 =~ s/(.{2})/$1 /g;
  #print "$len: $message2" . "\n";
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

sub decodebitmap {
  my ( $message, $findbit ) = @_;

  my @msgvalues   = ();
  my @bitlenarray = ();

  $bitlenarray[2]   = "LLVAR";
  $bitlenarray[3]   = 6;
  $bitlenarray[4]   = 12;
  $bitlenarray[7]   = 14;
  $bitlenarray[11]  = 6;
  $bitlenarray[12]  = 12;
  $bitlenarray[13]  = 8;
  $bitlenarray[14]  = 4;
  $bitlenarray[18]  = 4;
  $bitlenarray[22]  = "12a";
  $bitlenarray[25]  = 2;
  $bitlenarray[31]  = "LLVARa";
  $bitlenarray[32]  = "LLVAR";
  $bitlenarray[35]  = "LLVAR";
  $bitlenarray[37]  = "12a";
  $bitlenarray[38]  = "6a";
  $bitlenarray[39]  = "3a";
  $bitlenarray[41]  = 3;
  $bitlenarray[42]  = "15a";
  $bitlenarray[44]  = "LLVARa";
  $bitlenarray[45]  = "LLVARa";
  $bitlenarray[48]  = "LLLVARa";
  $bitlenarray[49]  = 3;
  $bitlenarray[52]  = 16;
  $bitlenarray[53]  = "LLVARa";
  $bitlenarray[54]  = "LLLVARa";
  $bitlenarray[56]  = "LLVARa";
  $bitlenarray[59]  = "LLLVARa";
  $bitlenarray[60]  = "LLLVAR";
  $bitlenarray[61]  = "LLLVARa";
  $bitlenarray[62]  = "LLLVARa";
  $bitlenarray[63]  = "LLLVARa";
  $bitlenarray[64]  = "8a";
  $bitlenarray[70]  = 3;
  $bitlenarray[126] = "LLLVARa";

  my $idxstart = 2;                             # bitmap start point
  my $idx      = $idxstart;
  my $bitmap1  = substr( $message, $idx, 8 );
  my $bitmap   = unpack "H16", $bitmap1;

  #print "\n\nbitmap1: $bitmap\n";
  if ( ( $findbit ne "" ) && ( $bitmap1 ne "" ) ) {
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/serverlogmsg.txt" );
    print logfile "\n\nbitmap1: $bitmap\n";
    close(logfile);
  }
  $idx = $idx + 8;

  my $end     = 1;
  my $bitmap2 = "";
  if ( $bitmap =~ /^(8|9|a|b|c|d|e|f)/ ) {
    $bitmap2 = substr( $message, $idx, 8 );
    $bitmap = unpack "H16", $bitmap2;

    #print "bitmap2: $bitmap\n";
    if ( ( $findbit ne "" ) && ( $bitmap1 ne "" ) ) {
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/serverlogmsg.txt" );
      print logfile "bitmap2: $bitmap\n";
      close(logfile);
    }
    $end = 2;
    $idx = $idx + 8;
  }

  my $myk        = 0;
  my $myj        = 0;
  my $bitnum     = 0;
  my $bitnum2    = 0;
  my $bitmaphalf = $bitmap1;
  my $wordflag   = 3;
  for ( $myj = 1 ; $myj <= $end ; $myj++ ) {
    my $bitmaphalfa = substr( $bitmaphalf, 0, 4 );
    my $bitmapa = unpack "N", $bitmaphalfa;

    my $bitmaphalfb = substr( $bitmaphalf, 4, 4 );
    my $bitmapb = unpack "N", $bitmaphalfb;

    $bitmaphalf = $bitmapa;

    while ( $idx < length($message) ) {
      my $bit = 0;
      while ( ( $bit == 0 ) && ( $bitnum <= 64 ) ) {
        if ( ( $bitnum == 33 ) || ( $bitnum == 97 ) ) {
          $bitmaphalf = $bitmapb;
        }
        if ( ( $bitnum == 33 ) || ( $bitnum == 65 ) || ( $bitnum == 97 ) ) {
          $wordflag--;
        }

        #$bit = ($bitmaphalf >> (128 - $bitnum)) % 2;
        $bit = ( $bitmaphalf >> ( 128 - ( $wordflag * 32 ) - $bitnum ) ) % 2;
        $bitnum++;
        $bitnum2++;
      }
      if ( $bitnum == 65 ) {
        last;
      }

      my $idxlen1 = $bitlenarray[ $bitnum2 - 1 ];
      my $idxlen  = $idxlen1;
      if ( $idxlen1 eq "LLVAR" ) {

        #$idxlen = substr($message,$idx,2);
        $idxlen = substr( $message, $idx, 1 );
        $idxlen = unpack "H2", $idxlen;
        $idxlen = int( ( $idxlen / 2 ) + .5 );
        $idx = $idx + 1;
      } elsif ( $idxlen1 eq "LLVARa" ) {
        $idxlen = substr( $message, $idx, 1 );
        $idxlen = unpack "H2", $idxlen;
        $idx = $idx + 1;

        #print "idxlen: $idxlen\n";
      } elsif ( $idxlen1 eq "LLLVAR" ) {
        $idxlen = substr( $message, $idx, 2 );
        $idxlen = unpack "H4", $idxlen;
        $idxlen = int( ( $idxlen / 2 ) + .5 );
        $idx = $idx + 2;
      } elsif ( $idxlen1 eq "LLLVARa" ) {
        $idxlen = substr( $message, $idx, 2 );
        $idxlen = unpack "H4", $idxlen;
        $idx = $idx + 2;
      } elsif ( $idxlen1 =~ /a/ ) {
        $idxlen =~ s/a//g;
      } else {
        $idxlen = int( ( $idxlen / 2 ) + .5 );
      }

      my $value = substr( $message, $idx, $idxlen );
      if ( $idxlen1 !~ /a/ ) {
        $value = unpack "H*", $value;
      }

      my $tmpbit = $bitnum2 - 1;

      #if ($findbit ne "") {
      #print "bit: $tmpbit  $idxlen  $value\n";
      #}
      $msgvalues[$tmpbit] = $value;
      $myk++;
      if ( $myk > 20 ) {
        print "myk 20\n";
        exit;
      }
      if ( $findbit == $bitnum - 1 ) {

        #return $idx, $value;
      }
      $idx = $idx + $idxlen;
      if ( $bitnum == 65 ) {
        last;
      }
    }
    $bitnum     = 0;
    $bitnum2    = $bitnum2 - 1;
    $bitmaphalf = $bitmap2;
  }    # end for
       #print "\n";
       #return "-1", "";

  #open(logfile,">>/home/p/pay1/batchfiles/$devprod/mercury/serverlogmsg.txt");
  #print logfile "\n\n";
  my $bitmap1str = unpack "H*", $bitmap1;
  my $bitmap2str = unpack "H*", $bitmap2;
  print "bitmap1: $bitmap1str\n";
  print "bitmap2: $bitmap2str\n";
  for ( my $i = 0 ; $i <= $#msgvalues ; $i++ ) {
    if ( $msgvalues[$i] ne "" ) {
      print "$i  $msgvalues[$i]\n";
    }
  }

  #close(logfile);

  return @msgvalues;
}

sub pidcheck {
  open( infile, "/home/p/pay1/batchfiles/$devprod/mercury/pid$group.txt" );
  $chkline = <infile>;
  chop $chkline;
  close(infile);

  if ( $pidline ne $chkline ) {
    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
    print logfile "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    print logfile "$pidline\n";
    print logfile "$chkline\n";
    close(logfile);

    print "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    print "$pidline\n";
    print "$chkline\n";

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: mercury - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

sub socketwritessl {
  my ( $host, $port, $path, $msg ) = @_;

  Net::SSLeay::load_error_strings();
  Net::SSLeay::SSLeay_add_ssl_algorithms();
  Net::SSLeay::randomize('/etc/passwd');

  my $mime_type = 'application/xml; charset="utf-8"';

  #my $mime_type = 'application/x-www-form-urlencoded';

  #$msg = "IN=" . $msg;
  my $len     = length($msg);
  my $content = "Content-Type: $mime_type\r\n" . "Content-Length: $len\r\n\r\n$msg";

  #my $req = "POST $path HTTP/1.0\r\nHost: $host\r\n" . "Accept: */*\r\n$content";
  my $req = "POST $path HTTP/1.0\r\nHost: $host:$port\r\n" . "Accept: */*\r\n$content";

  #print "send:\n$req\n";

  $dest_ip = gethostbyname($host);

  if ( $dest_ip eq "" ) {
    print "sleep 20\n";
    &miscutils::mysleep(20.0);
    $dest_ip = gethostbyname($host);
  }
  my $dest_ipaddress = Net::SSLeay::inet_ntoa($dest_ip);

  $dest_serv_params = sockaddr_in( $port, $dest_ip );

  $flag = "success";
  socket( S, &AF_INET, &SOCK_STREAM, 0 ) or return ( &errmssg( "socket: $!", 1 ) );

  $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
  print logfile "$mytime before connect  $dest_ipaddress\n";
  close(logfile);
  print "bbbb before connect  $dest_ipaddress\n";
  connect( S, $dest_serv_params ) or $flag = &retry();
  $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/$fileyear/$username$time$pid.txt" );
  print logfile "$mytime after connect  $dest_ipaddress\n";
  close(logfile);
  print "cccc after connect  $flag\n";

  if ( $flag ne "success" ) {
    return "";
  }
  select(S);
  $| = 1;
  select(STDOUT);    # Eliminate STDIO buffering

  # The network connection is now open, lets fire up SSL
  $ctx = Net::SSLeay::CTX_new() or die_now("Failed to create SSL_CTX $!");
  Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL )
    and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
  $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
  Net::SSLeay::set_fd( $ssl, fileno(S) );    # Must use fileno
  $flag = "success";
  $res = Net::SSLeay::connect($ssl) or $flag = "sslconnect: $!";

  #$res = Net::SSLeay::connect($ssl) and Net::SSLeay::die_if_ssl_error("ssl connect");
  print "dddd after sslconnect  $flag\n";
  if ( $flag ne "success" ) {
    close S;
    return "";
  }

  #open(TMPFILE,">>/home/p/pay1/logfiles/ciphers.txt");
  #print TMPFILE __FILE__ . ": " . Net::SSLeay::get_cipher($ssl) . "\n";
  #close(TMPFILE);

  # Exchange data
  $res = Net::SSLeay::ssl_write_all( $ssl, $req );    # Perl knows how long $msg is
  Net::SSLeay::die_if_ssl_error("ssl write");

  #shutdown S, 1;  # Half close --> No more output, sends EOF to server

  my $response = "";

  $got      = Net::SSLeay::read($ssl);                # Perl returns undef on failure
  $response = $response . $got;
  print "in while $got\n";

  if ( $username eq "testmercury" ) {

    #shutdown S, 1;  # Half close --> No more output, sends EOF to server
    my ( $rin, $rout, $temp );
    vec( $rin, $temp = fileno(S), 1 ) = 1;
    $count = 8;
    while ( $count && select( $rout = $rin, undef, undef, 20.0 ) ) {
      $got      = Net::SSLeay::read($ssl);            # Perl returns undef on failure
      $response = $response . $got;
      print "in while $got\n";

      #my $chkmessage = $got;
      #$chkmessage =~ s/></>\n</g;
      #$chkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
      #$chkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
      #print "recv:\n$chkmessage\n\n";

      $mytime = gmtime( time() );
      if ( $got =~ /\/BinaryMsgResp/ ) {
        last;
      }
      if ( length($got) < 1 ) {
        last;
      }
      Net::SSLeay::die_if_ssl_error("ssl read");
      $count--;
    }
    if ( $count == 1 ) {
      &errmssg("select timeout, please try again\n");
      return "";
    }
  } elsif ( $got !~ /\/BinaryMsgResp/ ) {
    my ( $rin, $rout, $temp );
    vec( $rin, $temp = fileno(S), 1 ) = 1;
    $count = 8;
    while ( $count && select( $rout = $rin, undef, undef, 20.0 ) ) {
      $got      = Net::SSLeay::read($ssl);    # Perl returns undef on failure
      $response = $response . $got;
      if ( length($got) < 1 ) {
        last;
      }
      if ( $got =~ /\/BinaryMsgResp/ ) {
        last;
      }
      Net::SSLeay::die_if_ssl_error("ssl read");
      $count--;
    }
    if ( $count == 1 ) {
      &errmssg("no response received within timeout period, please try again\n");
      return "";
    }
  }

  print "after while\n";

  Net::SSLeay::free($ssl);    # Tear down connection
  Net::SSLeay::CTX_free($ctx);
  close S;

  return $response;
}

sub retry {
  print "in retry\n";
  socket( S, &AF_INET, &SOCK_STREAM, 0 ) or return ("retry socket: $!");
  connect( S, $dest_serv_params ) or return ("retry connect: $!");

  return "success";
}

sub mercuryerror {
  my ($msg) = @_;

  #print "in mercuryerror\n";
  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/mercury/error.txt" );
  print logfile "$msg\n";
  close(logfile);
  exit;
}

