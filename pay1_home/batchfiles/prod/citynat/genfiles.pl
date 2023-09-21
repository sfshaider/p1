#!/usr/local/bin/perl

$| = 1;

use lib '/home/p/pay1/perl_lib';
use Net::FTP;
use miscutils;
use rsautils;
use Time::Local;
use smpsutils;

# city nat sweeps at 2pm EST

$devprod     = "prod";
$devprodlogs = "logs";

if ( ( -e "/home/p/pay1/batchfiles/$devprodlogs/stopgenfiles.txt" ) || ( -e "/home/p/pay1/batchfiles/$devprodlogs/citynat/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'citynat/genfiles.pl'`;
if ( $cnt > 1 ) {
  print "genfiles.pl already running, exiting...\n";
  exit;
}

$mytime  = time();
$machine = `uname -n`;
$pid     = $$;

chop $machine;
open( outfile, ">/home/p/pay1/batchfiles/$devprodlogs/citynat/pid.txt" );
$pidline = "$mytime $$ $machine";
print outfile "$pidline\n";
close(outfile);

&miscutils::mysleep(2.0);

open( infile, "/home/p/pay1/batchfiles/$devprodlogs/citynat/pid.txt" );
$chkline = <infile>;
chop $chkline;
close(infile);

if ( $pidline ne $chkline ) {
  print "genfiles.pl already running, pid alterred by another program, exiting...\n";
  print "$pidline\n";
  print "$chkline\n";

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: citynat - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

# xxxxaaaa
#$checkstring = " and username='windhaven'";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 * 6 ) );
$sixmonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 10 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$twomonthsagotime = $twomonthsago . "000000";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() + ( 3600 * 24 ) );
$tomorrow = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );

( $batchorderid, $today, $todaytime ) = &miscutils::genorderid();
$batchid  = $batchorderid;
$filename = $todaytime;

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyearonly");
  chmod( 0700, "/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyearonly" );
}
if ( !-e "/home/p/pay1/batchfiles/$devprodlogs/citynat/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/p/pay1/batchfiles/$devprodlogs/citynat/$filemonth");
  chmod( 0700, "/home/p/pay1/batchfiles/$devprodlogs/citynat/$filemonth" );
}
if ( !-e "/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear");
  chmod( 0700, "/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear" );
}
if ( !-e "/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: citynat - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory citynat/$fileyear.\n\n";
  close MAILERR;
  exit;
}

if ( ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/p/pay1/batchfiles/$devprodlogs/citynat/stopgenfiles.txt" ) ) {
  unlink "/home/p/pay1/batchfiles/$devprodlogs/citynat/batchfile.txt";
  exit;
}

$batch_flag   = 1;
$file_flag    = 1;
$errorflag    = 0;
$usersalesamt = 0;

$dbh  = &miscutils::dbhconnect("pnpmisc");
$dbh2 = &miscutils::dbhconnect("pnpdata");

local $sthpnp = $dbh->prepare(
  qq{
        select enccardnumber,length
        from citynat
        where username='pnpcitymstr'
        }
  )
  or die __LINE__ . __FILE__ . "Can't prepare: $DBI::errstr";
$sthpnp->execute or die __LINE__ . __FILE__ . "Can't execute: $DBI::errstr";
( $enccardnumber, $length ) = $sthpnp->fetchrow;
$sthpnp->finish;

$cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
( $pnproutenum, $pnpacctnum ) = split( / /, $cardnumber );

#$pnproutenum = "061211168";
#$pnpacctnum = "815700";

# new info 11/07/2003  also need to change pnpcitymstr
#$pnproutenum = "091408598";
#$pnpacctnum = "1701352547";

# xxxx
#and username='pnpcitymstr'

$sthtrans = $dbh2->prepare(
  qq{
        select t.username,count(t.username),min(o.trans_date)
        from operation_log o, trans_log t
        where t.trans_date>='$onemonthsago'
        and t.trans_date<='$today'
        and t.operation in ('postauth','return')
        $checkstring
        and t.finalstatus='pending'
        and t.accttype in ('checking','savings')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.processor='citynat'
        and o.lastoptime>='$onemonthsagotime'
        and o.lastopstatus='pending'
        group by t.username
  }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthtrans->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthtrans->bind_columns( undef, \( $user, $usercount, $usertdate ) );
while ( $sthtrans->fetch ) {
  my $sth2 = $dbh->prepare(
    qq{
        select status
        from citynat
        where username='$user'
        }
    )
    or die __LINE__ . __FILE__ . "Can't prepare: $DBI::errstr";
  $sth2->execute or die __LINE__ . __FILE__ . "Can't execute: $DBI::errstr";
  ($chkstatus) = $sth2->fetchrow;
  $sth2->finish;

  if ( $chkstatus eq "enabled" ) {
    print "b: $user\n";
    @userarray = ( @userarray, $user );
  }
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}
$sthtrans->finish;

#local $sth = $dbh2->prepare(qq{
#        select distinct username
#        from trans_log
#        where trans_date>='$twomonthsago'
#$checkstring
#        and accttype in ('checking','savings')
#        and finalstatus='pending'
#        and username<>'pnpdemo'
#	order by username
#        }) or die __LINE__ . __FILE__ . "Can't prepare: $DBI::errstr";
#$sth->execute or die __LINE__ . __FILE__ . "Can't execute: $DBI::errstr";
#$sth->bind_columns(undef,\($username));
#
#while ($sth->fetch) {
#  my $sth2 = $dbh->prepare(qq{
#        select status
#        from citynat
#        where username='$username'
#        }) or die __LINE__ . __FILE__ . "Can't prepare: $DBI::errstr";
#  $sth2->execute or die __LINE__ . __FILE__ . "Can't execute: $DBI::errstr";
#  ($chkstatus) = $sth2->fetchrow;
#  $sth2->finish;
#
#  if ($chkstatus eq "enabled") {
#    print "b: $username\n";
#    @userarray = (@userarray,$username);
#  }
#}
#$sth->finish;

@oparray = ( 'postauth', 'return' );

foreach $username (@userarray) {
  if ( ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/p/pay1/batchfiles/$devprodlogs/citynat/stopgenfiles.txt" ) ) {
    unlink "/home/p/pay1/batchfiles/$devprodlogs/citynat/batchfile.txt";
    last;
  }

  print "u: $username\n";

  umask 0033;
  open( checkin, ">/home/p/pay1/batchfiles/$devprodlogs/citynat/genfiles.txt" );
  print checkin "$username\n";
  close(checkin);

  umask 0033;
  open( batchfile, ">/home/p/pay1/batchfiles/$devprodlogs/citynat/batchfile.txt" );
  print batchfile "$username\n";
  close(batchfile);

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  %checkdup = ();

  local $sthcust = $dbh->prepare(
    qq{
        select merchant_id,pubsecret,proc_type,status,features
        from customers
        where username='$username'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthcust->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $merchant_id, $terminal_id, $proc_type, $chkstatus, $features ) = $sthcust->fetchrow;
  $sthcust->finish;

  # xxxxaaaa
  if ( ( $chkstatus ne "live" ) && ( $username ne "pnpcitymstr" ) ) {
    next;
  }

  local $sthcust = $dbh->prepare(
    qq{
        select enccardnumber,length,holdamount,holdrate,holdbalance,feerate,company,status,companyid,companyidccd,fileext
        from citynat
        where username='$username'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthcust->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $enccardnumber, $length, $holdamount, $holdrate, $holdbalance, $feerate, $company, $status, $companyidppd, $companyidccd, $fileext ) = $sthcust->fetchrow;
  $sthcust->finish;

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
      open( logfile, ">>/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear/$username$time$pid.txt" );
      print logfile "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      close(logfile);
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear/$username$time$pid.txt" );
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
  open( logfile, ">>/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear/$username$time$pid.txt" );
  print "$username\n";
  print logfile "$username  group: $batchgroup  sweeptime: $sweeptime  settletime: $settletime\n";
  print logfile "$features\n";
  close(logfile);

  $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
  ( $merchroutenum, $merchacctnum ) = split( / /, $cardnumber );

  $rlen = length($merchroutenum);
  $alen = length($merchacctnum);
  print "v: $rlen $alen\n";

  if ( ( $rlen != 9 ) || ( $alen < 2 ) ) {
    next;
  }
  print "v: $rlen $alen\n";

  print "twomonthsagotime: $twomonthsagotime\n";
  print "username: $username\n";
  print "starttransdate: $starttransdate\n";

  $sthtrans = $dbh2->prepare(
    qq{
          select orderid,lastop,auth_code
          from operation_log
          where trans_date>='$starttransdate'
          and username='$username'
          and lastoptime>='$twomonthsagotime'
          and lastop in ('postauth','return')
          and lastopstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and accttype in ('checking','savings')
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthtrans->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthtrans->bind_columns( undef, \( $orderid, $lastop, $auth_code ) );

  @orderidarray = ();
  while ( $sthtrans->fetch ) {
    $seccode = substr( $auth_code, 6, 3 );

    # temp
    if ( $seccode eq "WEB" ) {
      $seccode = "PPD";
    }
    $orderidarray{"$seccode $lastop $orderid"} = 1;
  }
  $sthtrans->finish;

  $mintrans_date = $today;

  foreach $key ( sort keys %orderidarray ) {
    ( $seccode, $operation, $orderid ) = split( / /, $key );

    $sthtrans2 = $dbh2->prepare(
      qq{
          select trans_date,trans_time,enccardnumber,length,amount,auth_code,avs,finalstatus,card_name,accttype
          from trans_log
          where orderid='$orderid'
          and username='$username'
          and trans_date>='$twomonthsago'
          and operation='$operation'
          and finalstatus='pending'
          and (duplicate is NULL or duplicate ='')
          and accttype in ('checking','savings')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthtrans2->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ( $trans_date, $trans_time, $enccardnumber, $length, $amount, $auth_code, $avs_code, $finalstatus, $card_name, $accttype ) = $sthtrans2->fetchrow;
    $sthtrans2->finish;

    if ( ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/p/pay1/batchfiles/$devprodlogs/citynat/stopgenfiles.txt" ) ) {
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
      $orderidold = $orderid;
      next;    # transaction is newer than sweeptime
    }

    print "bb $username $seccode $operation $orderid $fileext\n";

    if ( $checkdup{"$operation $orderid"} == 1 ) {
      next;
    }
    $checkdup{"$operation $orderid"} = 1;

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "citynat", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
    ( $routenum, $acctnum ) = split( / /, $cardnumber );

    $errflag = &errorchecking();
    if ( $errflag ne "0" ) {
      print "cardnumber failed error checking $errflag\n";
      next;
    }

    if ( ( $batch_flag == 0 ) && ( $seccodeold ne "" ) && ( $seccode ne $seccodeold ) ) {
      &batchtrailer();

      #&batchheader($company,$companyid,"$seccodeold");
      #&merchantdeposits();
      #&batchtrailer();
      $usersalesamt = 0;
      $batch_flag   = 1;
      &filetrailer();
      $file_flag = 1;
    }

    if ( $file_flag == 1 ) {
      &pidcheck();
      if ( $seccode eq "PPD" ) {
        $companyid = $companyidppd;
      } else {
        $companyid = $companyidccd;
      }
      &fileheader();

      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear/t$filename.txt" );
      print logfile "\n$username\n";
      close(logfile);
    }

    if ( ( $operationold ne "" ) && ( $operation ne $operationold ) ) {
      if ( $batch_flag == 0 ) {
        &batchtrailer();
      }
      $batch_flag = 1;
    }

    if ( $batch_flag == 1 ) {

      #if ($operation eq "return") {
      &batchheader( $company, $companyid, "$seccode" );

      #}
      #else {
      #  &batchheader($company,$companyid,"WEB");
      #}
      $batch_flag     = 0;
      $batchdetreccnt = 0;
      $batchfees      = 0;
      $usersalescnt   = 0;
      $userretamt     = 0;
      $userretcnt     = 0;
    }

    umask 0077;
    my $crdname = $card_name;
    $crdname =~ s/^ +//g;
    $crdname =~ s/[^0-9a-zA-Z ]//g;
    $crdname =~ tr/a-z/A-Z/;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear/t$filename.txt" );
    print logfile "$orderid $operation $crdname\n";
    close(logfile);

    $transamt = substr( $amount, 4 );
    $transamt = sprintf( "%.2f", $transamt + .0001 );
    print "transamt: $transamt\n";

    if ( $operation =~ /postauth|return/ ) {
      local $sthinfo = $dbh2->prepare(
        qq{
          update trans_log set finalstatus='locked',result=?
	  where orderid='$orderid'
	  and username='$username'
	  and trans_date>='$twomonthsago'
	  and finalstatus='pending'
	  and accttype in ('checking','savings')
          }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthinfo->execute("$batchid") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthinfo->finish;

      $operationstatus = $operation . "status";
      $operationtime   = $operation . "time";

      local $sthinfo = $dbh2->prepare(
        qq{
          update operation_log set lastopstatus='locked',$operationstatus='locked',batchfile=?
	  where orderid='$orderid'
	  and username='$username'
	  and trans_date>='$sixmonthsago'
	  and lastopstatus='pending'
	  and accttype in ('checking','savings')
          }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthinfo->execute("$batchid") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthinfo->finish;

      if ( $operation eq "postauth" ) {
        $usersalesamt = $usersalesamt + $transamt;
      } else {
        $usersalesamt = $usersalesamt - $transamt;
      }
      $usersalescnt = $usersalescnt + 1;

      if ( ( $operation eq "postauth" ) && ( $accttype eq "checking" ) ) {
        $tcode = "27";
      } elsif ( ( $operation eq "postauth" ) && ( $accttype eq "savings" ) ) {
        $tcode = "37";
      } elsif ( ( $operation eq "return" ) && ( $accttype eq "checking" ) ) {
        $tcode = "22";
      } elsif ( ( $operation eq "return" ) && ( $accttype eq "savings" ) ) {
        $tcode = "32";
      }

      &batchdetail( $routenum, $acctnum, $orderid, $card_name, $transamt, $tcode );
    } elsif ( (0) && ( $operation eq "return" ) ) {
      $amt                          = $transamt + $feerate;
      $userretamt                   = $userretamt + $transamt;
      $userretcnt                   = $userretcnt + 1;
      $retamt                       = $retamt + $amt;
      $batchorderid                 = &miscutils::incorderid($batchorderid);
      $merchroute{$batchorderid}    = $merchroutenum;
      $merchorderid{$batchorderid}  = $orderid;
      $merchacct{$batchorderid}     = $merchacctnum;
      $merchcompany{$batchorderid}  = $company;
      $merchdeposit{$batchorderid}  = $amt;
      $merchtcode{$batchorderid}    = $tcode;
      $merchusername{$batchorderid} = $username;
      $merchfeerate{$batchorderid}  = $feerate;
      $merchfilename{$batchorderid} = $filename;
      $merchtransamt{$batchorderid} = $transamt;
    }

    $temp = substr( $recseqnum, 3, 4 );
    if ( $temp >= 9998 ) {
      &batchtrailer();

      #&batchheader($company,$companyid,"$seccode");
      #&merchantdeposits();
      #&batchtrailer();
      $usersalesamt = 0;
      $batch_flag   = 1;
      &filetrailer();
      $file_flag = 1;
    }

    $usernameold  = $username;
    $operationold = $operation;
    $seccodeold   = $seccode;
  }

  print "bbbb $batch_flag\n";
  if ( $batch_flag == 0 ) {
    &batchtrailer();

    #&batchheader($company,$companyid,"$seccode");
    #&merchantdeposits();
    #&batchtrailer();
    $usersalesamt = 0;
    $batch_flag   = 1;
    &filetrailer();
    $file_flag = 1;
  }
}

$a = keys(%merchroute);
print "a: $a\n";
if ( keys(%merchroute) > 0 ) {
  &batchheader("Plug & Pay Technologies, Inc.");
}

if ( $file_flag == 0 ) {
  foreach $key ( sort keys %merchroute ) {
    local $sthinfo = $dbh2->prepare(
      qq{
          update trans_log set finalstatus='locked',result=?
	  where orderid='$merchorderid{$key}'
	  and trans_date>='$twomonthsago'
	  and username='$merchusername{$key}'
	  and finalstatus='pending'
	  and accttype in ('checking','savings')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthinfo->execute("$batchid") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthinfo->finish;

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";

    local $sthinfo = $dbh2->prepare(
      qq{
          update operation_log set lastopstatus='locked',$operationstatus='locked',batchfile=?
	  where orderid='$merchorderid{$key}'
	  and trans_date>='$sixmonthsago'
	  and username='$merchusername{$key}'
	  and finalstatus='pending'
	  and accttype in ('checking','savings')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthinfo->execute("$batchid") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthinfo->finish;

    if ( $merchtransamt{$key} > 0 ) {
      $amt = sprintf( "%.2f", ( 0 - $merchtransamt{$key} ) - .0001 );

      # xxxxaaaa
      if (1) {
        local $sthach = $dbh->prepare(
          qq{
            insert into citydetails
	    (username,filename,batchid,orderid,fileid,batchnum,detailnum,operation,amount,descr,trans_date,status,transfee,step,trans_time)
            values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sthach->execute( "$merchusername{$key}", "$merchfilename{$key}", "$batchid", "$merchorderid{$key}", "$fileid", "$batchnum", "$recseqnum", "return",
          "$amt", "return", "$today", "pending", "$merchfeerate{$key}", "one", "$todaytime" )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sthach->finish;
      }
    }

    $user              = $merchusername{$key};
    $sumdeposit{$user} = $sumdeposit{$user} + $merchdeposit{$key};
    $sumroute{$user}   = $merchroute{$key};
    $sumacct{$user}    = $merchacct{$key};
    $sumcompany{$user} = $merchcompany{$key};

    #&detail($merchroute{$key},$merchacct{$key},$merchorderid{$key},$merchcompany{$key},${merchdeposit$key},$merchtcode{$key});
  }

  foreach $key ( sort keys %sumdeposit ) {
    $batchorderid = &miscutils::incorderid($batchorderid);
    $amt = sprintf( "%.2f", $sumdeposit{$key} + .0001 );
    &detail( $sumroute{$key}, $sumacct{$key}, $batchorderid, $sumcompany{$key}, $amt, "27" );

    # xxxxaaaa
    if (1) {
      local $sthinfo = $dbh->prepare(
        qq{
          update citydetails set detailnum=?
          where trans_date='$today'
          and batchid='$batchid'
          and username='$key'
          }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthinfo->execute("$recseqnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthinfo->finish;
    }
  }

  %sumdeposit    = ();
  %sumroute      = ();
  %sumacct       = ();
  %sumcompany    = ();
  %merchroute    = ();
  %merchacct     = ();
  %merchcompany  = ();
  %merchdeposit  = ();
  %merchtcode    = ();
  %merchusername = ();
  %merchfeerate  = ();
  %merchfilename = ();
  %merchorderid  = ();
  %merchtransamt = ();

  &filetrailer();
  $file_flag = 1;
}

$dbh->disconnect;
$dbh2->disconnect;

unlink "/home/p/pay1/batchfiles/$devprodlogs/citynat/batchfile.txt";

umask 0033;
open( checkin, ">/home/p/pay1/batchfiles/$devprodlogs/citynat/genfiles.txt" );
close(checkin);

# xxxxaaaa
system("/home/p/pay1/batchfiles/$devprod/citynat/putfiles.pl >> /home/p/pay1/batchfiles/$devprodlogs/citynat/ftplog.txt 2>\&1");

exit;

sub batchheader {
  my ( $companyinfo, $companyid, $seccode ) = @_;

  $recseqnum++;
  $batchsalescnt  = 0;
  $batchsalesamt  = 0;
  $batchretcnt    = 0;
  $batchretamt    = 0;
  $batchtotamt    = 0;
  $batchtotcnt    = 0;
  $batchreccnt    = 1;
  $batchdetreccnt = 0;
  $batch_flag     = 0;
  $transseqnum    = 0;
  $routenumhash   = 0;
  $usersalescnt   = 0;
  $userretamt     = 0;
  $userretcnt     = 0;

  $batchcount++;
  $batchnum++;

  $batchid = &miscutils::incorderid($batchid);

  $batchreccnt = 1;
  $filereccnt++;

  @bh           = ();
  $bh[0]        = '5';                                        # record type code (1n)
  $bh[1]        = '200';                                      # service class code (3n)
  $companyname  = substr( $companyinfo . " " x 16, 0, 16 );
  $companydescr = substr( $companyinfo, 16, 10 );
  if ( $companydescr eq "" ) {
    $companydescr = "PAYMT     ";
  } else {
    $companydescr = substr( $companydescr . " PAYMT    ", 0, 10 );
  }
  $bh[2] = "$companyname";                                    # company name (16a)

  # xxxx
  $bh[3] = 'WAA009' . " " x 14;                               # company discretionary data (20a)
                                                              #$bh[4] = '1351000295';        # company identification (10a)

  $companyid = substr( $companyid . " " x 10, 0, 10 );
  $bh[4] = $companyid;                                        # company identification (10a)
                                                              #$bh[4] = '8004619800';        # company identification (10a)

  #$seccode = substr($auth_code,6,3);
  #if ($seccode !~ /[A-Z]{3}/) {
  #$seccode = "WEB";
  #}
  $bh[5] = $seccode;         # standard entry class code (3a)
  $bh[6] = $companydescr;    # company entry description (10a)
  $tdate = substr( $tomorrow, 2, 6 );
  $bh[7] = $tdate;           # company descriptive date (6a)

  # xxxx two days later than actual date
  $bh[8]  = $tdate;          # effective entry date (6n)
  $bh[9]  = "   ";           # settlement date (julian) - leave blank (3n)
  $bh[10] = '1';             # originator status code (1a)
                             #$bh[11] = '11190324';         # originating dfi identification (8a)
  $bh[11] = '06600436';      # originating dfi identification (8a)
  $batchnum = substr( "0" x 7 . $batchnum, -7.7 );

  # xxxx sames as  8 record, field 11
  $bh[12] = $batchnum;       # batch number (7n)

  foreach $var (@bh) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "\n";
  print outfile2 "\n";

}

sub detail {
  my ( $routenum, $acctnum, $orderid, $card_name, $transamt, $tcode ) = @_;

  $batchdetreccnt++;
  $filedetreccnt++;
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;

  $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );

  if ( $tcode =~ /^(27|37)$/ ) {
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
  $batchtotamt = $batchtotamt + $transamt;
  $batchtotcnt = $batchtotcnt + 1;
  $filetotamt  = $filetotamt + $transamt;

  local $sthinfo = $dbh->prepare(
    qq{
          select refnumber
          from citynat
          where username='pnpcitymstr'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ($refnumber) = $sthinfo->fetchrow;
  $sthinfo->finish;

  $refnumber = $refnumber + 1;
  if ( $refnumber >= 9999998 ) {
    $refnumber = 1;
  }

  $refnumber = substr( "0" x 15 . $refnumber, -15, 15 );

  local $sthinfo = $dbh->prepare(
    qq{
          update citynat set refnumber=?
          where username='pnpcitymstr'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute("$refnumber") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthinfo->finish;

  @bd              = ();
  $bd[0]           = '6';                                            # record type code (1n)
  $tcode           = substr( $tcode . "  ", 0, 2 );
  $bd[1]           = $tcode;                                         # transaction code (2n)
  $routenum        = substr( "0" x 9 . $routenum, -9, 9 );
  $routenumhash    = $routenumhash + substr( $routenum, 0, 8 );
  $totroutenumhash = $totroutenumhash + substr( $routenum, 0, 8 );
  $bd[2]           = $routenum;                                      # receiving dfi identification (8n) (9n) includes check digit
  $acctnum         = substr( $acctnum . " " x 17, 0, 17 );
  $bd[3]           = $acctnum;                                       # dfi account number (17a)
  $transamt        = substr( "0" x 10 . $transamt, -10, 10 );
  $bd[4]           = $transamt;                                      # amount (10n)
                                                                     #$oid = substr($orderid,-15,15);
                                                                     #$refnumber = substr($refnumber . " " x 15,0,15);
  $refnumber       = substr( "0" x 15 . $refnumber, -15, 15 );
  $bd[5]           = $refnumber;                                     # individual identification number (15a)
  $card_name =~ s/^ +//g;
  $card_name =~ s/[^0-9a-zA-Z ]//g;
  $card_name =~ tr/a-z/A-Z/;
  $card_name = substr( $card_name . " " x 22, 0, 22 );
  $bd[6] = $card_name;                                               # individual name (22a)
  $bd[7] = "  ";                                                     # discretionary data (2a)
  $bd[8] = "0";                                                      # addenda record indicator (1n)
  $recseqnum = substr( "0" x 7 . $recseqnum, -7, 7 );

  #$bd[9] = '11190324' . $recseqnum;   # trace number (15n)
  $bd[9] = '06600436' . $recseqnum;                                  # trace number (15n)

  foreach $var (@bd) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "\n";
  print outfile2 "\n";

}

sub batchtrailer {
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;

  $batchsalescnt  = substr( "0000000" . $batchsalescnt, -6,  6 );
  $batchretcnt    = substr( "0000000" . $batchretcnt,   -6,  6 );
  $batchtotamt    = substr( "0" x 12 . $batchtotamt,    -12, 12 );
  $batchtotcnt    = substr( "0" x 6 . $batchtotcnt,     -6,  6 );
  $batchdetreccnt = substr( "0" x 9 . $batchdetreccnt,  -9,  9 );
  $routenumhash   = substr( "0" x 10 . $routenumhash,   -10, 10 );

  $batchsalesamt = sprintf( "%d", $batchsalesamt + .0001 );
  $batchsalesamt = substr( "0" x 12 . $batchsalesamt, -12, 12 );

  $batchretamt = sprintf( "%d", $batchretamt + .0001 );
  $batchretamt = substr( "0" x 12 . $batchretamt, -12, 12 );

  @bt       = ();
  $bt[0]    = '8';                                   # record type code (1n)
  $bt[1]    = '200';                                 # service class code (3n)
  $bt[2]    = $batchtotcnt;                          # entry/addenda count (6n)
  $bt[3]    = $routenumhash;                         # entry hash (10n)
  $bt[4]    = $batchsalesamt;                        # total debit entry dollar amt (12n)
  $bt[5]    = $batchretamt;                          # total credit entry dollar amt (12n)
                                                     #$bt[6] = '1351000295';        # company identification (10a)
  $bt[6]    = '1113392673';                          # company identification (10a)
  $bt[7]    = ' ' x 19;                              # message authentication code (19a)
  $bt[8]    = '      ';                              # reserved (6a)
                                                     #$bt[9] = '11190324';          # originating dfi identification (8a)
  $bt[9]    = '06600436';                            # originating dfi identification (8a)
  $batchnum = substr( "0" x 7 . $batchnum, -7.7 );
  $bt[10]   = $batchnum;                             # batch number (7n)

  foreach $var (@bt) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "\n";
  print outfile2 "\n";

}

sub merchantdeposits {
  print "usersalesamt: $usersalesamt\n";
  if ( $usersalesamt != 0 ) {

    # money transfers from customer to Plug & Pay
    $amt = $usersalesamt;
    if ( $amt > 0 ) {
      $tcode = "22";
    } else {
      $amt   = 0 - $amt;
      $tcode = "27";
    }
    $batchorderid = &miscutils::incorderid($batchorderid);
    &detail( $merchroutenum, $merchacctnum, $batchorderid, $company, $amt, $tcode );
  }
}

sub fileheader {

  $recseqnum       = $julian . "0000";
  $filesalescnt    = 0;
  $filesalesamt    = 0;
  $fileretcnt      = 0;
  $fileretamt      = 0;
  $filetotamt      = 0;
  $filereccnt      = 1;
  $filedetreccnt   = 0;
  $batchcount      = 0;
  $batchnum        = 0;
  $totroutenumhash = 0;
  $retamt          = 0;

  $filecnt = 0;

  $file_flag = 0;

  $filename = &miscutils::incorderid($filename);

  local $sthfile = $dbh->prepare(
    qq{
        select fileid
        from citynat
        where username='pnpcitymstr'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthfile->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ($fileid) = $sthfile->fetchrow;
  $sthfile->finish;

  $fileid =~ tr/A-Z0-9/B-Z0-9A/;
  if ( $fileid eq "" ) {
    $fileid = "A";
  }

  local $sthinfo = $dbh->prepare(
    qq{
        update citynat set fileid=?
        where username='pnpcitymstr'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute("$fileid") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthinfo->finish;

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear/t$filename.txt" );
  print logfile "fileid: $fileid\n";
  close(logfile);

  umask 0077;
  open( outfile,  ">/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear/$filename.txt" );
  open( outfile2, ">/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear/$filename.done" );

  @fh         = ();
  $fh[0]      = '1';                                    # record type code (1n)
  $fh[1]      = '01';                                   # priority code (2n)
  $fh[2]      = ' 066004367';                           # immediate destination (10a)
  $fh[3]      = $companyid;                             # immediate origin (10a)
  $cdate      = substr( $todaytime, 2, 6 );
  $ctime      = substr( $todaytime, 8, 4 );
  $fh[4]      = $cdate;                                 # file creation date (6n)
  $fh[5]      = $ctime;                                 # file creation time (4n)
  $fileid     = substr( $fileid, 0, 1 );
  $fh[6]      = $fileid;                                # file id modifier - like a seq num, A-Z, 1-9 (1a)
  $fh[7]      = '094';                                  # record size (3n)
  $fh[8]      = '10';                                   # blocking factor (2n)
  $fh[9]      = '1';                                    # format code (1n)
  $fh[10]     = 'City National Bank     ';              # immediate destination name (23a)
  $companystr = substr( $company . " " x 23, 0, 23 );
  $fh[11]     = $companystr;                            # immediate origin name (23a)

  # xxxx
  $refcode = substr( $filename, 2, 8 );
  $fh[12] = $refcode;                                   # reference code (8a)

  foreach $var (@fh) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "\n";
  print outfile2 "\n";
}

sub filetrailer {
  print "in filetrailer\n";

  #if ($retamt > 0) {
  #  $tcode = "22";			# deposit into master account
  #  $batchorderid = &miscutils::incorderid($batchorderid);
  #  &detail($pnproutenum,$pnpacctnum,$batchorderid,"Plug & Pay Technologies, Inc.",$retamt,$tcode);
  #}

  if ( $batch_flag == 0 ) {
    &batchtrailer();
    $batch_flag = 1;
  }

  $filereccnt++;
  $recseqnum++;

  $filesalescnt    = substr( "0000000" . $filesalescnt,   -7,  7 );
  $filesalesamt    = substr( "0" x 12 . $filesalesamt,    -12, 12 );
  $fileretamt      = substr( "0" x 12 . $fileretamt,      -12, 12 );
  $fileretcnt      = substr( "0000000" . $fileretcnt,     -7,  7 );
  $filetotamt      = substr( "0" x 12 . $filetotamt,      -12, 12 );
  $filedetreccnt   = substr( "0" x 8 . $filedetreccnt,    -8,  8 );
  $filereccnt      = substr( "0" x 9 . $filereccnt,       -9,  9 );
  $totroutenumhash = substr( "0" x 10 . $totroutenumhash, -10, 10 );

  @ft = ();
  $ft[0] = '9';    # record type code (1n)

  # xxxx
  $batchnum = substr( "0" x 6 . $batchnum, -6.6 );
  $ft[1] = $batchnum;                     # batch count (6n)
  $blockcnt = ( $filereccnt - 1 ) / 10;
  $blockcnt = sprintf( "%06d", $blockcnt + 1 );
  $ft[2] = $blockcnt;                     # block count (6n)
  $ft[3] = $filedetreccnt;                # entry/addenda count (8n)
  $ft[4] = $totroutenumhash;              # entry hash (10n)
  $ft[5] = $filesalesamt;                 # total debit entry dollar amt in file (12n)
  $ft[6] = $fileretamt;                   # total credit entry dollar amt in file (12n)
  $ft[7] = ' ' x 39;                      # reserved (39a)

  foreach $var (@ft) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "\n";
  print outfile2 "\n";

  # filler to make sure there are groups of 10 lines
  if ( $filereccnt % 10 != 0 ) {
    for ( $i = $filereccnt % 10 ; $i <= 9 ; $i++ ) {
      print outfile '9' x 94 . "\n";      # filler (1n)
      print outfile2 '9' x 94 . "\n";     # filler (1n)
    }
  }

  close(outfile);
  close(outfile2);
}

sub errorchecking {
  my $errmsg = "";

  if ( ( $refnumber eq "" ) && ( ( $operation eq "auth" ) || ( ( $operation eq "return" ) && ( $finalstatus eq "locked" ) && ( $chkproc_type ne "authonly" ) ) ) ) {
    $errmsg = "Missing transid";
  }

  if ( $acctnum =~ /[^0-9]/ ) {
    $errmsg = "Account number can only contain numbers";
  }

  if ( $routenum =~ /[^0-9]/ ) {
    $errmsg = "Route number can only contain numbers";
  }

  $mod10 = &miscutils::mod10($cardnumber);
  if ( $mod10 ne "success" ) {
    $errmsg = "route number failed mod10 check";
  }

  # check for bad card numbers
  if ( ( length($enccardnumber) > 1024 ) || ( length($enccardnumber) < 30 ) ) {
    $errmsg = "could not decrypt $enclength";
  }

  $mylen = length($cardnumber);

  # 11
  if ( ( $mylen < 6 ) || ( $mylen > 32 ) ) {
    $errmsg = "bad account length";
  }

  # check for 0 amount
  if ( $amount eq "usd 0.00" ) {
    $errmsg = "amount = 0.00";
  }

  if ( $errmsg ne "" ) {
    my $sthlock = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='problem',descr=?
            where orderid='$orderid'
            and username='$username'
            and trans_date>='$twomonthsago'
            and finalstatus in ('locked','pending')
            and accttype in ('checking','savings')
            }
      )
      or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthlock->execute("$errmsg") or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthlock->finish;

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid='$orderid'
            and username='$username'
            and $operationstatus in ('locked','pending')
            and (voidstatus is NULL  or voidstatus ='')
            and accttype in ('checking','savings')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute("$errmsg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;

    return $errmsg;
  }

  return "0";
}

sub batchdetail {
  my ( $routenum, $acctnum, $orderid, $card_name, $transamt, $tcode ) = @_;

  $batchdetreccnt++;
  $filedetreccnt++;
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;

  $recseqnum = substr( "0" x 7 . $recseqnum, -7, 7 );
  $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );

  if ( $tcode =~ /^(27|37)$/ ) {
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
  $batchtotamt = $batchtotamt + $transamt;
  $batchtotcnt = $batchtotcnt + 1;
  $filetotamt  = $filetotamt + $transamt;

  $morderid = substr( $orderid, -16, 16 );

  local $sthinfo = $dbh->prepare(
    qq{
          select refnumber
          from citynat
          where username='pnpcitymstr'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ($refnumber) = $sthinfo->fetchrow;
  $sthinfo->finish;

  $refnumber = $refnumber + 1;
  if ( $refnumber >= 999998 ) {
    $refnumber = 1;
  }

  $refnumber = substr( "0" x 15 . $refnumber, -15, 15 );

  local $sthinfo = $dbh->prepare(
    qq{
          update citynat set refnumber=?
          where username='pnpcitymstr'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute("$refnumber") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthinfo->finish;

  # xxxxaaaa
  if (1) {
    local $sthinfo = $dbh->prepare(
      qq{
        insert into batchfilescity
	(username,filename,trans_date,orderid,status,detailnum,refnumber,operation,fileext)
        values (?,?,?,?,?,?,?,?,?)
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthinfo->execute( "$username", "$filename", "$today", "$orderid", "pending", "$recseqnum", "$refnumber", "$operation", "$fileext" )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthinfo->finish;

    $amt = sprintf( "%.2f", ( $transamt / 100 ) + .0001 );

    local $sthach = $dbh->prepare(
      qq{
        insert into citydetails
	(username,filename,batchid,orderid,fileid,batchnum,detailnum,operation,amount,descr,trans_date,status,transfee,step,trans_time)
        values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthach->execute( "$username", "$filename", "$batchid", "$orderid", "$fileid", "$batchnum", "$recseqnum", "$operation", "$amt", "$operation", "$today", "pending", "$feerate", "one", "$todaytime" )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthach->finish;
  }

  @bd              = ();
  $bd[0]           = '6';                                            # record type code (1n)
  $bd[1]           = $tcode;                                         # transaction code (2n)
  $routenum        = substr( "0" x 9 . $routenum, -9, 9 );
  $routenumhash    = $routenumhash + substr( $routenum, 0, 8 );
  $totroutenumhash = $totroutenumhash + substr( $routenum, 0, 8 );
  $bd[2]           = $routenum;                                      # receiving dfi identification (8n) (9n) includes check digit
  $acctnum         = substr( $acctnum . " " x 17, 0, 17 );
  $bd[3]           = $acctnum;                                       # dfi account number (17a)
  $transamt        = substr( "0" x 10 . $transamt, -10, 10 );
  $bd[4]           = $transamt;                                      # amount (10n)
                                                                     #$oid = substr($orderid,-15,15);
                                                                     #$oid = substr($oid . " " x 15,0,15);
  $oid             = substr( "0" x 15 . $refnumber, -15, 15 );
  $bd[5]           = $oid;                                           # individual identification number (15a)
  $card_name =~ s/^ +//g;
  $card_name =~ s/[^0-9a-zA-Z ]//g;
  $card_name =~ tr/a-z/A-Z/;
  $card_name = substr( $card_name . " " x 22, 0, 22 );
  $bd[6] = $card_name;                                               # individual name (22a)
  $bd[7] = "  ";                                                     # discretionary data (2a)
  $bd[8] = "0";                                                      # addenda record indicator (1n)
                                                                     #$bd[9] = '11190324' . $recseqnum;   # trace number (15n)
  $bd[9] = '06600436' . $recseqnum;                                  # trace number (15n)

  my $myi = 0;
  foreach $var (@bd) {
    print outfile "$var";

    if ( ( $myi == 2 ) || ( $myi == 3 ) ) {
      $var =~ s/./x/g;
      print outfile2 "$var";
    } else {
      print outfile2 "$var";
    }
    $myi++;
  }
  print outfile "\n";
  print outfile2 "\n";

  print "$checknum $seccode\n";

  $checknum = substr( $auth_code, 9, 8 );

  #$checknum = "1111";
  $checknum =~ s/ //g;

  if ( (0) && ( $seccode =~ /^(PPD|CCD|WEB)$/ ) && ( $checknum ne "" ) ) {

    #$recseqnum++;
    $batchtotcnt = $batchtotcnt + 1;
    $filedetreccnt++;
    $filereccnt++;

    @bd    = ();
    $bd[0] = '7';     # record type code (1n)
                      #$tcode = substr($tcode . "  ",0,2);
    $bd[1] = "05";    # transaction code (2n)

    $checknum = substr( $checknum . " " x 80, 0, 80 );
    $bd[2] = $checknum;    # discretionary data (80a)
    $bd[3] = "0001";       # addenda sequence number (4n)
    $recseqnum = substr( "0" x 7 . $recseqnum, -7, 7 );
    $bd[4] = $recseqnum;    # trace number (7n)

    foreach $var (@bd) {
      print outfile "$var";
      print outfile2 "$var";
    }
    print outfile "\n";
    print outfile2 "\n";
  }

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

sub pidcheck {
  open( infile, "/home/p/pay1/batchfiles/$devprodlogs/citynat/pid.txt" );
  $chkline = <infile>;
  chop $chkline;
  close(infile);

  if ( $pidline ne $chkline ) {
    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprodlogs/citynat/$fileyear/$username$time$pid.txt" );
    print logfile "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print logfile "$pidline\n";
    print logfile "$chkline\n";
    close(logfile);

    print "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print "$pidline\n";
    print "$chkline\n";

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: citynat - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

