#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;

if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
  exit;
}

$devprod = "logs";

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'buypass/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: buypass - genfiles already running\n";
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
&procutils::flagwrite( "$username", "buypass", "/home/pay1/batchfiles/logs/buypass", "pid.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my @infilestrarray = &procutils::flagread( "$username", "buypass", "/home/pay1/batchfiles/logs/buypass", "pid.txt" );
$chkline = $infilestrarray[0];
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
  $printstr .= "$pidline\n";
  $printstr .= "$chkline\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: buypass - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $batchid, $today, $time ) = &miscutils::genorderid();
$todaytime = $time;
$batchid   = $time;
$borderid  = substr( "0" x 12 . $batchid, -12, 12 );

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/buypass/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/buypass/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/buypass/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/buypass/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/buypass/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/buypass/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/buypass/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/buypass/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/buypass/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/buypass/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: buypass - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory $devprod/buypass/$fileyear.\n\n";
  close MAILERR;
  exit;
}

#and username='completene'
my $dbquerystr = <<"dbEOM";
        select distinct username
        from trans_log
        where trans_date>=?
        and finalstatus = 'pending'
        and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
my @dbvalues = ("$onemonthsago");
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 1 ) {
  ($user) = @sthtransvalarray[ $vali .. $vali + 0 ];

  my $dbquerystr = <<"dbEOM";
        select status,processor
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$user");
  ( $chkstatus, $chkprocessor ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( ( $chkstatus eq "live" ) && ( $chkprocessor eq "buypass" ) ) {
    my $printstr = "b: $user\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );
    @userarray = ( @userarray, $user );
  }
}

foreach $username ( sort @userarray ) {
  if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
    &procutils::flagwrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "batchfile.txt", "unlink", "", "" );
    last;
  }

  &pidcheck();

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::flagwrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "genfiles.txt", "write", "", $checkinstr );

  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );
  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::flagwrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "batchfile.txt", "write", "", $batchfilestr );

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
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass/$fileyear", "$username$time$pid.txt", "write", "", $logfilestr );
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass/$fileyear", "$username$time$pid.txt", "write", "", $logfilestr );
      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  my $printstr = "gmt today: $todaytime\n";
  $printstr .= "est today: $esttime\n";
  $printstr .= "est yesterday: $yesterday\n";
  $printstr .= "settletime: $settletime\n";
  $printstr .= "sweeptime: $sweeptime\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );

  $logfilestr .= "$username  sweeptime: $sweeptime  settletime: $settletime\n";
  $logfilestr .= "$features\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  # check that previous batch has completed successfully
  my $dbquerystr = <<"dbEOM";
        select orderid
        from trans_log
        where trans_date>=?
        and finalstatus='locked'
        and username=?
        and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$onemonthsago", "$username" );
  my @sthcheckvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $errorflag    = 0;
  @orderidarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthcheckvalarray) ; $vali = $vali + 1 ) {
    ($orderid) = @sthcheckvalarray[ $vali .. $vali + 0 ];

    $errorflag = 1;

    $orderidarray[ ++$#orderidarray ] = $orderid;
  }

  if ( $errorflag == 1 ) {
    &senderrmail();
    my $printstr = "locked transactions found\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );
    next;
  }

  my $dbquerystr = <<"dbEOM";
          select orderid,operation,finalstatus,amount
          from trans_log
          where trans_date>=?
          and username=?
          and operation IN ('postauth','return','void')
          and finalstatus IN ('pending','success')
          and (duplicate IS NULL or duplicate ='')
          and (accttype is NULL or accttype='' or accttype='credit')
          order by orderid,trans_time DESC
dbEOM
  my @dbvalues = ( "$onemonthsago", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 4 ) {
    ( $orderid, $operation, $finalstatus, $amount ) = @sthtransvalarray[ $vali .. $vali + 3 ];

    if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
      &procutils::flagwrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "batchfile.txt", "unlink", "", "" );
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
      next;    # transaction is newer than sweeptime
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    my $printstr = "$orderid $operation\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='locked',result=?
	    where orderid=?
	    and username=?
	    and finalstatus='pending'
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$today", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending'
          where orderid=?
          and username=?
          and $operationstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$today", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $operation eq "postauth" ) {
      $trans_type = "bpostauth";
    } elsif ( $operation eq "return" ) {
      $trans_type = "breturn";
    }

    if ( $operation eq "postauth" ) {
      %result = &miscutils::sendmserver( $username, $trans_type, 'order-id', $orderid );
    } else {
      %result = &miscutils::sendmserver( $username, $trans_type, 'amount', $amount, 'order-id', $orderid );
    }
    umask 0077;
    $logfilestr = "";
    foreach my $key ( sort keys %result ) {
      $logfilestr .= "$key $result{$key} ";
    }
    $logfilestr .= "\n\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  }

}

&procutils::flagwrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "batchfile.txt", "unlink", "", "" );

umask 0033;
$checkinstr = "";
&procutils::flagwrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "genfiles.txt", "write", "", $checkinstr );

exit;

sub senderrmail {
  my ($message) = @_;

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: buypass - batch problem\n";
  print MAILERR "\n";
  print MAILERR "Username: $username\n";
  print MAILERR "orderid: $orderid\n";
  print MAILERR "\nLocked transactions found in trans_log.\n";
  close MAILERR;
}

sub printrecord {
  my ($message) = @_;

  my $len = length($message);
  $message2 = $message;
  $message2 =~ s/([^0-9A-Za-z \n,])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] \n,])/unpack("H2",$1)/ge;
  my $printstr = "$len: $message2" . "\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );
}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  my $printstr = "origtime: $origtime $timezone1\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month2 happens on wday $wday\n";

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $printstr = "The $times2 Sunday of month $month2 happens on the $mday2\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );

  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );

  my $printstr = "newtime: $newtime $timezone2\n\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );
  return $newtime;

}

sub pidcheck {
  my @infilestrarray = &procutils::flagread( "$username", "buypass", "/home/pay1/batchfiles/logs/buypass", "pid.txt" );
  $chkline = $infilestrarray[0];
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $printstr .= "$pidline\n";
    $printstr .= "$chkline\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: buypass - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}
