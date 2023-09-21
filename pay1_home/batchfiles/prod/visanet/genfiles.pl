#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use Net::SSLeay qw(get_https post_https sslcat make_headers make_form);
use IO::Socket;
use Socket;
use rsautils;
use isotables;
use smpsutils;
use Time::Local;

$devprod = "logs";

# test ip 206.175.128.3

# visa net DirectLink-visanet version 1.7

my $mygroup = $ARGV[0];
if ( $mygroup eq "" ) {
  $mygroup = "0";
}
my $printstr = "group: $mygroup\n";
&procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

# xxxx
$usevnetsslflag = 0;    # do not comment this line

if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/visanet/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'visanet/genfiles.pl $mygroup'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: visanet - genfiles already running\n";
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
&procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet", "pid$mygroup.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

$chkline = &procutils::fileread( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet", "pid$mygroup.txt" );
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl $mygroup already running, pid alterred by another program, exiting...\n";
  $printstr .= "$pidline\n";
  $printstr .= "$chkline\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: visanet - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl $mygroup already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

$time = time();
( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $d8, $d9, $modtime ) = stat "/home/pay1/batchfiles/$devprod/visanet/genfiles$mygroup.txt";

$delta = $time - $modtime;

if ( $delta < ( 3600 * 12 ) ) {
  umask 0033;
  $checkuser = &procutils::fileread( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet", "genfiles$mygroup.txt" );
  chop $checkuser;

}

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>='$checkuser'";
}

#$checkstring = "and t.username='aaaa'";
#$checkstring = "and t.username in ('aaaa','aaaa')";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 * 2 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

#print "two months ago: $twomonthsago\n";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $dummy, $today, $ttime ) = &miscutils::genorderid();
$todaytime = $ttime;

#$runtime = substr($ttime,8,2);

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/visanet/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/visanet/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/visanet/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/visanet/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/visanet/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/visanet/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/visanet/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/visanet/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/visanet/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/visanet/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: visanet - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/visanet/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;

#$dbh = &miscutils::dbhconnect("pnpmisc");

my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from operation_log o, trans_log t
        where t.trans_date>=?
        and t.trans_date<=?
        and t.operation in ('postauth','return')
        $checkstring
        and t.finalstatus='pending'
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.processor='visanet'
        and o.lastoptime>=?
        and o.lastopstatus='pending'
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];
  print "userarray: $user\n";

  if ( $user ne "downgrape" ) {
    @userarray = ( @userarray, $user );
  }
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

foreach $username ( sort @userarray ) {
  &processbatch();
}

if ( $usercountarray{"downgrape"} ne "" ) {
  $username = "downgrape";
  &processbatch();
}

#$dbh->disconnect;
#$dbh2->disconnect;

unlink "/home/pay1/batchfiles/$devprod/visanet/batchfile.txt";

if ( ( !-e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) && ( !-e "/home/pay1/batchfiles/$devprod/visanet/stopgenfiles.txt" ) ) {
  umask 0033;
  $checkinstr = "";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet", "genfiles$mygroup.txt", "write", "", $checkinstr );
}

exit;

sub pidcheck {
  $chkline = &procutils::fileread( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet", "pid$mygroup.txt" );
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl $mygroup already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl $mygroup $mygroup already running, pid alterred by another program, exiting...\n";
    $printstr .= "$pidline\n";
    $printstr .= "$chkline\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: visanet - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl $mygroup $mygroup already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

sub processbatch {
  if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/visanet/stopgenfiles.txt" ) ) {
    unlink "/home/pay1/batchfiles/$devprod/visanet/batchfile.txt";
    last;
  }

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet", "batchfile.txt", "write", "", $batchfilestr );

  $dontallowamexflag = 0;
  $dontallowdiscflag = 0;

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  if ( $usercountarray{$username} > 2000 ) {
    $batchcntuser = 500;    # visanet has trouble doing more than 500 records in a batch
  } elsif ( $usercountarray{$username} > 1000 ) {
    $batchcntuser = 300;
  } elsif ( $usercountarray{$username} > 600 ) {
    $batchcntuser = 200;
  } elsif ( $usercountarray{$username} > 300 ) {
    $batchcntuser = 100;
  } else {
    $batchcntuser = 100;
  }

  if ( $username =~ /^(agencyinsu1|agencyserv|agencyserv1|mariobades3|mariobade4|cyd1423506)$/ ) {
    $batchcntuser = 1200;
  }

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,company,addr1,city,state,zip,tel,status,currency,
		switchtime,features
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $company, $address, $city, $state, $zip, $tel, $status, $currency, $switchtime, $features ) =
    &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
        select agentbank,agentchain,storenum,categorycode,bin,terminalnum,industrycode,track,batchtime,capabilities,
                authen,requestorid,payfacid,payfacname,mvv
        from visanet
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $agentbank, $agentchain, $storenum, $categorycode, $bin, $terminalnum, $industrycode, $track, $batchgroup, $capabilities, $authencode, $tokenreqid, $payfacid, $payfacname, $mvv ) =
    &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $status ne "live" ) {
    return;
  }

  if ( ( $mygroup eq "6" ) && ( $batchgroup ne "6" ) ) {
    return;
  } elsif ( ( $mygroup eq "5" ) && ( $batchgroup ne "5" ) ) {
    return;
  } elsif ( ( $mygroup eq "4" ) && ( $batchgroup ne "4" ) ) {
    return;
  } elsif ( ( $mygroup eq "3" ) && ( $batchgroup ne "3" ) ) {
    return;
  } elsif ( ( $mygroup eq "2" ) && ( $batchgroup ne "2" ) ) {
    return;
  } elsif ( ( $mygroup eq "1" ) && ( $batchgroup ne "1" ) ) {
    return;
  } elsif ( ( $mygroup eq "0" ) && ( $batchgroup ne "" ) ) {
    return;
  } elsif ( $mygroup !~ /^(0|1|2|3|4|5|6)$/ ) {
    return;
  }

  print "processuser: $username\n";
  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet", "genfiles$mygroup.txt", "write", "", $checkinstr );

  #if (($runtime =~ /(20|21|22|23|00|01|02|03|04|05|06)/) && ($batchtime eq "2")) {
  #  return;
  #}
  #elsif (($runtime !~ /(20|21|22|23|00|01|02|03|04|05|06)/) && ($batchtime ne "2")) {
  #  return;
  #}

  umask 0077;
  $logfilestr = "";
  my $printstr = "$username $starttransdate\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr .= "$username\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "write", "", $logfilestr );

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
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  my $printstr = "gmt today: $todaytime\n";
  $printstr .= "est today: $esttime\n";
  $printstr .= "est yesterday: $yesterday\n";
  $printstr .= "settletime: $settletime\n";
  $printstr .= "sweeptime: $sweeptime\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr .= "$username  sweeptime: $sweeptime  settletime: $settletime\n";
  $logfilestr .= "$features\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  $redobatch = 1;
  $firstredo = 0;
  while ( $redobatch == 1 ) {

    $batch_flag = 0;
    $netamount  = 0;
    $hashtotal  = 0;
    $batchcnt   = 1;
    $recseqnum  = 0;
    $redobatch  = 0;

    my $printstr = "starttransdate: $starttransdate\n";
    $printstr .= "today: $today\n";
    $printstr .= "onemonthsagotime: $onemonthsagotime\n";
    $printstr .= "username: $username\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

    #select orderid,trans_date
    #from operation_log force index(oplog_tdateloptimeuname_idx)
    #where trans_date>=?
    #and trans_date<=?
    #and lastoptime>=?
    #and username=?
    #and lastopstatus='pending'
    #and lastop in ('postauth','return')
    #and (voidstatus is NULL or voidstatus ='')
    #and (accttype is NULL or accttype ='' or accttype='credit')

    print "before orderidarray\n";
    my $dbquerystr = <<"dbEOM";
        select o.orderid,o.trans_date
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
        and o.processor='visanet'
        and (o.voidstatus is NULL or o.voidstatus ='')
        and (o.accttype is NULL or o.accttype ='' or o.accttype='credit')
dbEOM
    my @dbvalues = ( "$onemonthsago", "$username" );
    my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %orderidarray = ();
    for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 2 ) {
      ( $orderid, $trans_date ) = @sthtransvalarray[ $vali .. $vali + 1 ];

      #print "$orderid\n";
      $orderidarray{"$orderid"} = 1;

      $starttdateinarray{"$username $trans_date"} = 1;
    }

    print "after orderidarray\n";

    my $printstr = "bbbb\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

    $mintrans_date      = $today;
    $postauthtrans_date = $today;

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
    $logfilestr = "";
    $logfilestr .= "tdatechkstr: $tdatechkstr\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    foreach $orderid ( sort keys %orderidarray ) {

      my $dbquerystr = <<"dbEOM";
            select lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,transflags,refnumber,lastopstatus,cardtype
            from operation_log
            where orderid=?
            and username=?
dbEOM
      my @dbvalues = ( "$orderid", "$username" );
      ( $operation, $trans_date, $trans_time, $enccardnumber, $enclength, $exp, $amount, $auth_code, $avs_code, $transflags, $refnumber, $finalstatus, $card_type ) =
        &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/visanet/stopgenfiles.txt" ) ) {
        unlink "/home/pay1/batchfiles/$devprod/visanet/batchfile.txt";
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
        $orderidold = $orderid;
        next;    # transaction is newer than sweeptime
      }

      if ( ( $trans_date < $mintrans_date ) && ( $trans_date >= '19990101' ) ) {
        $mintrans_date = $trans_date;
      }
      if ( ( $operation eq "postauth" ) && ( $trans_date < $postauthtrans_date ) && ( $trans_date >= '19990101' ) ) {
        $postauthtrans_date = $trans_date;
      }

      #select amount,operation
      #from trans_log
      #where orderid='$orderid'
      #and trans_date>='$twomonthsago'
      #and operation in ('auth','forceauth')
      #and username='$username'
      #and (accttype is NULL or accttype='credit')
      my $dbquerystr = <<"dbEOM";
          select authtime,authstatus,forceauthtime,forceauthstatus,reauthtime,reauthstatus,origamount
          from operation_log
          where orderid=?
          and username=?
          and lastoptime>=?
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$orderid", "$username", "$onemonthsagotime" );
      ( $authtime, $authstatus, $forceauthtime, $forceauthstatus, $reauthtime, $reauthstatus, $origamount ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      if ( $switchtime ne "" ) {
        $switchtime = substr( $switchtime . "0" x 14, 0, 14 );
        if ( ( $operation eq "postauth" ) && ( $authtime ne "" ) && ( $authtime < $switchtime ) ) {
          next;
        }
      }

      if ( ( $authtime ne "" ) && ( $authstatus eq "success" ) ) {

        #$trans_time = $authtime;
        $origoperation = "auth";
      } elsif ( ( $forceauthtime ne "" ) && ( $forceauthstatus eq "success" ) ) {

        #$trans_time = $forceauthtime;
        $origoperation = "forceauth";
      } else {

        #$trans_time = "";
        $origoperation = "";
        $origamount    = "";
      }

      if ( ( $reauthtime ne "" ) && ( $reauthstatus eq "success" ) ) {
        $reauthflag = 1;
      } else {
        $reauthflag = 0;
      }

      umask 0077;
      $logfilestr = "";
      $logfilestr .= "$orderid $operation\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      my $printstr = "$orderid $operation\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

      $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "visanet", $enccardnumber );

      $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

      if ( $transflags !~ /(ctoken|ttoken)/ ) {
        $card_type = &smpsutils::checkcard($cardnumber);
      }

      $errorflag = &errorchecking();
      if ( $errorflag == 1 ) {
        next;
      }

      if ( ( $dontallowamexflag == 1 ) && ( $card_type eq "ax" ) ) {
        next;
      } elsif ( ( $dontallowdiscflag == 1 ) && ( $card_type eq "ds" ) ) {
        next;
      }

      if ( $batchcnt == 1 ) {
        if ( $usevnetsslflag == 0 ) {
          &socketopen( "64.66.62.9", "5000" );    # production
                                                  #&socketopen("64.66.62.9","5001");       # test
          recv( SOCK, $respenc, 2048, 0 );

          umask 0077;
          $logfilestr = "";
          $temp = unpack "H*", $respenc;
          my $printstr = "recva: $temp\n";
          &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
          $logfilestr .= "recva: $temp\n";
          &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

          if ( $respenc !~ /\x05/ ) {
            recv( SOCK, $respenc, 2048, 0 );

            umask 0077;
            $logfilestr = "";
            $temp = unpack "H*", $respenc;
            my $printstr = "recvb: $temp\n";
            &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
            $logfilestr .= "recvb: $temp\n";
            &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
          }
        }

        my $printstr = "\nsocketopen\n";
        &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
        $errorflag       = 0;
        $startbatchflag  = 1;
        $returnsincluded = 0;

        &pidcheck();

        &batchheader();
        $startbatchflag = 0;
        if ( $merchanterrorflag == 1 ) {
          last;
        } elsif ( $errorflag == 1 ) {
          $batchcnt = 1;
          next;
        }
      }

      if ( $operation eq "return" ) {
        $returnsincluded = 1;
      }

      my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='locked',result=?
	    where orderid=?
	    and username=?
	    and trans_date>=?
	    and finalstatus='pending'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$time$batchnum", "$orderid", "$username", "$onemonthsago" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      $operationstatus = $operation . "status";
      $operationtime   = $operation . "time";
      my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending'
          where orderid=?
          and username=?
          and $operationstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$time$batchnum", "$orderid", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      &batchdetail();
      if ( $errorcnt{$username} > 5 ) {
        last;
      }
      if ( $errorflag == 1 ) {
        $batchcnt = 1;
        next;
      }

      if ( $batchcnt >= $batchcntuser ) {
        $endbatchflag = 1;
        &batchtrailer();
        &sslsend();
        $batchcnt     = 1;
        $endbatchflag = 0;
      }
    }

    if ( $batchcnt > 1 ) {
      $endbatchflag = 1;
      &batchtrailer();
      &sslsend();
      $endbatchflag = 0;
    }

  }

}

sub batchheader {
  $cashbacktotal     = 0;
  $netamount         = 0;
  $hashtotal         = 0;
  $recseqnum         = 0;
  $batch_flag        = 0;
  $batchsalescnt     = 0;
  $batchsalesamt     = 0;
  $batchretcnt       = 0;
  $batchretamt       = 0;
  %errorderid        = ();
  $bigmessage        = "";
  $merchanterrorflag = 0;

  $batchcount++;

  my $dbquerystr = <<"dbEOM";
          select batchnum
          from visanet
          where username=?
dbEOM
  my @dbvalues = ("$username");
  ($batchnum) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = $batchnum + 1;
  if ( $batchnum >= 998 ) {
    $batchnum = 1;
  }

  my $dbquerystr = <<"dbEOM";
          update visanet set batchnum=?
          where username=?
dbEOM
  my @dbvalues = ( "$batchnum", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchreccnt = 1;
  $filereccnt++;
  $recseqnum++;

  @bh = ();
  $bh[0] = pack "H2", "02";    # stx
  $bh[1] = 'K';                # record format (1a)
  my $sendapptype = "1";
  if ( $transflags =~ /level3/ ) {
    $sendapptype = "5";
  }
  $bh[2] = $sendapptype;       # application type 0 = single, 4 = multiple interleaved(1a)
  $bh[3] = '.';                # message delimiter (1a)
  $bh[4] = 'Z';                # X.25 Routing ID (1a)
  if ( $industrycode !~ /^(retail|grocery|restaurant)$/ ) {
    $bh[5] = 'H@@@R';          # record type (5a)
    if ( $authencode ne "" ) {
      $bh[5] = 'H@@@Z';
    }
  } else {
    $bh[5] = 'H@@@P';          # record type (5a)
    if ( $authencode ne "" ) {
      $bh[5] = 'H@@@X';
    }
  }
  $bin = substr( "0" x 6 . $bin, -6, 6 );
  $bh[6] = $bin;               # acquirer bin (6n) 999295
  $agentbank = substr( "0" x 6 . $agentbank, -6, 6 );
  $bh[7] = $agentbank;         # agent bank number (6n)
  $agentchain = substr( "0" x 6 . $agentchain, -6, 6 );
  $bh[8] = $agentchain;        # agent chain number (6n)
  $mid = substr( "0" x 12 . $merchant_id, -12, 12 );
  $bh[9] = $mid;               # merchant number (12n)
  $storenum = substr( "0" x 4 . $storenum, -4, 4 );
  $bh[10] = $storenum;         # store number (4n)
  $terminalnum = substr( "0" x 4 . $terminalnum, -4, 4 );
  $bh[11] = $terminalnum;      # terminal number (4n)
                               #if ($usevnetsslflag == 1) {
                               #  $bh[12] = 'E';                    # device code (1a) E - electronic cash register 4.33
                               #}
                               #else {
  $bh[12] = 'Q';               # device code (1a) Q - third party developer 4.33
                               #}

  if ( $transflags =~ /(bill|recur|install|motox)/ ) {
    $bh[13] = 'D';             # industry code (1a) D - direct marketing 4.40
  } elsif ( $industrycode eq "retail" ) {
    $bh[13] = "R";             # industry code (1a) D - direct marketing, R - retail, F - restaurant, G - grocery 4.40
  } elsif ( $industrycode eq "restaurant" ) {
    $bh[13] = "F";             # industry code (1a) D - direct marketing, R - retail, F - restaurant, G - grocery 4.40
  } elsif ( $industrycode eq "grocery" ) {
    $bh[13] = "G";             # industry code (1a) D - direct marketing, R - retail, F - restaurant, G - grocery 4.40
  } else {
    $bh[13] = 'D';             # industry code (1a) D - direct marketing 4.40
  }
  if ( $currency eq "" ) {
    $currency = "usd";
  }
  $currency =~ tr/a-z/A-Z/;
  $currencycode = $isotables::currencyUSD840{$currency};
  $bh[14]       = $currencycode;                           # currency code (3n)
  $bh[15]       = '00';                                    # language indicator (2n) 00 - english 4.45
  $bh[16]       = '705';                                   # time zone differential (3n) - 705 = using EST (not sure if correct)
  $batchdate    = substr( $today, 4, 4 );
  $bh[17]       = $batchdate;                              # batch transmission date (4n)
  $batchnum     = substr( "000" . $batchnum, -3, 3 );
  $bh[18]       = $batchnum;                               # batch number (3n)
  $bh[19]       = '0';                                     # blocking indicator (1n)

  # group 2
  if ( $industrycode !~ /^(retail|grocery|restaurant)$/ ) {
    $tel =~ s/^1//;
    $tel =~ s/[^0-9A-Z]//g;
    $tel = substr( $tel, 0, 3 ) . '-' . substr( $tel, 3, 7 );
    $tel = substr( $tel . " " x 11, 0, 11 );
    $bh[20] = $tel;                                        # 999-9999999
    $bh[21] = $tel;                                        # 999-9999999
  }

  # group 4
  if ( $authencode ne "" ) {
    $authencode = substr( $authencode . " " x 24, 0, 24 );
    $bh[22] = "$authencode";
  }

  # group 5
  $bh[23] = '000325';                                      # developer id
  $bh[24] = 'B031';                                        # version id

  $bh[25] = pack "H2", "17";                               # etb

  $message = "";
  foreach $var (@bh) {
    $message = $message . $var;
  }
  &sendrecord($message);
  if ( ( $usevnetsslflag == 0 ) && ( ( length($response) != 1 ) || ( $response !~ /^(\x05|\x06|\x07)$/ ) ) ) {
    $errorcnt{$username}++;
    &error("header");
  }

  $recseqnum++;

  @bp = ();
  $bp[0] = pack "H2", "02";    # stx
  $bp[1] = 'K';                # record format (1a)
  my $sendapptype = "1";
  if ( $transflags =~ /level3/ ) {
    $sendapptype = "5";
  }
  $bp[2]       = $sendapptype;    # application type 0 = single, 4 = multiple interleaved(1a)
  $bp[3]       = '.';             # message delimiter (1a)
  $bp[4]       = 'Z';             # X.25 Routing ID (1a)
  $bp[5]       = 'P@@@@';         # record type (5a)
  $countrycode = "840";           # 084 = US
  $bp[6]       = $countrycode;    # country code (3n)
  $zip =~ s/[^0-9]//g;
  $zip = substr( $zip . " " x 9, 0, 9 );
  $bp[7] = $zip;                  # city code (9a)
  $bp[8] = $categorycode;         # merchant category code (4n)
  $company =~ tr/a-z/A-Z/;
  $company = substr( $company . " " x 25, 0, 25 );
  $bp[9] = $company;              # merchant name (25a)
  my $data = "";

  if ( $industrycode =~ /^(retail|grocery|restaurant)$/ ) {
    $city =~ tr/a-z/A-Z/;
    $data = substr( $city . " " x 13, 0, 13 );
  } else {
    $tel =~ s/[^0-9A-Z]//g;
    $tel = substr( $tel, 0, 3 ) . '-' . substr( $tel, 3, 7 );
    $data = substr( $tel . " " x 13, 0, 13 );
  }
  $bp[10] = $data;                # merchant city or tel (13a)
  $state =~ tr/a-z/A-Z/;
  $state = substr( $state . "  ", 0, 2 );
  $bp[11] = $state;               # merchant state (2a)
  $bp[12] = '00001';              # merchant location number (5a)
  $tid = substr( "0" x 8 . $terminal_id, -8, 8 );
  $bp[13] = $tid;                 # terminal id number (8n)
  $bp[14] = pack "H2", "17";      # etb

  $message = "";
  foreach $var (@bp) {
    $message = $message . $var;
  }
  &sendrecord($message);

  if ( ( $usevnetsslflag == 0 ) && ( ( length($response) != 1 ) || ( $response !~ /^(\x05|\x06|\x07)$/ ) ) ) {
    &error("parameter");
  }

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

  $batchcnt++;
  $batchreccnt++;
  $recseqnum++;

  $commcardtype = "";
  if ( $operation eq "postauth" ) {
    $commcardtype = substr( $auth_code, 29, 10 );
    $commcardtype =~ s/ //g;
  }
  my $printstr = "commcardtype: $commcardtype\n\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  my $printstr = "auth_code: $auth_code " . length($auth_code) . "\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  if ( ( $operation eq "postauth" ) && ( ( length($auth_code) == 8 ) || ( length($auth_code) == 20 ) || ( length($auth_code) == 171 ) ) ) {
    $authcode         = substr( $auth_code . " " x 6, 0, 6 );
    $aci              = " ";
    $auth_src         = substr( $auth_code, 7, 1 );
    $auth_src         = substr( $auth_src . " ", 0, 1 );
    $resp_code        = "  ";
    $trans_id         = "0" x 15;
    $val_code         = "    ";
    $trandate         = substr( $trans_time, 4, 4 );
    $trantime         = substr( $trans_time, 8, 6 );
    $l3trandate       = substr( $trans_time, 2, 6 );
    $transseqnum      = "0001";
    $tax              = "0" x 12;
    $ponumber         = "";
    $cardholderidcode = "";
    $acctdatasrc      = "";
    $requestedaci     = "";
    if ( length($auth_code) == 20 ) {
      $gratuity = substr( $auth_code, 8, 12 );
    } else {
      $gratuity = "0" x 12;
    }
    $restorigamount = "0" x 12;

    my $dbquerystr = <<"dbEOM";
        select transseqnum
        from visanet
        where username=?
dbEOM
    my @dbvalues = ("$username");
    ($transseqnum) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $transseqnum = ( $transseqnum % 9999 ) + 1;

    my $dbquerystr = <<"dbEOM";
        update visanet set transseqnum=?
        where username=?
dbEOM
    my @dbvalues = ( "$transseqnum", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $transseqnum = substr( "0000" . $transseqnum, -4, 4 );
  } elsif ( ( $operation eq "postauth" ) || ( ( $card_type =~ /(vi|mc|ds)/ ) && ( $operation eq "return" ) && ( substr( $auth_code, 0, 6 ) ne "      " ) && ( length($auth_code) != 0 ) ) ) {
    $authcode  = substr( $auth_code . " " x 6, 0,  6 );
    $aci       = substr( $auth_code,           6,  1 );
    $aci       = substr( $aci . " ",           0,  1 );
    $auth_src  = substr( $auth_code,           7,  1 );
    $auth_src  = substr( $auth_src . " ",      0,  1 );
    $resp_code = substr( $auth_code,           8,  2 );
    $resp_code = substr( $resp_code . "  ",    0,  2 );
    $trans_id  = substr( $auth_code,           10, 15 );
    $trans_id  = substr( $trans_id . "0" x 15, 0,  15 );
    $val_code  = substr( $auth_code,           25, 4 );
    $val_code  = substr( $val_code . " " x 4,  0,  4 );
    $trandate  = substr( $auth_code,           39, 4 );
    $l3trandate = substr( $auth_code, 43, 2 ) . substr( $auth_code, 39, 4 );
    $trantime = substr( $auth_code, 45, 6 );

    #if ($username eq "taketoau2") {}
    if ( (0) && ( ( $industrycode !~ /^(retail|grocery|restaurant)$/ ) || ( $transflags =~ /moto/ ) ) ) {    # shaila 04/30/2020
      my $ltime = &miscutils::strtotime($trans_time);
      if ( $ltime ne "" ) {
        my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($ltime);
        $year     = $year + 1900;
        $year     = substr( $year, 2, 2 );
        $trantime = sprintf( "%04d%02d%02d%02d%02d%02d", $year, $month + 1, $day, $hour, $min, $sec );
      } else {
        $trantime = $trans_time;
      }
      $trandate   = substr( $trantime, 4, 4 );
      $l3trandate = substr( $trantime, 2, 6 );
      $trantime   = substr( $trantime, 8, 6 );
    }
    $trandate    = substr( $trandate . " " x 4,    0,   4 );
    $trantime    = substr( $trantime . " " x 6,    0,   6 );
    $transseqnum = substr( $auth_code,             51,  4 );
    $transseqnum = substr( $transseqnum . " " x 4, 0,   4 );
    $tax         = substr( $auth_code,             55,  8 );
    $tax         = substr( "0" x 12 . $tax,        -12, 12 );
    $ponumber    = substr( $auth_code,             63,  25 );
    $ponumber =~ s/ //g;
    $cardholderidcode = substr( $auth_code, 88,  1 );
    $acctdatasrc      = substr( $auth_code, 89,  1 );
    $requestedaci     = substr( $auth_code, 90,  1 );
    $gratuity         = substr( $auth_code, 91,  12 );
    $restorigamount   = substr( $auth_code, 103, 12 );
  } else {
    $authcode  = " " x 6;
    $aci       = " ";
    $auth_src  = "9";
    $resp_code = "  ";
    $trans_id  = "0" x 15;
    $val_code  = "    ";

    #$trandate = substr($trans_time,4,4);
    #$trantime = substr($trans_time,8,6);
    my $ltime = &miscutils::strtotime($trans_time);
    if ( $ltime ne "" ) {
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($ltime);
      $year     = $year + 1900;
      $year     = substr( $year, 2, 2 );
      $trantime = sprintf( "%04d%02d%02d%02d%02d%02d", $year, $month + 1, $day, $hour, $min, $sec );
    } else {
      $trantime = $trans_time;
    }
    $trandate   = substr( $trantime, 4, 4 );
    $l3trandate = substr( $trantime, 2, 6 );
    $trantime   = substr( $trantime, 8, 6 );

    $tax              = "0" x 12;
    $ponumber         = "";
    $cardholderidcode = "";
    $acctdatasrc      = "";
    $requestedaci     = "";
    $gratuity         = "0" x 12;
    $restorigamount   = "0" x 12;

    my $dbquerystr = <<"dbEOM";
        select transseqnum
        from visanet
        where username=?
dbEOM
    my @dbvalues = ("$username");
    ($transseqnum) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $transseqnum = ( $transseqnum % 9999 ) + 1;

    my $dbquerystr = <<"dbEOM";
        update visanet set transseqnum=?
        where username=?
dbEOM
    my @dbvalues = ( "$transseqnum", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $transseqnum = substr( "0000" . $transseqnum, -4, 4 );
  }

  if ( $transseqnum =~ / / ) {
    $transseqnum = "0001";
  }

  $cardlevelresults = substr( $auth_code, 115, 2 );
  $cardlevelresults =~ s/ //g;

  @bd = ();
  $bd[0] = pack "H2", "02";    # stx
  $bd[1] = 'K';                # record format (1a)
  my $sendapptype = "1";
  if ( $transflags =~ /level3/ ) {
    $sendapptype = "5";
  }
  $bd[2] = $sendapptype;       # application type 0 = single, 4 = multiple interleaved(1a)
  $bd[3] = '.';                # message delimiter (1a)
  $bd[4] = 'Z';                # X.25 Routing ID (1a)

  if ( ( $cardlevelresults ne "" ) || ( ( $card_type eq "vi" ) && ( $transflags =~ /(recur|install|bill|debt)/ ) && ( $transflags !~ /init/ ) ) ) {
    if ( $commcardtype ne "" ) {
      $bd1 = 'DX';
    } else {
      $bd1 = 'DP';             # `
    }
  } else {
    if ( $commcardtype ne "" ) {
      $bd1 = 'DH';
    } else {
      $bd1 = 'D@';
    }
  }

  $ucafind = substr( $auth_code, 122, 1 );
  $ucafind =~ s/ //g;
  if ( $ucafind ne "" ) {
    $bd2 = "P";    # ucaf collection indicator
  } elsif ( ( $card_type eq "vi" ) && ( $transflags =~ /debt/ ) ) {
    $bd2 = "H";    # existing debt indicator
  } else {
    $bd2 = "@";
  }

  if ( ( $industrycode eq "restaurant" ) && ( $transflags =~ /moto/ ) ) {
    $bd3 = '`D';    # `
  } elsif ( $industrycode eq "restaurant" ) {
    $bd3 = '@B';
  } elsif ( $industrycode =~ /^(retail|grocery)$/ ) {
    $bd3 = '@@';
  } else {
    $bd3 = '`D';    # `
  }
  $bd[5] = $bd1 . $bd2 . $bd3;    # record type (5a)

  if ( $operation eq "return" ) {
    $tcode = 'CR';
  } elsif ( $transflags =~ /(bill|debt)/ ) {
    $tcode = '5B';
  } elsif ( ( $industrycode eq "restaurant" ) && ( $transflags =~ /moto/ ) ) {
    $tcode = '56';
  }

  #elsif (($industrycode =~ /^(retail|restaurant|grocery)$/) && ($transflags =~ /(bill|debt|recur|install|recinitial)/)) {
  #  $tcode = '5B';
  #}
  elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $operation eq "postauth" ) ) {
    $tcode = '54';
  } elsif ( $operation eq "postauth" ) {
    $tcode = '56';
  }
  $bd[6] = $tcode;    # transaction code (2a)

  my $magstripetrack = substr( $auth_code, 244, 1 );
  $magstripetrack =~ s/ //g;
  if ( $cardholderidcode ne "" ) {
    $bd[7] = "$cardholderidcode";    # cardholder id code (1a)
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $transflags =~ /(recur|install)/ ) && ( $transflags !~ /init/ ) ) {
    $bd[7] = 'N';
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $magstripetrack !~ /(1|2)/ ) ) {
    $bd[7] = 'M';
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $transflags !~ /moto/ ) ) {
    $bd[7] = '@';                    # cardholder id code (1a)
  } elsif ( ( $origoperation eq "forceauth" ) || ( $operation eq "return" ) ) {
    $bd[7] = 'N';                    # cardholder id code (1a)
  } else {
    $bd[7] = 'N';                    # cardholder id code (1a)
  }

  if ( $acctdatasrc ne "" ) {
    $bd[8] = $acctdatasrc;           # account data source (1a)
  } elsif ( ( $origoperation eq "forceauth" ) && ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) ) {
    $bd[8] = 'T';                    # account data source (1a)
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $magstripetrack eq "1" ) ) {
    $bd[8] = 'H';                    # acct data source (1a) H - track 1
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $magstripetrack eq "2" ) ) {
    $bd[8] = 'D';                    # acct data source (1a) D - track 2
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $track eq "2" ) ) {
    $bd[8] = 'T';                    # account data source (1a)
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $track eq "1" ) ) {
    $bd[8] = 'X';                    # account data source (1a)
  } else {
    $bd[8] = '@';                    # account data source (1a)
  }

  $cardnumber = substr( $cardnumber . " " x 22, 0, 22 );
  $bd[9] = $cardnumber;              # cardholder acct num (22a)

  if ( $operation eq "return" ) {
    $bd[10] = 'Y';                   # requested ACI (1a)
  } elsif ( ( $requestedaci ne "" ) && ( $requestedaci ne " " ) ) {
    $bd[10] = $requestedaci;         # requested ACI (1a)
  } elsif ( ( $card_type eq "vi" ) && ( $transflags =~ /(bill|init)/ ) ) {
    $bd[10] = 'Y';                   # requested ACI (1a)
  } elsif ( ( $transflags =~ /(install|recur)/ ) && ( $transflags !~ /init/ ) ) {
    $bd[10] = 'R';                   # requested ACI (1a)
  } else {
    $bd[10] = 'Y';                   # requested ACI (1a)
  }
  $bd[11] = $aci;                    # returned ACI (1a)
  $bd[12] = $auth_src;               # authorization source code (1a)
  $bd[13] = $transseqnum;            # trans seq num (4n)
  $bd[14] = $resp_code;              # response code (2a)
  $bd[15] = $authcode;               # authorization code (6a)
  $bd[16] = $trandate;               # local trans date MMDD (4n)
  $bd[17] = $trantime;               # local trans time HHMMSS (6n)
  $avs_code = substr( $avs_code . "0", 0, 1 );
  $bd[18] = $avs_code;               # avs result code (1a)
  $bd[19] = $trans_id;               # trans id (15a)
  $bd[20] = $val_code;               # validation code (4a)
  $bd[21] = ' ';                     # void indicator (1a)

  if ( ( $reauthflag == 1 ) && ( $card_type eq "vi" ) ) {
    $bd[22] = '10';                  # transaction status code (2n)
  } else {
    $bd[22] = '00';                  # transaction status code (2n)
  }
  $bd[23] = '0';                     # reimbursement attr (1a)
  $amt = substr( "0" x 12 . $transamt, -12, 12 );
  $bd[24] = $amt;                    # settlement amount (12n)
  if ( $industrycode eq "restaurant" ) {
    $authamt = $restorigamount;
  } elsif ( $origamount ne "" ) {
    $authamt = substr( $origamount, 4 );
    $authamt = sprintf( "%d", ( $authamt * 100 ) + .0001 );
    $authamt = substr( "0" x 12 . $authamt, -12, 12 );
  } else {
    $authamt = $amt;
  }

  #if (($origoperation eq "forceauth") || ($operation eq "return")) {}
  if ( $operation eq "return" ) {
    $bd[25] = "0" x 12;    # authorized amount (12n)
  } else {
    $bd[25] = $authamt;    # authorized amount (12n)
  }

  my @group = ();

  # group 1 for retail, grocery cashback
  $cashback = substr( $auth_code,           245, 8 );
  $cashback = substr( "0" x 12 . $cashback, -12, 12 );
  if ( ( $industrycode =~ /^(retail|grocery)$/ ) && ( $card_type eq "ds" ) && ( $cashback > 0 ) ) {
    $cashbacktotal = $cashbacktotal + $cashback;
    $group[1] = $cashback;    # group 1 - cashback (12n)
  }
  my $printstr = "cashback: $cashback\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  # group 2 for restaurant
  if ( ( $industrycode eq "restaurant" ) && ( $operation eq "postauth" ) ) {
    $group[2] = $gratuity;    # group 2 - gratuity (12n)
  }

  #if ((($card_type eq "vi") && ($transflags =~ /bill|debt/)) || ($industrycode !~ /^(retail|grocery|restaurant)$/)) {}

  if (
    (    ( $industrycode =~ /^(retail|restaurant|grocery)$/ )
      && ( $transflags =~ /moto|recur|install|bill|debt/ )
      && ( $transflags !~ /init/ )
      && ( $transflags !~ /avsonly/ )
      && ( $magstripetrack !~ /(0|1|2)/ )
    )
    || ( ( $industrycode !~ /^(retail|restaurant|grocery)$/ ) && ( $transflags !~ /avsonly/ ) )
    ) {

    if ( ( $origoperation eq "forceauth" ) || ( $operation eq "return" ) ) {
      $group3amt = "0" x 12;    # group 3 - total auth amount (12n)
    } else {
      $group3amt = $authamt;    # group 3 - total auth amount (12n)
    }

    if ( $ponumber ne "" ) {
      $purchaseid = substr( $ponumber, -17, 17 );
      $purchaseid = substr( $purchaseid . " " x 25, 0, 25 );
    } else {
      $purchaseid = substr( $orderid, -17, 17 );
      $purchaseid = substr( $purchaseid . " " x 25, 0, 25 );
    }

    # group 3 for moto/ecom
    if ( $transflags !~ /level3/ ) {
      $group[3] = $group3amt . '1' . $purchaseid;    # group 3 - purchase id (25a)
    }

    # group 11 lane number
    $deviceid = substr( $auth_code, 151, 8 );
    $deviceid =~ s/ //g;
    if ( ( $deviceid ne "" ) && ( $deviceid ne "00000000" ) ) {
      $deviceid = substr( "0" x 4 . $deviceid, -4, 4 );
      $group[11] = $deviceid;                        # group 11 - lane number (4a)
    }

    # group 12
    $eci = substr( $auth_code, 121, 1 );
    $eci =~ s/ //g;
    if ( $transflags =~ /(install)/ ) {
      $installinfo = substr( $auth_code, 117, 4 );
      $installinfo =~ s/ //g;
      $installinfo = substr( "0" x 4 . $installinfo, -4, 4 );
      $group[12] = $installinfo . '3';               # group 12 - 7 = ecom, 2 = recurring (5a)
    } elsif ( ( $transflags =~ /(recur)/ ) && ( $transflags !~ /init/ ) ) {
      $group[12] = '00002';                          # group 12 - 7 = ecom, 2 = recurring (5a)
    } elsif ( $transflags =~ /(moto)/ ) {
      $group[12] = '00001';                          # group 12 - 7 = ecom, 2 = recurring (5a)
    } elsif ( $industrycode eq "retail" ) {
      $group[12] = '0000 ';                          # group 12 - 7 = ecom, 2 = recurring (5a)
    } elsif ( $eci ne "" ) {
      $group[12] = '0000' . $eci;                    # group 12 - 7 = ecom, 2 = recurring (5a)
    } else {
      $group[12] = '00007';                          # group 12 - 7 = ecom, 2 = recurring (5a)
    }
  }

  if ( ( $card_type eq "vi" ) && ( $transflags =~ /debt/ ) ) {
    $group[16] = '9';                                # group 16 - existing debt indicator
  }

  $ucafind = substr( $auth_code, 122, 1 );
  $ucafind =~ s/ //g;
  if ( ( $card_type eq "mc" ) && ( $ucafind ne "" ) ) {
    $group[17] = $ucafind;                           # group 17 - ucaf collection indicator
  }

  if ( ( $transflags =~ /hsa/ ) && ( $mvv ne "" ) ) {
    $mvv = substr( "0" x 10 . $mvv, -10, 10 );
    $group[20] = $mvv;                               # group 20 - hsa merchant verification value mvv visa
  }

  # group 21 or 22
  if ( ( $commcardtype ne "" ) && ( $transflags !~ /level3/ ) ) {
    if ( ( $capabilities =~ /ax/ ) && ( $card_type eq "ax" ) ) {    # ax purchase card data only sent if merch is setup at Tsys for it and it's required by ax
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() );
      my $juliantime = sprintf( "%03d%02d%02d%02d", $yday, $hour, $min, $sec );
      $newauthcode = substr( $auth_code . " " x 133, 0, 133 ) . $juliantime . substr( $auth_code, 142 );
      my $newauthcode = substr( $auth_code, 0, 133 ) . $juliantime . substr( $auth_code, 142 );

      my $dbquerystr = <<"dbEOM";
              update trans_log set auth_code=?
	      where orderid=?
	      and username=?
	      and trans_date>=?
	      and finalstatus='locked'
              and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$newauthcode", "$orderid", "$username", "$onemonthsago" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      my $dbquerystr = <<"dbEOM";
            update operation_log set auth_code=?
            where orderid=?
            and username=?
            and lastopstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$newauthcode", "$orderid", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      if ( $ponumber ne "" ) {
        $purchaseid = substr( $ponumber . " " x 17, 0, 17 );
      } else {
        $purchaseid = substr( $orderid, -17, 17 );
        $purchaseid = substr( $purchaseid . " " x 17, 0, 17 );
      }
      my $suppliernum = $juliantime;
      my $shipzip = substr( $auth_code, 123, 10 );
      $shipzip =~ s/ //g;
      if ( length($shipzip) == 9 ) {
        $shipzip = substr( $shipzip, 0, 5 );
      }
      $shipzip = substr( $shipzip . " " x 6, 0, 6 );
      my $tax = substr( $tax, -6, 6 );
      my $chargedescriptor = "purchase";
      $chargedescriptor =~ tr/a-z/A-Z/;
      $chargedescriptor = substr( $chargedescriptor . " " x 40, 0, 40 );
      $group[21] = $suppliernum . $purchaseid . $shipzip . $tax . $chargedescriptor;
    } elsif ( (0) && ( $card_type eq "vi" ) ) {
      if ( $tax > 0 ) {
        $optamtid = '1';     # optional amount identifier (1a)
        $optamt   = $tax;    # optional amount (12n)
      } elsif ( ( $transflags =~ /exempt/ ) && ( $transflags !~ /notexempt/ ) ) {
        $optamtid = '2';         # optional amount identifier (1a)
        $optamt   = '0' x 12;    # optional amount (12n)
      } else {
        $optamtid = '0';         # optional amount identifier (1a)
        $optamt   = '0' x 12;    # optional amount (12n)
      }

      #$purchaseid = substr($orderid . " " x 17,0,17);
      if ( $ponumber ne "" ) {
        $purchaseid = substr( $ponumber . " " x 17, 0, 17 );
      } else {
        $purchaseid = substr( $orderid, -17, 17 );
        $purchaseid = substr( $purchaseid . " " x 17, 0, 17 );
      }
      $group[22] = $optamtid . $optamt . $purchaseid;    # purchase order number (17a)
    }
  }
  my $printstr = "group 22: $group[22]\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  if ( $transflags =~ /level3/ ) {
    my $printstr = "select from orderdetails where orderid=$orderid  $username\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

    @level3details = ();
    $itemcnt       = 0;
    $chkamounts    = 0;

    my $dbquerystr = <<"dbEOM";
          select shipzip,shipcountry
          from ordersummary
          where orderid=? 
          and username=?
dbEOM
    my @dbvalues = ( "$orderid", "$username" );
    ( $destzip, $destcountry ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $printstr = "destcountry: $destcountry\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

    my $dbquerystr = <<"dbEOM";
          select item,quantity,cost,description,unit,customa,customb,customc,customd
          from orderdetails
          where orderid=? 
          and username=?
dbEOM
    my @dbvalues = ( "$orderid", "$username" );
    my @sthdetailsvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    for ( my $vali = 0 ; $vali < scalar(@sthdetailsvalarray) ; $vali = $vali + 9 ) {
      ( $item, $quantity, $cost, $descr, $unit, $customa, $customb, $customc, $customd ) = @sthdetailsvalarray[ $vali .. $vali + 8 ];

      my $printstr = "aaaa $item  $quantity  $cost  $descr  $unit  $customb\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
      $itemcnt++;

      my $addtldata = "";

      #my ($str, $format, $len, $filter, $mult) = @_;
      #$item =~ s/[^a-zA-Z0-9 \-]//g;	# 3/29/2016
      #$item =~ tr/a-z/A-Z/;
      #$item = substr($item . " " x 12,0,12);
      #$descr =~ s/[^a-zA-Z0-9 \-\/]//g;
      #$descr =~ tr/a-z/A-Z/;
      #$descr =~ s/^ +//;
      #$descr = substr($descr . " " x 35,0,35);

      $item  = &formatstr( $item,  "leftspacecaps", "12", '[^a-zA-Z0-9 \-]',   "" );
      $descr = &formatstr( $descr, "leftspacecaps", "35", '[^a-zA-Z0-9 \-\/]', "" );
      $quantity = sprintf( "%d", ( $quantity * 10000 ) + .0001 );
      $quantity = substr( "0" x 12 . $quantity, -12, 12 );
      $unit     = substr( $unit . " " x 12,     0,   12 );
      if ( $operation eq "return" ) {
        $debitind = "C";
      } else {
        $debitind = "D";
      }
      if ( $cost < 0.0 ) {
        $cost = 0.00 - $cost;
        if ( $operation eq "return" ) {
          $debitind = "D";
        } else {
          $debitind = "C";
        }
      }
      $netind   = "N";
      $unitcost = sprintf( "%d", ( $cost * 10000 ) + .0001 );
      $unitcost = substr( "0" x 12 . $unitcost, -12, 12 );

      $discountamt = 0;
      if ( $customa ne "" ) {
        $discountamt = $customa;
        $discountamt = sprintf( "%d", ( $discountamt * 100 ) + .0001 );
      }

      #$taxamt = 0;
      #if ($customb ne "") {
      #  $taxamt = $customb;
      #  $taxamt = sprintf("%d", ($taxamt*100)+.0001);
      #}

      $extcost = ( $unitcost * $quantity / 1000000 ) - $discountamt;
      $extcost = sprintf( "%d", $extcost + .0001 );

      $extcost = substr( "0" x 12 . $extcost, -12, 12 );

      #if ($customd ne "") {
      #  $extcost = sprintf("%d", ($customd*100)+.0001);
      #  $extcost = substr("0" x 13 . $extcost,-13,13);
      #}

      $chkamounts = $chkamounts + $extcost;

      $discountamt = $customa;

      #if ($discountamt ne "") {
      $discountamt = sprintf( "%d", ( $discountamt * 100 ) + .0001 );
      $discountamt = substr( "0" x 12 . $discountamt, -12, 12 );

      #}

      $taxamt = $customb;
      if ( $taxamt < 0 ) {
        $taxamt = 0 - $taxamt;
      }
      $taxamt = sprintf( "%d", ( $taxamt * 100 ) + .0001 );
      $taxamt = substr( "0" x 12 . $taxamt, -12, 12 );

      if ( $extcost == 0 ) {
        $taxrate = "0";
      } else {
        $taxrate = $taxamt / $extcost;
        $taxrate = sprintf( "%d", ( $taxrate * 10000 ) + .0001 );
      }
      $taxrate = substr( "0" x 4 . $taxrate, -4, 4 );

      $commoditycode = $customc;
      if ( $commoditycode ne "" ) {
        $commoditycode =~ s/[^a-zA-Z0-9 ]//g;
        $commoditycode =~ tr/a-z/A-Z/;
        $commoditycode = substr( $commoditycode . " " x 12, 0, 12 );
      }

      $level3data = "";
      if ( $card_type eq "vi" ) {
        $level3data = "\x02K5.ZL\@\@\@\@VISA$commoditycode$descr$item$quantity$unit$unitcost$taxamt$taxrate$discountamt$extcost\x17";
      } else {

        # alttaxid = merchant tax number from visanet table
        $alttaxid = "1" x 15;
        $taxtype  = "    ";     # the type of taxes that are applied
        my $netgrossind  = "N";                       # N - item amount does not include tax  Y - item amount does include tax
        my $discountrate = $discountamt / $extcost;
        $discountrate = sprintf( "%d", ( $discountrate * 100 ) + .0001 );
        $discountrate = substr( "0" x 5 . $discountrate, -5, 5 );
        my $discountind = "N";
        if ( $discountamt > 0 ) {
          $discountind = "Y";
        }

        #$quantity = "00" . substr($quantity,0,length($quantity)-2);	# only need to do this if quantity exponent is 2
        $extcost = substr( $extcost, -9, 9 );
        my $printstr = "discountind: $discountind\n";
        $printstr .= "netgrossind: $netgrossind\n";
        $printstr .= "extcost: $extcost\n";
        &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

        my $quantityexp = "4";
        my $discountexp = "2";
        $level3data = "\x02K5.ZL\@\@\@\@MCRD$descr$item$quantity$unit$alttaxid$taxrate$taxtype$taxamt$discountind$netgrossind$extcost$debitind$discountamt$discountrate$quantityexp$discountexp\x17";
      }

      push( @level3details, $level3data );
    }

    # group 25
    # group 26 visa
    # group 27 mastercard

    $localamtid = '0';         # local amount identifier (1a)
    $localamt   = '0' x 12;    # local amount (12n)
                               #if ($tax > 0) {
                               #  $localamtid = '1';          	# local amount identifier (1a)
                               #  $localamt = $tax;               	# local amount (12n)
                               #}
                               #elsif (($transflags =~ /exempt/) && ($transflags !~ /notexempt/)) {
                               #  $localamtid = '2';            	# local amount identifier (1a)
                               #}

    $natlamtid = '0';          # natl amount identifier (1a)
    $natlamt   = '0' x 12;     # natl amount (12n)
    if ( $tax > 0 ) {
      $natlamtid = '1';        # natl amount identifier (1a)
      $natlamt   = $tax;       # natl amount (12n)
    } elsif ( ( $transflags =~ /exempt/ ) && ( $transflags !~ /notexempt/ ) ) {
      $natlamtid = '2';        # natl amount identifier (1a)
    }

    if ( ( $origoperation eq "forceauth" ) || ( $operation eq "return" ) ) {
      $totalauthamt = "0" x 12;    # group 3 - total auth amount (12n)
    } else {
      $totalauthamt = $authamt;    # group 3 - total auth amount (12n)
    }

    $purchaseidformat = " ";       # purchase id format code space - reserved, 1 - direct marketing ordernum
    if ( $ponumber ne "" ) {
      $purchaseid = substr( $ponumber, -17, 17 );
    } else {
      $purchaseid = substr( $orderid, -17, 17 );
    }
    $purchaseid   = substr( $purchaseid . " " x 17, 0, 17 );
    $cardholderid = substr( $purchaseid . " " x 25, 0, 25 );
    $group[25]    = "$totalauthamt$purchaseidformat$cardholderid$localamtid$localamt$natlamtid$natlamt$purchaseid";

    my $suppliernum = $juliantime;

    $vattax         = "0" x 12;    # national tax (vat tax) (12a)
    $merchvatregnum = " " x 20;    # merchant vat registration number (20a)
    $custvatregnum  = " " x 13;    # customer vat registration number (13a)
    $summarycommod  = "    ";      # summary commodity code (4a)

    $discount = substr( $auth_code,           221, 7 );
    $discount = substr( "0" x 12 . $discount, -12, 12 );
    $duty     = substr( $auth_code,           228, 7 );
    $duty     = substr( "0" x 12 . $duty,     -12, 12 );
    $freight  = substr( $auth_code,           235, 7 );
    $freight  = substr( "0" x 12 . $freight,  -12, 12 );

    my $shipzip     = substr( $auth_code,      123, 10 );
    my $shipfromzip = substr( $zip . " " x 10, 0,   10 );
    $destcountry =~ tr/a-z/A-Z/;
    $destcountry = $isotables::countryUS840{"$destcountry"};
    $destcountry = substr( $destcountry . " " x 3, 0, 3 );

    $vatinvnum = $purchaseid;
    $vatinvnum =~ s/ //g;
    $vatinvnum = substr( $vatinvnum . " " x 15, 0, 15 );

    $orderdate = substr( $l3trandate . " " x 6, 0, 6 );    # order date YYMMDD (6a)
    $vattaxamt = "0" x 12;                                 # vat tax on freight/shipping (12a)

    if ( ( $freight + $shipping ) == 0 ) {
      $vattaxrate = "0";
    } else {
      $vattaxrate = $vattaxamt / ( $freight + $shipping );    # vat tax rate on freight/shipping (4a)
      $vattaxrate = sprintf( "%d", ( $vattaxrate * 100 ) + .0001 );
    }
    $vattaxrate = substr( "0" x 4 . $vattaxrate, -4, 4 );

    $itemcnt = substr( "0" x 3 . $itemcnt, -3, 3 );

    if ( $card_type eq "vi" ) {
      $group[26] = "$merchvatregnum$custvatregnum$summarycommod$discount$freight$duty$shipzip$shipfromzip$destcountry$vatinvnum$orderdate$vattaxamt$vattaxrate$itemcnt";
    } elsif ( $card_type eq "mc" ) {
      $alttaxamtind = "N";                                                                              # alternate tax amount indicator (1a) Y or N
      $alttaxamt    = "0" x 9;                                                                          # alternate amount (9a)
      $group[27]    = "$freight$duty$shipzip$shipfromzip$destcountry$alttaxamtind$alttaxamt$itemcnt";
    }

  }

  $posentry = substr( $auth_code,           159, 12 );
  $posentry = substr( $posentry . " " x 12, 0,   12 );
  if ( $posentry ne "            " ) {
    $group[32] = $posentry;
  }

  $cardlevelresults = substr( $auth_code, 115, 2 );
  $cardlevelresults =~ s/ //g;

  #if (($cardlevelresults ne "") || ($transflags =~ /hsa/) || (($card_type =~ /(vi|mc|ax|ds)/) && ($transflags =~ /recinitial|recur|install|bill|debt/))) {}
  if ( ( $cardlevelresults ne "" ) || ( $transflags =~ /hsa/ ) || ( ( $card_type =~ /(vi|mc|ax|ds)/ ) && ( $transflags =~ /(bill|debt)/ ) ) ) {

    # group 23 group map extension
    #my $bd1 = '@';
    #my $bd2 = '@';

    # group 31
    #if (($card_type =~ /^(vi|mc|ax|ds)$/) && ($transflags =~ /(recinitial|recur|install|bill|debt)/)) {
    if ( ( $card_type =~ /^(vi|mc|ax|ds)$/ ) && ( $transflags =~ /(bill|debt)/ ) ) {

      #$bd1 = 'A';
      $group[31] = 'B';    # bill payment indicator market specific data indicator
    } elsif ( ( $card_type =~ /^(vi|mc)$/ ) && ( $transflags =~ /hsa/ ) ) {
      $group[31] = 'M';    # bill payment indicator
    }
  }

  my $marketdata = substr( $auth_code, 174, 38 );
  if ( ( length($marketdata) == 38 ) && ( $marketdata ne "" ) && ( $marketdata ne ( " " x 38 ) ) ) {
    my $name = substr( $marketdata, 0, 25 );
    $name =~ tr/a-z/A-Z/;
    $name = substr( $name . " " x 38, 0, 38 );

    my $marketaddr = " " x 38;

    my $phonecity = substr( $marketdata, 25, 13 );
    $phonecity =~ s/^ +//g;
    $phonecity =~ tr/a-z/A-Z/;
    $phonecity = substr( $phonecity . " " x 21, 0, 21 );

    #$phonecity = substr($phonecity . " " x 3,0,3) .  "-" . substr($phonecity . " " x 17,3,17);

    my $marketzip = $zip;
    $marketzip =~ tr/a-z/A-Z/;
    $marketzip = substr( $marketzip . " " x 15, 0, 15 );

    $group[36] = $name . $marketaddr . $phonecity . "   " . "   " . $marketzip;
  } elsif ( ( $card_type =~ /(vi|mc|ds)/ ) && ( $payfacid ne "" ) ) {
    my $subname = substr( $payfacname, 0, 3 ) . '*' . substr( $company, 0, 18 );
    $subname = substr( $subname . " " x 38, 0, 38 );
    $subname =~ tr/a-z/A-Z/;

    my $subaddr = " " x 38;
    my $subcity = substr( $city . " " x 21, 0, 21 );
    $subcity =~ tr/a-z/A-Z/;

    my $substate = substr( $state . "   ", 0, 3 );
    $substate =~ tr/a-z/A-Z/;

    if ( $country eq "" ) {
      $country = "US";
    }
    if ( $country !~ /(US|CA)/ ) {
      $substate = "   ";
    }

    my $subcountry = $isotables::countryUS840{$country};
    my $subzip = substr( $zip . " " x 15, 0, 15 );
    $subzip =~ tr/a-z/A-Z/;

    $group[36] = $subname . $subaddr . $subcity . $substate . $subcountry . $subzip;
  }

  # group 38
  # visa
  if ( $cardlevelresults ne "" ) {

    #$bd2 = 'B';
    $cardlevelresults = substr( $auth_code, 115, 2 );
    $cardlevelresults = substr( $cardlevelresults . " " x 2, 0, 2 );
    $group[38] = '001' . $cardlevelresults;    # card level results
  }

  #$bd[34] = '@' . $bd2 . $bd1 . '@';		# group 23     group extension map groups 25 - 48

  #elsif ($card_type eq "mc") {
  #  # group 37 mastercard misc
  #  $group[37] = '001' . $xxxx;
  #}

  if ( ( $commcardtype ne "" ) && ( $capabilities =~ /ax/ ) && ( $card_type eq "ax" ) ) {    # ax purchase card data only sent if merch is setup at Tsys for it and it's required by ax
                                                                                             # group 39 ax capn corporate purchase cards
                                                                                             # ax purchase card data only sent if merch is setup at Tsys for it and it's required by ax
    my $requester   = " " x 38;                                                              # requester name  38a 4.223
    my $totaltax    = substr( "0" x 12 . $tax, -12, 12 );                                    # 12n 4.276
    my $taxtypecode = "056";                                                                 # 3n 4.262
    $group[39] = $requester . $totaltax . $taxtypecode;
  }

  if ( $card_type eq "ds" ) {

    # group 40 discover misc
    if ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $transflags !~ /moto/ ) ) {
      $posdevattend    = "0";
      $poscardpres     = "0";
      $poscardinputcap = "7";
    } else {
      $posdevattend    = "1";
      $poscardpres     = "1";
      $poscardinputcap = "U";
    }

    if ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $transflags !~ /moto/ ) ) {
      $posdevloc         = "0";
      $poscardholderpres = "0";
    } elsif ( $origoperation eq "forceauth" ) {
      $posdevloc         = "3";
      $poscardholderpres = "1";
    } elsif ( ( $transflags =~ /recur/ ) && ( $transflags !~ /init/ ) ) {
      $posdevloc         = "2";
      $poscardholderpres = "4";
    } elsif ( $transflags =~ /moto/ ) {
      $posdevloc         = "2";
      $poscardholderpres = "3";
    } else {
      $posdevloc         = "2";
      $poscardholderpres = "5";
    }
    if ( $transflags =~ /partial/ ) {
      $partial = "1";
    } else {
      $partial = "0";
    }
    $poscardcap = "1";
    if ( $origoperation eq "forceauth" ) {
      $postransstatus = "0";
    } else {
      $postransstatus = "0";
    }
    $postranssecurity = "9";
    $partshipind      = "N";

    $group[40] = '001' . $posdevattend . $partial . $posdevloc . $poscardholderpres . $poscardpres . $poscardcap . $postransstatus . $postranssecurity . '00' . $poscardinputcap . '00' . $partshipind;
    my $printstr = "group40: $group[40]\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  }

  my $tags = "";

  $cavv = substr( $auth_code, 253, 40 );
  $cavv =~ s/ //g;
  $cavv =~ tr/a-z/A-Z/;
  if ( ( $card_type eq "mc" ) && ( $cavv ne "" ) ) {
    my $cavvlen = length($cavv);
    $cavvlen = substr( "00" . $cavvlen, -2, 2 );
    $tags .= "AAV$cavvlen$cavv";
  }

  $xid = substr( $auth_code, 293, 40 );    # mc directory server transaction id
  $xid =~ s/ //g;
  $xid =~ tr/a-z/A-Z/;
  if ( ( $card_type eq "mc" ) && ( $xid ne "" ) && ( $transflags =~ /3d2/ ) ) {
    my $xidlen = length($xid);
    $xidlen = substr( "00" . $xidlen, -2, 2 );
    $tags .= "DTI$xidlen$xid";
  }

  my $mcseclevel = substr( $auth_code, 218, 3 );    # ucaf ind is third char
  $mcseclevel =~ s/[^0-9]//g;
  if ( length($mcseclevel) == 3 ) {
    $tags .= "ESI03$mcseclevel";
  }

  if ( ( $card_type eq "mc" ) && ( $cavv ne "" ) ) {
    my $protocol = "1";
    if ( $transflags =~ /3d2/ ) {
      $protocol = "2";
    }
    $tags .= "PGP01$protocol";
  }

  $iiasind = substr( $auth_code, 150, 1 );
  $iiasind =~ s/ //g;
  if ( ( $card_type eq "mc" ) && ( $iiasind ne "" ) ) {
    $tags .= "IIA01$iiasind";
  }
  $surcharge = substr( $auth_code, 142, 8 );
  $surcharge =~ s/ //g;
  if ( ( $operation ne "return" ) && ( $surcharge > 0 ) ) {
    $surcharge = "D" . substr( "0" x 8 . $surcharge, -8, 8 );
    $tags .= "TFA09$surcharge";
  }

  if ( ( $commcardtype ne "" ) && ( $transflags !~ /level3/ ) ) {
    if ( $card_type =~ /(vi|mc)/ ) {
      if ( $ponumber ne "" ) {
        $purchaseid = substr( $ponumber . " " x 25, 0, 25 );
      } else {
        $purchaseid = substr( $orderid, -25, 25 );
        $purchaseid = substr( $purchaseid . " " x 25, 0, 25 );
      }
      if ( $card_type eq "vi" ) {
        $purchaseid = substr( $purchaseid, -17, 17 );
      }
      my $purchaseidlen = length($purchaseid);
      $purchaseidlen = substr( "00" . $purchaseidlen, -2, 2 );
      if ( $tax > 0 ) {
        $optamtid = '1';     # optional amount identifier (1a)
        $optamt   = $tax;    # optional amount (12n)
      } elsif ( ( $transflags =~ /exempt/ ) && ( $transflags !~ /notexempt/ ) ) {
        $optamtid = '2';         # optional amount identifier (1a)
        $optamt   = '0' x 12;    # optional amount (12n)
      } else {
        $optamtid = '0';         # optional amount identifier (1a)
        $optamt   = '0' x 12;    # optional amount (12n)
      }
      $tags .= "OAI01$optamtid" . "OA 12$optamt" . "PON$purchaseidlen$purchaseid";

      #$group[41] = "0057" . "OAI01$optamtid" . "OA 12$optamt" . "PON25$purchaseid";
    }
  }

  my $devtype = substr( $auth_code, 171, 2 );
  $devtype =~ s/ //g;
  if ( ( $card_type eq "mc" ) && ( $transflags =~ /ctls/ ) ) {
    $devtype = substr( "00" . $devtype, -2, 2 );
    $tags .= "MDE02$devtype";    # device type

    $tags .= "MDO010";           # domain server no domain
  }

  if ( ( $card_type eq "vi" ) && ( $transflags =~ /(init|recur|install)/ ) ) {
    my $posenv = "C";            # credentials
    if ( $transflags =~ /(init)/ ) {
      $posenv = "C";
    } elsif ( $transflags =~ /(recur)/ ) {
      $posenv = "R";
    } elsif ( $transflags =~ /install/ ) {
      $posenv = "I";
    }
    $tags .= "PEI01$posenv";
  }

  if ( ( $card_type =~ /(vi|mc)/ ) && ( $payfacid ne "" ) ) {
    $payfacid = substr( "0" x 11 . $payfacid, -11, 11 );
    my $submid = substr( "0" x 15 . $merchant_id, -15, 15 );

    $tags .= "PFI11$payfacid";
    $tags .= "SMI15$submid";
  }

  if ( $card_type eq "vi" ) {
    my $sqi = substr( $auth_code, 173, 1 );
    $sqi = substr( $sqi . " ", 0, 1 );
    $tags .= "SQI01$sqi";
  }

  my $tokenlev = substr( $auth_code, 212, 2 );
  $tokenlev   = substr( $tokenlev . "  ",   0, 2 );
  $tokenreqid = substr( $tokenreqid . "  ", 0, 11 );
  if ( $tokenlev ne "  " ) {
    $tags .= "TAL02$tokenlev";
    $tags .= "TRI11$tokenreqid";
  }

  $tic = substr( $auth_code, 242, 2 );
  if ( ( $card_type eq "mc" ) && ( $tic ne "  " ) && ( $tic ne "" ) ) {
    $tags .= "TIC02$tic";
  }

  if ( $tags ne "" ) {
    my $taglen = length($tags) + 4;
    $taglen = substr( "0000" . $taglen, -4, 4 );
    $group[41] = $taglen . $tags;
  }

  if ( $transflags =~ /token/ ) {
    $group[45] = "T";    # transaction security indicator
  }

  my $printstr = "origbd5: $bd[5]\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  ( $mainbitmap, $group[23] ) = &gengroupbitmap(@group);
  $bd[5] = 'D' . $mainbitmap;
  my $printstr = "newbd5: $bd[5]\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  $recseqnum = substr( "0000" . $recseqnum, -4, 4 );
  $errorderid{$recseqnum} = $orderid;

  $message = "";
  foreach $var (@bd) {
    $message = $message . $var;
  }
  foreach $var (@group) {
    $message = $message . $var;
  }
  $etb = pack "H2", "17";       # etb
  $message = $message . $etb;

  &sendrecord($message);

  if ( $usevnetsslflag == 0 ) {
    if ( $response =~ /\x02.+RB/ ) {
      &sslsend();
      $errorflag = 1;
    } elsif ( ( length($response) != 1 ) || ( $response !~ /^(\x05|\x06|\x07)$/ ) ) {
      &error("detail");
    }
  }

  foreach $message (@level3details) {

    #$batchcnt++;
    $batchreccnt++;
    $recseqnum++;

    $recseqnum = substr( "0000" . $recseqnum, -4, 4 );
    $errorderid{$recseqnum} = $orderid;

    #$etb = pack "H2", "17";        	# etb
    #$message = $message . $etb;

    &sendrecord($message);

    if ( $usevnetsslflag == 0 ) {
      if ( $response =~ /\x02.+RB/ ) {
        &sslsend();
        $errorflag = 1;
      } elsif ( ( length($response) != 1 ) || ( $response !~ /^(\x05|\x06|\x07)$/ ) ) {
        &error("detail");
      }
    }

  }
  @level3details = ();

}

sub formatstr {
  my ( $str, $format, $len, $filter, $mult ) = @_;

  if ( $filter ne "" ) {
    $str =~ s/$filter//g;
  }

  if ( $format =~ /caps/ ) {
    $str =~ tr/a-z/A-Z/;
  }

  $str =~ s/^ +//;
  $str =~ s/ +$//;

  if ( $mult ne "" ) {
    $str = sprintf( "%d", ( $str * $mult ) + .0001 );
  }

  if ( $format =~ /space/ ) {
    if ( $format =~ /right/ ) {
      $str = substr( " " x $len . $str, -$len, $len );
    } else {
      $str = substr( $str . " " x $len, 0, $len );
    }
  }
  if ( $format =~ /zero/ ) {
    if ( $format =~ /right/ ) {
      $str = substr( "0" x $len . $str, -$len, $len );
    } else {
      $str = substr( $str . "0" x $len, 0, $len );
    }
  }

  return $str;

}

sub batchtrailer {
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

  @bt = ();
  $bt[0] = pack "H2", "02";    # stx
  $bt[1] = 'K';                # record format (1a)
  my $sendapptype = "1";
  if ( $transflags =~ /level3/ ) {
    $sendapptype = "5";
  }
  $bt[2] = $sendapptype;       # application type 0 = single, 4 = multiple interleaved(1a)
  $bt[3] = '.';                # message delimiter (1a)
  $bt[4] = 'Z';                # X.25 Routing ID (1a)
  $bt[5] = 'T@@@@';            # record type (5a)
  $bdate = substr( $today, 4, 4 );
  $bt[6] = $bdate;             # batch trans date (4n)
  $batchnum = substr( "0" x 3 . $batchnum, -3, 3 );
  $bt[7] = $batchnum;          # batch number (3n)
  $recseqnum = substr( "0" x 9 . $recseqnum, -9, 9 );
  $bt[8] = $recseqnum;         # batch record count (9n)
  $hashtotal = sprintf( "%d", $hashtotal + .0001 );
  $hashtotal = substr( "0" x 16 . $hashtotal, -16, 16 );
  $bt[9] = $hashtotal;         # batch hashing total (16n)
  $cashbacktotal = substr( "0" x 16 . $cashbacktotal, -16, 16 );
  $bt[10] = $cashbacktotal;    # cashback total (16n)

  if ( $netamount < 0 ) {
    $netamount = 0 - $netamount;
  }
  $netamount = sprintf( "%d", $netamount + .0001 );
  $netamount = substr( "0" x 16 . $netamount, -16, 16 );
  $bt[11] = $netamount;         # batch net depost (16n)
  $bt[12] = pack "H2", "03";    # stx

  $message = "";
  foreach $var (@bt) {
    $message = $message . $var;
  }
  &sendrecord($message);
}

sub sendrecord {
  ($message) = @_;

  my $printstr = "\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  $rlen     = length($message);
  $message2 = $message;
  $cardnumber =~ s/ //g;
  $cnumlen = length($cardnumber);
  if ( ( $cnumlen >= 13 ) && ( $cnumlen <= 19 ) ) {
    $xs = "x" x $cnumlen;
    $message2 =~ s/$cardnumber/$xs/;
  }
  $message2 =~ s/\x1c/\[1c\]/g;
  $message2 =~ s/\x02/\[STX\]/g;
  $message2 =~ s/\x17/\[ETB\]/g;
  $message2 =~ s/\x03/\[ETX\]/g;
  my $mytime = gmtime( time() );
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$mytime send: $rlen $message2  $orderid\n";
  my $printstr = "send: $rlen $message2\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet",            "miscdebug.txt",          "append", "misc", $printstr );
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "",     $logfilestr );

  # do the parity thing
  $mess = "";
  $lrc  = "";
  $len  = length($message);
  for ( $i = 0 ; $i < $len ; $i++ ) {
    $byte = substr( $message, $i, 2 );
    $setbits = unpack( "%8b8", $byte );
    $byte = unpack "H2", $byte;
    $byte = hex($byte);

    $setbits    = ( $setbits % 2 ) * 128;
    $newmessage = $byte + $setbits;

    $mess2 = sprintf( "%02X", $newmessage );

    $mess = $mess . $mess2;

    if ( $i != 0 ) {
      $lbin = pack "H2", $mess2;
      $lrc  = $lbin ^ $lrc;
      $temp = unpack "H*", $lrc;

      #print "lrc: $temp\n";
    }
  }

  #print "$mess\n";
  $message = pack "H*", $mess;
  $message = $message . $lrc;

  $bigmessage = $bigmessage . $message;

  if ( $usevnetsslflag == 0 ) {
    my $printstr = "socketwrite\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
    &socketwrite($message);
  }

  return;
}

sub printrecord {
  my ($printmessage) = @_;

  my $temp     = length($printmessage);
  my $printstr = "$temp\n";

  ($message2) = unpack "H*", $printmessage;
  $printstr .= "$message2\n\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  $message1 = $printmessage;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;

  #print "$message1\n$message2\n\n";
}

sub sslsend {
  $message = $bigmessage;
  if ( $usevnetsslflag == 1 ) {
    &vnetsslsend();
  } else {

    my $printstr = "socketclose\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  }

  $index = index( $response, "\x02" );
  if ( $index > 0 ) {
    $extradata = substr( $response, 0, $index );
    $temp = unpack "H*", $extradata;
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "extra data: $temp\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  }
  $response = substr( $response, $index );

  $errorflag = 0;
  ( $d1, $recordformat, $apptype, $d2, $routingid, $recordtype, $batchreccnt, $batchnetdep, $respcode, $d3, $batchnum ) = unpack "H2A1A1A1A1A5A9A16A2A2A3", $response;

  $resp = substr( $response, 42 );

  #print "d1   $d1\n";
  #print "recordformat   $recordformat\n";
  #print "apptype   $apptype\n";
  #print "d2   $d2\n";
  #print "routingid   $routingid\n";
  #print "recordtype   $recordtype\n";
  #print "batchreccnt   $batchreccnt\n";
  #print "batchnetdep   $batchnetdep\n";
  my $printstr = "respcode   $respcode\n";
  $printstr .= "batchnum   $batchnum\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  if ( $respcode eq "GB" ) {
    ( $resptext, $d1 ) = unpack "A9A16", $resp;
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "resptext   $resptext\n";
    $logfilestr .= "d1   $d1\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "resptext   $resptext\n";
    $printstr .= "d1   $d1\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

    ( $d1, $ptoday, $ptime ) = &miscutils::genorderid();

    $mytime = gmtime( time() );
    my $printstr = "$mytime before update trans_log\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

    my $dbherrorflag = 0;
    my $dbquerystr   = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?
	    where trans_date>=?
            and trans_date<=?
	    and username=?
	    and result=?
	    and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$ptime", "$onemonthsago", "$today", "$username", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
    if ( $DBI::errstr =~ /lock.*try restarting/i ) {
      &miscutils::mysleep(60.0);
      my @dbvalues = ("$ptime");
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
    } elsif ( $dbherrorflag == 1 ) {
      &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    }

    $hint = "/*+ INDEX(OPLOG_OPTIMEUN_IDX) */";

    $usetransdate = $postauthtrans_date;

    $mytime = gmtime( time() );
    my $printstr = "$mytime after update trans_log\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
    $logfilestr = "";
    $logfilestr .= "$mytime after update trans_log\n";
    $logfilestr .= "using trans_date $usetransdate\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    #where trans_date>='$mintrans_date'
    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

    #update $hint operation_log set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
    my $dbherrorflag = 0;

    #where trans_date>='$usetransdate'
    #and trans_date<='$today'
    my $dbquerystr = <<"dbEOM";
            update operation_log force index(oplog_tdateloptimeuname_idx) set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
            where trans_date in ($tdateinstr)
            and username=?
            and lastoptime>=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$ptime", "$ptime", @tdateinarray, "$username", "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $DBI::errstr =~ /lock.*try restarting/i ) {
      &miscutils::mysleep(60.0);

      my @dbvalues = ( "$ptime", "$ptime", @tdateinarray, "$onemonthsagotime", "$username", "$time$batchnum" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
    } elsif ( $dbherrorflag == 1 ) {
      &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    }

    $mytime = gmtime( time() );
    my $printstr = "$mytime after update operation_log postauth\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
    $logfilestr = "";
    $logfilestr .= "$mytime after update operation_log postauth\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    if ( $returnsincluded == 1 ) {
      %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbherrorflag = 0;

      #where trans_date>='$mintrans_date'
      #and trans_date<='$today'
      my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
            where trans_date in ($tdateinstr)
            and username=?
            and lastoptime>=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$ptime", "$ptime", @tdateinarray, "$username", "$onemonthsagotime", "$time$batchnum" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      if ( $DBI::errstr =~ /lock.*try restarting/i ) {
        &miscutils::mysleep(60.0);

        my @dbvalues = ( "$ptime", "$ptime", @tdateinarray, "$onemonthsagotime", "$username", "$time$batchnum" );
        &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
      } elsif ( $dbherrorflag == 1 ) {
        &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      }

      $mytime = gmtime( time() );
      my $printstr = "$mytime after update operation_log\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
      $logfilestr = "";
      $logfilestr .= "$mytime after update operation_log return\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    } else {
      $mytime = gmtime( time() );
      my $printstr = "$mytime no returns in batch, update operation_log return not done\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
      $logfilestr = "";
      $logfilestr .= "$mytime no returns in batch, update operation_log return not done\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$mytime\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  } elsif ( $respcode eq "RB" ) {
    ( $errortype, $errorrecseqnum, $errorrectype, $errordatafieldnum, $errordata ) = unpack "A1A4A1A2A30", $resp;

    $errordata =~ s/\x03./\[ETX\]/g;

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "orderid   $errorderid{$errorrecseqnum}\n";
    $logfilestr .= "errortype   $errortype\n";
    $logfilestr .= "errorrecseqnum   $errorrecseqnum\n";
    $logfilestr .= "errorrectype   $errorrectype\n";
    $logfilestr .= "errordatafieldnum   $errordatafieldnum\n";
    $logfilestr .= "errordata   $errordata\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "orderid   $errorderid{$errorrecseqnum}\n";
    $printstr .= "errortype   $errortype\n";
    $printstr .= "errorrecseqnum   $errorrecseqnum\n";
    $printstr .= "errorrectype   $errorrectype\n";
    $printstr .= "errordatafieldnum   $errordatafieldnum\n";
    $printstr .= "errordata   $errordata\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

    if ( $errordata =~ /(AMEX|DISC)/ ) {
      $dontallowamexflag = 1;
      $dontallowdiscflag = 1;
    }

    if ( $errordata =~ /^ZH/ ) {
      $errorcnt{$username}++;
    }

    if ( ( $errortype eq "S" ) && ( $errorrectype eq "X" ) ) {
      if ( $username ne "$usernameold" ) {
        if ( $firstredo == 0 ) {
          $redobatch = 1;
          $firstredo = 1;
          umask 0077;
          $logfilestr = "";
          $logfilestr .= "redo batch\n\n";
          &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
        }
      }
      $usernameold = $username;
    } else {
      my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
	    where orderid=?
	    and username=?
	    and trans_date>=?
	    and result=?
            and (accttype is NULL or accttype ='' or accttype='credit')
	    and finalstatus='locked'
dbEOM
      my @dbvalues = ( "$errorrecseqnum, $errorrectype, $errordatafieldnum, $errordata", "$errorderid{$errorrecseqnum}", "$username", "$onemonthsago", "$time$batchnum" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and username=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$errorrecseqnum, $errorrectype, $errordatafieldnum, $errordata", "$errorderid{$errorrecseqnum}", "$username", "$time$batchnum" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and username=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$errorrecseqnum, $errorrectype, $errordatafieldnum, $errordata", "$errorderid{$errorrecseqnum}", "$username", "$time$batchnum" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    }

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='pending'
	    where trans_date>=?
            and trans_date<=?
	    and username=?
	    and result=?
	    and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$onemonthsago", "$today", "$username", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    #where trans_date>='$mintrans_date'
    #and trans_date<='$today'
    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and username=?
            and lastoptime>=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$username", "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    #where trans_date>='$mintrans_date'
    #and trans_date<='$today'
    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and username=?
            and lastoptime>=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$username", "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dprice\@plugnpay.com\n";
    print MAILERR "Cc: barbara\@plugnpay.com\n";
    print MAILERR "Cc: michelle\@plugnpay.com\n";
    print MAILERR "Subject: visanet - RB INV DATA\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $time\n";
    print MAILERR "file: $username$time$pid.txt\n\n";
    print MAILERR "orderid: $errorderid{$errorrecseqnum}\n";
    print MAILERR "errorrecseqnum: $errorrecseqnum\n";
    print MAILERR "errorrectype: $errorrectype\n";
    print MAILERR "errordatafieldnum: $errordatafieldnum\n";
    print MAILERR "errordata: $errordata\n";
    close MAILERR;
  } elsif ( $respcode eq "DB" ) {
    ( $batchtransdate, $d4 ) = unpack "A4A21", $resp;
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "batchtransdate   $batchtransdate\n";
    $logfilestr .= "d4   $d4\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "batchtransdate   $batchtransdate\n";
    $printstr .= "d4   $d4\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
	    where trans_date>=?
            and trans_date<=?
	    and username=?
	    and result=?
	    and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "Duplicate Batch: $batchtransdate", "$onemonthsago", "$today", "$username", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );

    #where trans_date>='$mintrans_date'
    #and trans_date<='$today'
    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?
            where trans_date in ($tdateinstr)
            and username=?
            and lastoptime>=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "Duplicate Batch: $batchtransdate", @tdateinarray, "$username", "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );

    #where trans_date>='$mintrans_date'
    #and trans_date<='$today'
    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='problem',lastopstatus='problem',descr=?
            where trans_date in ($tdateinstr)
            and username=?
            and lastoptime>=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "Duplicate Batch: $batchtransdate", @tdateinarray, "$username", "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dprice\@plugnpay.com\n";
    print MAILERR "Subject: visanet - duplicate batch\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: duplicate batch\n\n";
    print MAILERR "batchtransdate: $batchtransdate\n";
    close MAILERR;
  } elsif ( $response =~ /^failure/ ) {

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "orderid   $errorderid{$errorrecseqnum}\n";
    $logfilestr .= "error   $response\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='pending'
	    where trans_date>=?
            and trans_date<=?
	    and username=?
	    and result=?
	    and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$onemonthsago", "$today", "$username", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    #where trans_date>='$mintrans_date'
    #and trans_date<='$today'
    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and username=?
            and lastoptime>=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$username", "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    #where trans_date>='$mintrans_date'
    #and trans_date<='$today'
    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and username=?
            and lastoptime>=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$username", "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dprice\@plugnpay.com\n";
    print MAILERR "Subject: visanet - vnetssl no response\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $time\n";
    print MAILERR "file: $username$time$pid.txt\n\n";
    print MAILERR "orderid: $errorderid{$errorrecseqnum}\n";
    print MAILERR "error: $response\n";
    close MAILERR;

    exit;
  } else {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dprice\@plugnpay.com\n";
    print MAILERR "Subject: visanet - unkown error\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $resp\n";
    print MAILERR "file: $username$time$pid.txt\n";
    close MAILERR;
  }

}

sub errorchecking {
  if ( $transflags =~ /token/ ) {
    return 0;
  }

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

sub error {
  my ($group) = @_;

  if ( $group =~ /^(header|parameter)$/ ) {
    $merchanterrorflag = 1;
  } else {

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='pending'
	    where trans_date>=?
            and trans_date<=?
	    and username=?
	    and result=?
	    and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$onemonthsago", "$today", "$username", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    #where trans_date>='$mintrans_date'
    #and trans_date<='$today'
    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and username=?
            and lastoptime>=?
            and batchfile=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$username", "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    #where trans_date>='$mintrans_date'
    #and trans_date<='$today'
    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='pending',lastopstatus='pending'
            where trans_date in ($tdateinstr)
            and username=?
            and lastoptime>=?
            and batchfile=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( @tdateinarray, "$username", "$onemonthsagotime", "$time$batchnum" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  }

  $errorflag = 1;

  my $printstr = "socketclose\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
}

sub errormsg {
  my ( $username, $orderid, $operation, $errmsg ) = @_;

  my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where orderid=?
            and username=?
            and trans_date>=?
            and finalstatus='pending'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$errmsg", "$orderid", "$username", "$onemonthsago" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";
  %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
  my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and username=?
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$errmsg", "$orderid", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

}

sub socketopen {
  ( $addr, $port ) = @_;
  my $printstr = "aaaa: $addr  $port\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) or die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) or die "socket: $!";

  my $host = "processor-host";

  #my $iaddr = inet_aton($host);
  #my $sockaddr = sockaddr_in(0, $iaddr);
  #bind(SOCK, $sockaddr) || die "bind: $!\n";

  connect( SOCK, $paddr ) or die "connect: $!";
}

sub socketwrite {
  $temp = unpack "H*", $message;
  my $printstr = "send: $temp\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  send( SOCK, $message, 0, $paddr );
  recv( SOCK, $respenc, 2048, 0 );

  umask 0077;
  $logfilestr = "";
  $temp = unpack "H*", $respenc;
  my $printstr = "recvc: $temp\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr .= "recvc: $temp\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  if ( $respenc eq "\x05" ) {
    recv( SOCK, $respenc, 2048, 0 );

    umask 0077;
    $logfilestr = "";
    $temp = unpack "H*", $respenc;
    my $printstr = "recvg: $temp\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
    $logfilestr .= "recvg: $temp\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  }

  if ( $endbatchflag == 1 ) {
    my $i = 0;
    while ( ( $respenc =~ /(\x12|\x05|\x06)$/ ) && ( length($respenc) < 15 ) ) {
      select undef, undef, undef, 4.0;
      recv( SOCK, $respenc, 2048, 0 );

      umask 0077;
      $logfilestr = "";
      $temp = unpack "H*", $respenc;
      my $printstr = "recvd: $temp\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
      $logfilestr .= "recvd: $temp\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      $i++;

      if ( $i >= 10 ) {
        last;
      }
    }
  } else {
    my $i = 0;
    while ( $respenc eq "\x12" ) {
      select undef, undef, undef, 4.0;
      recv( SOCK, $respenc, 2048, 0 );

      umask 0077;
      $logfilestr = "";
      $temp = unpack "H*", $respenc;
      my $printstr = "recve: $temp\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
      $logfilestr .= "recve: $temp\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      $i++;

      if ( $i >= 10 ) {
        last;
      }
    }
  }

  $respdec = "";
  $rlen    = length($respenc);
  my $printstr = "len2: $rlen\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  for ( $i = 0 ; $i < $rlen ; $i++ ) {
    $resp1   = substr( $respenc, $i, 1 );
    $newresp = $resp1 & "\x7f";
    $respdec = $respdec . $newresp;
  }
  $response = $respdec;

  $message2 = $response;
  $message2 =~ s/\x1c/\[1c\]/g;
  $message2 =~ s/\x02/\[STX\]/g;
  $message2 =~ s/\x17/\[ETB\]/g;
  $message2 =~ s/\x03/\[ETX\]/g;
  $rlen = length($response);
  if ( $rlen == 1 ) {
    $message2 = unpack "H*", $message2;
  } else {
    $message2 = substr( $message2, 0, -1 );
  }
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "recv: $rlen $message2\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  my $printstr = "recv: $rlen $message2\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  return;

  my $printstr = "read socket $message\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  vec( $rin, $temp = fileno(S), 1 ) = 1;
  $count   = 2;
  $respenc = "";
  my $printstr = "waiting for recv...\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  while ( $count && select( $rout = $rin, undef, undef, 10.0 ) ) {
    recv( SOCK, $got, 2048, 0 );
    $respenc = $respenc . $got;

    #if ($respenc =~ /\x03/) {
    last;

    #}
    $count--;
  }

  my $printstr = "done waiting\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  $temp = unpack "H*", $respenc;
  my $printstr = "recva: $temp\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  #return($response);
}

sub vnetsslsend {
  $msg      = $bigmessage;
  $message  = $bigmessage;
  $response = "";

  Net::SSLeay::load_error_strings();
  Net::SSLeay::SSLeay_add_ssl_algorithms();
  Net::SSLeay::randomize('/etc/passwd');

  #$site = "ssltest2h.tsysacquiring.net";		# test
  #$port = "15443";
  $site = "ssl1.tsysacquiring.net";    # production
  $port = "443";

  $dest_serv = $site;

  $msg = "$message";

  my $len = length($msg);

  my $req = "POST /scripts/gateway.dll\?transact HTTP/1.0\r\n";
  $req = $req . "Host: $site:443\r\n";
  $req = $req . "Accept: */*\r\n";
  $req = $req . "Content-Type: x-Visa-II/x-settle\r\n";
  $req = $req . "Content-Length: $len\r\n\r\n";
  $req = $req . "$message";

  $dest_ip = gethostbyname($dest_serv);
  $dest_serv_params = sockaddr_in( $port, $dest_ip );

  $flag = "success";
  socket( S, &AF_INET, &SOCK_STREAM, 0 ) or return ( &errmssg( "failure socket: $!", 1 ) );

  my $host = "processor-host";

  #my $iaddr = inet_aton($host);
  #my $sockaddr = sockaddr_in(0, $iaddr);
  #bind(S, $sockaddr) || die "bind: $!\n";

  connect( S, $dest_serv_params ) or $flag = &retry();
  if ( $flag ne "success" ) {
    return "failure connect: $!";
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
  $res = Net::SSLeay::connect($ssl) or return "failure sslconnect: $!";

  #$res = Net::SSLeay::connect($ssl) and Net::SSLeay::die_if_ssl_error("ssl connect");

  umask 0077;
  $TMPFILEstr = "";
  $TMPFILEstr .= __FILE__ . ": " . Net::SSLeay::get_cipher($ssl) . "\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/logfiles", "ciphers.txt", "append", "", $TMPFILEstr );

  # Exchange data
  $res = Net::SSLeay::ssl_write_all( $ssl, $req );    # Perl knows how long $msg is
  Net::SSLeay::die_if_ssl_error("ssl write");

  #shutdown S, 1;  # Half close --> No more output, sends EOF to server

  $respenc = "";

  my ( $rin, $rout, $temp );
  vec( $rin, $temp = fileno(S), 1 ) = 1;
  $count = 8;
  while ( $count && select( $rout = $rin, undef, undef, 60.0 ) ) {

    #$respenc = Net::SSLeay::ssl_read_all($ssl);         # Perl returns undef on failure
    $got     = Net::SSLeay::read($ssl);    # Perl returns undef on failure
                                           #umask 0011;
                                           #open(tmpfile,">>/home/pay1/batchfiles/$devprod/visanet/bserverlogmsg.txt");
                                           #print tmpfile "$mytime got: $len $got\n";
                                           #close(tmpfile);
    $respenc = $respenc . $got;
    if ( $respenc =~ /\x03/ ) {
      last;
    }
    Net::SSLeay::die_if_ssl_error("ssl read");
    $count--;
  }
  if ( $count == 1 ) {
    return "no response";
  }
  Net::SSLeay::free($ssl);                 # Tear down connection
  Net::SSLeay::CTX_free($ctx);
  close S;

  $respdec = "";
  my $rlen = length($respenc);
  for ( $i = 0 ; $i < $rlen ; $i++ ) {
    $resp1   = substr( $respenc, $i, 1 );
    $newresp = $resp1 & "\x7f";
    $respdec = $respdec . $newresp;
  }
  $response = $respdec;

  my $head1;
  ( $head1, $response ) = split( /\r\n\r\n/, $response );

  $message2 = $response;
  $message2 =~ s/\x1c/\[1c\]/g;
  $message2 =~ s/\x02/\[STX\]/g;
  $message2 =~ s/\x17/\[ETB\]/g;
  $message2 =~ s/\x03/\[ETX\]/g;
  $rlen = length($response);
  if ( $rlen == 1 ) {
    $message2 = unpack "H*", $message2;
  } else {
    $message2 = substr( $message2, 0, -1 );
  }
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "recv: $rlen $message2\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  my $printstr = "recv: $rlen $message2\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  #if ($head1 =~ /x-data\/xact-error/) {
  #  $result{'MStatus'} = "problem";
  #  $result{'FinalStatus'} = "problem";
  #  $rmessage = "$response";
  #  return;
  #}

  #if ($response eq "") {
  #  $result{'MStatus'} = "problem";
  #  $result{'FinalStatus'} = "problem";
  #  $rmessage = "b: Processor did not respond in a timely manner.";
  #  return;
  #}

}

sub retry {
  socket( S, &AF_INET, &SOCK_STREAM, 0 ) or return ( &errmssg( "socket: $!", 1 ) );

  #my $iaddr = inet_aton($host);
  #my $sockaddr = sockaddr_in(0, $iaddr);
  #bind(S, $sockaddr) || die "bind: $!\n";

  connect( S, $dest_serv_params ) or return ( &errmssg( "connect: $!", 1 ) );

  return "success";
}

sub errmssg {
  my ( $mssg, $level ) = @_;

  if ( $level != 1 ) {
    Net::SSLeay::free($ssl);    # Tear down connection
    Net::SSLeay::CTX_free($ctx);
  }
  close S;

  return $mssg;
}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  my $printstr = "origtime: $origtime $timezone1\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month2 happens on wday $wday\n";

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $printstr = "The $times2 Sunday of month $month2 happens on the $mday2\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

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

  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );

  $printstr .= "newtime: $newtime $timezone2\n\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  return $newtime;

}

sub gengroupbitmap {
  my (@msg) = @_;

  my $groupdataflag = 0;
  my $tempdata      = "";
  my $message       = "";
  my $tempstr       = "";
  my $bitmap1       = "";
  my $bitmap2       = "";
  my @bitmap        = ();

  my $bytenum = 7;
  for ( my $i = 48 ; $i >= 0 ; $i-- ) {
    if ( ( $i % 6 == 0 ) && ( $i != 48 ) ) {
      $tempdata = 64 + $tempdata;
      $tempdata = pack "C", $tempdata;

      #$tmpstr = unpack "H*", $tempdata;
      #print "tmpstr: $tempdata\n";
      #$tempdata = \x40 | $tempdata;
      $bitmap[$bytenum] = $tempdata;
      my $printstr = "bitmap: $bytenum  $i  $tempdata\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
      $tempdata = "";
      $bytenum--;
    } else {
      $tempdata = $tempdata << 1;

      #$tmpstr = unpack "H*", $tempdata;
      #print "tmpstr: $tempdata\n";
    }
    if ( $i <= 0 ) {
      last;
    }
    if ( $msg[$i] ne "" ) {
      my $printstr = "$i\n";
      &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
      $tempdata = $tempdata | 1;
      if ( $i > 23 ) {
        $groupdataflag = 1;
      }
    }

    #$tempstr = pack "N", $tempdata;
    #$tempstr = unpack "H32", $tempstr;
  }

  if ( $groupdataflag == 1 ) {
    my $printstr = "groupdataflag == 1\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
    $tempdata = unpack "H2", $bitmap[3];
    $tempdata = $tempdata + 10;
    $bitmap[3] = pack "H2", $tempdata;
    my $printstr = "bitmap3 $bitmap[3]\n";
    &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
    $bitmap1 = $bitmap[3] . $bitmap[2] . $bitmap[1] . $bitmap[0];
    $bitmap2 = $bitmap[7] . $bitmap[6] . $bitmap[5] . $bitmap[4];
  } else {
    $bitmap1 = $bitmap[3] . $bitmap[2] . $bitmap[1] . $bitmap[0];
    $bitmap2 = "";
  }

  my $printstr = "mainbitmap: $bitmap1\n";
  $printstr .= "groupbitmap: $bitmap2\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  return $bitmap1, $bitmap2;

}

