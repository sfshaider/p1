#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use procutils;
use smpsutils;
use Math::BigInt;
use Math::BigFloat;

$devprod   = "logs";
$devprodpl = "prod";

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
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  exit;
}

my $group = $ARGV[0];
if ( $group eq "" ) {
  $group = "0";
}
my $printstr = "group: $group\n";
&procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

if ( ( -e "/home/pay1/batchfiles/logs/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/logs/fdmsintl/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdmsintl/genfiles.pl $group'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  exit;
}

$mytime  = time();
$machine = `uname -n`;
$pid     = $$;

chop $machine;
$outfilestr = "";
$pidline    = "$mytime $$ $machine";
$outfilestr .= "$pidline\n";
&procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "pid$group.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my $chkline = &procutils::fileread( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "pid$group.txt" );
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  $printstr .= "$pidline\n";
  $printstr .= "$chkline\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

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

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
( $dummy, $today, $todaytime ) = &miscutils::genorderid();

$runtime = substr( $todaytime, 8, 2 );

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsintl/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsintl - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory fdmsintl/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batchtotalamt = Math::BigInt->new(0);
$filetotalamt  = Math::BigInt->new(0);

$batch_flag = 1;
$file_flag  = 1;

my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        and t.trans_date<=?
        $checkstring
        and t.finalstatus='pending'
        and (t.accttype is NULL or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastoptime>=?
        and o.lastopstatus='pending'
        and o.processor='fdmsintl'
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
$mycnt = 0;
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $dbquerystr = <<"dbEOM";
        select username,banknum,discovermid,amexmid,categorycode,newusdflag,dsfullservice,batchtime,industrycode
        from fdmsintl
        where username=?
dbEOM
  my @dbvalues = ($user);
  my ( $username, $banknum, $discovermid, $amexmid, $categorycode, $newusdflag, $dsfullservice, $batchgroup, $industrycode ) =
    &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
        select currency
        from customers
        where username=?
dbEOM
  my @dbvalues = ($user);
  my ($currency) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $currency eq "" ) {
    $currency = "usd";
  }
  $banknumarray{$username}      = $banknum;
  $currencyarray{$username}     = $currency;
  $newusdflagarray{$username}   = $newusdflag;
  $batchgrouparray{$username}   = $batchgroup;
  $industrycodearray{$username} = $industrycode;

  $mycnt++;
  @userarray = ( @userarray, $user );
  $userbankarray{"$banknumarray{$user} $currencyarray{$user} $user"} = 1;
  $usercountarray{$user}                                             = $usercount;
  $starttdatearray{$user}                                            = $usertdate;
}

foreach $key ( sort keys %userbankarray ) {
  ( $banknum, $currency, $username ) = split( / /, $key );

  $newusdflag   = $newusdflagarray{"$username"};
  $batchgroup   = $batchgrouparray{"$username"};
  $industrycode = $industrycodearray{"$username"};

  ( $d1, $d2, $time ) = &miscutils::genorderid();

  if ( ( -e "/home/pay1/batchfiles/logs/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/logs/fdmsintl/stopgenfiles.txt" ) ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "stopgenfiles\n";
    my $printstr = "stopgenfiles\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl",            "miscdebug.txt",          "append", "misc", $printstr );
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear", "$username$time$pid.txt", "append", "",     $logfilestr );
    unlink "/home/pay1/batchfiles/$devprod/fdmsintl/batchfile.txt";
    last;
  }

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,currency,processor
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $status, $currency, $processor ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $currency eq "" ) {
    $currency = "usd";
  }

  if ( $processor ne "fdmsintl" ) {
    next;
  }

  if ( $status ne "live" ) {
    next;
  }

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
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  my $printstr = "gmt today: $todaytime\n";
  $printstr .= "est today: $esttime\n";
  $printstr .= "est yesterday: $yesterday\n";
  $printstr .= "settletime: $settletime\n";
  $printstr .= "sweeptime: $sweeptime\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr .= "$username  sweeptime: $sweeptime  settletime: $settletime\n";
  $logfilestr .= "$features\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "genfiles$group.txt", "write", "", $batchfilestr );

  my $printstr = "bbbb $username  $banknum\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "batchfile.txt", "write", "", $batchfilestr );

  umask 0077;
  $logfilestr = "";
  my $printstr = "cccc $username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr .= "$username $usercountarray{$username} $starttransdate $currency\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  my $dbquerystr = <<"dbEOM";
          select orderid
          from operation_log force index(oplog_tdateloptimeuname_idx)
          where trans_date>=?
          and username=?
          and lastopstatus='pending'
          and lastop IN ('postauth','return')
          and (voidstatus is NULL or voidstatus='')
          and (accttype is NULL or accttype='credit')
dbEOM
  my @dbvalues = ( "$starttransdate", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  @orderidarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 1 ) {
    ($orderid) = @sthtransvalarray[ $vali .. $vali + 0 ];

    $orderidarray[ ++$#orderidarray ] = $orderid;
  }

  foreach $orderid ( sort @orderidarray ) {
    my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,amount,
                 auth_code,avs,lastopstatus,transflags,authtime
          from operation_log
          where orderid=?
          and username=?
          and lastop in ('postauth','return')
          and lastopstatus in ('pending')
          and (voidstatus is NULL or voidstatus='')
          and (accttype is NULL or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$username" );
    ( $chkorderid, $operation, $trans_date, $trans_time, $enccardnumber, $length, $amount, $auth_code, $avs_code, $finalstatus, $transflags, $authtime ) =
      &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    # the time of the switch to the new genfiles
    if ( ( $authtime ne "" ) && ( $authtime <= "20170511052500" ) ) {
      next;
    }

    if ( ( -e "/home/pay1/batchfiles/logs/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/logs/fdmsintl/stopgenfiles.txt" ) ) {
      unlink "/home/pay1/batchfiles/$devprod/fdmsintl/batchfile.txt";
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
      next;    # transaction is newer than sweeptime
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "fdmsintl", $enccardnumber );

    my $dbquerystr = <<"dbEOM";
          select origamount,forceauthstatus
          from operation_log
          where orderid=?
          and username=?
          and trans_date>=?
          and (authstatus='success'
          or forceauthstatus='success')
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$twomonthsago" );
    ( $origamount, $forceauthstatus ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $origoperation = "";
    if ( $forceauthstatus eq "success" ) {
      $origoperation = "forceauth";
    }

    if ( ( $username ne $usernameold ) && ( $batch_flag == 0 ) ) {
      &batchtrailer();
      $batch_flag = 1;
    }

    if ( ( ( $banknum ne $banknumold ) || ( $currency ne $currencyold ) ) && ( $file_flag == 0 ) ) {
      &filetrailer();
      $file_flag = 1;
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
        and (accttype is NULL or accttype='credit')
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
          and (voidstatus is NULL or voidstatus='')
          and (accttype is NULL or accttype='credit')
dbEOM
    my @dbvalues = ( "$time$summaryid", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
        insert into batchfilesfdmsi
	(username,banknum,filename,batchnum,batchheader,trans_date,orderid,status,merchant_id)
        values (?,?,?,?,?,?,?,?,?)
dbEOM
    my %inserthash = (
      "username",   "$username", "banknum", "$banknum", "filename", "$filename", "batchnum",    "$time$summaryid", "batchheader", "$fileext",
      "trans_date", "$today",    "orderid", "$orderid", "status",   "pending",   "merchant_id", "$merchant_id"
    );
    &procutils::dbinsert( $username, $orderid, "pnpmisc", "batchfilesfdmsi", %inserthash );

    $batchreccnt++;
    $filereccnt++;
    $recseqnum++;
    $recseqnum   = substr( "0000000" . $recseqnum, -7, 7 );
    $transseqnum = $transseqnum + 1;
    $transseqnum = substr( "000" . $transseqnum, -3, 3 );
    $cardnumber  = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $card_type    = &smpsutils::checkcard($cardnumber);
    $origcardtype = $card_type;
    if ( $card_type =~ /dc|jc/ ) {
      $card_type = "ds";
    }

    $transtime = substr( $trans_time, 8, 6 );
    $transamt = substr( $amount, 4 );
    $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );

    $transamt = substr( "0" x 12 . $transamt, -12, 12 );
    $authcode = substr( $auth_code,           0,   6 );
    if ( $operation eq "return" ) {
      $tcode = "07";
    } else {
      $tcode = "06";
    }

    $clen = length($cardnumber);
    $cabbrev = substr( $cardnumber, 0, 4 );
    if ( $card_type eq "vi" ) {
      $cardtype = 'V';    # visa
    } elsif ( $card_type eq "mc" ) {
      $cardtype = 'M';    # mastercard
    } elsif ( $card_type eq "ax" ) {
      $cardtype = 'A';    # amex
    } elsif ( $card_type eq "dc" ) {
      $cardtype = 'S';    # carte blanche
    } elsif ( $card_type eq "dc" ) {
      $cardtype = 'S';    # diners club
    } elsif ( $card_type eq "ds" ) {
      $cardtype = 'S';    # Novus
    } elsif ( $card_type eq "jc" ) {
      $cardtype = 'S';    # jcb
    }

    $transseqnum = substr( $transseqnum . " " x 3, 0, 3 );
    $tcode       = substr( $tcode . " " x 2,       0, 2 );
    $transtime   = substr( $transtime . " " x 6,   0, 6 );

    $authresp       = substr( $authresp . " " x 2, 0,  2 );
    $avs_code       = substr( $avs_code . " " x 1, 0,  1 );
    $magstripetrack = substr( $auth_code,          25, 1 );

    @bd       = ();
    $bd[0]    = $tcode;                                    # tran code (2n) 06 = sale, 07 = return
    $bd[1]    = $cardtype;                                 # card type (1a)
    $ccard    = substr( $cardnumber . " " x 16, 0, 16 );
    $bd[2]    = $ccard;                                    # cardholder number (16a)
    $bd[3]    = " ";                                       # filler (1a)
    $tdate    = substr( $trans_time, 4, 4 );
    $bd[4]    = $tdate;                                    # transaction date - MMDD EST (4n)
    $bd[5]    = " ";                                       # filler (1a)
    $authcode = substr( $authcode . " " x 6, 0, 6 );
    $bd[6]    = $authcode;                                 # authorization code
    if ( ( ( $currency eq "usd" ) && ( $card_type eq "vi" ) && ( $transflags =~ /recurring/ ) )
      || ( ( $currency eq "usd" ) && ( $card_type eq "mc" ) && ( $transflags =~ /recurring|recinitial/ ) )
      || ( ( $currency eq "usd" ) && ( $card_type eq "ax" ) && ( $transflags =~ /recurring|recinitial/ ) )
      || ( ( $currency eq "usd" ) && ( $card_type eq "ds" ) && ( $transflags =~ /recurring/ ) )
      || ( ( $currency ne "usd" ) && ( $card_type eq "vi" ) && ( $transflags =~ /recurring|install/ ) )
      || ( ( $currency ne "usd" ) && ( $card_type eq "mc" ) && ( $transflags =~ /recurring|recinitial/ ) )
      || ( ( $currency ne "usd" ) && ( $card_type eq "ax" ) && ( $transflags =~ /recurring|recinitial/ ) )
      || ( ( $currency ne "usd" ) && ( $card_type eq "ds" ) && ( $transflags =~ /recurring/ ) ) ) {
      $bd[7] = "R";                                        # mail order/tel order flag - space = default
    } elsif ( ( $origoperation eq "forceauth" ) && ( $operation eq "postauth" ) ) {
      $bd[7] = "T";                                        # mail order/tel order flag - space = default
    } elsif ( ( $card_type eq "vi" ) && ( $transflags =~ /bill/ ) ) {
      $bd[7] = "S";                                        # mail order/tel order flag - space = default
    } elsif ( ( $currency eq "usd" ) && ( $card_type eq "vi" ) && ( $transflags =~ /install/ ) ) {
      $bd[7] = "N";                                        # mail order/tel order flag - space = default
    } elsif ( ( $card_type eq "vi" ) && ( $transflags =~ /deferred/ ) ) {
      $bd[7] = "F";                                        # mail order/tel order flag - space = default
    } elsif ( $transflags =~ /moto/ ) {
      $bd[7] = "M";                                        # mail order/tel order flag - space = default
    } else {
      $bd[7] = " ";                                        # mail order/tel order flag - space = default
    }
    $tamt = $transamt;
    $tamt = sprintf( "%08d", $tamt + .0001 );
    if ( ( $currency eq "cad" ) || ( ( $newusdflag eq "yes" ) && ( $currency eq "usd" ) ) ) {
      $bd[8] = $tamt;                                      # transaction amount (12n)
    } else {
      $bd[8] = "0" x 8;                                    # transaction amount (8n)
    }

    $eciind = substr( $auth_code, 161, 2 );
    $eciind = substr( $eciind,    -1,  1 );
    if ( ( $industrycode =~ /^(retail|restaurant)$/ ) && ( $transflags !~ /moto/ ) ) {
      $ecomind = " ";
    } elsif ( ( $origoperation eq "forceauth" ) && ( $operation eq "postauth" ) ) {
      $ecomind = " ";
    } elsif ( ( $card_type eq "ax" ) && ( $eciind =~ /(5|6|7)/ ) && ( $transflags !~ /recinitial|recurring/ ) ) {
      $ecomind = $eciind;
    }

    elsif ( ( $cardtype eq "V" ) && ( $transflags !~ /moto|recurring|deferred/ ) ) {
      if ( ( $operation eq "postauth" ) && ( $eciind eq "5" ) ) {
        $ecomind = "5";
      } elsif ( ( $operation eq "postauth" ) && ( $eciind eq "6" ) ) {
        $ecomind = "6";
      } else {
        $ecomind = "7";
      }
    } elsif ( ( $cardtype eq "M" ) && ( $transflags !~ /moto|recurring|recinitial/ ) ) {
      $ecomind = "J";
    } else {
      $ecomind = " ";
    }
    $bd[9] = $ecomind;    # electronic commerce ind (1a) 7 for visa, K for mastercard, else spaces (1a)

    $oid = substr( $orderid, -13, 13 );

    $oid = substr( $oid . " " x 13, 0, 13 );
    $bd[10] = $oid;       # merchant reference number (13a)
    $tid = substr( $merchant_id, 8, 3 );
    $bd[11] = $tid;        # location/store # , pos 8-11 of mid (3a)
    $bd[12] = "      ";    # filler (6a)
    $bd[13] = " ";         # authorization source - space fill (1a)
    if ( ( $industrycode =~ /^(retail|restaurant)$/ ) && ( $transflags !~ /moto/ ) ) {
      $postermcap   = "2";
      $cardholderid = "1";
      if ( $magstripetrack eq "2" ) {
        $posentry = "2";
      } elsif ( $magstripetrack eq "1" ) {
        $posentry = "6";
      } else {
        $posentry = "1";
      }
    } else {
      $postermcap   = "9";
      $cardholderid = "4";
      $posentry     = "1";
    }
    $bd[14] = $postermcap;      # POS terminal capability - space fill (1a)
    $bd[15] = $posentry;        # POS entry mode - space fill (1a)
    $bd[16] = $cardholderid;    # cardholder id - space fill (1a)
    $aci = substr( $auth_code, 127, 1 );

    $aci = substr( $aci . " ", 0, 1 );
    if ( $card_type ne "vi" ) {
      $aci = " ";
    }
    if ( ( $currency eq "cad" ) || ( ( $newusdflag eq "yes" ) && ( $currency eq "usd" ) ) ) {
      $aci = " ";
    }
    $bd[17] = $aci;             # auth char ind - space fill (1a)
    $bd[18] = "0000";           # filler (4n)
    $bd[19] = "    ";           # filler (4a)
    $bd[20] = "    ";           # terminal id (unique id for each pos device) (4a)

    $myi = 0;
    foreach $var (@bd) {
      $outfilestr .= "$var";
      if ( $myi == 2 ) {
        $var =~ s/[0-9]/x/g;
      }
      $outfiletxtstr .= "$var";
      $myi++;
    }
    $outfilestr    .= "\n";
    $outfiletxtstr .= "\n";

    # don't send for new spec
    if ( ( $currency ne "cad" ) && ( ( $newusdflag ne "yes" ) || ( $currency ne "usd" ) ) ) {
      $batchreccnt++;
      $filereccnt++;

      @bd    = ();
      $bd[0] = $tcode;     # tran code (2n) 06 = sale, 07 = return
      $bd[1] = "<1";       # addendum record 1 (2n)
      $bd[2] = " " x 6;    # filler (6a)
      if ( ( $currency eq "cad" ) || ( ( $newusdflag eq "yes" ) && ( $currency eq "usd" ) ) ) {
        $bd[3] = "0" x 34;
        $bd[5] = " " x 36;    # filler (55a)
      } else {
        $bd[3] = $transamt;    # transaction amount (12n)
        $bd[4] = "   ";        # filler (3a)
        $bd[5] = " " x 55;     # filler (55a)
      }

      $myi = 0;
      foreach $var (@bd) {
        $outfilestr    .= "$var";
        $outfiletxtstr .= "$var";
        $myi++;
      }
      $outfilestr    .= "\n";
      $outfiletxtstr .= "\n";
    }

    if ( ( $operation eq "postauth" ) && ( $card_type eq "ax" ) && ( $origoperation ne "forceauth" ) ) {
      $batchreccnt++;
      $filereccnt++;

      @bd    = ();
      $bd[0] = $tcode;    # tran code (2n) 06 = sale, 07 = return
      $bd[1] = "<4";      # addendum record 1 (2n)

      my $posdata = substr( $auth_code, 105, 12 );
      $posdata = substr( $posdata . " " x 12, 0, 12 );
      $bd[2] = $posdata;    # pos entry (12a)
      my $transid = substr( $auth_code, 6, 15 );
      $transid = substr( $transid . " " x 15, 0, 15 );
      $bd[3] = $transid;    # transaction id (15a)
      my $servicecode = substr( $auth_code, 236, 6 );
      $servicecode = substr( $servicecode . " " x 3, 0, 3 );
      $bd[4] = $servicecode;    # service code from magstripe (3a)
      $bd[5] = " " x 46;        # filler (46a)

      $myi = 0;
      foreach $var (@bd) {
        $outfilestr    .= "$var";
        $outfiletxtstr .= "$var";
        $myi++;
      }
      $outfilestr    .= "\n";
      $outfiletxtstr .= "\n";
    }

    $cashbackamt = substr( $auth_code, 120, 7 );
    $cashbackamt =~ s/ //g;
    my $printstr = "cashbackamt: $cashbackamt\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

    $transid = substr( $auth_code, 6, 15 );
    $transid =~ s/ //g;
    if (
      (    ( $currency eq "usd" )
        && ( $operation eq "postauth" )
        && ( $card_type eq "ds" )
        && ( $origoperation ne "forceauth" )
        && ( ( ( $dsfullservice ne "yes" ) && ( $transid ne "" ) ) || ( $cashbackamt > 0 ) )
      )
      || ( ( $currency ne "usd" )
        && ( $operation eq "postauth" )
        && ( $origcardtype =~ /(ds|dc)/ )
        && ( $origoperation ne "forceauth" )
        && ( ( ( $dsfullservice ne "yes" ) && ( $transid ne "" ) ) || ( $cashbackamt > 0 ) ) )
      ) {
      $batchreccnt++;
      $filereccnt++;

      @bd    = ();
      $bd[0] = $tcode;    # tran code (2n) 06 = sale, 07 = return
      $bd[1] = "<5";      # addendum record 1 (2n)

      $cashbackamt = substr( "0" x 12 . $cashbackamt, -12, 12 );
      $bd[2] = $cashbackamt;    # filler (12a) US only

      $magstripetrack = substr( $auth_code, 25,  1 );
      $dsposentry     = substr( $auth_code, 248, 3 );
      $dsposentry =~ s/ //g;
      $posentry = substr( $dsposentry . "  ", 0, 2 );
      $bd[3] = $posentry;       # pos entry (2a)
      $pinentry = substr( $dsposentry,     2, 1 );
      $pinentry = substr( $pinentry . "0", 0, 1 );
      $bd[4] = $pinentry;       # pin entry (1a)

      $dstrace = substr( $auth_code, 242, 6 );
      $dstrace =~ s/ //g;
      $dstrace = substr( $dstrace . "0" x 6, 0, 6 );
      $bd[5] = $dstrace;        # trace audit number (6a)

      $transid = substr( $transid . " " x 15, 0, 15 );
      $bd[6] = $transid;        # trans id (15a)

      $dsrespcode = substr( $auth_code, 290, 2 );
      $dsrespcode =~ s/ //g;
      $dsrespcode = substr( $dsrespcode . " " x 2, 0, 2 );
      $bd[7]  = $dsrespcode;    # auth resp code (2a)
      $bd[8]  = " " x 1;        # avs response (1a)
      $bd[9]  = "0" x 13;       # auth amount (13a)
      $bd[10] = " " x 6;        # local trans time (6a)
      $bd[11] = " " x 6;        # processing code (6a)
      $bd[12] = "0" x 8;        # local trans date (8a)
      $bd[13] = " " x 3;        # service code (3a)
      $bd[14] = " ";            # filler (1a)
      my $printstr = "magstripetrack: $magstripetrack\n";
      $printstr .= "posentry: $posentry\n";
      $printstr .= "transid: $transid\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

      $myi = 0;
      foreach $var (@bd) {
        $outfilestr    .= "$var";
        $outfiletxtstr .= "$var";
        $myi++;
      }
      $outfilestr    .= "\n";
      $outfiletxtstr .= "\n";
    }

    # mobile and installment record
    if ( $transflags =~ /install/ ) {
      $batchreccnt++;
      $filereccnt++;

      @bd         = ();
      $bd[0]      = $tcode;                         # tran code (2n) 06 = sale, 07 = return
      $bd[1]      = "<7";                           # addendum record 1 (2n)
      $bd[2]      = "000000000";                    # tax (9n)
      $bd[3]      = " ";                            # mobile ind space fill (1a)
      $bd[4]      = "1";                            # installment ind space fill (1a)
      $installtot = substr( $auth_code, 103, 2 );
      $bd[5]      = "$installtot";                  # installment number (2a)
      $bd[6]      = " " x 63;                       # filler (63a)

      $myi = 0;
      foreach $var (@bd) {
        $outfilestr    .= "$var";
        $outfiletxtstr .= "$var";
        $myi++;
      }
      $outfilestr    .= "\n";
      $outfiletxtstr .= "\n";
    }

    if ( $operation eq "postauth" ) {
      $batchtotalamt = $batchtotalamt + bint($transamt);
      $batchtotalcnt = $batchtotalcnt + 1;
      $filetotalamt  = $filetotalamt + bint($transamt);
      $filetotalcnt  = $filetotalcnt + 1;
    } else {
      $batchtotalamt = $batchtotalamt - bint($transamt);
      $batchtotalcnt = $batchtotalcnt + 1;
      $filetotalamt  = $filetotalamt - bint($transamt);
      $filetotalcnt  = $filetotalcnt + 1;
    }

    if ( ( $username eq "cmg1" ) && ( $transseqnum >= 2500 ) ) {
      &batchtrailer();
      $batch_flag = 1;
    } elsif ( ( $username eq "cmg2" ) && ( $transseqnum >= 2500 ) ) {
      &batchtrailer();
      $batch_flag = 1;
    } elsif ( $transseqnum >= 1998 ) {
      &batchtrailer();
      $batch_flag = 1;
    }

    if ( $batchcount >= 1998 ) {
      &filetrailer();
      $file_flag = 1;
    }

    $banknumold     = $banknum;
    $currencyold    = $currency;
    $usernameold    = $username;
    $merchant_idold = $merchant_id;
    $batchidold     = "$time$summaryid";
    my $printstr = "usernameold: $usernameold\n";
    $printstr .= "batchidold: $batchidold\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
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

unlink "/home/pay1/batchfiles/$devprod/fdmsintl/batchfile.txt";

umask 0033;
$batchfilestr = "";
&procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "genfiles$group.txt", "write", "", $batchfilestr );

$mytime = gmtime( time() );
umask 0077;
$outfilestr = "";
$outfilestr .= "\n\n$mytime\n";
$outfilestr .= "filecount: $filecount\n";
&procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplogtest.txt", "append", "", $outfilestr );

umask 0077;
$outfilestr = "";
$outfilestr .= "before putfiles\n";
&procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "", $outfilestr );

if (1) {
  if ( ( $filecount > 0 ) && ( $filecount < 80 ) ) {
    for ( $myi = 0 ; $myi <= ( $filecount + 15 ) ; $myi++ ) {
      umask 0077;
      $mytime     = gmtime( time() );
      $outfilestr = "";
      $outfilestr .= "$mytime before putfiles\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "", $outfilestr );
      system("/home/pay1/batchfiles/$devprodpl/fdmsintl/putfiles.pl");
      &miscutils::mysleep(60);
      umask 0077;
      $mytime     = gmtime( time() );
      $outfilestr = "";
      $outfilestr .= "$mytime before getfiles\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "", $outfilestr );
      system("/home/pay1/batchfiles/$devprodpl/fdmsintl/getfiles.pl");
      umask 0077;
      $mytime     = gmtime( time() );
      $outfilestr = "";
      $outfilestr .= "$mytime after getfiles\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "", $outfilestr );

    }
  }
}

exit;

sub batchheader {
  $batch_flag = 0;

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

  $batchtotalamt = Math::BigInt->new("0");
  $batchretcnt   = 0;
  $batchretamt   = 0;
}

sub batchtrailer {
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

  $batchretcnt = substr( "0000000" . $batchretcnt,     -6,  6 );
  $batchretamt = substr( "00000000000" . $batchretamt, -11, 11 );
  $batchreccnt = substr( "0000000" . $batchreccnt,     -7,  7 );

  if ( $batchtotalamt >= 0 ) {
    $tcode = "70";
  } else {
    $tcode         = "71";
    $batchtotalamt = bint(0) - $batchtotalamt;
  }

  @bt    = ();
  $bt[0] = $tcode;                                        # tran code - 70 = debit summary, 71 = credit summary (2n)
  $bt[1] = " ";                                           # filler (1a)
  $mid   = substr( $merchant_idold . " " x 11, 0, 11 );
  $bt[2] = $mid;                                          # merchant number (11n)
  if ( ( $currency eq "cad" ) || ( ( $newusdflag eq "yes" ) && ( $currency eq "usd" ) ) ) {
    $bt[3] = " " x 16;                                    # filler (14a)
    $batchtotalamt = substr( "0" x 10 . $batchtotalamt, -10, 10 );
    $bt[6] = $batchtotalamt;                              # net sales amount, sales - returns(12n)
  } else {
    $bt[3] = " " x 14;                                    # filler (14a)
    $batchtotalamt = substr( "0" x 12 . $batchtotalamt, -12, 12 );
    $bt[6] = $batchtotalamt;                              # net sales amount, sales - returns(12n)
  }
  $bt[7] = " " x 40;                                      # filler (40a)

  foreach $var (@bt) {
    $outfilestr    .= "$var";
    $outfiletxtstr .= "$var";
  }
  $outfilestr    .= "\n";
  $outfiletxtstr .= "\n";

  if ( $tcode eq "71" ) {
    $batchtotalamtstr = "-" . $batchtotalamt;
  } else {
    $batchtotalamtstr = $batchtotalamt;
  }

  # xxxx
  my $dbquerystr = <<"dbEOM";
        update batchfilesfdmsi
        set count=?,amount=?
        where batchnum=?
        and username=?
        and (amount is NULL or amount='')
dbEOM
  my @dbvalues = ( "$batchtotalcnt", "$batchtotalamtstr", "$batchidold", "$usernameold" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

}

sub bint { Math::BigInt->new(shift); }

sub fileheader {
  my $printstr = "in fileheader\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  $batchcount = 0;
  $filecount++;

  $file_flag = 0;

  ( $d1, $d2, $ttime ) = &miscutils::genorderid();
  if ( $ttime eq "$filename" ) {
    &miscutils::mysleep(2.0);
    ( $d1, $d2, $ttime ) = &miscutils::genorderid();
  }
  $filename = "$ttime";

  umask 0077;
  $outfilestr    = "";
  $outfiletxtstr = "";

  $customerid = substr( $customerid . " " x 10, 0, 10 );

  $filesalescnt = 0;
  $filesalesamt = 0;
  $fileretcnt   = 0;
  $fileretamt   = 0;
  $filereccnt   = 1;

  $filetotalamt = Math::BigInt->new("0");
  $recseqnum    = 1;
  $recseqnum    = substr( "0000000" . $recseqnum, -7, 7 );
  $createdate   = substr( $trans_time, 4, 4 ) . substr( $trans_time, 2, 2 );
  $createdate   = substr( $createdate . " " x 6, 0, 6 );
  $createtime   = substr( $trans_time, 8, 6 );
  $createtime   = substr( $createtime . " " x 6, 0, 6 );
  $fileid       = substr( $fileid . " " x 20, 0, 20 );

  @fh = ();
  my $printstr = "aaaa $currency $newusdflag\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  if ( ( $currency eq "cad" ) || ( ( $newusdflag eq "yes" ) && ( $currency eq "usd" ) ) ) {
    if ( $currency eq "cad" ) {
      $fileext = "RCDMPLG2";
    } else {
      $fileext = "RCDMPLG3";
    }

    my $printstr = "bbbb $currency $newusdflag\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
    $fh[0] = "00";    # tran code (2n)
    $fh[1] = " ";     # filler (1a)
    $merchantname = substr( 'PLUG & PAY' . " " x 16, 0, 16 );
    $fh[4] = $merchantname;    # merchant name (16a) must be upper case
    $fh[5] = " ";              # filler (1a)
    $createdate = substr( $today, 4, 4 );
    $fh[6]  = $createdate;     # creation date - MMDD (4n)
    $fh[7]  = " " x 48;        # filler (47a)
                               # xxxx
                               #$fh[9] = "TEST";		# test/prod identifier - spaces = production, Test = test
    $fh[9]  = "    ";          # test/prod identifier - spaces = production, Test = test
    $fh[10] = "    ";          # filler (4a)
  } else {
    $fileext = "RCDMPLGS";

    $fh[0] = "00";             # tran code (2n)
    $fh[1] = " ";              # filler (1a)
    $fh[2] = "+";              # bank identifier (1a)
    $banknum = substr( "0" x 5 . $banknum, -5, 5 );
    $fh[3] = $banknum;          # bank number (5n)
    $bankname = "PLUG & PAY";
    $bankname = substr( $bankname . " " x 10, 0, 10 );
    $fh[4] = $bankname;         # bank name (10a) must be   Plug & Pay
    $fh[5] = " ";               # filler (1a)
    $createdate = substr( $today, 4, 4 );
    $fh[6] = $createdate;       # creation date - MMDD (4n)
    $fh[7] = " " x 47;          # filler (47a)

    if ( $currency eq "usd" ) {
      $currencyind = " ";
    } else {
      $currencyind = "F";
    }
    $fh[8]  = $currencyind;     # currency indicator (1a)
                                # xxxx
                                #$fh[9] = "TEST";		# test/prod identifier - spaces = production, Test = test
    $fh[9]  = "    ";           # test/prod identifier - spaces = production, Test = test
    $fh[10] = "C025";           # file type (4a)
  }

  foreach $var (@fh) {
    $outfilestr    .= "$var";
    $outfiletxtstr .= "$var";
  }
  $outfilestr    .= "\n";
  $outfiletxtstr .= "\n";

}

sub filetrailer {

  $filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

  $filesalescnt = substr( "0000000" . $filesalescnt,     -7,  7 );
  $fileretcnt   = substr( "0000000" . $fileretcnt,       -7,  7 );
  $fileretamt   = substr( "0000000000000" . $fileretamt, -13, 13 );

  if ( $filetotalamt >= 0 ) {
    $tcode = "80";
  } else {
    $tcode        = "85";
    $filetotalamt = bint(0) - $filetotalamt;
  }

  @ft = ();
  $ft[0] = $tcode;    # tran code - 80 = debit batch, 85 = credit batch (2a)
  if ( ( $currency eq "cad" ) || ( ( $newusdflag eq "yes" ) && ( $currency eq "usd" ) ) ) {
    $ft[1] = " " x 37;    # filler (37a)
    $filetotalamt = substr( "0" x 10 . $filetotalamt, -10, 10 );
    $ft[2] = $filetotalamt;    # file total amount - no decimal (10n)
    $filereccnt = substr( "0000000" . $filereccnt, -7, 7 );
    $ft[4] = $filereccnt;      # file record count (7n)
  } else {
    $ft[1] = " " x 32;         # filler (32a)
    $filetotalamt = substr( "0" x 15 . $filetotalamt, -15, 15 );
    $ft[2] = $filetotalamt;    # file total amount - no decimal (15n)
    $filereccnt = substr( "0000000" . $filereccnt, -7, 7 );
    $ft[4] = $filereccnt;      # file record count (6n)
  }
  $ft[5] = " " x 24;           # filler (24a)

  foreach $var (@ft) {
    $outfilestr    .= "$var";
    $outfiletxtstr .= "$var";
  }
  $outfilestr    .= "\n";
  $outfiletxtstr .= "\n";

  my $filestatus = &procutils::fileencwrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear", "$filename", "write", "", $outfilestr );
  print "fileencwritestatus: $filestatus\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear", "$filename.txt", "write", "", $outfiletxtstr );
}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  my $printstr = "origtime: $origtime $timezone1\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $printstr = "The $times2 Sunday of month $month2 happens on the $mday2\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  my $printstr = "newtime: $newtime $timezone2\n\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  return $newtime;

}

sub pidcheck {
  my $chkline = &procutils::fileread( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "pid$group.txt" );
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    $printstr .= "$pidline\n";
    $printstr .= "$chkline\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

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

