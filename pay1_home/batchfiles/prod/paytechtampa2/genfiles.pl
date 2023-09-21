#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;
use smpsutils;

use IO::Socket;
use Socket;
use Time::Local;
use paytechtampaiso;

# paytech tampa version 3.4

$devprod = "logs";
my $logProc = 'paytechtampa2';

# 2017 fall time change, to prevent genfiles from running twice
# exit if time is between 6am gmt and 7am gmt
my $timechange = "20171105020000";    # 2am eastern on the morning of the time change (1am to 1am to 2am)

my $str6am  = $timechange + 40000;                 # str represents 6am gmt
my $str7am  = $timechange + 50000;                 # str represents 7am gmt
my $time6am = &miscutils::strtotime("$str6am");    # 6am gmt
my $time7am = &miscutils::strtotime("$str7am");    # 7am gmt
my $now     = time();

if ( ( $now >= $time6am ) && ( $now < $time7am ) ) {
  my $printstr = "exiting due to fall time change\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, 'miscdebug', $logData );
  exit;
}

my $mygroup = $ARGV[0];
if ( $mygroup eq "" ) {
  $mygroup = "0";
}
my $printstr = "mygroup: $mygroup\n";
# &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
my $logData = { 'mygroup' => "$mygroup", 'msg' => "$printstr" };
&procutils::writeDataLog( $username, $logProc, 'miscdebug', $logData );
if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'paytechtampa2/genfiles.pl $mygroup'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl $mygroup already running, exiting...\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'mygroup' => "$mygroup", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, 'miscdebug', $logData );
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: paytechtampa2 - genfiles $mygroup already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl $mygroup because it's already running.\n\n";
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
# &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "pid$mygroup.txt", "write", "", $outfilestr );
my $logData = { 'mytime' => "$mytime", 'pid' => "$pid", 'machine' => "$machine", 'msg' => "$outfilestr" };
&procutils::writeDataLog( $username, $logProc, "pid$mygroup", $logData );

&miscutils::mysleep(2.0);

my $chkline = &procutils::fileread( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "pid$mygroup.txt" );
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl $mygroup already running, pid alterred by another program, exiting...\n";
  $printstr .= "$pidline\n";
  $printstr .= "$chkline\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'pidline' => "$pidline", 'chkline' => "$chkline", 'mygroup' => "$mygroup", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: paytechtampa2 - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl $mygroup already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

$host = "processor-host";

my $checkuser = &procutils::flagread( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "genfiles$mygroup.txt" );
chop $checkuser;

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>='$checkuser'";
}

%errcode = (
  '0',  'Approved',           '2',  'ReferCardIssuer',    '3',  'InvalidMerchant',       '4',  'DoNotHonor',           '5',  'UnableToProcess',    '6',  'InvalidTransactionTerm',
  '8',  'IssuerTimeout',      '9',  'NoOriginal',         '10', 'UnableToReverse',       '12', 'InvalidTransaction',   '13', 'InvalidAmount',      '14', 'InvalidCard',
  '17', 'InvalidCaptureDate', '18', 'NoMatchTotals',      '19', 'SystemErrorReenter',    '20', 'NoFromAccount',        '21', 'NoToAccount',        '22', 'NoCheckingAccount',
  '23', 'NoSavingAccount',    '30', 'MessageFormatError', '39', 'TransactionNotAllowed', '41', 'HotCard',              '42', 'SpecialPickup',      '43', 'HotCardPickUp',
  '44', 'PickUpCard',         '45', 'TxnBackOff',         '51', 'NoFunds',               '54', 'ExpiredCard',          '55', 'IncorrectPIN',       '57', 'TxnNotPermittedOnCard',
  '61', 'ExceedsLimit',       '62', 'RestrictedCard',     '63', 'MACKeyError',           '65', 'ExceedsFreqLimit',     '67', 'RetainCard',         '68', 'LateResponse',
  '75', 'ExceedsPINRetry',    '76', 'InvalidAccount',     '77', 'NoSharingArrangement',  '78', 'FunctionNotAvailable', '79', 'KeyValidationError', '82', 'InvalidCVV',
  '84', 'InvalidLifeCycle',   '87', 'PINKeyError',        '88', 'MACSyncError',          '89', 'SecurityViolation',    '91', 'SwitchNotAvailable', '92', 'InvalidIssuer',
  '93', 'InvalidAcquirer',    '94', 'InvalidOriginator',  '96', 'SystemError',           '97', 'NoFundsTransfer',      '98', 'DuplicateReversal',  '99', 'DuplicateTransaction'
);

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 60 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $d1, $today, $time ) = &miscutils::genorderid();
$todaytime = $time;

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );
my $printstr = "";
my $logData = {};
if ( !-e "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyearonly" ) {
  $printstr .= "creating $fileyearonly\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  $logData = { 'fileyearonly' => "$fileyearonly" };
  system("mkdir /home/pay1/batchfiles/$devprod/paytechtampa2/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/paytechtampa2/$filemonth" ) {
  $printstr .= "creating $filemonth\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  $logData = { %{$logData}, 'filemonth' => "$filemonth" };
  system("mkdir /home/pay1/batchfiles/$devprod/paytechtampa2/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/paytechtampa2/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear" ) {
  $printstr .= "creating $fileyear\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  $logData = { %{$logData}, 'fileyear' => "$fileyear" };
  system("mkdir /home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear" );
}
if ($printstr ne "") {
  $logData = { %{$logData}, 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
}

if ( !-e "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: paytechtampa2 - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/paytechtampa2/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$response = "";    # don't delete

my $printstr = "aaaa\n";
# &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
my $logData = { 'msg' => "$printstr" };
&procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
# xxxx
my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        and t.trans_date<=?
        $checkstring
        and (t.finalstatus='pending' or substr(t.auth_code,187,10)='open      ')
        and (t.accttype is NULL or t.accttype='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastoptime>=?
        and (o.lastopstatus='pending' or substr(o.auth_code,187,10)='open      ')
        and o.processor='paytechtampa2'
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
my $printstr = "";
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  $printstr .= "$user\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}
if ($printstr ne "") {
  my $logData = { 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
}

my $printstr = "cccc\n";
# &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
my $logData = { 'msg' => "$printstr" };
&procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

foreach $username ( sort @userarray ) {
  if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "stopgenfiles\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    my $logData = { 'msg' => "$logfilestr" };
    &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );
    unlink "/home/pay1/batchfiles/$devprod/paytechtampa2/batchfile.txt";
    last;
  }

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  # &procutils::flagwrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "genfiles$mygroup.txt", "write", "", $checkinstr );
  my $logData = { 'username' => "$username", 'msg' => "$checkinstr" };
  &procutils::writeDataLog( $username, $logProc, "genfiles$mygroup", $logData );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "batchfile.txt", "write", "", $batchfilestr );
  my $logData = { 'username' => "$username", 'msg' => "$batchfilestr" };
  &procutils::writeDataLog( $username, $logProc, "batchfile", $logData );

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  if ( $usercountarray{$username} > 2000 ) {
    $batchcntuser = 900;
  } elsif ( $usercountarray{$username} > 1000 ) {
    $batchcntuser = 500;
  } elsif ( $usercountarray{$username} > 600 ) {
    $batchcntuser = 200;
  } elsif ( $usercountarray{$username} > 300 ) {
    $batchcntuser = 200;
  } else {
    $batchcntuser = 200;
  }

  if ( $username =~ /^(austinlion|austinjimm|austinweb|austingolf|banyanpilo)$/ ) {
    $batchcntuser = 4000;
  }

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,currency,switchtime,features
        from customers
        where username=?
        and processor='paytechtampa2'
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $status, $mcurrency, $switchtime, $features ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
        select bankid,categorycode,poscond,industrycode,batchtime,requestorid
        from paytechtampa2
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $bankid, $categorycode, $poscond, $industrycode, $batchgroup, $requestorid ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $status ne "live" ) {
    next;
  }

  if ( ( $mygroup eq "5" ) && ( $batchgroup ne "5" ) ) {
    next;
  } elsif ( ( $mygroup eq "4" ) && ( $batchgroup ne "4" ) ) {
    next;
  } elsif ( ( $mygroup eq "3" ) && ( $batchgroup ne "3" ) ) {
    next;
  } elsif ( ( $mygroup eq "2" ) && ( $batchgroup ne "2" ) ) {
    next;
  } elsif ( ( $mygroup eq "1" ) && ( $batchgroup ne "1" ) ) {
    next;
  } elsif ( ( $mygroup eq "0" ) && ( $batchgroup ne "" ) ) {
    next;
  } elsif ( $mygroup !~ /^(0|1|2|3|4|5)$/ ) {
    next;
  }

  umask 0077;

  my $printstr = "$username $usercountarray{$username} $starttransdate\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'username' => "$username", 'starttransdate' => "$starttransdate", 'userCount' => "$usercountarray{$username}", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  $logfilestr = "";
  $logfilestr .= "$username $usercountarray{$username} $starttransdate\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  my $logData = { 'username' => "$username", 'starttransdate' => "$starttransdate", 'userCount' => "$usercountarray{$username}", 'msg' => "$logfilestr" };
  &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

  if ( $industrycode eq "petroleum" ) {
    &petroleumsettle();
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
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'sweeptime' => "$sweeptime", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      my $logData = { 'newhour' => "$newhour", 'settlehour' => "$settlehour", 'msg' => "$logfilestr" };
      &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      my $logData = { 'newhour' => "$newhour", 'settlehour' => "$settlehour", 'msg' => "$logfilestr" };
      &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  my $printstr = "gmt today: $todaytime\n";
  $printstr .= "est today: $esttime\n";
  $printstr .= "est yesterday: $yesterday\n";
  $printstr .= "settletime: $settletime\n";
  $printstr .= "sweeptime: $sweeptime\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'todaytime' => "$todaytime", 'esttime' => "$esttime", 'yesterday' => "$yesterday", 'settletime' => "$settletime", 'sweeptime' => "$sweeptime", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  umask 0077;
  my $printstr = "$username\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'username' => "$username", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  $logfilestr = "";
  $logfilestr .= "$username  group: $batchgroup  sweeptime: $sweeptime  settletime: $settletime\n";
  $logfilestr .= "$features\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  my $logData = { 'username' => "$username", 'batchgroup' => "$batchgroup", 'sweeptime' => "$sweeptime", 'settletime' => "$settletime", 'features' => "$features", 'msg' => "$logfilestr" };
  &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

  my $printstr =
    "select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,card_zip,card_addr,authtime,authstatus,forceauthtime,forceauthstatus\n";
  $printstr .= "from operation_log\n";
  $printstr .= "where trans_date>='$starttransdate'\n";
  $printstr .= "and trans_date<='$today'  \n";
  $printstr .= "and lastoptime>='$onemonthsagotime'\n";
  $printstr .= "and username='$username'\n";
  $printstr .= "and lastop in ('postauth','return')\n";
  $printstr .= "and lastopstatus='pending'\n";
  $printstr .= "and voidstatus is NULL\n";
  $printstr .= "and (accttype is NULL or accttype='credit')\n";
  $printstr .= "order by orderid\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'starttransdate' => "$starttransdate", 'today' => "$today", 'onemonthsagotime' => "$onemonthsagotime", 'username' => "$username", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  $batch_flag = 1;
  @details    = ();

  my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,card_zip,card_addr,
                 authtime,authstatus,forceauthtime,forceauthstatus
          from operation_log
          where trans_date>=?
          and trans_date<=?  
          and lastoptime>=?
          and username=?
          and lastop in ('postauth','return')
          and lastopstatus='pending'
          and (voidstatus is NULL or voidstatus='')
          and (accttype is NULL or accttype='' or accttype='credit')
          order by orderid
dbEOM
  my @dbvalues = ( "$starttransdate", "$today", "$onemonthsagotime", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $mintrans_date = $today;

  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 20 ) {
    ( $orderid,   $operation,   $trans_date, $trans_time, $enccardnumber, $enclength, $exp,      $amount,     $auth_code,     $avs_code,
      $refnumber, $finalstatus, $cvvresp,    $transflags, $card_zip,      $card_addr, $authtime, $authstatus, $forceauthtime, $forceauthstatus
    )
      = @sthtransvalarray[ $vali .. $vali + 19 ];

    my $printstr = "aaaa\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    my $logData = { 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
    if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "stopgenfiles\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      my $logData = { 'msg' => "$logfilestr" };
      &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

      unlink "/home/pay1/batchfiles/$devprod/paytechtampa2/batchfile.txt";
      last;
    }

    if ( $operation eq "void" ) {
      $orderidold = $orderid;
      next;
    }
    if ( ( $orderid eq $orderidold ) || ( $finalstatus !~ /^(pending|locked)$/ ) ) {
      $orderidold = $orderid;
      next;
    }

    $orderidold = $orderid;

    if ( ( $sweeptime ne "" ) && ( $trans_time > $sweeptime ) ) {
      next;    # transaction is newer than sweeptime
    }

    if ( $switchtime ne "" ) {
      $switchtime = substr( $switchtime . "0" x 14, 0, 14 );
      if ( ( $operation eq "postauth" ) && ( $authtime ne "" ) && ( $authtime < $switchtime ) ) {
        next;
      }
    }

    if ( ( $trans_date < $mintrans_date ) && ( $trans_date >= '19990101' ) ) {
      $mintrans_date = $trans_date;
    }

    my $dbquerystr = <<"dbEOM";
          select origamount
          from operation_log
          where orderid=?
          and username=?
          and trans_date>=?
          and (authstatus='success'
          or forceauthstatus='success')
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$twomonthsago" );
    ($origamount) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "paytechtampa2", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $card_type = &smpsutils::checkcard($cardnumber);
    if ( $card_type eq "dc" ) {
      $card_type = "ds";
    }

    $errflag = &errorchecking();
    if ( $errflag == 1 ) {
      next;
    }

    umask 0077;
    $logfilestr = "";
    $tmp = substr( $cardnumber, 0, 2 );
    $logfilestr .= "$orderid $operation $transflags $tmp\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    my $logData = { 'orderid' => "$orderid", 'operation' => "$operation", 'transflags' => "$transflags", 'tmp' => "$tmp", 'msg' => "$logfilestr" };
    &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

    if ( $batch_flag == 1 ) {
      &pidcheck();

      $batch_flag = 0;

      $datasentflag    = 0;
      $socketerrorflag = 0;
      $dberrorflag     = 0;
      $batcherrorflag  = 0;
      $batchcnt        = 1;
      $recseqnum       = 0;
      $salesamt        = 0;
      $salescnt        = 0;
      $returnamt       = 0;
      $returncnt       = 0;
      $seqnum          = 0;
      $errorrecord     = "";
      $batchoidarray   = ();

      my $dbquerystr = <<"dbEOM";
              select username,batchnum
              from paytechtampa2
              where username=?
dbEOM
      my @dbvalues = ("$username");
      ( $chkusername, $batchnum ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      $batchnum = $batchnum + 1;

      if ( $batchnum >= 998 ) {

        # xxxx   should be 1 after old stuff is turned off
        $batchnum = 501;
      }

      # xxxx   should go away after old stuff is turned off
      if ( $batchnum < 501 ) {
        $batchnum = 501;
      }

      $batchnum = substr( "0" x 6 . $batchnum, -6, 6 );    # batch number (6n)
      $batchid  = substr( "0" x 3 . $batchnum, -3, 3 );    # batch number (6n)

      if ( $chkusername eq "" ) {
        my $dbquerystr = <<"dbEOM";
              insert into paytechtampa2
              (username,batchnum)
              values (?,?)
dbEOM
        my %inserthash = ( "username", "$username", "batchnum", "$batchnum" );
        &procutils::dbinsert( $username, $orderid, "pnpmisc", "paytechtampa2", %inserthash );

      } else {
        my $dbquerystr = <<"dbEOM";
              update paytechtampa2 set batchnum=?
              where username=?
dbEOM
        my @dbvalues = ( "$batchnum", "$username" );
        &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      }

    }

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='locked',result=?
            where orderid=?
	    and username=?
	    and trans_date>=?
	    and finalstatus in ('pending','locked')
dbEOM
    my @dbvalues = ( "$time$batchid", "$orderid", "$username", "$onemonthsago" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending'
          where orderid=?
          and username=?
          and $operationstatus in ('pending','locked')
          and (voidstatus is NULL or voidstatus='')
          and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time$batchid", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    &batchdetail();
    if ( $socketerrorflag == 1 ) {
      last;    # if socket error stop altogether
    }

    if ( $batchcnt >= $batchcntuser ) {
      &batchheader();
      &batchtrailer();
      &endbatch();
      @orderidarray = ();
      $batch_flag   = 1;
      $batchcnt     = 1;
      $datasentflag = 0;
      @details      = ();
      if ( $batcherrorflag == 1 ) {
        last;    # if batch error move on to next username
      }
    }
  }

  if ( ( ( $batchcnt > 1 ) || ( $datasentflag == 1 ) ) && ( $socketerrorflag == 0 ) ) {
    &batchheader();
    &batchtrailer();
    &endbatch();
    @orderidarray = ();
    $batch_flag   = 1;
    $batchcnt     = 1;
    $datasentflag = 0;
    @details      = ();
  }
}

unlink "/home/pay1/batchfiles/$devprod/paytechtampa2/batchfile.txt";

if ( ( !-e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) && ( $socketerrorflag == 0 ) ) {
  umask 0033;
  $checkinstr = "";
  &procutils::flagwrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "genfiles$mygroup.txt", "write", "", $checkinstr );
}

exit;

sub mysleep {
  for ( $myi = 0 ; $myi <= 60 ; $myi++ ) {
    umask 0033;
    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "baccesstime.txt", "write", "", $outfilestr );
    my $logData = { 'temptime' => "$temptime", 'msg' => "$outfilestr" };
    &procutils::writeDataLog( $username, $logProc, "baccesstime", $logData );

    select undef, undef, undef, 60.00;
  }
}

sub senderrmail {
  my ($message) = @_;

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: paytechtampa2 - batch problem\n";
  print MAILERR "\n";
  print MAILERR "Username: $username\n";
  print MAILERR "\nLocked transactions found in trans_log and batchid's did not match.\n";
  print MAILERR " Or batch out of balance.\n\n";
  print MAILERR "$message.\n\n";
  print MAILERR "chkbatchid: $chkbatchid    batchid: $batchid\n";
  close MAILERR;

}

sub endbatch {

  $ipaddress = "206.253.180.20";    # production server
  $port      = "17600";             # production port
                                    #$ipaddress = "206.253.180.250";  # new test server
                                    #$ipaddress = "206.253.184.250";  # new test server
                                    #$port = "12002";                 # test port

  &socketopen( $ipaddress, $port );

  $group = "header";
  &decodebitmap($batchheader);
  &sendrecord($batchheader);
  if ( $response eq "" ) {
    close(SOCK);
    &miscutils::mysleep(2.0);
    &socketopen( $ipaddress, $port );
    &sendrecord($batchheader);
  }
  if ( $response eq "" ) {
    &sendrecord($batchheader);
  }
  if ( $response =~ /DUP BATCH NUM/ ) {
    $batchnum = $batchnum + 1;
    if ( $batchnum == 998 ) {

      # xxxx   should be 1 after old stuff is turned off
      $batchnum = 501;
    }
    $batchnum = substr( "0" x 6 . $batchnum, -6, 6 );    # batch number (6n)
    $batchid  = substr( "0" x 3 . $batchnum, -3, 3 );    # batch number (6n)

    my $dbquerystr = <<"dbEOM";
          update paytechtampa2 set batchnum=?
          where username=?
dbEOM
    my @dbvalues = ( "$batchnum", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $batchheader = substr( $batchheader, 0, 95 ) . $batchnum . substr( $batchheader, 101 );
    &sendrecord($batchheader);
  }

  &decodebitmap($response);

  if ( $msgvalues[39] ne "00" ) {
    my $printstr = "error in header: $msgvalues[39]\n";
    $printstr .= "    $msgvalues[48]\n";
    $printstr .= "    $msgvalues[60]\n";
    $printstr .= "    $msgvalues[62]\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    my $logData = { 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
  }

  if ( $msgvalues[39] eq "00" ) {
    $group = "detail";
    foreach $detail (@details) {
      &decodebitmap($detail);
      &sendrecord($detail);
      &decodebitmap($response);
      $msgcode = substr( $response, 26, 4 );
      if ( $msgvalues[39] ne "00" ) {
        my $printstr = "error in detail: $msgvalues[39]\n";
        $printstr .= "    $msgvalues[48]\n";
        $printstr .= "    $msgvalues[60]\n";
        $printstr .= "    $msgvalues[62]\n";
        $printstr .= "    msg: $msgcode    seqnum: $msgvalues[11]   orderid: $batchoidarray{$msgvalues[11]}\n";
        # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
        my $logData = { 'msgcode' => "$msgcode", 'seqnum' => "$msgvalues[11]", 'orderid' => "$batchoidarray{$msgvalues[11]}", 'msg' => "$printstr" };
        &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

        umask 0077;
        $logfilestr = "";
        $logfilestr .= "    msg: $msgcode    seqnum: $msgvalues[11]   orderid: $batchoidarray{$msgvalues[11]}\n";
        # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
        my $logData = { 'msgcode' => "$msgcode", 'seqnum' => "$msgvalues[11]", 'orderid' => "$batchoidarray{$msgvalues[11]}", 'msg' => "$logfilestr" };
        &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

        if ( ( $msgcode eq "1330" ) && ( $batchoidarray{ $msgvalues[11] } ne "" ) ) {
          $errorrecord = $batchoidarray{ $msgvalues[11] };
          my $printstr = "update databases $errorrecord\n";
          # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
          my $logData = { 'errorrecord' => "$errorrecord", 'msg' => "$printstr" };
          &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
        }

        last;
      }
    }
  }

  if ( $msgvalues[39] eq "00" ) {
    $group = "trailer";
    &decodebitmap($batchtrailer);
    &sendrecord($batchtrailer);
    &decodebitmap($response);
    if ( $msgvalues[39] ne "00" ) {
      my $printstr = "error in trailer: $msgvalues[39]\n";
      $printstr .= "    $msgvalues[48]\n";
      $printstr .= "    $msgvalues[60]\n";
      $printstr .= "    $msgvalues[62]\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
      my $logData = { 'msg' => "$printstr" };
      &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
    }
  }

  close(SOCK);

  $respcode = $msgvalues[39];

  # bit 62
  $nextbatchnum = "";
  if ( $msgvalues[62] =~ /B3/ ) {
    $newidx  = 0;
    $datalen = substr( $restofdata, 0, 3 );
    $data    = substr( $restofdata, 3, $datalen );
    for ( my $newidx = 0 ; $newidx < $datalen ; ) {
      $tag     = substr( $data, $newidx + 0, 2 );
      $taglen  = substr( $data, $newidx + 2, 2 );
      $tagdata = substr( $data, $newidx + 4, $taglen );
      $newidx  = $newidx + 4 + $taglen;

      my $printstr = "tag: $tag\n";
      $printstr .= "taglen: $taglen\n";
      $printstr .= "tagdata: $tagdata\n\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
      my $logData = { 'tag' => "$tag", 'taglen' => "$taglen", 'tagdata' => "$tagdata", 'msg' => "$printstr" };
      &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
    }
  }

  my $printstr = "bbbb\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  if ( ( $group eq "trailer" ) && ( $respcode eq "00" ) ) {
    my $printstr = "respcode = 00\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    my $logData = { 'respcode' => "$respcode", 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

    ( $d1, $today, $ptime ) = &miscutils::genorderid();
    my $printstr = "";
    foreach $oid (@orderidarray) {
      $printstr .= "$username $oid success\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
      my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?
	    where orderid=?
	    and username=?
	    and trans_date>=?
            and (accttype is NULL or accttype='' or accttype='credit')
	    and finalstatus='locked'
dbEOM
      my @dbvalues = ( "$ptime", "$oid", "$username", "$onemonthsago" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
	    where orderid=?
            and username=?
            and trans_date>=?
            and lastoptime>=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$ptime", "$ptime", "$oid", "$username", "$mintrans_date", "$onemonthsagotime" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
	    where orderid=?
            and username=?
            and trans_date>=?
            and lastoptime>=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$ptime", "$ptime", "$oid", "$username", "$mintrans_date", "$onemonthsagotime" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
    }
    my $logData = { 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  } elsif ( $group ne "trailer" ) {
    my $printstr = "respcode = $respcode\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    my $logData = { 'respcode' => "$respcode", 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

    if ( $errorrecord ne "" ) {
      my $printstr = "$username $oid problem\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
      my $logData = { 'username' => "$username", 'oid' => "$oid", 'msg' => "$printstr" };
      &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
      my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr='invalid detail record'
	    where orderid=?
	    and username=?
	    and trans_date>=?
            and trans_date<=?
	    and finalstatus='locked'
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$errorrecord", "$username", "$onemonthsago", "$today" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='problem',lastopstatus='problem',descr='invalid detail record'
	    where orderid=?
            and username=?
            and trans_date>=?
            and trans_date<=?  
            and lastoptime>=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$errorrecord", "$username", "$mintrans_date", "$today", "$onemonthsagotime" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='problem',lastopstatus='problem',descr='invalid detail record'
	    where orderid=?
            and username=?
            and trans_date>=?
            and trans_date<=?  
            and lastoptime>=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$errorrecord", "$username", "$mintrans_date", "$today", "$onemonthsagotime" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    }
    my $printstr = "";
    foreach $oid (@orderidarray) {
      $printstr .= "$username $oid pending\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
      my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='pending'
	    where orderid=?
	    and username=?
	    and trans_date>=?
            and trans_date<=?
	    and finalstatus='locked'
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$oid", "$username", "$onemonthsago", "$today" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='pending',lastopstatus='pending'
	    where orderid=?
            and username=?
            and trans_date>=?
            and trans_date<=?  
            and lastoptime>=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$oid", "$username", "$mintrans_date", "$today", "$onemonthsagotime" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='pending',lastopstatus='pending'
	    where orderid=?
            and username=?
            and trans_date>=?
            and trans_date<=?  
            and lastoptime>=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$oid", "$username", "$mintrans_date", "$today", "$onemonthsagotime" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
    }
    my $logData = { 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch trailer: $respcode $errcode{$respcode}\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    my $logData = { 'respcode' => "$respcode", 'errcode' => "$errcode{$respcode}", 'msg' => "$logfilestr" };
    &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );
  }
}

sub batchdetail {
  $transamt = substr( $amount, 4 );
  $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );
  $transamt = substr( "00000000" . $transamt, -8, 8 );

  if ( $operation eq "return" ) {
    $returnamt = $returnamt + $transamt;
    $returncnt++;
  } else {
    $salesamt = $salesamt + $transamt;
    $salescnt++;
  }
  $batchcnt++;

  $origoperation = "";
  if ( $operation eq "postauth" ) {
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
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      my $logData = { 'username' => "$username", 'twomonthsago' => "$twomonthsago", 'orderid' => "$orderid", 'trans_time' => "$trans_time", 'msg' => "$logfilestr" };
      &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

      $socketerrorflag = 1;
      $dberrorflag     = 1;
      return;
    }
  }

  $datasentflag = 1;
  $orderidarray[ ++$#orderidarray ] = $orderid;

  my $cashback = substr( $auth_code, 258, 12 );
  $cashback =~ s/ //g;

  @bd = ();

  $len   = length($cardnumber);
  $len   = substr( "00" . $len, -2, 2 );
  $bd[2] = $len . $cardnumber;             # primary acct number (19a) 2

  if ( ( $transflags =~ /gift/ ) && ( $operation eq "return" ) && ( $transflags =~ /prior/ ) ) {
    $bd[3] = '169500';                     # processing code (6a) 3 prior issue
  } elsif ( ( $transflags =~ /gift/ ) && ( $operation eq "return" ) ) {
    $bd[3] = '239500';                     # processing code (6a) 3 issue
  } elsif ( ( $transflags =~ /gift/ ) && ( $transflags =~ /capt/ ) ) {
    $bd[3] = '009500';                     # processing code (6a) 3 redemption
  } elsif ( ( $transflags =~ /gift/ ) && ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
    $bd[3] = '199500';                     # processing code (6a) 3 prior redemption
  } elsif ( $transflags =~ /gift/ ) {
    $bd[3] = '199500';                     # processing code (6a) 3 redemption completion
  } elsif ( $operation eq "return" ) {
    $bd[3] = '209100';                     # processing code (6a) 3
  }

  elsif ( $transflags =~ /capt/ ) {
    $bd[3] = '009100';                     # processing code (6a) 3
  } else {
    $bd[3] = '179100';                     # processing code (6a) 3
  }

  ( $currency, $transamount ) = split( / /, $amount );
  $transamount = sprintf( "%d", ( $transamount * 100 ) + .0001 );
  $transamount = substr( "0" x 12 . $transamount, -12, 12 );
  $bd[4] = $transamount;                   # bd amount (12n) 4

  my $surcharge = substr( $auth_code, 404, 8 );
  $surcharge =~ s/ //g;
  if ( $surcharge > 0 ) {
    $surcharge = substr( "0" x 12 . $surcharge, -12, 12 );
    $bd[8] = $surcharge;                   # surcharge (12n) 8
  }

  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
  my $ltrandate = sprintf( "%02d%02d%04d", $lmonth + 1, $lday, 1900 + $lyear );
  my $ltrantime = sprintf( "%02d%02d%02d", $lhour,      $lmin, $lsec );

  $seqnum++;
  $seqnum = substr( "0" x 6 . $seqnum, -6, 6 );
  $batchoidarray{$seqnum} = $orderid;
  $bd[11]                 = $seqnum;       # system trace number (6n) 11
  if ( $operation eq "return" ) {
    $trandate = $ltrandate;
    $trantime = $ltrantime;
  } else {
    my $printstr = "auth_code: $auth_code\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    my $logData = { 'auth_code' => "$auth_code", 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
    $trandate = substr( $auth_code, 110, 8 );
    $trantime = substr( $auth_code, 118, 6 );
  }
  $bd[12] = $trantime;                     # local time HHMMSS (6n) 12
  $bd[13] = $trandate;                     # local date MMDDYYYY (8n) 13

  $expdate = substr( $exp, 3, 2 ) . substr( $exp, 0, 2 );
  $expdate = substr( "0000" . $expdate, -4, 4 );
  $bd[14] = $expdate;                      # expiration date YYMM (4n) 14

  $magstripetrack = substr( $auth_code, 87, 1 );
  if ( ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) && ( $magstripetrack =~ /^(1|2)$/ ) && ( $transflags !~ /prior/ ) ) {
    $posentry = '902';
  } elsif ( ( $transflags !~ /recinit/ ) && ( $transflags =~ /(recur|install|cit|incr|resub|delay|reauth|noshow)/ ) && ( $transflags !~ /notcof/ ) ) {
    $posentry = '102';
  } else {
    $posentry = '012';
  }
  $bd[22] = $posentry;                     # pos entry mode (3a) 22

  $poscond = substr( $auth_code,         148, 2 );
  $poscond = substr( $poscond . " " x 2, 0,   2 );
  $bd[25] = $poscond;                      # pos condition code (2a) 25

  my $refnum = $refnumber;
  if ( ( $refnumber eq "" ) || ( $refnumber eq "000000000000" ) ) {
    $refnum = &smpsutils::gettransid( $username, "paytechtampa2", $orderid );
    $refnum = "1" . substr( "0" x 11 . $refnum, -11, 11 );
  }
  $bd[37] = $refnum;                       # reference number (12n) 37

  $authcode = substr( $auth_code,          0, 6 );
  $authcode = substr( $authcode . " " x 6, 0, 6 );
  $bd[38] = $authcode;                     # authorization number (6n) 38

  my $tid = substr( $terminal_id . " " x 3, 0, 3 );
  $bd[41] = $tid;                          # terminal id (3n) 41

  $mid = substr( $merchant_id . " " x 12, 0, 12 );
  $bd[42] = $mid;                          # card acceptor id code - terminal/merchant id (12a) 42

  my $addtldata = "";

  $magstripetrack = substr( $auth_code, 87, 1 );
  if ( $transflags =~ /moto/ ) {
    $dataentry = "02";
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery|petroleum)$/ ) && ( $magstripetrack eq "1" ) && ( $transflags !~ /prior/ ) ) {
    $dataentry = "04";
  } elsif ( ( $industrycode =~ /^(retail|restaurant|grocery|petroleum)$/ ) && ( $magstripetrack eq "2" ) && ( $transflags !~ /prior/ ) ) {
    $dataentry = "03";
  } else {
    $dataentry = "02";
  }
  $addtldata = $addtldata . "D102$dataentry";    # data entry source

  if ( $transflags =~ /gift/ ) {
    $d2data = substr( $auth_code, 196, 8 );
    my $len = length($d2data);
    $len = substr( "00" . $len, -2, 2 );
    $addtldata = $addtldata . "D2$len$d2data";
  }

  my $marketdata = substr( $auth_code, 366, 38 );
  $marketdata =~ s/^ *//g;
  $marketdata =~ s/ +$//g;
  if ( ( $marketdata ne "" ) && ( substr( $marketdata, 28, 10 ) ne "          " ) ) {
    my $phone = substr( $marketdata, 28, 10 );
    $phone =~ s/ //g;
    my $phonelen = length($phone);
    $marketdata = substr( $marketdata . " " x 25, 0, 25 - $phonelen ) . $phone;
  }
  $marketdata =~ tr/a-z/A-Z/;
  $marketdata =~ s/[^0-9A-Z\-\.\* ]//g;
  if ( $marketdata ne "" ) {
    $marketdata = substr( $marketdata, 0, 25 );
    my $marketdatalen = length($marketdata);
    $marketdatalen = substr( "00" . $marketdatalen, -2, 2 );
    $addtldata = $addtldata . "D7$marketdatalen$marketdata";
  }

  $commcardtype = substr( $auth_code, 157, 12 );
  $taxind       = substr( $auth_code, 49,  1 );
  $commcardtype =~ s/ //g;
  if ( ( $card_type =~ /^(vi|mc|ax)$/ ) && ( ( $commcardtype ne "" ) || ( $transflags =~ /level3/ ) ) ) {
    $ponumber = substr( $auth_code, 68, 17 );
    my $len = length($ponumber);
    $len = substr( "00" . $len, -2, 2 );
    $addtldata = $addtldata . "E1$len$ponumber";

    $tax = substr( $auth_code, 59, 9 );
    $tax =~ s/ //g;
    $tax = substr( "0" x 7 . $tax, -7, 7 );
    if ( $tax > 0 ) {
      $exemptind = 1;
    } elsif ( ( $taxind eq "1" ) || ( $transflags =~ /notexempt/ ) ) {
      $exemptind = 1;
    } elsif ( ( $taxind eq "2" ) || ( $transflags =~ /exempt/ ) ) {
      $exemptind = 2;
    } else {
      $exemptind = 0;
    }
    $addtldata = $addtldata . "E208$exemptind$tax";
  }

  $shipzip = substr( $auth_code, 50, 9 );
  $shipzip =~ s/ //g;
  if ( ( $shipzip ne "" ) && ( $card_type =~ /^(vi|mc|ax)$/ ) && ( ( $commcardtype ne "" ) || ( $transflags =~ /level3/ ) ) ) {
    $shipzip = substr( $shipzip . " " x 9, 0, 9 );
    $addtldata = $addtldata . "E309$shipzip";
  }

  if ( ( $card_type =~ /(vi|mc|xds|xjc)/ ) && ( $operation ne "return" ) && ( $transflags =~ /(init|recur|install|cit|incr|resub|delay|reauth|noshow|mit)/ ) && ( $transflags !~ /xnotcof/ ) ) {
    if ( ( ( $card_type eq "mc" ) && ( $transflags =~ /(init|recur|install|cit|incr|resub|delay|reauth|noshow|mit)/ ) )
      || ( ( $card_type ne "mc" ) && ( $transflags !~ /init/ ) && ( $transflags =~ /(recur|install|cit|incr|resub|delay|reauth|noshow|mit)/ ) && ( $transflags !~ /notcof/ ) ) ) {
      $addtldata = $addtldata . "CF01Y";    # card on file (1a)
    }
  }

  if ( ( $operation ne "return" ) && ( $card_type =~ /(vi|xds)/ ) && ( $transflags =~ /(init|recur|install|cit|incr|resub|delay|reauth|noshow|mit)/ ) && ( $transflags !~ /xnotcof/ ) ) {

    my $transid = substr( $auth_code, 412, 15 );
    $transid = substr( "0" x 15 . $transid, -15, 15 );

    my $posenv = " ";                       # credentials

    if ( ( $transflags =~ /(init|mit)/ ) && ( $transflags !~ /(recur|install)/ ) ) {
      $posenv = "C";
    } elsif ( $transflags =~ /(recur)/ ) {
      $posenv = "R";
    } elsif ( $transflags =~ /(install)/ ) {
      $posenv = "I";
    } elsif ( $transflgas =~ /moto/ ) {
      $posenv = " ";
    }

    my $reason = "0000";
    if ( $transflags =~ /incr/ ) {
      $reason = "3900";
    } elsif ( $transflags =~ /resub/ ) {
      $reason = "3901";
    } elsif ( $transflags =~ /delay/ ) {
      $reason = "3902";
    } elsif ( $transflags =~ /reauth/ ) {
      $reason = "3903";
    } elsif ( $transflags =~ /noshow/ ) {
      $reason = "3904";
    }

    my $origamt = "0" x 12;
    if ( $card_type eq "ds" ) {
      $origamt = $transamount;
    }

    my $origsign = "C";
    if ( $origamt eq "000000000000" ) {
      $origsign = " ";
    }

    my $estauthind = " ";
    if ( $paytechtampaiso::datainfo{'transflags'} =~ /estim/ ) {
      $estauthind = "E";
    }

    my $wantatxid = substr( $auth_code, 428, 1 );
    $wantatxid = substr( $wantatxid . " ", 0, 1 );

    if ( ( $transid ne "" ) || ( $transflags =~ /(recinit|recur|install|incr|resub|delay|reauth|noshow|cit|mit)/ ) ) {
      $addtldata = $addtldata . "MT35" . $transid . $reason . $origamt . $origsign . $posenv . $estauthind . $wantatxid;
    }
  }

  my $freeform = substr( $auth_code, 270, 30 );
  $freeform =~ tr/a-z/A-Z/;
  $freeform =~ s/[^0-9A-Z\-\.]//g;
  if ( $freeform ne "" ) {
    $freeform = substr( $freeform, 0, 30 );
    my $freeformlen = length($freeform);
    $freeformlen = substr( "00" . $freeformlen, -2, 2 );
    $addtldata = $addtldata . "R1$freeformlen$freeform";
  }

  if ( $transflags =~ /recinit/ ) {
    $addtldata = $addtldata . "R202RF";
  } elsif ( $transflags =~ /recur/ ) {
    $addtldata = $addtldata . "R202RS";
  }

  $s1resp = substr( $auth_code, 150, 2 );
  $s1resp =~ s/ +$//;
  $s1resp = substr( $s1resp . "0" x 2, 0, 2 );
  if ( $s1resp eq "00" ) {
    if ( $card_type eq "vi" ) {
      $s1resp = "VI";
    } elsif ( $card_type eq "mc" ) {
      $s1resp = "MC";
    } elsif ( $card_type eq "ax" ) {
      $s1resp = "AE";
    } elsif ( $card_type eq "ds" ) {
      $s1resp = "DS";
    } elsif ( $card_type eq "dc" ) {
      $s1resp = "DS";
    } elsif ( $card_type eq "jc" ) {
      $s1resp = "JC";
    } elsif ( $cardnumber =~ /^603028/ ) {
      $s1resp = "CC";
    } elsif ( $cardnumber =~ /^(690046|707138)/ ) {
      $s1resp = "WX";
    } elsif ( $transflags =~ /gift/ ) {
      $s1resp = "SV";
    } else {
      $s1resp = "$card_type";
      my $printstr = "$orderid\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
      my $logData = { 'orderid' => "$orderid", 'msg' => "$printstr" };
      &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
      exit;
    }
  }
  $s1resp =~ s/DC/DS/;
  $s2resp = substr( $auth_code, 152, 5 );
  $s2resp =~ s/ +$//;
  $s2resp = substr( $s2resp . "0" x 5, 0, 5 );
  if ( $s2resp eq "00000" ) {
    $s2resp = "00 00";
  }
  $addtldata = $addtldata . "S102$s1resp";
  $addtldata = $addtldata . "S205$s2resp";

  my $printstr = "transflags: $transflags\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'transflags' => "$transflags", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  if ( $transflags =~ /uset/ ) {
    $addtldata = $addtldata . "T3012";    # acct is a token, send back a token

    my $subseqflag = " ";

    #$requestorid = "33322222333";              # for testing, should be in database
    $requestorid = substr( $requestorid . " " x 11, 0, 11 );
    if ( $datainfo{'transflags'} =~ /recur/ ) {
      $subseqflag = "Y";
    }
    $addtldata = $addtldata . "TK16" . "NXXY" . $subseqflag . $requestorid;    # requestor id

    if ( ( $datainfo{'transflags'} =~ /uset/ ) && ( $datainfo{'transflags'} =~ /recur/ ) && ( $card_type eq "vi" ) ) {
      $addtldata = $addtldata . "VA20SUBSEQUENT0000000000";
    } elsif ( ( $datainfo{'transflags'} =~ /uset/ ) && ( $datainfo{'transflags'} =~ /recur/ ) && ( $card_type eq "ax" ) ) {
      $addtldata = $addtldata . "AD40SUBSEQUENT000000000000000000000000000000";
    }
  }

  if ( $transflags =~ /debt/ ) {
    $addtldata = $addtldata . "PI01D";
  }

  my $healthdata = substr( $auth_code, 306, 60 );
  $healthdata =~ s/ //g;
  if ( $healthdata ne "" ) {
    my $healthdatalen = length($healthdata);
    $healthdatalen = substr( "00" . $healthdatalen, -2, 2 );
    $addtldata = $addtldata . "H1$healthdatalen$healthdata";
  }

  if ( ( $operation ne "return" ) && ( $card_type eq "vi" ) ) {
    ( $d1, $origamt ) = split( / /, $origamount );
    $origamt = sprintf( "%d", ( $origamt * 100 ) + .0001 );
    $origamt = substr( "0" x 12 . $origamt, -12, 12 );
    $addtldata = $addtldata . "V612$origamt";
  }

  $vbvresp = substr( $auth_code, 147, 1 );
  $vbvresp =~ s/ //g;
  if ( $vbvresp ne "" ) {
    $addtldata = $addtldata . "VB01$vbvresp";
  }

  my $len = length($addtldata);
  $len = substr( "000" . $len, -3, 3 );
  $bd[48] = "$len$addtldata";    # additional data (private) (LLLVAR) 48

  if ( ( $card_type eq "ds" ) && ( $cashback > 0 ) ) {
    $cashback = substr( "0" x 12 . $cashback, -12, 12 );
    $bd[54] = $cashback;
  }

  my $addtldata = "";
  my $posdata = substr( $auth_code, 124, 21 );
  $posdata = substr( $posdata . " " x 21, 0, 21 );
  if ( ( $operation eq "return" ) && ( ( $transflags !~ /moto/ ) && ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) ) ) {
    $posdata = "00000000000          ";
  } elsif ( ( $operation eq "return" ) && ( ( $transflags =~ /moto/ ) && ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) ) ) {
    $posdata = "00000110000          ";
  } elsif ( ( $operation eq "return" ) && ( $transflags =~ /moto/ ) ) {
    $posdata = "00000110005          ";
  } elsif ( $operation eq "return" ) {
    $posdata = "00000110005          ";
  } elsif ( $origoperation eq "forceauth" ) {
    if ( ( $transflags !~ /moto/ ) && ( $industrycode =~ /^(retail|restaurant|grocery)$/ ) ) {
      $posdata = "00000000000          ";
    } else {
      $posdata = "00000110005          ";
    }
  }
  $addtldata = $addtldata . "A1021$posdata";

  my $len = length($addtldata);
  $len = substr( "000" . $len, -3, 3 );
  $bd[60] = "$len$addtldata";    # additional data (national) (LLLVAR) 60

  my $addtldata = "";

  my $p1data = "001E" . "00E5" . "0" x 20;    # pos/var capabilities (28a)
  $addtldata = "P1028$p1data";

  my $p2bitmap = "62A0000000000000";
  my $p2       = "44";                        # host processing platform  page 11-25
  my $p3       = "80";
  my $p7       = "20";
  my $p9       = "6E";
  my $p11      = "44";
  $addtldata = $addtldata . "P2026" . $p2bitmap . $p2 . $p3 . $p7 . $p9 . $p11;

  if ( $addtldata ne "" ) {
    my $len = length($addtldata);
    $len = substr( "000" . $len, -3, 3 );
    $bd[62] = "$len$addtldata";               # private data (LLLVAR) 62
  }

  my $addtldata = "";

  my $eci = substr( $auth_code, 145, 2 );
  if ( ( $transflags !~ /gift/ ) && ( $transflags =~ /(moto|recur|recinit|install|init|xcit|incr|resub|delay|reauth|noshow)/ ) ) {
    my $oid = substr( "0" x 9 . $orderid, -9, 9 );
    my $type = "1";
    if ( $transflags =~ /(recur|recinit)/ ) {
      $type = "2";
    } elsif ( $transflags =~ /(install)/ ) {
      $type = "3";
    }
    $addtldata = $addtldata . "M1010$oid$type";
  } elsif ( ( $transflags !~ /gift/ ) && ( $industrycode eq "retail" ) ) {
    my $invoicenum = substr( $auth_code, 95, 6 );
    $invoicenum = substr( $invoicenum . " " x 6, 0, 6 );
    if ( $invoicenum eq "      " ) {
      $invoicenum = substr( "0" x 6 . $orderid, -6, 6 );
    }
    $traninfo = substr( " " x 20, 0, 20 );
    $addtldata = $addtldata . "R2026$invoicenum$traninfo";
  } elsif ( ( $transflags !~ /gift/ ) && ( $industrycode eq "restaurant" ) ) {
    my $invoicenum = substr( $auth_code, 95, 6 );
    $invoicenum = substr( $invoicenum . " " x 6, 0, 6 );
    if ( $invoicenum eq "      " ) {
      $invoicenum = substr( "0" x 6 . $orderid, -6, 6 );
    }
    my $gratuity = substr( $auth_code, 88, 7 );
    $gratuity =~ s/ //g;
    $gratuity = substr( "0" x 7 . $gratuity, -7, 7 );
    my $server = substr( $auth_code, 102, 8 );
    $server =~ s/ //g;
    $server = substr( "0" x 8 . $server, -8, 8 );
    if ( $server eq "00000000" ) {
      $server = "00000001";
    }
    my $tax = substr( $auth_code, 59, 9 );
    $tax =~ s/ //g;
    $tax = substr( "0" x 9 . $tax, -7, 7 );
    $addtldata = $addtldata . "R1028$invoicenum$gratuity$server$tax";
  } elsif ( $transflags !~ /gift/ ) {
    my $oid = substr( "0" x 16 . $orderid, -16, 16 );
    my $eci = substr( $auth_code,          145, 2 );
    my $goods = "D ";
    if ( $transflags =~ /physical/ ) {
      $goods = "P ";
    }

    $addtldata = $addtldata . "E1020$oid$eci$goods";
  }

  if ( $transflags =~ /gift/ ) {
    my $cashregid   = "0" x 15;
    my $employeenum = "0" x 10;
    my $cashoutind  = "N";
    if ( $transflags =~ /cashout/ ) {
      $cashoutind = "Y";
    }
    my $cardseqnum = "01";
    my $totalcards = "01";

    $addtldata = $addtldata . "SV030$cashregid$employeenum$cashoutind$cardseqnum$totalcards";
  }

  if ( $addtldata ne "" ) {
    my $len = length($addtldata);
    $len = substr( "000" . $len, -3, 3 );
    $bd[63] = "$len$addtldata";    # private data (LLLVAR) 63
  }

  my ( $bitmap1, $bitmap2 ) = &paytechtampaiso::generatebitmap(@bd);

  $bitmap1 = pack "H16", $bitmap1;
  if ( $bitmap2 ne "" ) {
    $bitmap2 = pack "H16", $bitmap2;
  }

  my $messtype = "1300";
  my $message  = $messtype . $bitmap1 . $bitmap2;

  foreach $var (@bd) {
    $message = $message . $var;
  }

  &decodemsg(@bd);

  if ( $datainfo{'transflags'} =~ /gift/ ) {
    $tmpfilestr = "";
    $tmpfilestr .= "$orderid        $operation  $transflags   $bd[3]\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "gift.txt", "append", "", $tmpfilestr );
    my $logData = { 'orderid' => "$orderid", 'operation' => "$operation", 'transflags' => "$transflags", 'bd' => "$bd[3]", 'msg' => "$tmpfilestr" };
    &procutils::writeDataLog( $username, $logProc, "gift", $logData );
  }

  $checkmessage = $message;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime = gmtime( time() );

  my $printstr = "$temptime send: $checkmessage\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );

  $header  = "K.PTIISOYN          ";
  $message = $header . $message;
  $len     = length($message);
  $len     = pack "n", $len;
  my $zero = pack "H2", "00";
  $message = $len . ( $zero x 4 ) . $message;

  @details = ( @details, $message );

  $printstr .= "dddd dddd $transflags\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'temptime' => "$temptime", 'checkmessage' => "$checkmessage", 'transflags' => "$transflags", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  # xxxx
  $chkamounts = $tax;

  # level3 - one 1320 record for each item purchased
  if ( $transflags =~ /level3/ ) {
    my $printstr = "select from orderdetails where orderid=$orderid  $username\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    my $logData = { 'orderid' => "$orderid", 'username' => "$username", 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

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

      my $printstr = "aaaa $item  $quantity  $cost  $descr  $unit\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
      my $logData = { 'item' => "$item", 'quantity' => "$quantity", 'cost' => "$cost", 'descr' => "$descr", 'unit' => "$unit" };
      @bd = ();
      $bd[0] = '1320';    # message id (4n)
      $bd[1] = pack "H16", "0020000008C10002";    # primary bit map (8n)

      $bd[2] = $seqnum;                           # system trace number (6n) 11

      $bd[3] = "0" x 12;                          # reference number (12n) 37

      my $tid = substr( $terminal_id . " " x 3, 0, 3 );
      $bd[4] = $tid;                              # terminal id (3n) 41

      $mid = substr( $merchant_id . " " x 12, 0, 12 );
      $bd[5] = $mid;                              # card acceptor id code - terminal/merchant id (12a) 42

      my $addtldata = "";
      if ( $transflags =~ /level3/ ) {
        $addtldata = $addtldata . "A308PCL3DATA";
      }

      my $len = length($addtldata);
      $len = substr( "000" . $len, -3, 3 );
      $bd[6] = "$len$addtldata";                  # additional data (private) (LLLVAR) 48

      my $addtldata = "";
      $item =~ s/[^a-zA-Z0-9 \-]//g;              # 3/29/2016
      $item =~ tr/a-z/A-Z/;
      $item = substr( $item . " " x 12, 0, 12 );
      $descr =~ s/[^a-zA-Z0-9 \-\/]//g;
      $descr =~ tr/a-z/A-Z/;
      $descr =~ s/^ +//;
      $descr = substr( $descr . " " x 35, 0, 35 );
      $quantity = sprintf( "%d", ( $quantity * 10000 ) + .0001 );
      $quantity = substr( "0" x 13 . $quantity, -13, 13 );
      $unit     = substr( $unit . " " x 3,      0,   3 );

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
      $unitcost = substr( "0" x 13 . $unitcost, -13, 13 );

      $discountamt = 0;
      if ( $customa ne "" ) {
        $discountamt = $customa;
        $discountamt = sprintf( "%d", ( $discountamt * 100 ) + .0001 );
      }

      $extcost = ( $unitcost * $quantity / 1000000 ) - $discountamt;

      # new 04/12/2006
      $extcost = sprintf( "%d", $extcost + .0001 );

      $extcost = substr( "0" x 13 . $extcost, -13, 13 );

      $chkamounts = $chkamounts + $extcost;

      $addtldata = $addtldata . "D1078$item$descr$quantity$unit$debitind$netind$extcost";

      $addtldata = $addtldata . "D2013$unitcost";

      $discountamt = $customa;

      $discountamt = sprintf( "%d", ( $discountamt * 100 ) + .0001 );
      $discountamt = substr( "0" x 13 . $discountamt, -13, 13 );
      $addtldata = $addtldata . "D3013$discountamt";

      $taxamt = $customb;

      # xxxx 9/21/2009 see if only positive tax amounts work
      if ( $taxamt < 0 ) {
        $taxamt = 0 - $taxamt;
      }
      $taxamt = sprintf( "%d", ( $taxamt * 100 ) + .0001 );
      $taxamt = substr( "0" x 13 . $taxamt, -13, 13 );
      $addtldata = $addtldata . "D4013$taxamt";

      $commoditycode = $customc;
      if ( ( $card_type eq "vi" ) || ( $commoditycode ne "" ) ) {
        $commoditycode =~ s/[^a-zA-Z0-9 ]//g;
        $commoditycode =~ tr/a-z/A-Z/;
        if ( $commoditycode eq "" ) {
          $commoditycode = "00001";
        }
        $commoditycode = substr( $commoditycode . " " x 12, 0, 12 );
        $addtldata = $addtldata . "D5012$commoditycode";
      }

      if ( $addtldata ne "" ) {
        my $len = length($addtldata);
        $len = substr( "000" . $len, -3, 3 );
        $bd[7] = "$len$addtldata";    # private data (LLLVAR) 63
      }

      my $message = "";
      foreach $var (@bd) {
        $message = $message . $var;
      }

      &decodemsg(@bd);

      $checkmessage = $message;
      $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
      $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
      $temptime = gmtime( time() );

      $printstr .= "$temptime send: $checkmessage\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
      $logData = { %{$logData}, 'temptime' => "$temptime", 'checkmessage' => "$checkmessage", 'msg' => "$printstr" };
      &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

      $header  = "K.PTIISOYN          ";
      $message = $header . $message;
      $len     = length($message);
      $len     = pack "n", $len;
      my $zero = pack "H2", "00";
      $message = $len . ( $zero x 4 ) . $message;

      @details = ( @details, $message );

    }
  }

  return;

  if ( $respcode eq "" ) {
    my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='pending',descr=?
          where trans_date>=?
          and trans_date<=?
          and username=?
          and result=?
          and (accttype is NULL or accttype='' or accttype='credit')
          and finalstatus='locked'
dbEOM
    my @dbvalues = ( "Response incorrect", "$onemonthsago", "$today", "$username", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='pending',lastopstatus='pending',descr='Response incorrect'
            where trans_date>=?
            and trans_date<=?
            and lastoptime>=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$mintrans_date", "$today", "$onemonthsagotime", "$username", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch detail: response incorrect $checkbeginm $checkbeginr $checkrecordm $checkrecordr $checkoperationm $checkoperationr\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    my $logData = { 'checkbeginm' => "$checkbeginm", 'checkbeginr' => "$checkbeginr", 'checkrecordm' => "$checkrecordm", 'checkrecordr' => "$checkrecordr", 'checkoperationm' => "$checkoperationm", 'checkoperationr' => "$checkoperationr", 'msg' => "$logfilestr" };
    &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

    $socketerrorflag = 1;
    return;
  }

  if ( $respcode eq "00" ) {
    $transamt = substr( $amount, 4 );
    $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );
    $transamt = substr( "00000000" . $transamt, -8, 8 );

  } elsif ( ( $respcode ne "" ) && ( $respcode ne "00" ) ) {
    my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='problem',descr=?
          where orderid=?
          and username=?
          and trans_date>=?
          and result=?
          and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$errcode{$respcode}", "$orderid", "$username", "$onemonthsago", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$errcode{$respcode}", "$orderid", "$username", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch detail: $respcode $errcode{$respcode}\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    my $logData = { 'respcode' => "$respcode", 'errcode' => "$errcode{$respcode}", 'msg' => "$logfilestr" };
    &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );
  } else {
    my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='pending',descr=?
          where trans_date>=?
          and trans_date<=?
          and username=?
          and result=?
          and (accttype is NULL or accttype='' or accttype='credit')
          and finalstatus='locked'
dbEOM
    my @dbvalues = ( "No response from socket", "$onemonthsago", "$today", "$username", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='pending',lastopstatus='pending',descr='No response from socket'
            where trans_date>=?
            and trans_date<=?  
            and lastoptime>=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$mintrans_date", "$today", "$onemonthsagotime", "$username", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch detail: No response from socket\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    my $logData = { 'msg' => "$logfilestr" };
    &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

    $socketerrorflag = 1;
  }
}

sub batchheader {
  $batch_flag = 0;

  $batchcount++;

  $batchreccnt = 1;
  $filereccnt++;
  $recseqnum++;
  $recseqnum   = substr( "0000000" . $recseqnum,  -7, 7 );
  $merchant_id = substr( $merchant_id . " " x 12, 0,  12 );
  $terminal_id = substr( $terminal_id . " " x 3,  0,  3 );

  $batchdate = $createdate;
  $batchdate = substr( $batchdate . " " x 6, 0, 6 );
  $batchtime = $createtime;
  $batchtime = substr( $batchtime . " " x 6, 0, 6 );
  $banknum   = substr( $banknum . " " x 3, 0, 3 );

  @bh = ();
  $bh[0] = '1500';    # message id (4n)
  $bh[1] = pack "H16", "2018000008C00004";    # primary bit map (8n)
  $bh[2] = "920000";                          # processing code (6a) 3
  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
  my $ltrandate = sprintf( "%02d%02d%04d", $lmonth + 1, $lday, 1900 + $lyear );
  my $ltrantime = sprintf( "%02d%02d%02d", $lhour,      $lmin, $lsec );
  $bh[3] = $ltrantime;                        # local time(6n) HHMMSS 12
  $bh[4] = $ltrandate;                        # local date (8n) MMDDYYYY 13
  $bh[5] = "0" x 12;                          # retrieval reference number (12a) 37

  my $tid = substr( $terminal_id . " " x 3, 0, 3 );
  if ( $tid eq "   " ) {
    $tid = "001";
  }
  $bh[6] = $tid;                              # card acceptor terminal id (3a) 41

  my $mid = substr( $merchant_id . " " x 12, 0, 12 );
  $bh[7] = $mid;                              # card acceptor id code - terminal/merchant id (12a) 42

  my $addtldata = "";
  $batchuploadtype = "RU";                                        # batch upload type RU - regular upload (2a)
  $batchnum        = substr( "0" x 6 . $batchnum, -6, 6 );        # batch number (6n)
  $salescnt        = substr( "0" x 6 . $salescnt, -6, 6 );        # sales transaction count (6n)
  $salesamt        = substr( "0" x 12 . $salesamt, -12, 12 );     # total sales amount (12n)
  $returncnt       = substr( "0" x 6 . $returncnt, -6, 6 );       # return transaction count (6n)
  $returnamt       = substr( "0" x 12 . $returnamt, -12, 12 );    # total returns amount (12n)

  $addtldata = $addtldata . "B2044$batchuploadtype$batchnum$salescnt$salesamt$returncnt$returnamt";
  $addtldata = $addtldata . "T1026DIRLINK   042513VERSION3.4";

  my $len = length($addtldata);
  $len = substr( "000" . $len, -3, 3 );
  $bh[8] = "$len$addtldata";                                      # reserved private data (LLLVAR) 62

  $message = "";
  foreach $var (@bh) {
    $outfilestr .= "$var";
    $message = $message . $var;
  }
  $outfilestr .= "\n";

  &decodemsg(@bh);

  $checkmessage = $message;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime = gmtime( time() );

  $header  = "K.PTIISOYN          ";
  $message = $header . $message;
  $len     = length($message);
  $len     = pack "n", $len;
  my $zero = pack "H2", "00";
  $message = $len . ( $zero x 4 ) . $message;

  $batchheader = $message;

  $transseqnum   = 0;
  $batchsalescnt = 0;
  $batchsalesamt = 0;
  $batchretcnt   = 0;
  $batchretamt   = 0;

}

sub batchtrailer {
  $recseqnum = $recseqnum + 2;
  $recseqnum = substr( $recseqnum, -8, 8 );

  @bt = ();
  $bt[0] = '1500';    # message id (4n)
  $bt[1] = pack "H16", "2018000008C00000";    # primary bit map (8n)
  $bt[2] = "930000";                          # processing code (6a) 3
  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
  my $ltrandate = sprintf( "%02d%02d%04d", $lmonth + 1, $lday, 1900 + $lyear );
  my $ltrantime = sprintf( "%02d%02d%02d", $lhour,      $lmin, $lsec );
  $bt[3] = $ltrantime;                        # local time(6n) HHMMSS 12
  $bt[4] = $ltrandate;                        # local date (8n) MMDDYYYY 13
  $bt[5] = "0" x 12;                          # retrieval reference number (12a) 37

  my $tid = substr( $terminal_id . " " x 3, 0, 3 );
  if ( $tid eq "   " ) {
    $tid = "001";
  }
  $bt[6] = $tid;                              # card acceptor terminal id (3a) 41

  my $mid = substr( $merchant_id . " " x 12, 0, 12 );
  $bt[7] = $mid;                              # card acceptor id code - terminal/merchant id (12a) 42

  my $message = "";
  foreach $var (@bt) {
    $message = $message . $var;
  }

  &decodemsg(@bt);

  $checkmessage = $message;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime = gmtime( time() );

  my $printstr = "send: $checkmessage\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'checkmessage' => "$checkmessage", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  $header  = "K.PTIISOYN          ";
  $message = $header . $message;
  $len     = length($message);
  $len     = pack "n", $len;
  my $zero = pack "H2", "00";
  $message = $len . ( $zero x 4 ) . $message;

  $batchtrailer = $message;

}

sub sendrecord {
  my ($message) = @_;

  $checkmessage = $message;
  $cnum         = "";
  if ( $checkmessage =~ /PTIISOYN          1300/ ) {
    $cnumlen = substr( $checkmessage, 38, 2 );
    if ( ( $cnumlen >= 12 ) && ( $cnumlen <= 19 ) ) {
      $cnum = substr( $checkmessage, 40, $cnumlen );
      $xs = "x" x $cnumlen;
      $checkmessage =~ s/$cnum/$xs/;
    }
  }
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$checkmessage\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  my $logData = { 'checkmessage' => "$checkmessage", 'msg' => "$logfilestr" };
  &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

  &socketwrite($message);
  &socketread();

  if ( $response eq "failure" ) {
    $response = "";
  }

  $checkmessage = $response;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$checkmessage\n\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  my $logData = { 'checkmessage' => "$checkmessage", 'msg' => "$logfilestr" };
  &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

  $borderid = &miscutils::incorderid($borderid);
  $borderid = substr( "0" x 12 . $borderid, -12, 12 );

}

sub errorchecking {

  # check for bad card numbers
  my $errorstatus = "";
  my $errormsg    = "";

  if ( ( $enclength > 1024 ) || ( $enclength < 30 ) ) {
    $errorstatus = "problem";
    $errormsg    = "could not decrypt card";
  }

  $mylen = length($cardnumber);
  if ( ( $mylen < 13 ) || ( $mylen > 20 ) ) {
    $errorstatus = "problem";
    $errormsg    = "bad card length";
  }

  if ( $cardnumber eq "4111111111111111" ) {
    $errorstatus = "problem";
    $errormsg    = "test card number";
  }

  # check for 0 amount
  $amt = substr( $amount, 4 );
  if ( $amt == 0 ) {
    $errorstatus = "problem";
    $errormsg    = "amount = 0.00";
  }

  if ( $errorstatus ne "" ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus=?,descr=?
            where orderid=?
            and username=?
            and trans_date>=?
            and finalstatus='pending'
dbEOM
    my @dbvalues = ( "$errorstatus", "$errormsg", "$orderid", "$username", "$onemonthsago" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus=?,lastopstatus=?,descr=?
            where orderid=?
            and username=?
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$errorstatus", "$errorstatus", "$errormsg", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    return 1;
  }

  return 0;
}

sub decodemsg {
  my @msgarray = @_;

  $tempstr = unpack "H16", $msgarray[1];
  my $printstr = "\n\nbitmap1: $tempstr\n";
  my $logData = { 'bitmap1' => "$tempstr" };
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );

  my $end = 1;
  if ( $msgarray[1] =~ /^(8|9|A|B|C|D|E|F)/i ) {
    $tempstr = unpack "H16", $msgarray[2];
    $printstr .= "bitmap2: $tempstr\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    $logData = { %{$logData}, 'bitmap2' => "$tempstr" };
    $end = 2;
  }
  $logData = { %{$logData}, 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  my $message = "";
  my $msg1    = "                                  ";
  my $msg2    = "";

  $myi    = 0;
  $bitnum = 0;
  for ( $myj = 1 ; $myj <= $end ; $myj++ ) {
    $bitmaphalf = $msgarray[$myj];
    $bitmapa = unpack "N", $bitmaphalf;

    $bitmaphalf = substr( $msgarray[$myj], 4 );
    $bitmapb = unpack "N", $bitmaphalf;

    $bitmaphalf = $bitmapa;

    foreach $var (@msgarray) {
      if ( $var ne "" ) {
        $checkmessage = $var;
        $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
        $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;

        $msg2 = $msg2 . "$checkmessage^";

        if ( $myi > $myj ) {
          $bit = 0;
          while ( ( $bit == 0 ) && ( $bitnum < 129 ) ) {
            if ( ( $bitnum == 33 ) || ( $bitnum == 97 ) ) {
              $bitmaphalf = $bitmapb;
            }
            $bit = ( $bitmaphalf >> ( 128 - $bitnum ) ) % 2;
            $bitnum++;
          }
          $bitnumstr = sprintf( "%-*d", length($checkmessage) + 1, $bitnum - 1 );
          $msg1 = $msg1 . $bitnumstr;
        }

        $myi++;
      }
    }
  }
  my $printstr = "$msg1\n$msg2\n\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'msg1' => "$msg1", 'msg2' => "$msg2", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
  # my $printstr = "\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
}

sub decodebitmap {
  my ( $message, $findbit ) = @_;

  $bitlenarray[2]  = "LLVAR";
  $bitlenarray[3]  = 6;
  $bitlenarray[4]  = 12;
  $bitlenarray[7]  = 14;
  $bitlenarray[11] = 6;
  $bitlenarray[12] = 6;
  $bitlenarray[13] = 8;
  $bitlenarray[14] = 4;
  $bitlenarray[18] = 4;
  $bitlenarray[22] = 3;
  $bitlenarray[25] = 2;
  $bitlenarray[35] = "LLVAR";
  $bitlenarray[37] = 12;
  $bitlenarray[38] = 6;
  $bitlenarray[39] = 2;
  $bitlenarray[41] = 3;
  $bitlenarray[42] = 12;
  $bitlenarray[45] = "LLVAR";
  $bitlenarray[48] = "LLLVAR";
  $bitlenarray[49] = 3;
  $bitlenarray[54] = 12;
  $bitlenarray[60] = "LLLVAR";
  $bitlenarray[62] = "LLLVAR";
  $bitlenarray[63] = "LLLVAR";
  $bitlenarray[70] = 3;

  my $idxstart = 30;                            # bitmap start point
  my $idx      = $idxstart;
  my $bitmap1  = substr( $message, $idx, 8 );
  my $bitmap   = unpack "H16", $bitmap1;
  my $printstr = "\n\nbitmap1: $bitmap\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'bitmap1' => "$bitmap" };
  $idx = $idx + 8;

  my $end = 1;
  if ( $bitmap =~ /^(8|9|a|b|c|d|e|f)/ ) {
    $bitmap2 = substr( $message, $idx, 8 );
    $bitmap = unpack "H16", $bitmap2;
    $printstr .= "bitmap2: $bitmap\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    $logData = { %{$logData}, 'bitmap2' => "$bitmap" };
    $end = 2;
    $idx = $idx + 8;
  }
  $logData = { %{$logData}, 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  @msgvalues = ();
  my $myk        = 0;
  my $myi        = 0;
  my $bitnum     = 0;
  my $bitmaphalf = $bitmap1;
  my $wordflag   = 3;
  for ( $myj = 1 ; $myj <= $end ; $myj++ ) {
    my $bitmaphalfa = substr( $bitmaphalf, 0, 4 );
    my $bitmapa = unpack "N", $bitmaphalfa;

    my $bitmaphalfb = substr( $bitmaphalf, 4, 4 );
    my $bitmapb = unpack "N", $bitmaphalfb;

    my $bitmaphalf = $bitmapa;

    while ( $idx < length($message) ) {
      my $bit = 0;
      while ( ( $bit == 0 ) && ( $bitnum < 129 ) ) {
        if ( ( $bitnum == 33 ) || ( $bitnum == 97 ) ) {
          $bitmaphalf = $bitmapb;
        }
        if ( ( $bitnum == 33 ) || ( $bitnum == 65 ) || ( $bitnum == 97 ) ) {
          $wordflag--;
        }

        $bit = ( $bitmaphalf >> ( 128 - ( $wordflag * 32 ) - $bitnum ) ) % 2;
        $bitnum++;
      }

      my $idxlen = $bitlenarray[ $bitnum - 1 ];
      if ( $idxlen eq "LLVAR" ) {
        $idxlen = substr( $message, $idx, 2 );
        $idx = $idx + 2;
      } elsif ( $idxlen eq "LLLVAR" ) {
        $idxlen = substr( $message, $idx, 3 );
        $idx = $idx + 3;
      }
      my $value = substr( $message, $idx, $idxlen );
      $tmpbit = $bitnum - 1;
      my $printstr = "bit: $tmpbit  $idx  $idxlen  $value\n\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
      my $logData = { 'tmpbit' => "$tmpbit", 'idx' => "$idx", 'idxlen' => "$idxlen", 'value' => "$value", 'msg' => "$printstr" };
      &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

      $msgvalues[$tmpbit] = "$value";

      $myk++;
      if ( $myk > 26 ) {
        exit;
      }
      if ( $findbit == $bitnum - 1 ) {
        return $idx, $value;
      }
      $idx = $idx + $idxlen;
    }
  }    # end for
  # my $printstr = "\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  return -1, "";
}

sub socketopen {
  my ( $addr, $port ) = @_;
  ( $iaddr, $paddr, $proto, $line );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );
  my $printstr = "bbbb socket open\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";
  my $printstr = "cccc socket open\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  my $printstr = "dddd socket open\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  connect( SOCK, $paddr ) or &socketopen2( $addr, $port, "connect: $!" );
  $retrycnt = 0;
  my $printstr = "aaaa socket open\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
}

sub socketopen2 {
  my ( $addr, $port, $msg ) = @_;
  ( $iaddr, $paddr, $proto, $line );

  my $printstr = "$msg $retrycnt\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'message' => "$msg", 'retrycnt' => "$retrycnt", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  system('sleep 2');
  $retrycnt++;
  if ( $retrycnt > 2000 ) {
    my $printstr = "giving up\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    my $logData = { 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: Paytechtampa2 - FAILURE\n";
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

  connect( SOCK, $paddr ) or &socketopen2( $addr, $port, "connect: $!" );
  my $printstr = "aaaa socket open2\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
}

sub socketwrite {
  ($message) = @_;

  send( SOCK, $message, 0, $paddr );
  my $printstr = "aaaa socket write\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
}

sub socketread {
  my $printstr = "aaaa in socket read\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  vec( $rin, $temp = fileno(SOCK), 1 ) = 1;
  $count    = 4;
  $response = "";
  $respdata = "";

  while ( $count && select( $rout = $rin, undef, undef, 20.0 ) ) {
    recv( SOCK, $response, 2048, 0 );
    $checkmessage = $response;
    $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
    $printstr .= "aa$checkmessage\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );

    $respdata = $respdata . $response;

    $resplength = unpack "n", $respdata;
    $resplength = $resplength + 6;
    $rlen       = length($respdata);

    if ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      $response = substr( $respdata, 0, $resplength );
      last;
    }
    $count--;
  }
  my $logData = { 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  my $printstr = "origtime: $origtime $timezone1\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'origtime' => "$origtime", 'timezone1' => "$timezone1" };

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

  if ( $wday1 < $wday ) {
    $wday1 = 7 + $wday1;
  }
  my $mday1 = ( 7 * ( $times1 - 1 ) ) + 1 + ( $wday1 - $wday );
  my $timenum1 = timegm( 0, substr( $time1, 3, 2 ), substr( $time1, 0, 2 ), $mday1, $month1 - 1, substr( $origtime, 0, 4 ) - 1900 );

  $printstr .= "The $times1 Sunday of month $month1 happens on the $mday1\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  $logData = { %{$logData}, 'times1' => "$times1", 'month1' => "$month1", 'mday1' => "$mday1" };

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  $printstr .= "The $times2 Sunday of month $month2 happens on the $mday2\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  $logData = { %{$logData}, 'times2' => "$times2", 'month2' => "$month2", 'mday2' => "$mday2" };

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

  $printstr .= "zoneadjust: $zoneadjust\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  $logData = { %{$logData}, 'zoneadjust' => "$zoneadjust" };
  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  $printstr .= "newtime: $newtime $timezone2\n\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  $logData = { %{$logData}, 'newtime' => "$newtime", 'timezone2' => "$timezone2", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
  return $newtime;

}

sub petroleumsettle {

  my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,card_zip,card_addr,
                 authtime,authstatus,forceauthtime,forceauthstatus
          from operation_log
          where trans_date>=?
          and trans_date<=?  
          and lastoptime>=?
          and username=?
          and (voidstatus is NULL or voidstatus='')
          and substr(auth_code,187,10)='open      '
          and (accttype is NULL or accttype='' or accttype='credit')
          order by orderid
dbEOM
  my @dbvalues = ( "$starttransdate", "$today", "$onemonthsagotime", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $mintrans_date = $today;

  my $petroamt     = 0;
  my $petrocnt     = 0;
  my %orderidarray = ();

  my %transarray = ();
  umask 0077;
  $logfilestr = "";

  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 20 ) {
    ( $orderid,   $operation,   $trans_date, $trans_time, $enccardnumber, $enclength, $exp,      $amount,     $auth_code,     $avs_code,
      $refnumber, $finalstatus, $cvvresp,    $transflags, $card_zip,      $card_addr, $authtime, $authstatus, $forceauthtime, $forceauthstatus
    )
      = @sthtransvalarray[ $vali .. $vali + 19 ];

    if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
      umask 0077;
      $logfilestr .= "stopgenfiles\n";
      unlink "/home/pay1/batchfiles/$devprod/paytechtampa2/batchfile.txt";
      last;
    }

    # don't include incomplete auths, balance inquiries
    if ( ( ( $operation eq "auth" ) && ( $finalstatus eq "pending" ) ) || ( $transflags =~ /balance/ ) ) {
      next;
    }

    ( $d1, $amount ) = split( / /, $amount );

    $petrocnt++;
    if ( $operation eq "return" ) {
      $petroamt = $petroamt - $amount;
    } else {
      $petroamt = $petroamt + $amount;
    }

    $day      = substr( $auth_code, 9,  3 );
    $batchnum = substr( $auth_code, 12, 6 );
    $class    = substr( $auth_code, 18, 1 );
    $seqnum   = substr( $auth_code, 19, 6 );
    $orderidarray{"$day$batchnum$seqnum"} = $orderid;

    $transarray{"$orderid"} = $seqnum;

    my $printstr = "$orderid $operation $seqnum $amount  $day $batchnum $seqnum  $class\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    my $logData = { 'orderid' => "$orderid", 'operation' => "$operation", 'seqnum' => "$seqnum", 'amount' => "$amount", 'day' => "$day", 'batchnum' => "$batchnum", 'seqnum' => "$seqnum", 'class' => "$class", 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

    $logfilestr .= "$orderid $operation $seqnum $amount  $day $batchnum $seqnum  $class\n";

  }
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  my $logData = { 'orderid' => "$orderid", 'operation' => "$operation", 'seqnum' => "$seqnum", 'amount' => "$amount", 'day' => "$day", 'batchnum' => "$batchnum", 'seqnum' => "$seqnum", 'class' => "$class", 'msg' => "$logfilestr" };
  &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

  $petroamt = $petroamt + 0.00;
  $result{'totalamt'} = $result{'totalamt'} + 0.00;

  $result{'totalcnt'} = sprintf( "%d", $result{'totalcnt'} );
  $petrocnt = sprintf( "%d", $petrocnt );

  $result{'totalamt'} = sprintf( "%.2f", $result{'totalamt'} );
  $petroamt = sprintf( "%.2f", $petroamt );

  my ($oid) = &miscutils::genorderid();
  my %result = &miscutils::sendmserver( "$username", "inquiry", "order-id", "$oid", "details", "no" );

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "petroleum inquiry $result{'FinalStatus'} $result{'MErrMsg'}\n";

  $logfilestr .= "Our numbers: $petrocnt $petroamt\n\n";
  $logfilestr .= "inquiry $result{'FinalStatus'} $result{'MErrMsg'}\n";
  $logfilestr .= "inquiry $result{'totalcnt'} $result{'totalamt'}\n\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  my $logData = { 'petrocnt' => "$petrocnt", 'petroamt' => "$petroamt", 'FinalStatus' => "$result{'FinalStatus'}", 'MErrMsg' => "$result{'MErrMsg'}", 'totalcnt' => "$result{'totalcnt'}", 'totalamt' => "$result{'totalamt'}", 'msg' => "$logfilestr" };
  &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

  my $printstr = "Our numbers: $petrocnt $petroamt\n\n";
  $printstr .= "inquiry $result{'FinalStatus'} $result{'MErrMsg'}\n";
  $printstr .= "inquiry $result{'totalcnt'} $result{'totalamt'}\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'petrocnt' => "$petrocnt", 'petroamt' => "$petroamt", 'FinalStatus' => "$result{'FinalStatus'}", 'MErrMsg' => "$result{'MErrMsg'}", 'totalcnt' => "$result{'totalcnt'}", 'totalamt' => "$result{'totalamt'}", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  if ( ( $petroamt != $result{'totalamt'} ) || ( $petrocnt != $result{'totalcnt'} ) ) {
    my $initial = "yes";
    for ( my $j = 0 ; $j < 9 ; $j++ ) {
      my %result = &miscutils::sendmserver( "$username", "inquiry", "order-id", "$oid", "details", "yes", "initial", "$initial" );
      $initial = "no";
      my $printstr = "inquiry2 $result{'FinalStatus'} $result{'MErrMsg'}\n";
      $printstr .= "inquiry2 $result{'FinalStatus'} $result{'MErrMsg'}\n";
      $printstr .= "inquiry2 $result{'totalcnt'} $result{'totalamt'}\n";
      $printstr .= "inquiry2 moredata: $result{'moredata'}\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
      my $logData = { 'FinalStatus' => "$result{'FinalStatus'}", 'MErrMsg' => "$result{'MErrMsg'}", 'totalcnt' => "$result{'totalcnt'}", 'totalamt' => "$result{'totalamt'}", 'moredata' => "$result{'moredata'}", 'msg' => "$printstr" };
      &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

      umask 0077;
      $logfilestr = "";
      $logfilestr .= "petroleum inquiry $result{'FinalStatus'} $result{'MErrMsg'}\n";

      for ( my $i = 0 ; $i < 2400 ; $i++ ) {
        if ( $result{"seqnum-$i"} eq "" ) {
          last;
        }
        $day      = $result{"day"};
        $batchnum = $result{"batchnum"};
        $seqnum   = $result{"seqnum-$i"};
        $logfilestr .=
            "inquiry "
          . $result{"day"} . " "
          . $result{"batchnum"} . " "
          . $result{"seqnum-$i"} . " "
          . $result{"authcode-$i"} . " "
          . $result{"ttype-$i"} . " "
          . $result{"amount-$i"} . " "
          . $result{"ctype-$i"} . " "
          . $orderidarray{"$day$batchnum$seqnum"} . "\n";

        my $printstr =
            "inquiry "
          . $result{"day"} . " "
          . $result{"batchnum"} . " "
          . $result{"seqnum-$i"} . " "
          . $result{"authcode-$i"} . " "
          . $result{"ttype-$i"} . " "
          . $result{"amount-$i"} . " "
          . $result{"ctype-$i"} . " "
          . $orderidarray{"$day$batchnum$seqnum"} . "\n";
        # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
        my $logData = {
          'day' => $result{"day"},
          'batchnum' => $result{"batchnum"},
          "seqnum-$i" => $result{"seqnum-$i"},
          "authcode-$i" => $result{"authcode-$i"},
          "ttype-$i" => $result{"ttype-$i"},
          "amount-$i" => $result{"amount-$i"},
          "ctype-$i" => $result{"ctype-$i"},
          'msg' => "$printstr"
        };
        &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
      }
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      my $logData = { 'msg' => "$logfilestr" };
      &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

      if ( $result{'moredata'} ne "M" ) {
        last;
      }
    }
  }

  $oid = &miscutils::incorderid($oid);
  my %result = &miscutils::sendmserver( "$username", "settle", "$order-id", "oid" );
  my $printstr = "settle $result{'FinalStatus'} $result{'MErrMsg'}\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );

  my $day      = $result{'day'};
  my $batchnum = $result{'batchnum'};
  $printstr .= "day $day  $batchnum\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
  my $logData = { 'FinalStatus' => "$result{'FinalStatus'}", 'MErrMsg' => "$result{'MErrMsg'}", 'day' => "$day", 'batchnum' => "$batchnum", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

  if ( $result{'FinalStatus'} eq "success" ) {
    my $authinfo = "$day$batchnum";

    my $printstr = "update trans_log  today $today  username $username  authinfo $authinfo\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    my $logData = { 'today' => "$today", 'username' => "$username", 'authinfo' => "$authinfo", 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
    my $dbquerystr = <<"dbEOM";
            update trans_log
            set result=?,auth_code=concat(substr(auth_code,1,186),'closed    ',substr(auth_code,197))
            where trans_date>=?
            and trans_date<=?  
            and username=?
            and substr(auth_code,187,10)='open      '
            and substr(auth_code,10,3)=?
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$authinfo", "$onemonthsago", "$today", "$username", "$day" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $printstr = "update operation_log\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    my $logData = { 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
    my $dbquerystr = <<"dbEOM";
            update operation_log
            set batchfile=?,auth_code=concat(substr(auth_code,1,186),'closed    ',substr(auth_code,197))
            where trans_date>=?
            and trans_date<=?  
            and lastoptime>=?
            and username=?
            and (voidstatus is NULL or voidstatus='')
            and substr(auth_code,187,10)='open      '
            and substr(auth_code,10,3)=?
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$authinfo", "$starttransdate", "$today", "$onemonthsagotime", "$username", "$day" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $printstr = "done with operation_log\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    my $logData = { 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );
  }

  $logfilestr = "";
  $logfilestr .= "petroleum settle $result{'FinalStatus'} $result{'MErrMsg'}\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  my $logData = { 'FinalStatus' => "$result{'FinalStatus'}", 'MErrMsg' => "$result{'MErrMsg'}", 'msg' => "$logfilestr" };
  &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );
  next;
}

sub pidcheck {
  my $chkline = &procutils::fileread( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "pid$mygroup.txt" );
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl $mygroup already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    my $logData = { 'mygroup' => "$mygroup", 'pidline' => "$pidline", 'chkline' => "$chkline", 'msg' => "$logfilestr" };
    &procutils::writeDataLog( $username, $logProc, "$username$time$pid", $logData );

    my $printstr = "genfiles.pl $mygroup already running, pid alterred by another program, exiting...\n";
    $printstr .= "$pidline\n";
    $printstr .= "$chkline\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "miscdebug.txt", "append", "misc", $printstr );
    my $logData = { 'mygroup' => "$mygroup", 'pidline' => "$pidline", 'chkline' => "$chkline", 'msg' => "$printstr" };
    &procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: paytechtampa2 - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl $mygroup already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

