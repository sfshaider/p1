#!/usr/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SSLeay qw(get_https post_https sslcat make_headers make_form);
use Net::FTP;
use miscutils;
use IO::Socket;
use Socket;
use rsautils;
use smpsutils;
use Time::Local;
use PlugNPay::CreditCard;

$devprod = "logs";

my $group = $ARGV[0];
if ( $group eq "" ) {
  $group = "0";
}
print "group: $group\n";

$host = "209.51.176.199";

if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/nova/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'nova/genfiles.pl $group'`;
if ( $cnt > 1 ) {
  print "genfiles.pl $group already running, exiting...\n";

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dprice\@plugnpay.com\n";
  print MAILERR "Subject: nova - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl $group because it's already running.\n\n";
  close MAILERR;

  exit;
}

$mytime  = time();
$machine = `uname -n`;
$pid     = $$;

chop $machine;
open( outfile, ">/home/pay1/batchfiles/$devprod/nova/pid$group.txt" );
$pidline = "$mytime $$ $machine";
print outfile "$pidline\n";
close(outfile);

&miscutils::mysleep(2.0);

open( infile, "/home/pay1/batchfiles/$devprod/nova/pid$group.txt" );
$chkline = <infile>;
chop $chkline;
close(infile);

if ( $pidline ne $chkline ) {
  print "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  print "$pidline\n";
  print "$chkline\n";

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dprice\@plugnpay.com\n";
  print MAILERR "Subject: nova - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

open( checkin, "/home/pay1/batchfiles/$devprod/nova/genfiles$group.txt" );
$checkuser = <checkin>;
chop $checkuser;
close(checkin);

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>='$checkuser'";
}

#$checkstring = "and t.username='aaaa'";
#$checkstring = "and t.username in ('aaaa','aaaa')";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $dummy, $today, $time ) = &miscutils::genorderid();
$todaytime = $time;

$starttransdate = $today - 10000;

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/nova/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/pay1/batchfiles/$devprod/nova/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/nova/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/nova/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/pay1/batchfiles/$devprod/nova/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/nova/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/nova/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/pay1/batchfiles/$devprod/nova/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/nova/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/nova/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dprice\@plugnpay.com\n";
  print MAILERR "Subject: nova - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory /home/pay1/batchfiles/$devprod/nova/$fileyear.\n\n";
  close MAILERR;
  exit;
}

#$secondaryflag = 0;
#if (-e "/home/pay1/batchfiles/$devprod/nova/secondary.txt") {
#  $secondaryflag = 1;
#}

$batch_flag = 1;
$file_flag  = 1;

$dbh2 = &miscutils::dbhconnect("pnpdata");

# xxxx
#and t.username='emarinei'

$sthtrans = $dbh2->prepare(
  qq{
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>='$onemonthsago'
        and t.trans_date<='$today'
        $checkstring
        and t.finalstatus = 'pending'
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.processor='nova'
        and o.lastopstatus='pending'
        group by t.username
  }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthtrans->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthtrans->bind_columns( undef, \( $user, $usercount, $usertdate ) );
while ( $sthtrans->fetch ) {
  print "$user $usertdate\n";
  push( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}
$sthtrans->finish;

foreach $username ( sort @userarray ) {
  &dosettle();
}

foreach $username ( sort @erruserarray ) {
  &dosettle();
}

$dbh2->disconnect;

unlink "/home/pay1/batchfiles/$devprod/nova/batchfile.txt";

if ( ( !-e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) && ( !-e "/home/pay1/batchfiles/$devprod/nova/stopgenfiles.txt" ) ) {
  umask 0033;
  open( checkin, ">/home/pay1/batchfiles/$devprod/nova/genfiles$group.txt" );
  close(checkin);
}

exit;

sub dosettle {
  if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/nova/stopgenfiles.txt" ) ) {
    unlink "/home/pay1/batchfiles/$devprod/nova/batchfile.txt";
    last;
  }

  umask 0033;
  open( batchfile, ">/home/pay1/batchfiles/$devprod/nova/batchfile.txt" );
  print batchfile "$username\n";
  close(batchfile);

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  if ( $usercountarray{$username} > 3000 ) {
    $batchcntuser = 2000;
  } elsif ( $usercountarray{$username} > 2000 ) {
    $batchcntuser = 1500;
  } else {
    $batchcntuser = 1000;
  }

  # xxxx
  #and username='royaltyp'

  $dbh = &miscutils::dbhconnect("pnpmisc");

  local $sthcust = $dbh->prepare(
    qq{
        select processor,merchant_id,pubsecret,proc_type,status,features
        from customers
        where username='$username'
        }
    )
    or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthcust->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $processor, $merchant_id, $terminal_id, $proc_type, $status, $features ) = $sthcust->fetchrow;
  $sthcust->finish;

  local $sthcust = $dbh->prepare(
    qq{
        select industrycode,batchgroup
        from nova
        where username='$username'
        }
    )
    or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthcust->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $industrycode, $batchgroup ) = $sthcust->fetchrow;
  $sthcust->finish;

  $dbh->disconnect;

  if ( $status ne "live" ) {
    next;
  }

  if ( $processor ne "nova" ) {
    next;
  }

  if ( ( $group eq "4" ) && ( $batchgroup ne "4" ) ) {
    next;
  } elsif ( ( $group eq "3" ) && ( $batchgroup ne "3" ) ) {
    next;
  } elsif ( ( $group eq "2" ) && ( $batchgroup ne "2" ) ) {
    next;
  } elsif ( ( $group eq "1" ) && ( $batchgroup ne "1" ) ) {
    next;
  } elsif ( ( $group eq "0" ) && ( $batchgroup ne "" ) ) {
    next;
  } elsif ( $group !~ /^(0|1|2|3|4)$/ ) {
    next;
  }

  open( checkin, ">/home/pay1/batchfiles/$devprod/nova/genfiles$group.txt" );
  print checkin "$username\n";
  close(checkin);

  umask 0077;
  open( logfile, ">/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
  print logfile "$username $usercountarray{$username} $starttransdate\n";
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
    print "todaytime: $todaytime\n";
    print "timezone: $timezone\n";
    print "dstflag: $dstflag\n";
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
      print logfile "aaaa  sweephour: $newhour  settlehour: $settlehour\n";
      close(logfile);
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
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
  open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
  print "$username\n";
  print logfile "$username  sweeptime: $sweeptime  settletime: $settletime\n";
  print logfile "$features\n";
  close(logfile);

  $batchnum = 0;

  $batch_flag   = 1;
  $batchmessage = "";
  @batchdata    = ();
  $netamount    = 0;
  $hashtotal    = 0;
  $batchcnt     = 1;
  $recseqnum    = 0;
  %errorderid   = ();

  my ( $qmarks, $dateArrayRef ) = &miscutils::dateIn( $starttransdate, $today, '1' );

  $sthtrans = $dbh2->prepare(
    qq{
        select orderid,trans_date
        from operation_log force index(oplog_tdateloptimeuname_idx)
        where trans_date IN ($qmarks)
        and lastoptime>='$onemonthsagotime'
        and username='$username'
        and lastop in ('postauth','return')
        and lastopstatus='pending'
        and processor='nova'
        and (voidstatus is NULL or voidstatus ='')
        and (accttype is NULL or accttype ='' or accttype='credit')
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthtrans->execute(@$dateArrayRef) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthtrans->bind_columns( undef, \( $orderid, $trans_date ) );

  @orderidarray      = ();
  %starttdateinarray = ();
  while ( $sthtrans->fetch ) {
    $orderidarray[ ++$#orderidarray ] = $orderid;

    $starttdateinarray{"$username $trans_date"} = 1;
  }
  $sthtrans->finish;

  $mintrans_date = $today;

  # list of trans_date's for update statement
  $tdateinstr   = "";
  $tdatechkstr  = "";
  @tdateinarray = ();
  foreach my $key ( sort %starttdateinarray ) {
    my ( $chkuser, $chktdate ) = split( / /, $key );
    if ( ( $username eq $chkuser ) && ( $chktdate =~ /^[0-9]{8}$/ ) ) {

      #$tdateinstr .= "'" . $chktdate . "',";
      $tdateinstr  .= "?,";
      $tdatechkstr .= "$chktdate,";
      push( @tdateinarray, $chktdate );
    }
  }
  chop $tdateinstr;

  umask 0077;
  open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
  print logfile "tdatechkstr: $tdatechkstr\n";
  close(logfile);

  foreach $orderid ( sort @orderidarray ) {

    # operation_log should only have one orderid per username
    if ( $orderid eq $chkorderidold ) {
      next;
    }
    $chkorderidold = $orderid;

    $sthtrans2 = $dbh2->prepare(
      qq{
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,
                 auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,card_zip,
                 authtime,authstatus,forceauthtime,forceauthstatus
          from operation_log
          where orderid='$orderid'
          and username='$username'
          and trans_date>='$starttransdate'
          and trans_date<='$today'  
          and lastoptime>='$onemonthsagotime'
          and lastop in ('postauth','return')
          and lastopstatus in ('pending','locked')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthtrans2->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ( $orderid,   $operation,   $trans_date, $trans_time, $enccardnumber, $enclength, $exp,        $amount,        $auth_code, $avs_code,
      $refnumber, $finalstatus, $cvvresp,    $transflags, $card_zip,      $authtime,  $authstatus, $forceauthtime, $forceauthstatus
    )
      = $sthtrans2->fetchrow;
    $sthtrans2->finish;

    if ( $orderid eq "" ) {
      next;
    }

    #while ($sthtrans->fetch) {}

    if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/nova/stopgenfiles.txt" ) ) {
      unlink "/home/pay1/batchfiles/$devprod/nova/batchfile.txt";
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

    open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
    print logfile "$orderid $operation\n";
    close(logfile);

    $sthamt = $dbh2->prepare(
      qq{
          select amount,trans_date
          from trans_log
          where orderid='$orderid'
          and trans_date>='$twomonthsago'
          and operation in ('auth','forceauth')
          and username='$username'
          and finalstatus='success'
          and (accttype is NULL or accttype ='' or accttype='credit')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthamt->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ( $origamount, $chkdate ) = $sthamt->fetchrow;
    $sthamt->finish;

    if ( ( $chkdate < $starttransdate ) && ( $chkdate > '19990101' ) ) {
      $starttransdate = $chkdate;
    }

    print "$orderid $operation $starttransdate\n";

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "nova", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );
    print "$cardnumber\n";

    $errorflag = &errorchecking();
    if ( $errorflag == 1 ) {
      next;
    }

    if ( $batch_flag == 1 ) {
      &pidcheck();

      $batch_flag   = 0;
      $batchmessage = "";
      @batchdata    = ();
      $batchdetails = "";
      $netamount    = 0;
      $hashtotal    = 0;
      $batchcnt     = 1;
      $recseqnum    = 0;
      %errorderid   = ();

      $batchnum++;
      $batchnum = substr( "000" . $batchnum, -3, 3 );
    }

    $errorderid{$batchcnt} = $orderid;

    my $sthlock = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='locked',detailnum='$batchcnt',result='$time$batchnum'
	    where orderid='$orderid'
	    and trans_date>='$onemonthsago'
	    and username='$username'
	    and finalstatus='pending'
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
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,detailnum=?,batchstatus='pending'
          where orderid='$orderid'
          and username='$username'
          and $operationstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute( "$time$batchnum", "$batchcnt" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;

    $orderidold = $orderid;
    &batchdetail();

    if ( $batchcnt >= $batchcntuser ) {
      &batchheader();
      &batchtrailer();
      &sendrecord();
      &endbatch();
      $batch_flag = 1;
      $batchcnt   = 1;
    }
  }

  #$sthtrans->finish;

  if ( $batchcnt > 1 ) {
    &batchheader();
    &batchtrailer();
    &sendrecord();
    &endbatch();
    $batch_flag = 1;
    $batchcnt   = 1;
  }

}

sub endbatch {
  ( $d1, $ptoday, $ptime ) = &miscutils::genorderid();

  if ( ( $result eq "GBOK" ) || ( $result eq "GB TEST DROPPED" ) ) {

    print "GBOK\n";

    #unlink "/home/pay1/batchfiles/$devprod/nova/$username$time$pid.txt";

    my $dbherrorflag = 0;
    my $sthpass      = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='success',trans_time=?
	    where trans_date>='$onemonthsago'
            and trans_date<='$today'
	    and username='$username'
	    and result='$time$batchnum'
	    and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpass->execute("$ptime") or $dbherrorflag = 1;
    if ( $DBI::errstr =~ /lock.*try restarting/i ) {
      &miscutils::mysleep(60.0);
      $sthpass->execute("$ptime") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    } elsif ( $dbherrorflag == 1 ) {
      &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    }
    $sthpass->finish;

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbherrorflag = 0;

    #where trans_date>='$starttransdate'
    #and trans_date<='$today'
    $sthop1 = $dbh2->prepare(
      qq{
            update operation_log force index(oplog_tdateloptimeuname_idx) set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
            where trans_date in ($tdateinstr)
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop1->execute( "$ptime", "$ptime", @tdateinarray ) or $dbherrorflag = 1;

    if ( $DBI::errstr =~ /lock.*try restarting/i ) {
      &miscutils::mysleep(60.0);
      $sthop1->execute( "$ptime", "$ptime", @tdateinarray ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    } elsif ( $dbherrorflag == 1 ) {
      &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    }
    $sthop1->finish;

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbherrorflag = 0;

    #where trans_date>='$starttransdate'
    #and trans_date<='$today'
    $sthop2 = $dbh2->prepare(
      qq{
            update operation_log force index(oplog_tdateloptimeuname_idx) set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
            where trans_date in ($tdateinstr)
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop2->execute( "$ptime", "$ptime", @tdateinarray ) or $dbherrorflag = 1;

    if ( $DBI::errstr =~ /lock.*try restarting/i ) {
      &miscutils::mysleep(60.0);
      $sthop2->execute( "$ptime", "$ptime", @tdateinarray ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    } elsif ( $dbherrorflag == 1 ) {
      &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    }
    $sthop2->finish;

  } elsif ( $response =~ /RB INV/ ) {
    print "RB INV\n";

    #(@fields) = split(/ /,$response);
    #$batcherrnum = $fields[3] + 0;
    $batcherrnum = substr( $fields[14], 12, 4 );
    $batcherrnum = $batcherrnum + 0;
    print "RB INV: $username $batcherrnum\n";

    #$checkmessage = $response;
    #$checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    #$checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
    #print "$checkmessage\n";

    my $sthfail = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='problem',descr=?
	    where orderid='$errorderid{$batcherrnum}'
	    and trans_date>='$onemonthsago'
            and trans_date<='$today'
	    and username='$username'
	    and result='$time$batchnum'
	    and detailnum='$batcherrnum'
            and (accttype is NULL or accttype ='' or accttype='credit')
	    and finalstatus='locked'
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthfail->execute("$result") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthfail->finish;

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    $sthop3 = $dbh2->prepare(
      qq{
            update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?
	    where orderid='$errorderid{$batcherrnum}'
            and trans_date>='$starttransdate'
            and trans_date<='$today'
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and detailnum='$batcherrnum'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop3->execute("$result") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop3->finish;

    open( tmpfile, ">>/home/pay1/batchfiles/$devprod/nova/genfproblem.txt" );
    print tmpfile "username: $username\n";
    print tmpfile "orderid: $errorderid{$batcherrnum}\n";
    print tmpfile "trans_date: $today\n";
    print tmpfile "lastoptime: $onemonthsagotime\n";
    print tmpfile "batchfile: $time$batchnum\n";
    print tmpfile "detailnum: $batcherrnum\n\n";
    close(tmpfile);

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    $sthop4 = $dbh2->prepare(
      qq{
            update operation_log set returnstatus='problem',lastopstatus='problem',descr=?
	    where orderid='$errorderid{$batcherrnum}'
            and trans_date>='$starttransdate'
            and trans_date<='$today'
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and detailnum='$batcherrnum'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop4->execute("$result") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop4->finish;

    my $sthpending = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='pending'
	    where trans_date>='$onemonthsago'
            and trans_date<='$today'
	    and username='$username'
	    and result='$time$batchnum'
	    and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpending->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpending->finish;

    #where trans_date>='$starttransdate'
    #and trans_date<='$today'
    $sthop5 = $dbh2->prepare(
      qq{
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop5->execute(@tdateinarray) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop5->finish;

    #where trans_date>='$starttransdate'
    #and trans_date<='$today'
    $sthop6 = $dbh2->prepare(
      qq{
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop6->execute(@tdateinarray) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop6->finish;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: NOVA - RB INV DATA\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "orderid: $errorderid{$batcherrnum}\n";
    print MAILERR "result: $batcherrnum\n";
    print MAILERR "file: $username$time$pid.txt\n";
    print MAILERR "$result	$descr\n";
    close MAILERR;

  } elsif ( ( $response =~ /RB PLEASE RETRY/ ) || ( $response =~ /RBOUT OF BALANCE/ ) ) {
    print "RB PLEASE RETRY\n";
    my $sthpending = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='pending'
	    where trans_date>='$onemonthsago'
            and trans_date<='$today'
	    and username='$username'
	    and result='$time$batchnum'
	    and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpending->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpending->finish;

    #where trans_date>='$starttransdate'
    #and trans_date<='$today'
    $sthop1 = $dbh2->prepare(
      qq{
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop1->execute(@tdateinarray) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop1->finish;

    #where trans_date>='$starttransdate'
    #and trans_date<='$today'
    $sthop2 = $dbh2->prepare(
      qq{
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop2->execute(@tdateinarray) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop2->finish;

    @erruserarray = ( @erruserarray, $username );

    $fields[14] =~ s/[^0-9a-zA-Z _]//g;
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: NOVA - $fields[14]\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "response: $fields[14]\n";
    print MAILERR "file: $username$time$pid.txt\n";
    close MAILERR;

  } elsif ( $response =~ /SERV NOT ALLOWED/ ) {
    print "SERV NOT ALLOWED\n";
    my $sthpending = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='problem',descr='SERV NOT ALLOWED'
	    where trans_date>='$onemonthsago'
            and trans_date<='$today'
	    and username='$username'
	    and result='$time$batchnum'
	    and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpending->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpending->finish;

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );

    #and detailnum='$batcherrnum'
    #where trans_date>='$starttransdate'
    #and trans_date<='$today'
    $sthop1 = $dbh2->prepare(
      qq{
            update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?
            where trans_date in ($tdateinstr)
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop1->execute( "SERV NOT ALLOWED", @tdateinarray ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop1->finish;

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );

    #and detailnum='$batcherrnum'
    #where trans_date>='$starttransdate'
    #and trans_date<='$today'
    $sthop2 = $dbh2->prepare(
      qq{
            update operation_log set returnstatus='problem',lastopstatus='problem',descr=?
            where trans_date in ($tdateinstr)
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and batchfile='$time$batchnum'
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop2->execute( "SERV NOT ALLOWED", @tdateinarray ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop2->finish;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: NOVA - SERV NOT ALLOWED\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "response: SERV NOT ALLOWED\n";
    print MAILERR "file: $username$time$pid.txt\n";
    close MAILERR;
  } else {
    print "unknown error\n";
    $fields[14] =~ s/[^0-9a-zA-Z _]//g;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: NOVA - unknown error\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $fields[14]\n";
    print MAILERR "file: $username$time$pid.txt\n";
    close MAILERR;
  }
}

sub batchheader {
  $recseqnum = $recseqnum + 2;
  $recseqnum = substr( $recseqnum, -8, 8 );

  @bh    = ();
  $bh[0] = '@';      # network status byte (1)
  $bh[1] = 'E';      # application routing code (1)
  $bh[2] = 'NV';     # application type indicator (2) NV = third party solution
  $bh[3] = '000';    # application patch id (3)
  $bh[4] = '0';      # application sub patch id (1)   (ends on 21)
  $bh[5] = "92";     # transaction code (2)
  $bh[6] = '0';      # phone num dialed ind (1)   (ends on 24)

  my $marketind = "";
  if ( $industrycode eq "retail" ) {
    $marketind = "G";
  } elsif ( $industrycode eq "restaurant" ) {
    $marketind = "R";
  } else {
    $marketind = "I";
  }

  my $module = "";

  #if ($secondaryflag == 1) {
  $module = "C";

  #}
  #else {
  #  $module = "X";
  #}
  $bh[7] = "NH76V" . $marketind . "T" . $module;    # POS app version number - application id (8) (ends on 32)

  $bh[8]  = "$terminal_id";                         # terminal id number (22) var (begins on 33)
  $bh[9]  = pack "H2", "1C";                        # field separator
                                                    #if ($secondaryflag == 1) {
  $bh[10] = '@conex';                               # device tag routing number (6)
                                                    #}
                                                    #else {
                                                    #  $bh[10] = '000000';                 # device tag routing number (6)
                                                    #}
  $bh[11] = pack "H2", "1C";                        # field separator
  $bh[12] = "$recseqnum";                           # record count (8)
  $bh[13] = pack "H2", "1C";                        # field separator
  $bh[14] = "$netamount";                           # net dollar amount (12)
  $bh[15] = pack "H2", "1C";                        # field separator
  $bh[16] = '000';                                  # net tip amount (12)

  &genrecord( "header", @bh );
}

sub batchtrailer {

  @bt    = ();
  $bt[0] = '@';                                     # network status byte (1)
  $bt[1] = 'E';                                     # application routing code (1)
  $bt[2] = 'NV';                                    # application type indicator (2) NV = third party solution
  $bt[3] = '000';                                   # application patch id (3)
  $bt[4] = '0';                                     # application sub patch id (1)   (ends on 21)
  $bt[5] = "96";                                    # transaction code (2)
  $bt[6] = '0';                                     # phone num dialed ind (1)   (ends on 24)
                                                    #$bt[7] = 'NC76VITX';                # POS app version number (8) (ends on 32)

  my $marketind = "";
  if ( $industrycode eq "retail" ) {
    $marketind = "G";
  } elsif ( $industrycode eq "restaurant" ) {
    $marketind = "R";
  } else {
    $marketind = "I";
  }

  my $module = "";

  #if ($secondaryflag == 1) {
  $module = "C";

  #}
  #else {
  #  $module = "X";
  #}
  $bt[7] = "NH76V" . $marketind . "T" . $module;    # POS app version number - application id (8) (ends on 32)

  $bt[8]  = "$terminal_id";                         # terminal id number (22) var (begins on 33)
  $bt[9]  = pack "H2", "1C";                        # field separator
                                                    #$bt[10] = '000000';                 # device tag routing number (6)
                                                    #if ($secondaryflag == 1) {
  $bt[10] = '@conex';                               # device tag routing number (6)
                                                    #}
                                                    #else {
                                                    #  $bt[10] = '000000';                 # device tag routing number (6)
                                                    #}
  $bt[11] = pack "H2", "1C";                        # field separator
  $transdate = substr( $trans_date, 4, 4 );
  $bt[12] = $transdate;                             # transmission date MMDD (4)
  $bt[13] = pack "H2", "1C";                        # field separator
  $bt[14] = $recseqnum;                             # record count (9)
  $bt[15] = pack "H2", "1C";                        # field separator
  $bt[16] = $hashtotal;                             # net dollar amount (16)
  $bt[17] = pack "H2", "1C";                        # field separator
  $bt[18] = $netamount;                             # net dollar amount (16)

  &genrecord( "trailer", @bt );

}

sub batchdetail {
  $transamt = substr( $amount, 4 );
  $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );
  $transamt = substr( "00000000" . $transamt, -8, 8 );
  $authcode = substr( $auth_code,             0,  6 );

  if ( $operation =~ /^(auth|postauth)$/ ) {
    $netamount = $netamount + $transamt;
  } else {
    $netamount = $netamount - $transamt;
  }

  $hashtotal = $hashtotal + $transamt;

  $recseqnum++;
  $recseqnum = substr( $recseqnum, -8, 8 );

  @bd    = ();
  $bd[0] = '@';      # network status byte (1)
  $bd[1] = 'E';      # application routing code (1)
  $bd[2] = 'NV';     # application type indicator (2) NV = third party solution
  $bd[3] = '000';    # application patch id (3)
  $bd[4] = '0';      # application sub patch id (1)   (ends on 21)
  $bd[5] = "94";     # transaction code (2)
  $bd[6] = '0';      # phone num dialed ind (1)   (ends on 24)
                     #$bd[7] = 'NC76VITX';                # POS app version number (8) (ends on 32)

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

  my $module = "";

  #if ($secondaryflag == 1) {
  $module = "C";

  #}
  #else {
  #  $module = "X";
  #}

  #$appversion = substr($auth_code,101,8);
  #$appversion =~ s/ //g;
  #if (($appversion ne "") && ($appversion =~ /^N.76/) && (length($appversion == 8))) {
  #  $bd[7] = $appversion;        # POS app version number - application id (8) (ends on 32)
  #}
  #else {
  #}
  $bd[7] = "NH76V" . $marketind . "T" . $module;    # POS app version number - application id (8) (ends on 32)

  $bd[8]  = "$terminal_id";                         # terminal id number (22) var (begins on 33)
  $bd[9]  = pack "H2", "1C";                        # field separator
                                                    #$bd[10] = '000000';                 # device tag routing number (6)
                                                    #if ($secondaryflag == 1) {
  $bd[10] = '@conex';                               # device tag routing number (6)
                                                    #}
                                                    #else {
                                                    #  $bd[10] = '000000';                 # device tag routing number (6)
                                                    #}
  $bd[11] = pack "H2", "1E";                        # record separator

  $cardexp = substr( $exp, 0, 2 ) . substr( $exp, 3, 2 );

  if ( $operation eq "postauth" ) {
    $authdata = substr( $auth_code, 6, 14 );
    $authdata = $authdata . "$cardnumber=$cardexp";
    print "authdata: $authdata\n";
  } elsif ( $operation eq "return" ) {
    $trandate = substr( $trans_time, 4, 4 );
    $trantime = substr( $trans_time, 8, 4 );
    $authdata = "6$trandate$trantime" . "09  N";
    $authdata = $authdata . "$cardnumber=$cardexp";
  }
  $bd[12] = $authdata;          # authorization data (36)
  $bd[13] = pack "H2", "1C";    # field separator
  $recseqnum2 = substr( "0" x 4 . $recseqnum, -4, 4 );
  $bd[14] = $recseqnum2;        # sequence number (4)
  $bd[15] = pack "H2", "1C";    # field separator
  $authcode = substr( $auth_code, 0, 6 );
  $authcode =~ s/ //g;
  $bd[16] = $authcode;          # authorization code (6)
  $bd[17] = pack "H2", "1C";    # field separator

  $customdata = substr( $auth_code, 81, 12 );
  $customdata =~ s/ //g;
  $gratuity = substr( $auth_code,          93, 8 );
  $gratuity = substr( "0" x 6 . $gratuity, -6, 6 );
  if ( ( $industrycode eq "restaurant" ) && ( $operation ne "return" ) && ( $customdata ne "" ) ) {
    $customdata = substr( $customdata, 0, 6 ) . $gratuity;
    $bd[18] = $customdata;      # custom data
  } elsif ( ( $operation ne "return" ) && ( $customdata ne "" ) ) {
    $bd[18] = $customdata;      # custom data
  } elsif ( $transflags =~ /recurring/ ) {
    $bd[18] = '*20000000000';    # custom data
  } elsif ( $transflags =~ /moto|bill/ ) {
    $bd[18] = '*10000000000';    # custom data
  } elsif ( $industrycode eq "retail" ) {
    $bd[18] = '*90000000000';    # custom data
  } elsif ( $industrycode eq "restaurant" ) {
    $bd[18] = '*90000000000';    # custom data
  } else {
    $bd[18] = '*70000000000';    # custom data
  }
  $bd[19] = pack "H2", "1C";     # field separator
  $transamount = sprintf( "%d", ( substr( $amount, 4 ) * 100 ) + .0001 );
  $bd[20] = "$transamount";      # transaction amount
  $bd[21] = pack "H2", "1C";     # field separator
  if ( $origamount ne "" ) {
    $amt = sprintf( "%d", ( substr( $origamount, 4 ) * 100 ) + .0001 );
  } else {
    $amt = $transamount;
  }
  $bd[22] = "$amt";              # original auth amount
  $bd[23] = pack "H2", "1C";     # field separator
  $bd[24] = "$refnumber";        # ps2000
  $bd[25] = pack "H2", "1C";     # field separator

  $commcardtype = substr( $auth_code, 20, 1 );
  print "$operation $commcardtype $commtax $commponumber\n";
  print "aaaa $industrycode  $transflags  $commcardtype\n";

  if ( ( $industrycode =~ /retail|restaurant/ ) && ( $transflags !~ /moto/ ) && ( $commcardtype == 1 ) ) {
    $bd[26] = '001';             # format code 001 = purchase card
    $commponumber = substr( $auth_code, 28, 17 );
    $commponumber = substr( $commponumber . " " x 17, 0, 17 );
    $bd[27] = "$commponumber";    # format data data = customer number
    $bd[28] = pack "H2", "1C";    # field separator
    $commtax = substr( $auth_code,          21,  7 );
    $commtax = substr( "0" x 10 . $commtax, -10, 10 );
    $bd[29] = "$commtax";         # format data data = tax
  } elsif ( ( $commcardtype == 1 ) && length($auth_code) > 30 ) {
    $bd[26] = '006';              # format code 001 = purchase card
    $commponumber = substr( $auth_code, 28, 17 );
    $commponumber =~ s/ //g;

    #$commponumber = substr($commponumber . " " x 17,0,17);
    $bd[27] = "$commponumber";    # format data data = customer number
    $bd[28] = pack "H2", "1C";    # field separator
    $commtax = substr( $auth_code,          21,  7 );
    $commtax = substr( "0" x 10 . $commtax, -10, 10 );
    $bd[29] = "$commtax";         # tax
    $bd[30] = pack "H2", "1C";    # field separator
    $cardorderid = substr( $commponumber, 0, 25 );

    #$cardorderid = substr($commponumber . " " x 25,0,25);
    $bd[31] = "$cardorderid";     # format data data = invoice number
  } elsif ( ( $industrycode =~ /retail|restaurant/ ) && ( $transflags !~ /moto/ ) ) {
  } else {
    $bd[26] = '005';              # format code 005 = mail order
    $cardorderid = substr( '0' x 25 . $orderid, -25, 25 );
    $bd[27] = "$cardorderid";     # format data data = invoice number
  }

  $bd[32] = pack "H2", "1D";      # group separator
                                  # dcc stuff
  $bd[33] = "N";                  # dcc indicator
  $bd[34] = pack "H2", "1D";      # group separator
                                  # lodging data
  $bd[35] = pack "H2", "1D";      # group separator
  $bd[36] = $cvvresp;             # cvv response

  &genrecord( "detail", @bd );

  if ( $operation eq "postauth" ) {
    $filesalesamt = $filesalesamt + $transamt;
    $filesalescnt = $filesalescnt + 1;
  } else {
    $fileretamt = $fileretamt + $transamt;
    $fileretcnt = $fileretcnt + 1;
  }

  $banknumold  = $banknum;
  $usernameold = $username;
  $batchcnt++;
}

sub genrecord {
  my ( $type, @messagearray ) = @_;

  @header = ();

  #if ($secondaryflag == 1) {
  $header[0] = pack "H2", "02";    # stx
                                   #}
                                   #else {
                                   #  $header[0] = pack "H4", "0031";       # message id "0031" = request to the host
                                   #  $header[1] = pack "H4", "0000";       # destination nova node id
                                   #  $header[2] = pack "H2", "00";         # destination port
                                   #  $header[3] = pack "H4", "0000";       # source nova node id
                                   #  $header[4] = pack "H2", "00";         # source port
                                   #  $header[5] = pack "H4", "0000";       # sequence number  (ends on 13)
                                   #}

  $message = "";
  foreach $var (@header) {
    $message = $message . $var;
  }
  foreach $var (@messagearray) {
    $message = $message . $var;
  }

  #if (($secondaryflag == 1) && ($type ne "trailer")) {}
  if ( $type ne "trailer" ) {
    $trailer = pack "H2", "17";    # etb
  } else {
    $trailer = pack "H2", "03";    # etx
  }
  $message = $message . $trailer;

  #if ($secondaryflag == 1) {
  my $lrc = "";
  my $len = length($message);
  for ( my $i = 0 ; $i < $len ; $i++ ) {
    my $byte = substr( $message, $i, 1 );

    if ( $i != 0 ) {
      $lrc = $byte ^ $lrc;
    }
  }
  $message = $message . $lrc;

  #}
  #else {
  #  $length = length($message) + 2;
  #  $tcpheader = pack "H4n", "AA77", $length;
  #  if ($type ne "header") {
  #    $message = $tcpheader . $message;
  #  }
  #}

  if ( $type eq "header" ) {
    $batchheader = $message;
  } elsif ( $type eq "trailer" ) {
    $batchtrailer = $message;

    #if ($secondaryflag != 1) {
    #  $length = length($batchheader) + 2;
    #  $tcpheader = pack "H4n", "AA77", $length;
    #  $batchheader = $tcpheader . $batchheader;
    #}
  } else {
    @batchdata = ( @batchdata, $message );
    $batchdetails = $batchdetails . $message;
  }

}

sub sendrecord {

  #my $host = "certgate.viaconex.com";         # test  ##  20160926
  #my $host = "prodgate.viaconex.com";         # production  20160926
  my $host = "216.235.178.24";    # production  20160926
  my $port = "443";

  &sslsocketopen( "$host", "$port" );    # production

  #$temp = substr($batchheader,10);
  #@fields = split(/\x1c/,$temp);
  $checkmessage = $batchheader;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );

  #foreach $var (@fields) {
  #  print logfile "$var\[1c\]";
  #}
  $mytime = gmtime( time() );
  if ( $secondaryflag == 1 ) {
    print logfile "\nsecondary\n";
  }
  print logfile "$mytime send: $checkmessage\n";
  close(logfile);

  &socketwrite($batchheader);
  select undef, undef, undef, .20;

  #print "send header\n";
  #select undef, undef, undef, 20.20;

  $messagedata    = "";
  $messagedataold = "";
  foreach $var (@batchdata) {
    $messagedata = $var;

    #$messagedata = $messagedata . $var;
    $length = length($messagedata);
    if ( $length > 20 ) {
      select undef, undef, undef, .20;

      $checkmessage = $messagedata;

      #$checkmessage = $messagedataold;
      $cnum = "";
      if ( $checkmessage =~ /\x1e(.{14})([0-9]{13,19})\=[0-9]{4}\x1c/ ) {
        $cnum = $2;
        $xs   = "x" x length($cnum);
        $checkmessage =~ s/$cnum/$xs/g;
      }
      $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
      $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
      $mytime = gmtime( time() );
      open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
      print logfile "$mytime send: $checkmessage\n";
      close(logfile);

      &socketwrite($messagedata);

      $messagedataold = "";
      $messagedata    = $var;
    }
    $messagedataold = $messagedata;
  }
  if (0) {

    #if ($length > 0) {}
    select undef, undef, undef, .20;

    $checkmessage = $messagedata;
    $cnum         = "";
    if ( $checkmessage =~ /\x1e(.{14})([0-9]{13,19})\=[0-9]{4}\x1c/ ) {
      $cnum = $2;
      $xs   = "x" x length($cnum);
      $checkmessage =~ s/$cnum/$xs/g;
    }
    $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
    $mytime = gmtime( time() );
    open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
    print logfile "$mytime send: $checkmessage\n";
    close(logfile);

    &socketwrite($messagedata);

  }

  #select undef, undef, undef, 1.00;
  &miscutils::mysleep(1.0);

  $temp = substr( $batchtrailer, 10 );
  @fields = split( /\x1c/, $temp );
  $mytime = gmtime( time() );
  open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
  print logfile "$mytime send: ";
  foreach $var (@fields) {
    print logfile "$var\[1c\]";
  }
  print logfile "\n";
  close(logfile);

  &socketwrite($batchtrailer);

  #if ($secondaryflag != 1) {
  #  &socketread();
  #}

  @fields = split( /\x1c/, $response );

  #foreach $var (@fields) {
  #  print "tt$var" . "tt\n";
  #}

  $message1 = $response;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;
  $mytime = gmtime( time() );
  open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
  print logfile "$mytime recv: $message1\n\n";

  ( $result, $descr ) = split( / /, $fields[14], 2 );
  print logfile "$fields[14]	$result	$descr\n";
  close(logfile);

  #if ($secondaryflag == 1) {
  &sslsocketclose();

  #}
  #else {
  #  close(SOCK);
  #}

}

sub socketopen {
  my ( $addr, $port ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  #$iaddr = inet_aton($host);
  #my $sockaddr = sockaddr_in(0, $iaddr);
  #bind(SOCK, $sockaddr)    or die "bind: $!\n";
  connect( SOCK, $paddr ) or &socketopen2( $addr, $port, "connect: $!" );

  #sleep 20;
  $retrycnt = 0;
}

sub socketopen2 {
  my ( $addr, $port, $msg ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  print "$msg $retrycnt\n";

  system('sleep 2');
  $retrycnt++;
  if ( $retrycnt > 2000 ) {
    print "giving up\n";
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: Nova - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Batch program terminated unsuccessfully.\n\n";
    close MAILERR;

    exit;
  }

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  #$iaddr = inet_aton($host);
  #my $sockaddr = sockaddr_in(0, $iaddr);
  #bind(SOCK, $sockaddr)    or die "bind: $!\n";
  connect( SOCK, $paddr ) or &socketopen2( $addr, $port, "connect: $!" );

  #sleep 20;
}

sub socketwrite {
  ($message) = @_;

  #if ($secondaryflag == 1) {
  &socketwritefailover($message);
  return;

  #}

  #&printrecord($message);
  #send(SOCK, $message, 0, $paddr);
}

sub socketwritefailover {
  ($message) = @_;

  #my $host = "certgate.viaconex.com";         # test  ##  20160926
  #my $host = "prodgate.viaconex.com";         # production  20160926
  my $host = "216.235.188.24";    # production  20160926

  my $port = "443";

  my $len = length($message);
  my $msg = "POST /cgi-bin/encompass.cgi HTTP/1.1\r\n";
  $msg = $msg . "Content-Length: $len\r\n";
  $msg = $msg . "Host: $host:$port\r\n";
  $msg = $msg . "Registration-Key: 34S8H148QMPM040NF4L7\r\n";

  #$msg = $msg . "Registration-Key: NOVA_PORTAL_FAKE_KEY\r\n";
  $msg = $msg . "Connection: Keep-Alive\r\n";
  $msg = $msg . "\r\n";
  $msg = $msg . $message;

  ($response) = &sslsocketwrite( $msg, $host, $port );

  #if (length($response) < 20) {
  #  $result{'MStatus'} = "problem";
  #  $result{'FinalStatus'} = "problem";
  #  #$result{'MErrMsg'} = "Invalid Data From Nova";
  #  my $resp = substr($response,1,length($response)-3);
  #  $result{'MErrMsg'} = $resp;
  #  $pass = "xx";
  #}

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

sub socketread {

  vec( $rin, $temp = fileno(SOCK), 1 ) = 1;
  $count    = 4;
  $response = "";
  while ( $count && select( $rout = $rin, undef, undef, 50.0 ) ) {
    open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
    print logfile "while\n";
    close(logfile);

    recv( SOCK, $response, 2048, 0 );

    $rlen = length($response);

    #$temp = unpack "H120", $response;
    #print "$rlen $temp\n";

    $nullmessage1 = "aa77000d0011";
    $nullmessage2 = "aa550d001100";

    ($d1) = unpack "H12", $response;
    while ( ( ( $d1 eq $nullmessage1 ) || ( $d1 eq $nullmessage2 ) ) && ( $rlen >= 15 ) ) {
      print "in loop\n";
      $response = substr( $response, 15 );
      $rlen = length($response);
      ($d1) = unpack "H12", $response;
    }

    if ( $rlen > 15 ) {
      ($temp) = unpack "H*", $response;
      print "response: $temp\n";
      last;
    }
    $count--;
  }
  open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
  print logfile "end loop\n";
  close(logfile);

}

sub errorchecking {
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
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
            }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthop->execute("$errmsg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthop->finish;

}

sub sslsocketopen {
  my ( $host, $port ) = @_;

  Net::SSLeay::load_error_strings();
  Net::SSLeay::SSLeay_add_ssl_algorithms();
  Net::SSLeay::randomize('/etc/passwd');

  my $dest_serv = $host;
  my $port      = $port;

  my $dest_ip = gethostbyname($dest_serv);
  my $dest_serv_params = sockaddr_in( $port, $dest_ip );

  my $flag = "pass";
  socket( S, &AF_INET, &SOCK_STREAM, 0 ) or return ( &errmssg( "socket: $!", 1 ) );

  connect( S, $dest_serv_params ) or return ( &errmssg( "connect: $!", 1 ) );

  my $sockaddr    = getsockname(S);
  my $sockaddrlen = length($sockaddr);
  if ( $sockaddrlen == 16 ) {
    my ($sockaddrport) = unpack_sockaddr_in($sockaddr);
    my $tmpstr = inet_ntoa($dest_ip);
    open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
    print logfile "port: $tmpstr $sockaddrport\n";
    close(logfile);
  }

  if ( $flag ne "pass" ) {
    return;
  }
  select(S);
  $| = 1;
  select(STDOUT);    # Eliminate STDIO buffering

  # The network connection is now open, lets fire up SSL

  $ctx = Net::SSLeay::CTX_tlsv1_2_new() or die_now("Failed to create SSL_CTX $!");    # stops "bad mac decode" and "data between ccs and finished" errors by forcing version 2

  Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL ) and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
  $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
  Net::SSLeay::set_fd( $ssl, fileno(S) );                                             # Must use fileno
  my $res = Net::SSLeay::connect($ssl) or &error("$!");

  #$res = Net::SSLeay::connect($ssl) and Net::SSLeay::die_if_ssl_error("ssl connect");

  open( TMPFILE, ">>/home/pay1/batchfiles/$devprod/ciphers.txt" );
  print TMPFILE __FILE__ . ": " . Net::SSLeay::get_cipher($ssl) . "\n";
  close(TMPFILE);
}

sub sslsocketclose {
  Net::SSLeay::free($ssl);                                                            # Tear down connection
  Net::SSLeay::CTX_free($ctx);
  close S;
}

sub sslsocketwrite {
  my ( $req, $host, $port ) = @_;

  my $cardnum    = $cardnumber;
  my $sep        = pack "H2", "1c";
  my $xs         = "x" x length($cardnum);
  my $messagestr = $req;
  $messagestr =~ s/$cardnum/$xs/g;
  if ( $messagestr =~ /$xs=([0-9]{4})=1([0-9]{3,4}) {0,1}\x1c/ ) {
    my $exp = $1;
    my $cvv = $2;
    my $xs2 = "x" x length($cvv);
    $messagestr =~ s/$xs=$exp=1$cvv/$xs=$exp=1$xs2/;
  }

  my $cardnumber = $cardnum;

  #my $sha1 = new SHA;
  #$sha1->reset;
  #$sha1->add($cardnumber);
  #my $shacardnumber = $sha1->hexdigest();
  my $cc            = new PlugNPay::CreditCard($cardnumber);
  my $shacardnumber = $cc->getCardHash();

  #my $temp = gmtime(time());
  #my $checkmessage = $messagestr;
  #$checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  #$checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  #$checkmessage =~ s/\[0d\]\[0a\]/\n/g;
  #$checkmessage =~ s/\[2d\]/-/g;
  #$checkmessage =~ s/\[2e\]/./g;
  #$checkmessage =~ s/\[2f\]/\//g;
  #$checkmessage =~ s/\[3a\]/:/g;
  #$checkmessage =~ s/\[02\]/\n\[02\]/g;
##open(logfile,">>/home/pay1/batchfiles/$devprod/nova/serverlogmsgtest.txt");
  #open(logfile,">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt");
  #print logfile "\n$username $orderid secondary\n";
  #print logfile "$temp send: $checkmessage  $shacardnumber\n";
  #close(logfile);

  #print "cccc\n";

  if (0) {
    Net::SSLeay::load_error_strings();
    Net::SSLeay::SSLeay_add_ssl_algorithms();
    Net::SSLeay::randomize('/etc/passwd');

    my $dest_serv = $host;
    my $port      = $port;

    my $dest_ip = gethostbyname($dest_serv);
    my $dest_serv_params = sockaddr_in( $port, $dest_ip );

    my $flag = "pass";
    socket( S, &AF_INET, &SOCK_STREAM, 0 ) or return ( &errmssg( "socket: $!", 1 ) );

    connect( S, $dest_serv_params ) or return ( &errmssg( "connect: $!", 1 ) );

    if ( $flag ne "pass" ) {
      return;
    }
    select(S);
    $| = 1;
    select(STDOUT);    # Eliminate STDIO buffering

    # The network connection is now open, lets fire up SSL
    $ctx = Net::SSLeay::CTX_v3_new() or die_now("Failed to create SSL_CTX $!");

    # stops "bad mac decode" and "data between ccs and finished" errors by forcing version 2

    #$ctx = Net::SSLeay::CTX_new() or die_now("Failed to create SSL_CTX $!");

    Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL ) and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
    $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
    Net::SSLeay::set_fd( $ssl, fileno(S) );    # Must use fileno
    my $res = Net::SSLeay::connect($ssl) or &error("$!");

    #$res = Net::SSLeay::connect($ssl) and Net::SSLeay::die_if_ssl_error("ssl connect");

    open( TMPFILE, ">>/home/pay1/logfiles/ciphers.txt" );
    print TMPFILE __FILE__ . ": " . Net::SSLeay::get_cipher($ssl) . "\n";
    close(TMPFILE);
  }

  #open(logfile,">>/home/pay1/batchfiles/$devprod/nova/packet.txt");
  #print logfile "$req\n";
  #close(logfile);

  print "cccc\n";

  # Exchange data
  $res = Net::SSLeay::ssl_write_all( $ssl, $req );    # Perl knows how long $msg is
                                                      #Net::SSLeay::die_if_ssl_error("ssl write");

  #shutdown S, 1;  # Half close --> No more output, sends EOF to server

  my $respenc = "";

  my ( $rin, $rout, $temp );
  vec( $rin, $temp = fileno(S), 1 ) = 1;
  my $count = 8;
  while ( $count && select( $rout = $rin, undef, undef, 75.0 ) ) {

    #$respenc = Net::SSLeay::ssl_read_all($ssl);    # Perl returns undef on failure
    my $got = Net::SSLeay::read($ssl);                # Perl returns undef on failure
                                                      #open(tmpfile,">>/home/pay1/batchfiles/$devprod/nova/sslserverlogmsg.txt");
                                                      #print tmpfile "got: $got\n";
    print "got: $got\n";

    #close(tmpfile);
    $respenc = $respenc . $got;
    if ( $respenc =~ /\x03|\x06|\x15/ ) {
      last;
    }

    #Net::SSLeay::die_if_ssl_error("ssl read");
    $count--;
  }

  my $response = $respenc;

  #Net::SSLeay::free ($ssl);               # Tear down connection
  #Net::SSLeay::CTX_free ($ctx);
  #close S;

  #open(logfile,">>/home/pay1/batchfiles/$devprod/nova/packet.txt");
  #print logfile "$response\n";
  #close(logfile);

  my $header;
  ( $header, $response ) = split( /\r{0,1}\n\r{0,1}\n/, $response );

  my $temp         = gmtime( time() );
  my $checkmessage = $response;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $checkmessage =~ s/\[0d\]\[0a\]/\n/g;
  $checkmessage =~ s/\[2d\]/-/g;
  $checkmessage =~ s/\[2e\]/./g;
  $checkmessage =~ s/\[2f\]/\//g;
  $checkmessage =~ s/\[3a\]/:/g;

  #open(logfile,">>/home/pay1/batchfiles/$devprod/nova/serverlogmsgtest.txt");
  open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
  print logfile "$temp recv: $checkmessage\n\n";
  close(logfile);

  return $response, $header;
}

sub errmssg {
  my ( $mssg, $level ) = @_;

  $result{'MStatus'}     = "problem";
  $result{'FinalStatus'} = "problem";
  $rmessage              = $mssg;

  if ( $level != 1 ) {
    Net::SSLeay::free($ssl);    # Tear down connection
    Net::SSLeay::CTX_free($ctx);
  }
  close S;
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
  open( infile, "/home/pay1/batchfiles/$devprod/nova/pid$group.txt" );
  $chkline = <infile>;
  chop $chkline;
  close(infile);

  if ( $pidline ne $chkline ) {
    umask 0077;
    open( logfile, ">>/home/pay1/batchfiles/$devprod/nova/$fileyear/$username$time$pid.txt" );
    print logfile "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    print logfile "$pidline\n";
    print logfile "$chkline\n";
    close(logfile);

    print "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    print "$pidline\n";
    print "$chkline\n";

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: nova - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl $group already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

