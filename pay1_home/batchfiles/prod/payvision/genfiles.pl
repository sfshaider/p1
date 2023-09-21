#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;
use smpsutils;
use payvision;
use isotables;
use Time::Local;
use PlugNPay::CreditCard;
use JSON;

#use Data::Dumper;

$devprod = "logs";

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
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );
  exit;
}

if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'payvision/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: payvision - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

my $checkuser = &procutils::fileread( "$username", "payvision", "/home/pay1/batchfiles/$devprod/payvision", "genfiles.txt" );
chop $checkuser;

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>='$checkuser'";
}

#$checkstring = "and t.username='aaaa'";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "      ";
$starttransdate   = $onemonthsago - 10000;

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

#print "two months ago: $twomonthsago\n";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $dummy, $today, $ttime ) = &miscutils::genorderid();
$todaytime = $ttime;

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/payvision/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/payvision/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/payvision/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/payvision/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/payvision/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/payvision/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/payvision/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/payvision/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/payvision/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/payvision/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: payvision - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/payvision/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;

# xxxx
#and t.username='paragont'
# homeclip should not be batched, it shares the same account as golinte1
my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        and t.trans_date<=?
        $checkstring
        and t.finalstatus in ('pending','locked')
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.processor='payvision'
        and o.lastoptime>=?
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user $usercount $usertdate\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );
  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

foreach $username ( sort @userarray ) {
  if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
    unlink "/home/pay1/batchfiles/$devprod/payvision/batchfile.txt";
    last;
  }

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/$devprod/payvision", "genfiles.txt", "write", "", $checkinstr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/$devprod/payvision", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};

  my $printstr = "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/$devprod/payvision/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );

  %errorderid    = ();
  $detailnum     = 0;
  $batchsalesamt = 0;
  $batchsalescnt = 0;
  $batchretamt   = 0;
  $batchretcnt   = 0;
  $batchcnt      = 1;

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,country,addr1,city,state,zip,tel,status,features
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $mcountry, $address, $city, $state, $zip, $tel, $status, $features ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
        select memberid,memberguid,industrycode,allowmarketdata
        from payvision
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $memberid, $memberguid, $industrycode, $allowmarketdata ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $printstr = "$username $status\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );

  if ( $status ne "live" ) {
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
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/$devprod/payvision/$fileyear", "$username$time.txt", "append", "", $logfilestr );
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/$devprod/payvision/$fileyear", "$username$time.txt", "append", "", $logfilestr );
      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  my $printstr = "gmt today: $todaytime\n";
  $printstr .= "est today: $esttime\n";
  $printstr .= "est yesterday: $yesterday\n";
  $printstr .= "settletime: $settletime\n";
  $printstr .= "sweeptime: $sweeptime\n";
  $printstr .= "aaaa $starttransdate $onemonthsagotime $username\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );

  $batch_flag = 0;
  $netamount  = 0;
  $hashtotal  = 0;
  $batchcnt   = 1;
  $recseqnum  = 0;

  my $dbquerystr = <<"dbEOM";
        select o.orderid,o.trans_date
        from operation_log o, trans_log t
        where t.trans_date>=?
        and t.username=?
        and t.operation in ('postauth','return','forceauth')
        and t.finalstatus='pending'
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastop=t.operation
        and o.lastopstatus='pending'
        and o.processor='payvision'
        and (o.voidstatus is NULL or o.voidstatus ='')
        and (o.accttype is NULL or o.accttype ='' or o.accttype='credit')
dbEOM
  my @dbvalues = ( "$onemonthsago", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  %orderidarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 2 ) {
    ( $orderid, $trans_date ) = @sthtransvalarray[ $vali .. $vali + 1 ];

    $orderidarray{"$orderid"} = 1;

    #$starttdateinarray{"$username $trans_date"} = 1;
  }

  foreach $orderid ( sort keys %orderidarray ) {
    print "orderid: $orderid\n";

    my $dbquerystr = <<"dbEOM";
        select orderid,lastop,trans_date,lastoptime,enccardnumber,length,
                   card_exp,amount,auth_code,avs,refnumber,lastopstatus,
                   cvvresp,transflags,origamount,reauthstatus,postauthstatus,forceauthstatus
        from operation_log
        where orderid=?
        and username=?
dbEOM
    my @dbvalues = ( "$orderid", "$username" );
    ( $orderid,  $operation, $trans_date,  $trans_time, $enccardnumber, $enclength,  $exp,          $amount,         $auth_code,
      $avs_code, $refnumber, $finalstatus, $cvvresp,    $transflags,    $origamount, $reauthstatus, $postauthstatus, $forceauthstatus
    )
      = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
      unlink "/home/pay1/batchfiles/$devprod/payvision/batchfile.txt";
      last;
    }

    if ( ( $proc_type eq "authcapture" ) && ( $operation eq "postauth" ) ) {
      next;
    }

    if ( ( $transflags =~ /capture/ ) && ( $operation eq "postauth" ) ) {
      next;
    }

    if ( ( $sweeptime ne "" ) && ( $trans_time > $sweeptime ) ) {
      next;    # transaction is newer than sweeptime
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/$devprod/payvision/$fileyear", "$username$time.txt", "append", "", $logfilestr );

    my $printstr = "$orderid $operation $auth_code $refnumber\n";
    &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "payvision", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $errorflag = &errorchecking();
    if ( $errorflag == 1 ) {
      next;
    }

    if ( $batchcnt == 1 ) {
      $batchnum = "";

      #&getbatchnum();
    }

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='locked',result=?,detailnum=?
	    where orderid=?
	    and trans_date>=?
	    and finalstatus='pending'
	    and username=?
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time$batchnum", "$detailnum", "$orderid", "$onemonthsago", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending',detailnum=?
          where orderid=?
          and username=?
          and $operationstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time$batchnum", "$detailnum", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my ( $message, $tcode ) = &batchdetail();

    my $response = &sendmessage( $message, $tcode );

    &endbatch( $response, $tcode );
  }

  if ( $batchcnt > 1 ) {
    %errorderid = ();
    $detailnum  = 0;
  }
}

if ( !-e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  umask 0033;
  $checkinstr = "";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/$devprod/payvision", "genfiles.txt", "write", "", $checkinstr );
}

unlink "/home/pay1/batchfiles/$devprod/payvision/batchfile.txt";

exit;

sub endbatch {
  my ( $response, $tcode ) = @_;

  #my ($header,$data) = split(/\r{0,1}\n\r{0,1}\n/,$response);
  $response =~ s/\r{0,1}\n/;;;;/g;
  $response =~ s/^.*?\{/\{/;
  $response =~ s/;;;;/\n/g;

  my $jsonmsg = &JSON::decode_json($response);

  #print Dumper $jsonmsg;

  $pass = $jsonmsg->{ $tcode . "Result" }->{Result};

  my %resparray = &payvision::readjson( $jsonmsg, $tcode );

  my $message = $jsonmsg->{ "$tcode" . "Result" }->{Message};
  $respcode = $jsonmsg->{ "$tcode" . "Result" }->{Result};

  if ( $resparray{ "$tcode" . "Result,Cdc,BankInformation,BankCode" } ne "" ) {
    $respcode = $resparray{ "$tcode" . "Result,Cdc,BankInformation,BankCode" };
  }
  if ( ( $resparray{ "$tcode" . "Result,Cdc,BankInformation,BankMessage" } ne "" ) && ( $resparray{ "$tcode" . "Result,Cdc,BankInformation,BankMessage" } !~ /\-/ ) ) {
    $message = $resparray{ "$tcode" . "Result,Cdc,BankInformation,BankMessage" };
  }
  if ( $resparray{ "$tcode" . "Result,Cdc,BankInformation,BankApprovalCode" } ne "" ) {
    $auth_code = $resparray{ "$tcode" . "Result,Cdc,BankInformation,BankApprovalCode" };
  }
  if ( ( $resparray{ "$tcode" . "Result,Cdc,BankInformation,BankCode" } eq "" ) && ( $resparray{ "$tcode" . "Result,Cdc,ErrorInformation,ErrorCode" } ne "" ) ) {
    $respcode = $resparray{ "$tcode" . "Result,Cdc,ErrorInformation,ErrorCode" };
  }
  if ( ( $resparray{ "$tcode" . "Result,Cdc,BankInformation,BankCode" } eq "" ) && ( $resparray{ "$tcode" . "Result,Cdc,ErrorInformation,ErrorMessage" } ne "" ) ) {
    $message = $resparray{ "$tcode" . "Result,Cdc,ErrorInformation,ErrorMessage" };
  }

  $err_msg = "$respcode: $message";

  $transid   = $jsonmsg->{ $tcode . "Result" }->{TransactionId};
  $transguid = $jsonmsg->{ $tcode . "Result" }->{TransactionGuid};

  $err_msg = "$respcode: $message";

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "orderid   $orderid\n";
  $logfilestr .= "respcode   $respcode\n";
  $logfilestr .= "err_msg   $err_msg\n";
  $logfilestr .= "result   $time$batchnum\n\n\n";
  if ( $operation eq "return" ) {
    $tmpstr = "2";
  } else {
    $tmpstr = "1";
  }
  $logfilestr .= 'xxyy,"' . $respcode . '","' . $transid . '","' . $transguid . '","' . $orderid . $tmpstr . '","' . $err_msg . '"' . "\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/$devprod/payvision/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  my $printstr = "orderid   $orderid\n";
  $printstr .= "transseqnum   $transseqnum\n";
  $printstr .= "respcode   $respcode\n";
  $printstr .= "err_msg   $err_msg\n";
  $printstr .= "result   $time$batchnum\n\n\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  if ( $respcode =~ /^(0|00|000)$/ ) {

    $auth_code  = substr( $auth_code . " " x 6,   0, 6 );     # 0
    $transid    = substr( $transid . " " x 30,    0, 30 );    # 6
    $transguid  = substr( $transguid . " " x 40,  0, 40 );    # 36
    $marketdata = substr( $marketdata . " " x 35, 0, 35 );    # 76

    $auth_code = $auth_code . $transid . $transguid . $marketdata;

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?,auth_code=?
            where orderid=?
            and trans_date>=?
            and result=?
            and username=?
            and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$auth_code", "$orderid", "$onemonthsago", "$time$batchnum", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='success',lastopstatus='success',$operationtime=?,lastoptime=?,auth_code=?
            where orderid=?
            and lastoptime>=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$time", "$auth_code", "$orderid", "$onemonthsagotime", "$username", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  } elsif ( $respcode ne "success" ) {
    my $printstr = "bbbb $orderid  $onemonthsago  $username\n";
    &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );

    $err_msg =~ s/the following errors occurred during parsing://;
    $err_msg = substr( $err_msg, 0, 63 );

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where orderid=?
            and trans_date>=?
            and username=?
            and (accttype is NULL or accttype ='' or accttype='credit')
            and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$err_msg", "$orderid", "$onemonthsago", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and lastoptime>=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$err_msg", "$orderid", "$onemonthsagotime" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    #open(MAILERR,"| /usr/lib/sendmail -t");
    #print MAILERR "To: cprice\@plugnpay.com\n";
    #print MAILERR "From: dcprice\@plugnpay.com\n";
    #print MAILERR "Subject: payvision - FORMAT ERROR\n";
    #print MAILERR "\n";
    #print MAILERR "username: $username\n";
    #print MAILERR "result: format error\n\n";
    #print MAILERR "batchtransdate: $batchtransdate\n";
    #close MAILERR;
  } else {
    my $printstr = "cccc $orderid  $onemonthsago  $username\n";
    $printstr .= "respcode	$respcode unknown\n";
    &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: payvision - unkown error\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $resp\n";
    print MAILERR "file: $username$time.txt\n";
    close MAILERR;
  }

}

sub getbatchnum {

  my $dbquerystr = <<"dbEOM";
          select batchnum
          from payvision
          where username=?
dbEOM
  my @dbvalues = ("$username");
  ($batchnum) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = $batchnum + 1;
  if ( $batchnum >= 998 ) {
    $batchnum = 1;
  }

  my $dbquerystr = <<"dbEOM";
          update payvision set batchnum=?
          where username=?
dbEOM
  my @dbvalues = ( "$batchnum", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = substr( "0000" . $batchnum, -4, 4 );

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

  if ( $operation eq "postauth" ) {
    $batchsalesamt = $batchsalesamt + $transamt;
    $batchsalescnt = $batchsalescnt + 1;
    $filesalesamt  = $filesalesamt + $transamt;
    $filesalescnt  = $filesalescnt + 1;
  } else {
    $batchretamt = $batchretamt + $transamt;
    $batchretcnt = $batchretcnt + 1;
    $fileretamt  = $fileretamt + $transamt;
    $fileretcnt  = $fileretcnt + 1;
  }

  $batchcnt++;
  $batchreccnt++;
  $recseqnum++;

  $origorderid = substr( $auth_code, 6,  10 );
  $cardtype    = substr( $auth_code, 16, 1 );
  $ipaddress   = substr( $auth_code, 17, 20 );
  $ipaddress =~ s/ +$//;

  ( $d1, $d2, $ttime ) = &miscutils::genorderid();

  @bd = ();

  $bd[0] = "<?xml version=\"1.0\" encoding=\"utf-8\"?>";
  $bd[1] = "<soap12:Envelope xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:soap12=\"http://www.w3.org/2003/05/soap-envelope\">";

  #$bd[2] = "<soap12:Header>";
  #$bd[3] = "<OriginatorHeader xmlns=\"http://payvision.com/gateway/\">";
  #$bd[4] = "<OriginatorId>xxxx</OriginatorId>";
  #$bd[5] = "</OriginatorHeader>";
  #$bd[6] = "</soap12:Header>";
  $bd[7] = "<soap12:Body>";
  my $printstr = "force: $forceauthstatus\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );

  $transid = substr( $auth_code, 6, 30 );
  $transid =~ s/ //g;

  my $tcode = "";
  if ( ( $operation eq "return" ) && ( $transflags =~ /fund/ ) ) {
    $tcode = "CardFundTransfer";
  } elsif ( ( $operation eq "return" ) && ( $transid eq "" ) ) {
    $tcode = "Credit";
  } elsif ( $operation eq "return" ) {
    $tcode = "Refund";
  } elsif ( $forceauthstatus eq "success" ) {
    $tcode = "ReferralApproval";
  } else {
    $tcode = "Capture";
  }
  $bd[8]  = "<$tcode xmlns=\"http://payvision.com/gateway/\">";
  $bd[9]  = "<memberId>$memberid</memberId>";
  $bd[10] = "<memberGuid>$memberguid</memberGuid>";
  if ( ( $operation eq "return" ) && ( $transid eq "" ) ) {
    my $country = $mcountry;
    $country =~ tr/a-z/A-Z/;
    $country = $isotables::countryUS840{$country};
    $bd[11]  = "<countryId>$country</countryId>";
    $bd[12]  = "<cardNumber>$cardnumber</cardNumber>";
    ( $monthexp, $yearexp ) = split( /\//, $exp );
    $bd[13] = "<cardExpiryMonth>$monthexp</cardExpiryMonth>";
    $bd[14] = "<cardExpiryYear>20$yearexp</cardExpiryYear>";

    if ( $transflags =~ /recurring/ ) {
      $merchaccttype = "4";
    } elsif ( $transflags =~ /moto/ ) {
      $merchaccttype = "2";
    } elsif ( $industrycode eq "retail" ) {
      $merchaccttype = "3";
    } else {
      $merchaccttype = "1";
    }
    $bd[15] = "<merchantAccountType>$merchaccttype</merchantAccountType>";
  } else {
    $bd[11] = "<transactionId>$transid</transactionId>";
    $transguid = substr( $auth_code, 36, 40 );
    $transguid =~ s/ //g;
    $bd[12] = "<transactionGuid>$transguid</transactionGuid>";
  }
  ( $currency, $amount ) = split( / /, $amount );
  $currency =~ tr/a-z/A-Z/;
  my $currency = $isotables::currencyUSD840{$currency};
  $bd[16] = "<amount>$amount</amount>";
  $bd[17] = "<currencyId>$currency</currencyId>";

  if ( ( $operation eq "return" ) && ( $transflags =~ /fund/ ) ) {
    $bd[18] = "<trackingMemberCode>$orderid" . "1</trackingMemberCode>";
  } elsif ( $operation eq "return" ) {
    $bd[18] = "<trackingMemberCode>$orderid" . "2</trackingMemberCode>";
  } else {
    $bd[18] = "<trackingMemberCode>$orderid" . "1</trackingMemberCode>";
  }

  #my $cardtype = $payvision::card_type;
  #$cardtype =~ tr/a-z/A-Z/;
  #$bd[20] = "<cardType>$cardtype</cardType>";
  #my $issuenum = substr($payvision::datainfo{'cardissuenum'},0,2);
  #$bd[21] = "<issueNumber>$issuenum</issueNumber>";
  #my $merchaccttype = "";
  #$bd[23] = "<dynamicDescriptor>xxxx</dynamicDescriptor>";
  #$bd[24] = "<avsAddress>![CDATA[$payvision::datainfo{'card-address'}]]</avsAddress>";
  #$bd[25] = "<avsZip>$payvision::datainfo{'card-zip'}</avsZip>";

  $marketdata = substr( $auth_code, 76, 35 );
  $marketdata =~ s/ +$//g;
  if ( ( $marketdata ne "" ) && ( ( $operation eq "return" ) || ( ( $operation eq "postauth" ) && ( $forceauthstatus eq "success" ) ) ) ) {
    my $phone = substr( $marketdata, -10, 10 );
    $phone =~ s/ //g;

    my $extramarketdata = substr( $marketdata, 0, 25 );
    $extramarketdata =~ s/ +$//g;
    $extramarketdata =~ tr/a-z/A-Z/;

    if ( $allowmarketdata eq "no" ) {
      $extramarketdata = "";
    }

    $bd[23] = "<dbaName>$extramarketdata</dbaName>";
    $bd[24] = "<dbaCity>$phone</dbaCity>";
  }

  $bd[27] = "</$tcode>";

  $bd[28] = "</soap12:Body>";
  $bd[29] = "</soap12:Envelope>";

  my $message = "";
  my $indent  = 0;
  foreach $var (@bd) {
    if ( $var =~ /^<\/.*>/ ) {
      $indent--;
    }
    if ( ( $var ne "" ) && ( $var !~ /></ ) ) {
      $message = $message . $var . "\n";
    }

    #$message = $message . " " x $indent . $var . "\n";
    if ( ( $var !~ /\// ) && ( $var != /<?/ ) ) {
      $indent++;
    }
    if ( $indent < 0 ) {
      $indent = 0;
    }
  }

  $message = &payvision::xmltojson( $message, $tcode );

  my $messagestr = $req;
  my $xs         = "x" x length($cardnumber);
  $messagestr =~ s/\"cardNumber\"\: \"[0-9]+?\"/\"cardNumber\"\: \"$xs\"/;

  my $tmpcardnum = $cardnumber;
  $tmpcardnum =~ s/[^0-9]//g;
  my $tmpcardlen    = length($tmpcardnum);
  my $shacardnumber = "";
  if ( ( $tmpcardlen > 12 ) && ( $tmpcardlen < 22 ) ) {
    my $cc = new PlugNPay::CreditCard($tmpcardnum);
    $shacardnumber = $cc->getCardHash();
  }

  return $message, $tcode;
}

sub sendmessage {
  my ( $msg, $tcode ) = @_;

  my $host = "processor.payvisionservices.com";
  my $port = "443";
  my $path = "/GatewayV2/BasicOperationsService.svc/json/$tcode";

  if ( $username eq "testpayv" ) {
    $host = "testprocessor.payvisionservices.com";
  }

  $mytime = gmtime( time() );
  my $chkmessage = $msg;
  $chkmessage =~ s/\"cardNumber\"\: \"[0-9]+\"/\"cardNumber\"\: \"xxxxxxxx\"/;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username  $orderid\n";
  $logfilestr .= "$host:$port  $path\n";
  $logfilestr .= "$mytime send: $chkmessage\n\n";
  $logfilestr .= "sequencenum: $sequencenum retries: $retries\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/$devprod/payvision/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  my $len        = length($msg);
  my %sslheaders = ();
  $sslheaders{'Host'}           = "$host";
  $sslheaders{'Content-Type'}   = 'application/json';
  $sslheaders{'Content-Length'} = $len;
  ( my $response, my $header, my %resulthash ) = &procutils::sendsslmsg( "payvision", $host, $port, $path, $msg, "noshutdown,noheaders,http10,got=\/BinaryMsgResp,len<1", %sslheaders );

  $mytime = gmtime( time() );
  my $chkmessage = $response;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username  $orderid\n";
  $logfilestr .= "$mytime recv: $chkmessage\n\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/$devprod/payvision/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  return $response;
}

sub errorchecking {

  #my $chkauthcode = substr($auth_code,0,6);
  #$authcode =~ s/ //g;

  #if (($chkauthcode eq "") || ($refnumber eq "")) {
  #  &errormsg($username,$orderid,$operation,'missing auth code or reference number');
  #  return 1;
  #}

  if ( $enclength > 1024 ) {
    &errormsg( $username, $orderid, $operation, 'could not decrypt' );
    return 1;
  }
  $temp = substr( $amount, 4 );
  if ( $temp == 0 ) {
    &errormsg( $username, $orderid, $operation, 'amount = 0.00' );
    return 1;
  }

  if ( $cardnumber eq "4111111111111111" ) {
    &errormsg( $username, $orderid, $operation, 'test card number' );
    return 1;
  }

  $clen      = length($cardnumber);
  $cabbrev   = substr( $cardnumber, 0, 4 );
  $card_type = &smpsutils::checkcard($cardnumber);
  if ( $card_type eq "" ) {
    &errormsg( $username, $orderid, $operation, 'bad card number' );
    return 1;
  }
  return 0;
}

sub errormsg {
  my ( $username, $orderid, $operation, $errmsg ) = @_;

  my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where orderid=?
            and trans_date>=?
            and username=?
            and finalstatus='pending'
            and (accttype is NULL or accttype ='' or accttype='credit')
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
            and lastoptime>=?
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$errmsg", "$orderid", "$username", "$onemonthsagotime" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  my $printstr = "origtime: $origtime $timezone1\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );

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

  my $printstr = "The $times1 Sunday of month $month1 happens on the $mday1\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month2 happens on wday $wday\n";

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $printstr = "The $times2 Sunday of month $month2 happens on the $mday2\n";
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "payvision", "/home/pay1/batchfiles/devlogs/payvision", "miscdebug.txt", "append", "misc", $printstr );
  return $newtime;

}

