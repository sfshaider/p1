#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use procutils;
use smpsutils;
use isotables;

my $group = $ARGV[0];
if ( $group eq "" ) {
  $group = "0";
}
my $printstr = "group: $group\n";
&procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );

if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/logs/fdmsrc/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdmsrc/genfiles.pl $group'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
  exit;
}

$mytime  = time();
$machine = `uname -n`;
$pid     = $$;

chop $machine;
$outfilestr = "";
$pidline    = "$mytime $$ $machine";
$outfilestr .= "$pidline\n";
&procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc", "pid$group.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my @infilestrarray = &procutils::fileread( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc", "pid$group.txt" );
$chkline = $infilestrarray[0];
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  $printstr .= "$pidline\n";
  $printstr .= "$chkline\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsrc - dup genfiles\n";
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

if ( !-e "/home/pay1/batchfiles/logs/fdmsrc/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/fdmsrc/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/logs/fdmsrc/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/logs/fdmsrc/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/fdmsrc/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/logs/fdmsrc/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/logs/fdmsrc/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/fdmsrc/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/logs/fdmsrc/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/logs/fdmsrc/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsrc - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/fdmsrc/$fileyear.\n\n";
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
        and o.processor='fdmsrcdw'
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
$mycnt = 0;
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  $mycnt++;

  my $printstr = "aaaa $user  $usercount  $usertdate\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );

  @userarray = ( @userarray, $user );
  $userbankarray{"$banknumarray{$user} $currencyarray{$user} $user"} = 1;
  $usercountarray{$user}                                             = $usercount;
  $starttdatearray{$user}                                            = $usertdate;
}

foreach $key ( sort keys %userbankarray ) {
  ( $banknum, $currency, $username ) = split( / /, $key );
  ( $d1, $d2, $time ) = &miscutils::genorderid();

  if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/logs/fdmsrc/stopgenfiles.txt" ) ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "stopgenfiles\n";

    my $printstr = "stopgenfiles\n";
    &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc",        "miscdebug.txt",          "append", "misc", $printstr );
    &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc/$fileyear", "$username$time$pid.txt", "append", "",     $logfilestr );

    &procutils::flagwrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc", "batchfile.txt", "unlink", "", "" );
    last;
  }

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc", "genfiles$group.txt", "write", "", $batchfilestr );

  my $printstr = "bbbb $username  $banknum\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc", "batchfile.txt", "write", "", $batchfilestr );

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
  ( $merchant_id, $terminal_id, $proc_type, $status, $currency, $company, $city, $state, $merchzip, $phone, $mcountry ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $currency eq "" ) {
    $currency = "usd";
  }

  if ( $status ne "live" ) {
    next;
  }

  my $dbquerystr = <<"dbEOM";
        select industrycode,fedtaxid,vattaxid,categorycode,chargedescr,batchtime,merchantnum,tokenreqid
        from fdmsrc
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $industrycode, $fedtaxid, $vattaxid, $categorycode, $chargedescr, $batchgroup, $xmerchant_id, $tokenreqid ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  # xmerchant_id - remove the x for certifications only

  if ( ( $group eq "5" ) && ( $batchgroup ne "5" ) ) {
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
  } elsif ( $group !~ /^(0|1|2|3|4|5)$/ ) {
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
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  my $printstr = "gmt today: $todaytime\n";
  $printstr .= "est today: $esttime\n";
  $printstr .= "est yesterday: $yesterday\n";
  $printstr .= "settletime: $settletime\n";
  $printstr .= "sweeptime: $sweeptime\n";
  $printstr .= "cccc $username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username $usercountarray{$username} $starttransdate $currency\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username  sweeptime: $sweeptime  settletime: $settletime\n";
  $logfilestr .= "$features\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  print "aaaa\n";

  my $dbquerystr = <<"dbEOM";
        select o.orderid,o.trans_date,substr(o.auth_code,180,38),o.cardtype
        from operation_log o, trans_log t
        where t.trans_date>=?
        and t.username=?
        and t.operation in ('postauth','return')
        and t.finalstatus='pending'
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastop=t.operation
        and o.lastopstatus='pending'
        and o.processor='fdmsrcdw'
        and (o.voidstatus is NULL or o.voidstatus ='')
        and (o.accttype is NULL or o.accttype ='' or o.accttype='credit')
dbEOM
  my @dbvalues = ( "$onemonthsago", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  %orderidarray      = ();
  %starttdateinarray = ();
  %axarray           = ();
  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 4 ) {
    ( $orderid, $trans_date, $marketdata, $card_type ) = @sthtransvalarray[ $vali .. $vali + 3 ];

    $marketdata =~ tr/a-z/A-Z/;
    $orderidarray{ "$marketdata" . "jj,jj" . "$orderid" } = 1;    # if there is an ax card send R record
    if ( $card_type eq "ax" ) {
      $axarray{"$username"} = 1;
    }

    $starttdateinarray{"$username $trans_date"} = 1;

    my $printstr = "$orderid\n";
    &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
  }

  $marketdataold = "";
  foreach my $keya ( sort keys %orderidarray ) {
    ( $marketdata, $orderid ) = split( /jj,jj/, $keya, 3 );
    my $dbquerystr = <<"dbEOM";
          select lastop,trans_date,lastoptime,enccardnumber,length,amount,auth_code,avs,lastopstatus,transflags,card_exp,cvvresp,refnumber,
                 authtime,authstatus,forceauthtime,forceauthstatus,origamount,reauthstatus,cardtype,batchinfo
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
    ( $operation, $trans_date, $trans_time, $enccardnumber, $length,        $amount,          $auth_code,  $avs_code,     $finalstatus, $transflags, $exp,
      $cvvresp,   $refnumber,  $authtime,   $authstatus,    $forceauthtime, $forceauthstatus, $origamount, $reauthstatus, $card_type,   $batchinfo
    )
      = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/logs/fdmsrc/stopgenfiles.txt" ) ) {
      &procutils::flagwrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc", "batchfile.txt", "unlink", "", "" );
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
    &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "fdmsrc", $enccardnumber );

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

    $batchreccnt++;
    $filereccnt++;

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    if ( $card_type eq "" ) {
      $card_type = &smpsutils::checkcard($cardnumber);
    }
    if ( $card_type =~ /(dc|jc)/ ) {
      $card_type = 'ds';
    }
    if ( $card_type =~ /(ma)/ ) {
      $card_type = "mc";
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

&procutils::flagwrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc", "batchfile.txt", "unlink", "", "" );

umask 0033;
$batchfilestr = "";
&procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc", "genfiles$group.txt", "write", "", $batchfilestr );

$mytime = gmtime( time() );
umask 0077;
$outfilestr = "";
$outfilestr .= "\n\n$mytime\n";
&procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc", "ftplog.txt", "append", "", $outfilestr );

system("/home/pay1/batchfiles/prod/fdmsrc/putfiles.pl");

exit;

sub batchdetail {

  $origoperation = "";
  if ( $operation eq "postauth" ) {
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
      &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
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

  $detailcount++;

  $commflag = substr( $auth_code, 221, 1 );
  $commflag =~ s/ //g;

  $trandategmt = substr( $auth_code, 26, 4 );
  $trandategmt =~ s/ //g;
  if ( $trandategmt eq "" ) {
    my $loctime = &miscutils::strtotime($auth_time);

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

  $outfile2str .= "$username  $orderid  $operation  $transflags  $marketdata\n";

  @bd            = ();
  $bd[0]         = "E";                            # record id (1a)  pg. 10-77
  $bd[1]         = "    ";                         # store id (4a)
  $bd[2]         = "    ";                         # terminal id (4a)
  $acategorycode = substr( $auth_code, 414, 4 );
  $acategorycode =~ s/ //g;
  if ( $acategorycode eq "" ) {
    $acategorycode = $categorycode;
  }
  $acategorycode = substr( $acategorycode . " " x 4, 0, 4 );
  $bd[3] = "$acategorycode";                       # merchant category code (4a)

  if ( ( $card_type eq "mc" ) && ( $transflags !~ /moto/ ) && ( $industrycode !~ /^(retail|restaurant$)/ ) ) {
    $cat = "6";
  } else {
    $cat = " ";
  }
  $bd[4] = $cat;                                   # cardholder activated terminal CAT (1a)

  $magstripetrack = substr( $auth_code, 118, 1 );
  $magstripetrack =~ s/ //g;

  $posentry        = substr( $auth_code, 418, 3 );
  $magstripestatus = substr( $posentry,  0,   2 );
  $magstripestatus =~ s/ //g;
  if ( $magstripetrack =~ /^(1|2)$/ ) {
    $magstatus = "90";
  } elsif ( ( $card_type =~ /(vi|mc|ax|ds)/ ) && ( $transflags =~ /(recur|install|cit|mit|defer)/ ) && ( $transflags !~ /(init|notcof)/ ) ) {
    $magstatus = "10";                             # credential on file
  } elsif ( ( $card_type eq "mc" ) && ( $transflags !~ /moto/ ) && ( $industrycode !~ /^(retail|restaurant$)/ ) ) {
    $magstatus = "81";
  } elsif ( $magstripestatus ne "" ) {
    $magstatus = substr( $magstripestatus . "  ", 0, 2 );
  } else {
    $magstatus = "01";
  }
  $bd[5] = $magstatus;                             # magnetic stripe status (2a)

  if ( ( $card_type eq "vi" ) && ( $transflags =~ /(deferred)/ ) ) {
    $visaind = "7";
  } elsif ( ( $card_type eq "vi" ) && ( $transflags !~ /(moto|recur|bill|init|mit|install)/ ) && ( $industrycode !~ /^(retail|restaurant$)/ ) ) {
    $visaind = "1";
  } else {
    $visaind = " ";
  }
  $bd[6] = $visaind;                               # visa service development (1a)
  $bd[7] = " " x 6;                                # filler (6a)

  if ( $origoperation eq "forceauth" ) {
    $authsrc = "D";
  } elsif ( $operation eq "return" ) {
    $authsrc = " ";
  } else {
    $authsrc = " ";
  }
  $bd[8] = $authsrc;                               # authorization source (1a)

  if ( ( $industrycode =~ /^(retail|restaurant)$/ ) && ( $transflags =~ /recur/ ) ) {
    $postermcap = "2";
  } elsif ( ( $industrycode =~ /^(retail|restaurant)$/ )
    && ( $transflags !~ /moto/ )
    && ( ( $transflags !~ /xrecur|xinstall|xmit|xcit|xincr|resub|delay|reauth|defer|noshow/ ) || ( $transflags =~ /init/ ) ) ) {
    $postermcap = "2";
  } else {
    $postermcap = "9";
  }
  $bd[9] = $postermcap;                            # POS terminal capability (1a)

  if ( $magstripetrack eq "2" ) {
    $posentry = "9";
  } elsif ( $magstripetrack eq "1" ) {
    $posentry = "9";
  } elsif ( ( $card_type =~ /(vi|mc|ax|ds)/ ) && ( $transflags =~ /(recur|install|cit|mit|defer)/ ) && ( $transflags !~ /(init|notcof)/ ) ) {
    $posentry = "G";                               # credential on file
  } elsif ( ( $card_type eq "mc" ) && ( $transflags !~ /moto/ ) && ( $industrycode !~ /^(retail|restaurant$)/ ) ) {
    $posentry = "F";
  } else {
    $posentry = "1";
  }
  $bd[10] = $posentry;                             # entry mode (1a)

  if ( $debitflag == 1 ) {
    $cardid = "2";
  } elsif ( $industrycode =~ /(retail|restaurant)/ ) {
    $cardid = "1";
  } else {
    $cardid = "4";
  }
  $bd[11] = $cardid;                               # cardholder ID (1a)

  $mzip = $merchzip;
  $mzip =~ s/[^0-9a-zA-Z]//g;
  $mzip = substr( $mzip . " " x 9, 0, 9 );
  $bd[12] = $mzip;                                 # merchant zip (9a)
  $bd[13] = " " x 6;                               # filler (6a)
  $recseqnum++;
  $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
  $bd[14] = "$recseqnum";                          # record sequence number (6n)
  $bd[15] = " " x 32;                              # filler (32a)

  foreach $var (@bd) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
  }

  $outfilestr  .= "\n";
  $outfile2str .= "\n";

  if (
    (    ( $operation ne "return" )
      && ( $card_type eq "vi" )
      && ( ( $industrycode !~ /retail|restaurant/ ) || ( $transflags =~ /moto/ ) )
      && ( ( ( $operation ne "return" ) && ( $origoperation ne "forceauth" ) ) || ( $commflag == 1 ) )
    )
    || ( ( $operation ne "return" ) && ( $card_type =~ /(vi|mc|ax)/ ) && ( $commflag == 1 ) )
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
    } elsif ( ( $transflags =~ /recur|bill|debt|install|moto/ ) || ( $industrycode !~ /^(retail|restaurant)$/ ) ) {
      $oid = substr( $orderid,        -15, 15 );
      $oid = substr( $oid . " " x 15, 0,   15 );
      $bd[2] = $oid;          # order number (15a)

      $custphone = $phone;    # merchant phone from customer table
      $custphone =~ s/[^0-9a-zA-Z]//g;
      $custphone =~ tr/a-z/A-Z/;
      $custmarketphone = $marketphone;    # phone from marketdata
      $custmarketphone =~ s/ //g;
      if ( $custmarketphone ne "" ) {
        $custphone = $custmarketphone;
      }
      $custphone =~ s/[^0-9]//g;
      $custphone = substr( $custphone . " " x 10, 0, 10 );
      $bd[3] = $custphone;                # customer service number (10n)
    }
    $bd[4] = " " x 45;                    # filler (45a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  # F record pg. 10-81  dcc
  ($currency) = split( / /, $amount );
  if ( (0) && ( $currency ne "usd" ) ) {
    @bd    = ();
    $bd[0] = "F";        # record id (1a)  pg. 10-81
    $bd[1] = " " x 9;    # filler (9a)
    $currency =~ tr/a-z/A-Z/;
    $bd[2] = $currency;    # currency code (3n)

    if ( ( $dccrate > 0 ) && ( $dccoptout eq "N" ) ) {
      $bd[3] = "x" x 6;    # dcc transaction time (6a)
      $bd[4] = "x";        # dcc indicator (1a)
      $bd[5] = "xxx";      # dcc time zone of transaction (3a)
      $bd[6] = " " x 7;    # filler (7a)
      $recseqnum++;
      $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
      $bd[7] = "$recseqnum";    # record sequence number (6n)
      $bd[8] = "x" x 9;         # dcc foreign exchange rate (9n)
      $bd[9] = " " x 19;        # filler (19a)
    } else {
      $bd[3] = " " x 17;        # filler (17a)
      $recseqnum++;
      $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
      $bd[4] = "$recseqnum";    # record sequence number (6n)
      $bd[5] = " " x 45;        # filler (45a)
    }

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  # OR1 record  ax restaurant  pg. 10-101
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
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[6] = "$recseqnum";    # record sequence number (6n)
    $bd[7] = " " x 21;        # filler (21a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  # XM05  url or email address visa
  # XM06  url or email address mastercard, ax, discover pg. 10-104

  if ( ( $operation ne "return" ) && ( $card_type =~ /(vi|mc|ax)/ ) && ( $commflag == 1 ) && ( $operation ne "return" ) ) {

    # XD23  purchase card reference id number  destination country  pg. 10-106
    @bd = ();
    $bd[0] = "XD23";    # record id (4a)  pg. 10-106
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
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

  if ( ( $operation ne "return" ) && ( $card_type =~ /^(vi|mc|ax)$/ ) && ( $commflag == 1 ) ) {

    # XD24  purchase card tax freight duty  pg. 10-107
    @bd = ();
    $bd[0] = "XD24";    # record id (4a)  pg. 10-107
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
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
    if ( $card_type eq "ax" ) {
      $freight = "0" x 13;
    }
    $bd[4] = "$freight";     # freight amount (13n)

    $duty = substr( $auth_code, 81, 11 );
    $duty =~ s/ //g;
    $duty = substr( "0" x 13 . $duty, -13, 13 );
    if ( $card_type eq "ax" ) {
      $duty = "0" x 13;
    }
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

  if ( ( $operation ne "return" ) && ( $card_type =~ /^(vi|mc|ax)$/ ) && ( $commflag == 1 ) ) {

    # XD25  purchase card ship to zip, merchant zip pg. 10-109
    @bd = ();
    $bd[0] = "XD25";    # record id (4a)  pg. 10-109
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
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
  }

  # CP01  product descriptor record  pg. 10-114

  if ( $transflags =~ /(pldeb|star)/ ) {
    $authnetwkid = substr( $auth_code, 411, 2 );
    if ( ( $authnetwkid eq "07" ) || ( $transflags =~ /xstar/ ) ) {

      @bd = ();
      $bd[0] = "XS06";    # record id (1a)
      $recseqnum++;
      $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
      $bd[1] = "$recseqnum";    # record sequence number (6n)
      $posentry = substr( $auth_code,          418, 3 );
      $posentry = substr( $posentry . " " x 3, 0,   3 );
      $bd[2] = $posentry;       # pos entry move (3a)
      $tracenum = substr( $auth_code, 230, 6 );
      $bd[3] = $tracenum;       # system trace audit number (6a)
      $refnum = substr( $refnumber . " " x 12, 0, 12 );
      $bd[4] = $refnum;         # retrieval reference number (12a)
      $bd[5] = " " x 49;        # filler (49a)

      foreach $var (@bd) {
        $outfilestr  .= "$var";
        $outfile2str .= "$var";
      }

      $outfilestr  .= "\n";
      $outfile2str .= "\n";

      @bd    = ();
      $bd[0] = "XS07";          # record id (1a)
      $recseqnum++;
      $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
      $bd[1] = "$recseqnum";    # record sequence number (6n)
      $startranseqnum = substr( $auth_code, 255, 15 );
      $startranseqnum = substr( $startranseqnum . " " x 15, 0, 15 );
      $bd[2] = $startranseqnum;    # star transaction sequence number atsn (15a)
      $bd[3] = " " x 55;           # filler (55a)

      foreach $var (@bd) {
        $outfilestr  .= "$var";
        $outfile2str .= "$var";
      }

      $outfilestr  .= "\n";
      $outfile2str .= "\n";

      @bd    = ();
      $bd[0] = "XE03";             # record id (1a)
      $recseqnum++;
      $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
      $bd[1] = "$recseqnum";       # record sequence number (6n)
                                   #$posentry = substr($auth_code,418,3);
                                   #$posentry = substr($dsposentry . " " x 3,0,3);

      $posentry = "";
      $termop   = "1";
      if ( ( $industrycode =~ /(retail|restaurant|grocery)/ ) && ( $transflags !~ /moto/ ) ) {
        $termop = "0";
      }

      $custop = "0";               # customer operated
      if ( $industrycode =~ /(retail|restaurant|grocery)/ ) {
        $custop = "1";             # merchant operated
      } elsif ( $transflags =~ /moto/ ) {
        $custop = "1";             # merchant operated
      }

      $onoffpremise = " ";

      $cardhpres = "7";            # ecommerce
      if ( ( $industrycode =~ /(retail|restaurant|grocery)/ ) && ( $transflags !~ /moto/ ) ) {
        $cardhpres = "0";
      } elsif ( $transflags =~ /recur/ ) {
        $cardhpres = "4";
      } elsif ( $transflags =~ /defer/ ) {
        $cardhpres = "9";
      } elsif ( $transflags =~ /install/ ) {
        $cardhpres = "S";
      } elsif ( $transflags =~ /mail/ ) {
        $cardhpres = "2";
      } elsif ( $transflags =~ /moto/ ) {
        $cardhpres = "3";
      }

      $cardpres = "1";
      if ( ( $industrycode =~ /(retail|restaurant|grocery)/ ) && ( $transflags !~ /moto/ ) ) {
        $cardpres = "0";
      }

      $devcardret      = " ";
      $transactiondisp = " ";
      $securitycond    = " ";

      $termtype = "25";    # internet terminal
      if ( ( $industrycode =~ /(retail|restaurant|grocery)/ ) && ( $transflags !~ /moto/ ) ) {
        $termtype = "01";
      } elsif ( $transflags =~ /moto/ ) {
        $termtype = "01";
      }

      $terminput = "6";
      if ( $magstripetrack =~ /^(0|1|2)$/ ) {
        $terminput = "S";
      }

      $devicetype = "00";    # card

      $cardhid = "1";
      if ( ( $industrycode =~ /(retail|restaurant|grocery)/ ) && ( $transflags !~ /moto/ ) ) {
        $cardhid = "3";      # signature
      }

      my $posentry = $termop . $custop . $onoffpremise . $cardhpres . $cardpres . $devcardret . $transactiondisp . $securitycond . $termtype . $terminput . $devicetype . $cardhid;    # pos data code

      $bd[2] = $posentry;                                                                                                                                                              # pos entry (13a)

      $bd[3] = " " x 56;                                                                                                                                                               # filler (56a)

      foreach $var (@bd) {
        $outfilestr  .= "$var";
        $outfile2str .= "$var";
      }

      $outfilestr  .= "\n";
      $outfile2str .= "\n";
    }
  }

  my $surcharge = substr( $auth_code, 421, 9 );
  $surcharge =~ s/ //g;
  if ( $surcharge > 0 ) {
    @bd = ();
    $bd[0] = "XS08";    # record id (1a)
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)

    $surcharge = substr( "0" x 8 . $surcharge, -8, 8 );
    $bd[2] = $surcharge;      # surcharge (8a)

    my $sign = "D";
    if ( $operation eq "return" ) {
      $sign = "C";
    }
    $bd[3] = $sign;           # sign (1a)

    $bd[4] = " " x 61;        # filler (61)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";

  }

  my $freeformdata = substr( $auth_code, 255, 20 );
  $freeformdata =~ s/ +$//g;
  if ( $transflags =~ /pldeb/ ) {
    $freeformdata = "";
  }
  if (
    ( ( $card_type eq "vi" ) && ( ( ( $operation ne "return" ) && ( $transflags =~ /moto/ ) )
        || ( ( $transflags !~ /moto/ ) && ( $industrycode !~ /^(retail|restaurant)$/ ) )
        || ( ( $transflags =~ /bill/ ) && ( $industrycode =~ /^(retail)$/ ) ) )
    )
    || ( $freeformdata ne "" )
    || ( ( $card_type eq "mc" )
      && ( $operation ne "return" )
      && ( ( $transflags =~ /moto/ ) || ( ( $industrycode !~ /^(retail|restaurant)$/ ) && ( $transflags =~ /^(recur|bill|debt|install)$/ ) ) ) )
    ) {
    # S  special condition record
    @bd    = ();
    $bd[0] = "S";    # record id (1a)  pg. 10-116
    $bd[1] = "N";    # quasi cash indicator (1a)

    $eci = substr( $auth_code, 161, 2 );
    $eci =~ s/ //g;
    if ( ( $card_type eq "mc" ) && ( $transflags =~ /recur/ ) && ( $transflags !~ /init/ ) ) {
      $eci = '2';    # request flag (2n) 08 = non-secure
    } elsif ( ( $card_type !~ /(vi|mc)/ ) && ( $operation eq "return" ) ) {
      $eci = ' ';    # request flag (2n) 08 = non-secure
    } elsif ( $card_type =~ /ax|ds/ ) {
      $eci = ' ';    # request flag (2n) 08 = non-secure
    } elsif ( ( $card_type =~ /(vi)/ ) && ( $operation eq "postauth" ) && ( $transflags =~ /recur/ ) ) {
      $eci = "2";    # request flag (2n) 08 = non-secure
    } elsif ( ( $card_type =~ /(mc)/ ) && ( $operation eq "postauth" ) && ( $transflags =~ /recur/ ) && ( $transflags !~ /init/ ) ) {
      $eci = "2";    # request flag (2n) 08 = non-secure
    } elsif ( ( $card_type =~ /(vi)/ ) && ( $operation eq "postauth" ) && ( $transflags =~ /install/ ) ) {
      $eci = "3";    # request flag (2n) 08 = non-secure
    } elsif ( ( $card_type =~ /(vi)/ ) && ( $operation eq "postauth" ) && ( $transflags =~ /(init|bill)/ ) ) {
      $eci = "1";    # request flag (2n) 08 = non-secure
    } elsif ( ( $card_type =~ /(mc|vi)/ ) && ( $operation eq "postauth" ) && ( $transflags =~ /moto/ ) ) {
      $eci = "1";    # request flag (2n) 08 = non-secure
    } elsif ( $industrycode =~ /^(retail|restaurant)$/ ) {
      $eci = ' ';    # request flag (2n) 08 = non-secure
    } elsif ( $transflags =~ /install/ ) {
      $eci = " ";    # request flag (2n) 08 = non-secure
    } elsif ( ( $card_type =~ /(mc)/ ) && ( $operation eq "return" ) && ( $transflags =~ /moto/ ) ) {
      $eci = "1";    # request flag (2n) 08 = non-secure
    } elsif ( $card_type eq "mc" ) {
      $eci = " ";    # request flag (2n) 08 = non-secure
    } elsif ( $transflags =~ /moto|bill|debt/ ) {
      $eci = "1";    # request flag (2n) 08 = non-secure
    } elsif ( $eci > 0 ) {
      if ( $eci eq "01" ) {
        $eci = "5";
      } elsif ( $eci eq "02" ) {
        $eci = "6";
      } elsif ( $eci eq "03" ) {
        $eci = "7";
      }
      $eci = substr( $eci, -1, 1 );    # request flag (2n) 08 = non-secure
    } else {
      $eci = '7';                      # request flag (2n) 08 = non-secure
    }
    $bd[2] = "$eci";                   # special condition indicator (1a)
    $bd[6] = " " x 39;                 # filler (34a)
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[7] = "$recseqnum";             # record sequence number (6n)

    $specialuse = " " x 19;
    if ( $freeformdata ne "" ) {
      $freeformdata = substr( $freeformdata . " " x 12, 0, 12 );

      my $authtime = substr( $auth_code, 314, 14 );
      $authtime = substr( $authtime,           -6, 6 );
      $authtime = substr( $authtime . " " x 6, 0,  6 );
      my $spectranstime = $authtime;

      if ( $spectranstime eq "      " ) {
        $spectranstime = sprintf( "%02d%02d%02d", substr( $trans_time, 8, 2 ), substr( $trans_time, 10, 2 ), substr( $trans_time, 12, 2 ) );
      }

      $specialuse = $spectranstime . $freeformdata . " ";
    }
    $bd[8] = $specialuse;    # special use fields (19a)
                             # now trans time, inv number, filler

    if ( ( $operation ne "return" ) && ( $card_type eq "vi" ) && ( $transflags =~ /debt/ ) ) {
      $transind = "9";
    } else {
      $transind = " ";
    }
    $bd[9]  = "$transind";    # merchant transaction indicator (1a)
    $bd[10] = " ";            # certified for mastercard merchant advice code (1a)
    $bd[11] = "  ";           # mastercard transaction category indicator (2a)
    $bd[12] = " " x 9;        # filler (9a)

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
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)
    $posdata = substr( $auth_code,          105, 12 );
    $posdata = substr( $posdata . " " x 12, 0,   12 );
    $bd[2]   = "$posdata";

    my $eci = substr( $auth_code, 161, 2 );
    my $axeci = "07";
    if ( ( $industrycode =~ /(retail|restaurant)/ ) || ( $transflags =~ /moto/ ) ) {
      $axeci = "  ";          #
    } elsif ( ( $transflags =~ /recur|install/ ) && ( $transflags !~ /init/ ) ) {
      $axeci = "  ";
    } elsif ( $eci eq "02" ) {
      $axeci = "06";          # 06
    } elsif ( $eci eq "01" ) {
      $axeci = "05";          # 05
    } elsif ( $eci eq "03" ) {
      $axeci = "07";          # 07
    }

    $bd[14] = $axeci;         # amex token electronic commerce indicator (2a)
    $bd[15] = " " x 56;       # filler (58a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  if ( ( ( $card_type =~ /(vi|ax)/ ) || ( $transflags =~ /xstar/ ) ) && ( $origoperation ne "forceauth" ) && ( $operation ne "xreturn" ) ) {

    # XD01  supplemental vi  pg. 10-122
    @bd = ();
    $bd[0] = "XD01";    # record id (4a)  pg. 10-116
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
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

    $authrespcode = substr( $auth_code, 335, 3 );
    if ( $authrespcode eq "002" ) {
      $authrespcode = "010";
    }
    $authrespcode = substr( $authrespcode,           -2, 2 );
    $authrespcode = substr( $authrespcode . " " x 2, 0,  2 );
    if ( $card_type ne "vi" ) {
      $authrespcode = "  ";
    }
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

  if ( ( $card_type eq "mc" ) && ( $origoperation ne "forceauth" ) && ( $operation ne "xreturn" ) ) {

    # XD02  supplemental mc  pg. 10-124
    @bd = ();
    $bd[0] = "XD02";    # record id (4a)  pg. 10-116
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
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
      $ucafind = " ";
    }
    $bd[5] = "$ucafind";         # ucaf status (1a)

    $bd[6] = " ";                # filler (1a)
    $authamt = substr( $auth_code, 163, 12 );
    $authamt =~ s/ //g;
    $authamt = substr( "0" x 12 . $authamt, -12, 12 );
    $bd[7] = "$authamt";         # auth amount (12n)

    $transerrcode = substr( $auth_code,          175, 1 );
    $transerrcode = substr( $transerrcode . " ", 0,   1 );
    $transerrcode =~ tr/3/E/;
    $bd[8] = "$transerrcode";    # transaction error edit code (1a)

    $cvcerror = substr( $auth_code,      176, 1 );
    $cvcerror = substr( $cvcerror . " ", 0,   1 );
    $bd[9] = "$cvcerror";        # cvc error (1a)

    $posentrychange = substr( $auth_code,            222, 1 );
    $posentrychange = substr( $posentrychange . " ", 0,   1 );
    $bd[10] = $posentrychange;    # pos entry mode change (1a)

    my $mcauthtime = substr( $auth_code, 314 + 8, 4 );
    $mcauthtime = substr( $mcauthtime . " " x 4, 0, 4 );
    $bd[11] = "$mcauthtime";      # auth time HHMM (4n)

    $bd[12] = "00";               # device type indicator (2a)

    $authrespcode = substr( $auth_code,              335, 3 );
    $authrespcode = substr( $authrespcode,           -2,  2 );
    $authrespcode = substr( $authrespcode . " " x 2, 0,   2 );
    if ( $authrespcode eq "02" ) {
      $authrespcode = "10";
    }
    $bd[13] = $authrespcode;      # auth response code (2a)
    $bd[14] = " " x 30;           # filler (30a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";

    # XE02  supplemental mc
    @bd    = ();
    $bd[0] = "XE02";              # record id (4a)  pg. 10-116
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";        # record sequence number (6n)

    my $posdata = substr( $auth_code, 105, 12 );
    $posdata = substr( $posdata . " " x 12, 0, 12 );
    $bd[2] = "$posdata";

    $bd[3] = " " x 58;            # filler (58a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  my $printstr = "$card_type  $commflag\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );

  if (
    ( ( $card_type eq "vi" ) && ( $operation ne "xreturn" ) && ( ( $commflag == 1 ) || ( $operation eq "return" ) || ( ( $origoperation ne "forceauth" ) && ( $operation eq "postauth" ) ) ) )
    || ( ( $card_type eq "mc" )
      && ( $operation ne "return" )
      && ( ( $commflag == 1 ) || ( $magstripetrack =~ /^(1|2)$/ ) || ( ( $reauthstatus eq "success" ) && ( $operation eq "postauth" ) ) ) )
    || ( $transflags =~ /star/ )
    || ( ( $card_type =~ /(ax|ds|dc|jc)/ ) && ( $magstripetrack =~ /^(1|2)$/ ) && ( $operation eq "postauth" ) )
    ) {

    # XD05  market specific data record  pg. 10-126
    @bd = ();
    $bd[0] = "XD05";    # record id (4a)  pg. 10-126
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)

    $idformat = " ";
    if ( ( $card_type eq "mc" ) && ( $reauthstatus eq "success" ) && ( $operation eq "postauth" ) ) {
      $idformat = " ";
    } elsif ( ( $card_type eq "vi" ) && ( ( $industrycode !~ /retail|restaurant/ ) || ( $transflags =~ /(moto|recur|install|mit|cit)/ ) ) && ( $commflag ne "1" ) ) {
      $idformat = "1";
    }
    $bd[2] = $idformat;       # purchase id format (1a)
    $bd[3] = "0";             # no show indicator (1a)
    $bd[4] = "      ";        # extra charges indicator (6a)

    $commflag = substr( $auth_code, 221, 1 );
    if ( ( $card_type ne "ax" ) && ( $operation ne "return" ) && ( $commflag eq "1" ) ) {
      $bd[5] = "$transyymmdd";    # market specific date (6n)
    } else {
      $bd[5] = "000000";          # market specific date (6n)
    }

    my $amt = "0" x 12;

    if ( $card_type =~ /(vi|mc)/ ) {
      $amt = substr( $amount, 4 );
      $amt = sprintf( "%d", ( $amt * 100 ) + .0001 );
      $amt = substr( "0" x 12 . $amt, -12, 12 );
    }
    $bd[6] = $amt;                # total auth amount (12n)

    if ( ( $card_type eq "vi" ) && ( $transflags =~ /(init|recur|bill|debt|install|deferred)/ ) ) {
      $marketind = "B";
    } elsif ( $transflags =~ /(transit)/ ) {
      $marketind = "T";
    } elsif ( $transflags =~ /(hsa)/ ) {
      $marketind = "M";
    } else {
      $marketind = " ";
    }
    $bd[7] = $marketind;          # market specific auth indicator (1a)

    $cardlevelres = substr( $auth_code,           177, 2 );
    $cardlevelres = substr( $cardlevelres . "  ", 0,   2 );
    $bd[8] = $cardlevelres;       # visa card level indicator (2a)
    $servicecode = substr( $auth_code,             356, 3 );
    $servicecode = substr( $servicecode . " " x 3, 0,   3 );
    $bd[9] = $servicecode;        # service code from magstripe data (3a)
    $poscond = "  ";
    if ( $card_type eq "vi" ) {
      if ( $magstripetrack =~ /^(1|2)$/ ) {
        $poscond = '00';
      } elsif ( ( $card_type =~ /^(vi|mc|ax|ds)$/ ) && ( $transflags =~ /xrecinitial|recur|xdeferred|install/ ) ) {
        $poscond = '04';
      } elsif ( $transflags =~ /moto/ ) {
        $poscond = '08';
      } elsif ( ( $industrycode =~ /restaurant/ ) && ( $magstripetrack !~ /(1|2)/ ) ) {
        $poscond = '71';
      } elsif ( ( $card_type =~ /vi/ ) && ( $magstripetrack eq "0" ) ) {
        $poscond = '71';
      } elsif ( ( $card_type =~ /vi/ ) && ( $industrycode =~ /retail|restaurant/ ) ) {
        $poscond = '00';
      } elsif ( $industrycode =~ /^(retail|restaurant|petroleum)$/ ) {
        $poscond = '00';
      } else {
        $poscond = '59';
      }
    }
    $bd[10] = $poscond;    # visa pos condition code (2a)
    $bd[11] = " " x 36;    # filler (36a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  if ( $transflags =~ /token/ ) {

    # XD67  token data
    @bd = ();
    $bd[0] = "XD67";    # record id (4a)  pg. 10-126
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)

    $token = substr( $cardnumber . " " x 19, 0, 19 );
    $bd[2] = "$token";        # token (19a)

    $tokentype = substr( $auth_code,           380, 4 );
    $tokentype = substr( $tokentype . " " x 4, 0,   4 );
    $bd[3] = "$tokentype";    # token type (4)

    $bd[4] = " " x 47;        # filler (47)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  $cavv = substr( $batchinfo, 42, 32 );
  $cavv =~ s/ //g;
  if ( (0) && ( $card_type eq "mc" ) && ( $cavv ne "" ) ) {
    if ( $transflags =~ /3d2/ ) {
      @bd = ();
      $bd[0] = "XG04";    # record id (4a)  pg. 10-126
      $recseqnum++;
      $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
      $bd[1] = "$recseqnum";    # record sequence number (6n)

      $xid = substr( $batchinfo,      0, 32 );
      $xid = substr( $xid . " " x 32, 0, 32 );
      $bd[2] = "$xid";          # directory server transaction id first 32 of 36 (32a)

      $bd[3] = " " x 38;        # filler (38)

      foreach $var (@bd) {
        $outfilestr  .= "$var";
        $outfile2str .= "$var";
      }

      $outfilestr  .= "\n";
      $outfile2str .= "\n";
    }

    @bd    = ();
    $bd[0] = "XG05";            # record id (4a)  pg. 10-126
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";      # record sequence number (6n)

    $xid = substr( $batchinfo,     32, 4 );
    $xid = substr( $xid . " " x 4, 0,  4 );
    $bd[2] = "$xid";            # directory server transaction id last 4 (32a)

    $protocol = "1";
    if ( $transflags =~ /3d2/ ) {
      $protocol = "2";
    }
    $bd[3] = "$protocol";       # protocol (1a)

    $bd[4] = " " x 65;          # filler (65)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";

    @bd    = ();
    $bd[0] = "XG06";            # record id (4a)  pg. 10-126
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";      # record sequence number (6n)

    $cavv = substr( $cavv . " " x 32, 0, 32 );
    $bd[2] = "$cavv";           # accountholder authentication value aav (32a)

    $bd[3] = " " x 38;          # filler (38)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  if ( ( $card_type eq "ds" ) && ( ( $operation eq "return" ) || ( ( $operation eq "postauth" ) && ( $origoperation ne "forceauth" ) ) ) ) {

    # XV01  market specific data record  pg. 9-78
    @bd = ();
    $bd[0] = "XV01";    # record id (4a)  pg. 9-78
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)
    my $authtime = substr( $auth_code, 300, 14 );
    $authtime = substr( $authtime,           -6, 6 );
    $authtime = substr( $authtime . " " x 6, 0,  6 );
    $bd[2] = "$authtime";     # local transaction time (6n)
    my $pcode = substr( $auth_code, 236, 6 );
    $pcode = substr( $pcode . " " x 6, 0, 6 );
    $bd[3] = "$pcode";        # processing code (6a)
    my $dstrace = substr( $auth_code, 230, 6 );
    $dstrace = substr( $dstrace . " " x 6, 0, 6 );

    #$dstrace = substr($refnumber,-6,6);
    $bd[4] = "$dstrace";      # system trace audit number (6n)

    my $dsposentry = substr( $auth_code, 242, 4 );
    $dsposentry = substr( $dsposentry . " " x 3, 0, 3 );
    $bd[5] = "$dsposentry";    # pos entry mode (3a)

    my $trackcond1 = "0";
    my $trackcond2 = "0";
    if ( $magstripetrack eq "1" ) {
      $trackcond1 = "2";
    } elsif ( $magstripetrack eq "2" ) {
      $trackcond2 = "2";
    } elsif ( ( $industrycode !~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
      $trackcond1 = "6";
    }
    $transcond = $trackcond1 . $trackcond2;

    my $dstransqual = substr( $auth_code, 248, 2 );
    $dstransqual =~ s/ //g;
    if ( ( $card_type =~ /(ds|dc|jc)/ ) && ( $dstransqual ne "" ) ) {
      $transcond = substr( $dstransqual . "  ", 0, 2 );
    }
    $bd[6] = $transcond;    # transaction track data condition code (2a)

    my $posdata = substr( $auth_code, 105, 13 );
    $posdata = substr( $posdata . " " x 13, 0, 13 );
    $bd[7] = "$posdata";    # pos data (13a)
    $bd[8] = " " x 34;      # filler (34a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile2str .= "\n";

    # XV02  market specific data record  pg. 9-85
    @bd    = ();
    $bd[0] = "XV02";        # record id (4a)  pg. 9-85
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[1] = "$recseqnum";    # record sequence number (6n)
    $authrespcode = substr( $auth_code,           246, 2 );
    $authrespcode = substr( $authrespcode . "  ", 0,   2 );
    $bd[2] = $authrespcode;    # ds auth response code (2a)
    $bd[3] = "N";              # partial shipment indicator (1a)
    $avs_code = substr( $avs_code . " ", 0, 1 );
    $bd[4] = "$avs_code";      # avs response (1a)
    $authamt = substr( $auth_code, 163, 12 );
    $authamt =~ s/ //g;
    $authamt = substr( "0" x 13 . $authamt, -13, 13 );
    $bd[5] = "$authamt";       # auth amount (13n)
    $transid = substr( $auth_code,          6,   15 );
    $transid = substr( "0" x 15 . $transid, -15, 15 );

    if ( $transflags =~ /pldeb/ ) {
      $transid = " " x 15;
    }
    $bd[6] = "$transid";       # network reference id nrid(15n)
    $bd[7] = " " x 38;         # filler (38a)

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
      $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
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
  if ( $transflags =~ /token/ ) {
    $cardnum = "0" x 16;
  }
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

  $transdate = substr( $auth_code, 304, 4 );

  $bd[4] = "$transdate";                         # transaction date MMDD (4n) LocalDateTime
  $authcode = substr( $auth_code,          0, 6 );
  $authcode = substr( $authcode . " " x 6, 0, 6 );
  $bd[5] = "$authcode";                          # authorization code (6a)

  $authdate = "$trandategmt";

  $bd[6] = "$authdate";                          # authorization date MMDD (4n) TrnmsnDateTime
  $expdate = substr( $exp, 0, 2 ) . substr( $exp, 3, 2 );
  $bd[7] = "$expdate";                           # card expiration date MMYY (4n)
  $recseqnum++;
  $refnum = substr( "0" x 8 . $recseqnum, -8, 8 );
  $bd[8] = "$refnum";                            # reference number (8n) my choice
  $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
  $bd[9]   = "$recseqnum";                       # record sequence number (6n)
  $bd[10]  = " ";                                # filler (1a)
  $bd[11]  = " ";                                # prepaid card indicator (1a)
  $transid = "";

  if ( $transflags =~ /pldeb/ ) {
    $transid = substr( $auth_code, 6, 15 );
    $transid =~ s/ //g;
    if ( $transid eq "" ) {
      $transid = "0" x 15;
    }
  } elsif ( $card_type =~ /^(vi|ax)$/ ) {
    $transid = substr( $auth_code, 6, 15 );
    $transid =~ s/ //g;
    $transid = substr( $transid . "0" x 15, 0, 15 );
  } else {
    $transid = "0" x 15;
  }
  print "transid: $transid\n";
  $bd[12]    = "$transid";    # transaction identifier (15n)
  $bd[13]    = " ";           # filler (1a)
  $validcode = "";
  if ( $card_type eq "vi" ) {
    $validcode = substr( $auth_code, 21, 4 );
    $validcode =~ s/ //g;
  }
  $validcode = substr( $validcode . " " x 4, 0, 4 );
  $bd[14] = "$validcode";     # validation code (4a)

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

  my $dbquerystr = <<"dbEOM";
        insert into batchfilesfdmsrc
	(username,filename,batchname,filenum,detailnum,trans_date,orderid,status,amount,operation,processor)
        values (?,?,?,?,?,?,?,?,?,?,?)
dbEOM

  my %inserthash = (
    "username",  "$username", "filename",   "$filename",  "batchname", "$summaryid", "filenum", "$filejuliandate$filenum",
    "detailnum", "$refnum",   "trans_date", "$today",     "orderid",   "$orderid",   "status",  "pending",
    "amount",    "$amt",      "operation",  "$operation", "processor", "fdmsrc"
  );
  &procutils::dbinsert( $username, $orderid, "pnpmisc", "batchfilesfdmsrc", %inserthash );

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
  $bh[3] = "5692";                                       # merchant id/security code (4n)

  $submissiontype = "7";
  if ( ( $marketdata eq "" ) || ( $marketdata eq " " x 38 ) ) {
    $submissiontype = "6";
  }
  $bh[4] = $submissiontype;                              # submission type 7 = expanded N record (1a)

  # zzzz
  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
  $lyear = substr( $lyear, -2, 2 );

  $bh[5] = "$filejuliandate";                            # submission create date (5n)
  $filenum = substr( "0" . $filenum, -1, 1 );
  $bh[6] = "$filenum";                                   # submission sequence number (1n)
  $bh[7] = "5692";                                       # security code (4n)
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

  $mylen = length($marketdata);

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
      $mphone = $phone;
      $mphone =~ s/[^a-zA-Z0-9]//g;
      $mphone =~ tr/a-z/A-Z/;
      $mphone = substr( $mphone, 0, 3 ) . "-" . substr( $mphone, 3, 3 ) . "-" . substr( $mphone, 6 );
      $city = $mphone;
    }

    $city =~ tr/a-z/A-Z/;
    $city = substr( $city . " " x 13, 0, 13 );
    $city =~ tr/a-z/A-Z/;
    $bh[2] = "$city";    # merchant city (13a)
    $state = substr( $state . " " x 2, 0, 2 );
    if ( ( $mcountry eq "" ) || ( $mcountry eq "US" ) ) {
      $state = $state . " ";
    } elsif ( $mcountry eq "CA" ) {
      $state = $state . "*";
    } else {
      $mcountry =~ tr/a-z/A-Z/;
      $state = &isotables::countryUSUSA($mcountry);
    }
    $state = substr( $state . " " x 3, 0, 3 );
    $state =~ tr/a-z/A-Z/;
    $bh[3] = "$state";    # merchant state (3a)
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
    $marketphone = substr( $marketdata, 25, 13 );
    $marketphone =~ tr/a-z/A-Z/;

    if ( ( $industrycode !~ /retail|restaurant/ ) || ( $transflags =~ /moto/ ) ) {
      $city = $marketphone;
    }
    $city =~ tr/a-z/A-Z/;
    $city = substr( $city . " " x 11, 0, 11 );
    $city =~ tr/a-z/A-Z/;
    $bh[3] = "$city";       # merchant city (11a)
    $bh[4] = " ";           # filler (1a)
    $state = substr( $state . " " x 2, 0, 2 );
    if ( ( $mcountry eq "" ) || ( $mcountry eq "US" ) ) {
    } elsif ( $mcountry eq "CA" ) {
      $state = $state . "*";
    } else {
      $mcountry =~ tr/a-z/A-Z/;
      $state = &isotables::countryUSUSA($mcountry);
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
  if ( ( $card_type =~ /^(vi|mc)$/ ) && ( $commflag == 1 ) ) {
    @bd = ();
    $bd[0] = "XM02";    # record id (4a)  pg. 10-104
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
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
  }

  if ( $mcountry ne "US" ) {
    @bd = ();
    $bd[0] = "XM03";    # record id (4a)  pg. 10-105
    $recseqnum++;
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
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

  if ( ( $axarray{"$username"} == 1 ) && ( $chargedescr ne "" ) ) {
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
}

sub fileheader {
  my $printstr = "in fileheader\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
  $batchcount = 0;
  $filecount++;

  $file_flag = 0;
  my $dbquerystr = <<"dbEOM";
        select filenum,batchdate
        from fdmsrc
        where username='fdmsrc'
dbEOM
  my @dbvalues = ();
  ( $filenum, $batchdate ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $printstr = "batchdate: $batchdate, today: $today, filenum: $filenum\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );

  if ( $batchdate != $todaylocal ) {
    $filenum = 0;
  }
  $filenum = $filenum + 1;
  if ( $filenum > 9 ) {
    my $printstr = "<h3>You have exceeded the maximum allowable batches for today.</h3>\n";
    &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
  }

  ( $d1, $d2, $ttime ) = &miscutils::genorderid();
  $filename = "$ttime$pid";

  my $dbquerystr = <<"dbEOM";
        update fdmsrc set filenum=?,batchdate=?
	where username='fdmsrc'
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

  my $filestatus = &procutils::fileencwrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc/$fileyear", "$filename", "write", "", $outfilestr );
  $outfile2str .= "\nfileencwritestatus: $filestatus\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc/$fileyear", "$filename.txt", "write", "", $outfile2str );

  my $printstr = "filenum: $filenum  today: $today  amt: $filetotalamtstr  cnt: $filetotalcnt\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
}

sub pidcheck {
  my @infilestrarray = &procutils::fileread( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc", "pid$group.txt" );
  $chkline = $infilestrarray[0];
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/logs/fdmsrc/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
    &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
    my $printstr = "$pidline\n";
    &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
    my $printstr = "$chkline\n";
    &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: noc\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdmsrc - dup genfiles\n";
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
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $printstr = "The $times2 Sunday of month $month2 happens on the $mday2\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  my $printstr = "newtime: $newtime $timezone2\n\n";
  &procutils::filewrite( "$username", "fdmsrc", "/home/pay1/batchfiles/devlogs/fdmsrc", "miscdebug.txt", "append", "misc", $printstr );
  return $newtime;
}

