#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;
use smpsutils;
use telecheck;
use Sys::Hostname;

# plan etpay  version 2.0

$devprod = "logs";

if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'telecheck/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: telecheck - genfiles already running\n";
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
&procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "pid.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my $chkline = &procutils::fileread( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "pid.txt" );
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
  $printstr .= "$pidline\n";
  $printstr .= "$chkline\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: telecheck - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

#open(checkin,"/home/pay1/batchfiles/$devprod/telecheck/genfiles.txt");
#$checkuser = <checkin>;
#chop $checkuser;
#close(checkin);

#if (($checkuser =~ /^z/) || ($checkuser eq "")) {
$checkstring = "";

#}
#else {
#  $checkstring = "and t.username>='$checkuser'";
#}
#$checkstring = "and t.username='aaaa'";
#$checkstring = "and t.username in ('skyhawket1','skyhawkete')";

# xxxx
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "      ";
$starttransdate   = $onemonthsago - 10000;

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

#print "two months ago: $twomonthsago\n";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $dummy, $today, $ttime ) = &miscutils::genorderid();

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/telecheck/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/telecheck/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/telecheck/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/telecheck/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/telecheck/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/telecheck/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/telecheck/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/telecheck/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/telecheck/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/telecheck/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: telecheck - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory telecheck/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$processid = $$;

local %errcode = (

  #"0","Call Center or Data Entry Error",
  #"1","ACH Approved",
  #"2","Approved/Delayed Shipment/Offered",
  #"3","Code 3 Decline",
  #"4","Code 4 Decline",
  #"07","Approved",
  #"08","Rejected (negative data).",
  #"73","Lost or Stolen Check.",
  #"88","Rejected Code 3 (Risk).",
  #"25","Ineligible - ACH Not Offered.",
  #"82","Duplicate Check Ask for other form of payment. Transaction has previously been approved. Sale Referral Responses",
  #"41","Subscriber Number Not Active",
  #"03","Subscriber Number Does Not Exist",
  #"46","Merchant setup does not allow this type of transaction.",
  #"49","Processor Not Available Re-send message later.",
  #"27","Invalid Value for Field",
  #"97","Unable to Process (Time Out) Re-send message later.",

  "26", "Merchant allowed to send full/partial adjustments/refunds without transaction errors",
  "46", "Merchant setup does not allow this type of transaction.",
  "79", "Original transaction was not approved",
  "80", "Refund or partial amount is greater than original sale amount",
  "81", "Unable to locate original transaction (TCK Trace ID) Adjustment cannot be processed by TeleCheck",

  "OK",  "Inquiry (POS system) Packet was accepted and successfully processed by TeleCheck",
  "NAK", "Inquiry Packet was not successfully processed by TeleCheck (general error)",
  "49",  "Inquiry Packet was not successfully processed by TeleCheck (scheduled maintenance)",
  "97",  "Inquiry Packet was not successfully processed by TeleCheck (timeout)",
  "27",  "Inquiry Packet was not successfully processed by TeleCheck (invalid data)",

  "xx", "Undefined response"
);

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
        and t.accttype in ('savings','checking')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.processor='telecheck'
        and o.lastoptime>=?
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user $usercount $usertdate\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

foreach $username ( sort @userarray ) {
  if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
    unlink "/home/pay1/batchfiles/$devprod/telecheck/batchfile.txt";
    last;
  }

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};

  my $printstr = "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  umask 0077;
  $logfilestr = "";
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr .= "$username\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  %errorderid    = ();
  $detailnum     = 0;
  $batchsalesamt = 0;
  $batchsalescnt = 0;
  $batchretamt   = 0;
  $batchretcnt   = 0;
  $batchcnt      = 1;

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,company,addr1,city,state,zip,tel,status,currency
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $company, $address, $city, $state, $zip, $tel, $status, $currency ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
        select merchantnum
        from telecheck
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ($merchant_id) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  #if ($terminalnum eq "") {
  #  $terminalnum = "00000001";
  #}

  my $printstr = "$username $status\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  if ( $status ne "live" ) {
    next;
  }

  if ( $currency eq "" ) {
    $currency = "usd";
  }

  my $printstr = "aaaa $starttransdate $onemonthsagotime $username\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  $batch_flag = 0;
  $netamount  = 0;
  $hashtotal  = 0;
  $batchcnt   = 1;
  $recseqnum  = 0;

  %orderidarray    = ();
  %chkorderidarray = ();
  %inplanetarray   = ();
  %inoplogarray    = ();

  my $dbquerystr = <<"dbEOM";
        select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,
               auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,origamount,
               forceauthstatus,reauthstatus
        from operation_log
        where trans_date>=?
        and lastoptime>=?
        and username=?
        and lastopstatus in ('pending')
        and lastop IN ('auth','postauth','return','forceauth')
        and (voidstatus is NULL or voidstatus ='')
        and accttype in ('savings','checking')
        order by orderid
dbEOM
  my @dbvalues = ( "$starttransdate", "$onemonthsagotime", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 17 ) {
    ( $orderid,  $operation, $trans_date,  $trans_time, $enccardnumber, $enclength,  $exp,             $amount, $auth_code,
      $avs_code, $refnumber, $finalstatus, $cvvresp,    $transflags,    $origamount, $forceauthstatus, $reauthstatus
    )
      = @sthtransvalarray[ $vali .. $vali + 16 ];

    if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
      unlink "/home/pay1/batchfiles/$devprod/telecheck/batchfile.txt";
      last;
    }

    if ( ( $proc_type eq "authcapture" ) && ( $operation eq "postauth" ) ) {
      next;
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    my $printstr = "$orderid $operation $auth_code $refnumber\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "telecheck", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );
    ( $routenum, $acctnum ) = split( / /, $cardnumber );

    $errorflag = &errorchecking();
    my $printstr = "cccc $errorflag\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
    if ( $errorflag == 1 ) {
      next;
    }

    if ( $batch_flag == 0 ) {
      &pidcheck();
      $batch_flag = 1;

      #&batchheader();
    }

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='locked',result=?,detailnum=?
	    where orderid=?
	    and trans_date>=?
	    and finalstatus='pending'
	    and username=?
            and accttype in ('savings','checking')
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
          and accttype in ('savings','checking')
dbEOM
    my @dbvalues = ( "$time$batchnum", "$detailnum", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    &batchdetail();

    my $printstr = "message: $message\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

    $processid = $$;
    my $hostnm = hostname;
    $hostnm =~ s/[^0-9a-zA-Z]//g;
    $processid = $processid . $hostnm;
    ( $status, $invoicenum, $response ) = &procutils::sendprocmsg( "$processid", "telecheck", "$username", "$orderid", "$message" );

    if ( $status ne "success" ) {
      if ( $status eq "failure" ) {
        $result{'MErrMsg'} = $response;
      }
      open( MAILERR, "| /usr/lib/sendmail -t" );
      print MAILERR "To: cprice\@plugnpay.com\n";
      print MAILERR "From: dcprice\@plugnpay.com\n";
      print MAILERR "Subject: telecheck - genfiles error\n";
      print MAILERR "\n";
      print MAILERR "username: $username\n";
      print MAILERR "orderid: $orderid\n";
      print MAILERR "filename: logs/$fileyear/$username$time$pid.txt\n\n";
      close MAILERR;
      exit;
    }

    &endbatch($response);
  }

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "genfiles.txt", "append", "", $checkinstr );
}

if ( !-e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  umask 0033;
  $checkinstr = "";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "genfiles.txt", "write", "", $checkinstr );
}

unlink "/home/pay1/batchfiles/$devprod/telecheck/batchfile.txt";

exit;

sub endbatch {
  my ($response) = @_;

  my $printstr = "response: $response\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$mytime recv: $response\n\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  $csn       = "";
  $respcode  = "";
  $auth_code = "";
  $status    = "";

  if ( $response =~ /^....TR/ ) {
    my $printstr = "kkkk\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
    my $myindex   = 0;
    my %dataarray = ();
    my $pairstr   = substr( $response, 6 );
    my (@pairs) = split( /\|/, $pairstr );
    foreach my $var (@pairs) {
      my $tag = substr( $var, 0, 4 );
      my $data = substr( $var, 4 );
      $dataarray{"$tag"} = $data;
      my $printstr = "$tag  $dataarray{$tag}\n";
      &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
    }

    $csn      = $dataarray{'0021'};
    $respcode = $dataarray{'0500'};
    $traceid  = $dataarray{'0503'};

    #my $auth_code = $dataarray{'0503'};
    $status   = $dataarray{'0504'};
    $datetime = $dataarray{'0511'};
    $shipid   = $dataarray{'05xx'};
    my $appcode = $dataarray{'0501'};

    if ( $respcode eq "" ) {
      $respcode = $appcode;
    }
  }

  my $printstr = "respcode: $respcode\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
  $err_msg = "$respcode: " . $errcode{"$respcode"};

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "orderid   $orderid\n";
  $logfilestr .= "respcode   $respcode\n";
  $logfilestr .= "err_msg   $err_msg\n";
  $logfilestr .= "result   $time$batchnum\n\n\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  my $printstr = "orderid   $orderid\n";
  $printstr .= "transseqnum   $transseqnum\n";
  $printstr .= "respcode   $respcode\n";
  $printstr .= "err_msg   $err_msg\n";
  $printstr .= "result   $time$batchnum\n\n\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  if ( $respcode =~ /^(OK|26)$/ ) {
    $orderidarray{"$orderid"} = 1;

    if ( $operation eq "return" ) {
      $batchretamt = $batchretamt + $transamt;
      $batchretcnt = $batchretcnt + 1;
    } else {
      $batchsalesamt = $batchsalesamt + $transamt;
      $batchsalescnt = $batchsalescnt + 1;
    }

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?
            where orderid=?
            and trans_date>=?
            and result=?
            and username=?
            and finalstatus='locked'
            and operation=?
            and accttype in ('savings','checking')
dbEOM
    my @dbvalues = ( "$time", "$orderid", "$onemonthsago", "$time$batchnum", "$username", "$operation" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='success',lastopstatus='success',lastoptime=?
            where orderid=?
            and lastoptime>=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and accttype in ('savings','checking')
dbEOM
    my @dbvalues = ( "$time", "$orderid", "$onemonthsagotime", "$username", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
  } elsif ( $err_msg ne "" ) {
    $err_msg = substr( $err_msg, 0, 118 );

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where orderid=?
            and trans_date>=?
            and username=?
            and accttype in ('savings','checking')
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
            and accttype in ('savings','checking')
dbEOM
    my @dbvalues = ( "$err_msg", "$orderid", "$onemonthsagotime" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    #open(MAILERR,"| /usr/lib/sendmail -t");
    #print MAILERR "To: cprice\@plugnpay.com\n";
    #print MAILERR "From: dcprice\@plugnpay.com\n";
    #print MAILERR "Subject: telecheck - FORMAT ERROR\n";
    #print MAILERR "\n";
    #print MAILERR "username: $username\n";
    #print MAILERR "result: format error\n\n";
    #print MAILERR "batchtransdate: $batchtransdate\n";
    #close MAILERR;
  } else {
    my $printstr = "respcode	$respcode unknown\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: telecheck - unkown error\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $resp\n";
    print MAILERR "file: $username$time$pid.txt\n";
    close MAILERR;
  }

}

sub batchheader {

  my $dbquerystr = <<"dbEOM";
          select batchnum
          from telecheck
          where username=?
dbEOM
  my @dbvalues = ("$username");
  ($batchnum) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = $batchnum + 1;
  if ( $batchnum >= 998 ) {
    $batchnum = 1;
  }

  my $dbquerystr = <<"dbEOM";
          update telecheck set batchnum=?
          where username=?
dbEOM
  my @dbvalues = ( "$batchnum", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

}

sub batchdetail {

  $tempamount = $amount;

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

    #$batchsalesamt = $batchsalesamt + $transamt;
    #$batchsalescnt = $batchsalescnt + 1;
    $filesalesamt = $filesalesamt + $transamt;
    $filesalescnt = $filesalescnt + 1;
  } else {

    #$batchretamt = $batchretamt + $transamt;
    #$batchretcnt = $batchretcnt + 1;
    $fileretamt = $fileretamt + $transamt;
    $fileretcnt = $fileretcnt + 1;
  }

  $batchcnt++;
  $batchreccnt++;
  $recseqnum++;

  @bd = ();

  $bd[0] = 'TI';                                             # packet type identifier (2a)
  $bd[1] = '0001' . $merchant_id . "\|";                     # telecheck merchant id (8n)
  $bd[2] = '0062' . "xxxx 20110714 xxxx SNNK 000" . "\|";    # version control (67a)
  $bd[3] = '0014' . "$orderid" . "\|";                       # echo data (50a)

  my $traceid = substr( $auth_code, 6, 22 );
  $bd[4] = '0503' . "$traceid" . "\|";                       # telecheck trace id (22a)
  my $storenum = substr( $auth_code, 51, 35 );
  $storenum =~ s/ //g;
  $bd[5] = '0008' . "$storenum$orderid" . "\|";              # merchant trace id (50a)

  $tcode = "A";                                              # A = accepted
  if ( $operation eq "return" ) {
    $tcode = "R";
  }

  #elsif ($reauthstatus eq "success") {
  #  $tcode = "C";
  #}
  $bd[6] = '0101' . "$tcode" . "\|";    # transaction type (1a)

  if ( $operation eq "return" ) {

    #if (($operation eq "return") || ($reauthstatus eq "success")) {
    my $transamount = sprintf( "%d", ( substr( $amount, 4 ) * 100 ) + .0001 );
    $bd[7] = '0006' . "$transamount" . "\|";    # total check amount (9n)
  }

  my $datetime = substr( $auth_code, 28, 12 );
  $bd[8] = '0015' . "$datetime" . "\|";         # merchant date time MMDDYYYYHHMM (12n)

  my $shipid = substr( $auth_code, 40, 10 );
  if ( $shipid != " " x 10 ) {
    $bd[9] = '0510' . "$shipid" . "\|";         # delay ship id (10n)
  }

  $message = "";
  foreach $var (@bd) {
    $message = $message . $var;
  }
  chop $message;

  my $tcpheader = length($message);
  $tcpheader = substr( "0" x 4 . $tcpheader, -4, 4 );
  $message = $tcpheader . $message;

  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$orderid $operation\n";
  $logfilestr .= "$mytime send: $message\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
}

sub processmessage {
  my (@msg) = @_;

  my $message = "";
  my $indent  = 0;
  foreach my $var (@msg) {
    if ( $var =~ /^<\/.*>/ ) {
      $indent--;
    }
    if ( $var eq "" ) {
      next;
    }
    if ( $var =~ /></ ) {
      next;
    }
    if ( ( $var !~ /soap/ ) && ( $var !~ /i0/ ) ) {
      $var =~ s/<([^i\?][^0].*)>(.*)<\//<i0:$1>$2<\/i0:/;
      $var =~ s/<([^i\?\/].*)>/<i0:$1>/;
      $var =~ s/<\/([^i].*)>/<\/i0:$1>/;
    }

    #$message = $message . $var;
    $message = $message . " " x $indent . $var;
    if ( ( $var !~ /\// ) && ( $var != /<?/ ) ) {
      $indent++;
    }
    if ( $indent < 0 ) {
      $indent = 0;
    }
  }

  return $message;
}

sub processresponse {
  my ($data) = @_;

  $data =~ s/\r//g;
  $data =~ s/\n/ /g;
  $data =~ s/> *</>;;;</g;
  my @tmpfields = split( /;;;/, $data );
  my %temparray = ();
  my $levelstr  = "";
  foreach my $var (@tmpfields) {
    if ( $var =~ /<(.+)>(.*)</ ) {
      my $var2 = $1;
      my $val2 = $2;
      $var2 =~ s/ .*$//;
      $val2 =~ s/\&....;//g;
      if ( $temparray{"$levelstr$var2"} eq "" ) {
        $temparray{"$levelstr$var2"} = $val2;
      } else {
        $temparray{"$levelstr$var2"} = $temparray{"$levelstr$var2"} . "," . $val2;
      }
    } elsif ( $var =~ /<\/(.+)>/ ) {
      $levelstr =~ s/,[^,]*?,$/,/;
    } elsif ( ( $var =~ /<(.+)>/ ) && ( $var !~ /<\?/ ) && ( $var !~ /\/>/ ) ) {
      my $var2 = $1;
      $var2 =~ s/ .*$//;
      $levelstr = $levelstr . $var2 . ",";
    }
  }

  foreach my $key ( sort keys %temparray ) {
    my $printstr = "aa $key    bb $temparray{$key}\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
  }

  return %temparray;

}

sub printrecord {
  my ($printmessage) = @_;

  $temp = length($printmessage);
  my $printstr = "$temp\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
  ($message2) = unpack "H*", $printmessage;
  my $printstr = "$message2\n\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  $message1 = $printmessage;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;

  #print "$message1\n$message2\n\n";
}

sub errorchecking {
  my $errmsg = "";

  # check for 0 amount
  if ( $amount eq "usd 0.00" ) {
    $errmsg = "amount = 0.00";
  }
  my $printstr = "kkkk $errmsg\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  if ( $errmsg ne "" ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where username=?
            and orderid=?
            and finalstatus='pending'
            and accttype in ('checking','savings')
dbEOM
    my @dbvalues = ( "$errmsg", "$username", "$orderid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and username=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and accttype in ('checking','savings')
dbEOM
    my @dbvalues = ( "$errmsg", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

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
            and accttype in ('savings','checking')
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
            and accttype in ('savings','checking')
dbEOM
  my @dbvalues = ( "$errmsg", "$orderid", "$username", "$onemonthsagotime" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

}

sub pidcheck {
  my $chkline = &procutils::fileread( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "pid.txt" );
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $printstr .= "$pidline\n";
    $printstr .= "$chkline\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: telecheck - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

