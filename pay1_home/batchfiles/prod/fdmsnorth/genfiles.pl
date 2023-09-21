#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use procutils;
use smpsutils;
use isotables;

$devprod     = "prod";
$devprodlogs = "logs";

# fdms north version 1.2

# 2017 fall time change, to prevent genfiles from running twice
# exit if time is between 6am gmt and 7am gmt
my $timechange = "20171105020000";    # 2am eastern on the morning of the time change (1am to 1am to 2am)

my $str6am  = $timechange + 40000;                 # str represents 6am gmt
my $str7am  = $timechange + 50000;                 # str represents 7am gmt
my $time6am = &miscutils::strtotime("$str6am");    # 6am gmt
my $time7am = &miscutils::strtotime("$str7am");    # 7am gmt
my $now     = time();

if ( ( $now >= $time6am ) && ( $now < $time7am ) ) {
  my $printstr = "exiting due to fall time change\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  exit;
}

my $group = $ARGV[0];
if ( $group eq "" ) {
  $group = "0";
}
my $printstr = "group: $group\n";
&procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprodlogs/fdmsnorth/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdmsnorth/genfiles.pl $group'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  exit;
}

$mytime  = time();
$machine = `uname -n`;
$pid     = $$;

chop $machine;
$outfilestr = "";
$pidline    = "$mytime $$ $machine";
$outfilestr .= "$pidline\n";
&procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprodlogs/fdmsnorth", "pid$group.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my $chkline = &procutils::fileread( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprodlogs/fdmsnorth", "pid$group.txt" );
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  $printstr .= "$pidline\n";
  $printstr .= "$chkline\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsnorth - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

# batch cutoff times: 2:30am, 8am, 11:15am, 5pm M-F     12pm Sat   12pm, 7pm Sun

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
( $dummy, $today, $todaytime ) = &miscutils::genorderid();
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime( time() );
$todaylocal = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

$lyear = substr( $year, -2, 2 );
$filejuliandate = sprintf( "%02d%03d", $lyear, $yday + 1 );

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/logs/fdmsnorth/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/fdmsnorth/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/logs/fdmsnorth/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/logs/fdmsnorth/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/fdmsnorth/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/logs/fdmsnorth/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/fdmsnorth/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsnorth - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/fdmsnorth/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;

my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        $checkstring
        and t.finalstatus='pending'
        and (t.accttype is NULL or t.accttype='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastoptime>=?
        and o.lastopstatus='pending'
        and o.processor='fdmsnorth'
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
$mycnt = 0;
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  $mycnt++;
  my $printstr = "aaaa $user  $usercount  $usertdate\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  @userarray = ( @userarray, $user );
  $userbankarray{"$banknumarray{$user} $currencyarray{$user} $user"} = 1;
  $usercountarray{$user}                                             = $usercount;
  $starttdatearray{$user}                                            = $usertdate;
}

foreach $key ( sort keys %userbankarray ) {
  ( $banknum, $currency, $username ) = split( / /, $key );
  ( $d1, $d2, $time ) = &miscutils::genorderid();

  if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprodlogs/fdmsnorth/stopgenfiles.txt" ) ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "stopgenfiles\n";
    my $printstr = "stopgenfiles\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth",        "miscdebug.txt",          "append", "misc", $printstr );
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear", "$username$time$pid.txt", "append", "",     $logfilestr );

    unlink "/home/pay1/batchfiles/$devprodlogs/fdmsnorth/batchfile.txt";
    last;
  }

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprodlogs/fdmsnorth", "genfiles$group.txt", "write", "", $batchfilestr );

  my $printstr = "bbbb $username  $banknum\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprodlogs/fdmsnorth", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,currency,company,city,state,zip,tel,country
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $status, $currency, $company, $city, $state, $merchzip, $phone, $country ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $currency eq "" ) {
    $currency = "usd";
  }

  if ( $status ne "live" ) {
    next;
  }

  my $dbquerystr = <<"dbEOM";
        select industrycode,fedtaxid,vattaxid,categorycode,dcctype,chargedescr,batchtime
        from fdmsnorth
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $industrycode, $fedtaxid, $vattaxid, $categorycode, $dcctype, $chargedescr, $batchgroup ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( ( $group eq "3" ) && ( $batchgroup ne "3" ) ) {
    next;
  } elsif ( ( $group eq "2" ) && ( $batchgroup ne "2" ) ) {
    next;
  } elsif ( ( $group eq "1" ) && ( $batchgroup ne "1" ) ) {
    next;
  } elsif ( ( $group eq "0" ) && ( $batchgroup ne "" ) ) {
    next;
  } elsif ( $group !~ /^(0|1|2|3)$/ ) {
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

  # sweeptime
  $sweeptime = $feature{'sweeptime'};    # sweeptime=1:EST:19   dstflag:timezone:time
  my $printstr = "sweeptime: $sweeptime\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  my $printstr = "gmt today: $todaytime\n";
  $printstr .= "est today: $esttime\n";
  $printstr .= "est yesterday: $yesterday\n";
  $printstr .= "settletime: $settletime\n";
  $printstr .= "sweeptime: $sweeptime\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  my $printstr = "cccc $username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

  $logfilestr = "";
  $logfilestr .= "$username $usercountarray{$username} $starttransdate $currency\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  umask 0077;
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

  $logfilestr = "";
  $logfilestr .= "$username  sweeptime: $sweeptime  settletime: $settletime\n";
  $logfilestr .= "$features\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  my $dbquerystr = <<"dbEOM";
        select orderid,trans_date,substr(auth_code,180,38)
        from operation_log force index(oplog_tdateloptimeuname_idx)
        where trans_date>=?
        and lastoptime>=?
        and username=?
        and lastop in ('postauth','return')
        and lastopstatus='pending'
        and (voidstatus is NULL or voidstatus ='')
        and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$starttransdate", "$onemonthsagotime", "$username" );
  my @sthtrans2valarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  %orderidarray      = ();
  %starttdateinarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthtrans2valarray) ; $vali = $vali + 3 ) {
    ( $orderid, $trans_date, $marketdata ) = @sthtrans2valarray[ $vali .. $vali + 2 ];

    $marketdata =~ tr/a-z/A-Z/;
    $orderidarray{ "$marketdata" . "cc" . "$orderid" } = 1;
    $starttdateinarray{"$username $trans_date"} = 1;
  }

  $marketdataold = "";
  foreach my $keya ( sort keys %orderidarray ) {
    ( $marketdata, $orderid ) = split( /cc/, $keya, 2 );

    my $dbquerystr = <<"dbEOM";
          select lastop,trans_date,lastoptime,enccardnumber,length,amount,auth_code,avs,lastopstatus,transflags,card_exp,cvvresp,refnumber,
                 authtime,authstatus,forceauthtime,forceauthstatus,origamount,reauthstatus
          from operation_log
          where orderid=?
          and username=?
          and trans_date>=?
          and trans_date<=?  
          and lastoptime>=?
          and lastop in ('postauth','return')
          and lastopstatus in ('pending','locked')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$starttransdate", "$today", "$onemonthsagotime" );
    ( $operation, $trans_date, $trans_time, $enccardnumber, $length,     $amount,        $auth_code,       $avs_code,   $finalstatus, $transflags,
      $exp,       $cvvresp,    $refnumber,  $authtime,      $authstatus, $forceauthtime, $forceauthstatus, $origamount, $reauthstatus
    )
      = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprodlogs/fdmsnorth/stopgenfiles.txt" ) ) {

      unlink "/home/pay1/batchfiles/$devprodlogs/fdmsnorth/batchfile.txt";
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
      next;    # transaction is newer than sweeptime
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "fdmsnorth", $enccardnumber );

    if ( ( ( $username ne $usernameold ) || ( $marketdata ne $marketdataold ) ) && ( $batch_flag == 0 ) ) {
      &batchtrailer();
      $batch_flag = 1;
    }

    if ( $file_flag == 1 ) {
      &fileheader();
    }

    if ( $batch_flag == 1 ) {
      &pidcheck();
      &batchheader();
    }

    my $dbquerystr = <<"dbEOM";
        update trans_log set finalstatus='locked',result=?
	where username=?
	and trans_date>=?
	and orderid=?
	and finalstatus='pending'
	and operation=?
        and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time$summaryid", "$username", "$twomonthsago", "$orderid", "$operation" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending'
          where orderid=?
          and username=?
          and $operationstatus ='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time$summaryid", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    # insert into batchfilesfdmsn

    $batchreccnt++;
    $filereccnt++;

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $card_type = &smpsutils::checkcard($cardnumber);
    if ( $card_type =~ /(dc|jc)/ ) {
      $card_type = 'ds';
    }

    &batchdetail();

    if ( $transseqnum >= 998 ) {
      &batchtrailer();
      $batch_flag = 1;
    }

    if ( $batchcount >= 998 ) {
      &filetrailer();
      $file_flag = 1;
    }

    $banknumold     = $banknum;
    $currencyold    = $currency;
    $usernameold    = $username;
    $merchant_idold = $merchant_id;
    $batchidold     = "$time$summaryid";
    $marketdataold  = $marketdata;

  }

}

if ( $batch_flag == 0 ) {
  &batchtrailer();
  $batch_flag = 1;
}

if ( $file_flag == 0 ) {
  &filetrailer();
  $file_flag = 1;
}

unlink "/home/pay1/batchfiles/$devprodlogs/fdmsnorth/batchfile.txt";

umask 0033;
$batchfilestr = "";
&procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprodlogs/fdmsnorth", "genfiles$group.txt", "write", "", $batchfilestr );

$mytime = gmtime( time() );
umask 0077;
$outfilestr = "";
$outfilestr .= "\n\n$mytime\n";
&procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprodlogs/fdmsnorth", "ftplog.txt", "append", "", $outfilestr );

system("/home/pay1/batchfiles/$devprod/fdmsnorth/putfiles.pl");

exit;

sub batchdetail {

  $origoperation = "";
  if ( $operation eq "postauth" ) {
    my $dbquerystr = <<"dbEOM";
          select authtime,authstatus,forceauthtime,forceauthstatus
          from operation_log
          where orderid=?
          and username=?
          and lastoptime>=?
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$onemonthsagotime" );
    ( $authtime, $authstatus, $forceauthtime, $forceauthstatus ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( ( $authtime ne "" ) && ( $authstatus eq "success" ) ) {
      $auth_time     = $authtime;
      $origoperation = "auth";
    } elsif ( ( $forceauthtime ne "" ) && ( $forceauthstatus eq "success" ) ) {
      $auth_time     = $forceauthtime;
      $origoperation = "forceauth";
    } else {
      $auth_time     = "";
      $origoperation = "";
    }

    if ( $trans_time < 1000 ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "Error in batch detail: couldn't find trans_time $username $twomonthsago $orderid $trans_time\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      return;
    }
  }

  $transseqnum++;
  $transseqnum = substr( "0" x 6 . $transseqnum, -6, 6 );

  $addendum = 0;

  $transtime = substr( $trans_time, 8, 6 );

  ( $transcurr, $transamt ) = split( / /, $amount );
  $transcurr =~ tr/a-z/A-Z/;
  $transexp = $isotables::currencyUSD2{$transcurr};
  $transamt = sprintf( "%010d", ( ( $transamt * ( 10**$transexp ) ) + .0001 ) );

  $clen = length($cardnumber);
  $cabbrev = substr( $cardnumber, 0, 4 );

  $tcode     = substr( $tcode . " " x 2,     0, 2 );
  $transtime = substr( $transtime . " " x 6, 0, 6 );

  $authresp = substr( $authresp . " " x 2, 0, 2 );
  $avs_code = substr( $avs_code . " " x 1, 0, 1 );

  # yyyy
  $dccinfo     = substr( $auth_code, 186, 27 );
  $dccoptout   = substr( $dccinfo,   0,   1 );    # optout (1)  amount (12)  currency (3)  0's (3)  rate (7)  exponent (1)
  $dccamount   = substr( $dccinfo,   1,   12 );
  $dcccurrency = substr( $dccinfo,   13,  3 );
  $dccrate     = substr( $dccinfo,   19,  7 );
  $dccexponent = substr( $dccinfo,   26,  1 );

  $detailcount++;

  $commflag = substr( $auth_code, 221, 1 );
  $commflag =~ s/ //g;

  $trandategmt = "";
  if ( $card_tpe eq "vi" ) {
    $trandate = substr( $auth_code, 26, 4 );
    $trandate =~ s/ //g;
    $trandategmt = $trandate;
  } else {
    my $loctime = &miscutils::strtotime($auth_time);

    my ( $llsec, $llmin, $llhour, $llday, $llmonth, $llyear, $wday, $yday, $isdst ) = localtime($loctime);
    $trandate = sprintf( "%02d%02d", $llmonth + 1, $llday );
    $trandate = substr( $trandate . " " x 4, 0, 4 );

    my ( $llsec, $llmin, $llhour, $llday, $llmonth, $llyear, $wday, $yday, $isdst ) = gmtime($loctime);
    $trandategmt = sprintf( "%02d%02d", $llmonth + 1, $llday );
    $trandategmt = substr( $trandategmt . " " x 4, 0, 4 );
  }

  if ( $tran_date eq "" ) {
    my ( $llsec, $llmin, $llhour, $llday, $llmonth, $llyear, $wday, $yday, $isdst ) = localtime( time() );
    $transdate = sprintf( "%02d%02d", $llmonth + 1, $llday );
    $transtime = sprintf( "%02d%02d", $llhour,      $llmin );
    $llyear = substr( $llyear, -2, 2 );
    $transyymmdd = sprintf( "%02d%02d%02d", $llyear, $llmonth + 1, $llday );

    my ( $llsec, $llmin, $llhour, $llday, $llmonth, $llyear, $wday, $yday, $isdst ) = gmtime( time() );
    $transdategmt = sprintf( "%02d%02d", $llmonth + 1, $llday );
    $transtimegmt = sprintf( "%02d%02d", $llhour,      $llmin );
    $llyear = substr( $llyear, -2, 2 );
    $transyymmddgmt = sprintf( "%02d%02d%02d", $llyear, $llmonth + 1, $llday );
  } else {
    my $loctime = &miscutils::strtotime($trans_time);
    my ( $llsec, $llmin, $llhour, $llday, $llmonth, $llyear, $wday, $yday, $isdst ) = localtime($loctime);
    $transdate = sprintf( "%02d%02d", $llmonth + 1, $llday );
    $transtime = sprintf( "%02d%02d", $llhour,      $llmin );
    $llyear = substr( $llyear, -2, 2 );
    $transyymmdd = sprintf( "%02d%02d%02d", $llyear, $llmonth + 1, $llday );

    my ( $llsec, $llmin, $llhour, $llday, $llmonth, $llyear, $wday, $yday, $isdst ) = gmtime($loctime);
    $transdategmt = sprintf( "%02d%02d", $llmonth + 1, $llday );
    $transtimegmt = sprintf( "%02d%02d", $llhour,      $llmin );
    $llyear = substr( $llyear, -2, 2 );
    $transyymmddgmt = sprintf( "%02d%02d%02d", $llyear, $llmonth + 1, $llday );
  }

  $outfile2str .= "$username  $orderid  $operation  $transflags\n";

  @bd           = ();
  $bd[0]        = "E";                                       # record id (1a)  pg. 10-77
  $bd[1]        = "    ";                                    # store id (4a)
  $bd[2]        = "    ";                                    # terminal id (4a)
  $categorycode = substr( $categorycode . " " x 4, 0, 4 );
  $bd[3]        = "$categorycode";                           # merchant category code (4a)

  if ( ( $card_type eq "mc" ) && ( $transflags !~ /moto/ ) && ( $industrycode !~ /^(retail|restaurant$)/ ) ) {
    $cat = "6";
  } else {
    $cat = " ";
  }
  $bd[4] = $cat;                                             # cardholder activated terminal CAT (1a)

  $magstripetrack = substr( $auth_code, 25, 1 );
  $magstripetrack =~ s/ //g;
  if ( $magstripetrack =~ /^(1|2)$/ ) {
    $magstatus = "90";
  } else {
    $magstatus = "01";
  }
  $bd[5] = $magstatus;                                       # magnetic stripe status (2a)

  if ( ( $card_type eq "vi" ) && ( $transflags =~ /install/ ) ) {
    $visaind = " ";
  } elsif ( ( $card_type eq "vi" ) && ( $transflags =~ /recurring/ ) ) {
    $visaind = " ";
  } elsif ( ( $card_type eq "vi" ) && ( $transflags !~ /moto/ ) && ( $industrycode =~ /^(bill$)/ ) ) {
    $visaind = "1";
  } elsif ( ( $card_type eq "vi" ) && ( $transflags !~ /moto/ ) && ( $industrycode !~ /^(retail|restaurant$)/ ) ) {
    $visaind = "1";
  } else {
    $visaind = " ";
  }
  $bd[6] = $visaind;    # visa service development (1a)
  $bd[7] = " " x 6;     # filler (6a)

  if ( $origoperation eq "forceauth" ) {
    $authsrc = "D";
  } elsif ( $operation eq "return" ) {
    $authsrc = " ";
  } else {
    $authsrc = "5";
  }
  $bd[8] = $authsrc;    # authorization source (1a)

  if ( ( $industrycode =~ /^(retail|restaurant)$/ ) && ( $transflags !~ /moto/ ) ) {
    $postermcap = "2";
  } else {
    $postermcap = "9";
  }
  $bd[9] = $postermcap;    # POS terminal capability (1a)

  if ( $magstripetrack eq "2" ) {
    $posentry = "9";
  } elsif ( $magstripetrack eq "1" ) {
    $posentry = "9";
  } else {
    $posentry = "1";
  }
  $bd[10] = $posentry;     # entry mode (1a)

  if ( $debitflag == 1 ) {
    $cardid = "2";
  } elsif ( ( $industrycode =~ /retail|restaurant/ ) && ( $transflags !~ /recurring|install|bill|moto/ ) ) {
    $cardid = "1";
  } else {
    $cardid = "4";
  }
  $bd[11] = $cardid;       # cardholder ID (1a)

  $mzip = $merchzip;
  $mzip =~ s/[^0-9a-zA-Z]//g;
  $mzip = substr( $mzip . " " x 9, 0, 9 );
  $bd[12] = $mzip;         # merchant zip (9a)
  $bd[13] = " " x 6;       # filler (6a)
  $recseqnum++;
  $recseqnum = substr( "0" . $recseqnum, -6, 6 );
  $bd[14] = "$recseqnum";    # record sequence number (6n)
  $bd[15] = " " x 32;        # filler (32a)

  foreach $var (@bd) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
  }

  $outfilestr  .= "\n";
  $outfile2str .= "\n";

  if (
    ( ( $card_type eq "vi" ) && ( ( ( $operation ne "return" ) && ( $origoperation ne "forceauth" ) && ( $industrycode !~ /retail|restaurant/ ) )
        || ( $commflag == 1 ) )
    )
    || ( ( $card_type =~ /mc|ax/ ) && ( $commflag == 1 ) )
    ) {
    # pg. 10-79
    @bd = ();
    $bd[0] = "XN01";    # record id (4a)  pg. 10-79

    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)

    if ( ( $card_type eq "vi" ) && ( $commflag == 1 ) ) {
      $ponumber = substr( $auth_code, 30, 17 );
      $ponumber =~ s/ //g;
      if ( $ponumber eq "" ) {
        $ponumber = substr( $orderid, -17, 17 );
      }
      $ponumber = substr( $ponumber . " " x 17, 0, 17 );
      $bd[2] = $ponumber;     # customer code (17a)
      $bd[3] = " " x 8;       # filler (8a)
    } elsif ( ( $card_type =~ /^(mc|ax)$/ ) && ( $commflag == 1 ) ) {
      $ponumber = substr( $auth_code, 30, 17 );
      $ponumber =~ s/ //g;
      if ( $ponumber eq "" ) {
        $ponumber = substr( $orderid, -17, 17 );
      }
      $ponumber = substr( $ponumber . " " x 25, 0, 25 );
      $bd[2] = $ponumber;     # customer code (25a)
    } elsif ( ( $transflags =~ /recurring|bill|install|moto/ ) || ( $industrycode !~ /^(retail|restaurant)$/ ) ) {
      $oid = substr( $orderid,        -15, 15 );
      $oid = substr( $oid . " " x 15, 0,   15 );
      $bd[2] = $oid;          # order number (15a)

      $custphone = $phone;
      $custphone =~ s/[^0-9]//g;
      $custphone = substr( $custphone . " " x 10, 0, 10 );
      $bd[3] = $custphone;    # customer service number (10n)
    }
    $bd[4] = " " x 45;        # filler (45a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  # F record pg. 10-81  dcc
  ($currency) = split( / /, $amount );
  if ( $currency ne "usd" ) {
    @bd    = ();
    $bd[0] = "F";        # record id (1a)  pg. 10-81
    $bd[1] = " " x 9;    # filler (9a)
    $currency =~ tr/a-z/A-Z/;
    $bd[2] = $currency;    # currency code (3n)

    $dccinfo     = substr( $auth_code, 186, 27 );
    $dccoptout   = substr( $dccinfo,   0,   1 );    # optout (1)  amount (12)  currency (3)  0's (3)  rate (7)  exponent (1)
    $dccamount   = substr( $dccinfo,   1,   12 );
    $dcccurrency = substr( $dccinfo,   13,  3 );
    $dccrate     = substr( $dccinfo,   19,  7 );
    $dccexponent = substr( $dccinfo,   26,  1 );

    if ( ( $dccrate > 0 ) && ( $dccoptout eq "N" ) ) {

      $bd[3] = "x" x 6;                             # dcc transaction time (6a)
      $bd[4] = "x";                                 # dcc indicator (1a)
      $bd[5] = "xxx";                               # dcc time zone of transaction (3a)
      $bd[6] = " " x 7;                             # filler (7a)
      $recseqnum++;
      $recseqnum = substr( "0" . $recseqnum, -6, 6 );
      $bd[7] = "$recseqnum";                        # record sequence number (6n)
      $bd[8] = "x" x 9;                             # dcc foreign exchange rate (9n)
      $bd[9] = " " x 19;                            # filler (19a)
    } else {
      $bd[3] = " " x 17;                            # filler (17a)
      $recseqnum++;
      $recseqnum = substr( "0" . $recseqnum, -6, 6 );
      $bd[4] = "$recseqnum";                        # record sequence number (6n)
      $bd[5] = " " x 45;                            # filler (45a)
    }

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  # OR1 record  ax restaurant  pg. 10-101
  #if (($card_type eq "ax") && ($industrycode eq "restaurant")) {}
  if ( ( $card_type eq "ax" ) && ( $industrycode eq "restaurant" ) && ( $operation ne "return" ) && ( $origoperation ne "forceauth" ) ) {
    @bd    = ();
    $bd[0] = "OR1";         # record id (4a)  pg. 10-106
    $bd[1] = "FOOD    ";    # record id (4a)  pg. 10-106

    $gratuity = substr( $auth_code,          282, 8 );
    $gratuity = substr( "0" x 8 . $gratuity, -8,  8 );

    $amt = substr( $amount, 4 );
    $amt = sprintf( "%d", ( $amt * 100 ) + .0001 );

    $foodamt = $amt - $gratuity;
    $foodamt = substr( "0" x 8 . $foodamt, -8, 8 );

    $bd[2] = "$foodamt";     # food amount (8n)
    $bd[3] = "00000001";     # tip id (8a)
    $bd[4] = "$gratuity";    # gratuity (8n)
    $bd[5] = " " x 18;       # filler (18a)
    $recseqnum++;
    $recseqnum = substr( "0" . $recseqnum, -6, 6 );
    $bd[6] = "$recseqnum";    # record sequence number (6n)
    $bd[7] = " " x 21;        # filler (21a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";

    # OR 2 record ax

  }

  # XM05  url or email address visa
  # XM06  url or email address mastercard, ax, discover pg. 10-104

  if ( ( $card_type =~ /vi|mc|ax/ ) && ( $commflag == 1 ) ) {

    # XD23  purchase card reference id number  destination country  pg. 10-106
    @bd = ();
    $bd[0] = "XD23";    # record id (4a)  pg. 10-106
    $recseqnum++;
    $recseqnum = substr( "0" . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)
    $bd[2] = "   ";           # filler (3a)

    $ponumber = substr( $auth_code, 30, 17 );
    $ponumber =~ s/ //g;
    if ( $ponumber eq "" ) {
      $ponumber = substr( $orderid, -17, 17 );
    }
    $ponumber = substr( $ponumber . " " x 17, 0, 17 );
    $bd[3] = "$ponumber";     # purchase reference identifier (17a)

    $country = substr( $auth_code, 47, 2 );
    $country =~ s/ //g;
    if ( $country eq "" ) {
      $country = "US";
    }
    $country =~ tr/a-z/A-Z/;
    $country = $isotables::countryUSUSA{$country};
    $country = substr( $country . " " x 3, 0, 3 );
    if ( $card_type eq "ax" ) {
      $country = "   ";
    }
    $bd[4] = "$country";    # destination country (3a)
    $bd[5] = " " x 8;       # extended purchase reference identifier (8a)
    $bd[6] = " " x 39;      # filler (39a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";

  }

  if ( ( $card_type =~ /^(vi|mc)$/ ) || ( ( $card_type =~ /^(ax)$/ ) && ( $commflag == 1 ) ) ) {

    # XD24  purchase card tax freight duty  pg. 10-107
    @bd = ();
    $bd[0] = "XD24";    # record id (4a)  pg. 10-107
    $recseqnum++;
    $recseqnum = substr( "0" . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)

    $tax = substr( $auth_code, 49, 10 );
    $tax =~ s/ //g;
    $tax = substr( "0" x 13 . $tax, -13, 13 );
    if ( $card_type eq "ax" ) {
      $taxind = " ";
    } elsif ( $transflags =~ /exempt/ ) {
      $taxind = "N";
      $tax    = "0" x 13;
    } elsif ( $tax == 0 ) {
      $taxind = " ";
    } else {
      $taxind = "Y";
    }
    $bd[2] = "$tax";    # local tax amount (13n)

    $discount = substr( $auth_code, 59, 11 );
    $discount =~ s/ //g;
    $discount = substr( "0" x 13 . $discount, -13, 13 );
    $bd[3] = "$discount";    # discount amount (13n)

    $freight = substr( $auth_code, 70, 11 );
    $freight =~ s/ //g;
    $freight = substr( "0" x 13 . $freight, -13, 13 );
    $bd[4] = "$freight";     # freight amount (13n)

    $duty = substr( $auth_code, 81, 11 );
    $duty =~ s/ //g;
    $duty = substr( "0" x 13 . $duty, -13, 13 );
    $bd[5] = "$duty";        # duty amount (13n)

    $bd[6] = "$taxind";      # local tax indicator (1a)

    if ( $card_type eq "ax" ) {
      $discountind = " ";
    } elsif ( $discount == 0 ) {
      $discountind = "N";
    } else {
      $discountind = "Y";
    }
    $bd[7] = "$discountind";    # discount amount indicator (1a)

    if ( $card_type eq "ax" ) {
      $freightind = " ";
    } elsif ( $freight == 0 ) {
      $freightind = "N";
    } else {
      $freightind = "Y";
    }
    $bd[8] = "$freightind";     # freight amount indicator (1a)

    if ( $card_type eq "ax" ) {
      $dutyind = " ";
    } elsif ( $duty == 0 ) {
      $dutyind = "N";
    } else {
      $dutyind = "Y";
    }
    $bd[9] = "$dutyind";        # duty amount indicator (1a)

    $bd[10] = " " x 14;         # filler (14a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";

  }

  if ( ( $card_type =~ /^(vi|mc|ax)$/ ) && ( $commflag == 1 ) ) {

    # XD25  purchase card ship to zip, merchant zip pg. 10-109
    @bd = ();
    $bd[0] = "XD25";    # record id (4a)  pg. 10-109
    $recseqnum++;
    $recseqnum = substr( "0" . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)

    $shipzip = substr( $auth_code, 92, 9 );
    $shipzip =~ s/ //g;
    if ( length($shipzip) == 9 ) {
      $shipzip = substr( $shipzip, 0, 5 ) . "-" . substr( $shipzip, 5, 4 );
    }
    $shipzip = substr( $shipzip . " " x 10, 0, 10 );
    $bd[2] = "$shipzip";      # destination zip (10a)

    $mzip = $merchzip;
    $mzip =~ s/[^0-9a-zA-Z]//g;
    if ( length($mzip) == 9 ) {
      $mzip = substr( $mzip, 0, 5 ) . "-" . substr( $mzip, 5, 4 );
    }
    $mzip = substr( $mzip . " " x 10, 0, 10 );
    if ( $card_type eq "ax" ) {
      $mzip = " " x 10;
    }
    $bd[3] = "$mzip";         # merchant zip (10a)

    $bd[4] = "$mzip";         # ship from zip (10a)

    $bd[5] = " " x 40;        # filler (40a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";

    # XD31  purchase card level 3 item description  pg. 10-110
    # XD32  purchase card level 3 item description  pg. 10-111
    # XD33  purchase card level 3 item amount  pg. 10-112
    # XD34  purchase card level 3 unit  pg. 10-113
    # XD35  purchase card item tax  pg. 10-113
    # XD36  purchase card customer code mastercard  pg. 10-114
    # XD37  purchase card level 3 austin tetra num  pg. 10-114
  }

  # CP01  product descriptor record  pg. 10-114

  my $freeformdata = substr( $auth_code, 255, 20 );
  $freeformdata =~ s/ +$//g;
  if (
       ( ( $card_type eq "vi" ) && ( ( ( $operation ne "return" ) && ( $transflags =~ /moto/ ) ) || ( ( $transflags !~ /moto/ ) && ( $industrycode !~ /^(retail|restaurant)$/ ) ) ) )
    || ( $freeformdata ne "" )
    || ( ( $card_type eq "mc" )
      && ( $operation ne "return" )
      && ( ( $transflags =~ /moto/ ) || ( ( $industrycode !~ /^(retail|restaurant)$/ ) && ( $transflags =~ /^(recurring|bill|install)$/ ) ) ) )
    ) {
    # S  special condition record
    @bd    = ();
    $bd[0] = "S";    # record id (1a)  pg. 10-116
    $bd[1] = "N";    # quasi cash indicator (1a)

    $eci = substr( $auth_code, 161, 2 );
    $eci =~ s/ //g;
    if ( $industrycode =~ /^(retail|restaurant)$/ ) {
      $eci = ' ';    # request flag (2n) 08 = non-secure
    } elsif ( ( $card_type ne "vi" ) && ( $operation eq "return" ) ) {
      $eci = ' ';    # request flag (2n) 08 = non-secure
    } elsif ( ( $card_type =~ /ax|ds/ ) && ( ( $transflags =~ /recurring/ ) ) ) {
      $eci = ' ';    # request flag (2n) 08 = non-secure 2?
    } elsif ( ( $card_type =~ /ax|ds/ ) && ( ( $industrycode =~ /^(retail|restaurant)$/ ) || ( $transflags =~ /moto/ ) ) ) {
      $eci = ' ';    # request flag (2n) 08 = non-secure
    } elsif ( $card_type =~ /ax|ds/ ) {
      $eci = ' ';    # request flag (2n) 08 = non-secure
    } elsif ( ( $card_type eq "mc" ) && ( $operation eq "postauth" ) && ( $transflags =~ /moto,recurring/ ) ) {
      $eci = "2";    # request flag (2n) 08 = non-secure
    } elsif ( ( $card_type eq "mc" ) && ( $operation eq "postauth" ) && ( $transflags =~ /moto/ ) ) {
      $eci = "1";    # request flag (2n) 08 = non-secure
    } elsif ( $card_type eq "mc" ) {
      $eci = " ";    # request flag (2n) 08 = non-secure
    } elsif ( $eci > 0 ) {
      $eci = substr( $eci, -1, 1 );    # request flag (2n) 08 = non-secure
    } elsif ( $transflags =~ /install/ ) {
      $eci = "3";                      # request flag (2n) 08 = non-secure
    } elsif ( ( $card_type ne "mc" ) && ( $transflags =~ /recurring/ ) ) {
      $eci = "2";                      # request flag (2n) 08 = non-secure
    } elsif ( $transflags =~ /moto/ ) {
      $eci = "1";                      # request flag (2n) 08 = non-secure
    } else {
      $eci = '7';                      # request flag (2n) 08 = non-secure
    }
    $bd[2] = "$eci";                   # special condition indicator (1a)

    $installnum = substr( $auth_code, 101, 2 );
    $installnum =~ s/ //g;
    $installnum = substr( "0" x 2 . $installnum, -2, 2 );
    $bd[3] = "$installnum";            # clearing sequence (2n)

    $installtot = substr( $auth_code, 103, 2 );
    $installtot =~ s/ //g;
    $installtot = substr( "0" x 2 . $installtot, -2, 2 );
    $bd[4] = "$installtot";            # clearing count (2n)

    if ( $industrycode !~ /^(retail|restaurant)$/ ) {
      $phoneind = "Y";
    } else {
      $phoneind = "N";
    }
    $bd[5] = "$phoneind";              # customer service phone prt flag (1a)
    $bd[6] = " " x 34;                 # filler (34a)
    $recseqnum++;
    $recseqnum = substr( "0" . $recseqnum, -6, 6 );
    $bd[7] = "$recseqnum";             # record sequence number (6n)

    $specialuse = " " x 19;
    if ( $freeformdata ne "" ) {
      $freeformdata = substr( $freeformdata . " " x 12, 0, 12 );
      $specialuse = " " x 6 . $freeformdata . " ";
    }
    $bd[8] = $specialuse;              # special use fields (19a)

    $transind = " ";

    $bd[9]  = "$transind";             # merchant transaction indicator (1a)
    $bd[10] = " ";                     # certified for mastercard merchant advice code (1a)
    $bd[11] = "  ";                    # mastercard transaction category indicator (2a)
    $bd[12] = " " x 9;                 # filler (9a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  # XD28  purchase card VAT tax  pg. 10-110

  if ( ( $card_type eq "ax" ) && ( $operation ne "return" ) && ( $origoperation ne "forceauth" ) ) {

    # XE01  supplemental ax  pg. 10-119
    @bd = ();
    $bd[0] = "XE01";    # record id (4a)  pg. 10-116
    $recseqnum++;
    $recseqnum = substr( "0" . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)
    $posdata = substr( $auth_code,          105, 12 );
    $posdata = substr( $posdata . " " x 12, 0,   12 );
    $bd[2]   = "$posdata";

    #$bd[2] = "xxxx";   		# card input capability (1a)
    #$bd[3] = "xxxx";   		# card auth capability (1a)
    #$bd[4] = "xxxx";   		# card capture capability (1a)
    #$bd[5] = "xxxx";   		# operating environment (1a)
    #$bd[6] = "xxxx";   		# cardholder present (1a)
    #$bd[7] = "xxxx";   		# card present (1a)
    #$bd[8] = "xxxx";   		# card input mode (1a)
    #$bd[9] = "xxxx";   		# cardholder auth method (1a)
    #$bd[10] = "xxxx";   		# cardholder auth entry (1a)
    #$bd[11] = "xxxx";   		# card output capability (1a)
    #$bd[12] = "xxxx";   		# terminal output capability (1a)
    #$bd[13] = "xxxx";   		# pin capture capability (1a)
    $bd[14] = " " x 58;    # filler (58a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  if ( ( $card_type eq "vi" ) && ( $origoperation ne "forceauth" ) && ( $operation ne "return" ) ) {

    # XD01  supplemental vi  pg. 10-122
    @bd = ();
    $bd[0] = "XD01";    # record id (4a)  pg. 10-116
    $recseqnum++;
    $recseqnum = substr( "0" . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)

    my $amt = substr( $origamount, 4 );
    $amt = sprintf( "%d", ( $amt * 100 ) + .0001 );
    $amt = substr( "0" x 12 . $amt, -12, 12 );
    $bd[2] = "$amt";          # initial auth amount (12n)
    ($currency) = split( / /, $amount );
    if ( $currency eq "" ) {
      $currency = "usd";
    }
    $currency =~ tr/a-z/A-Z/;
    $currencycode = $isotables::currencyUSD840{$currency};
    $currencycode = substr( $currencycode . " " x 3, 0, 3 );
    $bd[3]        = "$currencycode";                           # auth currency code (3a)

    $authrespcode = substr( $auth_code, 118, 2 );
    $authrespcode = substr( $authrespcode . " " x 2, 0, 2 );
    $bd[4] = "$authrespcode";                                  # auth response code (2a)

    $cashback = substr( $auth_code,          120, 7 );
    $cashback = substr( "0" x 7 . $cashback, -7,  7 );
    $bd[5] = "$cashback";                                      # cash back amount (7n)

    $aci = substr( $auth_code, 127, 1 );
    $aci = substr( $aci . " ", 0,   1 );
    $bd[6] = "$aci";                                           # aci (1a)

    $avs_code = substr( $avs_code . " ", 0, 1 );
    $bd[7] = "$avs_code";                                      # avs response (1a)

    $bd[8] = "0" x 15;                                         # acknowledgment transaction id (15n) must send 0's

    $bd[9] = "    ";                                           # acknowledgment validation code (4a) must send spaces

    $cvvresp = substr( $cvvresp . " ", 0, 1 );
    $bd[10] = "$cvvresp";                                      # cvv result code (1a)

    $bd[11] = " " x 24;                                        # filler (24a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  if ( ( $card_type eq "mc" ) && ( $origoperation ne "forceauth" ) && ( $operation ne "return" ) ) {

    # XD02  supplemental mc  pg. 10-124
    @bd = ();
    $bd[0] = "XD02";    # record id (4a)  pg. 10-116
    $recseqnum++;
    $recseqnum = substr( "0" . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)

    $banknetrefid = substr( $auth_code, 143, 9 );
    $banknetrefid = substr( $banknetrefid . " " x 9, 0, 9 );
    $bd[2] = "$banknetrefid";    # banknet reference id (9a)

    $banknetdate = substr( $auth_code,             152, 9 );
    $banknetdate = substr( $banknetdate . " " x 4, 0,   4 );
    $bd[3] = "$banknetdate";     # banknet date (4n)

    if ( ( $transflags =~ /moto/ ) || ( $industrycode =~ /^(retail|restaurant)$/ ) ) {
      $ecilevel = "00";
    } else {
      $ecilevel = "21";
    }
    $bd[4] = "$ecilevel";        # electronic commerce security level (2a)

    $eci     = substr( $auth_code, 161, 2 );
    $ucafind = substr( $auth_code, 275, 1 );
    if ( ( $operation eq "return" ) || ( $ucafind eq " " ) ) {
      $ucafind = "0";
    }
    $bd[5] = "$ucafind";         # ucaf status (1a)

    $bd[6] = " ";                # filler (1a)
    $authamt = substr( $auth_code,          163, 12 );
    $authamt = substr( "0" x 12 . $authamt, -12, 12 );
    $bd[7] = "$authamt";         # auth amount (12n)

    $transerrcode = substr( $auth_code,          175, 1 );
    $transerrcode = substr( $transerrcode . " ", 0,   1 );
    $bd[8] = "$transerrcode";    # transaction error edit code (1a)

    $cvcerror = substr( $auth_code,      176, 1 );
    $cvcerror = substr( $cvcerror . " ", 0,   1 );
    $bd[9] = "$cvcerror";        # cvc error (1a)

    $posentrychange = substr( $auth_code,            222, 1 );
    $posentrychange = substr( $posentrychange . " ", 0,   1 );
    $bd[10] = $posentrychange;    # pos entry mode change (1a)

    my $mcauthtime = substr( $auth_code, 278, 4 );
    $mcauthtime = substr( $mcauthtime . " " x 4, 0, 4 );
    $bd[11] = "$mcauthtime";      # auth time HHMM (4n)

    $bd[12] = "  ";               # filler (2a)
    $bd[13] = " ";                # filler (1a)
    $bd[14] = " " x 31;           # filler (31a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  my $printstr = "$card_type  $commflag\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

  if (
    ( ( $card_type eq "vi" )
      && (
        ( $commflag == 1 )
        || ( ( ( $commflag == 1 ) || ( ( industrycode !~ /retail|restaurant/ ) || ( $transflags =~ /moto/ ) ) )
          && ( ( $origoperation ne "forceauth" ) && ( $operation eq "postauth" ) ) )
         )
    )
    || ( ( $card_type eq "mc" )
      && ( ( $commflag == 1 ) || ( ( $reauthstatus eq "success" ) && ( $operation eq "postauth" ) ) ) )
    ) {

    # XD05  market specific data record  pg. 10-126
    @bd = ();
    $bd[0] = "XD05";    # record id (4a)  pg. 10-126
    $recseqnum++;
    $recseqnum = substr( "0" . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)

    $idformat = " ";
    if ( ( $card_type eq "mc" ) && ( $reauthstatus eq "success" ) && ( $operation eq "postauth" ) ) {
      $idformat = " ";
    } elsif ( ( $industrycode !~ /retail|restaurant/ ) && ( $commflag ne "1" ) ) {
      $idformat = "1";
    }
    $bd[2] = $idformat;       # purchase id format (1a)
    $bd[3] = "0";             # no show indicator (1a)
    $bd[4] = "      ";        # extra charges indicator (6a)

    $commflag = substr( $auth_code, 221, 1 );
    if ( $commflag eq "1" ) {
      $bd[5] = "$transyymmdd";    # market specific date (6n)
    } else {
      $bd[5] = "000000";          # market specific date (6n)
    }

    my $amt = "0" x 12;
    if ( ( $operation ne "return" ) && ( ( $reauthstatus eq "success" ) || ( $commflag eq "1" ) ) ) {
      $amt = substr( $amount, 4 );
      $amt = sprintf( "%d", ( $amt * 100 ) + .0001 );
      $amt = substr( "0" x 12 . $amt, -12, 12 );
    }
    $bd[6] = $amt;                # total auth amount (12n)

    if ( ( $card_type eq "vi" ) && ( $transflags =~ /recurring|bill|install/ ) ) {
      $marketind = "B";
    } else {
      $marketind = " ";
    }
    $bd[7] = $marketind;          # market specific auth indicator (1a)

    $cardlevelres = substr( $auth_code,           177, 2 );
    $cardlevelres = substr( $cardlevelres . "  ", 0,   2 );
    $bd[8] = $cardlevelres;       # visa card level indicator (2a)
    $bd[9] = " " x 41;            # filler (41a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  if ( ( $card_type eq "ds" ) && ( $operation eq "postauth" ) && ( $origoperation ne "forceauth" ) ) {

    # XV01  market specific data record  pg. 9-78
    @bd = ();
    $bd[0] = "XV01";    # record id (4a)  pg. 9-78
    $recseqnum++;
    $recseqnum = substr( "0" . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)
    my $authtime = substr( $auth_code, 224, 6 );
    $authtime = substr( $authtime . " " x 6, 0, 6 );
    $bd[2] = "$authtime";     # local transaction time (6n)
    my $pcode = substr( $auth_code, 236, 6 );
    $pcode = substr( $pcode . " " x 6, 0, 6 );
    $bd[3] = "$pcode";        # processing code (6a)
    my $dstrace = substr( $auth_code, 242, 6 );
    $dstrace = substr( $dstrace . " " x 6, 0, 6 );
    $bd[4] = "$dstrace";      # system trace audit number (6n)

    my $dsposentry = substr( $auth_code, 248, 3 );
    $dsposentry = substr( $dsposentry . " " x 3, 0, 3 );
    $bd[5] = "$dsposentry";    # pos entry mode (3a)

    my $trackcond1 = "0";
    my $trackcond2 = "0";
    if ( $magstripetrack eq "1" ) {
      $trackcond1 = "2";
    } elsif ( $magstripetrack eq "2" ) {
      $trackcond2 = "2";
    }
    $bd[6] = $trackcond1 . $trackcond2;    # track data condition code (2a)

    my $posdata = substr( $auth_code, 105, 13 );
    $posdata = substr( $posdata . " " x 13, 0, 13 );
    $bd[7] = "$posdata";                   # pos data (13a)
    $bd[8] = " " x 34;                     # filler (34a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";

    # XV02  market specific data record  pg. 9-85
    @bd    = ();
    $bd[0] = "XV02";                       # record id (4a)  pg. 9-85
    $recseqnum++;
    $recseqnum = substr( "0" . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";                 # record sequence number (6n)
    $authrespcode = substr( $auth_code, 118, 2 );
    $authrespcode = substr( $authrespcode . " " x 2, 0, 2 );
    $bd[2] = $authrespcode;                # auth response code (2a)
    $bd[3] = "N";                          # partial shipment indicator (1a)

    if ( $card_type eq "ds" ) {
      my $dstrace = substr( $auth_code, 276, 1 );
      $avs_code = substr( $dstrace . " ", 0, 1 );
    } else {
      $avs_code = substr( $avs_code . " ", 0, 1 );
    }
    $bd[4] = "$avs_code";                  # avs response (1a)
    $authamt = substr( $auth_code,          163, 12 );
    $authamt = substr( "0" x 13 . $authamt, -13, 13 );
    $bd[5] = "$authamt";                   # auth amount (13n)
    $transid = substr( $auth_code,          6,   15 );
    $transid = substr( "0" x 15 . $transid, -15, 15 );
    $bd[6] = "$transid";                   # network reference id nrid(15n)
    $bd[7] = " " x 38;                     # filler (38a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";

    my $cashback = substr( $auth_code, 120, 7 );
    if ( $cashback > 0 ) {
      @bd = ();
      $bd[0] = "XV06";    # record id (4a)  pg. 9-78
      $recseqnum++;
      $recseqnum = substr( "0" . $recseqnum, -6, 6 );
      $bd[1] = "$recseqnum";    # record sequence number (6n)
      $cashback = substr( "0" x 12 . $cashback, -12, 12 );
      $bd[2] = "$cashback";     # cash back amount (12n)
      $bd[3] = " " x 58;        # filler (38a)

      foreach $var (@bd) {
        $outfilestr  .= "$var";
        $outfile2str .= "$var";
      }

      $outfilestr  .= "\n";
      $outfile2str .= "\n";
    }
  }

  # Q  debit detail  pg. 10-134
  # A  response credit without debit  pg. 10-138
  # A  response credit with debit  pg. 10-139

  @bd = ();
  $bd[0] = "D";    # record id (1a)  pg. 10-133
  my $cardnum = substr( "0" x 16 . $cardnumber, -16, 16 );
  $bd[1] = "$cardnum";    # cardholder account number (16n)
  my $tcode = "";
  if ( $operation eq "return" ) {
    $tcode = "6";
  } else {
    $tcode = "5";
  }
  $bd[2] = "$tcode";      # transaction code (1a)

  my $amt = substr( $amount, 4 );
  $amt = sprintf( "%d", ( $amt * 100 ) + .0001 );
  $amt      = substr( "0" x 8 . $amt, -8, 8 );
  $batchamt = $amt;                              # used for batch totals
  $bd[3]    = "$amt";                            # transaction amount (8n)

  if ( $card_type eq "vi" ) {
    $transdate = $transdategmt;
  }
  $bd[4] = "$transdate";                         # transaction date MMDD (4n)
  $authcode = substr( $auth_code,          0, 6 );
  $authcode = substr( $authcode . " " x 6, 0, 6 );
  $bd[5] = "$authcode";                          # authorization code (6a)
  if ( $operation eq "return" ) {
    $authdate = "0000";
  } elsif ( $card_type eq "vi" ) {
    $authdate = "$trandategmt";
  } else {
    $authdate = "$trandate";
  }
  $bd[6] = "$authdate";                          # authorization date MMDD (4n)
  $expdate = substr( $exp, 0, 2 ) . substr( $exp, 3, 2 );
  $bd[7] = "$expdate";                           # card expiration date MMYY (4n)
  $recseqnum++;
  $refnum = substr( "0" x 8 . $recseqnum, -8, 8 );
  $bd[8] = "$refnum";                            # reference number (8n) my choice
  $recseqnum = substr( "0" . $recseqnum, -6, 6 );
  $bd[9]   = "$recseqnum";                       # record sequence number (6n)
  $bd[10]  = " ";                                # filler (1a)
  $bd[11]  = " ";                                # prepaid card indicator (1a)
  $transid = "";

  if ( $card_type =~ /^(vi|ax)$/ ) {
    $transid = substr( $auth_code, 6, 15 );
    $transid =~ s/ //g;
  }
  $transid = substr( $transid . "0" x 15, 0, 15 );

  $bd[12]    = "$transid";                       # transaction identifier (15n)
  $bd[13]    = " ";                              # filler (1a)
  $validcode = "";
  if ( $card_type eq "vi" ) {
    $validcode = substr( $auth_code, 21, 4 );
    $validcode =~ s/ //g;
  }
  $validcode = substr( $validcode . " " x 4, 0, 4 );
  $bd[14] = "$validcode";                        # validation code (4a)

  foreach $var (@bd) {
    $outfilestr .= "$var";

    $xs = $cardnumber;
    $xs =~ s/[0-9]/x/g;
    $var =~ s/$cardnumber/$xs/;
    $outfile2str .= "$var";
  }

  $outfilestr  .= "\n";
  $outfile2str .= "\n";

  my $amt = substr( $amount, 4 );
  if ( $operation eq "return" ) {
    $amt = 0.00 - $amt;
    $amt = sprintf( "%.2f", $amt - .0001 );
  }

  # xxxx don't do for testing using eAnalyst
  if (1) {
    my $dbquerystr = <<"dbEOM";
        insert into batchfilesfdmsn
	(username,filename,batchname,filenum,detailnum,trans_date,orderid,status,amount,operation)
        values (?,?,?,?,?,?,?,?,?,?)
dbEOM

    my %inserthash = (
      "username",  "$username", "filename",   "$filename", "batchname", "$summaryid", "filenum", "$filejuliandate$filenum",
      "detailnum", "$refnum",   "trans_date", "$today",    "orderid",   "$orderid",   "status",  "pending",
      "amount",    "$amt",      "operation",  "$operation"
    );
    &procutils::dbinsert( $username, $orderid, "pnpmisc", "batchfilesfdmsn", %inserthash );

  }

  $amt2 = $batchamt;
  if ( $operation eq "postauth" ) {
    $batchtotalamt = $batchtotalamt + $amt2;
    $batchtotalcnt = $batchtotalcnt + 1;
    $batchsalesamt = $batchsalesamt + $amt2;
    $batchsalescnt = $batchsalescnt + 1;
    $filetotalamt  = $filetotalamt + $amt2;
    $filetotalcnt  = $filetotalcnt + 1;
    $filesalesamt  = $filesalesamt + $amt2;
    $filesalescnt  = $filesalescnt + 1;
  } else {
    $batchtotalamt = $batchtotalamt - $amt2;
    $batchtotalcnt = $batchtotalcnt + 1;
    $batchretamt   = $batchretamt + $amt2;
    $batchretcnt   = $batchretcnt + 1;
    $filetotalamt  = $filetotalamt - $amt2;
    $filetotalcnt  = $filetotalcnt + 1;
    $fileretamt    = $fileretamt + $amt2;
    $fileretcnt    = $fileretcnt + 1;
  }
}

sub batchheader {
  $batch_flag  = 0;
  $detailcount = 0;

  $batchcount++;

  $batchreccnt = 1;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );
  $batchdate = $createdate;
  $batchdate = substr( $batchdate . " " x 6, 0, 6 );
  $batchtime = $createtime;
  $batchtime = substr( $batchtime . " " x 6, 0, 6 );

  $transseqnum   = 0;
  $batchtotalcnt = 0;
  $batchtotalamt = 0;
  $batchretcnt   = 0;
  $batchretamt   = 0;
  $batchsalescnt = 0;
  $batchsalesamt = 0;

  @bh    = ();
  $bh[0] = "M";                                          # record id (1a)  pg. 10-71
  $mid   = substr( "0" x 12 . $merchant_id, -12, 12 );
  $bh[1] = "$mid";                                       # merchant account (12n)
  $bh[2] = "RR";                                         # reference id (2a)
  $bh[3] = "5045";                                       # merchant id/security code (4n)
  $bh[4] = "6";                                          # submission type (1a)

  # zzzz
  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
  $lyear = substr( $lyear, -2, 2 );

  $bh[5] = "$filejuliandate";                            # submission create date (5n)
  $filenum = substr( "0" . $filenum, -1, 1 );
  $bh[6] = "$filenum";                                   # submission sequence number (1n)
  $bh[7] = "5045";                                       # security code (4n)
  $subdate = sprintf( "%02d%02d%02d", $lmonth + 1, $lday, $lyear );
  $bh[8] = "$subdate";                                   # submission create date (6n)
  $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
  $bh[9]  = "$recseqnum";                                # record sequence number (6n)
  $bh[10] = " ";                                         # extension ind (1a)
  $bh[11] = " ";                                         # platform id (1a)
  $bh[12] = " ";                                         # filler (1a)
  $bh[13] = "   ";                                       # clearing code (3a)
  $bh[14] = " " x 16;                                    # ext. merchant number (16a)
  $bh[15] = "    ";                                      # filler (4a)
  $bh[16] = "      ";                                    # merchant bin number (6a)
  $bh[17] = "      ";                                    # merchant ica number (6a)

  foreach $var (@bh) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
  }

  $outfilestr  .= "\n";
  $outfile2str .= "\n";

  $installnum = substr( $auth_code, 217, 2 );
  $installtot = substr( $auth_code, 219, 2 );
  if ( ( $marketdata eq "" ) || ( $marketdata eq " " x 38 ) ) {
    @bh = ();
    $bh[0] = "N";    # record id (1a)

    $installinfo = "";
    $installlen  = "";
    if ( ( $installnum > 0 ) && ( $installtot > 0 ) ) {
      $installnum  = $installnum + 0;
      $installtot  = $installtot + 0;
      $installinfo = $installnum . "of" . $installtot;
      $installlen  = length($installinfo);
    }
    $company =~ s/ +$//g;

    $company =~ s/[^a-zA-Z0-9 \&,\/\.\'\-]//g;
    $companylen = length($company);
    if ( $companylen + $installlen > 19 ) {
      $company = substr( $company, 0, 19 - $installlen );
    }
    $company = $company . $installinfo;
    $company = substr( $company . " " x 19, 0, 19 );
    $company =~ tr/a-z/A-Z/;
    $bh[1] = "$company";    # merchant name (19a)

    if ( ( $industrycode !~ /retail|restaurant/ ) || ( $transflags =~ /moto/ ) ) {
      $custphone = $phone;
      $custphone =~ s/[^a-zA-Z0-9]//g;
      $custphone = substr( $custphone, 0, 3 ) . "-" . substr( $custphone, 3, 3 ) . "-" . substr( $custphone, 6 );
      $city = $custphone;
    }

    $city =~ tr/a-z/A-Z/;
    $city = substr( $city . " " x 13, 0, 13 );
    $city =~ tr/a-z/A-Z/;
    $bh[2] = "$city";       # merchant city (13a)
    $state = substr( $state . " " x 2, 0, 2 );
    if ( ( $country eq "" ) || ( $country eq "US" ) ) {
      $state = $state . " ";
    } elsif ( $country eq "CA" ) {
      $state = $state . "*";
    } else {
      $country =~ tr/a-z/A-Z/;
      $state = &isotables::countryUSUSA($country);
    }
    $state = substr( $state . " " x 3, 0, 3 );
    $state =~ tr/a-z/A-Z/;
    $bh[3] = "$state";      # merchant state (3a)
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bh[4] = "$recseqnum";    # sequence number (6n)
    $bh[5] = " " x 38;        # filler (38a)
  } else {
    @bh      = ();
    $bh[0]   = "N";                            # record id (1a)
    $company = substr( $marketdata, 0, 25 );
    $company =~ s/ +$//g;
    $company =~ s/[^a-zA-Z0-9 \&,\/\.\'\-\*]//g;
    $company =~ tr/a-z/A-Z/;
    $installinfo = "";
    $installlen  = "";

    if ( ( $installnum > 0 ) && ( $installtot > 0 ) ) {
      $installnum  = $installnum + 0;
      $installtot  = $installtot + 0;
      $installinfo = $installnum . "of" . $installtot;
      $installlen  = length($installinfo);
    }
    $companylen = length($company);
    if ( $companylen + $installlen > 25 ) {
      $company = substr( $company, 0, 25 - $installlen );
    }
    $company = $company . $installinfo;
    $company =~ tr/a-z/A-Z/;
    $company = substr( $company . " " x 25, 0, 25 );
    $company =~ tr/a-z/A-Z/;
    $bh[1] = "$company";    # merchant name (25a)
    $bh[2] = " ";           # filler (1a)

    if ( ( $industrycode !~ /retail|restaurant/ ) || ( $transflags =~ /moto/ ) ) {
      $marketphone = substr( $marketdata, 25, 13 );
      $marketphone =~ s/[^0-9a-zA-Z]//g;
      if ( ( $username eq "hbmspnp" ) && ( $marketphone eq "" ) ) {
        $marketphone = "4087455488";
      }
      $city = substr( $marketphone, -11, 11 );
      if ( $city eq "" ) {
        $city = $phone;     # fill in phone from db if no phone in marketdata
        $city =~ s/[^0-9a-zA-Z]//g;
      }
    }
    $city =~ tr/a-z/A-Z/;
    $city = substr( $city . " " x 11, 0, 11 );
    $bh[3] = "$city";       # merchant city (11a)

    $bh[4] = " ";           # filler (1a)
    $state = substr( $state . " " x 2, 0, 2 );
    if ( ( $country eq "" ) || ( $country eq "US" ) ) {
      $state = " ";
    } elsif ( $country eq "CA" ) {
      $state = $state . "*";
    } else {
      $country =~ tr/a-z/A-Z/;
      $state = &isotables::countryUSUSA($country);
    }
    $state = substr( $state . " " x 3, 0, 3 );
    $state =~ tr/a-z/A-Z/;
    $bh[5] = "$state";      # merchant state (3a)
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bh[6] = "$recseqnum";    # sequence number (6n)
    $bh[7] = " " x 32;        # filler (32a)
  }

  foreach $var (@bh) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
  }
  $outfilestr  .= "\n";
  $outfile2str .= "\n";

  # XM02  purchase card tax id  pg. 10-105
  my $printstr = "ffff: xm02\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  @bd = ();
  $bd[0] = "XM02";    # record id (4a)  pg. 10-104
  $recseqnum++;
  $recseqnum = substr( "0" . $recseqnum, -6, 6 );
  $bd[1] = "$recseqnum";    # record sequence number (6n)
  $fedtaxid = substr( $fedtaxid . " " x 15, 0, 15 );
  $bd[2] = $fedtaxid;       # fed tax id (15a) yyyy
  $bd[4] = " " x 55;        # filler (55a)

  foreach $var (@bd) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
  }

  $outfilestr  .= "\n";
  $outfile2str .= "\n";

  # XM03  purchase card VAT number
  if ( $mcountry ne "US" ) {
    @bd = ();
    $bd[0] = "XM03";    # record id (4a)  pg. 10-105
    $recseqnum++;
    $recseqnum = substr( "0" . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)
    $vattaxid = substr( $vattaxid . " " x 15, 0, 15 );
    $bd[2] = $vattaxid;       # fed tax id (15a)
    $bd[4] = " " x 55;        # filler (55a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  if ( $chargedescr ne "" ) {
    @bh = ();
    $bh[0] = "R";    # record id (1a)
    $chargedescr =~ tr/a-z/A-Z/;
    $chargedescr = substr( $chargedescr . " " x 23, 0, 23 );
    $bh[1] = $chargedescr;    # charge description (23a)
    $bh[2] = " " x 12;        # filler (12a)
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bh[3] = "$recseqnum";    # sequence number (6n)
    $bh[4] = " " x 38;        # filler (38a)

    foreach $var (@bh) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }
    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

}

sub batchtrailer {
  $batchreccnt++;
  $filereccnt++;

  $batchretcnt = substr( "0000000" . $batchretcnt,     -6,  6 );
  $batchretamt = substr( "00000000000" . $batchretamt, -11, 11 );
  $batchreccnt = substr( "0000000" . $batchreccnt,     -7,  7 );

  $batchtotalamtstr = $batchtotalamt;
  if ( $batchtotalamt < 0 ) {
    $batchtotalamt    = 0 - $batchtotalamt;
    $batchtotalamtstr = 0 - $batchtotalamt;
    $batchtotalamtstr = $batchtotalamtstr . "-";
    my $mychar = substr( $batchtotalamt, -1, 1 );
    $batchtotalamt = substr( $batchtotalamt, 0, length($batchtotalamt) - 1 );
    if ( $mychar eq "0" ) {
      $batchtotalamt = $batchtotalamt . "}";
    } elsif ( $mychar eq "1" ) {
      $batchtotalamt = $batchtotalamt . "J";
    } elsif ( $mychar eq "2" ) {
      $batchtotalamt = $batchtotalamt . "K";
    } elsif ( $mychar eq "3" ) {
      $batchtotalamt = $batchtotalamt . "L";
    } elsif ( $mychar eq "4" ) {
      $batchtotalamt = $batchtotalamt . "M";
    } elsif ( $mychar eq "5" ) {
      $batchtotalamt = $batchtotalamt . "N";
    } elsif ( $mychar eq "6" ) {
      $batchtotalamt = $batchtotalamt . "O";
    } elsif ( $mychar eq "7" ) {
      $batchtotalamt = $batchtotalamt . "P";
    } elsif ( $mychar eq "8" ) {
      $batchtotalamt = $batchtotalamt . "Q";
    } elsif ( $mychar eq "9" ) {
      $batchtotalamt = $batchtotalamt . "R";
    }
  }
  if ( $batchsalesamt < 0 ) {
    $batchsalesamt = 0 - $batchsalesamt;
  }
  if ( $batchretamt < 0 ) {
    $batchretamt = 0 - $batchretamt;
  }

  $batchtotalamt = substr( "0" x 10 . $batchtotalamt, -10, 10 );
  $batchsalescnt = substr( "0" x 6 . $batchsalescnt,  -6,  6 );
  $batchsalesamt = substr( "0" x 10 . $batchsalesamt, -10, 10 );
  $batchretcnt   = substr( "0" x 6 . $batchretcnt,    -6,  6 );
  $batchretamt   = substr( "0" x 10 . $batchretamt,   -10, 10 );
  $batchcount    = substr( "0" x 6 . $batchcount,     -6,  6 );
  $batchnum      = substr( "0" x 6 . $batchnum,       -6,  6 );
  $detailcount   = substr( "0" x 6 . $detailcount,    -6,  6 );

  if (0) {
    @bt     = ();
    $bt[0]  = "80";              # tran code (2a)
    $bt[1]  = $batchnum;         # relative batch # (6a)
    $bt[2]  = $createdate;       # process date - YYMMDD (6n)
    $bt[3]  = $detailcount;      # record count (6)
    $bt[4]  = $batchtotalamt;    # net batch total amount - no decimal (10n)
    $bt[5]  = $batchsalescnt;    # sale transaction count (6n)
    $bt[6]  = $batchsalesamt;    # sale total amount (10n)
    $bt[7]  = $batchretcnt;      # return transaction count (6n)
    $bt[8]  = $batchretamt;      # return total amount (10n)
    $bt[9]  = $createdate;       # date batch closed (6n)
    $bt[10] = $createtime;       # time batch closed (4n)
    $bt[11] = " " x 8;           # filler (8a)

    foreach $var (@bt) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }
    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

}

sub fileheader {
  my $printstr = "in fileheader\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  $batchcount = 0;
  $filecount++;

  $file_flag = 0;
  my $dbquerystr = <<"dbEOM";
        select filenum,batchdate
        from fdmsnorth
        where username='fdmsnorth'
dbEOM
  my @dbvalues = ();
  ( $filenum, $batchdate ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $printstr = "batchdate: $batchdate, today: $today, filenum: $filenum\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

  if ( $batchdate != $todaylocal ) {
    $filenum = 0;
  }
  $filenum = $filenum + 1;
  if ( $filenum > 9 ) {
    my $printstr = "<h3>You have exceeded the maximum allowable batches for today.</h3>\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  }

  ( $d1, $d2, $ttime ) = &miscutils::genorderid();
  $filename = "$ttime$pid";

  my $dbquerystr = <<"dbEOM";
        update fdmsnorth set filenum=?,batchdate=?
	where username='fdmsnorth'
dbEOM
  my @dbvalues = ( "$filenum", "$todaylocal" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  umask 0077;
  $outfilestr  = "";
  $outfile2str = "";

  $customerid = substr( $customerid . " " x 10, 0, 10 );

  $filesalescnt = 0;
  $filesalesamt = 0;
  $fileretcnt   = 0;
  $fileretamt   = 0;
  $filereccnt   = 1;
  $filetotalamt = 0;
  $filetotalcnt = 0;
  $recseqnum    = 0;
  $recseqnum    = substr( "0000000" . $recseqnum, -7, 7 );
  $fileid       = substr( $fileid . " " x 20, 0, 20 );

}

sub filetrailer {
  if ( $filetotalamt < 0 ) {
    $filetotalamtstr = sprintf( "%.2f", ( $filetotalamt / 100 ) - .0001 );
  } else {
    $filetotalamtstr = sprintf( "%.2f", ( $filetotalamt / 100 ) + .0001 );
  }

  if ( $filetotalamt < 0 ) {
    $filetotalamt = 0 - $filetotalamt;
    my $mychar = substr( $filetotalamt, -1, 1 );
    $filetotalamt = substr( $filetotalamt, 0, length($filetotalamt) - 1 );
    if ( $mychar eq "0" ) {
      $filetotalamt = $filetotalamt . "}";
    } elsif ( $mychar eq "1" ) {
      $filetotalamt = $filetotalamt . "J";
    } elsif ( $mychar eq "2" ) {
      $filetotalamt = $filetotalamt . "K";
    } elsif ( $mychar eq "3" ) {
      $filetotalamt = $filetotalamt . "L";
    } elsif ( $mychar eq "4" ) {
      $filetotalamt = $filetotalamt . "M";
    } elsif ( $mychar eq "5" ) {
      $filetotalamt = $filetotalamt . "N";
    } elsif ( $mychar eq "6" ) {
      $filetotalamt = $filetotalamt . "O";
    } elsif ( $mychar eq "7" ) {
      $filetotalamt = $filetotalamt . "P";
    } elsif ( $mychar eq "8" ) {
      $filetotalamt = $filetotalamt . "Q";
    } elsif ( $mychar eq "9" ) {
      $filetotalamt = $filetotalamt . "R";
    }
  }
  if ( $filesalesamt < 0 ) {
    $filesalesamt = 0 - $filesalesamt;
  }
  if ( $fileretamt < 0 ) {
    $fileretamt = 0 - $fileretamt;
  }

  $filereccnt++;

  $filetotalamt = substr( "0" x 12 . $filetotalamt, -10, 12 );
  $filesalescnt = substr( "0" x 6 . $filesalescnt,  -6,  6 );
  $filesalesamt = substr( "0" x 12 . $filesalesamt, -12, 12 );
  $fileretcnt   = substr( "0" x 6 . $fileretcnt,    -6,  6 );
  $fileretamt   = substr( "0" x 12 . $fileretamt,   -12, 12 );
  $batchcount   = substr( "0" x 6 . $batchcount,    -6,  6 );

  @ft    = ();
  $ft[0] = "T";                # record id (1a)  pg. 10-133
  $ft[1] = "$filesalesamt";    # total sales deposit amount (12n)
  $ft[2] = "$fileretamt";      # total return amount (12n)

  # xxxx fill in below 3 lines for debit cards
  $ft[3] = "0" x 12;           # total cash advance amount (12n)
  $ft[4] = "0" x 12;           # total sales deposit/auth request amount (12n)
  $ft[5] = "0" x 12;           # total cash advance deposit/auth request amount (12n)

  $recseqnum++;
  $recseqnum = substr( "0" . $recseqnum, -6, 6 );
  $ft[6] = "$recseqnum";       # record sequence number (6n)
  $ft[7] = " " x 13;           # filler (13a)

  foreach $var (@ft) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
  }

  $outfilestr  .= "\n";
  $outfile2str .= "\n";

  &procutils::fileencwrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear", "$filename", "write", "", $outfilestr );
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear", "$filename.txt", "write", "", $outfile2str );

  my $printstr = "filenum: $filenum  today: $today  amt: $filetotalamtstr  cnt: $filetotalcnt\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

}

sub pidcheck {
  my $chkline = &procutils::fileread( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprodlogs/fdmsnorth", "pid$group.txt" );
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/logs/fdmsnorth/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $printstr .= "$pidline\n";
    $printstr .= "$chkline\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdmsnorth - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  my $printstr = "origtime: $origtime $timezone1\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

  if ( length($origtime) != 14 ) {
    return $origtime;
  }

  # timezone  hours  week of month  day of week  month  time   hours  week of month  day of week  month  time
  %timezonearray = (
    'EST', '-4,2,0,3,02:00, -5,1,0,11,02:00',    # 4 hours starting 2nd Sunday in March at 2am, 5 hours starting 1st Sunday in November at 2am
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
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $printstr = "The $times2 Sunday of month $month2 happens on the $mday2\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  my $printstr = "newtime: $newtime $timezone2\n\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  return $newtime;

}

