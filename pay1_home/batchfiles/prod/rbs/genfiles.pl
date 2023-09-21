#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use rsautils;
use isotables;
use smpsutils;
use rbs;

$devprod = "logs";

my $host          = "tptrans.lynksystems.com";    # production
my $secondaryHost = "api.lynksystems.com";
my $port          = "443";
my $path          = "servlet/LynkePmtServlet";

if ( -e "/home/p/pay1/batchfiles/$devprod/rbs/secondary.txt" ) {
  $host = $secondaryHost;
}

# 2017 fall time change, to prevent genfiles from running twice
# exit if time is between 6am gmt and 7am gmt
my $timechange = "20171105020000";    # 2am eastern on the morning of the time change (1am to 1am to 2am)

my $str6am  = $timechange + 40000;                 # str represents 6am gmt
my $str7am  = $timechange + 50000;                 # str represents 7am gmt
my $time6am = &miscutils::strtotime("$str6am");    # 6am gmt
my $time7am = &miscutils::strtotime("$str7am");    # 7am gmt
my $now     = time();

if ( ( $now >= $time6am ) && ( $now < $time7am ) ) {
  print "exiting due to fall time change\n";
  exit;
}

if ( -e "/home/p/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'rbs/genfiles'`;
if ( $cnt > 1 ) {
  print "genfiles.pl already running, exiting...\n";

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: rbs - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

#open(checkin,"/home/p/pay1/batchfiles/$devprod/rbs/genfiles.txt");
#$checkuser = <checkin>;
#chop $checkuser;
#close(checkin);

#if (($checkuser =~ /^z/) || ($checkuser eq "")) {
#  $checkstring = "";
#}
#else {
#  $checkstring = "and t.username>='$checkuser'";
#}
#$checkstring = "and t.username='testrbs'";

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
my $filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
my $fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/p/pay1/batchfiles/$devprod/rbs/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/p/pay1/batchfiles/$devprod/rbs/$fileyearonly");
  chmod( 0700, "/home/p/pay1/batchfiles/$devprod/rbs/$fileyearonly" );
}
if ( !-e "/home/p/pay1/batchfiles/$devprod/rbs/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/p/pay1/batchfiles/$devprod/rbs/$filemonth");
  chmod( 0700, "/home/p/pay1/batchfiles/$devprod/rbs/$filemonth" );
}
if ( !-e "/home/p/pay1/batchfiles/$devprod/rbs/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/p/pay1/batchfiles/$devprod/rbs/$fileyear");
  chmod( 0700, "/home/p/pay1/batchfiles/$devprod/rbs/$fileyear" );
}
if ( !-e "/home/p/pay1/batchfiles/$devprod/rbs/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: rbs - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/rbs/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;

$dbh2 = &miscutils::dbhconnect("pnpdata");

# xxxx
#and t.username='paragont'
# homeclip should not be batched, it shares the same account as golinte1
$sthtrans = $dbh2->prepare(
  qq{
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>='$onemonthsago'
        and t.trans_date<='$today'
        $checkstring
        and t.finalstatus in ('pending','locked')
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.processor='rbs'
        and o.lastoptime>='$onemonthsagotime'
        group by t.username
  }
  )
  or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthtrans->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthtrans->bind_columns( undef, \( $user, $usercount, $usertdate ) );
while ( $sthtrans->fetch ) {
  print "$user $usercount $usertdate\n";
  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}
$sthtrans->finish;

foreach $username ( sort @userarray ) {
  if ( -e "/home/p/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
    unlink "/home/p/pay1/batchfiles/$devprod/rbs/batchfile.txt";
    last;
  }

  umask 0033;
  open( checkin, ">/home/p/pay1/batchfiles/$devprod/rbs/genfiles.txt" );
  print checkin "$username\n";
  close(checkin);

  umask 0033;
  open( batchfile, ">/home/p/pay1/batchfiles/$devprod/rbs/batchfile.txt" );
  print batchfile "$username\n";
  close(batchfile);

  $starttransdate = $starttdatearray{$username};

  print "$username $usercountarray{$username} $starttransdate\n";

  if ( $usercountarray{$username} > 2000 ) {
    $batchcntuser = 500;    # rbs recommends batches smaller than 500
  } elsif ( $usercountarray{$username} > 1000 ) {
    $batchcntuser = 500;
  } elsif ( $usercountarray{$username} > 600 ) {
    $batchcntuser = 200;
  } elsif ( $usercountarray{$username} > 300 ) {
    $batchcntuser = 100;
  } else {
    $batchcntuser = 50;
  }

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  %errorderid    = ();
  $detailnum     = 0;
  $batchsalesamt = 0;
  $batchsalescnt = 0;
  $batchretamt   = 0;
  $batchretcnt   = 0;
  $batchcnt      = 1;

  $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sthcust = $dbh->prepare(
    qq{
        select c.merchant_id,c.pubsecret,c.proc_type,c.company,c.addr1,c.city,c.state,c.zip,c.tel,c.status,r.industrycode,r.storeid,r.sellerid,r.password
        from customers c, rbs r
        where c.username='$username'
        and c.username=r.username
        }
    )
    or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthcust->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $merchant_id, $terminal_id, $proc_type, $company, $address, $city, $state, $zip, $tel, $status, $industrycode, $storeid, $sellerid, $password ) = $sthcust->fetchrow;
  $sthcust->finish;

  $dbh->disconnect;

  if ( $status ne "live" ) {
    next;
  }

  umask 0077;
  open( logfile, ">/home/p/pay1/batchfiles/$devprod/rbs/$fileyear/$username$time.txt" );
  print "$username\n";
  print logfile "$username\n";
  close(logfile);

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
  print "sweeptime: $sweeptime\n";
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/rbs/$fileyear/$username$time.txt" );
      print logfile "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      close(logfile);
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/rbs/$fileyear/$username$time.txt" );
      print logfile "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      close(logfile);
      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  print "gmt today: $todaytime\n";
  print "est today: $esttime\n";
  print "est yesterday: $yesterday\n";
  print "settletime: $settletime\n";
  print "sweeptime: $sweeptime\n";

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/rbs/$fileyear/$username$time.txt" );
  print "$username\n";
  print logfile "$username  sweeptime: $sweeptime  settletime: $settletime\n";
  print logfile "$features\n";
  close(logfile);

  print "aaaa $starttransdate $onemonthsagotime $username\n";

  $batch_flag = 0;
  $netamount  = 0;
  $hashtotal  = 0;
  $batchcnt   = 1;
  $recseqnum  = 0;

  $sthtrans = $dbh2->prepare(
    qq{
        select orderid
        from operation_log
        where trans_date>='$starttransdate'
        and lastoptime>='$onemonthsagotime'
        and username='$username'
        and lastopstatus in ('pending','locked')
        and lastop IN ('auth','postauth','return')
        and (voidstatus is NULL or voidstatus ='')
        and (accttype is NULL or accttype ='' or accttype='credit')
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthtrans->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthtrans->bind_columns( undef, \($orderid) );

  @orderidarray = ();
  while ( $sthtrans->fetch ) {

    #@orderidarray = (@orderidarray,$orderid);
    $orderidarray[ ++$#orderidarray ] = $orderid;
  }
  $sthtrans->finish;

  foreach $orderid ( sort @orderidarray ) {
    if ( -e "/home/p/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
      unlink "/home/p/pay1/batchfiles/$devprod/rbs/batchfile.txt";
      last;
    }

    # operation_log should only have one orderid per username
    if ( $orderid eq $chkorderidold ) {
      next;
    }
    $chkorderidold = $orderid;

    if ( ( $sweeptime ne "" ) && ( $trans_time > $sweeptime ) ) {
      $orderidold = $orderid;
      next;    # transaction is newer than sweeptime
    }

    $sthtrans2 = $dbh2->prepare(
      qq{
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,
                 auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,origamount,
                 forceauthstatus,card_name,card_addr,card_city,card_state,card_zip,card_country
          from operation_log
          where orderid='$orderid'
          and username='$username'
          and trans_date>='$starttransdate'
          and lastoptime>='$onemonthsagotime'
          and lastopstatus in ('pending','locked')
          and lastop IN ('auth','postauth','return')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthtrans2->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ( $orderid,     $operation, $trans_date, $trans_time, $enccardnumber,   $enclength, $exp,       $amount,    $auth_code,  $avs_code, $refnumber,
      $finalstatus, $cvvresp,   $transflags, $origamount, $forceauthstatus, $card_name, $card_addr, $card_city, $card_state, $card_zip, $card_country
    )
      = $sthtrans2->fetchrow;
    $sthtrans2->finish;

    if ( $orderid eq "" ) {
      next;
    }

    if ( ( $proc_type eq "authcapture" ) && ( $operation eq "postauth" ) ) {
      next;
    }

    if ( ( $transflags =~ /capture/ ) && ( $operation eq "postauth" ) ) {
      next;
    }

    if ( $forceauthstatus eq "success" ) {
      $origoperation = "forceauth";
    } elsif ( $operation eq "return" ) {
      $origoperation = "return";
    } else {
      $origoperation = "auth";
    }

    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/rbs/$fileyear/$username$time.txt" );
    print logfile "$orderid $operation\n";
    close(logfile);
    print "$orderid $operation $auth_code $refnumber\n";

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "rbs", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

    $card_type = &smpsutils::checkcard($cardnumber);

    if ( ( $card_type eq "pl" ) || ( $card_type eq "" ) ) {
      next;    # don't run genfiles on private label cards
    }

    $errorflag = &errorchecking();
    print "cccc $errorflag\n";
    if ( $errorflag == 1 ) {
      next;
    }

    if ( $batchcnt == 1 ) {
      $batchnum = "";

      #&getbatchnum();
    }

    my $sthlock = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='locked',result='$time$batchnum',detailnum='$detailnum'
	    where orderid='$orderid'
	    and trans_date>='$onemonthsago'
	    and finalstatus in ('pending','locked')
	    and username='$username'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthlock->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthlock->finish;

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    my $sthop = $dbh2->prepare(
      qq{
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending',detailnum='$detailnum'
          where orderid='$orderid'
          and username='$username'
          and $operationstatus in ('pending','locked')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute("$time$batchnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;

    &batchdetail();

    my $messagestr = $message;
    my $xs         = "x" x length($cardnumber);
    $messagestr =~ s/$cardnumber/$xs/;

    $mytime = gmtime( time() );

    #my $week = substr($rbs::trans_time,6,2) / 7;
    #$week = sprintf("%d", $week + .0001);
    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/rbs/$fileyear/$username$time.txt" );
    print logfile "$username  $orderid  $refnumber  $shacardnumber\n";
    print logfile "$mytime send: $messagestr\n\n";
    print "host: $host $port\n";
    print "$mytime send: $username $transid $messagestr\n\n";
    close(logfile);

    my $response = &rbs::sslsocketwrite( $message, $host, $port, $path );

    my $temptime   = gmtime( time() );
    my $chkmessage = $response;
    $chkmessage =~ s/></>\n</g;
    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/rbs/$fileyear/$username$time.txt" );
    print logfile "$temptime recv: $chkmessage\n\n";
    print "$temptime recv: $chkmessage\n\n";
    close(logfile);

    #if ($response ne "") {
    #  open(logfile2,">>/home/p/pay1/batchfiles/$devprod/rbs/bserverlogmsg.txt");
    #  print logfile2 "$temptime recv: $response\n\n";
    #  close(logfile2);
    #}

    &endbatch($response);

    if ( $batchcnt >= $batchcntuser ) {
      $errorrecseqnum = -1;
      %errorderid     = ();
      $detailnum      = 0;
      $batchsalesamt  = 0;
      $batchsalescnt  = 0;
      $batchretamt    = 0;
      $batchretcnt    = 0;
      $batchcnt       = 1;
    }
  }

  if ( $batchcnt > 1 ) {
    %errorderid = ();
    $detailnum  = 0;
  }
}

if ( !-e "/home/p/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  umask 0033;
  open( checkin, ">/home/p/pay1/batchfiles/$devprod/rbs/genfiles.txt" );
  close(checkin);
}

$dbh2->disconnect;

unlink "/home/p/pay1/batchfiles/$devprod/rbs/batchfile.txt";

exit;

sub endbatch {
  my ($response) = @_;

  $response =~ s/\r{0,1}\n//;

  my %temparray2 = ();
  my (@tmpfields) = split( /&/, $response );
  foreach my $var (@tmpfields) {
    my ( $name, $value ) = split( /=/, $var );
    $temparray2{"$name"} = $value;
  }

  #open(logfile,">>/home/p/pay1/batchfiles/$devprod/rbs/serverlogmsg.txt");
  #foreach my $key (keys %temparray2) {
  #  print logfile "aa $key    bb $temparray2{$key}\n";
  #}
  #print logfile "\n\n";
  #close(logfile);

  $respcode = $temparray2{'TransactionStatus'};

  my $appmssg = $temparray2{'ErrorMsg'};
  my ( $d1, $d2, $rspcode, $d4, $errmsg ) = split( /[,:]/, $appmssg );
  if ( $errmsg ne "" ) {
    $appmssg = "$errmsg";
  }
  if ( $rspcode ne "" ) {
    $respcode = $rspcode;
  }

  #$appmssg = $temparray2{'soap:Envelope,soap:Body,ProcessResponse,ProcessResult,Response_Reason_Text'};
  #$appmssg = "$respcode" . ": $msg";
  #$newrefnumber = $temparray2{'soap:Envelope,soap:Body,ProcessResponse,ProcessResult,Transaction_ID'};

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/rbs/$fileyear/$username$time.txt" );
  print logfile "orderid   $errorderid{$errorrecseqnum}\n";
  print logfile "respcode   $respcode\n";
  print logfile "appmssg   $appmssg\n";
  print logfile "refnumber   $newrefnumber\n";
  print logfile "result   $time$batchnum\n\n\n";

  print "orderid   $orderid\n";
  print "respcode   $respcode\n";
  print "appmssg   $appmssg\n";
  print "timestamp   $timestamp\n";
  print "result   $time$batchnum\n";
  close(logfile);

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  if ( ( $respcode =~ /^(0)$/ )
    || ( ( $respcode eq "1" ) && ( $appmssg =~ /Order is in the Settled State/ ) && ( $operation eq "postauth" ) )
    || ( ( $respcode eq "PAC7" ) && ( $operation eq "postauth" ) && ( $origoperation ne "forceauth" ) ) ) {

    #if (($origoperation eq "forceauth") && ($operation eq "postauth")) {
    #  $refnumber = $newrefnumber;
    #}

    print "$respcode  $orderid  $onemonthsago  $time$batchnum  $username\n";
    my $sthpass = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='success',trans_time=?
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and result='$time$batchnum'
            and username='$username'
            and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpass->execute("$time") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpass->finish;

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set $operationstatus='success',lastopstatus='success',$operationtime=?,lastoptime=?
            where orderid='$orderid'
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute( "$time", "$time" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );

  } elsif ( $respcode ne "" ) {
    my $sthfail = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='problem',descr=?
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and username='$username'
            and (accttype is NULL or accttype ='' or accttype='credit')
            and finalstatus='locked'
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthfail->execute("$respcode: $appmssg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthfail->finish;

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid='$orderid'
            and lastoptime>='$onemonthsagotime'
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute("$respcode: $appmssg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );

    #open(MAILERR,"| /usr/lib/sendmail -t");
    #print MAILERR "To: cprice\@plugnpay.com\n";
    #print MAILERR "From: dcprice\@plugnpay.com\n";
    #print MAILERR "Subject: rbs - FORMAT ERROR\n";
    #print MAILERR "\n";
    #print MAILERR "username: $username\n";
    #print MAILERR "result: format error\n\n";
    #print MAILERR "batchtransdate: $batchtransdate\n";
    #close MAILERR;
  } elsif ( $errorflag eq "DATA_ERROR" ) {
    my $sthfail = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='pending',descr=?
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and username='$username'
            and (accttype is NULL or accttype ='' or accttype='credit')
            and finalstatus='locked'
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthfail->execute("$respcode: $appmssg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthfail->finish;

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set $operationstatus='pending',lastopstatus='pending',descr=?
            where orderid='$orderid'
            and lastoptime>='$onemonthsagotime'
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute("$respcode: $appmssg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: rbs - DATA ERROR\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: data error\n\n";
    print MAILERR "batchtransdate: $batchtransdate\n";
    close MAILERR;
  } elsif ( $respcode eq "PENDING" ) {
  } else {
    print "respcode	$respcode unknown\n";
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: rbs - unkown error\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $resp\n";
    print MAILERR "file: $username$time.txt\n";
    close MAILERR;
  }

}

sub getbatchnum {
  my $sthinfo = $dbh->prepare(
    qq{
          select batchnum
          from rbs
          where username='$username'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ($batchnum) = $sthinfo->fetchrow;
  $sthinfo->finish;

  $batchnum = $batchnum + 1;
  if ( $batchnum >= 998 ) {
    $batchnum = 1;
  }

  my $sthinfo = $dbh->prepare(
    qq{
          update rbs set batchnum=?
          where username='$username'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute("$batchnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthinfo->finish;

  $batchnum = substr( "0000" . $batchnum, -4, 4 );

}

sub batchdetail {

  $currency = substr( $amount, 0, 3 );
  $currency =~ tr/a-z/A-Z/;
  my $exponent = $isotables::currencyUSD2{$currency};
  $transamt = substr( $amount, 4 );
  $transamt = $transamt * ( 10**$exponent );
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

  my %bd = ();

  my $tcode = "";
  if ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
    $tcode = "ForceSettle";
  } elsif ( $operation eq "postauth" ) {
    $tcode = "Settle";
  } elsif ( $operation eq "return" ) {
    $tcode = "Credit";
  }
  $bd{"SvcType"}     = "$tcode";        # Service Type
  $bd{"StoreId"}     = $storeid;        # Store id
  $bd{"SellerId"}    = "$sellerid";     # Seller id
  $bd{"Password"}    = "$password";     # Password
  $bd{"MerchantID"}  = $merchant_id;    # Merchant ID
  $bd{"TerminalId"}  = $terminal_id;    # Terminal ID
  $bd{"CustOrderId"} = $orderid;        # Customer orderid
  $bd{"OrderId"}     = $refnumber;      # Transaction ID

  my ( $fname, $lname ) = split( / /, $card_name );
  $fname =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
  $lname =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
  $bd{"FirstName"}     = $fname;           # First Name
                                           #$bd{"MiddleName"} = yyyy;                           # Middle Name
  $bd{"LastName"}      = $lname;           # Last Name
                                           #$bd{"BusinessName"} = yyyy;                         # Business Name
  $bd{"StreetAddress"} = $card_addr;       # Street Address
  $bd{"City"}          = $card_city;       # City
  $bd{"State"}         = $card_state;      # State
  $bd{"Zip"}           = $card_zip;        # Zip
  $bd{"Country"}       = $card_country;    # Country
                                           #$bd{"Email"} = $rbs::datainfo{'email'};		# email
  $bd{"Phone"}         = $phone;           # phone

  $bd{"PC2On"} = "Y";                      # purchase card indicator

  my $apptype = "LE";
  if ( ( $industrycode eq "retail" ) && ( $transflags !~ /moto/ ) ) {
    $apptype = "LG";
  } elsif ( ( $industrycode eq "restaurant" ) && ( $transflags !~ /moto/ ) ) {
    $apptype = "LF";
  }
  $bd{"AppType"} = $apptype;               # application type

  $bd{"CardNumber"}     = $cardnumber;     # card number
  $bd{"ExpirationDate"} = $exp;            # expiration date

  my $eci         = "";
  my $cardpresent = "";
  if ( ( $industrycode eq "retail" ) && ( $transflags !~ /moto/ ) ) {
    $eci         = "0";
    $cardpresent = "1";
  } elsif ( $transflags =~ /recurring/ ) {
    $eci         = "2";
    $cardpresent = "0";
  } elsif ( $transflags =~ /moto/ ) {
    $eci         = "1";
    $cardpresent = "0";
  } else {
    $eci         = "7";
    $cardpresent = "0";
  }
  $bd{"EntryMode"} = $eci;            # entry mode
  $bd{"Signature"} = $cardpresent;    # card present

  #$bd{"IDMethod"} = "6";                              # eci
  #$bd{"ShipToZipCode"} = $zip;        # ship zip
  #$bd{"ShipToCountry"} = $country;    # ship country
  my ( $curr, $amt ) = split( / /, $amount );
  $bd{"Amount"} = $amt;    # amount

  if ( $industrycode eq "restaurant" ) {
    my $gratuity = substr( $auth_code, 63, 9 );
    $gratuity =~ s/ //g;
    if ( ( $gratuity ne "" ) && ( $gratuity ne "000000.00" ) ) {
      $gratuity = sprintf( "%.2f", $gratuity + .0001 );
      $bd{"TipAmount"} = $gratuity;    # amount
    }
  }

  if ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
    $authcode = substr( $auth_code, 0, 6 );
    $authcode =~ s/ //g;
    $bd{"ApprovalCode"} = $authcode;    # approval code
  }

  my $commflag = substr( $auth_code, 62, 1 );

  if ( $commflag eq "1" ) {
    my $ponumber = substr( $auth_code, 8, 17 );
    $ponumber =~ s/ //g;
    if ( $ponumber eq "" ) {
      $ponumber = $orderid;
      $ponumber = substr( $ponumber, -17, 17 );
    }
    $bd{"PC2CustId"} = $ponumber;       # purchase order number

    my $tax = substr( $auth_code, 35, 9 );
    $bd{"TaxAmount"} = $tax;            # tax

    if ( ( $transflags =~ /exempt/ ) && ( $transflags !~ /notexempt/ ) ) {
      $bd{"TaxExempt"} = "Y";           # tax exempt indicator
    } else {
      $bd{"TaxExempt"} = "N";
    }
  }

  $message = "";
  foreach my $key ( sort keys %bd ) {
    my $value = $bd{$key};
    if ( $value ne "" ) {
      $value =~ s/(\W)/'%' . unpack("H2",$1)/ge;
      $message = $message . "$key=$value\&";
    }
  }
  chop $message;
}

sub printrecord {
  my ($printmessage) = @_;

  $temp = length($printmessage);
  print "$temp\n";
  ($message2) = unpack "H*", $printmessage;
  print "$message2\n\n";

  $message1 = $printmessage;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;

  #print "$message1\n$message2\n\n";
}

sub errorchecking {

  #my $chkauthcode = substr($auth_code,0,8);
  #$authcode =~ s/ //g;

  #if ((($origoperation eq "forceauth") && ($operation eq "postauth") && ($chkauthcode eq ""))
  #    || (($origoperation ne "forceauth") && ($refnumber eq ""))) {
  #print "dddd $username $orderid $operation $chkauthcode $auth_code $refnumber\n";
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

  $clen = length($cardnumber);
  $cabbrev = substr( $cardnumber, 0, 4 );
  if ( $card_type eq "" ) {
    &errormsg( $username, $orderid, $operation, 'bad card number' );
    return 1;
  }
  return 0;
}

sub errormsg {
  my ( $username, $orderid, $operation, $errmsg ) = @_;

  my $sthtest = $dbh2->prepare(
    qq{
            update trans_log set finalstatus='problem',descr=?
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and username='$username'
            and finalstatus='pending'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthtest->execute("$errmsg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthtest->finish;

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";
  %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
  my $sthop = $dbh2->prepare(
    qq{
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid='$orderid'
            and username='$username'
            and lastoptime>='$onemonthsagotime'
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthop->execute("$errmsg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthop->finish;

}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  print "origtime: $origtime $timezone1\n";

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

  print "The $times1 Sunday of month $month1 happens on the $mday1\n";

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month2 happens on wday $wday\n";

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  print "The $times2 Sunday of month $month2 happens on the $mday2\n";

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

  print "zoneadjust: $zoneadjust\n";
  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  print "newtime: $newtime $timezone2\n\n";
  return $newtime;

}

