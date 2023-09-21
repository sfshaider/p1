#!/usr/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SSLeay qw(get_https post_https sslcat make_headers make_form);
use miscutils;
use procutils;
use IO::Socket;
use Socket;
use rsautils;
use smpsutils;
use Time::Local;
use elavon;
use PlugNPay::Legacy::Genfiles;
use PlugNPay::Logging::DataLog;

$devprod = "logs";

$result = "";

my $group = $ARGV[0];
if ( $group eq "" ) {
  $group = "0";
}
my $printstr = "group: $group\n";
&procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/elavon/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'elavon/genfiles.pl $group'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl $group already running, exiting...\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dprice\@plugnpay.com\n";
  print MAILERR "Subject: elavon - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl $group because it's already running.\n\n";
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
&procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "pid$group.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my @infilestrarray = &procutils::fileread( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "pid$group.txt" );
$chkline = $infilestrarray[0];
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  $printstr .= "$pidline\n";
  $printstr .= "$chkline\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dprice\@plugnpay.com\n";
  print MAILERR "Subject: elavon - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

my @checkinstrarray = &procutils::fileread( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "genfiles$group.txt" );
$checkuser = $checkinstrarray[0];
chop $checkuser;

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>='$checkuser'";
}

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $dummy, $today, $time ) = &miscutils::genorderid();
$todaytime = $time;

$starttransdate = $today - 10000;

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/elavon/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/elavon/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/elavon/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/elavon/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/elavon/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/elavon/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/elavon/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/elavon/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/elavon/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/elavon/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dprice\@plugnpay.com\n";
  print MAILERR "Subject: elavon - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory elavon/$devprod/$fileyear.\n\n";
  close MAILERR;
  exit;
}

@orderidval = ();
$orderidstr = "";
$batch_flag = 1;
$file_flag  = 1;

my ( $qmarks, $dateArray ) = &miscutils::dateIn( $onemonthsago, $today, 1 );

my $dbquerystr = <<"dbEOM";
  select t.username,count(t.username),min(o.trans_date)
  from trans_log t, operation_log o
  where t.trans_date IN ($qmarks)
  $checkstring
  and t.finalstatus = 'pending'
  and (t.accttype is NULL or t.accttype='' or t.accttype='credit')
  and o.orderid=t.orderid
  and o.username=t.username
  and o.processor='elavon'
  and o.lastopstatus='pending'
  group by t.username
dbEOM
my @dbvalues = (@$dateArray);
my @sthtransvalarray = &procutils::dbread( "elavon", "genfiles", "pnpdata", $dbquerystr, @dbvalues );
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user $usertdate $usercount\n";
  print "$printstr\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

foreach $username ( sort @userarray ) {
  &dosettle();
}

foreach $username ( sort @erruserarray ) {
  &dosettle();
}

unlink "/home/pay1/batchfiles/$devprod/elavon/batchfile.txt";

# commented temporary for testing
if ( ( !-e "/home/pay1/batchfiles/stopgenfiles.txt" ) && ( !-e "/home/pay1/batchfiles/$devprod/elavon/stopgenfiles.txt" ) ) {
  umask 0033;
  $checkinstr = "";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "genfiles$group.txt", "write", "", $checkinstr );
}

exit;

sub dosettle {
  if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) && ( -e "/home/pay1/batchfiles/$devprod/elavon/stopgenfiles.txt" ) ) {
    unlink "/home/pay1/batchfiles/$devprod/elavon/batchfile.txt";
    last;
  }

  print "dosettle\n";
  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  if ( $usercountarray{$username} > 3000 ) {
    $batchcntuser = 2000;
  } elsif ( $usercountarray{$username} > 2000 ) {
    $batchcntuser = 1500;
  } else {
    $batchcntuser = 1000;
  }

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,features,currency
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $status, $features, $mcurrency ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $dbquerystr = <<"dbEOM";
        select industrycode,batchgroup,banknum,requestorid,contactless
        from elavon
        where username=?
dbEOM
  @dbvalues = ("$username");
  ( $industrycode, $batchgroup, $banknum, $tokenreqid, $ctlsflag ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $ctlsflag = 0;

  my $printstr = "batchgroup: $batchgroup\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  if ( $status ne "live" ) {
    next;
  }

  my $genfiles = new PlugNPay::Legacy::Genfiles();
  my $batchGroupStatus = $genfiles->batchGroupMatch($group,$batchgroup);

  if (!$batchGroupStatus) {
    my $error = $batchGroupStatus->getError();
    my $dataLog = new PlugNPay::Logging::DataLog({'collection' => 'elavon-genfiles-perl'});
    $dataLog->log({
      'username' => $username,
      'error' => $error
    });

    next;
  }

  # commented temporary for testing
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "genfiles$group.txt", "write", "", $checkinstr );

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "write", "", $logfilestr );

  # sweeptime
  my %feature = ();
  if ( $features ne "" ) {
    my @array = split( /\,/, $features );
    foreach my $entry (@array) {
      my ( $name, $value ) = split( /\=/, $entry );
      $feature{$name} = $value;
    }
  }

  if ( $feature{"multicurrency"} == 1 ) {
    print "multicurrency, skipping\n";
    next;
  }

  # sweeptime
  $sweeptime = $feature{'sweeptime'};    # sweeptime=1:EST:19   dstflag:timezone:time
  my $printstr = "sweeptime: $sweeptime\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    my $printstr = "todaytime: $todaytime\n";
    $printstr .= "timezone: $timezone\n";
    $printstr .= "dstflag: $dstflag\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {

      umask 0077;
      $logfilestr = "";
      $logfilestr .= "aaaa  sweephour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  my $printstr = "gmt today: $todaytime\n";
  $printstr .= "est today: $esttime\n";
  $printstr .= "est yesterday: $yesterday\n";
  $printstr .= "settletime: $settletime\n";
  $printstr .= "sweeptime: $sweeptime\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  $logfilestr = "";
  $logfilestr .= "$username  sweeptime: $sweeptime  settletime: $settletime\n";
  $logfilestr .= "$features\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  $batchnum = 0;

  @orderidval   = ();
  $orderidstr   = "";
  $batch_flag   = 1;
  $batchmessage = "";
  @batchdata    = ();
  $netamount    = 0;
  $hashtotal    = 0;
  $batchcnt     = 1;
  $recseqnum    = 0;
  %errorderid   = ();

  my ( $qmarks1, $dateArray1 ) = &miscutils::dateIn( $starttransdate, $today, 1 );

  my $dbquerystr = <<"dbEOM";
    select orderid,trans_date
    from operation_log force index(oplog_tdateuname_idx)
    where trans_date in ($qmarks1)
    and username=?
    and lastoptime>=?
    and lastop in ('postauth','return')
    and lastopstatus='pending'
    and processor='elavon'
    and (voidstatus is NULL or voidstatus ='')
    and (accttype is NULL or accttype='' or accttype='credit')
    and length(auth_code) <> 93
    and length(auth_code) <> 45
dbEOM
  my @dbvalues = ( @$dateArray1, "$username", "$onemonthsagotime" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  @orderidarray      = ();
  %starttdateinarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 2 ) {
    ( $orderid, $trans_date ) = @sthtransvalarray[ $vali .. $vali + 1 ];

    my $printstr = "$orderid\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  foreach $orderid ( sort @orderidarray ) {
    my $printstr = "aaaa $orderid\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

    # operation_log should only have one orderid per username
    if ( $orderid eq $chkorderidold ) {
      next;
    }
    $chkorderidold = $orderid;

    my ( $placeholders, $dates ) = &miscutils::dateIn( $starttransdate, $today, 1 );

    my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,
                 auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,card_zip,
                 authtime,authstatus,forceauthtime,forceauthstatus,cardtype
          from operation_log force index (oplog_tdateuname_idx)
          where orderid = ?
          and username = ?
          and trans_date in ($placeholders)
          and lastoptime >= ?
          and lastop in ('postauth','return')
          and lastopstatus = 'pending'
          and (voidstatus is NULL or voidstatus = '')
          and (accttype is NULL or accttype = '' or accttype = 'credit')
dbEOM
    my @dbvalues = ( "$orderid", "$username", @{$dates}, "$onemonthsagotime" );
    ( $orderid,   $operation,   $trans_date, $trans_time, $enccardnumber, $enclength, $exp,        $amount,        $auth_code,       $avs_code,
      $refnumber, $finalstatus, $cvvresp,    $transflags, $card_zip,      $authtime,  $authstatus, $forceauthtime, $forceauthstatus, $card_type
    )
      = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $orderid eq "" ) {
      next;
    }

    if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/elavon/stopgenfiles.txt" ) ) {
      unlink "/home/pay1/batchfiles/$devprod/elavon/batchfile.txt";
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

    if ( ( $sweeptime ne "" ) && ( $trans_time > $sweeptime ) ) {
      $orderidold = $orderid;
      next;    # transaction is newer than sweeptime
    }

    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "elavon", $enccardnumber );

    ( $placeholders, $dates ) = &miscutils::dateIn( $twomonthsago, $today, 1 );

    my $dbquerystr = <<"dbEOM";
          select amount,trans_date
          from trans_log
          where orderid=?
          and trans_date in ($placeholders)
          and operation in ('auth','forceauth')
          and username=?
          and finalstatus='success'
          and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", @{$dates}, "$username" );
    ( $origamount, $chkdate ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( ( $chkdate < $starttransdate ) && ( $chkdate > '19990101' ) ) {
      $starttransdate = $chkdate;
    }

    my $printstr = "$orderid $operation $starttransdate\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

    #$cardnumber = &rsautils::rsa_decrypt_file($enccardnumber,$enclength,"print enccardnumber 497","/home/pay1/pwfiles/keys/key");
    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/keys/pwfiles/keys/key" );

    $errorflag = &errorchecking();
    if ( $errorflag == 1 ) {
      next;
    }

    if ( $batch_flag == 1 ) {
      &pidcheck();

      $batch_flag   = 0;
      $batchmessage = "";
      @batchdata    = ();
      $batchdetails = "";
      $netamount    = 0;
      $hashtotal    = 0;
      $batchcnt     = 1;
      $recseqnum    = 0;
      %errorderid   = ();

      $batchnum++;
      $batchnum = substr( "000" . $batchnum, -3, 3 );
    }

    $errorderid{$batchcnt} = $orderid;

    ( $placeholders, $dates ) = &miscutils::dateIn( $onemonthsago, $today, 1 );

    my $dbquerystr = <<"dbEOM";
      update trans_log set finalstatus='locked',detailnum=?,result=?
	    where orderid=?
      and trans_date in ($placeholders)
	    and username=?
	    and finalstatus='pending'
      and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$batchcnt", "$time$batchnum", "$orderid", @{$dates}, "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";

    my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,detailnum=?,batchstatus='pending'
          where orderid=?
          and username=?
          and $operationstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time$batchnum", "$batchcnt", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $orderidold = $orderid;
    push( @orderidval, $orderid );
    $orderidstr .= "?,";
    &batchdetail();

    if ( $batchcnt >= $batchcntuser ) {
      chop $orderidstr;
      &batchheader();
      &batchtrailer();
      &sendrecord();
      &endbatch();
      @orderidval = ();
      $orderidstr = "";
      $batch_flag = 1;
      $batchcnt   = 1;
    }
  }

  #$sthtrans->finish;

  if ( $batchcnt > 1 ) {
    chop $orderidstr;
    &batchheader();
    &batchtrailer();
    &sendrecord();
    &endbatch();
    @orderidval = ();
    $orderidstr = "";
    $batch_flag = 1;
    $batchcnt   = 1;
  }

}

sub endbatch {
  ( $d1, $ptoday, $ptime ) = &miscutils::genorderid();

  my $printstr = "result: $result\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  my ( $placeholders, $dates );

  if ( ( $result =~ /GBOK/ ) || ( $result =~ /GB TEST DROPPED/ ) ) {
    my $printstr = "GBOK\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

    foreach my $var (@orderidval) {
      print "ffff $var\n";
    }
    print "$orderidstr\n";

    ( $placeholders, $dates ) = &miscutils::dateIn( $onemonthsago, $today, 1 );

    my $dbquerystr = <<"dbEOM";
      update trans_log set finalstatus='success',trans_time=?
      where orderid in ($orderidstr)
	    and username=?
      and trans_date in ($placeholders)
	    and result=?
	    and finalstatus='locked'
      and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$ptime", @orderidval, "$username", @{$dates}, "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbherrorflag = 0;

    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
            where orderid in ($orderidstr)
            and username=?
            and trans_date in ($tdateinstr)
            and lastoptime>=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$ptime", "$ptime", @orderidval, "$username", @tdateinarray, "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $DBI::errstr =~ /lock.*try restarting/i ) {
      &miscutils::mysleep(60.0);

      my @dbvalues = ( "$ptime", "$ptime", @tdateinarray, "$onemonthsagotime", "$username", "$time$batchnum" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
    } elsif ( $dbherrorflag == 1 ) {
      &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    }

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbherrorflag = 0;

    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
            where orderid in ($orderidstr)
            and username=?
            and trans_date in ($tdateinstr)
            and lastoptime>=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$ptime", "$ptime", @orderidval, "$username", @tdateinarray, "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $DBI::errstr =~ /lock.*try restarting/i ) {
      &miscutils::mysleep(60.0);

      my @dbvalues = ( "$ptime", "$ptime", @tdateinarray, "$onemonthsagotime", "$username", "$time$batchnum" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
    } elsif ( $dbherrorflag == 1 ) {
      &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    }

  } elsif ( $result =~ /RB INV/ ) {
    my $printstr = "RB INV\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
    $batcherrnum = $result;
    $batcherrnum = s/[^0-9]//g;

    my $printstr = "RB INV: $username $batcherrnum\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

    ( $placeholders, $dates ) = &miscutils::dateIn( $onemonthsago, $today, 1 );

    my $dbquerystr = <<"dbEOM";
      update trans_log set finalstatus='problem',descr=?
	    where orderid=?
      and trans_date in ($placeholders)
	    and username=?
	    and result=?
	    and detailnum=?
      and (accttype is NULL or accttype='' or accttype='credit')
	    and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$result", "$errorderid{$batcherrnum}", @{$dates}, "$username", "$time$batchnum", "$batcherrnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );

    ( $placeholders, $dates ) = &miscutils::dateIn( $starttransdate, $today, 1 );

    my $dbquerystr = <<"dbEOM";
      update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?
	    where orderid=?
      and trans_date in ($placeholders)
      and lastoptime>=?
      and username=?
      and batchfile=?
      and detailnum=?
      and postauthstatus='locked'
      and (voidstatus is NULL or voidstatus ='')
      and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$result", "$errorderid{$batcherrnum}", @{$dates}, "$onemonthsagotime", "$username", "$time$batchnum", "$batcherrnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $tmpfilestr = "";
    $tmpfilestr .= "username: $username\n";
    $tmpfilestr .= "orderid: $errorderid{$batcherrnum}\n";
    $tmpfilestr .= "trans_date: $today\n";
    $tmpfilestr .= "lastoptime: $onemonthsagotime\n";
    $tmpfilestr .= "batchfile: $time$batchnum\n";
    $tmpfilestr .= "detailnum: $batcherrnum\n\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "genfproblem.txt", "append", "", $tmpfilestr );

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );

    ( $placeholders, $dates ) = &miscutils::dateIn( $starttransdate, $today, 1 );

    my $dbquerystr = <<"dbEOM";
      update operation_log set returnstatus='problem',lastopstatus='problem',descr=?
	    where orderid=?
      and trans_date in ($placeholders)
      and lastoptime>=?
      and username=?
      and batchfile=?
      and detailnum=?
      and returnstatus='locked'
      and (voidstatus is NULL or voidstatus ='')
      and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$result", "$errorderid{$batcherrnum}", @{$dates}, "$onemonthsagotime", "$username", "$time$batchnum", "$batcherrnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    ( $placeholders, $dates ) = &miscutils::dateIn( $onemonthsago, $today, 1 );

    my $dbquerystr = <<"dbEOM";
      update trans_log set finalstatus='pending'
      where orderid in ($orderidstr)
	    and username=?
      and trans_date in ($placeholders)
	    and result=?
	    and finalstatus='locked'
      and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @orderidval, "$username", @{$dates}, "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where orderid in ($orderidstr)
            and username=?
            and trans_date in ($tdateinstr)
            and lastoptime>=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @orderidval, "$username", @tdateinarray, "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where orderid in ($orderidstr)
            and username=?
            and trans_date in ($tdateinstr)
            and lastoptime>=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @orderidval, "$username", @tdateinarray, "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dprice\@plugnpay.com\n";
    print MAILERR "Subject: elavon - RB INV DATA\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "orderid: $errorderid{$batcherrnum}\n";
    print MAILERR "result: $batcherrnum\n";
    print MAILERR "file: $username$time$pid.txt\n";
    print MAILERR "$result	$descr\n";
    close MAILERR;

  } elsif ( ( $result =~ /RB PLEASE RETRY/ ) || ( $result =~ /RBOUT OF BALANCE/ ) ) {
    my $printstr = "RB PLEASE RETRY\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

    ( $placeholders, $dates ) = &miscutils::dateIn( $onemonthsago, $today, 1 );

    my $dbquerystr = <<"dbEOM";
      update trans_log set finalstatus='pending'
      where orderid in ($orderidstr)
	    and username=?
      and trans_date in ($placeholders)
	    and result=?
	    and finalstatus='locked'
      and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @orderidval, "$username", @{$dates}, "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where orderid in ($orderidstr)
            and username=?
            and trans_date in ($tdateinstr)
            and lastoptime>=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @orderidval, "$username", @tdateinarray, "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where orderid in ($orderidstr)
            and username=?
            and trans_date in ($tdateinstr)
            and lastoptime>=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @orderidval, "$username", @tdateinarray, "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    @erruserarray = ( @erruserarray, $username );

    $fields[14] =~ s/[^0-9a-zA-Z _]//g;
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: elavon - $fields[14]\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $fields[14]\n";
    print MAILERR "file: $username$time$pid.txt\n";
    close MAILERR;

  } elsif ( $result =~ /SERV NOT ALLOWED/ ) {
    my $printstr = "SERV NOT ALLOWED\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

    ( $placeholders, $dates ) = &miscutils::dateIn( $onemonthsago, $today, 1 );

    my $dbquerystr = <<"dbEOM";
      update trans_log set finalstatus='problem',descr='SERV NOT ALLOWED'
      where orderid in ($orderidstr)
	    and username=?
      and trans_date in ($placeholders)
	    and result=?
	    and finalstatus='locked'
      and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( @orderidval, "$username", @{$dates}, "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );

    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?
            where orderid in ($orderidstr)
            and username=?
            and trans_date in ($tdateinstr)
            and lastoptime>=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "SERV NOT ALLOWED", @orderidval, "$username", @tdateinarray, "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );

    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='problem',lastopstatus='problem',descr=?
            where orderid in ($orderidstr)
            and username=?
            and trans_date in ($tdateinstr)
            and lastoptime>=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "SERV NOT ALLOWED", @orderidval, "$username", @tdateinarray, "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";

    print MAILERR "Subject: elavon - SERV NOT ALLOWED\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: SERV NOT ALLOWED\n";
    print MAILERR "file: $username$time$pid.txt\n";
    close MAILERR;
  } else {
    my $printstr = "unknown error\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
    $fields[14] =~ s/[^0-9a-zA-Z _]//g;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";

    print MAILERR "Subject: elavon - unknown error\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $fields[14]\n";
    print MAILERR "file: $username$time$pid.txt\n";
    close MAILERR;
  }
}

sub batchheader {
  $recseqnum = $recseqnum + 2;
  $recseqnum = substr( $recseqnum, -8, 8 );

  @bh    = ();
  $bh[0] = '#';       # network status byte (1)
  $bh[1] = '00';      # network routing code (2)
  $bh[2] = 'E';       # specification type (1)
  $bh[3] = '4039';    # specification version (4)
  $bh[4] = 'E';       # transaction routing code (1)
  $bh[5] = "920";     # transaction code (3)

  my $marketind = "";
  if ( $transflags =~ /moto/ ) {
    $marketind = "M";
  } elsif ( $industrycode eq "retail" ) {
    $marketind = "G";
  } elsif ( $industrycode eq "restaurant" ) {
    $marketind = "R";
  } else {
    $marketind = "I";
  }
  $bh[6] = 'TZ7601' . $marketind . 'C';    # application id (8)

  $bh[7] = $terminal_id;    # terminal id (22)
  $bh[8] = '@conex';        # device tag routing number (6)

  $bh[9]  = pack "H2", "1d";    # group separator
  $bh[10] = "90";               # group identifier (2)
  $bh[11] = "000";              # batch number (3)
  $bh[12] = "$recseqnum";       # record count (8)
  $bh[13] = pack "H2", "1C";    # field separator
  $bh[14] = "$netamount";       # net dollar amount (12)
  $bh[15] = pack "H2", "1C";    # field separator
  $bh[16] = '0';                # net tip amount (12)

  &genrecord( "header", @bh );
}

sub batchtrailer {

  @bt    = ();
  $bt[0] = '#';                 # network status byte (1)
  $bt[1] = '00';                # network routing code (2)
  $bt[2] = 'E';                 # specification type (1)
  $bt[3] = '4039';              # specification version (4)
  $bt[4] = 'E';                 # transaction routing code (1)
  $bt[5] = "929";               # transaction code (3)

  my $marketind = "";
  if ( $transflags =~ /moto/ ) {
    $marketind = "M";
  } elsif ( $industrycode eq "retail" ) {
    $marketind = "G";
  } elsif ( $industrycode eq "restaurant" ) {
    $marketind = "R";
  } else {
    $marketind = "I";
  }
  $bt[6] = 'TZ7601' . $marketind . 'C';    # application id (8)

  $bt[7] = $terminal_id;    # terminal id (22)
  $bt[8] = '@conex';        # device tag routing number (6)

  $bt[9] = pack "H2", "1d"; # group separator (1)
  $bt[11] = "98";           # group identifier (2)
  $transdate = substr( $trans_date, 4, 4 );
  $bt[12] = $transdate;         # transmission date MMDD (4)
  $bt[14] = $recseqnum;         # record count (9)
  $bt[15] = pack "H2", "1C";    # field separator
  $bt[16] = $netamount;         # net dollar amount (16)
  $bt[17] = pack "H2", "1C";    # field separator
  $bt[18] = $hashtotal;         # net dollar amount (16)

  &genrecord( "trailer", @bt );

}

sub batchdetail {
  $transamt = substr( $amount, 4 );
  $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );
  $transamt = substr( "00000000" . $transamt, -8, 8 );
  $authcode = substr( $auth_code,             0,  6 );

  if ( $operation =~ /^(auth|postauth)$/ ) {
    $netamount = $netamount + $transamt;
  } else {
    $netamount = $netamount - $transamt;
  }

  $hashtotal = $hashtotal + $transamt;
  my $printstr = "transamt: $transamt\n";
  $printstr .= "hashtotal: $hashtotal\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  $recseqnum++;
  $recseqnum = substr( $recseqnum, -8, 8 );

  @bd    = ();
  $bd[0] = '#';       # network status byte (1)
  $bd[1] = '00';      # network routing code (2)
  $bd[2] = 'E';       # specification type (1)
  $bd[3] = '4039';    # specification version (4)
  $bd[4] = 'E';       # transaction routing code (1)
  $bd[5] = "921";     # transaction code (3)

  my $marketind = "";
  if ( $transflags =~ /moto/ ) {
    $marketind = "M";
  } elsif ( $industrycode eq "retail" ) {
    $marketind = "G";
  } elsif ( $industrycode eq "restaurant" ) {
    $marketind = "R";
  } else {
    $marketind = "I";
  }
  $bd[6] = 'TZ7601' . $marketind . 'C';    # application id (8)

  $bd[7] = $terminal_id;    # terminal id (22)
  $bd[8] = '@conex';        # device tag routing number (6)

  $bd[9] = pack "H2", "1d"; # group separator (1)
  $bd[10] = "92";           # group identifier (2)
  $recseqnum2 = substr( "0" x 4 . $recseqnum, -4, 4 );
  $bd[11] = $recseqnum2;        # sequence number (4)
  $bd[12] = pack "H2", "1C";    # field separator
  $cardexp = substr( $exp, 0, 2 ) . substr( $exp, 3, 2 );
  $bd[13] = "$cardnumber=$cardexp";    # account data (76)
  $bd[14] = pack "H2", "1C";           # field separator
  $transamount = sprintf( "%d", ( substr( $amount, 4 ) * 100 ) + .0001 );
  $bd[15] = "$transamount";            # transaction amount
  $bd[16] = pack "H2", "1C";           # field separator

  if ( $origamount ne "" ) {
    $amt = sprintf( "%d", ( substr( $origamount, 4 ) * 100 ) + .0001 );
  } else {
    $amt = $transamount;
  }
  $bd[17] = "$amt";                    # original auth amount
  $bd[18] = pack "H2", "1C";           # field separator

  $authcode = substr( $auth_code, 0, 6 );
  $authcode =~ s/ //g;
  $authcode = substr( $auth_code . " " x 6, 0, 6 );
  $bd[19] = $authcode;                 # approval code (6)
  if ( $operation eq "postauth" ) {
    $trandate = substr( $auth_code, 7,  6 );
    $trantime = substr( $auth_code, 13, 6 );
  } elsif ( $operation eq "return" ) {
    $trandate = substr( $trans_time, 4, 4 ) . substr( $trans_time, 2, 2 );
    $trantime = substr( $trans_time, 8, 6 );
  }
  $bd[20] = $trandate;                 # authorization date (6) MMDDYY
  $bd[21] = $trantime;                 # authorization time (6) HHMMSS

  $magstripetrack = substr( $auth_code,            22, 1 );
  $magstripetrack = substr( $magstripetrack . " ", 0,  1 );

  $posentry = "01";
  if ( ( $transflags =~ /ctls/ ) || ( $ctlsflag eq "1" ) ) {
    $posentry = "03";                  # terminal capability
  } elsif ( $magstripetrack =~ /^(0|1|2)$/ ) {
    $posentry = "02";                  # pos entry capability (2)
  }
  $bd[22] = $posentry;                 # pos entry capability (2)

  $acctentry = "01";
  if ( $transflags =~ /use.token/ ) {
    $acctentry = "12";
  } elsif ( $transflags =~ /(recur|install|cit|mit)/ ) {
    $acctentry = "12";
  } elsif ( $magstripetrack =~ /^(1|2)$/ ) {
    $acctentry = "03";                 # account entry mode (2)
  } elsif ( ( $industrycode =~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $acctentry = "02";                 # account entry mode (2)
  }
  $bd[23] = $acctentry;                # account entry mode (2)

  $cardid  = substr( $auth_code,     23, 1 );
  $cardid  = substr( $cardid . " ",  0,  1 );
  $acctsrc = substr( $auth_code,     19, 1 );
  $acctsrc = substr( $acctsrc . " ", 0,  1 );
  my $printstr = "acctsrc: $acctsrc\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  $authsrc     = substr( $auth_code,         20,  1 );
  $authsrc     = substr( $authsrc . " ",     0,   1 );
  $captrancode = substr( $auth_code,         6,   1 );
  $captrancode = substr( $captrancode . " ", 0,   1 );
  $servicecode = substr( $auth_code,         121, 3 );

  $servicecode = substr( $servicecode . " " x 3, 0, 3 );
  if ( $operation eq "return" ) {
    $authsrc     = "9";
    $captrancode = "6";
  }
  if ( ( $operation eq "postauth" ) && ( $forceauthtime ne "" ) ) {
    $acctsrc     = "0";
    $authsrc     = "E";
    $captrancode = "2";
    if ( ( $industrycode =~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
      $captrancode = "5";
    }
  }
  $bd[24] = $cardid;         # card id (1)
  $bd[25] = $acctsrc;        # account source (1)
  $bd[26] = $authsrc;        # authorization source (1)
  $bd[27] = $captrancode;    # capture tran code (1)
  $bd[28] = $servicecode;    # service code (3)

  my $catind = "00";         # not a CAT transaction
  if ( ( $industrycode !~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $catind = "05";
  }
  $bd[29] = $catind;         # cat indicator (2)

  my $elavtokenind  = "0";
  my $assoctokenind = "0";
  if ( $transflags =~ /useptoken/ ) {
    $elavtokenind = "1";
  }
  $bd[30] = $elavtokenind;    # elavon token indicator (1)

  my $termtype = "04";        # no terminal used ecommerce ??
  if ( ( $industrycode =~ /(retail|restaurant)/ ) || ( $transflags =~ /moto/ ) ) {
    $termtype = "00";         # attended terminal
  }
  $bd[31] = $termtype;        # terminal type (2)

  $sqiind = substr( $auth_code,    197, 1 );
  $sqiind = substr( $sqiind . " ", 0,   1 );
  $bd[32] = $sqiind;          # spend qualified indicator (1)

  $bd[33] = '0';              # voucher indicator (1)

  my $storedcredind = 'N';

  if ( $transflags =~ /(init|mit|cit|recur|install)/ ) {
    $storedcredind = "C";
  }
  $bd[34] = $storedcredind;    # stored credential indicator (1)
  $bd[35] = "00";              # number of incrementals (2)

  $bd[36] = " ";               # type of mPOS device (1)
  $bd[37] = "2";               # PIN entry capability (1) 2 no pin capability

  $devicetype = substr( $auth_code, 280, 4 );
  $devicetype =~ s/ //g;
  if ( ( $devicetype ne "" ) || ( $transflags =~ /ctls/ ) ) {
    $transaction[38] = pack "H2", "1d";    # gs (1)
    $transaction[39] = "08";               # mobile/wallet type
    if ( $transflags =~ /ctls/ ) {
      $devicetype = "0102";
    }
    $devicetype = substr( $devicetype . " " x 4, 0, 4 );
    $transaction[40] = $devicetype;
  }

  if ( ( $operation eq "postauth" ) && ( $forceauthtime eq "" ) ) {
    $bd[41] = pack "H2", "1d";             # group separator (1)
    $bd[42] = "93";                        # group identifier (2)
    $avs_code = substr( $avs_code . " ", 0,   1 );
    $cvvresp  = substr( $cvvresp . " ",  0,   1 );
    $ps2000   = $refnumber;
    $msdi     = substr( $auth_code,      124, 1 );
    $msdi     = substr( $msdi . " ",     0,   1 );
    $bd[43] = $avs_code;                   # avs response (3)
    $bd[44] = $cvvresp;                    # cvv response (3)
    $bd[45] = $ps2000;                     # ps2000 data (22)
    $bd[46] = pack "H2", "1C";             # field separator
    $bd[47] = $msdi;                       # msdi data (22)

    my $surcharge = substr( $auth_code, 198, 8 );
    if ( $surcharge > 0 ) {
      $surcharge = substr( "0" x 4 . $surcharge, -4, 4 );
    } else {
      $surcharge = "";
    }
    $bd[48] = $surcharge;                  # surcharge (4)
    $bd[49] = pack "H2", "1C";             # field separator

    my $cashback = substr( $auth_code, 206, 8 );
    if ( $cashback > 0 ) {
      $cashback = substr( "0" x 8 . $cashback, -8, 8 );
      $bd[50] = $cashback;                 # cashback (8)
    } else {
      $cashback = "";
    }

    $bd[51] = pack "H2", "1C";             # field separator
    $bd[52] = "$amt";                      # total auth amount

    $bd[53] = pack "H2", "1C";             # field separator

    $seclevind = substr( $auth_code,           398, 3 );
    $seclevind = substr( $seclevind . " " x 3, 0,   3 );
    $bd[54] = $seclevind;                  # eci security level indicator (3)
  }

  $commcardtype = substr( $auth_code, 24, 1 );
  if ( $commcardtype == 1 ) {
    $bd[60] = pack "H2", "1d";             # group separator (1)
    $bd[61] = "11";                        # group identifier (2)
    $commtax = substr( $auth_code, 25, 7 );
    if ( $commtax eq "0000.00" ) {
      $commtax = "0";
    } else {
      $commtax = substr( "0" x 7 . $commtax, -7, 7 );
    }
    $bd[62] = "$commtax";                  # tax
    $bd[63] = pack "H2", "1C";             # field separator
    $commponumber = substr( $auth_code, 32, 17 );
    $commponumber =~ s/ //g;

    print "auth_code: $auth_code\n";
    print "commtax: $commtax\n";
    print "commponumber: $commponumber\n";
    $bd[64] = "$commponumber";             # format data data = customer number
    my $printstr = "commponum: $commponumber\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  }

  $bd[71] = pack "H2", "1d";               # gs (1)
  $bd[72] = "12";                          # group identifier (2)

  $porderid   = substr( $auth_code, 32,  17 );
  $invoicenum = substr( $auth_code, 255, 25 );
  $invoicenum =~ s/ +$//g;

  my $printstr = "invoicenum: $invoicenum\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  if ( $invoicenum ne "" ) {               # for cert
    $bd[73] = $invoicenum;                 # invoice or order number (25)
  } elsif ( ( $transflags =~ /moto/ ) || ( ( $industrycode !~ /^(retail|restaurant)$/ ) && ( $commcardtype eq "" ) ) ) {
    my $oid = substr( $orderid, -25, 25 );
    $bd[73] = $oid;                        # invoice or order number (25)
  } elsif ( $commcardtype eq "1" ) {
    $commponumber = substr( $auth_code, 32, 17 );
    $commponumber =~ s/ //g;
    $bd[73] = $commponumber;               # invoice or order number (25)
  } else {
    $oid = substr( '0' x 25 . $orderid, -25, 25 );
    $bd[73] = $oid;                        # invoice or order number (25)
  }
  $bd[74] = pack "H2", "1c";               # fs (1)

  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime( time() );
  my $shipdate = sprintf( "%02d%02d%04d", $month + 1, $day, $year + 1900 );
  $bd[75] = $shipdate;                     # shipping date (8) MMDDYYYY

  if ( ( $operation eq "postauth" ) && ( $forceauthtime eq "" ) && ( $industrycode !~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $bd[80] = pack "H2", "1d";    # gs (1)
    $bd[81] = "13";               # group identifier (2)
    $eci       = substr( $auth_code, 125, 1 );
    $eci       = substr( $eci . " ", 0,   1 );
    $cavvascii = substr( $auth_code, 127, 40 );
    $cavvascii =~ s/ //g;
    $ucafind = substr( $auth_code,     126, 1 );
    $ucafind = substr( $ucafind . " ", 0,   1 );
    $bd[82] = "$eci";             # eci value (1)
    $bd[83] = "$cavvascii";       # cavv value (40)
    $bd[84] = pack "H2", "1c";    # fs (1)
    $bd[85] = "$ucafind";         # ucaf indicator (1)
  }

  my $installtot = substr( $auth_code, 168, 2 );
  my $installnum = substr( $auth_code, 170, 2 );
  if ( $transflags =~ /(recurring|bill|install)/ ) {
    my $recurringind = "";
    if ( $transflags =~ /(recurring|bill)/ ) {
      $recurringind = "1";
      $installtot   = "";
      $installnum   = "";
    } elsif ( $transflags =~ /install/ ) {
      $recurringind = "2";
      $installtot   = $installtot;                           # total number of payments
      $installtot   = substr( "00" . $installtot, -2, 2 );
      $installnum   = $installnum;                           # payment sequence number
      $installnum   = substr( "00" . $installnum, -2, 2 );
    }

    $bd[92] = pack "H2", "1d";    # gs (1)
    $bd[93] = "14";               # group identifier (2)
    $bd[94] = $recurringind;      # recurring payment type (1)
    $bd[95] = $installnum;        # installment number (2)
    $bd[96] = pack "H2", "1c";    # fs (1)
    $bd[97] = $installtot;        # installment count (2)
    if ( $transflags =~ /install/ ) {
      $bd[98] = pack "H2", "1c";    # fs (1)
    }
    $bd[99] = "";                   # deferment count (2) number of months to defer payment
  }

  my $dccinfo = substr( $auth_code, 284, 52 );
  if ( ( $transflags =~ /(dcc|multicurrency)/ ) && ( $dccinfo =~ /,/ ) ) {
    my $dccinfo = substr( $auth_code, 284, 52 );

    my ( $dccoptout, $dccamount, $dcccurrency, $dccrate, $dccexponent, $dccdate, $dcctime ) = split( /,/, $dccinfo );
    my $dccind = "";
    if ( $transflags =~ /multicurrency/ ) {
      $dccind = "M";
    } elsif ( $dccoptout eq "Y" ) {
      $dccind = "N";
    } else {
      $dccind = "Y";
    }

    $bd[100] = pack "H2", "1d";    # gs (1)
    $bd[101] = "15";               # group identifier (2)
    $bd[102] = $dccind;            # dcc indicator (1)
    $bd[103] = $dccexponent;       # dcc exponent (1)
    $bd[104] = $dccrate;           # dcc rate (8v)
    $bd[105] = pack "H2", "1c";    # gs (1)
    $bd[106] = $dccamount;         # dcc amount (12v)
    $bd[107] = pack "H2", "1c";    # gs (1)
    $bd[108] = $dcccurrency;       # card currency (3)
    $mcurrency =~ tr/a-z/A-Z/;

    if ( $mcurrency eq "" ) {
      $mcurrency = "USD";
    }
    $bd[109] = $mcurrency;         # merchant currency (3)
  }

  $bd[110] = pack "H2", "1d";      # gs (1)
  $bd[111] = "03";                 # group identifier (2)
  $transseqnum = substr( $auth_code, 110, 11 );
  $transseqnum =~ s/ //g;
  if ( $transseqnum eq "" ) {
    $transseqnum = &smpsutils::gettransid( $username, "elavon", $orderid );
  }
  $transseqnum = substr( "0" x 11 . $transseqnum, -11, 11 );
  $marketdata = substr( $auth_code, 172, 25 );
  $marketdata =~ s/ +$//g;
  if ( ( $forceauthtime ne "" ) && ( $operation eq "postauth" ) ) {
    $transseqnum = "";
  }
  $bd[112] = $transseqnum;         # merchant reference number (11)
  $bd[113] = pack "H2", "1c";      # fs (1)
  $bd[114] = $marketdata;          # dba doing business as (25)

  $bd[115] = pack "H2", "1d";      # gs (1)
  $bd[116] = "04";                 # group identifier (2)
  $origtcode = substr( $auth_code,           105, 3 );
  $origtcode = substr( $origtcode . " " x 3, 0,   3 );
  if ( ( $operation eq "postauth" ) && ( $forceauthtime ne "" ) ) {
    $origtcode = "006";
  } elsif ( $operation eq "return" ) {
    $origtcode = "005";
  }
  $bd[117] = $origtcode;           # original transaction code (3)

  my $merchantdata = substr( $auth_code, 225, 30 );
  $merchantdata =~ s/ +//g;
  if ( $merchantdata eq "" ) {
    $merchantdata = "$orderid";
  }
  $merchantdata = substr( $merchantdata, 0, 39 );
  $bd[121] = pack "H2", "1d";    # gs (1)
  $bd[122] = "B1";               # group identifier (2)
  $bd[123] = $merchantdata;      # merchant data to appear on merchant statement roc text(39a)

  if ( $transflags =~ /use.token/ ) {
    $bd[130] = pack "H2", "1d";    # gs (1)
    $bd[131] = "8F";               # group identifier (2)

    my $tokenstatus = substr( $auth_code, 214, 1 );
    $tokenstatus = substr( $tokenstatus . " ", 0, 1 );
    $bd[132] = "$tokenstatus";     # token account status (1)

    my $tokenlev = substr( $auth_code, 215, 2 );
    $tokenlev = substr( $tokenlev . "  ", 0, 2 );
    $bd[133] = $tokenlev;          # token assurance level (2)

    my $tokenreqid = substr( $tokenreqid . " " x 11, 0, 11 );
    $bd[134] = $tokenreqid;        # token requestor id (11)
  }

  &genrecord( "detail", @bd );

  if ( $operation eq "postauth" ) {
    $filesalesamt = $filesalesamt + $transamt;
    $filesalescnt = $filesalescnt + 1;
  } else {
    $fileretamt = $fileretamt + $transamt;
    $fileretcnt = $fileretcnt + 1;
  }

  $banknumold  = $banknum;
  $usernameold = $username;
  $batchcnt++;
}

sub genrecord {
  my ( $type, @messagearray ) = @_;

  @header = ();

  $header[0] = pack "H2", "02";    # stx
                                   #}
                                   #else {
                                   #  $header[0] = pack "H4", "0031";       # message id "0031" = request to the host
                                   #  $header[1] = pack "H4", "0000";       # destination elavon node id
                                   #  $header[2] = pack "H2", "00";         # destination port
                                   #  $header[3] = pack "H4", "0000";       # source elavon node id
                                   #  $header[4] = pack "H2", "00";         # source port
                                   #  $header[5] = pack "H4", "0000";       # sequence number  (ends on 13)
                                   #}

  $message = "";
  foreach $var (@header) {
    $message = $message . $var;
  }
  foreach $var (@messagearray) {
    $message = $message . $var;
  }

  $trailer = pack "H2", "03";    # etx
                                 #}
  $message = $message . $trailer;

  my $lrc = "";
  my $len = length($message);
  for ( my $i = 0 ; $i < $len ; $i++ ) {
    my $byte = substr( $message, $i, 1 );

    if ( $i != 0 ) {
      $lrc = $byte ^ $lrc;
    }
  }
  $message = $message . $lrc;

  if ( $type eq "header" ) {
    $batchheader = $message;
  } elsif ( $type eq "trailer" ) {
    $batchtrailer = $message;

  } else {
    @batchdata = ( @batchdata, $message );
    $batchdetails = $batchdetails . $message;
  }

}

sub sendrecord {
  $result = "";
  my $status = "";

  my $host = "prodgate02.viaconex.com";    # production  20160926
  my $port = "443";
  &sslsocketopen( "$host", "$port" );      # production

  $checkmessage = $batchheader;
  $checkmessage =~ s/([^0-9A-Za-z \-\$\#])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] \-\$\#])/unpack("H2",$1)/ge;
  $logfilestr = "";

  $mytime = gmtime( time() );
  if ( $secondaryflag == 1 ) {
    $logfilestr .= "\nsecondary\n";
  }
  $logfilestr .= "$host: $port\n";
  $logfilestr .= "$mytime send: $checkmessage\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  &socketwrite($batchheader);
  select undef, undef, undef, .20;

  my @groups = split( /\x1d/, $response );

  foreach my $group (@groups) {
    my $groupid = substr( $group, 0, 2 );

    if ( $groupid eq "9F" ) {
      my @fields = split( /\x1c/, $group );
      $status = substr( $fields[1], 0, 1 );
      $descr = substr( $fields[1], 1 );
      if ( $status ne "A" ) {
        $result = "";
        return;
      }
    }
  }

  if ( $status ne "A" ) {
    $result = "";
    return;
  }

  $messagedata    = "";
  $messagedataold = "";
  foreach $var (@batchdata) {
    $result = "";
    $status = "";

    $messagedata = $var;

    $length = length($messagedata);
    if ( $length > 20 ) {
      select undef, undef, undef, .20;

      $checkmessage = $messagedata;

      $cnum = "";
      if ( $checkmessage =~ /\x1c([0-9]{13,19})\=[0-9]{4}\x1c/ ) {
        $cnum = $1;
        $xs   = "x" x length($cnum);
        $checkmessage =~ s/$cnum/$xs/g;
      }
      $checkmessage =~ s/([^0-9A-Za-z \-\$\#])/\[$1\]/g;
      $checkmessage =~ s/([^0-9A-Za-z\[\] \-\$\#])/unpack("H2",$1)/ge;
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime send: $checkmessage\n";
      &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

      &socketwrite($messagedata);

      my @groups = split( /\x1d/, $response );

      foreach my $group (@groups) {
        my $groupid = substr( $group, 0, 2 );

        if ( $groupid eq "9F" ) {
          my @fields = split( /\x1c/, $group );
          $status = substr( $fields[1], 0, 1 );
          $descr = substr( $fields[1], 1 );
          if ( $status ne "A" ) {
            $result = "";
            return;
          }
        }
      }
      if ( $status ne "A" ) {
        $result = "";
        return;
      }

      $messagedataold = "";
      $messagedata    = $var;
    }
    $messagedataold = $messagedata;
  }
  &miscutils::mysleep(1.0);

  $checkmessage = $batchtrailer;
  $checkmessage =~ s/([^0-9A-Za-z \-\$\#])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] \-\$\#])/unpack("H2",$1)/ge;
  $logfilestr = "";
  $mytime     = gmtime( time() );
  if ( $secondaryflag == 1 ) {
    $logfilestr .= "\nsecondary\n";
  }
  $logfilestr .= "$mytime send: $checkmessage\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  &socketwrite($batchtrailer);

  $batchnumber = "";
  my @groups = split( /\x1d/, $response );

  $result = "";
  $status = "";
  foreach my $group (@groups) {
    my $groupid = substr( $group, 0, 2 );

    if ( $groupid eq "89" ) {
      my @fields = split( /\x1c/, $group );
      $batchnumber = substr( $fields[0], 2, 3 );
      $descr       = substr( $fields[0], 5 );
      $result      = $descr;
    }
  }
  my $printstr = "result: $result\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  $message1 = $response;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;
  $message1 =~ s/\x05/\[05\]\n/g;
  $message1 =~ s/\x06/\[06\]\n/g;
  $message1 =~ s/\x15/\[15\]\n/g;
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$batchnumber	$result	$descr\n";
  my $printstr = "$batchnumber	$result	$descr\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon",            "miscdebug.txt",          "append", "misc", $printstr );
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "",     $logfilestr );

  &sslsocketclose();

}

sub socketwrite {
  ($message) = @_;

  &socketwritefailover($message);
  return;
}

sub socketwritefailover {
  ($message) = @_;

  my $host = "prodgate02.viaconex.com";    # production  20160926
  my $port = "443";

  my $len = length($message);
  my $msg = "POST /cgi-bin/encompass.cgi HTTP/1.1\r\n";
  $msg = $msg . "Content-Length: $len\r\n";
  $msg = $msg . "Host: $host:$port\r\n";
  $msg = $msg . "Registration-Key: 34S8H148QMPM040NF4L7\r\n";

  $msg = $msg . "Connection: Keep-Alive\r\n";
  $msg = $msg . "\r\n";
  $msg = $msg . $message;

  ($response) = &sslsocketwrite( $msg, $host, $port );
}

sub printrecord {
  my ($printmessage) = @_;

  $temp = length($printmessage);
  my $printstr = "$temp\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  ($message2) = unpack "H*", $printmessage;
  my $printstr = "$message2\n\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  $message1 = $printmessage;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;
}

sub socketread {

  vec( $rin, $temp = fileno(SOCK), 1 ) = 1;
  $count    = 4;
  $response = "";
  while ( $count && select( $rout = $rin, undef, undef, 50.0 ) ) {
    $logfilestr = "";
    $logfilestr .= "while\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    recv( SOCK, $response, 2048, 0 );

    $rlen = length($response);

    $nullmessage1 = "aa77000d0011";
    $nullmessage2 = "aa550d001100";

    ($d1) = unpack "H12", $response;
    while ( ( ( $d1 eq $nullmessage1 ) || ( $d1 eq $nullmessage2 ) ) && ( $rlen >= 15 ) ) {
      my $printstr = "in loop\n";
      &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
      $response = substr( $response, 15 );
      $rlen = length($response);
      ($d1) = unpack "H12", $response;
    }

    if ( $rlen > 15 ) {
      ($temp) = unpack "H*", $response;
      my $printstr = "response: $temp\n";
      &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
      last;
    }
    $count--;
  }
  $logfilestr = "";
  $logfilestr .= "end loop\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

}

sub errorchecking {
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
    $card_type = &smpsutils::checkcard($cardnumber);
  }
  if ( $card_type eq "" ) {
    &errormsg( $username, $orderid, $operation, 'bad card number' );
    return 1;
  }
  return 0;
}

sub errormsg {
  my ( $username, $orderid, $operation, $errmsg ) = @_;
  my $printstr = "$username $orderid $operation $errmsg\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where orderid=?
            and trans_date>=?
            and username=?
            and finalstatus='pending'
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$errmsg", "$orderid", "$onemonthsago", "$username" );
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
  my @dbvalues = ( "$errmsg", "$orderid", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

}

sub sslsocketopen {
  my ( $host, $port ) = @_;

  Net::SSLeay::load_error_strings();
  Net::SSLeay::SSLeay_add_ssl_algorithms();
  Net::SSLeay::randomize('/etc/passwd');

  my $dest_serv = $host;
  my $port      = $port;

  my $dnserrorflag = "";
  my $dest_ip      = gethostbyname($dest_serv);
  if ( $dest_ip eq "" ) {
    $dest_serv    = "216.235.178.29";
    $dest_ip      = gethostbyname($dest_serv);
    $dnserrorflag = "dns error";
  }
  my $dest_serv_params = sockaddr_in( $port, $dest_ip );

  my $tmpstr = `nslookup $host`;
  $tmpstr =~ s/\n/jjjj/g;
  $tmpstr =~ s/^.*Name:/Name:/;
  print "tmpstr: $tmpstr\n";

  my $flag = "pass";
  socket( S, &AF_INET, &SOCK_STREAM, 0 ) or return ( &errmssg( "socket: $!", 1 ) );
  print "socket\n";

  connect( S, $dest_serv_params ) or return ( &errmssg( "connect: $!", 1 ) );
  print "connect\n";

  my $sockaddr    = getsockname(S);
  my $sockaddrlen = length($sockaddr);
  if ( $sockaddrlen == 16 ) {
    my ($sockaddrport) = unpack_sockaddr_in($sockaddr);
    my $tmpstr = inet_ntoa($dest_ip);
    $logfilestr = "";
    $logfilestr .= "port: $tmpstr $sockaddrport    $dest_serv  $dnserrorflag\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  }

  if ( $flag ne "pass" ) {
    return;
  }
  select(S);
  $| = 1;
  select(STDOUT);    # Eliminate STDIO buffering

  # The network connection is now open, lets fire up SSL
  # stops "bad mac decode" and "data between ccs and finished" errors by forcing version 2
  $ctx = Net::SSLeay::CTX_tlsv1_2_new() or die_now("Failed to create SSL_CTX $!");    # stops "bad mac decode" and "data between ccs and finished" errors by forcing version 2

  Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL ) and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
  $ssl = Net::SSLeay::new($ctx) or Net::SSLeay::die_now("Failed to create SSL $!");
  Net::SSLeay::set_fd( $ssl, fileno(S) );                                             # Must use fileno
  my $res = Net::SSLeay::connect($ssl) or &error("$!");

  $TMPFILEstr = "";
  $TMPFILEstr .= __FILE__ . ": " . Net::SSLeay::get_cipher($ssl) . "\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod", "ciphers.txt", "append", "", $TMPFILEstr );
}

sub sslsocketclose {
  Net::SSLeay::free($ssl);                                                            # Tear down connection
  Net::SSLeay::CTX_free($ctx);
  close S;
}

sub sslsocketwrite {
  my ( $req, $host, $port ) = @_;

  my $cardnum    = $cardnumber;
  my $sep        = pack "H2", "1c";
  my $xs         = "x" x length($cardnum);
  my $messagestr = $req;
  $messagestr =~ s/$cardnum/$xs/g;
  if ( $messagestr =~ /$xs=([0-9]{4})=1([0-9]{3,4}) {0,1}\x1c/ ) {
    my $exp = $1;
    my $cvv = $2;
    my $xs2 = "x" x length($cvv);
    $messagestr =~ s/$xs=$exp=1$cvv/$xs=$exp=1$xs2/;
  }

  my $cardnumber = $cardnum;

  # Exchange data
  $res = Net::SSLeay::ssl_write_all( $ssl, $req );    # Perl knows how long $msg is

  my $respenc = "";

  my ( $rin, $rout, $temp );
  vec( $rin, $temp = fileno(S), 1 ) = 1;
  my $count = 8;
  while ( $count && select( $rout = $rin, undef, undef, 75.0 ) ) {
    my $got = Net::SSLeay::read($ssl);                # Perl returns undef on failure
    $respenc = $respenc . $got;
    if ( $respenc =~ /\x03|\x06|\x15/ ) {
      last;
    }
    $count--;
  }

  my $response = $respenc;

  my $header;
  ( $header, $response ) = split( /\r{0,1}\n\r{0,1}\n/, $response );

  my $temp         = gmtime( time() );
  my $checkmessage = $response;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $checkmessage =~ s/\[0d\]\[0a\]/\n/g;
  $checkmessage =~ s/\[2d\]/-/g;
  $checkmessage =~ s/\[2e\]/./g;
  $checkmessage =~ s/\[2f\]/\//g;
  $checkmessage =~ s/\[3a\]/:/g;
  $logfilestr = "";
  $logfilestr .= "$temp recv: $checkmessage\n\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  return $response, $header;
}

sub errmssg {
  my ( $mssg, $level ) = @_;

  $result{'MStatus'}     = "problem";
  $result{'FinalStatus'} = "problem";
  $rmessage              = $mssg;

  if ( $level != 1 ) {
    Net::SSLeay::free($ssl);    # Tear down connection
    Net::SSLeay::CTX_free($ctx);
  }
  close S;
}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  my $printstr = "origtime: $origtime $timezone1\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

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

  my $printstr = "The $times1 Sunday of month $month1 happens on the $mday1\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $printstr = "The $times2 Sunday of month $month2 happens on the $mday2\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

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
  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  $printstr .= "newtime: $newtime $timezone2\n\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  return $newtime;

}

sub pidcheck {
  my @infilestrarray = &procutils::fileread( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "pid$group.txt" );
  $chkline = $infilestrarray[0];
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    $printstr .= "$pidline\n";
    $printstr .= "$chkline\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dprice\@plugnpay.com\n";
    print MAILERR "Subject: elavon - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

