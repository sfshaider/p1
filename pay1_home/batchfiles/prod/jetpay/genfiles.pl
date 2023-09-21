#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use procutils;
use rsautils;
use smpsutils;
use jetpay;
use isotables;

$devprod = "logs";

if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/jetpay/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'jetpay/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: jetpay - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

#open(checkin,"/home/pay1/batchfiles/$devprod/jetpay/genfiles.txt");
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

$hoststr = "processor-host";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "      ";
$starttransdate   = $onemonthsago - 10000;

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

#print "two months ago: $twomonthsago\n";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $dummy, $today, $todaytime ) = &miscutils::genorderid();

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/jetpay/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/jetpay/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/jetpay/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/jetpay/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/jetpay/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/jetpay/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/jetpay/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/jetpay/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/jetpay/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/jetpay/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: jetpay - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/jetpay/$fileyear.\n\n";
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
        and o.processor='jetpay'
        and o.lastoptime>=?
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user $usercount $usertdate\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

my $printstr = "fff\n";
&procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );

my $printstr = "fff\n";
&procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );

foreach $username ( sort @userarray ) {
  if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/jetpay/stopgenfiles.txt" ) ) {
    unlink "/home/pay1/batchfiles/$devprod/jetpay/batchfile.txt";
    last;
  }

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/$devprod/jetpay", "genfiles.txt", "write", "", $checkinstr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/$devprod/jetpay", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};

  my $printstr = "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  umask 0077;
  $logfilestr = "";
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr .= "$username\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/$devprod/jetpay/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  %errorderid    = ();
  $detailnum     = 0;
  $batchsalesamt = 0;
  $batchsalescnt = 0;
  $batchretamt   = 0;
  $batchretcnt   = 0;
  $batchcnt      = 1;

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,company,addr1,city,state,zip,tel,status,country,currency,switchtime
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $company, $address, $city, $state, $zip, $tel, $status, $country, $currency, $switchtime ) =
    &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $printstr = "ggg\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );

  my $printstr = "ggg\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "$username $status\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );

  if ( $status ne "live" ) {
    next;
  }

  if ( $currency eq "" ) {
    $currency = "usd";
  }

  my $printstr = "aaaa $starttransdate $onemonthsagotime $username\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );

  $batch_flag = 0;
  $netamount  = 0;
  $hashtotal  = 0;
  $batchcnt   = 1;
  $recseqnum  = 0;

  my $dbquerystr = <<"dbEOM";
        select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,origamount,authtime,postauthtime,forceauthstatus
        from operation_log
        where trans_date>=?
        and lastoptime>=?
        and username=?
        and lastopstatus in ('pending','locked')
        and lastop IN ('auth','postauth','return','forceauth')
        and processor='jetpay'
        and (voidstatus is NULL or voidstatus ='')
        and (accttype is NULL or accttype ='' or accttype='credit')
        order by orderid
dbEOM
  my @dbvalues = ( "$starttransdate", "$onemonthsagotime", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 18 ) {
    ( $orderid,  $operation, $trans_date,  $trans_time, $enccardnumber, $enclength,  $exp,      $amount,       $auth_code,
      $avs_code, $refnumber, $finalstatus, $cvvresp,    $transflags,    $origamount, $authtime, $postauthtime, $forceauthstatus
    )
      = @sthtransvalarray[ $vali .. $vali + 17 ];

    if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/jetpay/stopgenfiles.txt" ) ) {
      unlink "/home/pay1/batchfiles/$devprod/jetpay/batchfile.txt";
      last;
    }
    my $printstr = "bbbb $proc_type  $transflags  $operation\n";
    &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );

    if ( ( $proc_type eq "authcapture" ) && ( $operation eq "postauth" ) ) {
      next;
    }

    if ( ( $transflags =~ /capture/ ) && ( $operation eq "postauth" ) ) {
      next;
    }

    if ( $switchtime ne "" ) {
      $switchtime = substr( $switchtime . "0" x 14, 0, 14 );
      if ( ( $operation eq "postauth" ) && ( $authtime ne "" ) && ( $authtime < $switchtime ) ) {
        next;
      }
    }

    $origoperation = "auth";
    if ( $forceauthstatus eq "success" ) {
      $origoperation = "forceauth";
    }

    # must wait one day for returns
    #my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime(time() - (3600 * 24));
    #$yesterdaytime = sprintf("%04d%02d%02d%02d%02d%02d",$year+1900,$month+1,$day,$hour,$min,$sec);
    #if (($transflags =~ /capture/) || ($proc_type eq "authcapture")) {
    #  $chktime = $authtime;
    #}
    #else {
    #  $chktime = $postauthtime;
    #}
    #if (($operation eq "return") && ($yesterdaytime < $chktime)) {
    #  next;
    #}

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/$devprod/jetpay/$fileyear", "$username$time.txt", "append", "", $logfilestr );
    my $printstr = "$orderid $operation $auth_code $refnumber\n";
    &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "jetpay", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $errorflag = &errorchecking();
    my $printstr = "cccc $errorflag\n";
    &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
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

    &batchdetail();

    $response = &sendmessage($message);

    &endbatch($response);
  }

  if ( $batchcnt > 1 ) {
    %errorderid = ();
    $detailnum  = 0;
  }
}

if ( ( !-e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) && ( !-e "/home/pay1/batchfiles/$devprod/jetpay/stopgenfiles.txt" ) ) {
  umask 0033;
  $checkinstr = "";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/$devprod/jetpay", "genfiles.txt", "write", "", $checkinstr );
}

unlink "/home/pay1/batchfiles/$devprod/jetpay/batchfile.txt";

exit;

sub endbatch {
  my ($response) = @_;

  #my ($header,$data) = split(/\r{0,1}\n\r{0,1}\n/,$response,2);
  my $data = $response;

  $data =~ s/\r{0,1}\n/ /g;
  $data =~ s/>\s*</>;;;</g;
  $data =~ s/<([^\/]*?)>;;;<[\/]/<$1><\//g;
  my $printstr = "\n\ndata: $data\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
  my @tmpfields = split( /;;;/, $data );
  my %temparray = ();
  my $levelstr  = "";
  my $key       = "";
  foreach my $var (@tmpfields) {

    if ( $var =~ /<\!/ ) {
    } elsif ( $var =~ /<\?/ ) {
    } elsif ( $var =~ /<(.+)>(.*)</ ) {
      my $var2  = $1;
      my $value = $2;
      $var2 =~ s/ .*$//;

      if ( $temparray{"$levelstr$var2"} eq "" ) {
        $temparray{"$levelstr$var2"} = $2;
      } else {
        $temparray{"$levelstr$var2"} = $temparray{"$levelstr$var2"} . "," . $2;
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
    &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
  }

  $pass = $temparray{'JetPayResponse,ActionCode'};
  my $message = $temparray{'JetPayResponse,ResponseText'};
  $message =~ s/&.+?;//g;
  $err_msg   = "$pass: $message";
  $auth_code = $temparray{'JetPayResponse,Approval'};

  #$refnumber = $temparray{'JetPayResponse,TransactionID'};

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "orderid   $orderid\n";
  $logfilestr .= "pass   $pass\n";
  $logfilestr .= "err_msg   $err_msg\n";
  $logfilestr .= "result   $time$batchnum\n\n\n";

  my $printstr = "orderid   $orderid\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "pass   $pass\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "err_msg   $err_msg\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "result   $time$batchnum\n\n\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay",            "miscdebug.txt",      "append", "misc", $printstr );
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/$devprod/jetpay/$fileyear", "$username$time.txt", "append", "",     $logfilestr );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  if ( $pass eq "000" ) {

    #and result='$time$batchnum'
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?
            where orderid=?
            and trans_date>=?
            and username=?
            and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$orderid", "$onemonthsago", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

    #and batchfile='$time$batchnum'
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='success',lastopstatus='success',lastoptime=?
            where orderid=?
            and lastoptime>=?
            and username=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$orderid", "$onemonthsagotime", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  } elsif ( $pass ne "" ) {
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
    #print MAILERR "Subject: jetpay - FORMAT ERROR\n";
    #print MAILERR "\n";
    #print MAILERR "username: $username\n";
    #print MAILERR "result: format error\n\n";
    #print MAILERR "batchtransdate: $batchtransdate\n";
    #close MAILERR;
  } else {
    my $printstr = "pass	$pass unknown\n";
    &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: jetpay - unkown error\n";
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
          from jetpay
          where username=?
dbEOM
  my @dbvalues = ("$username");
  ($batchnum) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = $batchnum + 1;
  if ( $batchnum >= 998 ) {
    $batchnum = 1;
  }

  my $dbquerystr = <<"dbEOM";
          update jetpay set batchnum=?
          where username=?
dbEOM
  my @dbvalues = ( "$batchnum", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = substr( "0000" . $batchnum, -4, 4 );

}

sub batchdetail {

  $transamt = substr( $amount, 4 );
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

  @bd = ();
  if ( $finalstatus eq "locked" ) {
    $bd[0] = "<JetPay>";
    $bd[1] = "<TransactionType>ENQ</TransactionType>";
    $bd[2] = "<MerchantID>$merchant_id</MerchantID>";
    my $transid = $refnumber;
    $transid = substr( "0" x 18 . $transid, -18, 18 );
    $bd[3]   = "<TransactionID>$transid</TransactionID>";
    $bd[4]   = "</JetPay>";
  } elsif ( $operation eq "return" ) {
    $bd[0] = "<JetPay>";
    $bd[1] = "<TransactionType>CREDIT</TransactionType>";
    $bd[2] = "<MerchantID>$merchant_id</MerchantID>";
    my $transid = $refnumber;
    $transid = substr( "0" x 18 . $transid, -18, 18 );
    $bd[3] = "<TransactionID>$transid</TransactionID>";

    #$bd[5] = "<RoutingCode>$yyyy</RoutingCode>";
    #$bd[6] = "<BatchID>$yyyy</BatchID>";
    my $origin = "";
    if ( $transflags =~ /recurring/ ) {
      $origin = "RECURRING";
    } elsif ( $transflags =~ /moto/ ) {
      $origin = "MAIL ORDER";
    } else {
      $origin = "INTERNET";
    }
    $bd[7] = "<Origin>$origin</Origin>";

    #$bd[8] = "<Password>$terminal_id</Password>";

    my $marketdata = substr( $auth_code, 59, 40 );
    $marketdata =~ s/ +$//g;
    if ( $marketdata eq "" ) {
      $marketdata = $orderid;
    }
    $bd[9] = "<OrderNumber>$marketdata</OrderNumber>";

    $bd[10] = "<CardNum CardPresent=\"false\">$cardnumber</CardNum>";

    #if ($card_type eq "sw") {
    #  $bd[12] = "<Issue>$cardissuenum</Issue>";
    #}
    $monthexp = substr( $exp, 0, 2 );
    $yearexp  = substr( $exp, 3, 2 );
    $bd[13]   = "<CardExpMonth>$monthexp</CardExpMonth>";
    $bd[14]   = "<CardExpYear>$yearexp</CardExpYear>";

    #my ($startmonth,$startyear) = split(/\//$cardstartdate);
    #if ($card_type eq "sw") {
    #  $bd[15] = "<CardStartMonth>$startmonth</CardStartMonth>";
    #  $bd[16] = "<CardStartYear>$startyear</CardStartYear>";
    #}
    #$bd[17] = "<Track1>$yyyy</Track1>";
    #$bd[18] = "<Track2>$yyyy</Track2>";
    $bd[19] = "<CardName>$card_name</CardName>";

    #$bd[20] = "<DispositionType>$yyyy</DispositionType>";

    $currency =~ tr/a-z/A-Z/;
    $exponent = $isotables::currencyUSD2{$currency};
    $transamt = sprintf( "%d", ( $transamt * ( 10**$exponent ) ) + .0001 );
    $bd[21]   = "<TotalAmount>$transamt</TotalAmount>";

    #$bd[22] = "<FeeAmount>$yyyy</FeeAmount>";
    #$bd[23] = "<TaxAmount>$yyyy</TaxAmount>";

    if (0) {
      $bd[24] = "<BillingAddress>$cardaddress</BillingAddress>";
      $bd[25] = "<BillingCity>$cardcity</BillingCity>";
      $bd[26] = "<BillingStateProv>$cardstate</BillingStateProv>";
      $bd[27] = "<BillingPostalCode>$cardzip</BillingPostalCode>";
      my $countrycode = $cardcountry;
      $countrycode =~ tr/a-z/A-Z/;
      $countrycode = $isotables::countryUS840{$countrycode};
      $bd[28]      = "<BillingCountry>$countrycode</BillingCountry>";
      $bd[29]      = "<BillingPhone>$phone</BillingPhone>";
    }
    $bd[30] = "<Email>$email</Email>";
    my $ipaddress = substr( $ENV{'REMOTE_ADDR'}, 0, 23 );
    if ( $ipaddress eq "" ) {
      $ipaddress = "209.51.176.50";
    }

    #$bd[31] = "<UserIPAddress>$ipaddress</UserIPAddress>";
    #$bd[32] = "<UserHost>$yyyy</UserHost>";
    #$bd[33] = "<ActionCode>$yyyy</ActionCode>";

    my $ind = "";
    if ( $industrycode eq "moto" ) {
      $ind = "MOTO";
    } elsif ( $industrycode eq "retail" ) {
      $ind = "RETAIL";
    } else {
      $ind = "ECOMMERCE";
    }
    $bd[34] = "<IndustryInfo Type=\"$ind\"></IndustryInfo>";

    $bd[40] = "</JetPay>";
  } elsif ( $origoperation eq "forceauth" ) {
    $bd[0] = "<JetPay>";
    $bd[1] = "<TransactionType>FORCE</TransactionType>";
    $bd[2] = "<MerchantID>$merchant_id</MerchantID>";
    my $transid = $refnumber;
    $transid = substr( "0" x 18 . $transid, -18, 18 );
    $bd[3] = "<TransactionID>$transid</TransactionID>";
    if ( $origoperation eq "forceauth" ) {
      my $authcode = substr( $auth_code, 0, 6 );
      $bd[4] = "<Approval>$authcode</Approval>";
    }
    $bd[5] = "<CardNum CardPresent=\"false\">$cardnumber</CardNum>";
    $monthexp = substr( $exp, 0, 2 );
    $yearexp  = substr( $exp, 3, 2 );
    $bd[6]    = "<CardExpMonth>$monthexp</CardExpMonth>";
    $bd[7]    = "<CardExpYear>$yearexp</CardExpYear>";

    $currency =~ tr/a-z/A-Z/;
    $exponent = $isotables::currencyUSD2{$currency};
    $transamt = sprintf( "%d", ( $transamt * ( 10**$exponent ) ) + .0001 );
    $bd[8]    = "<TotalAmount>$transamt</TotalAmount>";

    $bd[9] = "</JetPay>";
  } elsif ( $operation eq "postauth" ) {
    $bd[0] = "<JetPay>";
    $bd[1] = "<TransactionType>CAPT</TransactionType>";
    $bd[2] = "<MerchantID>$merchant_id</MerchantID>";
    my $transid = $refnumber;
    $transid = substr( "0" x 18 . $transid, -18, 18 );
    $bd[3] = "<TransactionID>$transid</TransactionID>";
    $currency =~ tr/a-z/A-Z/;
    $exponent = $isotables::currencyUSD2{$currency};
    $transamt = sprintf( "%d", ( $transamt * ( 10**$exponent ) ) + .0001 );
    $bd[4]    = "<TotalAmount>$transamt</TotalAmount>";
    $bd[5]    = "</JetPay>";
  }

  $message = "";
  foreach my $var (@bd) {
    my $value = $var;
    $value =~ s/^.*>(.*)<\/.*$/$1/;
    if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {

      #$var =~ s/>(.*)<\//>![CDATA[$value]]<\//;
    }
    if ( $var ne "" ) {
      $message = $message . $var . "\n";
    }
  }

}

sub printrecord {
  my ($printmessage) = @_;

  $temp = length($printmessage);
  my $printstr = "$temp\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );
  ($message2) = unpack "H*", $printmessage;
  my $printstr = "$message2\n\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/devlogs/jetpay", "miscdebug.txt", "append", "misc", $printstr );

  $message1 = $printmessage;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;

  #print "$message1\n$message2\n\n";
}

sub sendmessage {
  my ($msg) = @_;

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
  $logfilestr .= "$mytime send: $chkmessage\n\n";
  $logfilestr .= "sequencenum: $sequencenum retries: $retries\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/$devprod/jetpay/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  my $host = "gateway20.jetpay.com";
  my $port = "443";
  my $path = "/jetpay";
  if ( $jetpay::username eq "xtestjetpay" ) {
    $host = "test1.jetpay.com";
  }

  #my $len = length($msg);
  #my %sslheaders = ();
  #$sslheaders{'Host'} = "$host:$port";
  #$sslheaders{'Accept'} = "*/*";
  #$sslheaders{'Content-Type'} = 'text/xml';
  #$sslheaders{'Content-Length'} = $len;
  #(my $response,my $header,my %resulthash) = &procutils::sendsslmsg("jetpay",$host,$port,$path,$msg,"noshutdown,noheaders,http10,len<1",%sslheaders);

  my %sslheaders = ();
  $sslheaders{'Host'}   = "$host:$port";
  $sslheaders{'Accept'} = "*/*";

  #$sslheaders{'SoapAction'} = "https://www.gms-operations.com/webservices/ACHPayorService/$action";
  $sslheaders{'Content-Length'} = $len;
  $sslheaders{'Content-Type'}   = 'text/xml; charset=utf-8';
  ( my $response, my $header, my %resulthash ) = &procutils::sendsslmsg( "processor_jetpay", $host, $port, $path, $msg, "other", %sslheaders );

  $mytime = gmtime( time() );
  my $chkmessage = $response;
  $chkmessage =~ s/\>\</\>\n\</g;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username  $orderid\n";
  $logfilestr .= "$mytime recv: $chkmessage\n\n";
  &procutils::filewrite( "$username", "jetpay", "/home/pay1/batchfiles/$devprod/jetpay/$fileyear", "$username$time.txt", "append", "", $logfilestr );

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

  if ( $cardnumber eq "411111111111111" ) {
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

