#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use procutils;
use smpsutils;
use isotables;
use PlugNPay::Legacy::Genfiles;
use PlugNPay::Logging::DataLog;

$devprod     = "prod";
$devprodlogs = "logs";

# fdms emv version 1.2

my $group = $ARGV[0];
if ( $group eq "" ) {
  $group = "0";
}
my $printstr = "group: $group\n";
&procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprodlogs/elavon/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'elavon/genfilesfile.pl $group'`;
if ( $cnt > 1 ) {
  my $printstr = "genfilesfile.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  exit;
}

$mytime  = time();
$machine = `uname -n`;
$pid     = $$;

chop $machine;
$outfilestr = "";
$pidline    = "$mytime $$ $machine";
$outfilestr .= "$pidline\n";
&procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon", "pidfile$group.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my @infilestrarray = &procutils::fileread( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon", "pidfile$group.txt" );
$chkline = $infilestrarray[0];
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfilesfile.pl $group already running, pid alterred by another program, exiting...\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "$pidline\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "$chkline\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: elavon - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfilesfile.pl $group already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

# batch cutoff times: 2:30am, 8am, 11:15am, 5pm M-F     12pm Sat   12pm, 7pm Sun

#$checkstring = " and t.username='aaaa'";
#$checkstring = " and t.username in ('aaaa','aaaa')";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

#my ($sec,$min,$hour,$day1,$month,$year,$wday,$yday,$isdst) = gmtime(time());
#my ($sec,$min,$hour,$day2,$month,$year,$wday,$yday,$isdst) = localtime(time());
#if ($day1 != $day2) {
#  print "GMT day ($day1) and local day ($day2) do not match, try again after midnight local\n";
#}

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

if ( !-e "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprodlogs/elavon/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprodlogs/elavon/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprodlogs/elavon/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprodlogs/elavon/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprodlogs/elavon/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: elavon - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/elavon/$fileyear.\n\n";
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
        and o.processor='elavon'
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
$mycnt = 0;
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  $mycnt++;

  my $printstr = "aaaa $user  $usercount  $usertdate\n";
  print "$printstr\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  $userarray{"$user"}     = 1;
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

#if ($mycnt > 1) {
#  open(MAILTMP,"| /usr/lib/sendmail -t");
#  print MAILTMP "To: cprice\@plugnpay.com\n";
#  print MAILTMP "From: dcprice\@plugnpay.com\n";
#  print MAILTMP "Subject: elavon - more than one batch\n";
#  print MAILTMP "\n";
#  print MAILTMP "There are more than one elavon batches.\n";
#  close MAILTMP;
#}

foreach $username ( sort keys %userarray ) {
  ( $d1, $d2, $time ) = &miscutils::genorderid();

  if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprodlogs/elavon/stopgenfiles.txt" ) ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "stopgenfiles\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "stopgenfiles\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

    &procutils::flagwrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon", "batchfilefile.txt", "unlink", "", "" );
    last;
  }

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,currency,company,city,state,zip,tel,country,features
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $status, $mcurrency, $mcompany, $mcity, $mstate, $mzip, $mphone, $mcountry, $features ) =
    &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $mcurrency eq "" ) {
    $mcurrency = "usd";
  }

  if ( $status ne "live" ) {
    next;
  }

  my $dbquerystr = <<"dbEOM";
        select industrycode,batchgroup,banknum,requestorid,contactless
        from elavon
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $industrycode, $batchgroup, $banknum, $tokenreqid, $ctlsflag ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $genfiles = new PlugNPay::Legacy::Genfiles();
  my $batchGroupStatus = $genfiles->batchGroupMatch($group,$batchgroup);

  if (!$batchGroupStatus) {
    my $error = $batchGroupStatus->getError();
    my $dataLog = new PlugNPay::Logging::DataLog({'collection' => 'elavon-genfilesfile-perl'});
    $dataLog->log({
      'username' => $username,
      'error' => $error
    });

    next;
  }

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon", "genfilesfile$group.txt", "write", "", $batchfilestr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon", "batchfilefile.txt", "write", "", $batchfilestr );

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
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

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
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username $usercountarray{$username} $starttransdate $mcurrency\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username  sweeptime: $sweeptime  settletime: $settletime\n";
  $logfilestr .= "$features\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  print "aaaa $username $onemonthsago\n";

  my $dbquerystr = <<"dbEOM";
        select o.orderid,o.trans_date,substr(o.auth_code,172,25),substr(o.auth_code,285,1),o.amount,o.transflags
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
        and o.processor='elavon'
        and (o.voidstatus is NULL or o.voidstatus ='')
        and (o.accttype is NULL or o.accttype ='' or o.accttype='credit')
dbEOM
  my @dbvalues = ( "$onemonthsago", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  %orderidarray      = ();
  %starttdateinarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 6 ) {
    ( $orderid, $trans_date, $marketdata, $dccoptflag, $amount, $transflags ) = @sthtransvalarray[ $vali .. $vali + 5 ];
    $marketdata = "";

    $currency = substr( $amount, 0, 3 );

    if ( $dccoptflag eq "N" ) {
      $dccoptflag = "Y";    # do not use dccoptflag in any messages
    }
    if ( $transflags =~ /multi/ ) {
      $dccoptflag = "Y";    # do not use dccoptflag in any messages
    }

    $marketdata =~ tr/a-z/A-Z/;
    $orderidarray{ "$marketdata" . "jjjj" . $dccoptflag . "jjjj" . "$currency" . "jjjj" . $orderid } = 1;
    $starttdateinarray{"$username $trans_date"} = 1;

    my $printstr = "$orderid\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  }

  foreach my $keya ( sort keys %orderidarray ) {
    ( $marketdata, $dccoptflag, $currency, $orderid ) = split( /jjjj/, $keya, 4 );

    print "$marketdata  $dccoptflag  $currency  $orderid\n";

    #select operation,trans_date,trans_time,enccardnumber,length,amount,auth_code,avs,finalstatus,transflags,card_exp,cvvresp,refnumber
    #from trans_log
    #where orderid='$orderid'
    #and username='$username'
    #and trans_date>='$onemonthsago'
    #and (accttype is NULL or accttype='' or accttype='credit')
    #and operation IN ('postauth','return','void')
    #and finalstatus NOT IN ('problem')
    #and (duplicate IS NULL or duplicate ='')
    #order by orderid,trans_time DESC
    my $dbquerystr = <<"dbEOM";
          select lastop,trans_date,lastoptime,enccardnumber,length,amount,auth_code,avs,lastopstatus,transflags,card_exp,cvvresp,refnumber,
                 authtime,authstatus,forceauthtime,forceauthstatus,origamount,reauthstatus,cardtype,publisheremail
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
      $cvvresp,   $refnumber,  $authtime,   $authstatus,    $forceauthtime, $forceauthstatus, $origamount, $reauthstatus, $card_type,   $parvalue
    )
      = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprodlogs/elavon/stopgenfiles.txt" ) ) {
      &procutils::flagwrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon", "batchfilefile.txt", "unlink", "", "" );
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
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "elavon", $enccardnumber );

    if ( ( ( $username ne $usernameold ) || ( $currency ne $currencyold ) || ( $marketdata ne $marketdataold ) || ( $dccoptflag ne $dccoptflagold ) ) && ( $batch_flag == 0 ) ) {
      &batchtrailer();
      $batch_flag = 1;
    }

    #if ((($banknum ne $banknumold) || ($currency ne $currencyold)) && ($file_flag == 0)) {
    #  &filetrailer();
    #  $file_flag = 1;
    #}

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

    #$filereccnt++;

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    #print "$cardnumber\n";

    if ( $card_type eq "" ) {
      $card_type = &smpsutils::checkcard($cardnumber);
    }
    if ( $card_type =~ /(dc|jc)/ ) {
      $card_type = 'ds';
    }

    &batchdetail();

    #if ($transseqnum >= 6) {}
    if ( $batchtotalcnt >= 998 ) {
      &batchtrailer();
      $batch_flag = 1;
    }

    if ( $batchcount >= 998 ) {
      &filetrailer();
      $file_flag = 1;
    }

    $currencyold    = $currency;
    $usernameold    = $username;
    $merchant_idold = $merchant_id;
    $batchidold     = "$time$summaryid";
    $marketdataold  = $marketdata;
    $dccoptflagold  = $dccoptflag;

    #print "usernameold: $usernameold\n";
    #print "batchidold: $batchidold\n";
  }
}

if ( $batch_flag == 0 ) {
  print "bbbb\n";
  &batchtrailer();
  $batch_flag = 1;
}

if ( $file_flag == 0 ) {
  &filetrailer();
  $file_flag = 1;
}

&procutils::flagwrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon", "batchfilefile.txt", "unlink", "", "" );

umask 0033;
$batchfilestr = "";
&procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon", "genfilesfile$group.txt", "write", "", $batchfilestr );

$mytime = gmtime( time() );
umask 0077;
$outfilestr = "";
$outfilestr .= "\n\n$mytime\n";
&procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon", "ftplog.txt", "append", "", $outfilestr );

system("/home/pay1/batchfiles/$devprod/elavon/putfilesfile.pl");

#if (($filecount > 0) && ($filecount < 10)) {
#  for ($myi=0; $myi<=$filecount; $myi++) {

#for ($myi=0; $myi<=1; $myi++) {
#  system("/home/pay1/batchfiles/$devprodlogs/elavon/putfiles.pl >> /home/pay1/batchfiles/$devprodlogs/elavon/ftplog.txt 2>\&1");
#  &miscutils::mysleep(120);
#  system("/home/pay1/batchfiles/$devprodlogs/elavon/getfiles.pl >> /home/pay1/batchfiles/$devprodlogs/elavon/ftplog.txt 2>\&1");
#  &miscutils::mysleep(20);
#}

#}

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
      &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      return;
    }
  }

  $transseqnum++;
  $transseqnum = substr( "0" x 6 . $transseqnum, -6, 6 );

  $addendum = 0;

  $transtime = substr( $trans_time, 8, 6 );

  #$transamt = substr($amount,4);
  ( $transcurr, $transamt ) = split( / /, $amount );
  $transcurr =~ tr/a-z/A-Z/;
  $transexp = $isotables::currencyUSD2{$transcurr};
  $transamt = sprintf( "%010d", ( ( $transamt * ( 10**$transexp ) ) + .0001 ) );

  #$transamt = sprintf("%010d",(($transamt * 100) + .0001));

  $clen = length($cardnumber);
  $cabbrev = substr( $cardnumber, 0, 4 );

  $tcode     = substr( $tcode . " " x 2,     0, 2 );
  $transtime = substr( $transtime . " " x 6, 0, 6 );

  #$authsrc = substr($authsrc . " " x 1,0,1);
  $authresp = substr( $authresp . " " x 2, 0, 2 );
  $avs_code = substr( $avs_code . " " x 1, 0, 1 );

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

  $commcardtype = substr( $auth_code, 24, 1 );
  $commcardtype =~ s/ //g;

  $magstripetrack = substr( $auth_code, 22, 1 );

  $filereccnt++;
  @bd = ();
  $bd[0] = "DTR";    # record type (3a)

  my $tcode = "S";
  if ( $operation eq "return" ) {
    $tcode = "R";
  }
  $bd[1] = $tcode;    # transaction code (1a)

  my $cardtype = $card_type;
  $cardtype =~ tr/a-z/A-Z/;
  if ( $card_type eq "ma" ) {
    $cardtype = "MC";
  } elsif ( $card_type eq "jc" ) {
    $cardtype = "JB";
  } elsif ( ( $card_type eq "ds" ) && ( $cardnumber =~ /^(2|6)/ ) ) {
    $cardtype = "UP";
  }
  $bd[2] = $cardtype;    # card type (2a)
  $cardnumber = substr( $cardnumber . " " x 20, 0, 20 );
  $bd[3] = $cardnumber;    # card number (20a)
  $expdate = substr( $exp, 0, 2 ) . substr( $exp, 3, 2 );
  $bd[4] = $expdate;       # expiration date (4n) MMYY

  my $amt = substr( $amount, 4 );
  $amt = sprintf( "%d", ( $amt * 100 ) + .0001 );
  $amt = substr( "0" x 10 . $amt, -10, 10 );
  $bd[5] = $amt;           # settlement amount (10n)
  $transamt = $amt;

  if ( $operation eq "postauth" ) {
    $trandate = "20" . substr( $auth_code, 11, 2 ) . substr( $auth_code, 7, 4 );
    $trantime = substr( $auth_code, 13, 6 );
  } elsif ( $operation eq "return" ) {
    $trandate = substr( $trans_time, 0, 8 );    # gmt?
    $trantime = substr( $trans_time, 8, 6 );
  }
  $bd[6] = $trandate;                           # authorization date (8n) YYYYMMDD
  $bd[7] = $trantime;                           # authorization time (6n) HHMMSS

  $authcode = substr( $auth_code,           0, 6 );
  $authcode = substr( $auth_code . " " x 6, 0, 6 );
  $bd[8] = $authcode;                           # approval code (6a)

  my $posentry = "01";
  if ( $transflags =~ /(mit|cit|recur|install)/ ) {
    $posentry = "10";
  } elsif ( ( $card_type eq "mc" ) && ( ( $industrycode !~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) ) {
    $posentry = "81";
  } elsif ( $magstripetrack =~ /^(0|1|2)$/ ) {
    $posentry = "02";
  }
  $bd[9] = $posentry;                           # pos entry mode (2a)

  $acctsrc     = substr( $auth_code,             19,  1 );
  $acctsrc     = substr( $acctsrc . " ",         0,   1 );
  $authsrc     = substr( $auth_code,             20,  1 );
  $authsrc     = substr( $authsrc . " ",         0,   1 );
  $captrancode = substr( $auth_code,             6,   1 );
  $captrancode = substr( $captrancode . " ",     0,   1 );
  $servicecode = substr( $auth_code,             121, 3 );
  $servicecode = substr( $servicecode . " " x 3, 0,   3 );
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

  my $cardid = "4";    # moto ecom
  if ( ( $industrycode =~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $cardid = "1";
  }

  $bd[10] = $authsrc;    # auth source code (1a) 0-5   E force   9 return
  $bd[11] = $cardid;     # cardholder id method (1a)

  my $cardpres = "N";
  if ( ( $industrycode =~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $cardpres = "Y";
  }
  $bd[12] = $cardpres;    # card present indicator (1a)

  #$transseqnum = substr($auth_code,110,11);
  $transseqnum = substr( $auth_code, 55, 30 );
  $transseqnum =~ s/ //g;
  if ( ( $operation eq "postauth" ) && ( $forceauthtime ne "" ) ) {
    $transseqnum = "0" x 30;
  } elsif ( $transseqnum eq "" ) {

    #$transseqnum = &smpsutils::gettransid($username,"elavon",$orderid);
    $transseqnum = " " x 30;
  }
  $transseqnum = substr( "0" x 11 . $transseqnum, -11, 11 );
  $bd[13] = $transseqnum;    # reference number (11n)

  my $ps2000   = $refnumber;
  my $pos1     = substr( $refnumber, 0, 1 );     # vi aci, mc M, di D, ax A, up U
  my $pos2_16  = substr( $refnumber, 1, 15 );    # vi transid 15, mc banknetrefnum 9 spaces, ax transid 15, di nrid 15, up stan date/timesubstr
  my $ops17_20 = substr( $refnumber, 16, 4 );    # vi validcode, mc banknetdate, di condcode, ax spaces, up timesubstr/juliandate
  my $alptic   = substr( $refnumber, 20, 2 );    # vi alp, mc tic, di spaces, ax spaces, up spaces

  my $aci = $pos1;
  if ( $card_type eq "mc" ) {
    $aci = "M";
  } elsif ( $card_type eq "ax" ) {
    $aci = "A";
  } elsif ( $card_type eq "ds" ) {
    $aci = "D";
  } elsif ( ( $card_type eq "ds" ) && ( $cardnumber =~ /^(2|6)/ ) ) {
    $aci = "U";
  }
  $aci = substr( $aci . " ", 0, 1 );
  $bd[14] = $aci;    # visa aci (1a)

  $pos2_16 = substr( $pos2_16 . " " x 15, 0, 15 );
  $bd[15] = $pos2_16;    # visa transactionid 15, mc banknet reference number 9 spaces, amex transaction id 15, discover nrid 15, union pay stan date/time 6 9 (15a)
  $pos17_20 = substr( $pos17_20 . " " x 4, 0, 4 );
  $bd[16] = $pos17_20;    # visa validation code, mc banknet reference date MMDD, discover transaction data condition code, union paydata pos 10 of date/time julian date(4a)

  my $origeci   = substr( $auth_code, 125, 1 );
  my $cavvascii = substr( $auth_code, 127, 40 );
  $cavvascii =~ s/ //g;
  my $eci = "1";          # single transaction
  if ( ( $card_type eq "ax" ) && ( $origeci eq "1" ) ) {
    $eci = "5";
  } elsif ( ( $card_type eq "ax" ) && ( $origeci eq "2" ) ) {
    $eci = "6";
  } elsif ( ( $card_type eq "ax" ) && ( ( $industrycode !~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) ) {
    $eci = "7";
  } elsif ( $card_type eq "ax" ) {
    $eci = " ";
  } elsif ( $transflags =~ /install/ ) {
    $eci = "3";
  } elsif ( $transflags =~ /recur/ ) {
    $eci = "2";
  } elsif ( $transflags =~ /moto/ ) {
    $eci = " ";
  } elsif ( $origeci eq "1" ) {
    $eci = "5";
  } elsif ( $origeci eq "2" ) {
    $eci = "6";
  } elsif ( ( $industrycode !~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $eci = "7";
  }
  $bd[17] = $eci;    # mail/phone/ecommerce ind (1a)

  my $cat = " ";
  if ( $card_type eq "vi" ) {
  } elsif ( ( $card_type eq "mc" ) && ( $industrycode !~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $cat = "6";
  } elsif ( $card_type eq "mc" ) {
    $cat = "0";
  }
  $bd[18] = $cat;    # cardholder activated terminal (1a)

  my $poscap = "1";  # ecommerce
                     #if ($fdmsnorth::magstripetrack =~ /(0|1|2)/) {
                     #  $poscap = "2";
                     #}
  if ( $industrycode =~ /(retail|restaurant)/ ) {
    $poscap = "2";
  } elsif ( $transflags =~ /moto/ ) {
    $poscap = "9";
  }
  $bd[19] = $poscap;    # pos capability (1a)

  my $pass = substr( $auth_code, 108, 2 );
  $pass = substr( $pass . "  ", 0, 2 );
  $bd[20] = $pass;      # response code (2a)

  my ( $curr, $transamount ) = split( / /, $amount );
  $curr =~ tr/a-z/A-Z/;
  $bd[21] = $curr;      # authorization currency type (3a) USD, CAD

  if ( $origamount ne "" ) {
    $amt = sprintf( "%d", ( substr( $origamount, 4 ) * 100 ) + .0001 );
  } else {
    $amt = sprintf( "%d", ( substr( $amount, 4 ) * 100 ) + .0001 );
  }
  $amt = substr( "0" x 10 . $amt, -10, 10 );
  $bd[22] = $amt;       # original authorization amount (10n)

  $avs_code = substr( $avs_code . " ", 0, 1 );
  $bd[23] = $avs_code;    # avs result (1a)
  $bd[24] = "1";          # purchase identifier format code (1a)
  $bd[25] = "  ";         # debit network id (2a)
  $bd[26] = "    ";       # debit settlement date (4a) MMDD

  my $catcode = substr( $categorycode . " " x 4, 0, 4 );
  $catcode = "5999";                         # xxxx
  $bd[27]  = $catcode;                       # merchant category code (4n) xxxx
  $bd[28]  = "    ";                         # item number (4a)
  $msdi    = substr( $auth_code, 124, 1 );
  $msdi    = substr( $msdi . " ", 0, 1 );
  $msdi =~ tr/0123456789/ HNMTEABGJ/;
  if ( $msdi eq "" ) {
    $msdi = " ";
  }
  $bd[29] = $msdi;                           # msdi indicator (1a)

  #$cavvascii = substr($auth_code,127,40);
  #$cavvascii =~ s/ //g;
  $ucafind = substr( $auth_code,     126, 1 );
  $ucafind = substr( $ucafind . " ", 0,   1 );
  $bd[30] = $ucafind;    # ucaf indicator (1a)

  my $surcharge = substr( $auth_code, 198, 8 );
  $surcharge = substr( "0" x 8 . $surcharge, -8, 8 );
  $bd[31] = $surcharge;    # surcharge amount (8n)

  $bd[32] = " " x 13;      # waybill number (13n)
  $mid = substr( $mid . " " x 15, 0, 15 );
  $bd[33] = $mid;          # card acceptor id (15a) merchant id
  $bd[34] = "    ";        # ecs charge type (4a)
  $bd[35] = "0" x 8;       # convenience fee amount (8n)

  $cvvresp = substr( $cvvresp . " ", 0, 1 );
  $bd[36] = $cvvresp;      # cvv result (1a)

  $alptic = substr( $alptic . "  ", 0, 2 );
  $bd[37] = $alptic;       # alp tic (2a) visa account level processing response code, mastercard transaction integrity class response code, spaces

  $servicecode = substr( $auth_code,             121, 3 );
  $servicecode = substr( $servicecode . " " x 3, 0,   3 );
  $bd[38] = $servicecode;    # service code (3n) from track data

  $bd[39] = "   ";           # fee program indicator (3a) fpi response code
  $bd[40] = "N";             # real time clearing indicator (1a) rtic N not a RTC transaction, Y RTC eligible

  my $compind = " ";
  if ( ( $card_type eq "mc" ) && ( $operation eq "postauth" ) ) {
    $compind = "1";
  }
  $bd[41] = $compind;        # preauth completion indicator (1a) mc 1 within timeframe, spaces

  $bd[42] = " " x 6;         # rtc acquiring bin (6n)
  $bd[43] = "0";             # debit interchange indicator (1a)

  my $tokenind = "0";
  if ( $transflags =~ /token/ ) {
    $tokenind = "1";
  }
  $bd[44] = $tokenind;       # elavon token indicator (1a) 1 yes, 0 no

  $sqiind = substr( $auth_code,    197, 1 );
  $sqiind = substr( $sqiind . " ", 0,   1 );
  $bd[45] = $sqiind;         # spend qualifier (1a) ultra high net worth cardholders

  my $ii = 0;
  foreach $var (@bd) {
    $outfilestr .= "$var";

    my $var2 = substr( $var, 0, 6 ) . "\[\[$username $orderid\]\]" . substr( $var, 26 );
    $outfile3str .= "$var2";

    my $ccardnum = substr( $var, 6, 20 );
    $ccardnum =~ s/[0-9]/x/g;
    $var = substr( $var, 0, 6 ) . $ccardnum . substr( $var, 26 );
    $outfile2str .= "$var";

    $ii++;
  }

  $outfilestr  .= "\n";
  $outfile3str .= "\n";
  $outfile2str .= "\n";

  $filereccnt++;
  @bd = ();
  $bd[0] = "DT2";    # record type (3a)

  my $cashback = substr( $auth_code, 206, 8 );
  if ( $cashback > 0 ) {
    $cashback = substr( "0" x 10 . $cashback, -10, 10 );
  } else {
    $cashback = "0" x 10;
  }
  $bd[1] = $cashback;    # cashback amount (10n)
  $bd[2] = "N";          # opt blue indicator (1a)
  $bd[3] = "0" x 15;     # opt blue se number (15n)

  my $dccinfo = substr( $auth_code, 284, 52 );
  $dccinfo =~ s/ //g;

  my $dccpotential = "N";
  if ( $dccinfo ne "" ) {
    $dccpotential = "Y";
  }
  $bd[4] = $dccpotential;    # elavon dcc potential (1a)
  $bd[5] = $dccpotential;    # scheme dcc potential (1a)

  my $amt = sprintf( "%d", ( substr( $amount, 4 ) * 100 ) + .0001 );
  $amt = substr( "0" x 10 . $amt, -10, 10 );
  $bd[6] = $amt;             # total authorized amount (10n)

  my $storedcredind = 'N';
  if ( $transflags =~ /(init|mit|cit|recur|install)/ ) {
    $storedcredind = "C";
  }
  $bd[7] = $storedcredind;    # stored credential indicator (1a)

  $bd[8] = "00";              # number of incrementals (2n)

  $seclevind = substr( $auth_code,           398, 3 );
  $seclevind = substr( $seclevind . " " x 3, 0,   3 );
  $bd[9] = $seclevind;        # eci security level indicator (3a)

  $resptokenformat = substr( $auth_code, 95, 2 );
  $resptokenformat = substr( $resptokenformat . " " x 2, 0, 2 );
  $bd[10] = $resptokenformat;    # token format (2a) from auth
  $bd[11] = "0";                 # pin entry capability (1n)
  $bd[12] = " ";                 # mobile pos acceptance device (1a)

  my $parvalue = substr( $parvalue . " " x 35, 0, 35 );
  $bd[13] = $parvalue;           # payment account reference par value (35a)

  $oardata = substr( $auth_code,          336, 60 );
  $oardata = substr( $oardata . " " x 60, 0,   60 );
  $bd[14] = $oardata;            # original authorization response data oar (60a)

  my $debtind = "N";
  if ( $transflags =~ /debt/ ) {
    $debtind = "Y";
  }
  $bd[15] = $debtind;            # debt repayment indicator (1a)

  $bd[16] = "0" x 11;            # payment facilitator id (11n)

  my $cardhpres = "5";
  if ( ( $industrycode =~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $cardhpres = "0";
  } elsif ( $transflags =~ /(recur|install|mit|cit)/ ) {
    $cardhpres = "4";
  } elsif ( $transflags =~ /mail/ ) {
    $cardhpres = "2";
  } elsif ( $transflags =~ /moto/ ) {
    $cardhpres = "3";
  }
  $bd[17] = $cardhpres;          # cardholder present indicator (1n)
  $bd[18] = " " x 41;            # reserved (41a)

  foreach $var (@bd) {
    $outfilestr  .= "$var";
    $outfile3str .= "$var";
    $outfile2str .= "$var";
  }

  $outfilestr  .= "\n";
  $outfile3str .= "\n";
  $outfile2str .= "\n";

  #$marketdata = substr($auth_code,172,25); ????
  #$marketdata =~ s/ +$//g;
  #if ((0) && ($marketdata ne "")) {
  #  @bd = ();
  #  $bd[0] = "MAA";   		# record type (3a)
  #  $marketdata = substr($auth_code,172,25);
  #  $dbacompany = substr($marketdata,0,25);
  #  $bd[1] = $dbacompany;	# merchant dba name (25a)

  #  $bd[2] = " " x 13;   		# merchant city (13a) xxxx
  #  $bd[3] = "  ";   		# merchant state (2a) xxxx

  #  $bd[4] = " " x 9;   		# merchant postal code (9a)
  #  $bd[5] = " " x 3;   		# merchant country code (3a)
  #  $bd[6] = " " x 30;   		# merchant street address (30a)
  #  my $dbaphone = substr($mphone . " " x 25,-25,25);
  #  $bd[7] = $dbaphone;   		# merchant phone (20a) xxxx
  #  $bd[8] = " " x 15;   		# sub merchant id (15a)
  #  $bd[9] = " " x 40;   		# merchant email address (40a)
  #  $bd[10] = " " x 4;   		# merchant category code (4n)
  #  $bd[11] = " " x 14;   		# sub merchant tax id (14a)
  #  $bd[12] = " " x 22;   		# reserved (22a)

  #  foreach $var (@bd) {
  #    $outfilestr .= "$var";
  #    $outfile2str .= "$var";
  #  }

  #  $outfilestr .= "\n";
  #  $outfile2str .= "\n";

  #}

  if ( ( $transflags =~ /(dcc|multi)/ ) && ( $dccinfo =~ /,/ ) ) {
    my $dccinfo = substr( $auth_code, 284, 52 );

    my ( $dccoptout, $dccamount, $dcccurrency, $dccrate, $dccexponent, $dccdate, $dcctime ) = split( /,/, $dccinfo );
    my $dccind = "";
    if ( $transflags =~ /multi/ ) {
      $dccind = "M";
    } elsif ( $dccoptout eq "Y" ) {
      $dccind = "N";
    } else {
      $dccind = "Y";
    }
    $dccamount   = substr( "0" x 12 . $dccamount,  -12, 12 );
    $dcccurrency = substr( $dcccurrency . " " x 3, 0,   3 );
    $dccind      = substr( $dccind . " " x 1,      0,   1 );
    $dccrate     = substr( "0" x 10 . $dccrate,    -10, 10 );

    $filereccnt++;
    @bd    = ();
    $bd[0] = "DCC";           # record type (3a)
    $bd[1] = " " x 6;         # reserved (6a)
    $bd[2] = $dccamount;      # transaction amount in cardholders currency (12n)
    $bd[3] = $dcccurrency;    # cardholder currency value (3a) USD
    $bd[4] = $dccind;         # currency indicator (1a) D dcc, M multicurrency
    $bd[5] = " " x 5;         # reserved (5a)
    if ( $dccrate eq "0000000000" ) {
      $dccrate = " " x 10;
    }
    $bd[6] = $dccrate;        # conversion rate (10n) 5 decimal places implied 1099  109900000  87.5638 8756380
    $bd[7] = " " x 160;       # reserved (160a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile3str .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile3str .= "\n";
    $outfile2str .= "\n";

  }

  if ( ( $transflags =~ /moto/ ) || ( $industrycode !~ /^(retail|restaurant)$/ ) ) {

    # direct marketing card not present addendum
    $filereccnt++;
    @bd = ();
    $bd[0] = "DMA";    # record type (3a)

    #$porderid = substr($auth_code,32,17);
    $invoicenum = substr( $auth_code, 255, 25 );
    $invoicenum =~ s/ +$//g;
    my $ordernum = "";
    if ( $invoicenum ne "" ) {    # for cert
      $ordernum = $invoicenum;
    } elsif ( ( $transflags =~ /moto/ ) || ( ( $industrycode !~ /^(retail|restaurant)$/ ) && ( $commcardtype ne "1" ) ) ) {
      my $oid = substr( $orderid, -25, 25 );
      $ordernum = $oid;
    } elsif ( $commcardtype eq "1" ) {
      $commponumber = substr( $auth_code, 32, 17 );
      $commponumber =~ s/ //g;
      $ordernum = $commponumber;
    } else {
      $oid = substr( '0' x 25 . $orderid, -25, 25 );
      $ordernum = $oid;
    }
    $ordernum = substr( $ordernum . " " x 25, 0, 25 );
    $bd[1] = $ordernum;    # order number (25a)

    $avs_code = substr( $avs_code . " ", 0, 1 );
    $bd[2] = $avs_code;    # avs result (1a)

    my $installnum = "";
    my $installtot = "";
    if ( $transflags =~ /install/ ) {
      $installnum = substr( $auth_code, 170, 2 );
      $installtot = substr( $auth_code, 168, 2 );
    }
    $installnum = substr( "00" . $installnum, -2, 2 );
    $installtot = substr( "00" . $installtot, -2, 2 );
    $bd[3] = $installnum;    # moto installment sequence (2n) installnum
    $bd[4] = $installtot;    # moto installemnt count (2n) installtot

    my $amt = sprintf( "%d", ( substr( $amount, 4 ) * 100 ) + .0001 );
    $amt = substr( "0" x 10 . $amt, -10, 10 );
    $bd[5] = $amt;           # total authorized amount (10a)

    $mphone = substr( $mphone . " " x 10, 0, 10 );
    $bd[6] = $mphone;        # customer service telephone number (10a)

    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime( time() );
    my $shipdate = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
    $bd[7]  = $shipdate;     # ship date (8n) YYYYMMDD
    $bd[8]  = "00";          # multi clearing sequence number (2n)
    $bd[9]  = "00";          # multi clearing sequence count (2n)
    $bd[10] = "N";           # multi clearing partial reversal flag (1a)
    $bd[11] = "0" x 12;      # multi clearing partial reversal amount (12n)
    $bd[12] = " " x 122;     # reserved (122a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile3str .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile3str .= "\n";
    $outfile2str .= "\n";

  }

  if ( $commcardtype eq "1" ) {
    $filereccnt++;
    @bd = ();
    $bd[0] = "PCA";    # record type (3a)

    $commponumber = substr( $auth_code, 32, 17 );
    $commponumber = substr( $commponumber . " " x 25, 0, 25 );
    $bd[1] = $commponumber;    # purchase identifier (25a)

    my $taxind = "0";
    my $commtax = substr( $auth_code, 25, 7 );
    $commtax =~ s/ //g;
    if ( $commtax eq "0000.00" ) {
      $commtax = "0" x 8;
    } else {
      $commtax = substr( "0" x 8 . $commtax, -8, 8 );
      $taxind = "1";
    }

    if ( ( $card_type eq "mc" ) && ( $taxind eq "1" ) ) {
      $taxind = "Y";
    } elsif ( $card_type eq "mc" ) {
      $taxind = "N";
    }
    $bd[2] = $taxind;     # sales tax included (1a)
    $bd[3] = $commtax;    # sales tax amount (8n)

    $bd[4]  = " " x 10;   # ship from zip code (10a)
    $bd[5]  = " " x 10;   # destination zip code (10a)
    $bd[6]  = " " x 3;    # destination country code (3a)
    $bd[7]  = "0" x 12;   # discount amount (12n)
    $bd[8]  = "0" x 12;   # duty amount (12n)
    $bd[9]  = "0" x 12;   # freight amount (12n)
    $bd[10] = " ";        # national/alternate tax included (1a)
    $bd[11] = "0" x 12;   # national alternate tax (12n)
    $bd[12] = " " x 91;   # reserved (91a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile3str .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile3str .= "\n";
    $outfile2str .= "\n";

    #if ((0) && ($card_type eq "vi")) {
    #  @bd = ();
    #  $bd[0] = "PFA";   		# record type (3a) for visa
    #  $bd[1] = xxxx;   		# order date (6n)
    #  $bd[2] = xxxx;   		# other tax (12n)
    #  $bd[3] = xxxx;   		# summary commodity code (4a)
    #  $bd[4] = xxxx;   		# merchant vat reg single business reference number (20a)
    #  $bd[5] = xxxx;   		# customer vat registration number (13a)
    #  $bd[6] = xxxx;   		# vat tax amount freight (12n)
    #  $bd[7] = xxxx;   		# vat tax rate freight (4n)
    #  $bd[8] = xxxx;   		# vat invoice reference number unique (15a)
    #  $bd[9] = xxxx;   		# cardholder name (30a)
    #  $bd[10] = xxxx;   		# local tax registration id (15a)
    #  $bd[11] = xxxx;   		# local tax rate (5n)
    #  $bd[12] = xxxx;   		# invoice discount treatment (1n)
    #  $bd[13] = xxxx;   		# tax treatment (1n)
    #  $bd[14] = xxxx;   		# reserved (59a)

    #  foreach $var (@bd) {
    #    $outfilestr .= "$var";
    #    $outfile2str .= "$var";
    #  }

    #  $outfilestr .= "\n";
    #  $outfile2str .= "\n";

    #@bd = ();
    #  $bd[0] = "PVA";   		# record type (3a) for visa
    #  $bd[1] = xxxx;   		# item description (25a)
    #  $bd[2] = xxxx;   		# product code (12a)
    #  $bd[3] = xxxx;   		# item commodity code (12a)
    #  $bd[4] = xxxx;   		# quantity (12n)
    #  $bd[5] = xxxx;   		# unit of measure (12a)
    #  $bd[6] = xxxx;   		# unit cost (12n)
    #  $bd[7] = xxxx;   		# discount per line item (12n)
    #  $bd[8] = xxxx;   		# vat tax rate (4n)
    #  $bd[9] = xxxx;   		# vat tax amount (12n)
    #  $bd[10] = xxxx;   		# line item total (12n)
    #  $bd[11] = xxxx;   		# line item discount treatment (1n)
    #  $bd[12] = xxxx;   		# reserved (71a)

    #  foreach $var (@bd) {
    #    $outfilestr .= "$var";
    #    $outfile2str .= "$var";
    #  }

    #  $outfilestr .= "\n";
    #  $outfile2str .= "\n";

    #}

    # level3
    if ( (0) && ( $card_type eq "mc" ) ) {
      $filereccnt++;
      @bd         = ();
      $bd[0]      = "PMA";                                    # record type (3a) for mastercard
      $invoicenum = substr( $auth_code, 255, 25 );
      $invoicenum = substr( $auth_code . " " x 25, 0, 25 );
      $bd[1]      = $invoicenum;                              # invoice number (25a)
      $bd[2]      = " " x 172;                                # reserved (172a)

      foreach $var (@bd) {
        $outfilestr  .= "$var";
        $outfile3str .= "$var";
        $outfile2str .= "$var";
      }

      $outfilestr  .= "\n";
      $outfile3str .= "\n";
      $outfile2str .= "\n";

    }
  }

  # union pay addendum
  if ( $card_type eq "up" ) {
    $filereccnt++;
    @bd    = ();
    $bd[0] = "UPA";       # record type (3a)
    $bd[1] = "0" x 12;    # interchange fee from acom file (12n)

    my $upposcond = "00";
    if ( $transflags =~ /recur/ ) {
      $upposcond = "28";
    } elsif ( $transflags =~ /moto/ ) {
      $upposcond = "08";
    }
    $bd[2] = $upposcond;    # pos condition code (2a)

    my $transchan = "03";
    if ( $transflags =~ /recur/ ) {
      $transchan = "14";
    } elsif ( $transflags =~ /moto/ ) {
      $transchan = "09";
    } elsif ( ( $industrycode !~ /^(retail|restaurant$)/ ) && ( $transflags !~ /moto/ ) ) {
      $transchan = "07";
    }
    $bd[3] = $transchan;    # transaction channel (2a)

    $bd[4] = " " x 181;     # reserved (181a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile3str .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile3str .= "\n";
    $outfile2str .= "\n";
  }

  # user defined addendum
  $filereccnt++;
  @bd = ();
  $bd[0] = "UDA";    # record type (3a)

  my $roctext = $orderid;
  my $merchantdata = substr( $auth_code, 225, 30 );
  $merchantdata =~ s/ //g;
  if ( $merchantdata ne "" ) {
    $roctext = $merchantdata;
  }
  $roctext = substr( $orderid . " " x 39, 0, 39 );
  $bd[1] = $roctext;    # roc text data (39a) data that appears on merchant statement

  $bd[2] = " " x 158;   # reserved (158a)

  foreach $var (@bd) {
    $outfilestr  .= "$var";
    $outfile3str .= "$var";
    $outfile2str .= "$var";
  }

  $outfilestr  .= "\n";
  $outfile3str .= "\n";
  $outfile2str .= "\n";

  if (0) {

    # mobile wallet addendum
    $filereccnt++;
    @bd    = ();
    $bd[0] = "MWA";    # record type (3a)
                       #$devicetype = substr($auth_code,280,4);
                       #$devicetype =~ s/ //g;
                       #if (($devicetype ne "") || ($transflags =~ /ctls/)) {
                       #  #$transaction[38] = pack "H2", "1d";                 # gs (1)
                       #  #$transaction[39] = "08";                    # mobile/wallet type
                       #  if ($transflags =~ /ctls/) {
                       #    $devicetype = "0102";
                       #  }
                       #  $devicetype = substr($devicetype . " " x 4,0,4);
                       #  #$transaction[40] = $devicetype;
                       #}
  }

  # token data addendum
  if ( $transflags =~ /ctoken/ ) {
    $filereccnt++;
    @bd    = ();
    $bd[0] = "TDA";    # record type (3a)

    my $tokenstatus = substr( $auth_code, 214, 1 );
    $tokenstatus = substr( $tokenstatus . " ", 0, 1 );
    $bd[1] = $tokenstatus;    # token account status (1a)

    my $tokenlev = substr( $auth_code, 215, 2 );
    $tokenlev = substr( $tokenlev . "  ", 0, 2 );
    $bd[2] = $tokenlev;       # token assurance level (2a)

    my $tokenreqid = substr( $tokenreqid . " " x 11, 0, 11 );
    $bd[3] = $tokenreqid;     # token requestor id (11a)

    my $panlast4 = substr( $auth_code, 217, 4 );
    $panlast4 = substr( "0" x 4 . $panlast4, -4, 4 );
    $bd[4] = $panlast4;       # pan last 4 digits (4n)

    $bd[5] = " " x 179;       # reserved (179a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile3str .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile3str .= "\n";
    $outfile2str .= "\n";

  }

  # electronic commerce addendum
  my $cavvascii = substr( $auth_code, 127, 40 );
  $cavvascii =~ s/ //g;
  if ( $cavvascii ne "" ) {
    $filereccnt++;
    @bd    = ();
    $bd[0] = "ECI";    # record type (3a)
    $bd[1] = " ";      # system use field (1a)
    $bd[2] = " ";      # system use field (1a)
    $bd[3] = "   ";    # system use field (3a)

    my $protocol = "1";
    if ( $transflags =~ /3d2/ ) {
      $protocol = "2";
    }
    $bd[4] = $protocol;    # program protocol (1a) 3d version 1 or 2

    $cavvascii = substr( $cavvascii . " " x 80, 0, 80 );
    $bd[5] = $cavvascii;    # 3d secure value (80a)

    my $xid = "";
    if ( ( $card_type eq "mc" ) && ( $transflags =~ /3d2/ ) ) {
      $xid = substr( $auth_code, 401, 36 );
    }
    $xid = substr( $xid . " " x 36, 0, 36 );
    $bd[6] = $xid;          # directory server tran id (36a)
    $bd[7] = " " x 75;      # reserved (75a)

    foreach $var (@bd) {
      $outfilestr  .= "$var";
      $outfile3str .= "$var";
      $outfile2str .= "$var";
    }

    $outfilestr  .= "\n";
    $outfile3str .= "\n";
    $outfile2str .= "\n";
  }

  my $dbquerystr = <<"dbEOM";
        insert into batchfilesfdmsrc
	(username,filename,detailnum,trans_date,orderid,status,amount,operation,processor)
        values (?,?,?,?,?,?,?,?,?,?)
dbEOM

  my %inserthash = (
    "username", "$username", "filename", "$filename", "detailnum", "$refnum",    "trans_date", "$today", "orderid", "$orderid",
    "status",   "pending",   "amount",   "$amt",      "operation", "$operation", "processor",  "elavonfile"
  );
  &procutils::dbinsert( $username, $orderid, "pnpmisc", "batchfilesfdmsrc", %inserthash );

  #if ($transflags =~ /multi/) {
  #  $amt2 = $amt2 * $dccrate * (.1 ** $dccexponent);
  #  $amt2 = sprintf("%d", $amt2 + .5001);
  #}

  #open(batchfile,">>/home/pay1/batchfiles/$devprodlogs/elavon/tempfile.txt");
  #print batchfile "$orderid  $amt2  $dccrate  $dccexponent  $transamt\n";
  #close(batchfile);

  $amt2 = $transamt;

  #$amt2 = $batchamt;
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
  $recseqnum = substr( "000000" . $recseqnum, -6, 6 );
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

  $filereccnt++;
  @bh    = ();
  $bh[0] = "BHR";          # record type (3a)
  $mid   = $merchant_id;
  if ( $mid =~ /^000/ ) {
    $mid =~ s/^000//;
  }
  $mid = substr( $mid . " " x 16, 0, 16 );
  $bh[1] = "$mid";         # merchant id (16a)
  $mcompany = substr( $mcompany . " " x 25, 0, 25 );
  $bh[2] = "$mcompany";    # merchant dba name (25a)
  $mcity = substr( $mcity . " " x 13, 0, 13 );
  $bh[3] = "$mcity";       # merchant city (13a)
  $mstate = substr( $mstate . " " x 2, 0, 2 );
  $bh[4] = "$mstate";      # merchant state (2a)
  $mzip = substr( $mzip . " " x 9, 0, 9 );
  $bh[5] = "$mzip";        # merchant zip (9a)
  $mcountry = substr( $mcountry . " " x 3, 0, 3 );
  $bh[6] = "$mcountry";    # merchant country (3a) USA
  $tcurrency = substr( $currency . " " x 3, 0, 3 );

  if ( $tcurrency eq "   " ) {
    $tcurrency = "usd";
  }
  $tcurrency =~ tr/a-z/A-Z/;
  $bh[7] = "$tcurrency";    # currency code (3a)
  my $multicurrencyind = " ";
  if ( $transflags =~ /multi/ ) {
    $multicurrencyind = "M";
  }
  $bh[8] = $multicurrencyind;    # multicurrency indicator (1a) space or M

  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
  my $settledate = sprintf( "%04d%02d%02d", $lyear + 1900, $lmonth + 1, $lday );
  $bh[9] = "$settledate";        # settlement date (8n) YYYYMMDD

  $batchnum++;
  $batchnum = substr( "0" x 11 . $batchnum, -11, 11 );
  $bh[10] = $batchnum;           # batch number (11n)

  $bh[11] = "NOVA";              # network identifier (4a)

  #$recseqnum = substr("0" x 11 . $recseqnum,-11,11);
  $transseqnum = substr( $auth_code, 55, 30 );
  $transseqnum =~ s/ //g;
  if ( ( $operation eq "postauth" ) && ( $forceauthtime ne "" ) ) {
    $transseqnum = "0" x 30;
  } elsif ( $transseqnum eq "" ) {

    #$transseqnum = &smpsutils::gettransid($username,"elavon",$orderid);
    $transseqnum = " " x 30;
  }
  $transseqnum = substr( "0" x 11 . $transseqnum, -11, 11 );
  $bh[12] = $transseqnum;    # reference number (11a) mirrors transseqnum in first DTR record

  $bh[13] = "    ";          # client group (4a)
  $bh[14] = " " x 12;        # mps number (12a)
  $bh[15] = "  ";            # batch response code (2a)
  $bh[16] = " ";             # batch type (1a)

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
  $bh[17] = 'TZ7601' . $marketind . 'C';    # application id (8a)
  my $tid = substr( $terminal_id . " " x 22, 0, 22 );
  $bh[18] = $tid;                           # terminal id (22n)

  my $dccinfo = substr( $auth_code, 284, 52 );
  $dccinfo =~ s/ //g;

  # dcc potential known in batch header
  my $dccpotential = "N";
  if ( ( $dccinfo ne "" ) && ( $transflags !~ /multi/ ) ) {
    $dccpotential = "Y";
  }
  $bh[19] = $dccpotential;                  # dcc terminal capability (1a) N = terminal not capable of DCC processing

  $bh[20] = " " x 41;                       # reserved (41a)

  foreach $var (@bh) {
    $outfilestr  .= "$var";
    $outfile3str .= "$var";
    $outfile2str .= "$var";
  }

  $outfilestr  .= "\n";
  $outfile3str .= "\n";
  $outfile2str .= "\n";

}

sub batchtrailer {
  $batchreccnt++;
  $filereccnt++;

  $batchreccnt = substr( "0000000" . $batchreccnt, -7, 7 );

  if ( $batchsalesamt < 0 ) {
    $batchsalesamt = 0 - $batchsalesamt;
  }
  if ( $batchretamt < 0 ) {
    $batchretamt = 0 - $batchretamt;
  }

  my $batchnetsign = "+";
  if ( $batchtotalamt < 0 ) {
    $batchtotalamt = 0 - $batchtotalamt;
    $batchnetsign  = "-";
  }

  $batchtotalamt = substr( "0" x 12 . $batchtotalamt, -12, 12 );
  $batchsalescnt = substr( "0" x 6 . $batchsalescnt,  -6,  6 );
  $batchsalesamt = substr( "0" x 12 . $batchsalesamt, -12, 12 );
  $batchretcnt   = substr( "0" x 6 . $batchretcnt,    -6,  6 );
  $batchretamt   = substr( "0" x 12 . $batchretamt,   -12, 12 );
  $batchcount    = substr( "0" x 6 . $batchcount,     -6,  6 );
  $batchnum      = substr( "0" x 11 . $batchnum,      -11, 11 );
  $detailcount   = substr( "0" x 6 . $detailcount,    -6,  6 );

  @bt    = ();
  $bt[0] = "BTR";             # record type (3a)
  $bt[1] = $batchsalescnt;    # batch purchases count (6n)
  $bt[2] = $batchsalesamt;    # batch purchases amount (12n)
  $bt[3] = $batchretcnt;      # batch return count (6n)
  $bt[4] = $batchretamt;      # batch return amount (12n)
  $bt[5] = $detailcount;      # batch total count (6)
  $bt[6] = $batchtotalamt;    # batch net amount (12n)
  $bt[7] = $batchnetsign;     # batch net sign (1a) + or -
  $bt[8] = $batchnum;         # batch number (11n)
  $bt[9] = " " x 131;         # reserved (131a)

  foreach $var (@bt) {
    $outfilestr  .= "$var";
    $outfile3str .= "$var";
    $outfile2str .= "$var";
  }
  $outfilestr  .= "\n";
  $outfile3str .= "\n";
  $outfile2str .= "\n";

}

sub fileheader {
  my $printstr = "in fileheader\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  $batchcount = 0;
  $batchnum   = 0;
  $filecount++;

  $file_flag = 0;

  #my $dbquerystr = <<"dbEOM";
  #      select filenum,batchdate
  #      from elavon
  #      where username='elavon'
  #dbEOM
  #  my @dbvalues = ();
  #  ($filenum,$batchdate) = &procutils::dbread($username,$orderid,"pnpmisc",$dbquerystr,@dbvalues);

  #my $printstr = "batchdate: $batchdate, today: $today, filenum: $filenum\n";
  #&procutils::filewrite("$username","elavon","/home/pay1/batchfiles/devlogs/elavon","miscdebug.txt","append","misc",$printstr);

  #  if ($batchdate != $todaylocal) {
  #    $filenum = 0;
  #  }
  #  $filenum = $filenum + 1;
  #  if ($filenum > 9) {
  #  my $printstr = "<h3>You have exceeded the maximum allowable batches for today.</h3>\n";
  #  &procutils::filewrite("$username","elavon","/home/pay1/batchfiles/devlogs/elavon","miscdebug.txt","append","misc",$printstr);
  #  }

  ( $d1, $d2, $ttime ) = &miscutils::genorderid();

  #$filename = "$ttime$pid";
  $filename = "P8017" . substr( $ttime, 2, 12 ) . ".edc";

  #$filename = "P8017" . substr($ttime,2,12) . ".uat";

  #  my $dbquerystr = <<"dbEOM";
  #        update elavon set filenum=?,batchdate=?
  #	where username='elavon'
  #dbEOM
  #  my @dbvalues = ("$filenum","$todaylocal");
  #  &procutils::dbupdate($username,$orderid,"pnpmisc",$dbquerystr,@dbvalues);

  umask 0077;
  $outfilestr  = "";
  $outfile3str = "";
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
  $recseqnum    = substr( "000000" . $recseqnum, -6, 6 );
  $fileid       = substr( $fileid . " " x 20, 0, 20 );

  @fh         = ();
  $fh[0]      = "FHR";                        # record type (3a)
  $createdate = substr( $todaytime, 0, 8 );
  $createtime = substr( $todaytime, 8, 6 );
  $fh[1]      = $createdate;                  # file create date - YYYYMMDD (8n)
  $fh[2]      = $createtime;                  # file create date - HHMMSS (6n)
  $fh[3]      = "44";                         # version number (2n)

  #$filenum = substr("0" x 3 . $filenum,-3,3);
  $fh[4] = "8017";                            # elavon file number (4n) same for all pnp
  $fh[5] = "plgpay                   ";       # sending institution name (25a)

  my $origfilename = $filename;
  $origfilename = substr( $origfilename . " " x 32, 0, 32 );
  $fh[6] = $origfilename;                     # originating file name (32a)
  $fh[7] = " " x 120;                         # reserved (120a)

  foreach $var (@fh) {
    $outfilestr  .= "$var";
    $outfile3str .= "$var";
    $outfile2str .= "$var";
  }

  $outfilestr  .= "\n";
  $outfile3str .= "\n";
  $outfile2str .= "\n";

}

sub filetrailer {

  if ( $filesalesamt < 0 ) {
    $filesalesamt = 0 - $filesalesamt;
  }
  if ( $fileretamt < 0 ) {
    $fileretamt = 0 - $fileretamt;
  }

  $filereccnt++;

  my $filenetsign = "+";
  if ( $filetotalamt < 0 ) {
    $filetotalamt = 0 - $filetotalamt;
    $filenetsign  = "-";
  }

  $filetotalcnt = substr( "0" x 6 . $filetotalcnt,  -6,  6 );
  $filetotalamt = substr( "0" x 12 . $filetotalamt, -12, 12 );
  $filesalescnt = substr( "0" x 6 . $filesalescnt,  -6,  6 );
  $filesalesamt = substr( "0" x 12 . $filesalesamt, -12, 12 );
  $fileretcnt   = substr( "0" x 6 . $fileretcnt,    -6,  6 );
  $filereccnt   = substr( "0" x 6 . $filereccnt,    -6,  6 );
  $fileretamt   = substr( "0" x 12 . $fileretamt,   -12, 12 );
  $batchcount   = substr( "0" x 6 . $batchcount,    -6,  6 );

  @ft    = ();
  $ft[0] = "FTR";            # record type (3a)
  $ft[1] = $filesalescnt;    # file purchases count (6n)
  $ft[2] = $filesalesamt;    # file purchases amount (12n)
  $ft[3] = $fileretcnt;      # file return count (6n)
  $ft[4] = $fileretamt;      # file return amount (12n)
  $ft[5] = $filetotalcnt;    # file total count (6)
  $ft[6] = $filetotalamt;    # file net amount (12n)
  $ft[7] = $filenetsign;     # file net sign (1a) + or -
  $ft[8] = $filereccnt;      # file record count (6n)

  $createdate = substr( $todaytime, 0, 8 );
  $createtime = substr( $todaytime, 8, 6 );
  $ft[9]  = $createdate;     # file create date (8n)
  $ft[10] = $createtime;     # file create time (6n)
  $ft[11] = " " x 122;       # reserved (122a)

  foreach $var (@ft) {
    $outfilestr  .= "$var";
    $outfile3str .= "$var";
    $outfile2str .= "$var";
  }

  $outfilestr  .= "\n";
  $outfile3str .= "\n";
  $outfile2str .= "\n";

  print "$outfilestr\n";

  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear", "$filename",     "write", "", $outfilestr );
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear", "$filename.new", "write", "", $outfile3str );
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear", "$filename.txt", "write", "", $outfile2str );

  my $printstr = "filenum: $filenum  today: $today  amt: $filetotalamtstr  cnt: $filetotalcnt\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  #local $sthinfo = $dbh->prepare(qq{
  #    update batchfilesfdmse
  #    set amount=?,count=?
  #    where trans_date='$today'
  #    and filenum='$newfilenum'
  #    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  #$sthinfo->execute("$filetotalamtstr","$filetotalcnt") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
  #$sthinfo->finish;
}

sub pidcheck {
  my @infilestrarray = &procutils::fileread( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon", "pidfile$group.txt" );
  $chkline = $infilestrarray[0];
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfilesfile.pl already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprodlogs/elavon/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfilesfile.pl already running, pid alterred by another program, exiting...\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
    my $printstr = "$pidline\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
    my $printstr = "$chkline\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: elavon - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfilesfile.pl already running, pid alterred by another program, exiting...\n";
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
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

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

  #print "The first day of month $month1 happens on wday $wday\n";

  if ( $wday1 < $wday ) {
    $wday1 = 7 + $wday1;
  }
  my $mday1 = ( 7 * ( $times1 - 1 ) ) + 1 + ( $wday1 - $wday );
  my $timenum1 = timegm( 0, substr( $time1, 3, 2 ), substr( $time1, 0, 2 ), $mday1, $month1 - 1, substr( $origtime, 0, 4 ) - 1900 );

  #print "time1: $time1\n\n";

  my $printstr = "The $times1 Sunday of month $month1 happens on the $mday1\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month2 happens on wday $wday\n";

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $printstr = "The $times2 Sunday of month $month2 happens on the $mday2\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

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

  my $printstr = "zoneadjust: $zoneadjust\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  my $printstr = "newtime: $newtime $timezone2\n\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  return $newtime;

}

