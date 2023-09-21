#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use IO::Socket;
use Socket;
use rsautils;
use smpsutils;
use litle;
use Time::Local;

$devprod = "logs";

if ( -e "/home/p/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  exit;
}

# https://reports.iq.vantivcnp.com/ui/login   to change the passwd
#$passwd = "9Jjz2A5pMgrrWvu"; # 201707
$passwd = "YjNxzEzGz3RHnkr";    # 20180723
$passwd = "wSGXoiQQuASU7sW";    # 20190717 - expires 2020/07/16
$passwd = "bnYyaa7Kj6nQvbd";    # 20200618 - expires 2021/06/17
$passwd = "mdWrLJMZuxy2C9A";    # 20210604 - expires 2022/06/04
$passwd = "eEu7exfc5SDWxrp";    # 20220531 - expires 2023/05/31

#open(checkin,"/home/p/pay1/batchfiles/$devprod/litle/genfiles.txt");
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

$socketaddr = "copper.plugnpay.com";
$socketport = "8348";

#&socketopen($socketaddr,"$socketport");

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

if ( !-e "/home/p/pay1/batchfiles/$devprod/litle/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/p/pay1/batchfiles/$devprod/litle/$fileyearonly");
  chmod( 0700, "/home/p/pay1/batchfiles/$devprod/litle/$fileyearonly" );
}
if ( !-e "/home/p/pay1/batchfiles/$devprod/litle/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/p/pay1/batchfiles/$devprod/litle/$filemonth");
  chmod( 0700, "/home/p/pay1/batchfiles/$devprod/litle/$filemonth" );
}
if ( !-e "/home/p/pay1/batchfiles/$devprod/litle/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/p/pay1/batchfiles/$devprod/litle/$fileyear");
  chmod( 0700, "/home/p/pay1/batchfiles/$devprod/litle/$fileyear" );
}
if ( !-e "/home/p/pay1/batchfiles/$devprod/litle/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: litle - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/litle/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;

$dbh  = &miscutils::dbhconnect("pnpmisc");
$dbh2 = &miscutils::dbhconnect("pnpdata");

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
        and o.processor='litle'
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

#if (($checkstring ne "") && ($#userarray < 1)) {
#  $chkuser = $checkstring;
#  $chkuser =~ s/^.*\'(.*)\'.*/$1/g;
#  print "$chkuser\n";
#  @userarray = (@userarray,$chkuser);
#}

foreach $username ( sort @userarray ) {
  if ( -e "/home/p/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
    unlink "/home/p/pay1/batchfiles/$devprod/litle/batchfile.txt";
    last;
  }

  open( checkin, ">/home/p/pay1/batchfiles/$devprod/litle/genfiles.txt" );
  print checkin "$username\n";
  close(checkin);

  open( batchfile, ">/home/p/pay1/batchfiles/$devprod/litle/batchfile.txt" );
  print batchfile "$username\n";
  close(batchfile);

  $starttransdate = $starttdatearray{$username};

  print "$username $usercountarray{$username} $starttransdate\n";

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  %errorderid    = ();
  $detailnum     = 0;
  $batchsalesamt = 0;
  $batchsalescnt = 0;
  $batchretamt   = 0;
  $batchretcnt   = 0;
  $batchcnt      = 1;

  my $sthcust = $dbh->prepare(
    qq{
        select c.merchant_id,c.pubsecret,c.proc_type,c.company,c.addr1,c.city,c.state,c.zip,c.tel,c.status,c.features,
        e.industrycode,e.loginun,e.loginpw
        from customers c, litle e
        where c.username='$username'
        and e.username=c.username
        }
    )
    or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthcust->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $merchant_id, $terminal_id, $proc_type, $company, $address, $city, $state, $zip, $tel, $status, $features, $industrycode, $loginun, $loginpw ) = $sthcust->fetchrow;
  $sthcust->finish;

  if ( $status ne "live" ) {
    next;
  }

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/litle/$fileyear/$username$time.txt" );
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
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/litle/$fileyear/$username$time.txt" );
      print logfile "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      close(logfile);
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/litle/$fileyear/$username$time.txt" );
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
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/litle/$fileyear/$username$time.txt" );
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
        select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,refnumber,
               lastopstatus,cvvresp,transflags,origamount,forceauthstatus,card_name,card_addr,card_city,card_state,
               card_zip,card_country,email
        from operation_log
        where trans_date>='$starttransdate'
        and lastoptime>='$onemonthsagotime'
        and username='$username'
        and lastopstatus in ('pending')
        and lastop IN ('auth','postauth','return','forceauth')
        and (voidstatus is NULL or voidstatus ='')
        and (accttype is NULL or accttype ='' or accttype='credit')
        order by orderid
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthtrans->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthtrans->bind_columns(
    undef,
    \($orderid,   $operation, $trans_date, $trans_time,  $enccardnumber, $enclength,    $exp,        $amount,
      $auth_code, $avs_code,  $refnumber,  $finalstatus, $cvvresp,       $transflags,   $origamount, $forceauthstatus,
      $card_name, $card_addr, $card_city,  $card_state,  $card_zip,      $card_country, $email
     )
  );

  while ( $sthtrans->fetch ) {
    if ( -e "/home/p/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
      unlink "/home/p/pay1/batchfiles/$devprod/litle/batchfile.txt";
      last;
    }

    if ( ( $proc_type eq "authcapture" ) && ( $operation eq "postauth" ) ) {
      next;
    }

    if ( ( $sweeptime ne "" ) && ( $trans_time > $sweeptime ) ) {
      next;    # transaction is newer than sweeptime
    }

    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/litle/$fileyear/$username$time.txt" );
    print logfile "$orderid $operation\n";
    close(logfile);
    print "$orderid $operation $auth_code $refnumber\n";

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "litle", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

    $card_type = &smpsutils::checkcard($cardnumber);
    if ( $card_type eq "dc" ) {
      $card_type = "mc";
    }

    # xxxx
    #if (($username eq "variousinc3") && ($forceauthstatus ne "") && ($operation eq "postauth")) {
    #  next;
    #}

    $errorflag = &errorchecking();
    print "cccc $errorflag\n";
    if ( $errorflag == 1 ) {
      next;
    }

    if ( $batchcnt == 1 ) {
      $batchnum = "";

      #&getbatchnum();
    }
    print "before update\n";

    my $sthlock = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='locked',result='$time$batchnum',detailnum='$detailnum'
	    where orderid='$orderid'
	    and trans_date>='$onemonthsago'
	    and finalstatus='pending'
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
          and $operationstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute("$time$batchnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;
    print "after update\n";

    &batchdetail();

    if ( $username eq "testlitle" ) {
      $response = &socketwritessl( "transact-prelive.vantivcnp.com", "443", "/vap/communicator/online", $message );    # test
    } else {
      $response = &socketwritessl( "transact.vantivcnp.com", "443", "/vap/communicator/online", $message );            # production
    }

    &endbatch($response);
  }
  $sthtrans->finish;

  # xxxx
  if ( $batchcnt > 0 ) {
    %errorderid = ();
    $detailnum  = 0;

    # xxxx temp if commented out
    #&batchtrailer();
    #$response = &socketwritessl("secure.litletest.com","8086","/webTrans.aspx",$message);	# test
    #$response = &socketwritessl("secure.litle.com","8086","/webTrans.aspx",$message);		# production
    #print "$response\n";
  }
}

if ( !-e "/home/p/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  open( checkin, ">/home/p/pay1/batchfiles/$devprod/litle/genfiles.txt" );
  close(checkin);
}

$dbh->disconnect;
$dbh2->disconnect;

unlink "/home/p/pay1/batchfiles/$devprod/litle/batchfile.txt";

close(SOCK);

exit;

sub endbatch {
  my ($response) = @_;

  my $data = $response;

  $data =~ s/\n/ /g;
  $data =~ s/> *</>;;;;</g;
  my @tmpfields = split( /;;;;/, $data );
  my %temparray = ();
  my $levelstr  = "";
  foreach my $var (@tmpfields) {
    if ( $var =~ /<(.+)>(.*)</ ) {
      my $var2 = $1;
      my $var3 = $2;
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
    print "aa $key    bb $temparray{$key}\n";
  }

  my $tcode = "capture";
  if ( $operation eq "return" ) {
    $tcode = "credit";
  } elsif ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
    $tcode = "forceCapture";
  }

  $respcode = $temparray{ "litleOnlineResponse,$tcode" . "Response,response" };
  my $message = $temparray{ "litleOnlineResponse,$tcode" . "Response,message" };
  $message =~ s/  +/ /g;
  $err_msg = "$respcode: $message";
  my $statusid = $temparray{'XML,REQUEST,RESPONSE,ROW,STATUSID'};

  $refnumber = $temparray{ "litleOnlineResponse,$tcode" . "Response,litleTxnId" };
  $transid   = $temparray{'response,receipt,TransID'};

  if ( $respcode eq "null" ) {
    $respcode = "999";
  }

  open( tmpfile, ">>/home/p/pay1/batchfiles/$devprod/litle/scriptresults.txt" );
  print tmpfile "$refnumber\n";
  print tmpfile "aaaaaaaa $orderid  $operation  $refnumber\n";
  close(tmpfile);

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/litle/$fileyear/$username$time.txt" );
  print logfile "orderid   $orderid\n";
  print logfile "respcode   $respcode\n";
  print logfile "err_msg   $err_msg\n";
  print logfile "refnumber   $refnumber\n";
  print logfile "result   $time$batchnum\n\n\n";

  print "orderid   $orderid\n";
  print "transseqnum   $transseqnum\n";
  print "respcode   $respcode\n";
  print "err_msg   $err_msg\n";
  print "result   $time$batchnum\n\n\n";
  close(logfile);

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  if ( $respcode eq "000" ) {
    my $sthpass = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='success',trans_time=?,refnumber=?
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and result='$time$batchnum'
            and username='$username'
            and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpass->execute( "$time", "$refnumber" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpass->finish;

    print "update operation_log  $orderid  $onemonthsagotime  $operation  $username  $time$batchnum\n";

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set $operationstatus='success',lastopstatus='success',lastoptime=?,refnumber=?
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
    $sthop->execute( "$time", "$refnumber" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  } elsif ( ( ( $respcode eq "OK" ) && ( $operation ne "forceauth" ) )
    || ( ( $statusid eq "600" ) && ( $operation eq "forceauth" ) ) ) {

    my $sthpass = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='success',trans_time=?,refnumber=?
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and result='$time$batchnum'
            and username='$username'
            and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpass->execute( "$time", "$refnumber" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpass->finish;

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set $operationstatus='success',lastopstatus='success',$operationtime=?,lastoptime=?,refnumber=?
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
    $sthop->execute( "$time", "$time", "$refnumber" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );

  } elsif ( $respcode > 51 ) {
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
    $sthfail->execute("$err_msg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
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
    $sthop->execute("$err_msg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );

    #open(MAILERR,"| /usr/lib/sendmail -t");
    #print MAILERR "To: cprice\@plugnpay.com\n";
    #print MAILERR "From: dcprice\@plugnpay.com\n";
    #print MAILERR "Subject: litle - FORMAT ERROR\n";
    #print MAILERR "\n";
    #print MAILERR "username: $username\n";
    #print MAILERR "result: format error\n\n";
    #print MAILERR "batchtransdate: $batchtransdate\n";
    #close MAILERR;
  } elsif ( ( $operation eq "forceauth" ) && ( $statusid eq "99999" ) ) {
    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthfail = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='badcard'
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and username='$username'
            and (accttype is NULL or accttype ='' or accttype='credit')
            and finalstatus='locked'
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthfail->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthfail->finish;

    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set $operationstatus='badcard',lastopstatus='badcard'
            where orderid='$orderid'
            and lastoptime>='$onemonthsagotime'
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  } elsif ( ( $respcode =~ /RR/ ) || ( ( $operation eq "postauth" ) && ( $respcode eq "" ) ) || ( $operation eq "forceauth" ) ) {
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
    $sthfail->execute("$err_msg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
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
    $sthop->execute("$err_msg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );

  } elsif ( $respcode eq "PENDING" ) {
  } else {
    print "respcode	$respcode unknown\n";
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: litle - unkown error\n";
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
  my $sthinfo = $dbh->prepare(
    qq{
          select batchnum
          from litle
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
          update litle set batchnum=?
          where username='$username'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute("$batchnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthinfo->finish;

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
    $sthdate = $dbh2->prepare(
      qq{ 
          select authtime,authstatus,forceauthtime,forceauthstatus
          from operation_log 
          where orderid='$orderid' 
          and username='$username' 
          and lastoptime>='$onemonthsagotime'
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthdate->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ( $authtime, $authstatus, $forceauthtime, $forceauthstatus ) = $sthdate->fetchrow;
    $sthdate->finish;

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
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/litle/$fileyear/$username$time.txt" );
      print logfile "Error in batch detail: couldn't find trans_time $username $twomonthsago $orderid $trans_time\n";
      close(logfile);
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

  #$transseqnum = &litle::gettransid($username,"litle");

  @bd = ();

  my $mid = substr( $auth_code, 118, 10 );
  $mid =~ s/ //g;
  if ( $mid eq "" ) {
    $mid = $merchant_id;
  }

  if ( ( $operation eq "return" ) || ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
    $bd[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>";
    $bd[1] = "<litleOnlineRequest version=\"8.19\" xmlns=\"http://www.litle.com/schema\" merchantId=\"$mid\">";
    $bd[2] = "<authentication>";
    $bd[3] = "<user>u826045956261806093</user>";
    $bd[4] = "<password>$passwd</password>";
    $bd[5] = "</authentication>";

    if ( $operation eq "return" ) {
      $tcode = "credit";
    } else {
      $tcode = "forceCapture";
    }
    $bd[6] = "<$tcode id=\"$orderid\" reportGroup=\"$merchant_id\" customerId=\"\">";

    if ( $refnumber ne "" ) {
      $bd[8] = "<litleTxnId>$refnumber</litleTxnId>";
    } else {
      $bd[7] = "<orderId>$orderid</orderId>";
    }

    my $amount = sprintf( "%d", ( substr( $amount, 4 ) * 100 ) + .0001 );
    $bd[9] = "<amount>$amount</amount>";

    if ( $refnumber eq "" ) {
      my $src = "";
      if ( $transflags =~ /install/ ) {
        $src = "installment";
      } elsif ( $transflags =~ /recurring/ ) {
        $src = "recurring";
      } elsif ( $transflags =~ /moto/ ) {
        $src = "mailorder";
      } elsif ( $transflags =~ /phone/ ) {
        $src = "telephone";
      } elsif ( $industrycode eq "retail" ) {
        $src = "retail";
      } else {
        $src = "ecommerce";
      }
      $bd[14] = "<orderSource>$src</orderSource>";

      if ( $operation ne "return" ) {
        $bd[16] = "<billToAddress>";
        my ( $fname, $mname, $lname ) = split( / /, $card_name, 3 );
        if ( $lname eq "" ) {
          $lname = $mname;
          $mname = "";
        }
        my $name = $card_name;
        $name =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
        $fname =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
        $mname =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
        $lname =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
        $bd[17] = "<name>$name</name>";
        $bd[18] = "<firstName>$fname</firstName>";
        $bd[19] = "<middleInitial>$mname</middleInitial>";
        $bd[20] = "<lastName>$lname</lastName>";

        #my $card_company = $card_company;
        #$card_company =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
        #$bd[21] = "<companyName>$card_company</companyName>";

        $bd[22] = "<addressLine1>$card_addr</addressLine1>";
        $bd[23] = "<addressLine2></addressLine2>";
        $bd[24] = "<city>$card_city</city>";

        $card_country =~ tr/a-z/A-Z/;
        if ( ( $card_country eq "" ) || ( $card_country eq "US" ) || ( $card_country eq "CA" ) ) {
          $bd[25] = "<state>$card_state</state>";
        }
        $bd[26] = "<zip>$card_zip</zip>";
        $bd[27] = "<country>$card_country</country>";
        $bd[28] = "<email>$email</email> ";

        #$bd[29] = "<phone>$phone</phone>";
        $bd[30] = "</billToAddress>";
      }

      #$bd[23] = "<shipToAddress>";

      $bd[40] = "<card>";
      my $cardtype = $card_type;
      $cardtype =~ tr/a-z/A-Z/;
      if ( $cardtype eq "DS" ) {
        $cardtype = "DI";
      }
      $bd[41] = "<type>$cardtype</type>";
      $bd[42] = "<number>$cardnumber</number>";
      $monthexp = substr( $exp, 0, 2 );
      $yearexp  = substr( $exp, 3, 2 );
      $bd[43]   = "<expDate>$monthexp$yearexp</expDate>";
      $bd[45]   = "</card>";

      $commcardtype = substr( $auth_code, 98, 10 );
      $commcardtype =~ s/ //g;
      if ( $commcardtype ne "" ) {
        $bd[50] = "<enhancedData>";

        #$bd[51] = "<customerReference>$customerid</customerReference>";
        $tax = substr( $auth_code, 41, 12 );
        $tax =~ s/ //g;
        $tax = substr( "0" x 7 . $tax, -7, 7 );
        $bd[52] = "<salesTax>$tax</salesTax>";
        $taxex = substr( $auth_code, 97, 1 );
        if ( $taxex eq "1" ) {
          $bd[53] = "<taxExempt>true</taxExempt>";
        }

        #$bd[54] = "<discountAmount>$amount</discountAmount>";
        #$bd[55] = "<shippingAmount>$amount</shippingAmount>";
        #$bd[56] = "<dutyAmount>$amount</dutyAmount>";
        #$bd[57] = "<shipFromPostalCode>$amount</shipFromPostalCode>";
        #$bd[58] = "<destinationPostalCode>$amount</destinationPostalCode>";
        #$bd[59] = "<destinationCountryCode>$amount</destinationCountryCode>";
        $ponum = substr( $auth_code, 53, 25 );
        $ponum =~ s/ //g;
        $bd[60] = "<invoiceReferenceNumber>$ponum</invoiceReferenceNumber>";
        $bd[61] = "<orderDate>$amount</orderDate>";
        $bd[62] = "</enhancedData>";
      }

      $bd[70] = "<pos>";

      my $capability = "keyedonly";

      #if ($litle::magstripetrack =~ /(0|1|2)/) {
      #  $capability = "magstripe";
      #}
      $bd[71] = "<capability>$capability</capability>";

      my $entry = "keyed";

      #if ($litle::magstripetrack eq "2") {
      #  $entry = "track2";
      #}
      #elsif ($litle::magstripetrack eq "1") {
      #  $entry = "track1";
      #}
      $bd[72] = "<entryMode>$entry</entryMode>";

      my $cardid = "directmarket";
      if ( ( $industrycode eq "retail" ) && ( $transflags !~ /moto/ ) ) {
        $cardid = "signature";
      }
      $bd[73] = "<cardholderId>$cardid</cardholderId>";

      my $deviceid = substr( $auth_code, 108, 10 );
      $deviceid =~ s/ //g;
      if ( $deviceid ne "" ) {
        $deviceid = "$deviceid";
      } elsif ( $terminal_id ne "" ) {
        $deviceid = "$terminal_id";
      } else {
        $deviceid = "0001";
      }
      $bd[74] = "<terminalId>$deviceid</terminalId>";
      $bd[75] = "</pos>";
    }

    $bd[76] = "</$tcode>";
    $bd[77] = "</litleOnlineRequest>";
  } else {

    $bd[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>";
    $bd[1] = "<litleOnlineRequest version=\"8.19\" xmlns=\"http://www.litle.com/schema\" merchantId=\"$mid\">";
    $bd[2] = "<authentication>";
    $bd[3] = "<user>u826045956261806093</user>";
    $bd[4] = "<password>$passwd</password>";
    $bd[5] = "</authentication>";

    $bd[6] = "<capture id=\"$orderid\" reportGroup=\"$merchant_id\" customerId=\"\" partial=\"false\">";

    #$bd[7] = "<orderId>$orderid</orderId>";
    $bd[8] = "<litleTxnId>$refnumber</litleTxnId>";
    my $amount = sprintf( "%d", ( substr( $amount, 4 ) * 100 ) + .0001 );
    $bd[9] = "<amount>$amount</amount>";

    $commcardtype = substr( $auth_code, 98, 10 );
    $commcardtype =~ s/ //g;
    if ( $commcardtype ne "" ) {
      $bd[10] = "<enhancedData>";

      #$bd[11] = "<customerReference>$customerid</customerReference>";
      $tax = substr( $auth_code, 41, 12 );
      $tax =~ s/ //g;
      $tax = substr( "0" x 7 . $tax, -7, 7 );
      $bd[12] = "<salesTax>$tax</salesTax>";
      $taxex = substr( $auth_code, 97, 1 );
      if ( $taxex eq "1" ) {
        $bd[13] = "<taxExempt>true</taxExempt>";
      }

      #$bd[14] = "<discountAmount>$amount</discountAmount>";
      #$bd[15] = "<shippingAmount>$amount</shippingAmount>";
      #$bd[16] = "<dutyAmount>$amount</dutyAmount>";
      #$bd[17] = "<shipFromPostalCode>$amount</shipFromPostalCode>";
      #$bd[18] = "<destinationPostalCode>$amount</destinationPostalCode>";
      #$bd[19] = "<destinationCountryCode>$amount</destinationCountryCode>";
      $ponum = substr( $auth_code, 53, 25 );
      $ponum =~ s/ //g;
      $bd[20] = "<invoiceReferenceNumber>$ponum</invoiceReferenceNumber>";
      $bd[21] = "<orderDate>$amount</orderDate>";
      $bd[10] = "</enhancedData>";
    }
    $bd[23] = "</capture>";
    $bd[24] = "</litleOnlineRequest>";
  }

  $message = "";
  my $indent = 0;
  foreach $var (@bd) {
    if ( $var eq "" ) {
      next;
    }
    if ( $var =~ /></ ) {
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
  print "$temp\n";
  ($message2) = unpack "H*", $printmessage;
  print "$message2\n\n";

  $message1 = $printmessage;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;

  #print "$message1\n$message2\n\n";
}

sub socketopen {
  if ( $socketport =~ /\D/ ) { $socketport = getservbyname( $socketport, 'tcp' ) }
  die "No port" unless $socketport;
  $iaddr = inet_aton($socketaddr) or die "no host: $socketaddr";
  $paddr = sockaddr_in( $socketport, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) or die "socket: $!";
  $numretries = 0;
  connect( SOCK, $paddr ) or die "Couldn't connect: $!\n";
}

sub socketwritessl {
  my ( $host, $port, $path, $msg ) = @_;

  Net::SSLeay::load_error_strings();
  Net::SSLeay::SSLeay_add_ssl_algorithms();
  Net::SSLeay::randomize('/etc/passwd');

  #my $mime_type = 'application/xml; charset="utf-8"';
  #my $mime_type = 'application/x-www-form-urlencoded';

  #$msg = "IN=" . $msg;
  #my $content = "Content-Type: $mime_type\r\n" . "Content-Length: $len\r\n\r\n$msg";
  #my $req = "POST $path HTTP/1.0\r\nHost: $host\r\n" . "Accept: */*\r\n$content";
  #my $req = "POST $path HTTP/1.0\r\nHost: $host:$port\r\n" . "Accept: */*\r\n$content";

  my $len = length($msg);
  my $req = "POST $path HTTP/1.0\r\n";
  $req .= "Host: $host:$port\r\n";
  $req .= "Accept: */*\r\n";
  $req .= "Content-Type: application/xml; charset=\"utf-8\"\r\n";
  $req .= "Content-Length: $len\r\n\r\n";
  $req .= "$msg";

  #print "send:\n$req\n";

  $mytime = gmtime( time() );
  my $chkmessage = $req;
  if ( ( length($cardnumber) >= 13 ) && ( length($cardnumber) <= 19 ) ) {
    $xs = "x" x length($cardnumber);
    $chkmessage =~ s/$cardnumber/$xs/;
  }
  $chkmessage =~ s/\>\</\>\n\</g;
  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/litle/$fileyear/$username$time.txt" );
  print logfile "$username  $orderid\n";
  print logfile "$mytime send: $chkmessage\n\n";

  #print "$mytime send:\n$chkmessage\n\n";
  print logfile "sequencenum: $sequencenum retries: $retries\n";
  close(logfile);

  umask 0011;
  open( logfiletmp, ">>/home/p/pay1/batchfiles/$devprod/litle/serverlogmsg.txt" );
  print logfiletmp "$username  $orderid  $operation\n";
  print logfiletmp "$mytime send: $chkmessage\n\n";
  close(logfiletmp);

  $dest_ip = gethostbyname($host);
  $dest_serv_params = sockaddr_in( $port, $dest_ip );

  $flag = "success";
  socket( S, &AF_INET, &SOCK_STREAM, 0 ) or return ( &errmssg( "socket: $!", 1 ) );

  connect( S, $dest_serv_params ) or $flag = &retry();
  if ( $flag ne "success" ) {
    return "";
  }
  select(S);
  $| = 1;
  select(STDOUT);    # Eliminate STDIO buffering

  # The network connection is now open, lets fire up SSL
  $ctx = Net::SSLeay::CTX_new() or die_now("Failed to create SSL_CTX $!");
  Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL )
    and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
  $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
  Net::SSLeay::set_fd( $ssl, fileno(S) );    # Must use fileno
  $res = Net::SSLeay::connect($ssl) or &litleerror("$!");

  #$res = Net::SSLeay::connect($ssl) and Net::SSLeay::die_if_ssl_error("ssl connect");

  open( TMPFILE, ">>/home/p/pay1/logfiles/ciphers.txt" );
  print TMPFILE __FILE__ . ": " . Net::SSLeay::get_cipher($ssl) . "\n";
  close(TMPFILE);

  # Exchange data
  $res = Net::SSLeay::ssl_write_all( $ssl, $req );    # Perl knows how long $msg is
  Net::SSLeay::die_if_ssl_error("ssl write");

  #shutdown S, 1;  # Half close --> No more output, sends EOF to server

  my $response = "";

  #shutdown S, 1;  # Half close --> No more output, sends EOF to server
  my ( $rin, $rout, $temp );
  vec( $rin, $temp = fileno(S), 1 ) = 1;
  $count = 8;
  while ( $count && select( $rout = $rin, undef, undef, 80.0 ) ) {
    $got      = Net::SSLeay::read($ssl);              # Perl returns undef on failure
    $response = $response . $got;
    if ( length($got) < 1 ) {
      last;
    }
    Net::SSLeay::die_if_ssl_error("ssl read");
    $count--;
  }
  if ( $count == 1 ) {
    &errmssg("select timeout, please try again\n");
    return "";
  }

  Net::SSLeay::free($ssl);    # Tear down connection
  Net::SSLeay::CTX_free($ctx);
  close S;

  $mytime = gmtime( time() );
  my $chkmessage = $response;
  $chkmessage =~ s/\n/;;;;/g;
  $chkmessage =~ s/\>\</\>\n\</g;
  $chkmessage =~ s/;;;;/\n/g;
  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/litle/$fileyear/$username$time.txt" );
  print logfile "$username  $orderid\n";
  print logfile "$mytime recv: $chkmessage\n\n";

  #print "$mytime recv:\n$chkmessage\n\n";
  close(logfile);

  umask 0011;
  open( logfiletmp, ">>/home/p/pay1/batchfiles/$devprod/litle/serverlogmsg.txt" );
  print logfiletmp "$username  $orderid  $operation\n";
  print logfiletmp "$mytime recv: $chkmessage\n\n";
  close(logfiletmp);

  return $response;
}

sub errmssg {
  my ( $mssg, $level ) = @_;

  print "in errmssg\n";
  $result{'MStatus'}     = "problem";
  $result{'FinalStatus'} = "problem";
  $rmessage              = $mssg;

  if ( $level != 1 ) {
    Net::SSLeay::free($ssl);    # Tear down connection
    Net::SSLeay::CTX_free($ctx);
  }
  close S;
}

sub retry {
  print "in retry\n";
  socket( S, &AF_INET, &SOCK_STREAM, 0 ) or return ( &errmssg( "socket: $!", 1 ) );
  connect( S, $dest_serv_params ) or return ( &errmssg( "connect: $!", 1 ) );

  return "success";
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

