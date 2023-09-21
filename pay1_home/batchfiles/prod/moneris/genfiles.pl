#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;
use smpsutils;
use Time::Local;

$devprod = "logs";

if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  exit;
}

#open(checkin,"/home/pay1/batchfiles/$devprod/moneris/genfiles.txt");
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

if ( !-e "/home/pay1/batchfiles/$devprod/moneris/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/moneris/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/moneris/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/moneris/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/moneris/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/moneris/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/moneris/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/moneris/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/moneris/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/moneris/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: moneris - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/moneris/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;

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
        and o.processor='moneris'
        and o.lastoptime>=?
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user $usercount $usertdate\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );
  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

#if (($checkstring ne "") && ($#userarray < 1)) {
#  $chkuser = $checkstring;
#  $chkuser =~ s/^.*\'(.*)\'.*/$1/g;
#  print "$chkuser\n";
#  @userarray = (@userarray,$chkuser);
#}

foreach $username ( sort @userarray ) {
  if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
    unlink "/home/pay1/batchfiles/$devprod/moneris/batchfile.txt";
    last;
  }

  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris", "genfiles.txt", "write", "", $checkinstr );

  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};

  my $printstr = "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  umask 0077;
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );

  $logfilestr = "";
  $logfilestr .= "$username\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  %errorderid    = ();
  $detailnum     = 0;
  $batchsalesamt = 0;
  $batchsalescnt = 0;
  $batchretamt   = 0;
  $batchretcnt   = 0;
  $batchcnt      = 1;

  my $dbquerystr = <<"dbEOM";
        select c.merchant_id,c.pubsecret,c.proc_type,c.company,c.addr1,c.city,c.state,c.zip,c.tel,c.status,c.features,
        e.industrycode
        from customers c, moneris e
        where c.username=?
        and e.username=c.username
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $company, $address, $city, $state, $zip, $tel, $status, $features, $industrycode ) =
    &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

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
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris/$fileyear", "$username$time.txt", "append", "", $logfilestr );
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris/$fileyear", "$username$time.txt", "append", "", $logfilestr );
      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  my $printstr = "gmt today: $todaytime\n";
  $printstr .= "est today: $esttime\n";
  $printstr .= "est yesterday: $yesterday\n";
  $printstr .= "settletime: $settletime\n";
  $printstr .= "sweeptime: $sweeptime\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr .= "$username  sweeptime: $sweeptime  settletime: $settletime\n";
  $logfilestr .= "$features\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  my $printstr = "aaaa $starttransdate $onemonthsagotime $username\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );

  $batch_flag = 0;
  $netamount  = 0;
  $hashtotal  = 0;
  $batchcnt   = 1;
  $recseqnum  = 0;

  my $dbquerystr = <<"dbEOM";
        select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,origamount,forceauthstatus
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
      unlink "/home/pay1/batchfiles/$devprod/moneris/batchfile.txt";
      last;
    }

    if ( ( $proc_type eq "authcapture" ) && ( $operation eq "postauth" ) ) {
      next;
    }

    if ( ( $sweeptime ne "" ) && ( $trans_time > $sweeptime ) ) {
      next;    # transaction is newer than sweeptime
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris/$fileyear", "$username$time.txt", "append", "", $logfilestr );
    my $printstr = "$orderid $operation $auth_code $refnumber\n";
    &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "moneris", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $card_type = &smpsutils::checkcard($cardnumber);
    if ( $card_type eq "dc" ) {
      $card_type = "mc";
    }

    # xxxx
    #if (($username eq "variousinc3") && ($forceauthstatus ne "") && ($operation eq "postauth")) {
    #  next;
    #}

    $errorflag = &errorchecking();
    my $printstr = "cccc $errorflag\n";
    &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );
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

  # xxxx
  if ( $batchcnt > 0 ) {
    %errorderid = ();
    $detailnum  = 0;
  }
}

if ( !-e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  $checkinstr = "";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris", "genfiles.txt", "write", "", $checkinstr );
}

unlink "/home/pay1/batchfiles/$devprod/moneris/batchfile.txt";

exit;

sub endbatch {
  my ($response) = @_;

  my $data = $response;

  $data =~ s/\n/ /g;
  $data =~ s/></>;;;;</g;
  my @tmpfields = split( /;;;;/, $data );
  my %temparray = ();
  my $levelstr  = "";
  foreach my $var (@tmpfields) {
    if ( $var =~ /<(.+)>(.*)</ ) {
      my $var2 = $1;
      my $var3 = $2;
      $var2 =~ s/FIELD KEY=//;
      $var2 =~ s/\"//g;
      $var2 =~ s/ .*$//;
      if ( $temparray{"$levelstr$var2"} eq "" ) {
        $temparray{"$levelstr$var2"} = $var3;
      } else {
        $temparray{"$levelstr$var2"} = $temparray{"$levelstr$var2"} . "," . $var3;
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
    &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );
  }

  $respcode = $temparray{'response,receipt,ResponseCode'};
  my $message = $temparray{'response,receipt,Message'};
  $message =~ s/  +/ /g;
  $err_msg = "$respcode: $message";
  my $statusid = $temparray{'XML,REQUEST,RESPONSE,ROW,STATUSID'};

  $refnumber = $temparray{'response,receipt,ReferenceNum'};
  $transid   = $temparray{'response,receipt,TransID'};

  if ( $respcode eq "null" ) {
    $respcode = "999";
  }

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "orderid   $orderid\n";
  $logfilestr .= "respcode   $respcode\n";
  $logfilestr .= "err_msg   $err_msg\n";
  $logfilestr .= "result   $time$batchnum\n\n\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  my $printstr = "orderid   $orderid\n";
  $printstr .= "transseqnum   $transseqnum\n";
  $printstr .= "respcode   $respcode\n";
  $printstr .= "err_msg   $err_msg\n";
  $printstr .= "result   $time$batchnum\n\n\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  if ( ( $respcode ne "" ) && ( $respcode >= 0 ) && ( $respcode <= 50 ) ) {

    $transid = substr( $transid . " " x 16, 0, 16 );
    my $newauthcode = substr( $auth_code . " " x 78, 0, 78 ) . $transid . substr( $auth_code, 94 );

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?,refnumber=?,auth_code=?
            where orderid=?
            and trans_date>=?
            and result=?
            and username=?
            and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$refnumber", "$newauthcode", "$orderid", "$onemonthsago", "$time$batchnum", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $printstr = "update operation_log  $orderid  $onemonthsagotime  $operation  $username  $time$batchnum\n";
    &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='success',lastopstatus='success',lastoptime=?,refnumber=?,auth_code=?
            where orderid=?
            and lastoptime>=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$refnumber", "$newauthcode", "$orderid", "$onemonthsagotime", "$username", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  } elsif ( ( ( $respcode eq "OK" ) && ( $operation ne "forceauth" ) )
    || ( ( $statusid eq "600" ) && ( $operation eq "forceauth" ) ) ) {

    $transid = substr( $transid . " " x 16, 0, 16 );
    my $newauthcode = substr( $auth_code . " " x 78, 0, 78 ) . $transid . substr( $auth_code, 94 );

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?,refnumber=?,auth_code=?
            where orderid=?
            and trans_date>=?
            and result=?
            and username=?
            and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$refnumber", "$newauthcode", "$orderid", "$onemonthsago", "$time$batchnum", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='success',lastopstatus='success',$operationtime=?,lastoptime=?,refnumber=?,auth_code=?
            where orderid=?
            and lastoptime>=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$time", "$refnumber", "$newauthcode", "$orderid", "$onemonthsagotime", "$username", "$time$batchnum", "$time", "$refnumber" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  } elsif ( $respcode > 51 ) {
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
    #print MAILERR "Subject: moneris - FORMAT ERROR\n";
    #print MAILERR "\n";
    #print MAILERR "username: $username\n";
    #print MAILERR "result: format error\n\n";
    #print MAILERR "batchtransdate: $batchtransdate\n";
    #close MAILERR;
  } elsif ( ( $operation eq "forceauth" ) && ( $statusid eq "99999" ) ) {
    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='badcard'
            where orderid=?
            and trans_date>=?
            and username=?
            and (accttype is NULL or accttype ='' or accttype='credit')
            and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$orderid", "$onemonthsago", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='badcard',lastopstatus='badcard'
            where orderid=?
            and lastoptime>=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$onemonthsagotime" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  } elsif ( ( $respcode =~ /RR/ ) || ( ( $operation eq "postauth" ) && ( $respcode eq "" ) ) || ( $operation eq "forceauth" ) ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='pending',descr=?
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
            update operation_log set $operationstatus='pending',lastopstatus='pending',descr=?
            where orderid=?
            and lastoptime>=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$err_msg", "$orderid", "$onemonthsagotime" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  } elsif ( $respcode eq "PENDING" ) {
  } else {
    my $printstr = "respcode	$respcode unknown\n";
    &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: moneris - unkown error\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "orderid: $orderid\n";
    print MAILERR "err_msg: $err_msg\n";
    print MAILERR "file: $username$time.txt\n";
    close MAILERR;

    &miscutils::mysleep(60.0);
  }

}

sub getbatchnum {
  my $dbquerystr = <<"dbEOM";
          select batchnum
          from moneris
          where username=?
dbEOM
  my @dbvalues = ("$username");
  ($batchnum) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = $batchnum + 1;
  if ( $batchnum >= 998 ) {
    $batchnum = 1;
  }

  my $dbquerystr = <<"dbEOM";
          update moneris set batchnum=?
          where username=?
dbEOM
  my @dbvalues = ( "$batchnum", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = substr( "0000" . $batchnum, -4, 4 );

}

sub batchtrailer {
  @bt = ();

  #CUST_NBR=9009
  #MERCH_NBR=900912
  #DBA_NBR=1
  #TERMINAL_NBR=1

  #TRAN_NBR=16
  #TRAN_TYPE=CCEZ

  #BATCH_ID=0

  $bt[0] = "<DETAIL CUST_NBR=\"$bankid\" MERCH_NBR=\"$merchant_id\" DBA_NBR=\"$dbanum\" TERMINAL_NBR=\"$terminal_id\">";

  if ( $transflags =~ /moto/ ) {
    $tcode = "CCMZ";
  } elsif ( $industrycode =~ /^(retail|restaurant)$/ ) {
    $tcode = "CCRZ";
  } else {
    $tcode = "CCEZ";
  }
  $bt[1] = "<TRAN_TYPE>$tcode</TRAN_TYPE>";
  $bt[2] = "<BATCH_ID>0</BATCH_ID>";
  $bt[3] = "<TRAN_NBR>0</TRAN_NBR>";

  $bt[4] = "</DETAIL>";

  $message = "";
  my $indent = 0;
  foreach $var (@bt) {
    if ( $var =~ /^<\/.*>/ ) {
      $indent--;
    }
    $message = $message . $var;

    #$message = $message . " " x $indent . $var . "\n";
    if ( ( $var !~ /\// ) && ( $var != /<?/ ) ) {
      $indent++;
    }
    if ( $indent < 0 ) {
      $indent = 0;
    }
  }

}

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
      $trans_time    = $authtime;
      $origoperation = "auth";
    } elsif ( ( $forceauthtime ne "" ) && ( $forceauthstatus eq "success" ) ) {
      $trans_time    = $forceauthtime;
      $origoperation = "forceauth";
    } else {
      $trans_time    = "";
      $origoperation = "";
    }

    if ( $trans_time < 1000 ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "Error in batch detail: couldn't find trans_time $username $twomonthsago $orderid $trans_time\n";
      &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris/$fileyear", "$username$time.txt", "append", "", $logfilestr );
      $socketerrorflag = 1;
      $dberrorflag     = 1;
      return;
    }
  }

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

  @bd = ();

  if ( $operation eq "return" ) {
    $bd[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>";
    $bd[1] = "<request>";
    $bd[2] = "<store_id>$merchant_id</store_id>";
    $bd[3] = "<api_token>$terminal_id</api_token>";

    $transid = substr( $auth_code, 78, 16 );
    $transid =~ s/ //g;

    my $ttcode = "";
    if ( ( $transid ne "" ) && ( $merchant_id =~ /^monu/i ) ) {
      $ttcode = "us_refund";
    } elsif ( $transid ne "" ) {
      $ttcode = "refund";
    } elsif ( $merchant_id =~ /^monu/i ) {
      $ttcode = "us_ind_refund";
    } else {
      $ttcode = "ind_refund";
    }
    $bd[4] = "<$ttcode>";

    $bd[5] = "<order_id>$orderid" . "1</order_id>";
    ( $currency, $amount ) = split( / /, $amount );
    $amount = sprintf( "%.2f", $amount + .0001 );
    $bd[6] = "<amount>$amount</amount>";

    if ( $transid ne "" ) {
      $bd[7] = "<txn_number>$transid</txn_number>";
    } else {
      $bd[7] = "<pan>$cardnumber</pan>";
      $expdate = substr( $exp, 3, 2 ) . substr( $exp, 0, 2 );
      $bd[8] = "<expdate>$expdate</expdate>";
    }

    if ( $card_type eq "ax" ) {
      $eci = '7';    # request flag 07 - encrypted, 08 - non-secure (2n)
    } elsif ( ( $transflags =~ /bill/ ) && ( ( $transflags =~ /moto/ ) || ( $industrycode =~ /retail|restaurant/ ) ) ) {
      $eci = '1';    # request flag 01 - single bill payment (2n)
    } elsif ( $transflags =~ /install/ ) {
      $eci = '3';    # request flag 03 - installment payment (2n)
    } elsif ( ( $transflags =~ /recurring/ ) && ( $transflags !~ /bill|install/ ) ) {
      $eci = '2';    # request flag 07 - encrypted, 08 - non-secure (2n)
    } elsif ( $transflags =~ /moto/ ) {
      $eci = '1';    # request flag 01 - moto (2n)
    } elsif ( ( $cavv ne "" ) && ( $eci =~ /^(03|05)$/ ) ) {
      $eci = '5';    # request flag 07 - encrypted, 08 - non-secure (2n)
    } elsif ( $eci ne "" ) {
      $eci = '6';    # request flag 07 - encrypted, 08 - non-secure (2n)
    } else {
      $eci = '7';
    }
    $bd[9] = "<crypt_type>$eci</crypt_type>";

    $bd[10] = "</$ttcode>";

    $bd[11] = "</request>";

  } else {
    $bd[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>";
    $bd[1] = "<request>";
    $bd[2] = "<store_id>$merchant_id</store_id>";
    $bd[3] = "<api_token>$terminal_id</api_token>";

    if ( $merchant_id =~ /^monu/i ) {
      $bd[4] = "<us_completion>";
    } else {
      $bd[4] = "<completion>";
    }

    $bd[5] = "<order_id>$orderid" . "1</order_id>";
    ( $currency, $amount ) = split( / /, $amount );
    $amount = sprintf( "%.2f", $amount + .0001 );
    $bd[6] = "<comp_amount>$amount</comp_amount>";

    $transid = substr( $auth_code, 19, 10 );
    $transid =~ s/ //g;
    $transidnew = substr( $auth_code, 78, 16 );
    $transidnew =~ s/ //g;
    if ( $transidnew ne "" ) {
      $transid = $transidnew;
    }
    $bd[7] = "<txn_number>$transid</txn_number>";

    if ( $card_type eq "ax" ) {
      $eci = '7';    # request flag 07 - encrypted, 08 - non-secure (2n)
    } elsif ( ( $transflags =~ /bill/ ) && ( ( $transflags =~ /moto/ ) || ( $industrycode =~ /retail|restaurant/ ) ) ) {
      $eci = '1';    # request flag 01 - single bill payment (2n)
    } elsif ( $transflags =~ /install/ ) {
      $eci = '3';    # request flag 03 - installment payment (2n)
    } elsif ( ( $transflags =~ /recurring/ ) && ( $transflags !~ /bill|install/ ) ) {
      $eci = '2';    # request flag 07 - encrypted, 08 - non-secure (2n)
    } elsif ( $transflags =~ /moto/ ) {
      $eci = '1';    # request flag 01 - moto (2n)
    } elsif ( ( $cavv ne "" ) && ( $eci =~ /^(03|05)$/ ) ) {
      $eci = '5';    # request flag 07 - encrypted, 08 - non-secure (2n)
    } elsif ( $eci ne "" ) {
      $eci = '6';    # request flag 07 - encrypted, 08 - non-secure (2n)
    } else {
      $eci = '7';
    }
    $bd[10] = "<crypt_type>$eci</crypt_type>";

    if ( $merchant_id =~ /^monu/i ) {
      $bd[11] = "</us_completion>";
    } else {
      $bd[11] = "</completion>";
    }

    $bd[12] = "</request>";
  }

  $message = "";
  my $indent = 0;
  foreach $var (@bd) {
    if ( $var eq "" ) {
      next;
    }
    if ( $var =~ /^<\/.*>/ ) {
      $indent--;
    }

    #$message = $message . $var;
    $message = $message . " " x $indent . $var . "\n";
    if ( ( $var !~ /\// ) && ( $var != /<?/ ) ) {
      $indent++;
    }
    if ( $indent < 0 ) {
      $indent = 0;
    }
  }

}

sub printrecord {
  my ($printmessage) = @_;

  $temp = length($printmessage);
  my $printstr = "$temp\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );
  ($message2) = unpack "H*", $printmessage;
  my $printstr = "$message2\n\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );

  $message1 = $printmessage;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;

  #print "$message1\n$message2\n\n";
}

sub sendmessage {
  my ($msg) = @_;

  my $host    = "www3.moneris.com";                # production can
  my $port    = "443";
  my $path    = "/gateway2/servlet/MpgRequest";    # production can
  my $althost = "23.249.192.193";

  if ( $username eq "testmon" ) {
    $host    = "esplusqa.moneris.com";
    $path    = "/gateway_us/servlet/MpgRequest";
    $althost = "23.249.193.217";
  } elsif ( $merchant_id =~ /^monu/i ) {
    $host    = "esplus.moneris.com";               # production us
    $path    = "/gateway_us/servlet/MpgRequest";
    $althost = "23.249.193.217";
  }

  my $dnserrorflag = "";
  my $dest_ip      = gethostbyname($host);
  if ( $dest_ip eq "" ) {
    $host         = "$althost";
    $dnserrorflag = " dns error";
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
  $logfilestr .= "$host:$port  $path$althost\n";
  $logfilestr .= "$mytime send: $chkmessage\n\n";
  $logfilestr .= "sequencenum: $sequencenum retries: $retries\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  umask 0011;
  $logfiletmpstr = "";
  $logfiletmpstr .= "$username  $orderid  $operation\n";
  $logfiletmpstr .= "$host:$port  $path\n";
  $logfiletmpstr .= "$mytime send: $chkmessage\n\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris", "serverlogmsg.txt", "append", "", $logfiletmpstr );

  my %sslheaders = ();
  $sslheaders{'Host'}           = "$host:$port";
  $sslheaders{'Accept'}         = "*/*";
  $sslheaders{'Content-Length'} = $len;
  $sslheaders{'Content-Type'}   = 'application/xml; charset=\"utf-8\"';

  #my ($response) = &procutils::sendsslmsg("processor_moneris",$host,$port,$path,$msg,"direct",%sslheaders);
  $response = "";

  eval { ( $response, $header, %resulthash ) = &procutils::sendsslmsg( "processor_moneris", $host, $port, $path, $msg, "direct", %sslheaders ); };
  if ($@) {
    my $err = $@;
    print "err: $@\n";

    umask 0011;
    $mytime        = gmtime( time() );
    $logfiletmpstr = "";
    $logfiletmpstr .= "$mytime err: $err\n\n";
    &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris/$fileyear", "$username$time.txt", "append", "", $logfiletmpstr );
  }

  $mytime = gmtime( time() );
  my $chkmessage = $response;
  $chkmessage =~ s/\n/;;;;/g;
  $chkmessage =~ s/\>\</\>\n\</g;
  $chkmessage =~ s/;;;;/\n/g;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username  $orderid\n";
  $logfilestr .= "$mytime recv: $chkmessage\n\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  umask 0011;
  $logfiletmpstr = "";
  $logfiletmpstr .= "$username  $orderid  $operation\n";
  $logfiletmpstr .= "$mytime recv: $chkmessage\n\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/moneris", "serverlogmsg.txt", "append", "", $logfiletmpstr );

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

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  my $printstr = "origtime: $origtime $timezone1\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );

  if ( length($origtime) != 14 ) {
    return $origtime;
  }

  # timezone  hours  week of month  day of week  month  time   hours  week of month  day of week  month  time
  %timezonearray = (
    'EST', '-4,2,0,3,02:00, -5,1,0,11,02:00',    # 4 hours starting 2nd Sunday in March at 2am, 5 hours starting 1st Sunday in November at 2am
    'CST', '-5,2,0,3,02:00, -6,1,0,11,02:00',    # 5 hours starting 2nd Sunday in March at 2am, 6 hours starting 1st Sunday in November at 2am
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
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month2 happens on wday $wday\n";

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $printstr = "The $times2 Sunday of month $month2 happens on the $mday2\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );
  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  my $printstr = "newtime: $newtime $timezone2\n\n";
  &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/devlogs/moneris", "miscdebug.txt", "append", "misc", $printstr );

  return $newtime;
}

