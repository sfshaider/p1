#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;
use smpsutils;
use Time::Local;
use Time::HiRes;
use Sys::Hostname;

$devprod = "logs";

# this is ready for live use  4/25/2017

# batch cutoff times at 3:00am, 7:00am, noon, 3:00pm, 6:00pm, 10:00pm

# FD MS version 1.8

# 2017 fall time change, to prevent genfiles from running twice
# exit if time is between 6am gmt and 7am gmt
my $timechange = "20171105020000";    # 2am eastern on the morning of the time change

my $str6am  = $timechange + 40000;                 # str represents 6am gmt
my $str7am  = $timechange + 50000;                 # str represents 7am gmt
my $time6am = &miscutils::strtotime("$str6am");    # 6am gmt
my $time7am = &miscutils::strtotime("$str7am");    # 7am gmt
my $now     = time();

if ( ( $now >= $time6am ) && ( $now < $time7am ) ) {
  my $printstr = "exiting due to fall time change\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  exit;
}

my $group = $ARGV[0];
if ( $group eq "" ) {
  $group = "0";
}
my $printstr = "group: $group\n";
&procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

if ( ( -e "/home/pay1/batchfiles/logs/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/logs/fdms/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdms/genfiles.pl $group'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  exit;
}

$mytime  = time();
$machine = `uname -n`;
$pid     = $$;

chop $machine;
$outfilestr = "";
$pidline    = "$mytime $$ $machine";
$outfilestr .= "$pidline\n";
&procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "pid$group.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my $chkline = &procutils::fileread( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "pid$group.txt" );
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "$pidline\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "$chkline\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: FDMS - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

$time = time();
( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $d8, $d9, $modtime ) = stat "/home/pay1/batchfiles/$devprod/fdms/genfiles$group.txt";

$delta = $time - $modtime;

if ( $delta < ( 3600 * 12 ) ) {
  $checkuser = &procutils::fileread( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "genfiles$group.txt" );
  chop $checkuser;

}

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>='$checkuser'";
}

( $dummy, $today, $todaytime ) = &miscutils::genorderid();

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/fdms/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdms/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdms/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdms/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdms/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdms/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdms/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdms/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdms/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdms/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdms - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory fdms/$devprod/$fileyear.\n\n";
  close MAILERR;
  exit;
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

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 180 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 180 ) );
$sixmonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $batchid, $today, $time ) = &miscutils::genorderid();
$batchid = $time;

$bpid  = substr( "0" x 5 . $pid, -5, 5 );
$btime = substr( $time,          6,  6 );
$borderid = $bpid . $btime;
$borderid = substr( "0" x 12 . $borderid, -12, 12 );

my $printstr = "aaaa $onemonthsago  $onemonthsagotime  $sixmonthsago\n";
&procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

# xxxx
my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        $checkstring
        and t.finalstatus in ('pending','locked')
        and (t.accttype is NULL or t.accttype='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastoptime>=?
        and o.trans_date>=?
        and o.lastopstatus in ('pending','locked')
        and o.processor='fdms'
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$onemonthsagotime", "$sixmonthsago" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  $userarray[ ++$#userarray ] = "$user";
  $usercountarray{$user}      = $usercount;
  $starttdatearray{$user}     = $usertdate;
}

$redoflag = 0;
foreach $username ( sort @userarray ) {

  &processbatch();
}

$redocnt  = 0;
$redoflag = 1;
foreach $username ( sort @redoarray ) {
  $redocnt++;
  if ( $redocnt > 7 ) {
    last;
  }
  &processbatch();
}

unlink "/home/pay1/batchfiles/$devprod/fdms/batchfile.txt";

if ( ( !-e "/home/pay1/batchfiles/stopgenfiles.txt" ) && ( !-e "/home/pay1/batchfiles/logs/fdms/stopgenfiles.txt" ) && ( $socketerrorflag == 0 ) ) {
  umask 0033;
  $checkinstr = "";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "genfiles$group.txt", "write", "", $checkinstr );
}

exit;

sub pidcheck {
  my $chkline = &procutils::fileread( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "pid$group.txt" );
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
    my $printstr = "$pidline\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
    my $printstr = "$chkline\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: FDMS - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

sub processbatch {
  if ( ( -e "/home/pay1/batchfiles/logs/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/logs/fdms/stopgenfiles.txt" ) ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "stopgenfiles\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    unlink "/home/pay1/batchfiles/$devprod/fdms/batchfile.txt";
    last;
  }

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  if ( $usercountarray{$username} > 2000 ) {
    $batchcntuser = 900;
  } elsif ( $usercountarray{$username} > 1000 ) {
    $batchcntuser = 500;
  } elsif ( $usercountarray{$username} > 600 ) {
    $batchcntuser = 200;
  } elsif ( $usercountarray{$username} > 300 ) {
    $batchcntuser = 200;
  } else {
    $batchcntuser = 200;
  }

  if ( $username =~
    /^(clarkctrec|clarkctweb|clarkshoot|lakewilbur|lakewashin|lakelinkre|lakecultur|lakeonline|lakeherita|lakecommre|lakehomest|lakegreenm|lakefoxhol|lakeclemen|lakecharle|lakecarmod|lakebearcr|lakepublic|cityclerko)$/
    ) {
    $batchcntuser = 900;
  }

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,switchtime,features
        from customers
        where username=?
        and processor='fdms'
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $status, $switchtime, $features ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
        select batchtime,industrycode
        from fdms
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $batchgroup, $industrycode ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $status ne "live" ) {
    next;
  }

  if ( ( $group eq "9" ) && ( $batchgroup ne "9" ) ) {
    next;
  } elsif ( ( $group eq "8" ) && ( $batchgroup ne "8" ) ) {
    next;
  } elsif ( ( $group eq "7" ) && ( $batchgroup ne "7" ) ) {
    next;
  } elsif ( ( $group eq "6" ) && ( $batchgroup ne "6" ) ) {
    next;
  } elsif ( ( $group eq "5" ) && ( $batchgroup ne "5" ) ) {
    next;
  } elsif ( ( $group eq "4" ) && ( $batchgroup ne "4" ) ) {
    next;
  } elsif ( ( $group eq "3" ) && ( $batchgroup ne "3" ) ) {
    next;
  } elsif ( ( $group eq "2" ) && ( $batchgroup ne "2" ) ) {
    next;
  } elsif ( ( $group eq "1" ) && ( $batchgroup ne "1" ) ) {
    next;
  } elsif ( ( $group eq "0" ) && ( $batchgroup ne "" ) ) {
    next;
  } elsif ( $group !~ /^(0|1|2|3|4|5|6|7|8|9)$/ ) {
    next;
  }

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "genfiles$group.txt", "write", "", $checkinstr );

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
  my $printstr = "sweeptime: $sweeptime\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  my $printstr = "gmt today: $todaytime\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "est today: $esttime\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "est yesterday: $yesterday\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "settletime: $settletime\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "sweeptime: $sweeptime\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr .= "$username  group: $batchgroup  sweeptime: $sweeptime  settletime: $settletime\n";
  $logfilestr .= "$features\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  my $printstr = "$username $usercountarray{$username} $starttdatearray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr .= "$username $usercountarray{$username} $starttdatearray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  $summaryidold = "";

  $batch_flag = 1;

  my $printstr = "check that previous batch has completed successfully\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

  $starttdatesav = $starttransdate;

  $starttransdate = $onemonthsago;

  # check that previous batch has completed successfully
  my $dbquerystr = <<"dbEOM";
        select batchfile
        from operation_log force index(oplog_tdateloptimeuname_idx)
        where trans_date>=?
        and trans_date<=?  
        and lastoptime>=?
        and username=?
        and lastopstatus='locked'
        and processor='fdms'
        and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$starttransdate", "$today", "$onemonthsagotime", "$username" );
  ($result) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $starttransdate = $starttdatesav;

  $returnsonlyflag = 0;
  my @sthtransvalarray = ();
  if ( $result ne "" ) {
    my $printstr = "aaaa $starttransdate $today $onemonthsagotime $username\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

    $batchretry   = 1;
    $chksummaryid = substr( $result, -5, 5 );
    $summaryidold = substr( $result, -5, 5 );

    my $dbquerystr = <<"dbEOM";
          select orderid,trans_date
          from operation_log force index(oplog_tdateloptimeuname_idx)
          where trans_date>=?
          and trans_date<=?  
          and lastoptime>=?
          and username=?
          and lastopstatus='locked'
          and lastop IN ('postauth','return')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$starttransdate", "$today", "$onemonthsagotime", "$username" );
    @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "batcherror check: $chksummaryid\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  } else {
    my $printstr = "done checking\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

    $batchretry = 0;

    $chktime         = &miscutils::strtotime($starttransdate);
    $twomonthslater  = $today;
    $returnsonlyflag = 0;
    if ( ( $redoflag == 0 ) && ( $usercountarray{"$username"} > 100 ) && ( time() - $chktime > ( 3600 * 24 ) * 60 ) ) {
      $returnsonlyflag = 1;
      $twomonthslater  = &miscutils::timetostr( $chktime + ( ( 3600 * 24 ) * 60 ) );    # do returns only over 2 month period
      $twomonthslater  = substr( $twomonthslater, 0, 8 );

      $lastopstr = " and lastop in ('return') and trans_date<='$twomonthslater'";       # if returns are more than 2 months old and > 1000 transactions do returns alone
      (@redoarray) = ( @redoarray, "$username" );

      if ( $twomonthslater < $onemonthsago ) {
        $starttdatearray{$username} = $twomonthslater;                                  # after doing just old returns, do everything else
      } else {
        $starttdatearray{$username} = $onemonthsago;
      }
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "old returns, will do returns first from $starttransdate to $twomonthslater\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    } else {
      $lastopstr = " and lastop in ('postauth','return')";
    }

    my $printstr = "lastopstr: $lastopstr\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

    my $dbquerystr = <<"dbEOM";
          select orderid,lastoptime,trans_date
          from operation_log force index(oplog_tdateloptimeuname_idx)
          where trans_date>=?
          and lastoptime>=?
          and username=?
          $lastopstr
          and lastopstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$starttransdate", "$onemonthsagotime", "$username" );
    @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
  }

  @orderidarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
    ( $orderid, $trans_time, $trans_date ) = @sthtransvalarray[ $vali .. $vali + 2 ];
    print "cccc $orderid\n";

    if ( ( $sweeptime ne "" ) && ( $trans_time > $sweeptime ) ) {
      next;    # transaction is newer than sweeptime
    }

    $orderidarray[ ++$#orderidarray ] = $orderid;
    $starttdateinarray{"$username $trans_date"} = 1;
  }

  $mintrans_date = $today;

  # list of trans_date's for update statement
  $tdateinstr   = "";
  $tdatechkstr  = "";
  @tdateinarray = ();
  foreach my $key ( sort %starttdateinarray ) {
    my ( $chkuser, $chktdate ) = split( / /, $key );
    if ( ( $username eq $chkuser ) && ( $chktdate =~ /^[0-9]{8}$/ ) ) {

      $tdateinstr  .= "?,";
      $tdatechkstr .= "$chktdate,";
      push( @tdateinarray, $chktdate );
    }
  }
  chop $tdateinstr;

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "tdatechkstr: $tdatechkstr\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  foreach $orderid ( sort @orderidarray ) {
    print "gggg $orderid\n";
    if ( ( -e "/home/pay1/batchfiles/logs/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/logs/fdms/stopgenfiles.txt" ) ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "stopgenfiles\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      unlink "/home/pay1/batchfiles/$devprod/fdms/batchfile.txt";
      last;
    }

    # operation_log should only have one orderid per username
    if ( $orderid eq $chkorderidold ) {
      next;
    }
    $chkorderidold = $orderid;

    my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,
                 auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,card_zip,
                 authtime,authstatus,forceauthtime,forceauthstatus,cardtype
          from operation_log
          where orderid=?
          and username=?
          and trans_date>=?
          and trans_date<=?  
          and lastoptime>=?
          and lastop in ('postauth','return')
          and lastopstatus in ('pending','locked')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$starttransdate", "$today", "$onemonthsagotime" );
    ( $orderid,   $operation,   $trans_date, $trans_time, $enccardnumber, $enclength, $exp,        $amount,        $auth_code,       $avs_code,
      $refnumber, $finalstatus, $cvvresp,    $transflags, $card_zip,      $authtime,  $authstatus, $forceauthtime, $forceauthstatus, $card_type
    )
      = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    print "eeee $orderid\n";

    if ( $orderid eq "" ) {
      next;
    }

    if ( $operation eq "void" ) {
      $orderidold = $orderid;
      next;
    }
    if ( ( $orderid eq $orderidold ) || ( $finalstatus !~ /^(pending|locked)$/ ) ) {
      $orderidold = $orderid;
      next;
    }

    if ( $transflags =~ /avsonly/ ) {
      $orderidold = $orderid;
      next;
    }

    if ( ( $sweeptime ne "" ) && ( $trans_time > $sweeptime ) ) {
      $orderidold = $orderid;
      next;    # transaction is newer than sweeptime
    }

    if ( $switchtime ne "" ) {
      $switchtime = substr( $switchtime . "0" x 14, 0, 14 );
      if ( ( $operation eq "postauth" ) && ( $authtime ne "" ) && ( $authtime < $switchtime ) ) {
        next;
      }
    }

    if ( ( $trans_date < $mintrans_date ) && ( $trans_date >= '19990101' ) ) {
      $mintrans_date = $trans_date;
    }

    my $dbquerystr = <<"dbEOM";
          select origamount
          from operation_log
          where orderid=?
          and username=?
          and trans_date>=?
          and (authstatus='success'
          or forceauthstatus='success')
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$twomonthsago" );
    ($origamount) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "fdms", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    print "eeee $orderid\n";

    $errflag = &errorchecking();
    if ( $errflag == 1 ) {
      next;
    }

    umask 0077;
    $logfilestr = "";
    $tmp = substr( $cardnumber, 0, 2 );
    $logfilestr .= "$orderid $operation $transflags $tmp\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    if ( $batch_flag == 1 ) {
      $datasentflag    = 0;
      $socketerrorflag = 0;
      $dberrorflag     = 0;
      $batcherrorflag  = 0;
      $batchcnt        = 1;
      $recseqnum       = 0;
      $salesamt        = 0;
      $salescnt        = 0;
      $returnamt       = 0;
      $returncnt       = 0;
    }

    $myj             = 0;
    $batchstarterror = 0;
    while ( $batch_flag == 1 ) {
      $myj++;
      if ( $myj > 5 ) {
        $batchstarterror = 1;
        last;
      }

      # every day at 3:00am est and again at 5:00am est fdms switches to a different system
      # don't send batches at these times
      my ( $mysec, $mymin, $myhour ) = localtime( time() );
      $chktime = sprintf( "%02d%02d", $myhour, $mymin );
      if ( ( $chktime >= 257 ) && ( $chktime < 303 ) ) {
        &miscutils::mysleep(360);

        my ( $mysec, $mymin, $myhour ) = localtime( time() );
        $chktime2 = sprintf( "%02d%02d", $myhour, $mymin );
        $mytime = gmtime( time() );
        umask 0077;
        $logfilestr = "";
        $logfilestr .= "$mytime  aaaa $chktime  $chktime2\n";
        &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      } elsif ( ( $chktime >= 457 ) && ( $chktime < 503 ) ) {
        &miscutils::mysleep(360);

        my ( $mysec, $mymin, $myhour ) = localtime( time() );
        $chktime2 = sprintf( "%02d%02d", $myhour, $mymin );
        $mytime = gmtime( time() );
        umask 0077;
        $logfilestr = "";
        $logfilestr .= "$mytime  bbbb $chktime  $chktime2\n";
        &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      }

      my ( $mysec, $mymin, $myhour ) = localtime( time() );
      $chktime2 = sprintf( "%02d%02d", $myhour, $mymin );

      $mytime = gmtime( time() );
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "$mytime  $chktime  $chktime2\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

      &pidcheck();

      &batchheader();
      if ( $batchstarterror == 1 ) {
        last;
      }
      if ( $result eq "A" ) {
        $batch_flag = 0;

        # check if batch number has incremented, otherwise last batch wasn't really settled

        my $dbquerystr = <<"dbEOM";
                select batchnum from fdms
                where username=?
dbEOM
        my @dbvalues = ("$username");
        ($chkbatchnum) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

        print "chkbatchnum: $chkbatchnum   $username\n";

        if ( ( $batchretry == 0 ) && ( $chkbatchnum eq $summaryid ) ) {
          umask 0077;
          $logfilestr = "";
          $logfilestr .= "batcherror problem: last batch has same summaryid $chkbatchnum $summaryid\n";
          &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
          $logfile2str = "";
          $logfile2str .= "/home/pay1/batchfiles/$devprod/fdms/$fileyear/$username$time$pid.txt";
          $logfile2str .= "batcherror problem: last batch has same summaryid $chkbatchnum $summaryid\n";
          &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "batcherror.txt", "append", "", $logfile2str );
          &senderrmail("last successful batch has same summaryid $chkbatchnum $summaryid\nMust be redone.\n");
        }

      } else {
        select undef, undef, undef, 5.00;
      }
    }
    if ( $batchstarterror == 1 ) {
      if ( $batchredoflag == 0 ) {
        &senderrmail("Couldn't start batch.");
      }
      last;
    }

    if ( ( $batchretry == 1 ) && ( $chksummaryid ne $summaryid ) ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "batcherror problem: $chksummaryid $summaryid\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      &senderrmail("batcherror problem: $chksummaryid $summaryid");
      $batchretry = 0;
      last;
    }
    $batchretry = 0;

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='locked',result=?
            where orderid=?
	    and username=?
	    and trans_date>=?
	    and finalstatus in ('pending','locked')
dbEOM
    my @dbvalues = ( "$time$summaryid", "$orderid", "$username", "$onemonthsago" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending'
          where orderid=?
          and username=?
          and $operationstatus in ('pending','locked')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time$summaryid", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $operation eq "return" ) {
      $orderidstrarray[ ++$#orderidstrarray ] = $orderid;
    }

    &batchdetail();
    if ( $socketerrorflag == 1 ) {
      print "socketerrorflag = 1\n";
      last;    # if socket error stop altogether
    }

    if ( $batchcnt >= $batchcntuser ) {
      &endbatch();
      $batch_flag   = 1;
      $batchcnt     = 1;
      $datasentflag = 0;
      if ( $batcherrorflag == 1 ) {
        last;    # if batch error move on to next username
      }
    }
    $tmpfilestr = "";
    $tmpfilestr .= "$username $orderid after msgrcv\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "checkipc.txt", "append", "", $tmpfilestr );
  }

  if ( ( ( $batchcnt > 1 ) || ( $datasentflag == 1 ) ) && ( $socketerrorflag == 0 ) ) {
    &endbatch();
    $batch_flag   = 1;
    $batchcnt     = 1;
    $datasentflag = 0;
  }

  if ( $socketerrorflag == 1 ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='pending'
	    where trans_date>=?
            and trans_date<=?
	    and username=?
	    and result=?
	    and finalstatus='locked'
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$onemonthsago", "$today", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and lastoptime>=?
            and username=?
            and batchfile=?
            and postauthstatus='locked'
            and lastop='postauth'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$onemonthsagotime", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and lastoptime>=?
            and lastoptime>=?
            and username=?
            and batchfile=?
            and returnstatus='locked'
            and lastop='return'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$onemonthsagotime", "$onemonthsagotime", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  }

  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

}

sub mysleep {
  for ( $myi = 0 ; $myi <= 60 ; $myi++ ) {
    umask 0033;
    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/logs/fdms", "baccesstime.txt", "write", "", $outfilestr );

    select undef, undef, undef, 60.00;
  }
}

sub senderrmail {
  my ($message) = @_;

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: FDMS - batch problem\n";
  print MAILERR "\n";
  print MAILERR "Username: $username\n";
  print MAILERR "\nLocked transactions found in trans_log and summaryid's did not match.\n";
  print MAILERR " Or batch out of balance.\n\n";
  print MAILERR "$message.\n\n";
  print MAILERR "chksummaryid: $chksummaryid    summaryid: $summaryid\n";
  close MAILERR;

}

sub endbatch {
  &batchtrailer();

  if ( $btresp eq "" ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdms - batch FAILURE must fix\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "filename: $username$time$pid.txt\n";
    print MAILERR "batch number: $summaryid\n";
    print MAILERR "Possible communication error with this batch. Must check batch numbers with next batch.\n\n";
    print MAILERR "Transactions still locked.\n\n";
    close MAILERR;
  } elsif ( $result eq "A" ) {

    print "update fdms set batchnum=$summaryid\n";

    my $dbquerystr = <<"dbEOM";
            update fdms set batchnum=?
            where username=?
dbEOM
    my @dbvalues = ( "$summaryid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    my $dbherrorflag = 0;
    ( $d1, $today, $ptime ) = &miscutils::genorderid();
    my $dbquerystr = <<"dbEOM";
            update trans_log force index(tlog_tdateuname_idx) set finalstatus='success',trans_time=?
	    where trans_date>=?
            and trans_date<=?
	    and username=?
	    and result=?
            and (accttype is NULL or accttype='' or accttype='credit')
	    and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$ptime", "$onemonthsago", "$today", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
    if ( $DBI::errstr =~ /lock.*try restarting/i ) {
      &miscutils::mysleep(60.0);
      my @dbvalues = ( "$ptime", "$onemonthsago", "$today", "$username", "$time$summaryid" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
    } elsif ( $dbherrorflag == 1 ) {
      &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    }

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbherrorflag = 0;
    if ( $returnsonlyflag == 0 ) {

      my $dbquerystr = <<"dbEOM";
            update operation_log force index(oplog_tdateloptimeuname_idx) set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
            where trans_date in ($tdateinstr)
        and lastoptime>=?
            and username=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$ptime", "$ptime", @tdateinarray, "$onemonthsagotime", "$username", "$time$summaryid" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
      if ( $DBI::errstr =~ /lock.*try restarting/i ) {
        &miscutils::mysleep(60.0);
        my @dbvalues = ( "$ptime", "$ptime", @tdateinarray, "$onemonthsagotime", "$username", "$time$summaryid" );
        &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
      } elsif ( $dbherrorflag == 1 ) {
        &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      }

    }

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

    my $dbquerystr = <<"dbEOM";
            update operation_log force index(oplog_tdateloptimeuname_idx) set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
            where trans_date in ($tdateinstr)
            and lastoptime>=?
            and username=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$ptime", "$ptime", @tdateinarray, "$onemonthsagotime", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  } else {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='pending'
	    where trans_date>=?
            and trans_date<=?
	    and username=?
	    and result=?
	    and finalstatus='locked'
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$onemonthsago", "$today", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and lastoptime>=?
            and username=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$onemonthsagotime", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and lastoptime>=?
            and username=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$onemonthsagotime", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch trailer: $errorcode $errcode{$errorcode}\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    (@redoarray) = ( @redoarray, "$username" );

    if ( $result eq "Y" ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "Batch out of balance.\n";
      $logfilestr .= "Merchant Name: $company\n";
      $logfilestr .= "Merchant ID: $merchant_id\n";
      $logfilestr .= "Terminal ID: $terminal_id\n";
      $logfilestr .= "Total # of Sales: $salescnt\n";
      $logfilestr .= "Total Amt of Sales: $salesamt\n";
      $logfilestr .= "Total # of Credits: $returncnt\n";
      $logfilestr .= "Total Amt of Credits: $returnamt\n\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

      &senderrmail("Batch out of balance");
    }
    if ( $result !~ /^(Y|E)$/ ) {
      $socketerrorflag = 1;
    }
    if ( $errorcode ne "07" ) {
      $batcherrorflag = 1;
    }
  }
  $batchid = &miscutils::incorderid($batchid);
}

sub batchheader {
  @orderidstrarray = ();

  @bh          = ();
  $bh[0]       = "$borderid";                                  # user reference (12a);
  $bh[1]       = 'PNP8';                                       # source id (4a)
  $bh[2]       = '006';                                        # tcode (3n)
  $merchant_id = substr( "0" x 11 . $merchant_id, -11, 11 );
  $bh[3]       = "$merchant_id";                               # merchant id (11n)
  $terminal_id = substr( "0" x 11 . $terminal_id, -11, 11 );
  $bh[4]       = "$terminal_id";                               # terminal id (11n)

  my $message = "";
  foreach $var (@bh) {
    $message = $message . $var;
  }

  $bhresp = &sendrecord($message);

  if ( $bhresp eq "" ) {
    &miscutils::mysleep(120.0);
    $bhresp = &sendrecord($message);
  }

  $checkbeginm     = substr( $message, 0,  15 );
  $checkoperationm = substr( $message, 15, 4 );
  $checkmidm       = substr( $message, 19, 11 );
  $checkbeginr     = substr( $bhresp,  6,  15 );
  $checkoperationr = substr( $bhresp,  21, 4 );
  $checkmidr       = substr( $bhresp,  25, 11 );

  $batchredoflag = 0;
  if ( ( $checkoperationm != $checkoperationr - 1 ) || ( $checkmidm ne $checkmidr ) ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error starting batch: response incorrect $checkbeginm $checkbeginr $checkrecordm $checkrecordr $checkoperationm $checkoperationr\n";
    $temp = unpack "H*", $message;
    $logfilestr .= "message: $temp\n";
    $temp = unpack "H*", $bhresp;
    $logfilestr .= "respons: $temp\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    $batchstarterror = 1;

    if ( $checkbeginr eq "" ) {
      $batchredoflag = 1;
      (@redoarray) = ( @redoarray, "$username" );
    }
    return;
  }

  $summaryid = substr( $bhresp, 47, 5 );
  $result    = substr( $bhresp, 57, 1 );
  $errorcode = substr( $bhresp, 64, 2 );

  if ( $result ne "A" ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error starting batch: $errorcode\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  }

  if ( ( $summaryid eq $summaryidold ) && ( $summaryidold ne "" ) ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdms - batch FAILURE\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "filename: $username$time$pid.txt\n";
    print MAILERR "batch number: $summaryid\n";
    print MAILERR "Batch number same as previous batch number.\n\n";
    close MAILERR;
  }
  $summaryidold = $summaryid;

}

sub batchdetail {

  $origoperation = "";
  if ( $operation eq "postauth" ) {
    if ( ( $authtime ne "" ) && ( $authstatus eq "success" ) ) {
      if ( ( $industrycode =~ /retail|restaurant/ ) && ( $transflags !~ /moto/ ) ) {
        $trans_time = $authtime;
      }
      $origoperation = "auth";
    } elsif ( ( $forceauthtime ne "" ) && ( $forceauthstatus eq "success" ) ) {
      $trans_time    = $forceauthtime;
      $origoperation = "forceauth";
    } else {
      $trans_time    = "";
      $origoperation = "";
    }

    if ( $trans_time < 1000 ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "Error in batch detail: couldn't find trans_time $username $twomonthsago $orderid $trans_time\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      $socketerrorflag = 1;
      $dberrorflag     = 1;
      return;
    }
  }

  $datasentflag = 1;
  $magstripetrack = substr( $auth_code, 32, 1 );

  @bd             = ();
  $bd[0]          = $borderid;                                    # user reference (12a);
  $bd[1]          = 'PNP8';                                       # source id (4a)
  $bd[2]          = '072';                                        # tcode (3n)
  $merchant_id    = substr( "0" x 11 . $merchant_id, -11, 11 );
  $bd[3]          = "$merchant_id";                               # merchant id (11n)
  $terminal_id    = substr( "0" x 11 . $terminal_id, -11, 11 );
  $bd[4]          = "$terminal_id";                               # terminal id (11n)
  $summaryid      = substr( "0" x 5 . $summaryid, -5, 5 );
  $bd[5]          = "$summaryid";                                 # summary id (5n)
  $recseqnum      = $recseqnum + 1;
  $transaction_id = substr( "0" x 5 . $recseqnum, -5, 5 );
  $bd[6]          = "$transaction_id";                            # transaction id (5n)
  if ( $operation eq "return" ) {
    $proc_code = 'C';
    $auth_type = 'C';
  } else {
    $proc_code = 'S';
    $auth_type = 'A';
  }
  $bd[7] = $proc_code;                                            # process code (1a)
  $bd[8] = $auth_type;                                            # authorization type (1a)

  if ( $transflags !~ /token/ ) {
    $card_type = &smpsutils::checkcard($cardnumber);
  }

  if ( $card_type eq "vi" ) {
    $cardtype = '02';                                             # visa
  } elsif ( $card_type eq "mc" ) {
    $cardtype = '01';                                             # mastercard
  } elsif ( $card_type eq "ax" ) {
    $cardtype = '03';                                             # amex
  } elsif ( $card_type eq "dc" ) {
    $cardtype = '04';                                             # diners club/carte blanche
  } elsif ( $card_type eq "ds" ) {
    $cardtype = '10';                                             # discover
  } elsif ( $card_type eq "jc" ) {
    $cardtype = '28';                                             # jcb
  } else {
    $cardtype = '00';                                             # invalid card
  }

  $bd[9] = "$cardtype";                                           # card type (2n)
  $cardnum = substr( $cardnumber . " " x 19, 0, 19 );
  if ( $transflags =~ /token/ ) {
    $cardnum = " " x 19;
  }
  $bd[10] = "$cardnum";                                           # card number (19a)

  $temp = substr( $amount, 4 );
  $temp = sprintf( "%d", ( $temp * 100 ) + .0001 );
  $pamount = substr( "0" x 7 . $temp, -7, 7 );

  $bd[11] = $pamount;                                             # orig trans amount (7$)

  $invoicenum = substr( $auth_code, 33, 10 );
  $invoicenum =~ s/ //g;
  if ( ( $invoicenum eq "0000000000" ) || ( $invoicenum eq "" ) ) {
    $invoicenum = substr( '0' x 10 . $orderid, -10, 10 );
  }
  $bd[12] = "$invoicenum";                                        # invoice number (10n)
  if ( ( $operation eq "return" ) && ( ( $card_type !~ /(vi|ds)/ ) || ( $transflags =~ /offline/ ) ) ) {
    $authcode = "      ";
  } else {
    $authcode = substr( $auth_code . " " x 6, 0, 6 );
  }
  $bd[13] = "$authcode";                                          # orig auth code (6a)

  $magstripetrack = substr( $auth_code, 32, 1 );
  $temp           = substr( $auth_code, 32, 10 );

  my $printstr = "magstripetrack: $magstripetrack   $temp\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

  my $posentry = $magstripetrack;
  if ( ( $transflags !~ /init/ ) && ( $transflags =~ /(recur|install|mit|cit|incr|resub|delay|reauth|noshow|topup)/ ) ) {
    $posentry = 'C';                                              # pos entry mode C = credential on file
  } elsif ( $magstripetrack !~ /^(1|2)$/ ) {
    $posentry = '3';
  }
  $bd[14] = $posentry;                                            # pos entry mode (1n)

  if ( $industrycode eq "restaurant" ) {
    $gratuity = substr( $auth_code, 88, 7 );
    $gratuity =~ s/ //g;
    $gratuity = substr( "0" x 7 . $gratuity, -7, 7 );
  } else {
    $gratuity = "0000000";
  }
  $bd[15] = $gratuity;                                            # gratuity tip (7$)

  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime( time() );
  $year     = $year + 1900;
  $year     = substr( $year, 2, 2 );
  $trantime = sprintf( "%02d%02d%02d%02d%02d", $year, $month + 1, $day, $hour, $min );

  $bd[16] = "$trantime";                                          # transaction date and time (10n)

  my $commflag = substr( $auth_code, 280, 1 );
  print "auth_code: $auth_code\n";
  print "card_type: $card_type\n";
  print "commflag: $commflag\n";

  if ( ( $card_type !~ /^(vi|mc|ax)$/ ) || ( $commflag ne "1" ) ) {
    $bd[17] = '000';                                              # auxiliary data length (3n)
    $bd[18] = '';                                                 # format code (4n)
    $bd[19] = '';                                                 # format code revision (2n)
    $bd[20] = '';                                                 # compression indicator (1a)
  } else {
    $bd[17] = '065';                                              # auxiliary data length (3n)
    $bd[18] = '0020';                                             # format code (4n)
    $bd[19] = '02';                                               # format code revision (2n)
    $bd[20] = 'N';                                                # compression indicator (1a)
  }

  if ( ( $card_type !~ /^(vi|mc|ax)$/ ) || ( $commflag ne "1" ) ) {
    $bd[21] = "";                                                 # tax through freight combined (commercial card data)
    $bd[22] = "";
    $bd[23] = "";
    $bd[24] = "";
    $bd[25] = "";
    $bd[26] = "";
    $bd[27] = "";
  } elsif ( length($refnumber) >= 43 ) {
    $refnumber = substr( $refnumber . " " x 58, 0, 58 );
    $bd[21] = $refnumber;                                         # tax through freight combined (commercial card data)
    $bd[22] = "";
    $bd[23] = "";
    $bd[24] = "";
    $bd[25] = "";
    $bd[26] = "";
    $bd[27] = "";
  } else {
    $bd[21] = '0000000';                                          # tax amount (7n)
    $purchorderid = substr( '0' x 17 . $orderid,      -17, 17 );  # keep both lines
    $purchorderid = substr( $purchorderid . " " x 25, 0,   25 );  # keep both lines
    $bd[22] = $purchorderid;                                      # purchase order number (25a)
    $card_zip = substr( $card_zip . " " x 9, 0, 9 );
    $bd[23] = $card_zip;                                          # ship to zip code (9a) ????
    $bd[24] = '04';                                               # commercial card type (2n) ????
    $bd[25] = ' ';                                                # tax exempt indicator (1n) ????
    $bd[26] = '0000000';                                          # duty amount (7$)
    $bd[27] = '0000000';                                          # freight amount (7$)
  }

  $paysvccheck = substr( $auth_code, 6, 23 ) . $avs_code;

  $bd[28] = '@';                                                  # data indicator (1a)
  $paysvcdata = substr( $auth_code, 8, 23 );
  if ( ( ( $operation ne "return" ) || ( $transflags !~ /offline/ ) ) && ( ( ( $paysvcdata ne "" ) && ( $paysvcdata ne ( " " x 23 ) ) ) || ( $transflags =~ /incr/ ) ) ) {
    $paysvcdata = substr( $paysvcdata . " " x 23, 0, 23 );
    $bd[29] = $paysvcdata;                                        # pay service data (23a)
    if ( $origamount eq "" ) {
      $origamount = $amount;
    }

    $temp = substr( $origamount, 4 );
    $temp = sprintf( "%d", ( $temp * 100 ) + .0001 );
    $oamount = substr( "0" x 7 . $temp, -7, 7 );
    $bd[30] = $oamount;                                           # orig trans amount (7$) ????

    $incrtotalamt = substr( $amount, 4 );
    $incrtotalamt = sprintf( "%d", ( $incrtotalamt * 100 ) + .0001 );

    $incrtotalamt = substr( "0" x 7 . $incrtotalamt, -7, 7 );
    print "incrtotalamt: $incrtotalamt\n";
    $bd[31] = $incrtotalamt;                                      # final trans amount (7$) ????
  } else {
    $bd[29] = "";                                                 # don't send data
    $bd[30] = "";                                                 # don't send data
    $bd[31] = "";                                                 # don't send data
  }

  $bd[32] = '@';                                                  # avs data indicator (1a)
  $magstripetrack = substr( $auth_code, 32, 1 );
  if ( ( ( $operation ne "return" ) || ( ( $operation eq "return" ) && ( $transflags !~ /offline/ ) ) )
    && ( $origoperation ne "forceauth" )
    && ( ( $magstripetrack eq " " ) || ( $magstripetrack eq "0" ) ) ) {

    $addrmatch = substr( $auth_code, 6, 1 );
    $zipmatch  = substr( $auth_code, 7, 1 );

    $addrmatch = substr( $addrmatch . " ", 0, 1 );
    $zipmatch  = substr( $zipmatch . " ",  0, 1 );
    $avs_code  = substr( $avs_code . " ",  0, 1 );
    $avsinfo   = $addrmatch . $zipmatch . $avs_code;

    $bd[33] = $avsinfo;    # address match (1a)
  } else {
    $bd[33] = "   ";       # don't send data		04/18/2005 must send spaces
  }

  my $addtldatasep = '#';

  if (
    ( ( $card_type =~ /(vi|mc|dc|ds|jc|ax)/ ) && ( $transflags !~ /moto/ ) && ( $industrycode !~ /retail|restaurant/ ) )    # all ecommerce
    || ( ( $card_type =~ /(vi|mc|ds|jc|dc|ax)/ ) && ( $transflags =~ /recur|bill|install|deferred/ ) && ( $transflags !~ /init/ ) )    # all subsequent
    || ( ( $card_type =~ /(vi|mc|ds|jc|dc|ax)/ ) && ( $transflags =~ /bill/ ) )                                                        # all subsequent
    || ( ( $card_type =~ /(ax)/ ) && ( $transflags =~ /recur|bill|install|deferred/ ) && ( $transflags =~ /init/ ) )                   # ax recur init
    ) {
    $bd[34] = $addtldatasep;                                                                                                           # additional data separator (1a)
    $bd[35] = '002';                                                                                                                   # data id (3n)
    $eci = substr( $auth_code, 46, 2 );
    $eci =~ s/ //g;

    if ( $eci > 0 ) {
      $bd[36] = $eci;                                                                                                                  # request flag (2n) 08 = non-secure ????
    } elsif ( ( $card_type ne "mc" ) && ( $transflags =~ /recur/ ) ) {
      $bd[36] = "02";                                                                                                                  # request flag (2n) 08 = non-secure ????
    } else {
      $bd[36] = '07';                                                                                                                  # request flag (2n) 08 = non-secure ????
    }

    if ( ( ( $card_type eq "vi" ) && ( $transflags =~ /recur|bill|install|deferred/ ) && ( $transflags !~ /init/ ) )
      || ( ( $card_type eq "vi" ) && ( $transflags =~ /bill/ ) ) ) {
      $bd[36] = $bd[36] . "B";
    }

    $addtldatasep = '@';
  }

  my $printstr = "cardtype: $cardtype  transflags: $transflags\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

  if ( ( $card_type =~ /^(vi|mc|ax|ds|dc|jc)$/ ) && ( ( $transflags !~ /recur/ ) || ( $transflags =~ /init/ ) ) && ( $cvvresp ne "" ) && ( $cvvresp ne " " ) ) {
    $bd[37] = $addtldatasep;    # additional data separator (1a)
    $bd[38] = '013';            # cvv indicator (3n)
    $cvvresp =~ s/[^0-9a-zA-Z]//g;
    $cvvresp = substr( $cvvresp . " ", 0, 1 );
    $bd[39] = $cvvresp;         # cvv response (1a)
    $addtldatasep = '@';
  }

  $bd[40] = $addtldatasep;      # additional data separator (1a)
  $bd[41] = '015';              # customer presence indicator (3n)
  if ( ( $industrycode =~ /retail|restaurant/ ) && ( $transflags !~ /(recur|moto)/ ) ) {
    $bd[42] = '0';              # customer present (1n)
  } elsif ( ( $transflags =~ /recur/ ) && ( $card_type ne "jc" ) ) {
    $bd[42] = '2';              # customer not present (1n)
  } else {
    $bd[42] = '1';              # customer not present (1n)
  }

  my $cnpind = '1';
  if ( ( $industrycode =~ /retail|restaurant/ ) && ( $transflags !~ /(recur|moto)/ ) ) {
    $cnpind = '0';              # card present (1n)
  }
  $bd[43] = '@' . '016' . $cnpind;

  if ( $transflags =~ /deferred/ ) {
    $bd[44] = '@' . '017' . '1';    # deferred billing indicator (1a)
  }

  if ( $transflags =~ /debt/ ) {
    $bd[45] = '@' . '019' . '9';    # existing debt indicator (1a)
  }

  $tdsresp = substr( $auth_code, 43, 3 );
  $tdsresp = substr( $tdsresp,   -1, 1 );
  if ( ( $card_type eq "vi" ) && ( $tdsresp ne " " ) && ( $tdsresp ne "" ) ) {
    $bd[46] = '@';                  # separator (1a)
    $bd[47] = '020';                # 3dsecure info vpas (3n)
    $bd[48] = '05' . $tdsresp;
  }

  if ( $card_type eq "mc" ) {
    $ucafind = substr( $auth_code, 309, 1 );
    $ucafind =~ s/ //g;
    if ( $ucafind ne "" ) {
      $bd[46] = '@';                # separator (1a)
      $bd[47] = '020';              # 3dsecure info vpas (3n)
      $bd[48] = '06' . $ucafind;
    }
  }

  if ( ( $card_type eq "ax" ) && ( $operation eq "postauth" ) && ( $origoperation eq "auth" ) ) {
    $axcapntranid = substr( $auth_code, 95, 15 );
    $axcapntranid =~ s/ //g;
    if ( $axcapntranid ne "" ) {
      $fs = pack "H2", "1D";
      $bd[49] = '@';                # separator (1a)
      $bd[50] = 'AMX';              # ax capn data (27a)
      $bd[51] = '032';              # len (3n)
      $bd[52] = '01';
      $axcapntranid  = substr( $auth_code,                95,  15 );
      $axcapntranid  = substr( $axcapntranid . " " x 15,  0,   15 );
      $bd[53]        = $axcapntranid;
      $bd[54]        = $fs;
      $axcapnposdata = substr( $auth_code,                110, 12 );
      $axcapnposdata = substr( $axcapnposdata . " " x 12, 0,   12 );
      $bd[55]        = '02';
      $bd[56]        = $axcapnposdata;
    }
  } elsif ( ( $card_type eq "vi" ) && ( ( ( $operation eq "postauth" ) && ( $origoperation eq "auth" ) ) || ( $operation eq "return" ) && ( $transflags !~ /offline/ ) ) ) {
    $cardlevelres = substr( $auth_code, 122, 2 );
    $cardlevelres =~ s/ //g;

    $bd[49] = '@';      # separator (1a)
    $bd[50] = '0VI';    # vi card level results (2a)
    $bd[51] = '004';    # len (3n)
    $bd[52] = 'CR';
    $cardlevelres = substr( $auth_code,              122, 2 );
    $cardlevelres = substr( $cardlevelres . " " x 2, 0,   2 );
    $bd[53]       = $cardlevelres;

  } elsif ( ( $card_type =~ /(ds|dc|jc)/ ) && ( ( $operation eq "postauth" ) && ( $origoperation eq "auth" ) ) || ( ( $operation eq "return" ) && ( $transflags !~ /offline/ ) ) ) {
    $dicompliance = substr( $auth_code, 124, 92 );
    $dicompliance =~ s/ +$//;
    my $tmpstr = unpack "H*", $dicompliance;
    print "dicompliance: $tmpstr\n";
    if ( $dicompliance ne "" ) {
      $dicompliance = substr( $dicompliance, 3 );
      (@fields) = split( /\x1d/, $dicompliance );
      $dicompliance = "";
      my $gs = pack "H2", "1d";
      foreach $var (@fields) {
        $tag = substr( $var, 0, 2 );
        $data = substr( $var, 2 );
        if ( $tag =~ /(02|07|10)/ ) {
          $dicompliance .= "$tag$data$gs";
          print "tag: $tag    $dicompliance\n";
        }
      }
      chop $dicompliance;
      $len = length($dicompliance);
      $len = substr( "000" . $len, -3, 3 );
      if ( $len > 1 ) {
        $bd[49] = '@';             # separator (1a)
        $bd[50] = '0DS';           # di compliance (3a)
        $bd[51] = $len;            # len (3n)
        $bd[52] = $dicompliance;
      }
    }
  }

  my $addtldata = "";

  if ( $card_type eq "mc" ) {
    my $mcintegrity = substr( $auth_code, 281, 2 );
    $mcintegrity =~ s/ //g;
    if ( $mcintegrity ne "" ) {
      $addtldata .= 'IC002' . $mcintegrity;    # mastercard integrity class (2a)
    }

    if ( $addtldata ne "" ) {
      $len = length($addtldata);
      $len = substr( "000" . $len, -3, 3 );

      $bd[54] = '@';                           # separator (1a)
      $bd[55] = '0SD';
      $bd[56] = $len;                          # len (3n)
      $bd[57] = $addtldata;                    # token data (30v)
    }
  }

  if ( $transflags =~ /token/ ) {
    my $cardnumlen = substr( "000" . length($cardnumber), -3, 3 );

    my $providerid = substr( $auth_code, 239, 3 );
    $providerid =~ s/ //g;
    my $provideridlen = substr( "000" . length($providerid), -3, 3 );
    print "providerid: $providerid\n";

    my $addtldata = "010013" . "060043528" . "07$cardnumlen" . $cardnumber;    # token data (30a)

    if ( $providerid ne "" ) {
      $addtldata .= "10$provideridlen$providerid";
    }

    $len = length($addtldata);
    $len = substr( "000" . $len, -3, 3 );

    $bd[58] = '@';                                                             # separator (1a)
    $bd[59] = '0SP';
    $bd[60] = $len;                                                            # len (3n)
    $bd[61] = $addtldata;                                                      # token data (30v)
  }

  $bd[62] = '#';                                                               # additional data separator (1a)

  my $message = "";
  foreach $var (@bd) {
    $message = $message . $var;
  }

  $bdresp = &sendrecord($message);

  $checkbeginm     = substr( $message, 0,  15 );
  $checkoperationm = substr( $message, 15, 4 );
  $checkmidm       = substr( $message, 19, 11 );
  $checkbeginr     = substr( $bdresp,  6,  15 );
  $checkoperationr = substr( $bdresp,  21, 4 );
  $checkmidr       = substr( $bdresp,  25, 11 );
  $checkrecordm    = substr( $message, 45, 5 );
  $checkrecordr    = substr( $bdresp,  51, 5 );

  if ( ( $checkoperationm != $checkoperationr - 1 ) || ( $checkmidm ne $checkmidr ) ) {

    my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='pending',descr=?
          where trans_date>=?
          and trans_date<=?
          and username=?
          and result=?
          and (accttype is NULL or accttype='' or accttype='credit')
          and finalstatus='locked'
dbEOM
    my @dbvalues = ( "Response incorrect", "$onemonthsago", "$today", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='pending',lastopstatus='pending',descr='Response incorrect'
            where trans_date in ($tdateinstr)
            and lastoptime>=?
            and username=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$onemonthsagotime", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='pending',lastopstatus='pending',descr='Response incorrect'
            where trans_date in ($tdateinstr)
            and lastoptime>=?
            and username=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$onemonthsagotime", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch detail: response incorrect $checkbeginm $checkbeginr $checkrecordm $checkrecordr $checkoperationm $checkoperationr\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    $socketerrorflag = 1;
    (@redoarray) = ( @redoarray, "$username" );

    return;
  }

  $result    = substr( $bdresp, 57, 1 );
  $errorcode = substr( $bdresp, 64, 2 );

  if ( $result eq "A" ) {
    $transamt = substr( $amount, 4 );
    $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );
    $transamt = substr( "00000000" . $transamt, -8, 8 );

    if ( $operation eq "return" ) {
      $returnamt = $returnamt + $transamt;
      $returncnt++;
    } else {
      $salesamt = $salesamt + $transamt;
      $salescnt++;
    }
    $batchcnt++;
  } elsif ( $result eq "E" ) {
    my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='problem',descr=?
          where orderid=?
          and username=?
          and trans_date>=?
          and result=?
          and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$errcode{$errorcode}", "$orderid", "$username", "$onemonthsago", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$errcode{$errorcode}", "$orderid", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch detail: $errorcode $errcode{$errorcode}\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  } else {
    my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='pending',descr=?
          where trans_date>=?
          and trans_date<=?
          and username=?
          and result=?
          and (accttype is NULL or accttype='' or accttype='credit')
          and finalstatus='locked'
dbEOM
    my @dbvalues = ( "No response from socket", "$onemonthsago", "$today", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='pending',lastopstatus='pending',descr='No response from socket'
            where trans_date in ($tdateinstr)
            and lastoptime>=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$onemonthsagotime", "$username", "$time$summaryid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch detail: No response from socket\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    $socketerrorflag = 1;
    (@redoarray) = ( @redoarray, "$username" );
  }
}

sub batchtrailer {
  $recseqnum = $recseqnum + 2;
  $recseqnum = substr( $recseqnum, -8, 8 );

  @bt          = ();
  $bt[0]       = $borderid;                                    # user reference (12a);
  $bt[1]       = 'PNP8';                                       # source id (4a)
  $bt[2]       = '164';                                        # tcode (3n)
  $merchant_id = substr( "0" x 11 . $merchant_id, -11, 11 );
  $bt[3]       = "$merchant_id";                               # merchant id (11n)
  $terminal_id = substr( "0" x 11 . $terminal_id, -11, 11 );
  $bt[4]       = "$terminal_id";                               # terminal id (11n)
  $summaryid   = substr( "0" x 5 . $summaryid, -5, 5 );
  $bt[5]       = "$summaryid";                                 # summary id (5n)
  $summary_inv = "0" x 100;
  $bt[6]       = "$summary_inv";                               # summary invoice (100n) ????
  $salesamt    = substr( "0" x 9 . $salesamt, -9, 9 );
  $bt[7]       = "$salesamt";                                  # total sales amount (9$)
  $returnamt   = substr( "0" x 9 . $returnamt, -9, 9 );
  $bt[8]       = "$returnamt";                                 # total credit amount (9$)
  $salescnt    = substr( "0" x 4 . $salescnt, -4, 4 );
  $bt[9]       = "$salescnt";                                  # total sales count (4n)
  $returncnt   = substr( "0" x 4 . $returncnt, -4, 4 );
  $bt[10]      = "$returncnt";                                 # total credit count (4n)

  my $btmessage = "";
  foreach $var (@bt) {
    $btmessage = $btmessage . $var;
  }

  $btresp = &sendrecord($btmessage);

  $result    = substr( $btresp, 57, 1 );
  $errorcode = substr( $btresp, 64, 2 );
}

sub sendrecord {
  my ($message) = @_;

  $response = "";

  $head = pack "H8", "02464402";
  $tail = pack "H8", "03464403";
  $length    = length($message);
  $tcpheader = pack "n", $length;
  $message   = $head . $tcpheader . $message . $tail;

  $checkmessage = $message;
  if ( ( $message =~ /PNP8072/ ) && ( length($cardnumber) > 12 ) ) {
    $xs = "x" x length($cardnumber);
    $checkmessage =~ s/$cardnumber/$xs/;
  }
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$checkmessage\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  $processid = $$;
  my $hostnm = hostname;
  $hostnm =~ s/[^0-9a-zA-Z]//g;
  $processid = $processid . $hostnm;

  ( $status, $invoicenum, $response ) = &procutils::sendprocmsg( "$processid", "fdmsb", "$username", "$borderid", "$message" );

  if ( $response eq "failure" ) {
    $response = "";
  }

  $checkmessage = $response;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$checkmessage\n\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  $borderid = &miscutils::incorderid($borderid);
  $borderid = substr( "0" x 12 . $borderid, -12, 12 );

  return $response;
}

sub errorchecking {
  my $errorcheckstr = "";
  return 0;

  my $mylen = length($cardnumber);
  my $amt = substr( $amount, 4 );

  # check for bad card numbers
  if ( ( $enclength > 1024 ) || ( $enclength < 30 ) ) {
    $errorcheckstr = "could not decrypt card";
  } elsif ( ( $mylen < 13 ) || ( $mylen > 20 ) ) {
    $errorcheckstr = "bad card length";
  } elsif ( $cardnumber eq "4111111111111111" ) {
    $errorcheckstr = "test card number";
  } elsif ( $amt == 0 ) {

    # check for 0 amount
    $errorcheckstr = "amount = 0.00";
  }

  if ( $errorcheckstr ne "" ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where orderid=?
            and username=?
            and trans_date>=?
            and finalstatus='pending'
dbEOM
    my @dbvalues = ( "$errorcheckstr", "$orderid", "$username", "$onemonthsago" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and username=?
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$errorcheckstr", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  }

  return 0;
}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  my $printstr = "origtime: $origtime $timezone1\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

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

  if ( $wday1 < $wday ) {
    $wday1 = 7 + $wday1;
  }
  my $mday1 = ( 7 * ( $times1 - 1 ) ) + 1 + ( $wday1 - $wday );
  my $timenum1 = timegm( 0, substr( $time1, 3, 2 ), substr( $time1, 0, 2 ), $mday1, $month1 - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $printstr = "The $times1 Sunday of month $month1 happens on the $mday1\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $printstr = "The $times2 Sunday of month $month2 happens on the $mday2\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );

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

  my $printstr = "zoneadjust: $zoneadjust\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  my $printstr = "newtime: $newtime $timezone2\n\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append", "misc", $printstr );
  return $newtime;

}

