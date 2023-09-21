#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;
use smpsutils;
use planetpay;

$devprod = "logs";

# plan etpay  version 2.0

if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'planetpay/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: planetpay - genfiles already running\n";
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
&procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay", "pid.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my $chkline = &procutils::fileread( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay", "pid.txt" );
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
  $printstr .= "$pidline\n";
  $printstr .= "$chkline\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: planetpay - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

my $checkuser = &procutils::fileread( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay", "genfiles.txt" );
chop $checkuser;

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>='$checkuser'";
}

#$checkstring = "and t.username='aaaa'";
#$checkstring = "and t.username in ('aaaa','aaaa')";

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

if ( !-e "/home/pay1/batchfiles/$devprod/planetpay/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/planetpay/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/planetpay/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/planetpay/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/planetpay/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/planetpay/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/planetpay/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/planetpay/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/planetpay/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/planetpay/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: planetpay - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/planetpay/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;

# xxxx
#and t.username='paragont'
# homeclip should not be batched, it shares the same account as golinte1
#and (length(o.auth_code)='8' or length(o.auth_code) > 160)
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
        and o.processor='planetpay'
        and o.lastoptime>=?
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user $usercount $usertdate\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

foreach $username ( sort @userarray ) {
  if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
    unlink "/home/pay1/batchfiles/$devprod/planetpay/batchfile.txt";
    last;
  }

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};

  my $printstr = "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

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
        select terminalnum,industrycode
        from planetpay
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $terminalnum, $industrycode ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $terminalnum eq "" ) {
    $terminalnum = "00000001";
  }

  my $printstr = "$username $status\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  if ( $status ne "live" ) {
    next;
  }

  if ( $currency eq "" ) {
    $currency = "usd";
  }

  my $printstr = "aaaa $starttransdate $onemonthsagotime $username\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  $batch_flag = 0;
  $netamount  = 0;
  $hashtotal  = 0;
  $batchcnt   = 1;
  $recseqnum  = 0;

  %orderidarray    = ();
  %chkorderidarray = ();
  %inplanetarray   = ();
  %inoplogarray    = ();

  #and (length(auth_code)='8' or length(auth_code) > 160)
  my $dbquerystr = <<"dbEOM";
        select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,
               auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,origamount,
               forceauthstatus
        from operation_log
        where trans_date>=?
        and lastoptime>=?
        and username=?
        and lastopstatus in ('pending')
        and lastop IN ('auth','postauth','return','forceauth')
        and (voidstatus is NULL or voidstatus ='')
        and (accttype is NULL or accttype ='' or accttype='credit')
        order by orderid
dbEOM
  my @dbvalues = ( "$starttransdate", "$onemonthsagotime", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 16 ) {
    ( $orderid, $operation, $trans_date, $trans_time, $enccardnumber, $enclength, $exp, $amount, $auth_code, $avs_code, $refnumber, $finalstatus, $cvvresp, $transflags, $origamount, $forceauthstatus ) =
      @sthtransvalarray[ $vali .. $vali + 15 ];

    if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
      unlink "/home/pay1/batchfiles/$devprod/planetpay/batchfile.txt";
      last;
    }

    if ( ( $proc_type eq "authcapture" ) && ( $operation eq "postauth" ) ) {
      next;
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    my $printstr = "$orderid $operation $auth_code $refnumber\n";
    &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "planetpay", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $errorflag = &errorchecking();
    my $printstr = "cccc $errorflag\n";
    &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
    if ( $errorflag == 1 ) {
      next;
    }

    if ( $batch_flag == 0 ) {
      &pidcheck();
      $batch_flag = 1;
      &batchheader();
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

    ( $message, $tcode ) = &batchdetail();

    $response = &sendmessage( $message, $tcode );

    &endbatch($response);
  }

  if ( $batchcnt > 1 ) {
    %errorderid = ();
    $detailnum  = 0;

    &sendbatchstatus();
    my $chkresponse = &sendbatchstatusdetail();
    if ( ( $batchsalesamt == $hostsalesamt )
      && ( $batchsalescnt == $hostsalescnt )
      && ( $batchretamt == $hostrefundsamt )
      && ( $batchretcnt == $hostrefundscnt ) ) {

      #&sendbatchclose();
    } else {

      #&sendbatchstatusdetail();
      open( MAILERR, "| /usr/lib/sendmail -t" );
      print MAILERR "To: cprice\@plugnpay.com\n";
      print MAILERR "From: dcprice\@plugnpay.com\n";
      print MAILERR "Subject: planetpay - genfiles error\n";
      print MAILERR "\n";
      print MAILERR "username: $username\n";
      print MAILERR "batchnum: $batchnum\n";
      print MAILERR "filename: logs/$fileyear/$username$time$pid.txt\n\n";
      print MAILERR "Batch amounts do not match:\n";
      print MAILERR "                 Our numbers    Their numbers\n";
      print MAILERR "batchsalesamt: $batchsalesamt  $hostsalesamt\n";
      print MAILERR "batchsalescnt: $batchsalescnt  $hostsalescnt\n";
      print MAILERR "batchretamt: $batchretamt  $hostrefundsamt\n";
      print MAILERR "batchretcnt: $batchretcnt  $hostrefundscnt\n";
      close MAILERR;
    }

    if ( $chkresponse eq "success" ) {
      &sendbatchclose();
    }
  }

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay", "genfiles.txt", "write", "", $checkinstr );
}

if ( !-e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  umask 0033;
  $checkinstr = "";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay", "genfiles.txt", "write", "", $checkinstr );
}

unlink "/home/pay1/batchfiles/$devprod/planetpay/batchfile.txt";

exit;

sub endbatch {
  my ($response) = @_;

  $data = $response;
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
    &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  }

  #$auth_code = $temparray{'EngineDocList,EngineDoc,OrderFormDoc,Transaction,AuthCode'};

  $tcoderesponse = $tcode . "Response";
  $tcoderesult   = $tcode . "Result";
  $refnumber     = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseDetail,RetrievalReferenceNumber"};
  $respcode      = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseDetail,ResponseCode"};
  $errmsg        = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseDetail,ResponseMessage"};
  if ( $respcode eq "" ) {
    $refnumber = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseInfo,ResponseDetail,RetrievalReferenceNumber"};
    $respcode  = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseInfo,ResponseDetail,ResponseCode"};
    $errmsg    = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseInfo,ResponseDetail,ResponseMessage"};
  }

  $tmpfilestr = "";
  $tmpfilestr .= "$tempamount      $oid    $refnumber      $operation\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay", "scriptresults2.txt", "append", "", $tmpfilestr );

  $err_msg = "";
  if ( $respcode ne "" ) {
    $err_msg = "$respcode: $errmsg";
  }

  if ( $transflags =~ /multicurrency/ ) {
    if ( $operation eq "return" ) {
      $dcccurrency = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseInfo,ResponseTransactionDetail,TransactionCurrencyCode"};
      $dccamount   = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseInfo,ResponseTransactionDetail,TransactionAmount"};
    } else {
      $dcccurrency = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseTransactionDetail,TransactionCurrencyCode"};
      $dccamount   = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseTransactionDetail,TransactionAmount"};
    }
    $newdccinfo = "$dcccurrency,$dccamount";
    $newdccinfo = substr( $newdccinfo . " " x 20, 0, 20 );
    $auth_code  = substr( $auth_code, 0, 187 ) . $newdccinfo;
  }

  if ( $transflags =~ /multicurrency/ ) {
    $newdccinfo = substr( $auth_code, 187, 20 );    # get the usd amount returned at settlement for multicurrency
    ( $newcurrency, $transamt ) = split( /,/, $newdccinfo );

    # transamt is used to add up batch totals
  }

  my $printstr = "pass: $planetpay::pass\n";
  $printstr .= "err_msg: $planetpay::err_msg\n";
  $printstr .= "refnum: $planetpay::refnum\n";
  $printstr .= "dccexponent: $dccexponent\n";
  $printstr .= "dccrate: $dccrate\n";
  $printstr .= "dccamount: $dccamount\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  #$respcode = $temparray{'XML,REQUEST,RESPONSE,RESULT'};
  #my $code = $temparray{'XML,REQUEST,RESPONSE,ERROR,CODE'};
  #my $message = $temparray{'XML,REQUEST,RESPONSE,ERROR,MESSAGE'};
  #$err_msg = "$code: $message";
  #my $statusid = $temparray{'XML,REQUEST,RESPONSE,ROW,STATUSID'};

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "orderid   $orderid\n";
  $logfilestr .= "respcode   $respcode\n";
  $logfilestr .= "err_msg   $err_msg\n";
  $logfilestr .= "result   $time$batchnum\n\n\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  my $printstr = "orderid   $orderid\n";
  $printstr .= "transseqnum   $transseqnum\n";
  $printstr .= "respcode   $respcode\n";
  $printstr .= "err_msg   $err_msg\n";
  $printstr .= "result   $time$batchnum\n\n\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  if ( $respcode eq "00" ) {
    $orderidarray{"$orderid"} = 1;

    if ( $operation eq "return" ) {
      $batchretamt = $batchretamt + $transamt;
      $batchretcnt = $batchretcnt + 1;
    } else {
      $batchsalesamt = $batchsalesamt + $transamt;
      $batchsalescnt = $batchsalescnt + 1;
    }

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?,auth_code=?,refnumber=?
            where orderid=?
            and trans_date>=?
            and result=?
            and username=?
            and finalstatus='locked'
            and operation=?
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$auth_code", "$refnumber", "$orderid", "$onemonthsago", "$time$batchnum", "$username", "$operation" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='success',lastopstatus='success',lastoptime=?,auth_code=?,refnumber=?
            where orderid=?
            and lastoptime>=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$auth_code", "$refnumber", "$orderid", "$onemonthsagotime", "$username", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
  } elsif ( $err_msg ne "" ) {
    $err_msg = substr( $err_msg, 0, 118 );

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
    #print MAILERR "Subject: planetpay - FORMAT ERROR\n";
    #print MAILERR "\n";
    #print MAILERR "username: $username\n";
    #print MAILERR "result: format error\n\n";
    #print MAILERR "batchtransdate: $batchtransdate\n";
    #close MAILERR;
  } else {
    my $printstr = "respcode	$respcode unknown\n";
    &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: planetpay - unkown error\n";
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
          from planetpay
          where username=?
dbEOM
  my @dbvalues = ("$username");
  ($batchnum) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = $batchnum + 1;
  if ( $batchnum >= 998 ) {
    $batchnum = 1;
  }

  my $dbquerystr = <<"dbEOM";
          update planetpay set batchnum=?
          where username=?
dbEOM
  my @dbvalues = ( "$batchnum", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

}

sub batchdetail {

  my $tcode = "";

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

  $dccinfo = substr( $auth_code, 115, 52 );
  my $printstr = "dccinfo: $dccinfo\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  $dccinfo =~ s/ +$//g;
  if ( length($dccinfo) < 3 ) {
    $dccinfo = "";
  }

  @bd = ();

  $origoperation = "";
  if ( ( $operation eq "postauth" ) && ( $forceauthstatus eq "success" ) ) {
    $origoperation = "forceauth";
  }

  $eci = substr( $auth_code, 178, 1 );
  $eci =~ s/ //g;
  $posentry = substr( $auth_code, 179, 3 );
  $posentry =~ s/ //g;
  $poscond = substr( $auth_code, 182, 2 );
  $poscond =~ s/ //g;
  $postermcap = substr( $auth_code, 184, 1 );
  $postermcap =~ s/ //g;
  $cardholderid = substr( $auth_code, 185, 1 );
  $cardholderid =~ s/ //g;
  $magstripetrack = substr( $auth_code, 186, 1 );
  $magstripetrack =~ s/ //g;

  if ( $operation eq "postauth" ) {
    $bd[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    $bd[1] =
      "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:i0=\"http://www.planetpayment.net\">\n";

    $bd[2] = "<soap:Body>\n";

    $tcode = "Settlement";
    if ( $transflags =~ /multicurrency/ ) {
      $tcode = "SettlementMCP";
    } elsif ( $dccinfo ne "" ) {
      $tcode = "SettlementDCC";
    }
    $bd[3] = "<i0:$tcode>\n";
    $bd[4] = "<i0:req>\n";

    $bd[5] = "<AccessInfo>\n";

    my $userid = $merchant_id;

    #if ($username !~ /skyhawket1|intelstrar1/) {
    #  $userid = substr($userid,-12,12);
    #}
    $bd[6] = "<User>$userid</User>\n";

    if ( $username eq "testplanet" ) {
      $bd[7] = "<Password>f0I!Rzh[A#1-</Password>\n";
    } else {
      $bd[7] = "<Password>6g4\@B2c</Password>\n";
    }
    $bd[8] = "<ApplicationID>DirectLinkPlanet</ApplicationID>\n";
    $terminalnum = substr( "0" x 8 . $terminalnum, -8, 8 );
    $bd[9] = "<TerminalID>$terminalnum</TerminalID>\n";
    my $ipaddress = $ENV{'REMOTE_ADDR'};
    $ipaddress = "69.18.198.140";
    $bd[10]    = "<ClientIPAddress>$ipaddress</ClientIPAddress>\n";
    $bd[11]    = "</AccessInfo>\n";

    $bd[12] = "<i0:SettleInfo>\n";

    #$bd[13] = "<i0:ExtensionData></i0:ExtensionData>\n";

    $oid = substr( $orderid, -14, 14 );
    $bd[14] = "<i0:RequestIdentifier>$oid</i0:RequestIdentifier>\n";
    $bd[15] = "<i0:OriginalRequestIdentifier>$oid</i0:OriginalRequestIdentifier>\n";
    $bd[16] = "<i0:OriginalRetrievalReferenceNumber>$refnumber</i0:OriginalRetrievalReferenceNumber>\n";

    ( $mcpcurrency, $amount ) = split( / /, $amount );
    $currency2 = $currency;
    if ( $transflags =~ /multicurrency/ ) {
      $currency2 = $mcpcurrency;
    }
    $currency2 =~ tr/a-z/A-Z/;
    my $exponent = $isotables::currencyUSD2{$currency2};
    $currency2 = $isotables::currencyUSD840{$currency2};
    $amount = sprintf( "%d", ( $amount * ( 10**$exponent ) ) + .0001 );

    #$amount = sprintf("%.2f", $amount + .0001);

    $bd[17] = "<i0:TransactionAmount>$amount</i0:TransactionAmount>\n";

    $origamount = substr( $auth_code, 103, 12 );
    $origamount =~ s/ //g;
    if ( $origamount == 0 ) {
      $origamount = "";
    }
    $bd[18] = "<i0:OriginalTransactionAmount>$origamount</i0:OriginalTransactionAmount>\n";
    $bd[19] = "<i0:TotalAuthorizationAmounts>$origamount</i0:TotalAuthorizationAmounts>\n";

    $tax = substr( $auth_code, 55, 8 );
    $tax =~ s/ //g;
    if ( $tax == 0 ) {
      $tax = "";
    }
    $bd[20] = "<i0:TransactionSalesTaxAmount>$tax</i0:TransactionSalesTaxAmount>\n";

    if ( $industrycode eq "restaurant" ) {
      $gratuity = substr( $auth_code, 91, 12 );
      $gratuity =~ s/ //g;
      if ( $gratuity == 0 ) {
        $gratuity = "";
      }
      $bd[21] = "<i0:TransactionTipAmount>$gratuity</i0:TransactionTipAmount>\n";
    }
    $bd[22] = "<i0:TransactionCurrencyCode>$currency2</i0:TransactionCurrencyCode>\n";

    $bd[23] = "<i0:RateLookupRequestIdentifier></i0:RateLookupRequestIdentifier>\n";
    $bd[24] = "<i0:RateLookupRetrievalReferenceNumber></i0:RateLookupRetrievalReferenceNumber>\n";
    $authcode = substr( $auth_code, 0, 6 );
    $bd[25] = "<i0:AuthorizationNumber>$authcode</i0:AuthorizationNumber>\n";

    $bd[26] = "<i0:AdditionalMarketDataSettle>\n";

    $bd[27] = "<i0:General>\n";

    #$bd[28] = "<i0:ExtensionData></i0:ExtensionData>\n";
    #$bd[29] = "<i0:ChargeDescription></i0:ChargeDescription>\n";		# amex

    $ponumber = substr( $auth_code, 63, 25 );
    $ponumber =~ s/ //g;
    $bd[30] = "<i0:MarketSpecificData>$ponumber</i0:MarketSpecificData>\n";
    $refid = substr( $orderid, -17, 17 );
    $bd[31] = "<i0:MarketPurchaseReferenceID>$refid</i0:MarketPurchaseReferenceID>\n";

    #$tax = substr($auth_code,55,8);
    #$tax =~ s/ //g;
    #$bd[32] = "<i0:LocalTaxAmount>$tax</i0:LocalTaxAmount>\n";
    #$bd[33] = "<i0:ItemDescription></i0:ItemDescription>\n";
    #$bd[34] = "<i0:ItemDescription2></i0:ItemDescription2>\n";
    $shipzip = substr( $auth_code, 156, 9 );
    $shipzip =~ s/ //g;
    $bd[35] = "<i0:DestinationOrCustomerPostalCode>$shipzip</i0:DestinationOrCustomerPostalCode>\n";
    $bd[36] = "</i0:General>\n";

    #if ($industrycode eq "restaurant") {
    #  $bd[37] = "<i0:RestaurantBase>\n";
    #  #$bd[38] = "<i0:ExtensionData></i0:ExtensionData>\n";
    #  $bd[39] = "<i0:RestaurantID>FOOD-BEV</i0:RestaurantID>\n";
    #  $gratuity = substr($auth_code,91,12);
    #  $gratuity =~ s/ //g;

    #  $foodamt = $amount - $gratuity - $tax;
    #  $bd[40] = "<i0:RestaurantFoodAmount>$foodamt</i0:RestaurantFoodAmount>\n";
    #  $bd[41] = "<i0:RestaurantTipAmount>$gratuity</i0:RestaurantTipAmount>\n";
    #  $bd[42] = "</i0:RestaurantBase>\n";
    #}

    #if ($industrycode eq "retail") {
    #  $bd[43] = "<i0:Retail>\n";
    #  #$bd[44] = "<i0:ExtensionData></i0:ExtensionData>\n";
    #  $bd[45] = "<i0:DeptName></i0:DeptName>\n";
    #  $bd[46] = "<i0:ItemDesc></i0:ItemDesc>\n";
    #  $bd[47] = "<i0:ItemQuantity></i0:ItemQuantity>\n";
    #  $bd[48] = "<i0:ItemAmount></i0:ItemAmount>\n";
    #  $bd[49] = "<i0:RetailItemAdditional></i0:RetailItemAdditional>\n";
    #  $bd[50] = "</i0:Retail>\n";
    #}

    if ( $transflags =~ /multicurrency/ ) {
      $dccinfo = substr( $auth_code, 115, 52 );
      $dccinfo =~ s/ +$//g;

      ( $dccoptout, $dccamount, $dcccurrency, $dccrate, $dccexponent, $dccdate, $dcctime ) = split( /,/, $dccinfo );

      $bd[51] = "<i0:SettleMCPInfo>\n";

      #$bd[52] = "<i0:ExtensionData></i0:ExtensionData>\n";
      $bd[53] = "<i0:MCPAmount>$dccamount</i0:MCPAmount>\n";
      $bd[54] = "<i0:MCPCurrencyCode>$dcccurrency</i0:MCPCurrencyCode>\n";
      $bd[55] = "<i0:MCPLocalTransactionDate>$dccdate</i0:MCPLocalTransactionDate>\n";
      $bd[56] = "<i0:MCPLocalTransactionTime>$dcctime</i0:MCPLocalTransactionTime>\n";
      $bd[57] = "<i0:MCPTransactionConversionRate>$dccrate</i0:MCPTransactionConversionRate>\n";
      $bd[58] = "<i0:MCPTransactionConversionExponent>$dccexponent</i0:MCPTransactionConversionExponent>\n";
      $bd[59] = "<i0:MCPRateSourceDesignator>Planet</i0:MCPRateSourceDesignator>\n";
      $bd[60] = "</i0:SettleMCPInfo>\n";
    } elsif ( $dccinfo ne "" ) {
      $dccinfo = substr( $auth_code, 115, 52 );
      $dccinfo =~ s/ +$//g;

      ( $dccoptout, $dccamount, $dcccurrency, $dccrate, $dccexponent, $dccdate, $dcctime ) = split( /,/, $dccinfo );

      $bd[51] = "<i0:SettleDCCInfo>\n";
      $bd[53] = "<i0:DCCCardHolderTransactionAmount>$dccamount</i0:DCCCardHolderTransactionAmount>\n";
      $bd[54] = "<i0:DCCCardHolderTransactionTipAmount></i0:DCCCardHolderTransactionTipAmount>\n";
      $bd[55] = "<i0:DCCCardHolderCurrencyCode>$dcccurrency</i0:DCCCardHolderCurrencyCode>\n";
      $bd[56] = "<i0:DCCLocalTransactionDate>$dccdate</i0:DCCLocalTransactionDate>\n";
      $bd[57] = "<i0:DCCLocalTransactionTime>$dcctime</i0:DCCLocalTransactionTime>\n";
      $bd[58] = "<i0:DCCTransactionConversionRate>$dccrate</i0:DCCTransactionConversionRate>\n";
      $bd[59] = "<i0:DCCTransactionConversionExponent>$dccexponent</i0:DCCTransactionConversionExponent>\n";
      $bd[60] = "<i0:DCCRateSourceDesignator>Planet</i0:DCCRateSourceDesignator>\n";
      $bd[61] = "</i0:SettleDCCInfo>\n";
    }

    $bd[62] = "</i0:AdditionalMarketDataSettle>\n";

    $bd[63] = "</i0:SettleInfo>\n";
    $bd[64] = "</i0:req>\n";
    $bd[65] = "</i0:$tcode>\n";

    $bd[66] = "</soap:Body>\n";
    $bd[67] = "</soap:Envelope>\n";

  } elsif ( $operation eq "return" ) {

    $bd[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    $bd[3] =
      "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:i0=\"http://www.planetpayment.net\">\n";

    $bd[8] = "<soap:Body>\n";

    $tcode = "Refund";
    if ( $transflags =~ /multicurrency/ ) {
      $tcode = "RefundMCP";
    } elsif ( $transflags =~ /dcc/ ) {
      $tcode = "RefundDCC";
    }
    $bd[13] = "<i0:$tcode>\n";
    $bd[14] = "<i0:req>\n";

    $bd[15] = "<AccessInfo>\n";

    my $userid = $merchant_id;

    #if ($username !~ /skyhawket1|intelstrar1/) {
    #  $userid = substr($userid,-12,12);
    #}
    $bd[16] = "<User>$userid</User>\n";

    if ( $username eq "testplanet" ) {
      $bd[17] = "<Password>f0I!Rzh[A#1-</Password>\n";
    } else {
      $bd[17] = "<Password>6g4\@B2c</Password>\n";
    }
    $bd[18] = "<ApplicationID>DirectLinkPlanet</ApplicationID>\n";
    $terminalnum = substr( "0" x 8 . $terminalnum, -8, 8 );
    $bd[19] = "<TerminalID>$terminalnum</TerminalID>\n";
    my $ipaddress = $ENV{'REMOTE_ADDR'};
    $ipaddress = "69.18.198.140";
    $bd[20]    = "<ClientIPAddress>$ipaddress</ClientIPAddress>\n";
    $bd[21]    = "</AccessInfo>\n";

    $bd[22] = "<CardInfo>\n";

    if ( $refnumber ne "" ) {
      $oid = substr( $orderid, -14, 14 );
      $bd[23] = "<OriginalRetrievalReferenceNumber>$oid</OriginalRetrievalReferenceNumber>\n";
      $bd[24] = "<OriginalRequestIdentifier>$refnumber</OriginalRequestIdentifier>\n";
    }

    #if ($magstripetrack !~ /1|2/) {
    my $monthexp = substr( $exp, 0, 2 );
    my $yearexp  = substr( $exp, 3, 2 );
    $bd[25] = "<CardAccountNumber>$cardnumber</CardAccountNumber>\n";
    $bd[26] = "<CardExpirationMonth>$monthexp</CardExpirationMonth>\n";
    $bd[27] = "<CardExpirationYear>$yearexp</CardExpirationYear>\n";

    #if ($planetpay::datainfo{'issuenum'} ne "") {
    #$bd[28] = "<CardIssueNumber>xxxx</CardIssueNumber>\n";
    #$bd[29] = "<StartDateMonth>xxxx</StartDateMonth>\n";
    #$bd[30] = "<StartDateYear>xxxx</StartDateYear>\n";
    #}
    #}

    my $posentry = substr( $authcode, 179, 3 );
    $posentry =~ s/ //g;
    my $poscond = substr( $authcode, 182, 2 );
    $poscond =~ s/ //g;
    my $postermcap = substr( $authcode, 184, 1 );
    $postermcap =~ s/ //g;
    my $cardholderid = substr( $authcode, 185, 1 );
    $cardholderid =~ s/ //g;

    if ( $operation eq "return" ) {
      $posentry = "010";
      if ( $magstripetrack =~ /^(1|2)$/ ) {
        $posentry = "900";
      }

      $poscond = "59";
      if ( $magstripetrack eq "0" ) {
        $poscond = "71";
      } elsif ( $industrycode =~ /retail|restaurant/ ) {
        $poscond = "00";
      } elsif ( $transflags =~ /moto/ ) {
        $poscond = "08";
      }

      $postermcap = "0";
      if ( $industrycode =~ /retail|restaurant/ ) {
        $postermcap = "2";
      }

      $cardholderid = "4";
      if ( ( $transflags !~ /moto/ ) && ( $industrycode =~ /retail|restaurant/ ) ) {
        $cardholderid = "1";
      }
    }

    $bd[32] = "<POSEntryMode>$posentry</POSEntryMode>\n";
    $bd[33] = "<POSConditionCode>$poscond</POSConditionCode>\n";
    $bd[34] = "<POSTerminalCapability>$postermcap</POSTerminalCapability>\n";
    $bd[35] = "<CardholderIdMethod>$cardholderid</CardholderIdMethod>\n";

    if ( ( $transflags !~ /moto/ ) && ( $industrycode !~ /retail|restaurant/ ) ) {
      $eci = substr( $auth_code, 165, 1 );
      if ( ( $operation eq "return" ) || ( ( $origoperatoin eq "forceauth" ) && ( $operation eq "postauth" ) ) ) {
        if ( $planetpay::datainfo{'transflags'} =~ /recurring/ ) {
          $eci = "2";
        } elsif ( $planetpay::datainfo{'transflags'} =~ /install/ ) {
          $eci = "3";
        } elsif ( $planetpay::datainfo{'transflags'} =~ /moto/ ) {
          $eci = "1";
        } else {
          $eci = "7";
        }
      }
      $bd[36] = "<ECI>$eci</ECI>\n";
      $bd[37] = "<ECIDirectMktgOrderNumber>$orderid</ECIDirectMktgOrderNumber>\n";
    }

    #if ($planetpay::datainfo{'commcardtype'} ne "") {
    #  $bd[10] = "<PCard>xxxx</PCard>\n";
    #}
    #$bd[10] = "<AdditionalMarketData>xxxx</AdditionalMarketData>\n";

    $bd[50] = "</CardInfo>\n";

    $oid = substr( $orderid, -14, 14 );
    if ( $refnumber ne "" ) {
      $bd[51] = "<OriginalRequestIdentifier>$oid</OriginalRequestIdentifier>\n";
      $bd[52] = "<OriginalRetrievalReferenceNumber>$refnumber</OriginalRetrievalReferenceNumber>\n";
    }

    $bd[53] = "<TransactionInfo>\n";
    $bd[54] = "<RequestIdentifier>$oid</RequestIdentifier>\n";

    #$bd[55] = "<RetrievalReferenceNumber>xxxx</RetrievalReferenceNumber>\n";

    ( $d1, $amount ) = split( / /, $amount );
    $currency2 = $currency;
    $currency2 =~ tr/a-z/A-Z/;
    my $exponent = $isotables::currencyUSD2{$currency2};
    $currency2 = $isotables::currencyUSD840{$currency2};
    $amount = sprintf( "%d", ( $amount * ( 10**$exponent ) ) + .0001 );
    my $printstr = "currency: $currency  $currency2\n";
    &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

    #if ($transflags =~ /multicurrency/) {
    #  ($currency,$amount) = split(/ /,$amount);
    #  $currency =~ tr/a-z/A-Z/;
    #  $exponent = $isotables::currencyUSD2{$currency};
    #}

    $currencycode = $isotables::currencyUSD840{$currency};

    if ( $transflags !~ /multicurrency/ ) {
      $bd[56] = "<TransactionAmount>$amount</TransactionAmount>\n";

      #$bd[57] = "<TransactionSalesTaxAmount>xxxx</TransactionSalesTaxAmount>\n";
      #$bd[58] = "<TransactionTipAmount>xxxx</TransactionTipAmount>\n";
      #$bd[59] = "<TransactionSurchargeAmount>xxxx</TransactionSurchargeAmount>\n";
      $bd[60] = "<TransactionCurrencyCode>$currency2</TransactionCurrencyCode>\n";
    }
    $bd[61] = "</TransactionInfo>\n";

    #if ((($transflags !~ /recurring/) && ($industrycode !~ /^(retail|restaurant|grocery)$/))
    #      || (($industrycode =~ /^(retail|restaurant|grocery)$/)
    #                     && (($magstripetrack eq "0") || ($magstripetrack eq "")))) {
    #  $bd[62] = "<BillingAndShippingInfo>\n";
    #  $bd[63] = "<BillingAddress>$card_address</BillingAddress>\n";
    #  $bd[64] = "<BillingPostalCode>$card_zip</BillingPostalCode>\n";
    #  $bd[65] = "</BillingAndShippingInfo>\n";
    #}

    # extramarketdata
    #$bd[66] = "<MerchantInfo>\n";
    #$bd[67] = "</MerchantInfo>\n";

    #$bd[68] = "<AuthorizationNumber>xxxx</AuthorizationNumber>\n";

    if ( $transflags =~ /multicurrency/ ) {

      #($currency,$amount) = split(/ /,$amount);
      #$currency =~ tr/a-z/A-Z/;
      #$exponent = $isotables::currencyUSD2{$currency};

      $dccinfo = substr( $auth_code, 115, 52 );
      $dccinfo =~ s/ +$//g;

      ( $dccoptout, $dccamount, $dcccurrency, $dccrate, $dccexponent, $dccdate, $dcctime ) = split( /,/, $dccinfo );

      $bd[69] = "<MCPInfo>\n";
      $bd[70] = "<MCPAmount>$dccamount</MCPAmount>\n";
      $bd[71] = "<MCPCurrencyCode>$dcccurrency</MCPCurrencyCode>\n";
      my $mcprefnumber = substr( $auth_code, 207, 20 );
      $mcprefnumber =~ s/ //g;
      if ( ( $transflags =~ /multicurrency/ ) && ( $operation eq "return" ) ) {
        $bd[72] = "<MCPRetrievalReferenceNumber>$mcprefnumber</MCPRetrievalReferenceNumber>\n";
      }
      $bd[73] = "</MCPInfo>\n";
    } else {
      $dccinfo = substr( $auth_code, 115, 52 );
      $dccinfo =~ s/ +$//g;
      if ( length($dccinfo) > 3 ) {
        ( $dccoptout, $dccamount, $dcccurrency, $dccrate, $dccexponent, $dccdate, $dcctime ) = split( /,/, $dccinfo );
        my $printstr = "dccinfo: $dccinfo\n";
        &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

        $bd[69] = "<i0:DCCInfo>\n";
        $bd[70] = "<i0:DCCCardHolderTransactionAmount>$dccamount</i0:DCCCardHolderTransactionAmount>\n";

        #$bd[76] = "<i0:DCCCardHolderTransactionTipAmount></i0:DCCCardHolderTransactionTipAmount>\n";
        $bd[71] = "<i0:DCCCardHolderCurrencyCode>$dcccurrency</i0:DCCCardHolderCurrencyCode>\n";
        $bd[72] = "<DCCRetrievalReferenceNumber>$refnumber</DCCRetrievalReferenceNumber>\n";

        #$bd[79] = "<i0:DCCLocalTransactionDate>$dccdate</i0:DCCLocalTransactionDate>\n";
        #$bd[79] = "<i0:DCCLocalTransactionTime>$dcctime</i0:DCCLocalTransactionTime>\n";
        $bd[73] = "<i0:DCCTransactionConversionRate>$dccrate</i0:DCCTransactionConversionRate>\n";
        $bd[74] = "<i0:DCCTransactionConversionExponent>$dccexponent</i0:DCCTransactionConversionExponent>\n";
        $bd[75] = "<i0:DCCRateSourceDesignator>Planet</i0:DCCRateSourceDesignator>\n";
        $bd[76] = "</i0:DCCInfo>\n";
      }
    }

    $bd[82] = "</i0:req>\n";
    $bd[83] = "</i0:$tcode>\n";

    $bd[85] = "</soap:Body>\n";
    $bd[86] = "</soap:Envelope>\n";

  }

  my $message = "";
  my $indent  = 0;
  foreach $var (@bd) {
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

  return $message, $tcode;
}

sub sendbatchclose {

  @bs = ();

  $bs[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  $bs[1] =
    "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:i0=\"http://www.planetpayment.net\">\n";

  $bs[2] = "<soap:Body>\n";

  $tcode = "BatchSettlementClose";
  $bs[3] = "<i0:$tcode>\n";
  $bs[4] = "<i0:req>\n";

  $bs[5] = "<AccessInfo>\n";

  my $userid = $merchant_id;

  #if ($username !~ /skyhawket1|intelstrar1/) {
  #  $userid = substr($userid,-12,12);
  #}
  $bs[6] = "<User>$userid</User>\n";

  if ( $username eq "testplanet" ) {
    $bs[7] = "<Password>f0I!Rzh[A#1-</Password>\n";
  } else {
    $bs[7] = "<Password>6g4\@B2c</Password>\n";
  }
  $bs[8] = "<ApplicationID>DirectLinkPlanet</ApplicationID>\n";
  $terminalnum = substr( "0" x 8 . $terminalnum, -8, 8 );
  $bs[9] = "<TerminalID>$terminalnum</TerminalID>\n";
  my $ipaddress = $ENV{'REMOTE_ADDR'};
  $ipaddress = "69.18.198.140";
  $bs[10]    = "<ClientIPAddress>$ipaddress</ClientIPAddress>\n";
  $bs[11]    = "</AccessInfo>\n";

  $bs[12] = "<BatchSettlementInfo>\n";
  my ($oid) = &miscutils::genorderid();
  $oid = substr( $oid, -14, 14 );
  $bs[13] = "<i0:RequestIdentifier>$oid</i0:RequestIdentifier>\n";

  $bs[14] = "<i0:BatchNumber>$batchnum</i0:BatchNumber>\n";
  $bs[15] = "<i0:SalesCount>$hostsalescnt</i0:SalesCount>\n";
  $bs[16] = "<i0:SalesAmount>$hostsalesamt</i0:SalesAmount>\n";
  $bs[17] = "<i0:RefundsCount>$hostrefundscnt</i0:RefundsCount>\n";
  $bs[18] = "<i0:RefundsAmount>$hostrefundsamt</i0:RefundsAmount>\n";
  $bs[19] = "<i0:ReversalCount>$hostreversalcnt</i0:ReversalCount>\n";
  $bs[20] = "<i0:AdjustmentCount>0</i0:AdjustmentCount>\n";

  $bs[21] = "</BatchSettlementInfo>\n";

  $bs[22] = "</i0:req>\n";
  $bs[23] = "</i0:$tcode>\n";

  $bs[24] = "</soap:Body>\n";
  $bs[25] = "</soap:Envelope>\n";

  $message = &processmessage(@bs);

  $response = &sendmessage( $message, $tcode );

  my $printstr = "$response\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  %temparray = &processresponse($response);

  $batchnumber = $temparray{"s:Envelope,s:Body,BatchSettlementCloseResponse,BatchSettlementCloseResult,BatchSettlementCloseInfo,BatchNumber"};
  $status      = $temparray{"s:Envelope,s:Body,BatchSettlementCloseResponse,BatchSettlementCloseResult,BatchSettlementCloseInfo,Status"};
  $respcode    = $temparray{"s:Envelope,s:Body,BatchSettlementCloseResponse,BatchSettlementCloseResult,ResponseDetail,ResponseCode"};
  $errmsg      = $temparray{"s:Envelope,s:Body,BatchSettlementCloseResponse,BatchSettlementCloseResult,ResponseDetail,ResponseMessage"};
  $refnum      = $temparray{"s:Envelope,s:Body,BatchSettlementCloseResponse,BatchSettlementCloseResult,ResponseDetail,RetrievalReferenceNumber"};

  $tmpfilestr = "";
  $tmpfilestr .= "       	$oid	$refnum	batch close\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay", "scriptresults2.txt", "append", "", $tmpfilestr );

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "sendclose:\n";
  $logfilestr .= "batchnum: $batchnum\n";
  $logfilestr .= "status: $status\n";
  $logfilestr .= "respcode: $respcode\n";
  $logfilestr .= "errmsg: $errmsg\n";
  $logfilestr .= "refnum: $refnum\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
}

sub sendbatchstatus {
  @bs = ();

  $bs[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  $bs[1] =
    "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:i0=\"http://www.planetpayment.net\">\n";

  $bs[2] = "<soap:Body>\n";

  $tcode = "BatchSettlementStatus";
  $bs[3] = "<i0:$tcode>\n";
  $bs[4] = "<i0:req>\n";

  $bs[5] = "<AccessInfo>\n";

  my $userid = $merchant_id;

  #if ($username !~ /skyhawket1|intelstrar1/) {
  #  $userid = substr($userid,-12,12);
  #}
  $bs[6] = "<User>$userid</User>\n";

  if ( $username eq "testplanet" ) {
    $bs[7] = "<Password>f0I!Rzh[A#1-</Password>\n";
  } else {
    $bs[7] = "<Password>6g4\@B2c</Password>\n";
  }
  $bs[8] = "<ApplicationID>DirectLinkPlanet</ApplicationID>\n";
  $terminalnum = substr( "0" x 8 . $terminalnum, -8, 8 );
  $bs[9] = "<TerminalID>$terminalnum</TerminalID>\n";
  my $ipaddress = $ENV{'REMOTE_ADDR'};
  $ipaddress = "69.18.198.140";
  $bs[10]    = "<ClientIPAddress>$ipaddress</ClientIPAddress>\n";
  $bs[11]    = "</AccessInfo>\n";

  my ($oid) = &miscutils::genorderid();
  $oid = substr( $oid, -14, 14 );
  $bs[14] = "<i0:RequestIdentifier>$oid</i0:RequestIdentifier>\n";

  $bs[64] = "</i0:req>\n";
  $bs[65] = "</i0:$tcode>\n";

  $bs[66] = "</soap:Body>\n";
  $bs[67] = "</soap:Envelope>\n";

  $message = &processmessage(@bs);

  $response = &sendmessage( $message, $tcode );

  %temparray = &processresponse($response);

  $hostsalesamt    = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,HostSalesAmount"};
  $hostsalescnt    = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,HostSalesCount"};
  $hostrefundsamt  = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,HostRefundsAmount"};
  $hostrefundscnt  = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,HostRefundsCount"};
  $hostreversalamt = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,HostReversalAmount"};
  $hostreversalcnt = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,HostReversalCount"};
  $batchnumber     = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,BatchNumber"};
  $status          = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,Status"};
  $respcode        = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,ResponseDetail,ResponseCode"};
  $errmsg          = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,ResponseDetail,ResponseMessage"};
  $refnum          = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,ResponseDetail,RetrievalReferenceNumber"};

  my $printstr = "batchsalesamt: $batchsalesamt    $hostsalesamt\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "batchsalescnt: $batchsalescnt    $hostsalescnt\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "batchretamt: $batchretamt    $hostrefundsamt\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "batchretcnt: $batchretcnt    $hostrefundscnt\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  my $printstr = "reversalamt: xxxx    $hostreversalamt\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "reversalcnt: xxxx    $hostreversalcnt\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  my $printstr = "batchnum: $batchnum    $batchnumber\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "respcode: $respcode\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "errmsg: $errmsg\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "status: $status\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "refnum: $refnum\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "sendinquiry:\n";
  $logfilestr .= "batchsalesamt: $batchsalesamt    $hostsalesamt\n";
  $logfilestr .= "batchsalescnt: $batchsalescnt    $hostsalescnt\n";
  $logfilestr .= "batchretamt: $batchretamt    $hostrefundsamt\n";
  $logfilestr .= "batchretcnt: $batchretcnt    $hostrefundscnt\n";

  $logfilestr .= "reversalamt: xxxx    $hostreversalamt\n";
  $logfilestr .= "reversalcnt: xxxx    $hostreversalcnt\n";

  $logfilestr .= "batchnum: $batchnum    $batchnumber\n";
  $logfilestr .= "respcode: $respcode\n";
  $logfilestr .= "errmsg: $errmsg\n";
  $logfilestr .= "status: $status\n";
  $logfilestr .= "refnum: $refnum\n";

  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
}

sub sendbatchstatusdetail {
  @bs = ();

  $bs[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  $bs[1] =
    "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:i0=\"http://www.planetpayment.net\">\n";

  $bs[2] = "<soap:Body>\n";

  $tcode = "BatchSettlementStatusDetail";
  $bs[3] = "<i0:$tcode>\n";
  $bs[4] = "<i0:req>\n";

  $bs[5] = "<AccessInfo>\n";

  my $userid = $merchant_id;

  #if ($username !~ /skyhawket1|intelstrar1/) {
  #  $userid = substr($userid,-12,12);
  #}
  $bs[6] = "<User>$userid</User>\n";

  if ( $username eq "testplanet" ) {
    $bs[7] = "<Password>f0I!Rzh[A#1-</Password>\n";
  } else {
    $bs[7] = "<Password>6g4\@B2c</Password>\n";
  }
  $bs[8] = "<ApplicationID>DirectLinkPlanet</ApplicationID>\n";
  $terminalnum = substr( "0" x 8 . $terminalnum, -8, 8 );
  $bs[9] = "<TerminalID>$terminalnum</TerminalID>\n";
  my $ipaddress = $ENV{'REMOTE_ADDR'};
  $ipaddress = "69.18.198.140";
  $bs[10]    = "<ClientIPAddress>$ipaddress</ClientIPAddress>\n";
  $bs[11]    = "</AccessInfo>\n";

  my ($oid) = &miscutils::genorderid();
  $oid = substr( $oid, -14, 14 );
  $bs[14] = "<i0:RequestIdentifier>$oid</i0:RequestIdentifier>\n";

  #if ($batchnum eq "") {
  #  $batchnum = "0";
  #}
  $bs[14] = "<i0:BatchNumber>0</i0:BatchNumber>\n";

  $bs[64] = "</i0:req>\n";
  $bs[65] = "</i0:$tcode>\n";

  $bs[66] = "</soap:Body>\n";
  $bs[67] = "</soap:Envelope>\n";

  $message = &processmessage(@bs);

  $response = &sendmessage( $message, $tcode );

  if ( $response eq "" ) {
    &mysleep(10);
    $response = &sendmessage( $message, $tcode );
  }

  %temparray = &processresponse($response);

  umask 0077;
  $logfilestr = "";

  $data = $response;
  $data =~ s/\n/;;;/g;
  $data =~ s/^.*<BatchSettlementStatusInfoDetail>//;
  $data =~ s/<\/BatchSettlementStatusInfoDetail>.*$//;
  $data =~ s/\&lt;/</g;
  $data =~ s/\&gt;/>/g;
  $data =~ s/\&\#xD;//g;
  $data =~ s/^.*?<Transaction/<Transaction/;
  $data =~ s/;;;<\/Batch>.*$//;
  $data =~ s/;;;<Batch.*?>//;
  my (@lines) = split( /;;;/, $data );

  foreach my $line (@lines) {
    ( $d1, $type, $d2, $amount, $d3, $currency, $d4, $refnum, $d5, $oid, $d6, $datestr ) = split( /"/, $line );
    my $printstr = "type: $type  amount: $amount  currency: $currency  refnum: $refnum  oid: $oid\n";
    &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
    $logfilestr .= "type: $type  amount: $amount  currency: $currency  refnum: $refnum  oid: $oid\n";

    $chkorderidarray{"$oid"} = 1;
    if ( $orderidarray{"$oid"} != 1 ) {
      $inplanetarray{"$oid"} = 1;
    }
  }

  $logfilestr .= "\n";

  foreach $oid ( sort keys %orderidarray ) {
    if ( $chkorderidarray{"$oid"} != 1 ) {
      $inoplogarray{"$oid"} = 1;
    }
  }

  $logfilestr .= "\n";
  $logfilestr .= "The following orderids are on planet's list, but not ours:\n";
  foreach $oid ( sort keys %inplanetarray ) {
    $logfilestr .= "$oid\n";
  }
  $logfilestr .= "\n";

  $logfilestr .= "The following orderids are on our list, but not planet's:\n";
  foreach $oid ( sort keys %inoplogarray ) {
    $logfilestr .= "$oid\n";
  }

  $logfilestr .= "\n";

  $tcoderesponse = $tcode . "Response";
  $tcoderesult   = $tcode . "Result";

  $hostsalesamt    = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,HostSalesAmount"};
  $hostsalescnt    = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,HostSalesCount"};
  $hostrefundsamt  = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,HostRefundsAmount"};
  $hostrefundscnt  = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,HostRefundsCount"};
  $hostreversalamt = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,HostReversalAmount"};
  $hostreversalcnt = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,HostReversalCount"};
  $batchnumber     = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,BatchNumber"};
  $status          = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,Status"};
  $respcode        = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseDetail,ResponseCode"};
  $errmsg          = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseDetail,ResponseMessage"};
  $refnum          = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseDetail,RetrievalReferenceNumber"};

  my $printstr = "batchsalesamt: $batchsalesamt    $hostsalesamt\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "batchsalescnt: $batchsalescnt    $hostsalescnt\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "batchretamt: $batchretamt    $hostrefundsamt\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "batchretcnt: $batchretcnt    $hostrefundscnt\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  my $printstr = "reversalamt: xxxx    $hostreversalamt\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "reversalcnt: xxxx    $hostreversalcnt\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  my $printstr = "batchnum: $batchnum    $batchnumber\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "respcode: $respcode\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "errmsg: $errmsg\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "status: $status\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "refnum: $refnum\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  $logfilestr .= "sendinquiry:\n";
  $logfilestr .= "batchsalesamt: $batchsalesamt    $hostsalesamt\n";
  $logfilestr .= "batchsalescnt: $batchsalescnt    $hostsalescnt\n";
  $logfilestr .= "batchretamt: $batchretamt    $hostrefundsamt\n";
  $logfilestr .= "batchretcnt: $batchretcnt    $hostrefundscnt\n";

  $logfilestr .= "reversalamt: xxxx    $hostreversalamt\n";
  $logfilestr .= "reversalcnt: xxxx    $hostreversalcnt\n";

  $logfilestr .= "batchnum: $batchnum    $batchnumber\n";
  $logfilestr .= "respcode: $respcode\n";
  $logfilestr .= "errmsg: $errmsg\n";
  $logfilestr .= "status: $status\n";
  $logfilestr .= "refnum: $refnum\n";

  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  if ( $response ne "" ) {
    return "success";
  } else {
    return "";
  }
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
    &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  }

  return %temparray;

}

sub printrecord {
  my ($printmessage) = @_;

  $temp = length($printmessage);
  my $printstr = "$temp\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );
  ($message2) = unpack "H*", $printmessage;
  my $printstr = "$message2\n\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

  $message1 = $printmessage;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;

  #print "$message1\n$message2\n\n";
}

sub sendmessage {
  my ( $msg, $tcode ) = @_;

  my $host = "secure.planetpayment.net";
  my $port = "443";
  my $path = "/WebService/PlugNPay4Km5/PlanetPaymentWS/?wsdl";

  if ( $username eq "testplanet" ) {
    $host = "uat.planetpayment.net";
    $path = "/QAPlugnPayWS/?wsdl";     # test
  }

  $mytime = gmtime( time() );
  my $chkmessage = $msg;
  if ( ( length($cardnumber) >= 13 ) && ( length($cardnumber) <= 19 ) ) {
    $xs = "x" x length($cardnumber);
    $chkmessage =~ s/$cardnumber/$xs/;
  }
  $chkmessage =~ s/\>\</\>\n\</g;

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username  $orderid\n";
  $logfilestr .= "$host:$port  $path\n";
  $logfilestr .= "$mytime send: $chkmessage\n\n";
  $logfilestr .= "sequencenum: $sequencenum retries: $retries\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  my $len        = length($msg);
  my %sslheaders = ();
  $sslheaders{'Host'}           = "$host:$port";
  $sslheaders{'Accept'}         = '*/*';
  $sslheaders{'SOAPAction'}     = "http://www.planetpayment.net/ITransaction/$tcode";
  $sslheaders{'Content-Type'}   = 'text/xml';
  $sslheaders{'Content-Length'} = $len;
  my ($response) = &procutils::sendsslmsg( "processor_planet", $host, $port, $path, $msg, "other", %sslheaders );

  $mytime = gmtime( time() );
  my $chkmessage = $response;
  $chkmessage =~ s/\>\</\>\n\</g;
  if ( ( length($cardnumber) >= 13 ) && ( length($cardnumber) <= 19 ) ) {
    $chkmessage =~ s/$cardnumber/$xs/;
  }
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username  $orderid\n";
  $logfilestr .= "$mytime recv: $chkmessage\n\n";
  &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

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

  if ( $paymenttype eq "" ) {
    $clen      = length($cardnumber);
    $cabbrev   = substr( $cardnumber, 0, 4 );
    $card_type = &smpsutils::checkcard($cardnumber);
    if ( $card_type eq "" ) {
      &errormsg( $username, $orderid, $operation, 'bad card number' );
      return 1;
    }
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

sub pidcheck {
  my $chkline = &procutils::fileread( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay", "pid.txt" );
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/$devprod/planetpay/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $printstr .= "$pidline\n";
    $printstr .= "$chkline\n";
    &procutils::filewrite( "$username", "planetpay", "/home/pay1/batchfiles/devlogs/planetpay", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: planetpay - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

