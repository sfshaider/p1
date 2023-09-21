#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use lib $ENV{'PNP_PERL_PROCESSOR_LIB'};
use Net::FTP;
use miscutils;
use procutils;
use rsautils;
use smpsutils;
use tpayments;

$devprod     = "prod";
$devprodlogs = "logs";

my $chktransdateorauthcode = $ARGV[0];
if ( ( $chktransdateorauthcode !~ /^20[0-9]{6}$/ ) && ( $chktransdateorauthcode !~ /^[0-9]{6}$/ ) ) {
  $chktransdateorauthcode = "";
}

#$checkstring = " and t.username='aaaa'";
#$checkstring = " and t.username in ('aaaa','aaaa')";

# xxxx
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 16 ) );
$onemonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() + ( 3600 * 24 ) );
$tomorrow = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 4 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );

( $batchorderid, $today, $ttime ) = &miscutils::genorderid();
$todaytime = $ttime;

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprodlogs/tpayments/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprodlogs/tpayments/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprodlogs/tpayments/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprodlogs/tpayments/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprodlogs/tpayments/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprodlogs/tpayments/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprodlogs/tpayments/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprodlogs/tpayments/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprodlogs/tpayments/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprodlogs/tpayments/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: tpayments - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory tpayments/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$filename = "$ttime";
$batchid  = $batchorderid;

umask 0077;

if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
  unlink "/home/pay1/batchfiles/$devprodlogs/tpayments/batchfile.txt";
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'tpayments/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: tpayments - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

%returncodes = (
  "R01", "Insufficient Funds",                               "R02", "Account Closed",
  "R03", "No Account",                                       "R04", "Invalid Account Number",
  "R06", "Returned per ODFIs Request",                       "R07", "Authorization Revoked by Customer",
  "R08", "Payment Stopped or Stop Payment on Item",          "R09", "Uncollected Funds",
  "R10", "Customer Advises Not Authorized or other",         "R11", "Check Truncation Entry Return",
  "R12", "Branch Sold to Another DFI",                       "R14", "Representative Payee Deceased or other",
  "R15", "Beneficiary or Account Holder Deceased",           "R16", "Account Frozen",
  "R17", "File Record Edit Criteria",                        "R20", "Non-Transaction Account",
  "R21", "Invalid Company ID",                               "R22", "Invalid Individual ID Number",
  "R23", "Credit Entry Refused by Receiver",                 "R24", "Duplicate Entry",
  "R29", "Corporate Customer Advises Not Authorized",        "R31", "Permissible Return Entry",
  "R33", "Return of XCK Entry",                              "R40", "Return of ENR Entry by Federal Government Agency",
  "R41", "Invalid Transaction Code",                         "R42", "Routing Number/Check Digit Error",
  "R43", "Invalid DFI Account Number",                       "R44", "Invalid Individual ID Number",
  "R45", "Invalid Individual Name/Company Name",             "R46", "Invalid Representative Payee Indicator",
  "R47", "Duplicate Enrollment",                             "R61", "Misrouted Return",
  "R62", "Incorrect Trace Number",                           "R63", "Incorrect Dollar Amount",
  "R64", "Incorrect Individual Identification",              "R65", "Incorrect Transaction Code",
  "R66", "Incorrect Company Identification",                 "R67", "Duplicate Return",
  "R68", "Untimely Return",                                  "R69", "Multiple Errors",
  "R70", "Permissible Return Entry Not Accepted",            "R71", "Misrouted Dishonored Return",
  "R72", "Untimely Dishonored Return",                       "R73", "Timely Original Return",
  "R74", "Corrected Return",                                 "R13", "RDFI Not Qualified to Participate",
  "R18", "Improper Effective Entry Date",                    "R19", "Amount Field Error",
  "R25", "Addenda Error",                                    "R26", "Mandatory Field Error",
  "R27", "Trace Number Error",                               "R28", "Routing Number Check Digit Error",
  "R30", "RDFI Not Participant in Check Truncation Program", "R32", "RDFI Non-Settlement",
  "R34", "Limited Participation DFI",                        "R35", "Return of Improper Debit Entry",
  "R36", "Return of Improper Credit Entry",                  "C01", "Incorrect DFI Account Number",
  "C02", "Incorrect Routing Number",                         "C03", "Incorrect Routing Number, DFI Account Number",
  "C04", "Incorrect Individual Name/Receiving Company Name", "C05", "Incorrect Transaction Code",
  "C06", "Incorrect DFI Account Number, Transaction Code",   "C07", "Incorrect Routing Number, DFI Account Number, Trans Code",
  "C08", "Reserved",                                         "C09", "Incorrect Individual Identification Number",
  "C10", "Incorrect Company Name",                           "C11", "Incorrect Company Identification",
  "C12", "Incorrect Company Name, Company Identification",   "C13", "Addenda Format Error"
);

$batch_flag = 1;
$file_flag  = 1;
$errorflag  = 0;

my $printstr = "aaaa $twomonthsago $today\n";
&procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );

my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        $checkstring
        and t.finalstatus in ('pending','success')
        and t.accttype in ('checking','savings')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.trans_date>=?
        and o.lastopstatus in ('pending','success')
        and o.processor='tpayments'
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$twomonthsago" );
my @sthvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthvalarray) ; $vali = $vali + 3 ) {
  ( $username, $count, $starttransdate ) = @sthvalarray[ $vali .. $vali + 2 ];
  print "username: $username\n";

  @userarray = ( @userarray, $username );
}

foreach $username (@userarray) {
  if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
    unlink "/home/pay1/batchfiles/$devprodlogs/tpayments/batchfile.txt";
    last;
  }

  $filename = "$username$ttime.txt";

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/$devprodlogs/tpayments", "genfiles.txt", "write", "", $batchfilestr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/$devprodlogs/tpayments", "batchfile.txt", "write", "", $batchfilestr );

  %checkdup = ();

  my $dbquerystr = <<"dbEOM";
        select status
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ($chkstatus) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $chkstatus ne "live" ) {
    next;
  }

  my $dbquerystr = <<"dbEOM";
        select loginun,loginpw,gatewayid
        from tpayments
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $loginun, $loginpw, $gatewayid ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $loginpw = &rsautils::rsa_decrypt_file( $loginpw, '0', "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

  if ( ( $username eq "testpdata" ) && ( $loginun eq "" ) ) {
    $loginun   = "0W8MBDCWBQ130KTQLWUQ";
    $loginpw   = "266QU22QEQXP61Y0MRQX9T4KX3RY1A5CLRPYKUJI";
    $gatewayid = "340";
  }

  #if ($chkstatus ne "enabled") {
  #  print "$username not enabled\n";
  #  next;
  #}

  # update transaction status automatically
  #my $printstr = "get latest results\n";
  #&procutils::filewrite("$username","tpayments","/home/pay1/batchfiles/devlogs/tpayments","miscdebug.txt","append","misc",$printstr);
  #&getresults("","");	# orderid, transid

  #if ($chktransdateorauthcode ne "") {
  #  # update transaction status based on transaction date or auth code (transid)
  #  my $printstr = "get results for $chktransdateorauthcode\n";
  #  &procutils::filewrite("$username","tpayments","/home/pay1/batchfiles/devlogs/tpayments","miscdebug.txt","append","misc",$printstr);
  #  &getresults("","",$chktransdateorauthcode);	# orderid, transid, transdate
  #}

  if (1) {

    # manually get transaction status for other transactions
    my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,amount,
                 auth_code,avs,refnumber,lastopstatus,transflags,accttype,
		 card_name,card_addr,card_city,card_state,card_zip,card_country,
                 authtime,returntime
          from operation_log
          where trans_date>=?
          and trans_date<=?   
          and username=? 
          and lastop in ('auth','return')
          and lastopstatus in ('success','pending') 
          and (voidstatus is NULL or voidstatus ='')
          and accttype in ('checking','savings')
dbEOM
    my @dbvalues = ( "$twomonthsago", "$today", "$username" );
    my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 21 ) {
      ( $orderid,    $operation, $trans_date, $trans_time, $enccardnumber, $length,     $amount,   $auth_code,    $avs_code, $refnumber, $lastopstatus,
        $transflags, $accttype,  $card_name,  $card_addr,  $card_city,     $card_state, $card_zip, $card_country, $authtime, $returntime
      )
        = @sthtransvalarray[ $vali .. $vali + 20 ];

      if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
        last;
      }

      if ( $operation eq "void" ) {
        $orderidold = $orderid;
        next;
      }

      if ( $checkdup{"$operation $orderid"} == 1 ) {
        next;
      }
      $checkdup{"$operation $orderid"} = 1;

      print "orderid: $orderid\n";
      print "refnumber: $refnumber\n";
      print "operation: $operation\n\n";
      print "lastopstatus: $lastopstatus\n\n";

      &getresults( $orderid, $refnumber, $operation, $lastopstatus );

    }

  }

}

unlink "/home/pay1/batchfiles/$devprodlogs/tpayments/batchfile.txt";

umask 0033;
$batchfilestr = "";
&procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/$devprodlogs/tpayments", "genfiles.txt", "write", "", $batchfilestr );

#system("/home/pay1/batchfiles/$devprod/tpayments/putfiles.pl >> /home/pay1/batchfiles/$devprodlogs/tpayments/ftplog.txt 2>\&1");

exit;

sub getresults {
  my ( $orderid, $chargeid, $operation, $lastopstatus ) = @_;

  if ( $chargeid eq "" ) {
    return;
  }

  $response = "";

  my $host = "live.goodfundsgateway.com";
  if ( $username eq "testpdata" ) {
    $host = "demo.goodfundsgateway.com";
  }
  my $port = "443";
  my $path = "/api/transaction.json";

  $mytime     = gmtime( time() );
  $outfilestr = "";
  $outfilestr .= "\n\n$orderid $transid $transdateorauthcode\n";
  $outfilestr .= "$host:$port $path\n";
  $outfilestr .= "$mytime send: $path/$gatewayid/$chargeid\n\n";
  my $writestatus = &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/$devprodlogs/tpayments/$fileyear", "$filename", "append", "", $outfilestr );

  my $message = "GET $path/$gatewayid/$chargeid HTTP/1.1\r\n";
  $message .= "SVS-API-ID: $loginun\r\n";
  $message .= "SVS-API-KEY: $loginpw\r\n";
  $message .= "Host: $host\r\n";
  $message .= "Accept: */*\r\n\r\n";

  #print "message: $message\n";

  my ( $response, $header ) = &sendmessage( "$message", "$host", "$port", "$path", "$tcode" );

  #print "header: $header\n\n";
  print "response: $response\n\n";

  my $jsonmsg = "";
  if ( $response ne "" ) {
    $jsonmsg = &JSON::decode_json($response);
  }

  my $checkstr = $response;

  #$checkstr =~ s/></>\n</g;

  $mytime     = gmtime( time() );
  $outfilestr = "";
  $outfilestr .= "$mytime recv: $checkstr\n\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/$devprodlogs/tpayments/$fileyear", "$filename", "append", "", $outfilestr );

  my $status = $jsonmsg->{"status"};

  # {"status":"success","successMessage":{"response_code":707,"message":{"transaction":{"success":true,"charge_id":"5339","trans_id":"13BDCD74","trans_status":"Submitted ACH"}}}}

  my $respcode = $jsonmsg->{ $status . "Message" }->{"message"}->{"response_code"};
  my $err_msg  = $jsonmsg->{ $status . "Message" }->{"message"}->{"response_text"} . " " . $jsonmsg->{ $status . "Message" }->{"message"}->{"reason"};
  if ( $status eq "success" ) {
    $respcode  = $jsonmsg->{ $status . "Message" }->{"response_code"};
    $err_msg   = $jsonmsg->{ $status . "Message" }->{"message"}->{"transaction"}->{"trans_status"};
    $refnumber = $jsonmsg->{ $status . "Message" }->{"message"}->{"transaction"}->{"charge_id"};
    if ( $jsonmsg->{ $status . "Message" }->{"message"}->{"transaction"}->{"return_code"} =~ /^(R|C)/ ) {
      $respcode = $jsonmsg->{ $status . "Message" }->{"message"}->{"transaction"}->{"return_code"};
    }

    #$trans_id = $jsonmsg->{$status . "Message"}->{"message"}->{"charge"}->{"trans_id"};
    #$approval_code = $jsonmsg->{$status . "Message"}->{"message"}->{"charge"}->{"approval_code"};
    #$authCode = $jsonmsg->{$status . "Message"}->{"message"}->{"charge"}->{"raw_data"}->{"authCode"};
    #$refId = $jsonmsg->{$status . "Message"}->{"message"}->{"charge"}->{"raw_data"}->{"refId"};
  }
  my $errmsg = "$respcode: $err_msg";

  print "respcode: $respcode\n";
  print "err_msg: $err_msg\n";

  #$descr = "New Route Number: $newrout New Account Number: $newacct";
  #if ($newaccttype eq "37") {
  #  $descr = $descr . " Must use savings";
  #}
  #$error = "$noccode: $nocdesc";

  if (0) {
    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: cprice\@plugnpay.com\n";
    print MAIL "From: dcprice\@plugnpay.com\n";
    print MAIL "Subject: tpayments - genfiles error\n";
    print MAIL "\n";
    print MAIL "File has a non-existent orderid.\n";
    print MAIL "filename: $filename\n\n";

    print MAIL "username: $username\n";
    print MAIL "transid: $transid\n";
    print MAIL "refnumber: $refnumber\n";
    print MAIL "trans_type: $trans_type\n\n";

    print MAIL "transdatestr: $transdatestr\n";
    print MAIL "respcode: $respcode\n";
    print MAIL "errmsg: $errmsg\n\n";
    close(MAIL);

    next;
  }

  if ( ( $errmsg =~ /Paid ACH/ ) && ( $lastopstatus eq "pending" ) ) {
    &processsuccess( $username, $orderid, $operation, $errmsg );
  } elsif ( ( $errmsg =~ /Paid ACH/ )          && ( $lastopstatus eq "success" ) ) {
  } elsif ( $errmsg =~ /Submitted ACH/ ) {
  } elsif ( ( $errmsg =~ /(Returned|Voided)/ ) && ( $lastopstatus =~ /(pending|success)/ ) ) {
    my $rcode = substr( $errmsg, 0, 3 );
    my $yearmonthdayhms =
      substr( $transdatestr, 0, 4 ) . substr( $transdatestr, 5, 2 ) . substr( $transdatestr, 8, 2 ) . substr( $transdatestr, 11, 2 ) . substr( $transdatestr, 14, 2 ) . substr( $transdatestr, 17, 2 );
    if ( $rcode =~ /^C/ ) {
      &processnoc( $username, $orderid, $operation, $card_name, $rcode, $errmsg );
    } else {
      print "respcode: $respcode\n";
      print "errmsg: $errmsg\n";
      print "orderid: $orderid\n";
      print "operation: $operation\n";
      print "rcode: $rcode\n";
      print "yearmonthdayhms: $yearmonthdayhms\n\n";
      print "lastopstatus: $lastopstatus\n\n";
      &processreturn( $username, $orderid, $operation, $rcode, $yearmonthdayhms, $errmsg );
    }
  } else {
    print "respcode: $respcode\n";
    print "errmsg: $errmsg\n";
    print "orderid: $orderid\n";
    print "operation: $operation\n";
    print "rcode: $rcode\n";
    print "yearmonthdayhms: $yearmonthdayhms\n\n";
    print "lastopstatus: $lastopstatus\n\n";
    print "else\n";
    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: cprice\@plugnpay.com\n";
    print MAIL "From: dcprice\@plugnpay.com\n";
    print MAIL "Subject: tpayments - genfiles error\n";
    print MAIL "\n";

    print MAIL "username: $username\n";
    print MAIL "orderid: $orderid\n";
    print MAIL "operation: $operation\n\n";
    print MAIL "refnumber: $refnumber\n";

    print MAIL "message: $response\n\n";
    print MAIL "respcode: $respcode\n";
    print MAIL "errmsg: $errmsg\n\n";
    close(MAIL);

    if ( $errmsg =~ /There was an issue finding this transaction/ ) {
      $errorcnt++;

      if ( $errorcnt > 8 ) {
        print "too many erros, exiting...\n";
        exit;
      }
    }
  }

}

sub sendmessage {
  my ( $msg, $host, $port, $path, $tcode ) = @_;

  my $len = length($msg);

  my $header = "";

  my %sslheaders = ();
  $sslheaders{'Host'} = "$host";

  #$sslheaders{'SoapAction'} = "https://www.tpayments-operations.com/webservices/ACHPayorService/$action";
  $sslheaders{'SVS-API-ID'}     = "$loginun";
  $sslheaders{'SVS-API-KEY'}    = "$loginpw";
  $sslheaders{'Content-Length'} = $len;
  $sslheaders{'Content-Type'}   = 'application/json; charset=utf-8';

  #my ($response) = &procutils::sendsslmsg("processor_tpayments",$host,"",$path,$msg,"other",%sslheaders);
  my ($response) = &procutils::sendsslmsg( "processor_tpayments", $host, "$port", $path, $msg, "nopost,got=\}", %sslheaders );

  return $response, $header;

}

sub readxml {
  my ($msg) = @_;

  my $data = $msg;
  $data =~ s/\n/ /g;
  $data =~ s/\r/ /g;
  $data =~ s/\&lt;/</g;
  $data =~ s/\&gt;/>/g;
  $data =~ s/>\s*</>;;;</g;
  my @tmpfields = split( /;;;/, $data );
  my %temparray = ();
  my $levelstr  = "";
  my $idx       = 0;
  my $idxstr    = "";
  foreach my $var (@tmpfields) {

    if ( $var =~ /<(.+)>(.*)</ ) {
      my $var2 = $1;
      my $var3 = $2;
      $var2 =~ s/ .*$//;

      if ( $var2 =~ /OneTimeTransaction/ ) {
        $idx++;
        if ( $idx > 0 ) {
          $idxstr = ",$idx";
        }
      }

      if ( $temparray{"$levelstr$var2$idxstr"} eq "" ) {
        $temparray{"$levelstr$var2$idxstr"} = $var3;
      } else {
        $temparray{"$levelstr$var2$idxstr"} = $temparray{"$levelstr$var2$idxstr"} . "," . $var3;
      }
    } elsif ( $var =~ /<\/(.+)>/ ) {
      $levelstr =~ s/,[^,]*?,$/,/;
    } elsif ( ( $var =~ /<(.+)>/ ) && ( $var !~ /<\?/ ) && ( $var !~ /\/>/ ) ) {
      my $var2 = $1;
      $var2 =~ s/ .*$//;

      if ( $var2 =~ /OneTimeTransaction/ ) {
        $idx++;
        if ( $idx > 0 ) {
          $idxstr = ",$idx";
        }
      }

      $levelstr = $levelstr . $var2 . ",";
    }
  }

  return %temparray;
}

sub findtransaction {
  ( $username, $transid, $refnumber, $trans_type, $transdate ) = @_;

  $transdate = substr( $refnumber, 0, 8 );

  if ( ( $transdate < "20180101" ) || ( $transdate > 22000000 ) ) {
    return "";
  }

  my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,lastopstatus,card_name
          from operation_log
          where trans_date=?
          and username=?
          and refnumber=?
          and lastop in ('auth','return')
          and lastopstatus not in ('badcard','problem') 
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$transdate", "$username", "$refnumber" );
  my ( $orderid, $operation, $trans_date, $trans_time, $lastopstatus, $card_name ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  my $printstr = "aaaa $orderid bbbb $operation $lastopstatus\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );

  return $orderid, $operation, $lastopstatus, $card_name;
}

sub getdates {
  my ($transdate) = @_;

  my @datearray = ();
  $datearray[0] = &subtractoneday($transdate);
  $datearray[1] = &subtractoneday( $datearray[0] );
  $datearray[2] = &subtractoneday( $datearray[1] );
  $datearray[3] = &subtractoneday( $datearray[2] );
  $datearray[4] = &subtractoneday( $datearray[3] );
  $datearray[5] = &subtractoneday( $datearray[4] );
  $datearray[6] = &subtractoneday( $datearray[5] );

  return @datearray;

}

sub subtractoneday {
  my ($transdate) = @_;

  #my $year = substr($transdate,0,4);
  #my $month = substr($transdate,4,2);
  #my $day = substr($transdate,6,2);

  my $timenum = &miscutils::strtotime( $transdate . "000000" );
  $timenum = $timenum - ( 3600 * 24 );
  $transdate = &miscutils::timetostr($timenum);

  return $transdate;

}

sub processnoc {
  my ( $username, $orderid, $operation, $name, $noccode, $nocinfo ) = @_;

  $nocdesc = $returncodes{"$noccode"};

  my $printstr = "$cardnumber";
  $printstr .= "$nocinfo\n";
  $printstr .= "username: $username\n";
  $printstr .= "orderid: $orderid\n";
  $printstr .= "nocinfo: $nocinfo\n";
  $printstr .= "oldroute: $oldroute\n";
  $printstr .= "oldacct: $oldacct\n";
  $printstr .= "noccode: $noccode\n";
  $printstr .= "nocdesc: $nocdesc\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $nocfilestr = "";
  $nocfilestr .= "\nfile: $file\n";
  $nocfilestr .= "username: $username\n";
  $nocfilestr .= "orderid: $orderid\n";
  $nocfilestr .= "descr: $noccode: $nocdesc\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments/returns", "$today" . "summary.txt", "append", "", $nocfilestr );

  $newacct = "";
  $newrout = "";
  if ( $noccode eq "C01" ) {

    #$nocinfo = substr($line2,44,17);
    $newacct = $nocinfo;
    $newacct =~ s/ //g;
  } elsif ( $noccode eq "C02" ) {

    #$nocinfo = substr($line2,44,9);
    $newrout = $nocinfo;
    $newrout =~ s/ //g;
  } elsif ( $noccode eq "C03" ) {

    #$nocinfo = substr($line2,44,29);
    ( $newrout, $newacct ) = split( /\s+/, $nocinfo );
    $newacct =~ s/ //g;
  } elsif ( $noccode eq "C06" ) {

    # must use savings as the account type
    #$nocinfo = substr($line2,44,29);
    #($newacct,$newaccttype) = split(/   /,$nocinfo);
    #$newacct =~ s/ //g;
  } else {

    #$nocinfo = substr($line2,44,42);
  }

  $pnpcompany = "Plug and Pay";
  $pnpemail   = "michelle\@plugnpay.com";

  my $dbquerystr = <<"dbEOM";
        select reseller,merchemail from customers
        where username=? 
dbEOM
  my @dbvalues = ("$username");
  ( $reseller, $email ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $descr = "New Route Number: $newrout New Account Number: $newacct";
  if ( $newaccttype eq "37" ) {
    $descr = $descr . " Must use savings";
  }
  $error = "$noccode: $nocdesc";

  %datainfo = ( "username", "$username", "today", "$today", "orderid", "$orderid", "name", "$name", "descr", "$descr", "error", "$error" );

  my $dbquerystr = <<"dbEOM";
        select orderid from achnoc
        where orderid=?
        and username=?
        and error like ?
dbEOM
  my @dbvalues = ( "$orderid", "$username", "$noccode\%" );
  ($chkorderid) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $chkorderid eq "" ) {
    my $dbquerystr = <<"dbEOM";
          insert into achnoc 
          (username,trans_date,orderid,name,descr,error)
          values (?,?,?,?,?,?) 
dbEOM

    my %inserthash = ( "username", "$username", "trans_date", "$today", "orderid", "$orderid", "name", "$name", "descr", "$descr", "error", "$error" );
    &procutils::dbinsert( $username, $orderid, "pnpmisc", "achnoc", %inserthash );

    if ( $emailedmerch{$username} eq "" ) {
      $emailedmerch{$username} = "yes";

      if ( $plcompany{$reseller} ne "" ) {
        $privatelabelflag    = 1;
        $privatelabelcompany = $plcompany{$reseller};
        $privatelabelemail   = $plemail{$reseller};
      } else {
        $privatelabelflag    = 0;
        $privatelabelcompany = $pnpcompany;
        $privatelabelemail   = $pnpemail;
      }

      open( MAIL, "| /usr/lib/sendmail -t" );
      print MAIL "To: $email\n";
      print MAIL "Bcc: cprice\@plugnpay.com\n";
      print MAIL "From: $privatelabelemail\n";
      print MAIL "Subject: $privatelabelcompany - Notification of Change - $username\n";
      print MAIL "\n";
      print MAIL "We received a Notification of Change for some customers. If you do any more\n";
      print MAIL "electronic checking transactions for these customers, please use the new information\n";
      print MAIL "to prevent fees from being charged.\n\n";
      print MAIL "The new information can be found at:\n\n";
      print MAIL "https://pay1.plugnpay.com/admin/noc.cgi\n";
      print MAIL "\nThankyou,\n";
      print MAIL "$privatelabelcompany\n";
      close(MAIL);
    }
  }

}

sub processsuccess {
  my ( $username, $orderid, $operation, $descr ) = @_;
  my $printstr = "cccc $orderid $twomonthsago $twomonthsagotime $username $operation\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );

  if ( $orderid eq "" ) {
    return;
  }
  print "in processsuccess $orderid $operation $descr\n";

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='success',descr=?
          where orderid=?
          and trans_date>=?
          and username=?
          and operation=?
          and finalstatus in ('pending','locked')
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$descr", "$orderid", "$twomonthsago", "$username", "$operation" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
  my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='success',lastopstatus='success',descr=?
          where orderid=?
          and lastoptime>=?
          and username=?
          and lastop=?
          and $operationstatus in ('pending','locked')
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$descr", "$orderid", "$twomonthsagotime", "$username", "$operation" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  if ( $username =~ /^(pnppdata|ach2)/ ) {

    my $dbquerystr = <<"dbEOM";
          select username,orderid,trans_date,amount,card_type,descr,commission,paidamount,paiddate,transorderid,checknum
          from billingstatus
          where orderid=?
          and result='hold'
dbEOM
    my @dbvalues = ("$orderid");
    my @sth_statusvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    for ( my $vali = 0 ; $vali < scalar(@sth_statusvalarray) ; $vali = $vali + 11 ) {
      ( $busername, $borderid, $btrans_date, $bamount, $bcard_type, $bdescr, $bcommission, $bpaidamount, $bpaiddate, $btransorderid, $bchecknum ) = @sth_statusvalarray[ $vali .. $vali + 10 ];

      my $printstr = "billing username: $busername $borderid\n";
      &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );
      my $dbquerystr = <<"dbEOM";
              insert into billingreport
              (username,orderid,trans_date,amount,card_type,descr,commission,paidamount,paiddate,transorderid,checknum)
              values (?,?,?,?,?,?,?,?,?,?,?)
dbEOM

      my %inserthash = (
        "username",  "$busername",  "orderid",      "$borderid",      "trans_date", "$btrans_date", "amount",     "$bamount",
        "card_type", "$bcard_type", "descr",        "$bdescr",        "commission", "$bcommission", "paidamount", "$bpaidamount",
        "paiddate",  "$bpaiddate",  "transorderid", "$btransorderid", "checknum",   "$bchecknum"
      );
      &procutils::dbinsert( $username, $orderid, "pnpmisc", "billingreport", %inserthash );

    }

    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime update billingstatus set result='success' where orderid=? and result='hold'\n";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/logs/tpayments", "achlog.txt", "append", "", $achfilestr );
    my $printstr = " ";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );

    my $dbquerystr = <<"dbEOM";
          update billingstatus
          set result='success'
          where orderid=?
          and result='hold'
dbEOM
    my @dbvalues = ("$orderid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
          select orderid from pending 
          where transorderid=?
          and status='locked' 
dbEOM
    my @dbvalues = ("$orderid");
    my @sth_statusvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    for ( my $vali = 0 ; $vali < scalar(@sth_statusvalarray) ; $vali = $vali + 1 ) {
      ($oid) = @sth_statusvalarray[ $vali .. $vali + 0 ];

      my $dbquerystr = <<"dbEOM";
            update quickbooks 
            set result='success',trans_date=?
            where orderid=?
            and result='pending' 
dbEOM
      my @dbvalues = ( "$today", "$orderid" );
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    }

    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime delete from pending where transorderid='$orderid' and status='locked'\n";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/logs/tpayments", "achlog.txt", "append", "", $achfilestr );

    my $dbquerystr = <<"dbEOM";
          delete from pending 
          where transorderid=?
          and status='locked' 
dbEOM
    my @dbvalues = ("$orderid");
    &procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    #$updstatus = "success";
  }
}

sub processreturn {
  my ( $username, $orderid, $operation, $rcode, $yearmonthdayhms, $descr ) = @_;

  if ( $orderid eq "" ) {
    return;
  }

  if ( $descr =~ /Voided/ ) {
    $descr = "Voided";
  } elsif ( $rcode =~ /^X/ ) {
    $descr = "$rcode: " . $descr;
  } else {
    $descr = "$rcode: " . $returncodes{"$rcode"};
  }

  print "in processreturn $username $orderid $operation $rcode  $descr\n";

  %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

  my $dbquerystr = <<"dbEOM";
          select orderid
          from trans_log
          where orderid=?
          and trans_date>=?
          and username=?
          and operation=?
          and descr=?
dbEOM
  my @dbvalues = ( "$orderid", "$twomonthsago", "$username", "$operation", "$descr" );
  ($chkorderid) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $emailflag = 1;
  if ( $chkorderid ne "" ) {
    $emailflag = 0;
  }

  my $dbquerystr = <<"dbEOM";
          select card_name,acct_code,acct_code2,acct_code3,amount,accttype,result
          from trans_log
          where orderid=?
          and trans_date>=?
          and username=?
          and operation=?
dbEOM
  my @dbvalues = ( "$orderid", "$twomonthsago", "$username", "$operation" );
  ( $card_name, $acct_code1, $acct_code2, $acct_code3, $amount, $accttype, $batchid ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  my $printstr = "aa username: $username\n";
  $printstr .= "aa orderid: $orderid\n";
  $printstr .= "aa operation: $operation\n";
  $printstr .= "aa amount: $amount\n";
  $printstr .= "aa rcode: $rcode\n";
  $printstr .= "aa descr: $descr\n";
  $printstr .= "aa filename: $filename\n";
  $printstr .= "aa emailflag: $emailflag\n";
  print "printstr: $printstr\n";

  #&procutils::filewrite("$username","tpayments","/home/pay1/batchfiles/devlogs/tpayments","miscdebug.txt","append","misc",$printstr);

  # yyyy
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "aa username: $username\n";
  $logfilestr .= "aa orderid: $orderid\n";
  $logfilestr .= "aa operation: $operation\n";
  $logfilestr .= "aa amount: $amount\n";
  $logfilestr .= "aa descr: $descr\n";
  $logfilestr .= "aa filename: $filename\n";
  $logfilestr .= "aa twomonthsago: $twomonthsago\n";
  $logfilestr .= "aa twomonthsagotime: $twomonthsagotime\n";
  $logfilestr .= "aa emailflag: $emailflag\n\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/$devprodlogs/tpayments", "chk$username.txt", "append", "", $logfilestr );

  my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='badcard',descr=?
          where orderid=?
          and trans_date>=?
          and username=?
          and operation=?
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$descr", "$orderid", "$twomonthsago", "$username", "$operation" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  if ( $operation ne "return" ) {
    ( $curr, $price ) = split( / /, $amount );
    $price = $curr . " -" . $price;
  }

  my $tdate = substr( $yearmonthdayhms, 0, 8 );

  my $dbquerystr = <<"dbEOM";
          insert into trans_log
          (username,orderid,operation,trans_date,trans_time,batch_time,descr,amount,accttype,card_name,result)
          values (?,?,?,?,?,?,?,?,?,?,?)
dbEOM

  my %inserthash = (
    "username",   "$username",        "orderid",    "$orderid",   "operation", "chargeback", "trans_date", "$tdate",
    "trans_time", "$yearmonthdayhms", "batch_time", "$todaytime", "descr",     "$descr",     "amount",     "$price",
    "accttype",   "$accttype",        "card_name",  "$card_name", "result",    "$batchid"
  );
  &procutils::dbinsert( $username, $orderid, "pnpdata", "trans_log", %inserthash );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";
  my $dbquerystr = <<"dbEOM";
          update operation_log set lastopstatus='badcard',$operationstatus='badcard',descr=?
          where orderid=?
          and lastoptime>=?
          and username=?
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$descr", "$orderid", "$twomonthsagotime", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $pnpcompany = "Plug and Pay";
  $pnpemail   = "michelle\@plugnpay.com";

  my $dbquerystr = <<"dbEOM";
        select reseller,merchemail from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $reseller, $email ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $plcompany{$reseller} ne "" ) {
    $privatelabelflag    = 1;
    $privatelabelcompany = $plcompany{$reseller};
    $privatelabelemail   = $plemail{$reseller};
  } else {
    $privatelabelflag    = 0;
    $privatelabelcompany = $pnpcompany;
    $privatelabelemail   = $pnpemail;
  }

  my $dbquerystr = <<"dbEOM";
          select acct_code3
          from trans_log
          where orderid=?
          and operation='postauth'
dbEOM
  my @dbvalues = ("$orderid");
  ($acct_code3) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  if ( $acct_code3 eq "recurring" ) {

    my $dbquerystr = <<"dbEOM";
          select username,orderid
          from billingstatus
          where orderid=?
dbEOM
    my @dbvalues = ("$orderid");
    ( $chkusername, $chkorderid ) = &procutils::dbread( $username, $orderid, "$username", $dbquerystr, @dbvalues );

    if ( $chkorderid ne "" ) {
      my $dbquerystr = <<"dbEOM";
          insert into billingstatus
          (username,trans_date,amount,orderid,descr)
          values (?,?,?,?,?)
dbEOM

      my %inserthash = ( "username", "$chkusername", "trans_date", "$today", "amount", "-$amount", "orderid", "$orderid", "descr", "$descr" );
      &procutils::dbinsert( $username, $orderid, "$username", "billingstatus", %inserthash );

    }

  }

  my $printstr = "privatelabelcompany: $privatelabelcompany\n";
  $printstr .= "email: $email\n";
  $printstr .= "orderid: $orderid\n";
  $printstr .= "reason: $descr\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );

  if ( $emailflag == 1 ) {
    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: $email\n";
    print MAIL "Bcc: cprice\@plugnpay.com\n";
    print MAIL "Bcc: michelle\@plugnpay.com\n";
    print MAIL "From: $privatelabelemail\n";
    print MAIL "Subject: $privatelabelcompany - tpayments Order $username $orderid failed\n";
    print MAIL "\n";
    print MAIL "$username\n\n";
    print MAIL "We would like to inform you that order $orderid received a Return notice\n";
    print MAIL "today.\n\n";
    print MAIL "Orderid: $orderid\n\n";
    print MAIL "Card Name: $card_name\n\n";
    print MAIL "Amount: $amount\n\n";

    if ( $authtime1 ne "" ) {
      $authdate = substr( $authtime1, 4, 2 ) . "/" . substr( $authtime1, 6, 2 ) . "/" . substr( $authtime1, 0, 4 );
      print MAIL "Auth Date: $authdate\n";
    }
    print MAIL "Reason: $descr\n\n";
    if ( $acct_code1 ne "" ) {
      print MAIL "AcctCode1: $acct_code1\n\n";
    }
    if ( $acct_code2 ne "" ) {
      print MAIL "AcctCode2: $acct_code2\n\n";
    }
    if ( $acct_code3 ne "" ) {
      print MAIL "AcctCode3: $acct_code3\n\n";
    }
    print MAIL "Plug & Pay Technologies\n";
    close(MAIL);
  }

  if ( $username =~ /^(pnppdata|ach2)/ ) {
    my $printstr = "$username $orderid $batchid $twomonthsago $descr<br>\n";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );
    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime select username from billingstatus where orderid=?\n";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/logs/tpayments", "achlog.txt", "append", "", $achfilestr );
    my $dbquerystr = <<"dbEOM";
          select username,card_type from billingstatus
          where orderid=? 
dbEOM
    my @dbvalues = ("$orderid");
    ( $merchant, $chkcard_type ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    my $printstr = "cccc$merchant $orderid $chkcard_type<br>\n";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );

    if ( $chkcard_type eq "reseller" ) {
      my $dbquerystr = <<"dbEOM";
            select reseller from customers
            where username=?
dbEOM
      my @dbvalues = ("$merchant");
      ($merchant) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    } else {
      $achfilestr = "";
      $achfilestr .= "$remoteuser $todaytime update pending set card_type='check' where username='$merchant'\n";
      &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/logs/tpayments", "achlog.txt", "append", "", $achfilestr );
      my $dbquerystr = <<"dbEOM";
            update pending
            set card_type='check'
            where username=?
dbEOM
      my @dbvalues = ("$merchant");
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      $achfilestr = "";
      $achfilestr .= "$remoteuser $todaytime update customers set accttype='check' where username='$merchant'\n";
      &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/logs/tpayments", "achlog.txt", "append", "", $achfilestr );
      my $dbquerystr = <<"dbEOM";
            update customers 
            set accttype='check' 
            where username=? 
dbEOM
      my @dbvalues = ("$merchant");
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    }

    # yyyy

    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime select merchemail,reseller,company from customers where username='$merchant'\n";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/logs/tpayments", "achlog.txt", "append", "", $achfilestr );
    my $dbquerystr = <<"dbEOM";
          select email,reseller,company
          from customers 
          where username=? 
dbEOM
    my @dbvalues = ("$merchant");
    ( $email, $reseller, $company ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime select company,email from privatelabel where username='$reseller'\n";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/logs/tpayments", "achlog.txt", "append", "", $achfilestr );
    my $dbquerystr = <<"dbEOM";
            select company,email
            from privatelabel
            where username=?
dbEOM
    my @dbvalues = ("$reseller");
    ( $plcompany, $plemail ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    if ( $plcompany ne "" ) {
      $privatelabelflag    = 1;
      $privatelabelcompany = $plcompany;
      $privatelabelemail   = $plemail;
    } else {
      $privatelabelflag    = 0;
      $privatelabelcompany = "Plug & Pay Technologies, Inc.";
      $privatelabelemail   = "noreply\@plugnpay.com";
    }

    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: $email\n";
    print MAIL "Bcc: accounting\@plugnpay.com\n";
    print MAIL "Bcc: michelle\@plugnpay.com\n";
    print MAIL "Bcc: cprice\@plugnpay.com\n";
    print MAIL "From: $privatelabelemail\n";
    print MAIL "Subject: Monthly Billing - $privatelabelcompany - $username\n";
    print MAIL "\n";
    print MAIL "$company\n";
    print MAIL "$orderid\n\n";

    print MAIL "The attempt to bill your checking account for your monthly gateway fee\n";
    print MAIL "has failed. There is a returned check fee of \$20.00 in addition to your\n";
    print MAIL "monthly gateway fee. If payment is not received by the end of the month\n";
    print MAIL "then your account will be closed. Once your account is closed it cannot\n";
    print MAIL "be reopened until we have received payment.\n\n";

    print MAIL "To remit payment by check:\n";
    print MAIL "  Please include your username in the memo area of your check.\n";
    print MAIL "  Send check payment to:\n";
    print MAIL "      Plug \& Pay Technologies, Inc.\n";
    print MAIL "      1019 Ft. Salonga Rd. ste 10\n";
    print MAIL "      Northport, NY 11768\n\n";

    print MAIL "To pay  by credit card or update your banking information:\n";
    print MAIL "  - Complete the Billing Authorization form located in your administration\n";
    print MAIL "    area.\n";
    print MAIL "  - Click on the link labeled Billing Authorization.\n";
    print MAIL "  - Follow the online instructions\n\n";

    print MAIL "Cancellations:\n";
    print MAIL "  If you wish to cancel your account please send an email to\n";
    print MAIL "  accounting\@plugnpay.com requesting cancellation. Please include the\n";
    print MAIL "  subject line of your email bill.\n\n";

    print MAIL "Contact 800-945-2538 or email accounting\@plugnpay.com if you have any\n";
    print MAIL "questions.\n";

    #print MAIL "The attempt to bill your checking account failed. There is a returned check\n";
    #print MAIL "fee of \$20.00. If payment is not received by the end of the month then your\n";
    #print MAIL "account will be closed. Once your account is closed it cannot be reopened\n";
    #print MAIL "until we have received payment. When mailing a check please include your\n";
    #print MAIL "username in the memo area of your check.\n\n";
    #print MAIL "Contact 1-800-945-2538 if you have any questions or wish to arrange payment.\n\n";

    #if ($plcompany eq "") {
    #  print MAIL "Billing Address:\n";
    #  print MAIL "Plug \& Pay Technologies, Inc.\n";
    #  print MAIL "1363\-26 Veterans Hwy\n";
    #  print MAIL "Hauppauge, NY  11788\n";
    #  print MAIL "1\-800\-945\-2538\n\n";
    #}

    close(MAIL);

    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime update pending set status='' where username='$merchant' and transorderid='$orderid' \n";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/logs/tpayments", "achlog.txt", "append", "", $achfilestr );

    #where username='$merchant'
    #and transorderid='$orderid'
    my $dbquerystr = <<"dbEOM";
          update pending 
          set status=''  
          where transorderid=? 
dbEOM
    my @dbvalues = ("$orderid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    # xxxx 08/11/2004  and result='success' added
    my $dbquerystr = <<"dbEOM";
          select username,orderid,amount,card_type,descr,paidamount,transorderid
          from billingstatus
          where orderid=?
          and result='success'
dbEOM
    my @dbvalues = ("$orderid");
    my @sth_statusavalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    for ( my $vali = 0 ; $vali < scalar(@sth_statusavalarray) ; $vali = $vali + 7 ) {
      ( $busername, $borderid, $bamount, $bcard_type, $bdescr, $chkpaidamount, $btransorderid ) = @sth_statusavalarray[ $vali .. $vali + 6 ];

      if ( $chkpaidamount ne "" ) {
        my $dbquerystr = <<"dbEOM";
            insert into billingreport
            (username,orderid,trans_date,amount,card_type,descr,paidamount,transorderid)
            values (?,?,?,?,?,?,?,?)
dbEOM

        my %inserthash = (
          "username",  "$busername",  "orderid", "$borderid",       "trans_date", "$today",          "amount",       "-$bamount",
          "card_type", "$bcard_type", "descr",   "$bdescr problem", "paidamount", "-$chkpaidamount", "transorderid", "$btransorderid"
        );
        &procutils::dbinsert( $username, $orderid, "pnpmisc", "billingreport", %inserthash );

      } else {
        my $dbquerystr = <<"dbEOM";
            insert into billingreport
            (username,orderid,trans_date,amount,card_type,descr,transorderid)
            values (?,?,?,?,?,?,?)
dbEOM

        my %inserthash =
          ( "username", "$busername", "orderid", "$borderid", "trans_date", "$today", "amount", "-$bamount", "card_type", "$bcard_type", "descr", "$bdescr problem", "transorderid", "$btransorderid" );
        &procutils::dbinsert( $username, $orderid, "pnpmisc", "billingreport", %inserthash );

      }
    }

    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime update billingstatus set result='badcard' where orderid=?\n";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/logs/tpayments", "achlog.txt", "append", "", $achfilestr );
    my $dbquerystr = <<"dbEOM";
          update billingstatus  
          set result='badcard' 
          where orderid=? 
dbEOM
    my @dbvalues = ("$orderid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $errortype = "Return Fee: $descr";
    $fee       = "20.00";
    $type      = "check";

    my $dbquerystr = <<"dbEOM";
            select orderid
            from pending
            where username=?
            and orderid=?
            and descr like 'Return Fee%'
dbEOM
    my @dbvalues = ( "$merchant", "$orderid" );
    ($chkorderid) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    if ( $chkorderid eq "" ) {
      $achfilestr = "";
      &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/logs/tpayments", "achlog.txt", "append", "", $achfilestr );
      my $dbquerystr = <<"dbEOM";
              insert into pending 
              (orderid,username,amount,descr,trans_date,card_type)
              values (?,?,?,?,?,?) 
dbEOM

      my %inserthash = ( "orderid", "$orderid", "username", "$merchant", "amount", "$fee", "descr", "$errortype", "trans_date", "$today", "card_type", "$type" );
      &procutils::dbinsert( $username, $orderid, "pnpmisc", "pending", %inserthash );

    }
  } else {

    my $dbquerystr = <<"dbEOM";
            select acct_code3
            from trans_log 
            where orderid=?
            and operation='auth' 
dbEOM
    my @dbvalues = ("$orderid");
    ($acct_code3) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $acct_code3 eq "recurring" ) {

      my $dbquerystr = <<"dbEOM";
            select username,orderid
            from billingstatus 
            where orderid=? 
dbEOM
      my @dbvalues = ("$orderid");
      ( $chkusername, $chkorderid ) = &procutils::dbread( $username, $orderid, "$username", $dbquerystr, @dbvalues );

      if ( $chkorderid ne "" ) {
        my $dbquerystr = <<"dbEOM";
            insert into billingstatus
            (username,trans_date,amount,orderid,descr)
            values (?,?,?,?,?) 
dbEOM

        my %inserthash = ( "username", "$chkusername", "trans_date", "$today", "amount", "-$amount", "orderid", "$orderid", "descr", "$descr" );
        &procutils::dbinsert( $username, $orderid, "$username", "billingstatus", %inserthash );

      }

    }
  }

}

sub checkdir {
  my ($date) = @_;

  my $printstr = "checking $date\n";
  &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );

  $fileyear = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 );
  $filemonth = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 );
  $fileyearonly = substr( $date, 0, 4 );

  if ( !-e "/home/pay1/batchfiles/$devprod/tpayments/$fileyearonly" ) {
    my $printstr = "creating $fileyearonly\n";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/tpayments/$fileyearonly");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/tpayments/$filemonth" ) {
    my $printstr = "creating $filemonth\n";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/tpayments/$filemonth");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/tpayments/$fileyear" ) {
    my $printstr = "creating $fileyear\n";
    &procutils::filewrite( "$username", "tpayments", "/home/pay1/batchfiles/devlogs/tpayments", "miscdebug.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/tpayments/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/tpayments/$fileyear" ) {
    system("mkdir /home/pay1/batchfiles/$devprod/tpayments/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/tpayments/$fileyear" ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: tpayments - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Couldn't create directory logs/tpayments/$fileyear.\n\n";
    close MAILERR;
    exit;
  }

}

