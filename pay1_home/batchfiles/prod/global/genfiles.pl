#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;
use smpsutils;
use IO::Socket;
use Socket;
use Time::Local;
use PlugNPay::Features;

$devprod = "logs";

# 2012 fall time change, to prevent genfiles from running twice
$now = time();
if ( ( $now >= 1352005200 ) && ( $now < 1352008800 ) ) {
  exit;
}

my $group = $ARGV[0];
if ( $group eq "" ) {
  exit;
}
my $printstr = "group: $group\n";
&procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

# global batch cutoff time 03:00am

if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/global/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'global/genfiles.pl $group'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: global - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

$mytime  = time();
$machine = `uname -n`;
$pid     = $$;

chop $machine;
$outfilestr = "";
$pidline    = "$mytime $$ $machine";
$outfilestr .= "$pidline\n";
&procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "pid$group.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my $chkline = &procutils::fileread( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "pid$group.txt" );
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  $printstr .= "$pidline\n";
  $printstr .= "$chkline\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: global - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

$host = "processor-host";    # Source IP address

$primaryipaddress = '64.69.201.195';    # primary server
$primaryport      = '14133';            # primary server

$secondaryipaddress = '64.27.243.6';    # secondary server
$secondaryport      = '14133';          # secondary server

$ipaddress = $primaryipaddress;
$port      = $primaryport;
$ipaddress = $secondaryipaddress;
$port      = $secondaryport;

$testipaddress = '64.69.205.190';       # test server
$testport      = '18582';               # test server

#$ipaddress = $testipaddress;
#$port = $testport;

#&socketopen("64.69.205.190","18582");         # test server
#&socketopen("206.227.211.195","14133");         # primary server old
#&socketopen("64.69.201.195","14133");         # primary server
#&socketopen("64.69.203.195","18582");         # secondary server old
#&socketopen("64.27.243.6","14133");         # secondary server

&socketopen( $ipaddress, $port );

if ( $connectflag == 0 ) {
  close(SOCK);
  &miscutils::mysleep(600.0);
  &socketopen( $ipaddress, $port );
}

if ( $connectflag == 0 ) {
  close(SOCK);
  &miscutils::mysleep(600.0);
  &socketopen( $ipaddress, $port );
}

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

my $time = time();
my ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $d8, $d9, $modtime ) = stat "/home/pay1/batchfiles/$devprod/global/genfiles$group.txt";

my $delta = $time - $modtime;

if ( $delta < ( 3600 * 12 ) ) {
  $checkuser = &procutils::fileread( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "genfiles$group.txt" );
  chop $checkuser;
}

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = " and username>='$checkuser'";
}

#$checkstring = " and username='aaaa'";
#$checkstring = " and username in ('aaaa','aaaa')";

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

if ( !-e "/home/pay1/batchfiles/$devprod/global/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/global/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/global/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/global/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/global/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/global/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/global/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/global/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/global/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/global/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: global - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/global/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batchid = $time;
$borderid = substr( "0" x 12 . $batchid, -12, 12 );

my $printstr = "jjjj\n";
&procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

my $dbquerystr = <<"dbEOM";
        select username,count(username),min(trans_date)
        from operation_log force index(oplog_tdateloptimeuname_idx)
        where trans_date>=?
    $checkstring
        and trans_date<=?
        and lastoptime>=?
        and lastopstatus='pending'
        and processor='global'
        and (accttype is NULL or accttype ='' or accttype='credit')
        group by username
dbEOM
my @dbvalues = ( "$starttransdate", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
  my $printstr = "$user\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );
}

foreach $username ( sort @userarray ) {
  if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/global/stopgenfiles.txt" ) ) {
    unlink "/home/pay1/batchfiles/$devprod/global/batchfile.txt";
    last;
  }

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "genfiles$group.txt", "write", "", $batchfilestr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  my $printstr = "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  if ( $username eq "randalloak1" ) {
    $batchcntuser = 998;
  } elsif ( $usercountarray{$username} > 2000 ) {
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

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,features,switchtime
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $status, $features, $switchtime ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
        select bankid,industrycode,capabilities,batchtime
        from global
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $bankid, $industrycode, $capabilities, $batchgroup ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $status ne "live" ) {
    next;
  }

  if ( ( $group eq "1" ) && ( $batchgroup ne "1" ) ) {
    next;
  } elsif ( ( $group eq "0" ) && ( $batchgroup ne "" ) ) {
    next;
  } elsif ( $group !~ /^(0|1)$/ ) {
    next;
  }

  # sweeptime
  my %feature = ();
  if ( $features ne "" ) {
    my @array = split( /\,/, $features );
    foreach my $entry (@array) {
      my ( $name, $value ) = split( /\=/, $entry );
      $feature{$name} = $value;
    }
  }
  my $printstr = "features old: " . $feature{"batchcnt"} . "  " . $feature{"sweeptime"} . "\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  my $accountFeatures = new PlugNPay::Features( "$username", 'general' );
  $feature{"batchcnt"}  = $accountFeatures->get('batchcnt');
  $feature{"sweeptime"} = $accountFeatures->get('sweeptime');
  $features             = "batchcnt: $feature{'batchcnt'},  sweeptime: $feature{'sweeptime'}\n";

  my $printstr = "features new: " . $feature{"batchcnt"} . "  " . $feature{"sweeptime"} . "\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  if ( $feature{"batchcnt"} > 100 ) {
    $batchcntuser = $feature{"batchcnt"};
  }

  # sweeptime
  $sweeptime = $feature{'sweeptime'};    # sweeptime=1:EST:19   dstflag:timezone:time
  my $printstr = "sweeptime: $sweeptime\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    if ( ( $dstflag !~ /0|1/ ) || ( $timezone !~ /EST|CST|PST/ ) || ( $settlehour > 23 ) ) {
      $sweeptime = "";
    }
  }
  $justwantthehour = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );

    $settletime = sprintf( "%08d%02d%04d", substr( $todaytime, 0, 8 ), $settlehour, "0000" );    # need a valid time to get the hour in GMT
    $justwantthehour = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    $justwantthehour = substr( $justwantthehour, 8, 2 );                                         # just use the GMT hour
    $settletime = sprintf( "%08d%02d%04d", substr( $todaytime, 0, 8 ), $justwantthehour, "0000" );

    if ( $settletime > $todaytime ) {

      # subtract one day from settletime
      my $yr = substr( $settletime, 0, 4 );
      my $mn = substr( $settletime, 4, 2 );
      my $dy = substr( $settletime, 6, 2 );
      my $hr = substr( $settletime, 8, 2 );
      my $printstr = "yr: $yr\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );
      $dy = $dy - 1;
      if ( $dy == 0 ) {
        $mn = $mn - 1;
        if ( $mn == 0 ) {
          $yr = $yr - 1;
          $mn = 12;
        }
        if ( ( $mn == 2 ) && ( $yr % 4 == 0 ) ) {
          $dy = "29";
        } elsif ( $mn == 2 ) {
          $dy = "28";
        } elsif ( ( $mn == 6 ) || ( $mn == 9 ) || ( $mn == 4 ) || ( $mn == 11 ) ) {
          $dy = "30";
        } else {
          $dy = "31";
        }
      }
      $sweeptime = sprintf( "%04d%02d%02d%02d%04d", $yr, $mn, $dy, $hr, "0000" );
    } else {
      $sweeptime = $settletime;
    }

    my $printstr = "settlehour $timezone: $settlehour\n";
    $printstr .= "settlehour GMT: $justwantthehour\n";
    $printstr .= "sweeptime GMT: $sweeptime\n";
    $printstr .= "todaytime GMT: $todaytime\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  }

  #
  #  print "gmt today: $todaytime\n";
  #  print "est today: $esttime\n";
  #  print "est yesterday: $yesterday\n";
  #  print "settletime: $settletime\n";
  #  print "sweeptime: $sweeptime\n";

  umask 0077;
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  $logfilestr = "";
  $logfilestr .= "$features\n";
  $logfilestr .= "$username  sweeptime GMT: $sweeptime  todaytime GMT: $todaytime  settlehour GMT: $justwantthehour\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  &pidcheck();

  $chkconnectionflag = 1;

  $batch_flag = 1;

  my $dbquerystr = <<"dbEOM";
          select orderid
          from operation_log
          where trans_date>=?
          and trans_date<=?
          and lastoptime>=?
          and username=?
          and lastop in ('postauth','return')
          and lastopstatus='pending'
          and processor='global'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$starttransdate", "$today", "$onemonthsagotime", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  %orderidarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 1 ) {
    ($orderid) = @sthtransvalarray[ $vali .. $vali + 0 ];

    $orderidarray{"$orderid"} = 1;
  }

  $detailcnt   = 0;
  @detailarray = ();
  @oidarray    = ();
  ( $d1, $d2, $filename ) = &miscutils::genorderid();

  foreach $orderid ( sort keys %orderidarray ) {

    my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,transflags,refnumber,lastopstatus,cvvresp,reauthstatus
          from operation_log
          where orderid=?
          and username=?
          and trans_date>=?
          and trans_date<=?
          and lastoptime>=?
          and lastop in ('postauth','return')
          and lastopstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
          order by orderid
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$starttransdate", "$today", "$onemonthsagotime" );
    ( $orderid, $operation, $trans_date, $trans_time, $enccardnumber, $enclength, $exp, $amount, $auth_code, $avs_code, $transflags, $refnumber, $finalstatus, $cvvresp, $reauthstatus ) =
      &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/global/stopgenfiles.txt" ) ) {
      unlink "/home/pay1/batchfiles/$devprod/global/batchfile.txt";
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

    $orderidold = $orderid;

    if ( ( $sweeptime ne "" ) && ( $trans_time > $sweeptime ) ) {
      $orderidold = $orderid;
      next;    # transaction is newer than sweeptime
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "global", $enccardnumber );

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
    my $dbquerystr = <<"dbEOM";
          select authtime,authstatus,forceauthtime,forceauthstatus,origamount
          from operation_log
          where orderid=?
          and lastoptime>=?
          and username=?
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$onemonthsagotime", "$username" );
    ( $authtime, $authstatus, $forceauthtime, $forceauthstatus, $origamount ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

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

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='locked',result=?
	    where orderid=?
	    and username=?
	    and finalstatus='pending'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$filename", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending'
          where orderid=?
          and username=?
          and $operationstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$filename", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

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
      ( $d1, $d2, $filename ) = &miscutils::genorderid();
      if ( $batcherrorflag == 1 ) {
        last;    # if batch error move on to next username
      }
    }
  }

  if ( ( ( $detailcnt >= 1 ) || ( $datasentflag == 1 ) ) && ( $socketerrorflag == 0 ) ) {
    &endbatch();
    $nomoredata   = 0;
    $batch_flag   = 1;
    $batchcnt     = 0;
    $datasentflag = 0;
  }

  if ( ( $socketerrorflag == 1 ) || ( $headererrorflagx == 1 ) ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='pending'
	    where trans_date>=?
            and trans_date<=?
	    and username=?
	    and finalstatus='locked'
	    and result=?
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$onemonthsago", "$today", "$username", "$filename" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where trans_date>=?
            and trans_date<=?
        and lastoptime>=?
            and username=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$starttransdate", "$today", "$onemonthsagotime", "$username", "$filename" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where trans_date>=?
            and trans_date<=?
        and lastoptime>=?
            and username=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$starttransdate", "$today", "$onemonthsagotime", "$username", "$filename" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  }

  ( $d1, $d2, $filename ) = &miscutils::genorderid();

  if ( $socketerrorflag == 1 ) {
    close(SOCK);
    &miscutils::mysleep(600.0);

    #&socketopen("64.69.201.195","14133");         # primary server
    #&socketopen("64.27.243.6","14133");         # secondary server
    &socketopen( $ipaddress, $port );
  }
}
close(SOCK);

#$sth->finish;

unlink "/home/pay1/batchfiles/$devprod/global/batchfile.txt";

umask 0033;
$batchfilestr = "";
&procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "genfiles$group.txt", "write", "", $batchfilestr );

exit;

sub mysleep {
  for ( $myi = 0 ; $myi <= 60 ; $myi++ ) {
    umask 0033;
    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "baccesstime.txt", "write", "", $outfilestr );

    select undef, undef, undef, 60.00;
  }
}

sub senderrmail {
  my ($message) = @_;

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: global - batch problem\n";
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
  $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

  $datasentflag = 1;

  $commcardtype = substr( $auth_code, 16, 1 );
  my $printstr = "aaaa $orderid  $commcardtype\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

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

  $debitflag = substr( $auth_code, 221, 1 );

  $cashbackind = substr( $auth_code, 222, 1 );
  if ( $debitflag == 1 ) {

    # debit card
    $avs = $avs_code;
    $avs =~ s/ //g;

    my $proc1   = "";
    my $proc2   = "";
    my $newproc = "";

    if ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
      $proc1 = '18';    # force
    } elsif ( ( $operation eq "postauth" ) && ( $cashback ne "" ) ) {
      $proc1 = '09';    # cashback
    } elsif ( $operation eq "return" ) {
      $proc1 = '20';    # return
    } elsif (
      ( ( $transflags =~ /recurring/ ) && ( $card_type =~ /^(vi|mc|ax|ds)$/ ) )
      || ( ( $industrycode =~ /(retail|restaurant)/ )
        && ( $transflags !~ /moto/ ) )
      ) {
      $proc1 = '00';    # recurring or retail
    } elsif ( $industrycode eq "restaurant" ) {
      $proc1 = '00';    # recurring or retail
    } else {
      $proc1 = '17';    # normal ecommerce - avs included and keyed retail w/avs
    }

    if ( ( $debitflag == 1 ) && ( $accttype =~ /savings/ ) ) {
      $proc2 = '10';    # debit savings canada
    } elsif ( $transflags =~ /ebtcash/ ) {
      $proc2 = '96';    # ebt
    } elsif ( ( $debitflag == 1 ) && ( $accttype =~ /checking/ ) ) {
      $proc2 = '20';    # debit checking canada
    } elsif ( $debitflag == 1 ) {
      $proc2 = '00';    # debit
    } elsif ( $commcardtype eq "1" ) {
      $proc2 = '40';    # commercial
    } else {
      $proc2 = '30';    # credit
    }

    my $proc3 = "50";
    if ( ( $operation eq "reauth" ) && ( $transflags =~ /over/ ) ) {
      $proc3 = "10";    # override
    }

    $tcode = $proc1 . $proc2 . $proc3;    # processing code  50 = no duplicate checking (6a)

    $bd[0] = $tcode;                      # processing code (6an)

    if ( $posentry ne "" ) {              # to be certified
      $bd[1] = $posentry;
    } elsif ( $industrycode =~ /retail|restaurant/ ) {
      $posentry = '200100602000';         # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      if ( $capabilities =~ /debit/ ) {
        $posentry = substr( $posentry, 0, 1 ) . '1' . substr( $posentry, 2 );
      }
      if ( ( $capabilities =~ /partial/ ) || ( $transflags =~ /partial/ ) ) {
        $posentry = substr( $posentry, 0, 8 ) . '1' . substr( $posentry, 9 );
      }
      $bd[1] = $posentry;                 # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
    } else {
      if ( ( $transflags =~ /recurring/ ) && ( $card_type =~ /^(vi|mc|ax|ds)/ ) ) {
        $posentry = '600140622000';       # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      } elsif ( ( $origoperation eq "forceauth" ) || ( $operation eq "return" ) || ( $transflags =~ /moto/ ) ) {
        $posentry = '600110612000';       # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      } else {
        $posentry = '600550672000';       # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
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
    if ( $reportdata eq "" ) {
      $reportdata = substr( $auth_code, 166, 25 );    # the old way
      $reportdata =~ s/^.*,,,//;
      $reportdata =~ s/ +$//;
    }
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

    my $proc1 = "";
    my $proc2 = "";

    if ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
      $proc1 = '18';    # force
    } elsif ( ( $operation eq "postauth" ) && ( $cashback ne "" ) ) {
      $proc1 = '09';    # cashback
    } elsif ( $operation eq "return" ) {
      $proc1 = '20';    # return
    } elsif (
      ( ( $transflags =~ /recurring/ ) && ( $card_type =~ /^(vi|mc|ax|ds)$/ ) )
      || ( ( $industrycode =~ /(retail|restaurant)/ )
        && ( $transflags !~ /moto/ ) )
      ) {
      $proc1 = '00';    # recurring or retail
    } elsif ( $industrycode eq "restaurant" ) {
      $proc1 = '00';    # recurring or retail
    } else {
      $proc1 = '17';    # normal ecommerce - avs included and keyed retail w/avs
    }

    if ( ( $debitflag == 1 ) && ( $accttype =~ /savings/ ) ) {
      $proc2 = '10';    # debit savings canada
    } elsif ( $transflags =~ /ebtcash/ ) {
      $proc2 = '96';    # ebt
    } elsif ( ( $debitflag == 1 ) && ( $accttype =~ /checking/ ) ) {
      $proc2 = '20';    # debit checking canada
    } elsif ( $debitflag == 1 ) {
      $proc2 = '00';    # debit
    } elsif ( $commcardtype eq "1" ) {
      $proc2 = '40';    # commercial
    } else {
      $proc2 = '30';    # credit
    }

    my $proc3 = "50";
    if ( ( $operation eq "reauth" ) && ( $transflags =~ /over/ ) ) {
      $proc3 = "10";    # override
    }

    $tcode = $proc1 . $proc2 . $proc3;    # processing code  50 = no duplicate checking (6a)

    $bd[0] = $tcode;                      # processing code (6an)

    # begin temporary because global has a bug with mc UCAF on settlement
    $cavvresp = substr( $auth_code, 102, 1 );
    $cavvresp =~ s/ //g;
    if ( ( $card_type eq "mc" ) && ( $cavvresp eq "x" ) && ( $operation eq "postauth" ) ) {
      $posentry = '600550671000';         # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      $bd[1] = $posentry;
    }    # end of temporary stuff
    elsif ( $posentry ne "" ) {    # to be certified
      $bd[1] = $posentry;
    } elsif ( $industrycode =~ /retail|restaurant/ ) {
      $posentry = '200100602000';    # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      if ( $capabilities =~ /debit/ ) {
        $posentry = substr( $posentry, 0, 1 ) . '1' . substr( $posentry, 2 );
      }
      if ( ( $capabilities =~ /partial/ ) || ( $transflags =~ /partial/ ) ) {
        $posentry = substr( $posentry, 0, 8 ) . '1' . substr( $posentry, 9 );
      }
      $bd[1] = $posentry;            # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
    } else {
      if ( ( $transflags =~ /recurring/ ) && ( $card_type =~ /^(vi|mc|ax|ds)/ ) ) {
        $posentry = '600140622000';    # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      } elsif ( ( $origoperation eq "forceauth" ) || ( $operation eq "return" ) || ( $transflags =~ /moto/ ) ) {
        $posentry = '600110612000';    # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
      } else {
        $posentry = '600550672000';    # POS entry mode 1..2 = recurring, 3..1 = moto, 5..7 = ecom(12a)
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
    if ( $reportdata eq "" ) {
      $reportdata = substr( $auth_code, 166, 25 );    # the old way
      $reportdata =~ s/^.*,,,//;
      $reportdata =~ s/ +$//;
    }
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
      $bd[21] = $cavvresp;    # cavv result (1an)
    }
    $bd[22] = "";             # blank

    $surcharge = substr( $auth_code, 231, 8 );
    $surcharge =~ s/ //g;
    if ( ( $surcharge ne "" ) && ( $surcharge ne "00000000" ) ) {
      $surcharge = substr( "0" x 9 . $surcharge, -9, 9 );
    } else {
      $surcharge = "";
    }
    $bd[23] = $surcharge;     # surcharge future (9an)
  }

  $details = "";
  foreach $var (@bd) {
    $details = $details . $var . ",";
  }
  chop $details;
  $fs                      = pack "H2", "1C";
  $details                 = $details . "$fs";
  $detailarray[$detailcnt] = $details;
  $oidarray[$detailcnt]    = $orderid;

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
  $addtl[2] = "H1X";                          # terminal type H1X
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

  #$bt[7] = pack "H4H$len",$len,$addtldata;	# global ecom addtl data (ANS999) LLLVAR
  $bt[7] = pack "H4", $len;    # global ecom addtl data (ANS999) LLLVAR
  $bt[8] = $addtldata;         # global ecom addtl data (ANS999) LLLVAR

  $message = "";
  foreach $var (@bt) {
    $message = $message . $var;
  }

  $len     = length($message);
  $len     = substr( "0000" . $len, -4, 4 );
  $header  = pack "H4A4A4", "0101", "    ", $len;
  $trailer = pack "H2", "03";

  $message = $header . $message . $trailer;
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
  $addtl[2] = "H1X";             # terminal type H1X
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
  @globaladdtl = ();
  $globaladdtl[0] = pack "H4", $len;    # global ecom addtl data (ANS999) LLLVAR
  $globaladdtl[1] = $addtldata;         # global ecom addtl data (ANS999) LLLVAR
  foreach $var (@globaladdtl) {
    $message = $message . $var;
  }

  $len     = length($message);
  $len     = substr( "0000" . $len, -4, 4 );
  $header  = pack "H4A4A4", "0101", "    ", $len;
  $trailer = pack "H2", "03";

  $message = $header . $message . $trailer;
  &printrecord( "batchmessage", "$message" );

}

sub endbatch {
  my $printstr = "detailcnt: $detailcnt\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  # yyyy
  my $printstr = "fileheader\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  &fileheader();

  $response = &sendrecord($message);

  my (@msgvalues) = &decodebitmap($response);

  $tracenum = $msgvalues[11];
  $batchnum = $msgvalues[12];
  $pass     = $msgvalues[39];
  $rmessage = $msgvalues[44];
  ($rmessage) = split( /1c/, $rmessage );

  #$rmessage = pack "H*", $rmessage;

  my $printstr = "new data:\n";
  $printstr .= "tracenum: $tracenum\n";
  $printstr .= "batchnum: $batchnum\n";
  $printstr .= "pass: $pass\n";
  $printstr .= "rmessage: $rmessage\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  ( $d1, $d2, $len, $messid, $bitmap, $pcode, $restofdata ) = unpack "H4A4A4H4H16H6H*", $response;

  my $printstr = "$pass $rmessage\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );
  if ( $pass ne "000" ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "header pass: $pass\n";
    $logfilestr .= "rmessage: $rmessage\n\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "bad batch\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );
    $batcherrorflag  = 1;
    $headererrorflag = 1;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: barbara\@plugnpay.com\n";
    print MAILERR "Cc: michelle\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: global - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Problem with genfiles header.\n";
    print MAILERR "username: $username\n";
    print MAILERR "rmessage: $pass: $rmessage\n";
    close MAILERR;

    if ( $rmessage =~ /^(INVLD MERCH ID|INVLD TRAN CODE|UNAUTH TRANS)/ ) {
      return;
    }
    if ( $response eq "" ) {
      close(SOCK);

      $myerrorcnt++;
      if ( $myerrorcnt > 4 ) {
        exit;
      }

      &miscutils::mysleep(600.0);

      #&socketopen("64.69.201.195","14133");         # primary server
      #&socketopen("64.27.243.6","14133");         # secondary server
      &socketopen( $ipaddress, $port );
    }
    exit;

  }

  my $i;
  $batchcnt = 0;
  for ( $i = 0 ; $i < $detailcnt ; $i++ ) {
    if ( ( $i % 3 == 0 ) && ( $i > 0 ) ) {
      my $printstr = "batchtrailer()\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

      $batchcnt++;
      &batchtrailer();
      $response = &sendrecord($message);
      chop $orderidstr;
      &processresponse();
      if ( $batcherrorflag == 1 ) {
        last;
      }
      $batchid = &miscutils::incorderid($batchid);
    }

    if ( $i % 3 == 0 ) {
      if ( $i >= $detailcnt - 3 ) {
        my $printstr = "nomoredata\n";
        &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );
        $nomoredata = 1;
      }
      $detailmsg  = "";
      $orderidstr = "";

      my $printstr = "batchheader()\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

      &batchheader();
    }

    my $printstr = "detail\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

    $detailmsg  = $detailmsg . $detailarray[$i];
    $orderidstr = $orderidstr . "'$oidarray[$i]',";

    if ( $i == $detailcnt - 1 ) {
      my $printstr = "batchtrailer()\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );
      $batchcnt++;
      &batchtrailer();
      $response = &sendrecord($message);
      chop $orderidstr;
      &processresponse();
      $batchid = &miscutils::incorderid($batchid);
    }
  }
  @detailarray = ();
  @oidarray    = ();
}

sub processresponse {
  my (@msgvalues) = &decodebitmap($response);

  $tracenum = $msgvalues[11];
  $batchnum = $msgvalues[12];
  $pass     = $msgvalues[39];
  $rmessage = $msgvalues[44];
  ($rmessage) = split( /1c/, $rmessage );

  #$rmessage = pack "H*", $rmessage;

  my $printstr = "new data:\n";
  $printstr .= "tracenum: $tracenum\n";
  $printstr .= "batchnum: $batchnum\n";
  $printstr .= "pass: $pass\n";
  $printstr .= "rmessage: $rmessage\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  ( $d1, $d2, $len, $messid, $bitmap, $pcode, $restofdata ) = unpack "H4A4A4H4H16H6H*", $response;

  my ( $d1, $d2, $batchtime ) = &miscutils::genorderid();

  if ( $pass eq "000" ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?
	    where orderid in ($orderidstr)
	    and username=?
	    and trans_date>=?
            and trans_date<=?
	    and result=?
	    and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$batchtime", "$username", "$onemonthsago", "$today", "$filename" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
	    where orderid in ($orderidstr)
            and trans_date>=?
            and trans_date<=?
        and lastoptime>=?
            and batchfile=?
            and username=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$batchtime", "$batchtime", "$starttransdate", "$today", "$onemonthsagotime", "$filename", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
	    where orderid in ($orderidstr)
            and trans_date>=?
            and trans_date<=?
        and lastoptime>=?
            and batchfile=?
            and username=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$batchtime", "$batchtime", "$starttransdate", "$today", "$onemonthsagotime", "$filename", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  } else {
    if (0) {
      my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem'
	    where orderid in ($orderidstr)
	    and username=?
	    and trans_date>=?
	    and finalstatus='locked'
	    and result=?
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$username", "$onemonthsago", "$filename" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?
	    where orderid in ($orderidstr)
            and batchfile=?
            and username=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "", "$filename", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='problem',lastopstatus='problem',descr=?
	    where orderid in ($orderidstr)
            and batchfile=?
            and username=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "", "$filename", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Batch Problem: $pass $rmessage\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    if ( $response eq "" ) {
      close(SOCK);

      $myerrorcnt++;
      if ( $myerrorcnt > 4 ) {
        exit;
      }

      &miscutils::mysleep(600.0);

      #&socketopen("64.69.201.195","14133");         # primary server
      #&socketopen("64.27.243.6","14133");         # secondary server
      &socketopen( $ipaddress, $port );
    }

    $batcherrorflag = 1;
  }
}

sub sendrecord {
  my ($message) = @_;

  umask 0077;
  $message2 = $message;
  $message3 = substr( $message2, 65 );
  (@fields) = split( /,/, $message3 );
  if ( ( length( $fields[2] ) >= 13 ) && ( length( $fields[2] ) <= 19 ) ) {
    $xs = "x" x length( $fields[2] );
    $message2 =~ s/$fields[2]/$xs/;
  }
  if ( ( length( $fields[25] ) >= 13 ) && ( length( $fields[25] ) <= 19 ) ) {
    $xs = "x" x length( $fields[25] );
    $message2 =~ s/$fields[25]/$xs/;
  }
  if ( ( length( $fields[48] ) >= 13 ) && ( length( $fields[48] ) <= 19 ) ) {
    $xs = "x" x length( $fields[48] );
    $message2 =~ s/$fields[48]/$xs/;
  }
  $message2 =~ s/([^0-9A-Za-z \n,])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] \n,])/unpack("H2",$1)/ge;

  $logfilestr = "";
  $logfilestr .= "send: $message2" . "\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  &socketwrite($message);
  my $response = &socketread();

  umask 0077;
  $message2 = $response;
  $message2 =~ s/([^0-9A-Za-z \n,])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] \n,])/unpack("H2",$1)/ge;

  $logfilestr = "";
  $logfilestr .= "recv: $message2" . "\n\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  $borderid = &miscutils::incorderid($borderid);
  $borderid = substr( "0" x 12 . $borderid, -12, 12 );

  return $response;
}

sub socketopen {
  my ( $addr, $port ) = @_;
  my ( $iaddr, $paddr, $proto );

  $connectflag = 0;

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  #$iaddr = inet_aton($host);
  #my $sockaddr = sockaddr_in(0, $iaddr);
  #bind(SOCK, $sockaddr)    || die "bind: $!\n";
  connect( SOCK, $paddr ) or return "connect: $!";

  $socketopenflag = 1;

  $sockaddr    = getsockname(SOCK);
  $sockaddrlen = length($sockaddr);
  if ( $sockaddrlen == 16 ) {
    ($sockaddrport) = unpack_sockaddr_in($sockaddr);
  } else {
    $socketopenflag = 0;
    select undef, undef, undef, 5.00;
  }

  $connectflag = 1;
}

sub socketwrite {
  ($message) = @_;

  $line = `netstat -an | grep 14133`;
  my $printstr = "aaaa $line\n\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  if ( $chkconnectionflag == 1 ) {
    $chkconnectionflag = 0;

    my $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
    if ( $socketcnt < 1 ) {
      my $printstr = "socketcnt < 1\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

      shutdown SOCK, 2;
      close(SOCK);

      &socketopen( "$ipaddress", "$port" );
    }
  }

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

    #open(logfile,">>/home/pay1/batchfiles/$devprod/global/$fileyear/$username$time$pid.txt");
    #($d1,$d2,$temptime) = &miscutils::genorderid();
    #print logfile "while $temptime\n";
    #close(logfile);
    recv( SOCK, $response, 2048, 0 );

    $respdata = $respdata . $response;

    ( $d1, $d2, $resplength ) = unpack "H4A4A4", $respdata;
    $resplength = $resplength + 11;

    $rlen = length($respdata);

    #open(logfile,">>/home/pay1/batchfiles/$devprod/global/$fileyear/$username$time$pid.txt");
    #print logfile "rlen: $rlen, resplength: $resplength\n";
    #print "rlen: $rlen, resplength: $resplength\n";
    #close(logfile);

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      if ( $resplength > 17 ) {
        $response = substr( $respdata, 0, $resplength );
        return $response;
      } else {
        my $printstr = "null message found\n\n";
        &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );
      }
      $respdata = substr( $respdata, $resplength );

      $resplength = unpack "n", $respdata;
      $resplength = $resplength + 6;
      $rlen       = length($respdata);

      umask 0033;
      $temptime   = time();
      $outfilestr = "";
      $outfilestr .= "$temptime\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "baccesstime.txt", "write", "", $outfilestr );
    }

    $count--;
  }
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "no response a$response" . "b\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  return $response;

}

sub printrecord {
  my ( $type, $message ) = @_;

  my $len = length($message);
  $message2 = $message;
  $message2 =~ s/([^0-9A-Za-z \n,])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] \n,])/unpack("H2",$1)/ge;
  my $printstr = "$type	$len: $message2" . "\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  #$message2 = unpack "H*", $message;
  #$message2 =~ s/(.{2})/$1 /g;
  #print "$len: $message2" . "\n";
}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  my $printstr = "origtime: $origtime $timezone1\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

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

  my $printstr = "The $times1 Sunday of month $month1 happens on the $mday1\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month2 happens on wday $wday\n";

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $printstr = "The $times2 Sunday of month $month2 happens on the $mday2\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

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

  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  my $printstr = "zoneadjust: $zoneadjust\n";
  $printstr .= "newtime: $newtime $timezone2\n\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );
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

  my $idxstart = 12;                            # bitmap start point
  my $idx      = $idxstart;
  my $bitmap1  = substr( $message, $idx, 8 );
  my $bitmap   = unpack "H16", $bitmap1;

  #print "\n\nbitmap1: $bitmap\n";
  if ( ( $findbit ne "" ) && ( $bitmap1 ne "" ) ) {
    $logfilestr = "";
    $logfilestr .= "\n\nbitmap1: $bitmap\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );
  }
  $idx = $idx + 8;

  my $end     = 1;
  my $bitmap2 = "";
  if ( $bitmap =~ /^(8|9|a|b|c|d|e|f)/ ) {
    $bitmap2 = substr( $message, $idx, 8 );
    $bitmap = unpack "H16", $bitmap2;

    #print "bitmap2: $bitmap\n";
    if ( ( $findbit ne "" ) && ( $bitmap1 ne "" ) ) {
      $logfilestr = "";
      $logfilestr .= "bitmap2: $bitmap\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );
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
        my $printstr = "myk 20\n";
        &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );
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

  my $bitmap1str = unpack "H*", $bitmap1;
  my $bitmap2str = unpack "H*", $bitmap2;

  #my $printstr = "bitmap1: $bitmap1str\n";
  #$printstr .= "bitmap2: $bitmap2str\n";
  #for (my $i=0; $i<=$#msgvalues; $i++) {
  #  if ($msgvalues[$i] ne "") {
  #    $printstr .= "$i  $msgvalues[$i]\n";
  #  }
  #}
  #&procutils::filewrite("$username","global","/home/pay1/batchfiles/devlogs/global","miscdebug.txt","append","misc",$printstr);

  return @msgvalues;
}

sub pidcheck {
  my $chkline = &procutils::fileread( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "pid$group.txt" );
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    $printstr .= "$pidline\n";
    $printstr .= "$chkline\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: global - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

return;

