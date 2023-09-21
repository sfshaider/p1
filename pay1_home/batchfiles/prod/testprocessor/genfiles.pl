#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use procutils;
use rsautils;
use smpsutils;
use Time::Local;

# batch cutoff times at 3:00am, 7:00am, noon, 3:00pm, 6:00pm, 10:00pm

my $group = $ARGV[0];
if ( $group eq "" ) {
  $group = "0";
}
$group = "0";

my $printstr = "group: $group\n";
&procutils::filewrite( "$username", "testprocessor", "/home/pay1/batchfiles/devlogs/testprocessor", "miscdebug.txt", "append", "misc", $printstr );

if ( -e "/home/pay1/batchfiles/logs/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'testprocessor/genfiles.pl $group'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "testprocessor", "/home/pay1/batchfiles/devlogs/testprocessor", "miscdebug.txt", "append", "misc", $printstr );
  exit;
}

my $checkstring = "and t.username in (";

my $MERCHLISTstr = &procutils::fileread( "$username", "testprocessor", "/home/pay1/batchfiles/logs/testprocessor", "merchantList.txt" );
my @MERCHLISTstrarray = split( /\n/, $MERCHLISTstr );

foreach (@MERCHLISTstrarray) {
  chop;
  $checkstring .= "'$_\',";
}
chop $checkstring;
$checkstring .= ") ";

#my $checkstring = "and t.username='aaaa'";

$time = time();
( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $d8, $d9, $modtime ) = stat "/home/pay1/batchfiles/logs/testprocessor/genfiles$group.txt";

$delta = $time - $modtime;

if ( $delta < ( 3600 * 12 ) ) {
  my $checkinstr = &procutils::fileread( "$username", "testprocessor", "/home/pay1/batchfiles/logs/testprocessor", "genfiles$group.txt" );
  $checkuser = $checkinstr;
  chop $checkuser;

}

( $dummy, $today, $todaytime ) = &miscutils::genorderid();

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/logs/testprocessor/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "testprocessor", "/home/pay1/batchfiles/devlogs/testprocessor", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/testprocessor/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/logs/testprocessor/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/logs/testprocessor/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "testprocessor", "/home/pay1/batchfiles/devlogs/testprocessor", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/testprocessor/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/logs/testprocessor/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/logs/testprocessor/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "testprocessor", "/home/pay1/batchfiles/devlogs/testprocessor", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/testprocessor/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/logs/testprocessor/$fileyear" );
}

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 ) );
$onemonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 60 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$twomonthsagotime = $twomonthsago . "000000";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 3 ) );
$threedaysago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$threedaysagotime = $threedaysago . "000000";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $batchid, $today, $time ) = &miscutils::genorderid();
$batchid = $time;
$borderid = substr( "0" x 12 . $batchid, -12, 12 );

my $printstr = "aaaa $onemonthsago  $onemonthsagotime  $sixmonthsago\n";
&procutils::filewrite( "$username", "testprocessor", "/home/pay1/batchfiles/devlogs/testprocessor", "miscdebug.txt", "append", "misc", $printstr );

my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        $checkstring
        and t.finalstatus in ('pending','locked')
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastoptime>=?
        and o.trans_date>=?
        and o.lastopstatus in ('pending','locked')
        and o.processor='testprocessor'
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$threedaysagotime", "$onemonthsago" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "aaaa $user\n";
  &procutils::filewrite( "$username", "testprocessor", "/home/pay1/batchfiles/devlogs/testprocessor", "miscdebug.txt", "append", "misc", $printstr );
  $userarray[ ++$#userarray ] = "$user";
  $usercountarray{$user}      = $usercount;
  $starttdatearray{$user}     = $usertdate;
}

foreach $username ( sort @userarray ) {
  if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "stopgenfiles\n";
    &procutils::filewrite( "$username", "testprocessor", "/home/pay1/batchfiles/logs/testprocessor/$fileyear", "$username$time.txt", "append", "", $logfilestr );
    unlink "/home/pay1/batchfiles/logs/testprocessor/batchfile.txt";
    last;
  }

  my $starttransdate = $starttdatearray{$username};

  my $printstr = "UN:$username, ST:$starttransdate, TWOMONTH:$twomonthsagotime\n";
  &procutils::filewrite( "$username", "testprocessor", "/home/pay1/batchfiles/devlogs/testprocessor", "miscdebug.txt", "append", "misc", $printstr );

  my $dbquerystr = <<"dbEOM";
      select orderid,lastop,auth_code
      from operation_log FORCE INDEX(oplog_tdateuname_idx)
      where trans_date>=?
      and username=?
      and lastoptime>=?
      and lastop in ('postauth','return')
      and lastopstatus='pending'
      and (voidstatus is NULL or voidstatus ='')
dbEOM
  my @dbvalues = ( "$starttransdate", "$username", "$onemonthsagotime" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
    ( $orderid, $lastop, $auth_code ) = @sthtransvalarray[ $vali .. $vali + 2 ];

    my $printstr = "UN:$username $orderid\n";
    &procutils::filewrite( "$username", "testprocessor", "/home/pay1/batchfiles/devlogs/testprocessor", "miscdebug.txt", "append", "misc", $printstr );

    ( $d1, $today, $ptime ) = &miscutils::genorderid();
    my $dbquerystr = <<"dbEOM";
      update trans_log 
      set finalstatus='success',trans_time=?
      where trans_date>=?
      and trans_date<=?
      and orderid=?
      and username=?
      and (accttype is NULL or accttype ='' or accttype='credit')
      and finalstatus='pending'
dbEOM
    my @dbvalues = ( "$time", "$onemonthsago", "$today", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
        update operation_log set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
        where trans_date>=?
        and trans_date<=?  
        and orderid=?
        and username=?
        and lastoptime>=?
        and postauthstatus='pending'
        and (voidstatus is NULL or voidstatus='') 
        and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$time", "$onemonthsago", "$today", "$orderid", "$username", "$onemonthsagotime" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
        update operation_log set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
        where trans_date>=?
        and trans_date<=?  
        and orderid=?
        and username=?
        and lastoptime>=?
        and returnstatus='locked'
        and (voidstatus is NULL or voidstatus='')
        and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$time", "$onemonthsago", "$today", "$orderid", "$username", "$onemonthsagotime" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  }

}

