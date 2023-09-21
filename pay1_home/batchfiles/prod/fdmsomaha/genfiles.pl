#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;
use smpsutils;
use Sys::Hostname;

$devprod = "logs";

if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/fdmsomaha/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdmsomaha/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsomaha - genfiles already running\n";
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
&procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "pid.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my $chkline = &procutils::fileread( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "pid.txt" );
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "$pidline\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "$chkline\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsomaha - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

my $checkuser = &procutils::fileread( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "genfiles.txt" );
chop $checkuser;

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>'$checkuser'";
}

# batch cutoff is 6pm central (7pm eastern) and 12am central

%errcode92 = (
  "2", "Invalid cardholder number",                            "3", "Invalid expiration date",        "5", "Invalid transaction type",
  "7", "Invalid amount field",                                 "8", "Invalid department code",        "A", "Invalid merchant number",
  "B", "Merchant not on file",                                 "C", "Closed merchant",                "D", "Invalid cardholder prefix",
  "E", "Communication link down",                              "F", "Wrong merchant type",            "G", "Cardholder not on file",
  "H", "Bank params not on file",                              "I", "Wrong merchant assessment code", "J", "Function unavailable",
  "K", "Invalid encrypted PIN field format",                   "L", "Invalid ATM terminal ID",        "M", "General message format problem",
  "N", "Invalid PIN block format or invalid PIN availability", "O", "ETC void is unmatched",          "P", "ETC primary CPU not available",
  "S", "Invalid SE number - amex on AR31",                     "X", "Duplicate auth request (from INAS)"
);

%errcode22 = (
  "A", "Authorization prohibited", "B", "Bankrupt account",       "C", "Closed account",           "D", "Delinquent account",          "E", "Revoked card",
  "F", "Frozen account",           "I", "Interest prohibited",    "L", "Lost card",                "O", "Overlimit",                   "U", "Stolen card",
  "X", "Delinquent and overlimit", "Y", "Decline auth flag",      "Z", "Charged-off account",      "1", "Account on warning bulletin", "2", "Over cash advance limit",
  "3", "Over cash advance total",  "4", "Over merchandise limit", "6", "Excessive authorizations", "7", "Under cash advance minimum"
);

%errcode02 = (
  "1", "Function not allowed for merchant", "2", "Out of balance",            "3", "Primary system unavailable",
  "4", "Function disabled for maintenance", "5", "No open batch in progress", "6", "Non-numeric count or amount"
);

%errcodetmp = (
  "01", "Invalid Transaction Code",
  "03", "Terminal ID not setup for settlement on this Card Type",
  "04", "Terminal ID not setup for authorization on this Card Type",
  "05", "Invalid Card Expiration Date",
  "06", "Invalid Process Code, Authorization Type or Card Type",
  "07", "Invalid Transaction or Other Dollar Amount",
  "08", "Invalid Entry Mode",
  "09", "Invalid Card Present Flag",
  "10", "Invalid Customer Present Flag",
  "11", "Invalid Transaction Count Value",
  "12", "Invalid Terminal Type",
  "13", "Invalid Terminal Capability",
  "14", "Invalid Source ID",
  "15", "Invalid Summary ID",
  "16", "Invalid Mag Stripe Data",
  "17", "Invalid Invoice Number",
  "18", "Invalid Transaction Date or Time",
  "19", "Invalid bankcard merchant number in First Data database",
  "20", "File access error in First Data database",
  "26", "Terminal flagged as Inactive in First Data database",
  "27", "Invalid Merchant/Terminal ID combination",
  "30", "Unrecoverable database error from an authorization process (usually means the Merchant/Terminal ID was already in use)",
  "31", "Database access lock encountered, Retry after 3 seconds",
  "33", "Database error in summary process, Retry after 3 seconds",
  "43", "Transaction ID invalid, incorrect or out of sequence",
  "51", "Terminal flagged as violated in First Data database (Call Customer Support)",
  "54", "Terminal ID not set up on First Data database for leased line access",
  "59", "Settle Trans for Summary ID where earlier Summary ID still open",
  "60", "Invalid account number found by authorization process, See Appendix B",
  "61", "Invalid settlement data found in summary process (trans level)",
  "62", "Invalid settlement data found in summary process (summary level)",
  "80", "Invalid Payment Service data found in summary process (trans level)",
  "98", "General system error"
);

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 * 6 ) );
$sixmonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 180 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 8 ) );
$onemonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";

$starttransdate = $sixmonthsago;

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $d1, $today, $time ) = &miscutils::genorderid();
$borderid = substr( "0" x 12 . $time, -12, 12 );

$runtime = substr( $time, 8, 2 );

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsomaha/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsomaha/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsomaha/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsomaha/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsomaha - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/fdmsomaha/$fileyear.\n\n";
  close MAILERR;
  exit;
}

my $printstr = "cccc\n";
&procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );

# xxxx
my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        and t.trans_date<=?
        $checkstring
        and t.finalstatus='pending'
        and (t.accttype is NULL or t.accttype='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastoptime>=?
        and o.lastopstatus='pending'
        and o.processor='fdmsomaha'
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $userdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );
  @userarray = ( @userarray, $user );
  $usercountarray{$user} = $usercount;
  $transdatearray{$user} = $userdate;
}

foreach $username ( sort @userarray ) {
  if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/fdmsomaha/stopgenfiles.txt" ) ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "stopgenfiles\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    unlink "/home/pay1/batchfiles/$devprod/fdmsomaha/batchfile.txt";
    last;
  }

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "genfiles.txt", "write", "", $checkinstr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $transdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  my $printstr = "$username $usercountarray{$username}\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );

  # no batches > 500 allowed
  if ( $usercountarray{$username} > 1000 ) {
    $batchcntuser = 500;
  } elsif ( $usercountarray{$username} > 600 ) {
    $batchcntuser = 200;
  } elsif ( $usercountarray{$username} > 300 ) {
    $batchcntuser = 100;
  } else {
    $batchcntuser = 50;
  }

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,switchtime
        from customers
        where username=?
        and processor='fdmsomaha'
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $status, $switchtime ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
        select batchtime
        from fdmsomaha
        where username=? 
dbEOM
  my @dbvalues = ("$username");
  ($batchtime) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $status ne "live" ) {
    next;
  }

  $batch_flag = 1;
  $batchid    = "000";

  $errorflag = 0;

  my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,card_addr,card_zip,authtime,authstatus,forceauthtime,forceauthstatus
          from operation_log
          where trans_date>=?
          and trans_date<=?
          and lastoptime>=?
          and username=?
          and lastop in ('postauth','return')
          and lastopstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype='' or accttype='credit')
          order by orderid
dbEOM
  my @dbvalues = ( "$starttransdate", "$today", "$onemonthsagotime", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 20 ) {
    ( $orderid,   $operation,   $trans_date, $trans_time, $enccardnumber, $enclength, $exp,      $amount,     $auth_code,     $avs_code,
      $refnumber, $finalstatus, $cvvresp,    $transflags, $card_addr,     $card_zip,  $authtime, $authstatus, $forceauthtime, $forceauthstatus
    )
      = @sthtransvalarray[ $vali .. $vali + 19 ];

    if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/fdmsomaha/stopgenfiles.txt" ) ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "stopgenfiles\n";
      &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      unlink "/home/pay1/batchfiles/$devprod/fdmsomaha/batchfile.txt";
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

    if ( $switchtime ne "" ) {
      $switchtime = substr( $switchtime . "0" x 14, 0, 14 );
      if ( ( $operation eq "postauth" ) && ( $authtime ne "" ) && ( $authtime < $switchtime ) ) {
        next;
      }
    }

    my $dbquerystr = <<"dbEOM";
          select origamount
          from operation_log
          where orderid=?
          and trans_date>=?
          and username=?
          and (authstatus='success'
          or forceauthstatus='success')
dbEOM
    my @dbvalues = ( "$orderid", "$sixmonthsago", "$username" );
    ($origamount) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "fdmsomaha", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );
    $card_type = &smpsutils::checkcard($cardnumber);

    $errflag = &errorchecking();
    if ( $errflag == 1 ) {
      next;
    }

    umask 0077;
    $logfilestr = "";
    $tmp = substr( $cardnumber, 0, 2 );
    $logfilestr .= "$orderid $operation $transflags $tmp\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    if ( $batch_flag == 1 ) {
      &pidcheck();
      $datasentflag    = 0;
      $socketerrorflag = 0;
      $dberrorflag     = 0;
      $batcherrorflag  = 0;
      $batchcnt        = 0;
      $recseqnum       = 0;
      $totalamt        = 0;
      $totalcnt        = 0;
      $batch_flag      = 0;
      $batchid         = sprintf( "%03d", $batchid + 1 );
      $problemstr      = '';
      $orderidstr      = '';
      %orderidhash     = ();
    }

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='locked',result=?
            where orderid=?
	    and trans_date>=?
	    and username=?
	    and finalstatus in ('pending','locked')
dbEOM
    my @dbvalues = ( "$time$batchid", "$orderid", "$onemonthsago", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending'
          where orderid=?
          and username=?
          and $operationstatus in ('pending','locked')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time$batchid", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    &batchdetail();
    $response = &sendrecord($message);
    &process_detail();

    if ( $batchcnt >= $batchcntuser ) {
      &batchcheck();
      $response = &sendrecord($message);
      if ( $response eq "" ) {
        &miscutils::mysleep(5);
        $response = &sendrecord($message);
      }
      &endcheck();

      if ( $result eq "A" ) {
        &batchtrailer();
        $response = &sendrecord($message);
        if ( $response eq "" ) {
          &miscutils::mysleep(5);
          $response = &sendrecord($message);
        }
        &endbatch();
        &fixproblemstr();
      }
      $batch_flag = 1;
      $batchcnt   = 0;
    }

    if ( $socketerrorflag == 1 ) {
      last;    # if socket error stop altogether
    }
    if ( $batcherrorflag == 1 ) {
      last;    # if socket error stop altogether
    }

  }

  if ( $batchcnt >= 1 ) {
    &batchcheck();
    $response = &sendrecord($message);
    if ( $response eq "" ) {
      &miscutils::mysleep(5);
      $response = &sendrecord($message);
    }
    &endcheck();

    if ( $result eq "A" ) {
      &batchtrailer();
      $response = &sendrecord($message);
      if ( $response eq "" ) {
        &miscutils::mysleep(5);
        $response = &sendrecord($message);
      }
      &endbatch();
      &fixproblemstr();
    }
    $batch_flag = 1;
    $batchcnt   = 0;
  }

  if ( $batcherrorflag == 1 ) {
    unlink "/home/pay1/batchfiles/$devprod/fdmsomaha/batchfile.txt";
    exit;
  }

}

unlink "/home/pay1/batchfiles/$devprod/fdmsomaha/batchfile.txt";

if ( ( !-e "/home/pay1/batchfiles/stopgenfiles.txt" ) && ( !-e "/home/pay1/batchfiles/$devprod/fdmsomaha/stopgenfiles.txt" ) && ( $socketerrorflag == 0 ) ) {
  umask 0033;
  $checkinstr = "";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "genfiles.txt", "write", "", $checkinstr );
}

exit;

sub mysleep {
  for ( $myi = 0 ; $myi <= 60 ; $myi++ ) {
    umask 0033;
    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "baccesstime.txt", "write", "", $outfilestr );

    select undef, undef, undef, 60.00;
  }
}

sub senderrmail {
  my ($message) = @_;

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: FDMSOMAHA - batch problem\n";
  print MAILERR "\n";
  print MAILERR "Username: $username\n";
  print MAILERR "\nLocked transactions found in trans_log and summaryid's did not match.\n";
  print MAILERR " Or batch out of balance.\n\n";
  print MAILERR "$message.\n\n";
  print MAILERR "chksummaryid: $chksummaryid    summaryid: $summaryid\n";
  close MAILERR;

}

sub process_detail {

  my $chktcode = substr( $response, 2, 4 );

  $d1            = "";
  $tcode         = "";
  $refnumber     = "";
  $user1         = "";
  $result        = "";
  $transtype     = "";
  $auth_code     = "";
  $merchnum      = "";
  $chkcardnum    = "";
  $chkauthamt    = "";
  $declinereason = "";
  $phone         = "";
  $aci           = "";
  $chktransid    = "";
  $valcode       = "";
  $respcode      = "";
  $avs           = "";
  $cvvresp       = "";
  $settledate    = "";
  $posediterror  = "";

  if ( $chktcode eq "AR22" ) {
    ( $d1,            $tcode, $refnumber, $user1,      $usercntrl, $result,   $transtype, $auth_code, $merchnum,   $chkcardnum, $chkauthamt,
      $declinereason, $phone, $aci,       $chktransid, $valcode,   $respcode, $avs,       $cvvresp,   $settledate, $posediterror
    )
      = unpack "nA4A6A8A16A1A1A6A16A16A8A1A14A1A15A4A2A1A1A4A1", $response;
    $descr = "$declinereason: $errcode22{$declinereason}";
  } elsif ( $chktcode eq "AR92" ) {
    $result = "92";
    ( $d1, $tcode, $refnumber, $user1, $declinereason ) = unpack "nA4A6A8A1A1", $response;
    $descr = "$declinereason: $errcode92{$declinereason}";
  }

  $chktransid =~ s/ //g;
  $transid =~ s/ //g;
  $cardnum =~ s/ //g;
  $chkcardnum =~ s/ //g;

  my $mytime = gmtime( time() );
  umask 0077;
  $logfilestr = "";

  $logfilestr .= "$mytime\n";
  $logfilestr .= "refnumber: $refnumber\n";

  $logfilestr .= "result: $result\n";
  $logfilestr .= "transtype: $transtype\n";
  $logfilestr .= "auth_code: $auth_code\n";

  $logfilestr .= "declinereason: $declinereason\n";
  $logfilestr .= "descr: $descr\n";

  $logfilestr .= "chktransid: $chktransid\n";

  $logfilestr .= "respcode: $respcode\n";

  $logfilestr .= "posediterror: $posediterror\n";
  $logfilestr .= "\n\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  if (
    ( $result eq "A" ) && (
      ( $chktransid eq $transid )    # normal
      || ( ( $chkcardnum eq $cardnum ) && ( $chkauthamt eq $transamount ) )
    )
    ) {                              # returns and discover cards
    if ( $operation eq "return" ) {
      $totalamt = $totalamt - $transamt;
    } else {
      $totalamt = $totalamt + $transamt;
    }
    $totalcnt = $totalcnt + 1;

    $orderidstr = $orderidstr . $orderid . ",";
    $orderidhash{"$orderid"} = $operation;
    print "orderidstr: $orderidstr\n\n";
  } elsif ( ( $result eq "92" ) && ( $declinereason eq "J" ) ) {
    my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='pending'
          where orderid=?
          and trans_date>=?
          and result=?
          and username=?
          and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$orderid", "$onemonthsago", "$time$batchid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='pending',lastopstatus='pending'
            where orderid=?
            and batchfile=?
            and username=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$time$batchid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  } elsif ( ( $result eq "R" ) || ( ( $result eq "92" ) && ( $declinereason ne "J" ) ) ) {
    my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='problem',descr=?
          where orderid=?
          and trans_date>=?
          and result=?
          and username=?
          and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$descr", "$orderid", "$onemonthsago", "$time$batchid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and batchfile=?
            and username=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$descr", "$orderid", "$time$batchid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch detail: $descr\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  } elsif ( $result eq "A" ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch detail: response mismatch\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    &senderrmail("Error in batch detail: $username$time$pid.txt\n  response mismatch, genfiles terminated\n");
    $batcherrorflag = 1;
  } else {
    $problemstr = $problemstr . "'" . $orderid . "',";

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Trans id does not match: $transid $chktransid\n";
    $logfilestr .= "aaaa $chktransidold\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    $batcherrorflag = 1;
  }
  $chktransidold = $chktransid;
}

sub fixproblemstr {

  %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr", "problemstr", "$problemstr" );

  if ( $problemstr ne "" ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus=?
            where orderid in ($problemstr)
            and username=?
            and trans_date>=?
            and result=?
            and finalstatus='success'
dbEOM
    my @dbvalues = ( "$problemstrstatus", "$username", "$onemonthsago", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
              update operation_log set postauthstatus=?,lastopstatus=?
              where orderid in ($problemstr)
              and username=?
              and lastopstatus='success'
              and lastop='postauth'
              and batchfile=?
              and (voidstatus is NULL or voidstatus ='')
              and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$problemstrstatus", "$problemstrstatus", "$username", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
              update operation_log set returnstatus=?,lastopstatus=?
              where orderid in ($problemstr)
              and username=?
              and lastopstatus='success'
              and lastop='return'
              and batchfile=?
              and (voidstatus is NULL or voidstatus ='')
              and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$problemstrstatus", "$problemstrstatus", "$username", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  }
}

sub endcheck {
  my $chktcode = substr( $response, 2, 4 );

  $d1            = "";
  $tcode         = "";
  $refnumber     = "";
  $user1         = "";
  $result        = "";
  $declinereason = "";
  $depositdate   = "";
  $batchcount    = "";
  $batchamt      = "";
  $descr         = "";

  if ( $chktcode eq "AR92" ) {
    $result = "92";
    ( $d1, $tcode, $refnumber, $user1, $declinereason ) = unpack "nA4A6A8A1A1", $response;
    $descr = "$declinereason: $errcode92{$declinereason}";
  } elsif ( $chktcode eq "MT02" ) {
    ( $d1, $tcode, $refnumber, $user1, $result ) = unpack "nA4A6A8A1", $response;
    if ( $result eq "A" ) {
      ( $d1, $tcode, $refnumber, $user1, $result, $depositdate, $batchcount, $batchamt, $batchsign ) = unpack "nA4A6A8A1A4A5A9A1", $response;
    } else {
      ( $d1, $tcode, $refnumber, $user1, $result, $declinereason ) = unpack "nA4A6A8A1A1", $response;
      $descr = "$declinereason: $errcode03{$declinereason}";
    }
  }

  $batchamount = sprintf( "%.2f", ( $batchamt / 100 ) + .0001 );
  $batchamount = $batchsign . $batchamount;

  $totalamt = sprintf( "%.2f", $totalamt + .0001 );

  my $mytime = gmtime( time() );
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$mytime\n";
  $logfilestr .= "Our results: $totalcnt $totalamt\n";
  $logfilestr .= "Query results:\n";
  $logfilestr .= "tcode: $chktcode\n";
  $logfilestr .= "result: $result\n";
  $logfilestr .= "declinereason: $declinereason $descr\n";
  $logfilestr .= "depositdate: $depositdate\n";
  $logfilestr .= "batchcount: $batchcount\n";
  $logfilestr .= "batchamt: $batchsign $batchamt\n\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  $batchcount = $batchcount + 0;

  $problemstrstatus = "locked";

  chop $problemstr;
  if ( ( $batchamount != $totalamt ) || ( $batchcount != $totalcnt ) ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "problemstr: $problemstr\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

    if ( $problemstr ne "" ) {
      my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem'
            where orderid in ($problemstr)
            and username=?
            and trans_date>=?
            and result=?
            and finalstatus='pending'
dbEOM
      my @dbvalues = ( "$username", "$onemonthsago", "$time$batchid" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      my $dbquerystr = <<"dbEOM";
              update operation_log set postauthstatus='problem',lastopstatus='problem'
              where orderid in ($problemstr)
              and username=?
              and lastopstatus='pending'
              and lastop='postauth'
              and batchfile=?
              and (voidstatus is NULL or voidstatus ='')
              and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$username", "$time$batchid" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      my $dbquerystr = <<"dbEOM";
              update operation_log set returnstatus='problem',lastopstatus='problem'
              where orderid in ($problemstr)
              and username=?
              and lastopstatus='pending'
              and lastop='return'
              and batchfile=?
              and (voidstatus is NULL or voidstatus ='')
              and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$username", "$time$batchid" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    }

    &senderrmail("Batch count/amounts differ:\n  Ours:   $totalcnt   $totalamt\n  Theirs: $batchcount   $batchamount\n");
  } elsif ( ( $batchamount == $totalamt ) && ( $batchcount == $totalcnt ) ) {
    $problemstrstatus = 'pending';
  }
}

sub endbatch {

  my $chktcode = substr( $response, 2, 4 );

  $d1            = "";
  $tcode         = "";
  $refnumber     = "";
  $user1         = "";
  $result        = "";
  $transtype     = "";
  $auth_code     = "";
  $merchnum      = "";
  $chkcardnum    = "";
  $chkauthamt    = "";
  $declinereason = "";
  $phone         = "";
  $aci           = "";
  $chktransid    = "";
  $valcode       = "";
  $respcode      = "";
  $avs           = "";
  $cvvresp       = "";
  $settledate    = "";
  $posediterror  = "";

  if ( $chktcode eq "AR22" ) {
    ( $d1,            $tcode, $refnumber, $user1,      $result,  $transtype, $auth_code, $merchnum, $chkcardnum, $chkauthamt,
      $declinereason, $phone, $aci,       $chktransid, $valcode, $respcode,  $avs,       $cvvresp,  $settledate, $posediterror
    )
      = unpack "nA4A6A8A1A1A6A16A16A8A1A14A1A15A4A2A1A1A4A1", $response;
    $descr = "$declinereason: $errcode22{$declinereason}";
  } elsif ( $chktcode eq "AR92" ) {
    $result = "92";
    ( $d1, $tcode, $refnumber, $user1, $declinereason ) = unpack "nA4A6A8A1A1", $response;
    $descr = "$declinereason: $errcode92{$declinereason}";
  } elsif ( $chktcode eq "MQ02" ) {
    ( $d1, $tcode, $refnumber, $user1, $result, $declinereason ) = unpack "nA4A6A8A1A1", $response;
    $descr = "$declinereason: $errcode02{$declinereason}";
  }

  my $mytime = gmtime( time() );
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$mytime\n";
  $logfilestr .= "refnumber: $refnumber\n";

  $logfilestr .= "result: $result\n";
  $logfilestr .= "transtype: $transtype\n";
  $logfilestr .= "auth_code: $auth_code\n";

  $logfilestr .= "declinereason: $declinereason\n";
  $logfilestr .= "descr: $descr\n";

  $logfilestr .= "chktransid: $chktransid\n";

  $logfilestr .= "respcode: $respcode\n";

  $logfilestr .= "posediterror: $posediterror\n";
  $logfilestr .= "\n\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  if ( $result eq "A" ) {

    ( $d1, $today, $ptime ) = &miscutils::genorderid();

    foreach my $orderidupd ( sort keys %orderidhash ) {
      my $operationupd = $orderidhash{"$orderidupd"};

      my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?
            where orderid=?
            and operation=?
            and trans_date>=?
            and trans_date<=?
	    and username=?
	    and result=?
            and (accttype is NULL or accttype='' or accttype='credit')
	    and finalstatus='locked'
dbEOM
      my @dbvalues = ( "$ptime", "$orderidupd", "$operationupd", "$onemonthsago", "$today", "$username", "$time$batchid" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$orderidupd", "username", "$username", "operation", "$operationupd", "descr", "$descr" );

      if ( $operationupd eq "postauth" ) {
        my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
            where orderid=?
            and lastop=?
            and trans_date>=?
            and trans_date<=?
            and lastoptime>=?
            and batchfile=?
            and username=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
        my @dbvalues = ( "$ptime", "$ptime", "$orderidupd", "$operationupd", "$starttransdate", "$today", "$onemonthsagotime", "$time$batchid", "$username" );
        &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      } else {

        my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
            where orderid=?
            and lastop=?
            and trans_date>=?
            and trans_date<=?
            and lastoptime>=?
            and batchfile=?
            and username=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
        my @dbvalues = ( "$ptime", "$ptime", "$orderidupd", "$operationupd", "$starttransdate", "$today", "$onemonthsagotime", "$time$batchid", "$username" );
        &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
      }
    }

    my $mytime = gmtime( time() );
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$mytime\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  }

  elsif ( $result eq "92" ) {
    my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='problem',descr=?
          where trans_date>=?
          and username=?
          and result=?
          and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$descr", "$onemonthsago", "$username", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

    my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?
            where trans_date>=?
            and trans_date<=?
            and lastoptime>=?
            and batchfile=?
            and username=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$descr", "$starttransdate", "$today", "$onemonthsagotime", "$time$batchid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='problem',lastopstatus='problem',descr=?
            where trans_date>=?
            and trans_date<=?
            and lastoptime>=?
            and batchfile=?
            and username=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$descr", "$starttransdate", "$today", "$onemonthsagotime", "$time$batchid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch detail: $descr\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
  }
}

sub batchdetail {
  $batchcnt++;
  $transamt = sprintf( "%.2f", substr( $amount, 4 ) + .0001 );

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
      &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
      $socketerrorflag = 1;
      $dberrorflag     = 1;
      return;
    }
  }

  $datasentflag = 1;

  @bd = ();

  # xxxx added motoind 04/05/2005   the if authtype is not an error  it's to check for the latest version
  $authtype = substr( $auth_code, 66, 1 );
  $magstripetrack = "";
  if ( $authtype =~ /^(T|R)$/ ) {
    $magstripetrack = substr( $auth_code, 68, 1 );
  }

  if ( ( $transflags =~ /retail/ ) && ( ( $authtype eq "" ) || ( $magstripetrack =~ /^(1|2)$/ ) ) ) {

    $bd[0] = "AT21";                # transaction code (4a) 1
    $bd[1] = "000000";              # reference number (6n) 3
    $bd[2] = "00000000";            # user area (8n) 4
    $bd[3] = "CNTL011AYY      ";    # user control area (16n)
    $mid = substr( $merchant_id . " " x 16, 0, 16 );
    $bd[4] = $mid;                  # merchant number (16n) 5
    $cardnum = substr( $cardnumber . " " x 16, 0, 16 );
    $bd[5] = $cardnum;              # cardholder account (16n) 6
    $expdate = substr( $exp, 0, 2 ) . substr( $exp, 3, 2 );
    $expdate = substr( $expdate . " " x 4, 0, 4 );
    $bd[6] = $expdate;              # expiration date (4n) 7

    if ( ( $operation eq "postauth" ) && ( $origoperation ne "forceauth" ) ) {
      $posind = substr( $auth_code, 65, 1 );
    } else {
      $posind = "T";
    }
    $bd[7] = $posind;               # POS indicator (1a) 8
    $bd[8] = "R";                   # authorization type (1a) 9
    $transamount = sprintf( "%.2f", substr( $amount, 4 ) + .0001 );
    $transamount = sprintf( "%08d", ( $transamount * 100 ) + .0001 );
    $bd[9] = $transamount;          # authorization amount (8a) 11
    if ( $operation eq "return" ) {
      $bd[10] = "2";                # transaction type 2=credit (1a) 25
    } else {
      $bd[10] = "3";                # transaction type 3=ticket only (1a) 25
    }

    $magstripetrack = "0";
    $bd[11]         = $magstripetrack;    # track data indicator (1a) 22
    $maglen         = "00";
    $bd[12]         = $maglen;            # track data length (2a) 23
    $magstripe      = " " x 76;
    $bd[13]         = $magstripe;         # track data (76a) 24

    $tid = substr( $terminal_id . " " x 4, 0, 4 );
    $bd[14] = $tid;                       # terminal identifier (4a) 26
    $bd[15] = '6';                        # etc plus charge type (1a) 60
    $aci = substr( $auth_code, 12, 1 );
    $aci = substr( $aci . " ", 0,  1 );
    $bd[16] = $aci;                       # aci indicator (1a) 17
    $oid = substr( $orderid,        -25, 25 );
    $oid = substr( $oid . " " x 25, 0,   25 );
    $bd[17] = $oid;                       # industry interchange data (25a) 80

    if ( $operation eq "return" ) {
      $transamount2 = sprintf( "%.2f", substr( $amount, 4 ) + .0001 );
      $transamount2 = sprintf( "%09d", ( $transamount2 * 100 ) + .0001 );
    } else {
      $transamount2 = sprintf( "%.2f", substr( $origamount, 4 ) + .0001 );
      $transamount2 = sprintf( "%09d", ( $transamount2 * 100 ) + .0001 );
    }
    $bd[18] = $transamount2;              # total authorized amount (9a) 84
    $tax = substr( $auth_code, 36, 9 );
    $tax = sprintf( "%09d", ( $tax * 100 ) + .0001 );
    $bd[19] = $tax;                       # retail tax amount (9a) 85
    $bd[20] = " " x 17;                   # customer code (17a) 95

    $descrcodes = substr( $auth_code,             45, 16 );
    $descrcodes = substr( $descrcodes . " " x 16, 0,  16 );
    $bd[21] = $descrcodes;                # descriptor codes 2 (16a) 29

    $retailterms = substr( $auth_code,             61, 4 );
    $retailterms = substr( $retailterms . " " x 4, 0,  4 );
    $bd[22] = $retailterms;               # retail terms (4a) 74

    $transid = substr( $auth_code,          13, 15 );
    $transid = substr( $transid . " " x 15, 0,  15 );
    $bd[23] = $transid;                   # transaction identifier (15a) 18
    $valcode = substr( $auth_code,         28, 4 );
    $valcode = substr( $valcode . " " x 4, 0,  4 );
    $bd[24] = $valcode;                   # ps2000 validation code (4a) 19
    $settledate = substr( $auth_code,            32, 4 );
    $settledate = substr( $settledate . " " x 4, 0,  4 );
    $bd[25] = $settledate;                # settlement date (4n) 77

    my $surchargesign = substr( $auth_code, 69, 1 );
    my $surcharge     = substr( $auth_code, 70, 8 );
    if ( ( $surcharge eq "" ) || ( $surcharge eq "        " ) || ( $surcharge eq "00000000" ) || ( $surchargesign eq "0" ) ) {
      $surchargesign = " ";
      $surcharge     = "        ";
    }
    $bd[26] = $surchargesign;             # surcharge sign (1n)
    $bd[27] = $surcharge;                 # surcharge amount (8n)
  } else {
    $bd[0] = "AR21";                      # transaction code (4a) 1
    $bd[1] = "000000";                    # reference number (6n) 3
    $bd[2] = "00000000";                  # user area (8n) 4
    $bd[3] = "CNTL011AYY      ";          # user control area (16n)
    $mid = substr( $merchant_id . " " x 16, 0, 16 );
    $bd[4] = $mid;                        # merchant number (16n) 5
    $cardnum = substr( $cardnumber . " " x 16, 0, 16 );
    $bd[5] = $cardnum;                    # cardholder account (16n) 6
    $expdate = substr( $exp, 0, 2 ) . substr( $exp, 3, 2 );
    $expdate = substr( $expdate . " " x 4, 0, 4 );
    $bd[6] = $expdate;                    # expiration date (4n) 7
    $bd[7] = "T";                         # POS indicator (1a) 8
                                          # xxxx added authtype 04/05/2005
    $authtype = substr( $auth_code, 66, 1 );

    if ( $authtype =~ /^(T|R)$/ ) {
      $bd[8] = $authtype;                 # authorization type (1a) 9
    } else {
      $bd[8] = "T";                       # authorization type (1a) 9
    }
    $transamount = sprintf( "%.2f", substr( $amount, 4 ) + .0001 );
    $transamount = sprintf( "%08d", ( $transamount * 100 ) + .0001 );
    $bd[9] = $transamount;                # authorization amount (8a) 11
    if ( $operation eq "return" ) {
      $bd[10] = "2";                      # transaction type 2=credit (1a) 25
    } else {
      $bd[10] = "3";                      # transaction type 3=ticket only (1a) 25
    }

    if ( $transflags =~ /recurring/ ) {
      $bd[11] = "00";                     # avs indicator - 00=no avs (2a) 54
      $bd[12] = "     ";                  # avs address 1 (5a) 53
      $bd[13] = " " x 9;                  # avs zip code (9a) 52
    } else {
      $bd[11] = "01";                     # avs indicator - 01=avs (2a) 54

      $cardaddr = $card_addr;
      $cardaddr =~ s/[^0-9]//g;
      $cardaddr = substr( $cardaddr . " " x 5, 0, 5 );
      $bd[12] = $cardaddr;                # avs address 1 (5a) 53

      $zip = $card_zip;
      $zip =~ s/[^0-9]//g;
      $zip = substr( $zip . " " x 9, 0, 9 );
      $bd[13] = $zip;                     # avs zip code (9a) 52
    }

    # xxxx 04/05/2005  added  if retail  space
    if ( $transflags =~ /recurring/ ) {
      $bd[14] = "2";                      # moto indicator (1a) 75 recurring
                                          #$bd[15] = "     ";                         # cvv presence indicator, value (5a) 102,103
    } elsif ( $transflags =~ /moto/ ) {
      $bd[14] = "1";                      # moto indicator (1a) 75 moto
                                          #$bd[15] = "     ";                         # cvv presence indicator, value (5a) 102,103
    } elsif ( ( $transflags !~ /moto|recurring/ ) && ( $card_type eq "mc" ) ) {
      $bd[14] = "6";                      # moto indicator (1a) 75 mastercard ecommerce
                                          #$bd[15] = $cvvdata;                        # cvv presence indicator, value (5a) 102,103
    } else {
      $bd[14] = "7";                      # moto indicator (1a) 75
                                          #if ($cardtype =~ /^(012|112)$/) {
                                          #  $bd[15] = $cvvdata;                      # cvv presence indicator, value (5a) 102,103
                                          #}
                                          #else {
                                          #  $bd[15] = "     ";                       # cvv presence indicator, value (5a) 102,103
                                          #}
    }

    # xxxx added motoind 04/05/2005   the if authtype is not an error  it's to check for the latest version
    $motoind = substr( $auth_code, 67, 1 );
    if ( $authtype =~ /^(T|R)$/ ) {
      $bd[14] = $motoind;                 # moto indicator (1a) 75
    }

    $tid = substr( $terminal_id . " " x 4, 0, 4 );
    $bd[15] = $tid;                       # terminal identifier (4a) 26

    $bd[16] = "     ";                    # cvv presence indicator, value (5a) 102,103
                                          # Scott McNaughton says cvv data should not be sent for settlement 02/22/2002
    $bd[17] = '6';                        # etc plus charge type (1a) 60
    $aci = substr( $auth_code, 12, 1 );
    $aci = substr( $aci . " ", 0,  1 );
    $bd[18] = $aci;                       # aci indicator (1a) 17
    $oid = substr( $orderid,        -25, 25 );
    $oid = substr( $oid . " " x 25, 0,   25 );
    $bd[19] = $oid;                       # industry interchange data (25a) 80

    if ( $operation eq "return" ) {
      $transamount2 = sprintf( "%.2f", substr( $amount, 4 ) + .0001 );
      $transamount2 = sprintf( "%09d", ( $transamount2 * 100 ) + .0001 );
    } else {
      $transamount2 = sprintf( "%.2f", substr( $origamount, 4 ) + .0001 );
      $transamount2 = sprintf( "%09d", ( $transamount2 * 100 ) + .0001 );
    }
    $bd[20] = $transamount2;              # total authorized amount (9a) 84
    $tax = substr( $auth_code, 36, 9 );
    $tax = sprintf( "%09d", ( $tax * 100 ) + .0001 );
    $bd[21] = $tax;                       # retail tax amount (9a) 85
    $bd[22] = " " x 17;                   # customer code (17a) 95

    $descrcodes = substr( $auth_code,             45, 16 );
    $descrcodes = substr( $descrcodes . " " x 16, 0,  16 );
    $bd[23] = $descrcodes;                # descriptor codes 2 (16a) 29

    $retailterms = substr( $auth_code,             61, 4 );
    $retailterms = substr( $retailterms . " " x 4, 0,  4 );
    $bd[24] = $retailterms;               # retail terms (4a) 74

    $avs = substr( $avs_code . " ", 0, 1 );
    $bd[25] = $avs;                       # avs response (1a) 55
    $transid = substr( $auth_code,          13, 15 );
    $transid = substr( $transid . " " x 15, 0,  15 );
    $bd[26] = $transid;                   # transaction identifier (15a) 18
    $valcode = substr( $auth_code,         28, 4 );
    $valcode = substr( $valcode . " " x 4, 0,  4 );
    $bd[27] = $valcode;                   # ps2000 validation code (4a) 19
    $settledate = substr( $auth_code,            32, 4 );
    $settledate = substr( $settledate . " " x 4, 0,  4 );
    $bd[28] = $settledate;                # settlement date (4n) 77
    $bd[29] = "  ";                       # card cert serial length (2a) 96
    $bd[30] = " " x 32;                   # card cert serial (32a) 97
    $bd[31] = "  ";                       # merch cert serial length (2a) 98
    $bd[32] = " " x 32;                   # merch cert serial (32a) 99
    $bd[33] = " " x 40;                   # xid (40a) 100
    $bd[34] = " " x 40;                   # tran stain (40a) 101

    my $surchargesign = substr( $auth_code, 69, 1 );
    my $surcharge     = substr( $auth_code, 70, 8 );
    if ( ( $surcharge eq "" ) || ( $surcharge eq "        " ) || ( $surcharge eq "00000000" ) || ( $surchargesign eq "0" ) ) {
      $surchargesign = " ";
      $surcharge     = "        ";
    }
    $bd[35] = $surchargesign;             # surcharge sign (1n)
    $bd[36] = $surcharge;                 # surcharge amount (8n)
  }

  $message = "";
  foreach $var (@bd) {
    $message = $message . $var;
  }

  $length    = length($message) + 2;
  $tcpheader = pack "n", $length;
  $message   = $tcpheader . $message;

}

sub batchcheck {
  $recseqnum = $recseqnum + 2;
  $recseqnum = substr( $recseqnum, -8, 8 );

  @bt    = ();
  $bt[0] = "MT03";                                     # transaction code (4a) 1
  $bt[1] = "000000";                                   # reference number (6n) 3
  $bt[2] = "00000000";                                 # user area (8n) 4
                                                       #$bt[3] = "CNTL011AYY      ";               # user control area (16n)
  $mid   = substr( $merchant_id . " " x 16, 0, 16 );
  $bt[4] = $mid;                                       # merchant number (16n) 5
  $tid   = substr( $terminal_id . " " x 4, 0, 4 );
  $bt[5] = $tid;                                       # terminal identifier (4a) 26

  $message = "";
  foreach $var (@bt) {
    $message = $message . $var;
  }

  $length    = length($message) + 2;
  $tcpheader = pack "n", $length;
  $message   = $tcpheader . $message;

}

sub batchtrailer {
  $recseqnum = $recseqnum + 2;
  $recseqnum = substr( $recseqnum, -8, 8 );

  @bt       = ();
  $bt[0]    = "MQ05";                                     # transaction code (4a) 1
  $bt[1]    = "000000";                                   # reference number (6n) 3
  $bt[2]    = "00000000";                                 # user area (8n) 4
                                                          #$bt[3] = "CNTL011AYY      ";               # user control area (16n)
  $mid      = substr( $merchant_id . " " x 16, 0, 16 );
  $bt[4]    = $mid;                                       # merchant number (16n) 5
  $tid      = substr( $terminal_id . " " x 4, 0, 4 );
  $bt[5]    = $tid;                                       # terminal identifier (4a) 26
  $totalcnt = substr( "0" x 5 . $totalcnt, -5, 5 );
  $bt[6]    = "$totalcnt";                                # batch item count (5n)
  $sign     = "+";
  if ( $totalamt < 0 ) {
    $totalamt = 0 - $totalamt;
    $sign     = "-";
  }
  $totalamt = sprintf( "%d", ( $totalamt * 100 ) + .0001 );
  $totalamt = substr( "0" x 11 . $totalamt, -11, 11 );
  $bt[7] = "$totalamt";                                   # batch dollar amount (11$)
  $bt[8] = "$sign";                                       # sign (1a)
  $batchnum = substr( "0" x 5 . $batchnum, -8, 8 );
  $bt[9] = "$batchnum";                                   # batch number (8n)

  $message = "";
  foreach $var (@bt) {
    $message = $message . $var;
  }

  $length    = length($message) + 2;
  $tcpheader = pack "n", $length;
  $message   = $tcpheader . $message;

}

sub sendrecord {
  my ($message) = @_;
  my $printstr = "message: $message\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );
  $response = "";

  $checkmessage = $message;
  $cnum         = "";
  if ( $checkmessage =~ /^..A[RT]21/ ) {
    $cnum = substr( $checkmessage, 52, 16 );
    $cnum =~ s/ //g;
    $cnumlen = length($cnum);
    if ( ( $cnumlen >= 12 ) && ( $cnumlen <= 19 ) ) {
      $xs = "x" x $cnumlen;
      $checkmessage =~ s/$cnum/$xs/;
    }
  }
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$checkmessage\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  $processid = $$;
  my $hostnm = hostname;
  $hostnm =~ s/[^0-9a-zA-Z]//g;
  $processid = $processid . $hostnm;

  ( $status, $invoicenum, $response ) = &procutils::sendprocmsg( "$processid", "fdmsomaha", "$username", "$borderid", "$message" );

  if ( $response eq "failure" ) {
    $response = "";
  }

  $checkmessage = $response;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $checkmessage =~ s/$cnum/$xs/;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$checkmessage\n\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  return $response;
}

sub errorchecking {

  # check for bad card numbers
  if ( ( $enclength > 1024 ) || ( $enclength < 30 ) ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr='could not decrypt card'
            where orderid=?
            and trans_date>=?
            and username=?
            and finalstatus='pending'
dbEOM
    my @dbvalues = ( "$orderid", "$onemonthsago", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr='could not decrypt card'
            where orderid=?
            and username=?
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    return 1;
  }

  $mylen = length($cardnumber);
  if ( ( $mylen < 13 ) || ( $mylen > 20 ) ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr='bad card length'
            where orderid=?
            and trans_date>=?
            and username=?
            and finalstatus='pending'
dbEOM
    my @dbvalues = ( "$orderid", "$onemonthsago", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr='bad card length'
            where orderid=?
            and username=?
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    return 1;
  }

  if ( $cardnumber eq "4111111111111111" ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr='test card number'
            where orderid=?
            and trans_date>=?
            and username=?
            and finalstatus='pending'
dbEOM
    my @dbvalues = ( "$orderid", "$onemonthsago", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr='test card number'
            where orderid=?
            and username=?
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    return 1;
  }

  # check for 0 amount
  $amt = substr( $amount, 4 );
  if ( $amt == 0 ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr='amount = 0.00'
            where orderid=?
            and trans_date>=?
            and username=?
            and finalstatus='pending'
dbEOM
    my @dbvalues = ( "$orderid", "$onemonthsago", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr='amount = 0.00'
            where orderid=?
            and username=?
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    return 1;
  }

  return 0;
}

sub pidcheck {
  my $chkline = &procutils::fileread( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "pid.txt" );
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );
    my $printstr = "$pidline\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );
    my $printstr = "$chkline\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdmsomaha - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

