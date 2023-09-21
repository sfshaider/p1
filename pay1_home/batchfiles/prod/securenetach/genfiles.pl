#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use IO::Socket;
use Socket;
use rsautils;
use securenetach;
use PlugNPay::CreditCard;
use smpsutils;

$devprod = "logs";

if ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'securenetach/genfiles.pl'`;
if ( $cnt > 1 ) {
  print "genfiles.pl already running, exiting...\n";

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: securenetach - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

$mytime  = time();
$machine = `uname -n`;
$pid     = $$;

chop $machine;
open( outfile, ">/home/p/pay1/batchfiles/$devprod/securenetach/pid.txt" );
$pidline = "$mytime $$ $machine";
print outfile "$pidline\n";
close(outfile);

&miscutils::mysleep(2.0);

open( infile, "/home/p/pay1/batchfiles/$devprod/securenetach/pid.txt" );
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
  print MAILERR "Subject: securenetach - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

#open(checkin,"/home/p/pay1/batchfiles/$devprod/securenetach/genfiles.txt");
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

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 8 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 60 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$twomonthsagotime = $twomonthsago . "000000";

#print "two months ago: $twomonthsago\n";

$threemonthsago     = $onemonthsago;
$threemonthsagotime = $threemonthsago . "000000";

%returncodes = (
  "R01", "Insufficient Funds",                               "R02", "Account Closed",
  "R03", "No Account",                                       "R04", "Invalid Account Number",
  "R06", "Returned per ODFI's Request",                      "R07", "Authorization Revoked by Customer",
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

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $dummy, $today, $ttime ) = &miscutils::genorderid();

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/p/pay1/batchfiles/logs/securenetach/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/p/pay1/batchfiles/logs/securenetach/$fileyearonly");
  chmod( 0700, "/home/p/pay1/batchfiles/logs/securenetach/$fileyearonly" );
}
if ( !-e "/home/p/pay1/batchfiles/logs/securenetach/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/p/pay1/batchfiles/logs/securenetach/$filemonth");
  chmod( 0700, "/home/p/pay1/batchfiles/logs/securenetach/$filemonth" );
}
if ( !-e "/home/p/pay1/batchfiles/logs/securenetach/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/p/pay1/batchfiles/logs/securenetach/$fileyear");
  chmod( 0700, "/home/p/pay1/batchfiles/logs/securenetach/$fileyear" );
}
if ( !-e "/home/p/pay1/batchfiles/logs/securenetach/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: securenetach - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/securenetach/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;

$dbh2 = &miscutils::dbhconnect("pnpdata");

print "aaaa\n";

# xxxx
#and t.username='minnesotav'
# homeclip should not be batched, it shares the same account as golinte1
$sthtrans = $dbh2->prepare(
  qq{
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>='$onemonthsago'
        and t.trans_date<='$today'
        $checkstring
        and t.finalstatus in ('pending','lockedx')
        and t.accttype in ('checking','savings')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.processor='securenetach'
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

print "bbbb\n";

foreach $username ( sort @userarray ) {
  $usererrorflag = 0;

  if ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) {
    unlink "/home/p/pay1/batchfiles/$devprod/securenetach/batchfile.txt";
    last;
  }

  umask 0033;
  open( checkin, ">/home/p/pay1/batchfiles/$devprod/securenetach/genfiles.txt" );
  print checkin "$username\n";
  close(checkin);

  umask 0033;
  open( batchfile, ">/home/p/pay1/batchfiles/$devprod/securenetach/batchfile.txt" );
  print batchfile "$username\n";
  close(batchfile);

  $starttransdate = $starttdatearray{$username};
  $starttranstime = $starttransdate . "000000";

  print "$username $usercountarray{$username} $starttransdate\n";

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/logs/securenetach/$fileyear/$username$time.txt" );
  print "$username\n";
  print logfile "$username\n";
  close(logfile);

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
        select merchant_id,pubsecret,proc_type,company,addr1,city,state,zip,tel,status
        from customers
        where username='$username'
        }
    )
    or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthcust->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $merchant_id, $terminal_id, $proc_type, $company, $address, $city, $state, $zip, $tel, $status, $country ) = $sthcust->fetchrow;
  $sthcust->finish;

  my $sthinfo = $dbh->prepare(
    qq{
          select loginun,loginpw
          from securenetach
          where username='$username'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $loginun, $loginpw ) = $sthinfo->fetchrow;
  $sthinfo->finish;

  $dbh->disconnect;

  print "$username $status\n";

  if ( $status ne "live" ) {
    next;
  }

  print "aaaa $starttransdate $onemonthsagotime $username\n";

  &pidcheck();

  $batch_flag = 0;
  $netamount  = 0;
  $hashtotal  = 0;
  $batchcnt   = 1;
  $recseqnum  = 0;

  $sthtrans = $dbh2->prepare(
    qq{
        select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,origamount,accttype,card_name,acct_code,acct_code2,acct_code3,descr
        from operation_log
        where trans_date>='$starttransdate'
        and lastoptime>='$onemonthsagotime'
        and username='$username'
        and lastopstatus in ('pending','lockedx','problem')
        and lastop IN ('authx','postauthx','return','forceauthx')
        and (voidstatus is NULL or voidstatus ='')
        and accttype in ('checking','savings')
        and processor='securenetach'
        order by lastoptime
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthtrans->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthtrans->bind_columns(
    undef,
    \($orderid,     $operation, $trans_date, $trans_time, $enccardnumber, $enclength, $exp,        $amount,     $auth_code,  $avs_code, $refnumber,
      $finalstatus, $cvvresp,   $transflags, $origamount, $accttype,      $card_name, $acct_code1, $acct_code2, $acct_code3, $authdescr
     )
  );

  $dontchecklockedcnt = 0;
  while ( $sthtrans->fetch ) {
    if ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) {
      unlink "/home/p/pay1/batchfiles/$devprod/securenetach/batchfile.txt";
      last;
    }

    if ( ( $finalstatus eq "problem" ) && ( ( $operation ne "auth" ) || ( $authdescr !~ /must be voided/ ) ) ) {
      next;
    }

    if ( ( $finalstatus eq "locked" ) && ( $operation !~ /^(return|postauth)$/ ) ) {
      next;
    }

    # new 05/05/2007
    # stop doing showdetails after getting 10 not SETTLED responses, because there shouldn't be anymore SETTLED after that
    if ( ( $operation eq "postauth" ) && ( $finalstatus eq "locked" ) && ( $dontchecklockedcnt >= 10 ) ) {
      next;
    }

    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/logs/securenetach/$fileyear/$username$time.txt" );
    print logfile "$orderid $operation\n";
    close(logfile);
    print "$orderid $operation $auth_code $refnumber\n";

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "securenetach", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
    ( $routenum, $acctnum ) = split( / /, $cardnumber );

    $errorflag = &errorchecking();
    print "cccc $errorflag\n";
    if ( $errorflag == 1 ) {
      next;
    }

    if ( $batchcnt == 1 ) {
      $batchnum = "";

      #&getbatchnum();
    }

    if ( ( $operation =~ /^(return|postauth)$/ ) && ( $finalstatus eq "pending" ) ) {
      my $sthlock = $dbh2->prepare(
        qq{
            update trans_log set finalstatus='locked',result='$time$batchnum',detailnum='$detailnum'
	    where orderid='$orderid'
	    and trans_date>='$onemonthsago'
	    and finalstatus='pending'
	    and username='$username'
            and accttype in ('checking','savings')
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
          and accttype in ('checking','savings')
          }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthop->execute("$time$batchnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthop->finish;
    }

    $returnflag = 0;
    &batchdetail();

    my $host = "gateway.securenet.com";
    my $port = "443";
    my $path = "/API/Gateway.svc/SOAP";
    if ( $username eq "testsec" ) {
      $host = "certify.securenet.com";
      $port = "443";
      $path = "/API/Gateway.svc/SOAP";
    }

    my $req = "POST https://gateway.securenet.com/API/Gateway.svc/soap HTTP/1.1\r\n";
    $req .= "Host: $host\r\n";
    $req .= "Content-Type: text/xml; charset=utf-8\r\n";
    $req .= "SOAPAction: \"http://gateway.securenet.com/API/Contracts/IGateway/ProcessTransaction\"\r\n";

    $req .= "Content-Length: ";

    my $msglen = length($message);
    $req .= "$msglen\r\n";

    $req .= "\r\n";
    $req .= "$message";

    my $messagestr = $req;
    my $xs         = "x" x length($cardnumber);
    $messagestr =~ s/CreditCardNumber>[0-9]+<\/CreditCardNumber/CreditCardNumber>$xs<\/CreditCardNumber/;

    $mytime = gmtime( time() );

    #my $week = substr($securenetach::trans_time,6,2) / 7;
    #$week = sprintf("%d", $week + .0001);
    open( logfile, ">>/home/p/pay1/batchfiles/logs/securenetach/$fileyear/$username$time.txt" );
    print logfile "$username  $orderid  $shacardnumber 3 $refnumber\n";
    print logfile "$mytime send: $username $messagestr\n\n";
    close(logfile);

    my ( $response, $header ) = &securenetach::sslsocketwrite( "$req", "$host", "$port" );

    &endbatch($response);
    if ( $usererrorflag == 1 ) {
      last;
    }

  }
  $sthtrans->finish;

  if ( $batchcnt > 1 ) {
    %errorderid = ();
    $detailnum  = 0;
  }
}

if ( !-e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) {
  umask 0033;
  open( checkin, ">/home/p/pay1/batchfiles/$devprod/securenetach/genfiles.txt" );
  close(checkin);
}

$dbh2->disconnect;

unlink "/home/p/pay1/batchfiles/$devprod/securenetach/batchfile.txt";

close(SOCK);

exit;

sub endbatch {
  my ($response) = @_;

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/logs/securenetach/$fileyear/$username$time.txt" );
  print logfile "aaaa before database\n";
  close(logfile);

  $dbh = &miscutils::dbhconnect("pnpmisc");

  $mytime = gmtime( time() );
  my $chkmessage = $response;
  $chkmessage =~ s/\>\</\>\n\</g;
  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/logs/securenetach/$fileyear/$username$time.txt" );
  print logfile "$username  $orderid\n";
  if ( $response ne "" ) {
    print logfile "$mytime recv: $chkmessage\n\n";
  } else {
    print logfile "$mytime recv: $header\n\n";
  }
  print "$mytime recv:\n$chkmessage\n\n";
  close(logfile);

  $response =~ s/\n/ /g;
  $response =~ s/\r/ /g;
  $response =~ s/>\s*</>;</g;
  my @tmpfields = split( /;/, $response );
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

  foreach my $var ( sort keys %temparray ) {
    print "aa $var   $temparray{$var}\n";
  }

  $respcode  = $temparray{'s:Envelope,s:Body,ProcessTransactionResponse,ProcessTransactionResult,TRANSACTIONRESPONSE,RESPONSE_CODE'};
  $descr     = $temparray{'s:Envelope,s:Body,ProcessTransactionResponse,ProcessTransactionResult,TRANSACTIONRESPONSE,RESPONSE_REASON_TEXT'};
  $refnumber = $temparray{'s:Envelope,s:Body,ProcessTransactionResponse,ProcessTransactionResult,TRANSACTIONRESPONSE,TRANSACTIONID'};
  $transid   = $temparray{'s:Envelope,s:Body,ProcessTransactionResponse,ProcessTransactionResult,TRANSACTIONRESPONSE,TRANSACTIONID'};

  #$auth_code = $temparray{'soap:Envelope,soap:Body,ProcessResponse,ProcessResult,Approval_Code'};
  if ( ( $respcode eq "" ) && ( $descr eq "" ) ) {
    $descr = $temparray{'s:Envelope,s:Body,s:Fault,faultstring'};
  }

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/logs/securenetach/$fileyear/$username$time.txt" );
  print logfile "orderid   $orderid\n";
  print logfile "operation   $operation\n";
  print logfile "transid   $transid\n";
  print logfile "transtype   $transtype\n";
  print logfile "respcode   $respcode\n";
  print logfile "returncode   $returncode\n";
  print logfile "descr   $descr\n";
  print logfile "result   $time$batchnum\n\n\n";

  print "orderid   $orderid\n";
  print "operation   $operation\n";
  print "transid   $transid\n";
  print "transtype   $transtype\n";
  print "respcode   $respcode\n";
  print "returncode   $returncode\n";
  print "descr   $descr\n";
  print "result   $time$batchnum\n\n\n";
  close(logfile);

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  print "gggg $operation  $finalstatus  aa$respcode" . "aa $paymenttype\n";

  %datainfo = ( 'username', "$username", 'orderid', "$orderid", 'descr', "$descr", 'operation', "$operation", 'file', "$username$time.txt" );

  if ( ( $operation eq "auth" ) && ( $finalstatus eq "problem" ) && ( $authdescr =~ /must be voided/ ) && ( $respcode eq "VOIDED" ) ) {
    $err_msg = "HELD: Transaction voided";

    my $sthfail = $dbh2->prepare(
      qq{
            update trans_log set descr=?
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and username='$username'
            and accttype in ('checking','savings')
            and finalstatus='problem'
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthfail->execute("$err_msg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthfail->finish;

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set descr=?
            where orderid='$orderid'
            and lastoptime>='$onemonthsagotime'
            and $operationstatus='problem'
            and (voidstatus is NULL or voidstatus ='')
            and accttype in ('checking','savings')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute("$err_msg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;
  } elsif ( $descr eq "Invalid Transaction ID" ) {
    &processproblem();
  } elsif ( ( $operation eq "auth" ) && ( $transtype ne "DEBIT" ) ) {
    $err_msg = "operation $operation not equal to transtype $transtype";

    my $sthfail = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='problem',descr=?
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and username='$username'
            and accttype in ('checking','savings')
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
            and accttype in ('checking','savings')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute("$err_msg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;

    #open(MAILERR,"| /usr/lib/sendmail -t");
    #print MAILERR "To: cprice\@plugnpay.com\n";
    #print MAILERR "From: dcprice\@plugnpay.com\n";
    #print MAILERR "Subject: securenetach - settlement error\n";
    #print MAILERR "\n";
    #print MAILERR "username: $username\n";
    #print MAILERR "orderid: $orderid\n";
    #print MAILERR "transid: $transid\n";
    #print MAILERR "operation: $operation\n\n";
    #print MAILERR "transtype: $transtype\n";
    #close MAILERR;
  } elsif ( ( $operation eq "postauth" ) && ( $finalstatus eq "pending" ) && ( $respcode eq "" ) ) {
    my $sthfail = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='pending'
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and username='$username'
            and accttype in ('checking','savings')
            and finalstatus='locked'
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthfail->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthfail->finish;

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set $operationstatus='pending',lastopstatus='pending'
            where orderid='$orderid'
            and lastoptime>='$onemonthsagotime'
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and accttype in ('checking','savings')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: securenetach - settlement error postauth set to pending\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "orderid: $orderid\n";
    print MAILERR "transid: $transid\n";
    print MAILERR "operation: $operation\n\n";
    print MAILERR "transtype: $transtype\n";
    close MAILERR;
  } elsif ( $respcode eq "1" ) {
    print "cccc $orderid $onemonthsago $onemonthsagotime $username $operation\n";
    my $sthpass = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='success',trans_time=?,result=?
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and username='$username'
            and operation='$operation'
            and finalstatus in ('pending','locked')
            and accttype in ('checking','savings')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpass->execute( "$time", "$time$batchnum" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpass->finish;

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set $operationstatus='success',$operationtime=?,lastopstatus='success',lastoptime=?,batchfile=?
            where orderid='$orderid'
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and lastop='$operation'
            and $operationstatus in ('pending','locked')
            and (voidstatus is NULL or voidstatus ='')
            and accttype in ('checking','savings')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute( "$time", "$time", "$time$batchnum" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );

    my $sth_status = $dbh->prepare(
      qq{
          select username,orderid,trans_date,amount,card_type,descr,commission,paidamount,paiddate,transorderid,checknum
          from billingstatus
          where orderid='$orderid'
          and result='hold'
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_status->execute or die "Can't execute: $DBI::errstr";
    $sth_status->bind_columns( undef, \( $busername, $borderid, $btrans_date, $bamount, $bcard_type, $bdescr, $bcommission, $bpaidamount, $bpaiddate, $btransorderid, $bchecknum ) );

    while ( $sth_status->fetch ) {
      my $sth_insert = $dbh->prepare(
        qq{
            insert into billingreport
            (username,orderid,trans_date,amount,card_type,descr,commission,paidamount,paiddate,transorderid,checknum)
            values (?,?,?,?,?,?,?,?,?,?,?)
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_insert->execute( "$busername", "$borderid", "$btrans_date", "$bamount", "$bcard_type", "$bdescr", "$bcommission", "$bpaidamount", "$bpaiddate", "$btransorderid", "$bchecknum" )
        or die "Can't execute: $DBI::errstr";
      $sth_insert->finish;
    }
    $sth_status->finish;

    #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
    #print achfile "$remoteuser $todaytime update billingstatus set result='success' where orderid='$orderid' and result='hold'\n";
    #close(achfile);
    #print " ";

    my $sth_status = $dbh->prepare(
      qq{
          update billingstatus
          set result='success'
          where orderid='$orderid'
          and result='hold'
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_status->execute or die "Can't execute: $DBI::errstr";
    $sth_status->finish;

    #my $sth_status = $dbh->prepare(qq{
    #    select orderid from pending
    #    where transorderid='$orderid'
    #    and status='locked'
    #    }) or die "Can't prepare: $DBI::errstr";
    #$sth_status->execute or die "Can't execute: $DBI::errstr";
    #$sth_status->bind_columns(undef,\($oid));

    #while ($sth_status->fetch) {
    #  my $sth_upd = $dbh->prepare(qq{
    #      update quickbooks
    #      set result='success',trans_date='$today'
    #      where orderid='$orderid'
    #      and result='pending'
    #      }) or die "Can't prepare: $DBI::errstr";
    #  $sth_upd->execute or die "Can't execute: $DBI::errstr";
    #  $sth_upd->finish;
    #}
    #$sth_status->finish;

    #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
    #print achfile "$remoteuser $todaytime delete from pending where transorderid='$orderid' and status='locked'\n";
    #close(achfile);

    $sth_status = $dbh->prepare(
      qq{
          delete from pending 
          where transorderid='$orderid'
          and status='locked' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_status->execute or die "Can't execute: $DBI::errstr";
    $sth_status->finish;

    #$updstatus = "success";

  } elsif ( ( $respcode eq "RETURNED" ) && ( $transtype ne "" ) ) {
    &processreturn();
  } elsif ( $respcode eq "VOIDED" ) {
    if ( $respcode eq "VOIDED" ) {
      $descr = "transaction voided";
    }

    my $sth1 = $dbh2->prepare(
      qq{
                select orderid
                from trans_log
                where orderid='$orderid'
                and trans_date>='$onemonthsago'
                and username='$username'
                and finalstatus in ('pending','locked')
                and accttype in ('checking','savings')
                and descr='$descr'
             }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth1->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ($chkorderid) = $sth1->fetchrow;
    $sth1->finish;

    $emailflag = 1;
    if ( $chkorderid ne "" ) {
      $emailflag = 0;
    }

    my $sthpass = $dbh2->prepare(
      qq{
            update trans_log set finalstatus='badcard',result=?,descr=?
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and username='$username'
            and finalstatus in ('pending','locked')
            and accttype in ('checking','savings')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthpass->execute( "$time$batchnum", "$descr" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthpass->finish;

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set $operationstatus='badcard',lastopstatus='badcard',batchfile=?,descr=?
            where orderid='$orderid'
            and lastoptime>='$onemonthsagotime'
            and username='$username'
            and $operationstatus in ('pending','locked')
            and (voidstatus is NULL or voidstatus ='')
            and accttype in ('checking','savings')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute( "$time$batchnum", "$descr" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );

    # new 01/13/2005
    $pnpcompany = "Plug and Pay";
    $pnpemail   = "accounting\@plugnpay.com";

    my $sth_res = $dbh->prepare(
      qq{
              select reseller,merchemail from customers
              where username='$username'
              }
      )
      or die "Can't do: $DBI::errstr";
    $sth_res->execute or die "Can't execute: $DBI::errstr";
    ( $reseller, $email ) = $sth_res->fetchrow;
    $sth_res->finish;

    if ( $plcompany{$reseller} ne "" ) {
      $privatelabelflag    = 1;
      $privatelabelcompany = $plcompany{$reseller};
      $privatelabelemail   = $plemail{$reseller};
    } else {
      $privatelabelflag    = 0;
      $privatelabelcompany = $pnpcompany;
      $privatelabelemail   = $pnpemail;
    }

    print "privatelabelcompany: $privatelabelcompany\n";
    print "email: $email\n";
    print "orderid: $orderid\n";
    print "reason: $descr\n";

    if ( $emailflag == 1 ) {
      open( MAIL, "| /usr/lib/sendmail -t" );
      print MAIL "To: $email\n";
      print MAIL "Bcc: cprice\@plugnpay.com\n";
      print MAIL "Bcc: barbara\@plugnpay.com\n";
      print MAIL "From: $privatelabelemail\n";
      print MAIL "Subject: $privatelabelcompany - securenetach Order $username $orderid failed\n";
      print MAIL "\n";
      print MAIL "$username\n\n";
      print MAIL "We would like to inform you that order $orderid was voided\n";
      print MAIL "today.\n\n";
      print MAIL "Orderid: $orderid\n\n";
      print MAIL "Card Name: $card_name\n\n";
      print MAIL "Amount: $amount\n\n";
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

    if ( $username =~ /^(pnpsmart|ach2|pnp)/ ) {
      print "$username $orderid $batchid $twomonthsago $descr<br>\n";

      #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
      #print achfile "$remoteuser $todaytime select username from billingstatus where orderid='$orderid'\n";
      #close(achfile);
      $sth_sel = $dbh->prepare(
        qq{
          select username,card_type from billingstatus
          where orderid='$orderid'
          }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_sel->execute or die "Can't execute: $DBI::errstr";
      ( $merchant, $chkcard_type ) = $sth_sel->fetchrow;
      $sth_sel->finish;
      print "cccc$merchant $orderid $chkcard_type<br>\n";

      if ( $chkcard_type eq "reseller" ) {
        $sth_sel2 = $dbh->prepare(
          qq{
            select reseller from customers
            where username='$merchant'
            }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_sel2->execute or die "Can't execute: $DBI::errstr";
        ($merchant) = $sth_sel2->fetchrow;
        $sth_sel2->finish;
      } else {

        #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
        #print achfile "$remoteuser $todaytime update pending set card_type='check' where username='$merchant'\n";
        #close(achfile);
        my $sth_pend = $dbh->prepare(
          qq{
            update pending
            set card_type='check'
            where username='$merchant'
            }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_pend->execute or die "Can't execute: $DBI::errstr";
        $sth_pend->finish;

        #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
        #print achfile "$remoteuser $todaytime update customers set accttype='check' where username='$merchant'\n";
        #close(achfile);
        my $sth_cust = $dbh->prepare(
          qq{
            update customers
            set accttype='check'
            where username='$merchant'
            }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_cust->execute or die "Can't execute: $DBI::errstr";
        $sth_cust->finish;
      }

      # yyyy

      #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
      #print achfile "$remoteuser $todaytime select merchemail,reseller,company from customers where username='$merchant'\n";
      #close(achfile);
      my $sth_cust = $dbh->prepare(
        qq{
          select merchemail,reseller,company
          from customers 
          where username='$merchant' 
          }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_cust->execute or die "Can't execute: $DBI::errstr";
      ( $email, $reseller, $company ) = $sth_cust->fetchrow;
      $sth_cust->finish;

      #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
      #print achfile "$remoteuser $todaytime select company,email from privatelabel where username='$reseller'\n";
      #close(achfile);
      $sth_pl = $dbh->prepare(
        qq{
            select company,email
            from privatelabel
            where username='$reseller'
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_pl->execute or die "Can't execute: $DBI::errstr";
      ( $plcompany, $plemail ) = $sth_pl->fetchrow;
      $sth_pl->finish;

      if ( $plcompany ne "" ) {
        $privatelabelflag    = 1;
        $privatelabelcompany = $plcompany;
        $privatelabelemail   = $plemail;
      } else {
        $privatelabelflag    = 0;
        $privatelabelcompany = "Plug & Pay Technologies, Inc.";
        $privatelabelemail   = "accounting\@plugnpay.com";
      }

      open( MAIL, "| /usr/lib/sendmail -t" );
      print MAIL "To: $email\n";
      print MAIL "Bcc: cprice\@plugnpay.com,barbara\@plugnpay.com,michelle\@plugnpay.com\n";
      print MAIL "From: $privatelabelemail\n";
      print MAIL "Subject: Monthly Billing - $privatelabelcompany - $username\n";
      print MAIL "\n";
      print MAIL "$company\n\n";
      print MAIL "Order ID: $orderid\n\n";

      print MAIL "The attempt to bill your checking account failed. There is a returned check\n";
      print MAIL "fee of \$20.00. If payment is not received by the end of the month then your\n";
      print MAIL "account will be closed. Once your account is closed it cannot be reopened\n";
      print MAIL "until we have received payment. When mailing a check please include your\n";
      print MAIL "username in the memo area of your check.\n\n";
      print MAIL "Contact 1-800-945-2538 if you have any questions or wish to arrange payment.\n\n";

      #if ($plcompany eq "") {
      print MAIL "Billing Address:\n";
      print MAIL "Plug \& Pay Technologies, Inc.\n";
      print MAIL "1019 Ft. Salonga Rd. ste 10\n";
      print MAIL "Northport, NY 11768\n";
      print MAIL "1\-800\-945\-2538\n\n";

      #}

      close(MAIL);

      #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
      #print achfile "$remoteuser $todaytime update pending set status='' where username='$merchant' and transorderid='$orderid' \n";
      #close(achfile);
      #where username='$merchant'
      #and transorderid='$orderid'
      my $sth_pend = $dbh->prepare(
        qq{
          update pending
          set status='' 
          where transorderid='$orderid' 
          }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_pend->execute or die "Can't execute: $DBI::errstr";
      $sth_pend->finish;

      #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
      #print achfile "$remoteuser $todaytime update billingstatus set result='badcard' where orderid='$orderid'\n";
      #close(achfile);
      $sth_status = $dbh->prepare(
        qq{
          update billingstatus 
          set result='badcard'
          where orderid='$orderid' 
          }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_status->execute or die "Can't execute: $DBI::errstr";
      $sth_status->finish;

      $errortype = "Return Fee: $descr $returncodes{$descr}";
      $fee       = "20.00";
      $type      = "check";

      #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
      #print achfile "$remoteuser $todaytime insert into pending orderid=$orderid,username=$merchant,amount=$fee,descr=$errortype,trans_date=$today,card_type=$type\n";
      #close(achfile);
      $sth_status = $dbh->prepare(
        qq{
            insert into pending
            (orderid,username,amount,descr,trans_date,card_type)
            values (?,?,?,?,?,?)
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_status->execute( "$orderid", "$merchant", "$fee", "$errortype", "$today", "$type" ) or die "Can't execute: $DBI::errstr";
      $sth_status->finish;
    } else {

      $sth_tl = $dbh2->prepare(
        qq{
            select acct_code3
            from trans_log
            where orderid='$orderid'
            and operation='auth'
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_tl->execute or die "Can't execute: $DBI::errstr";
      ($acct_code3) = $sth_tl->fetchrow;
      $sth_tl->finish;

      if ( $acct_code3 eq "recurring" ) {
        $dbhmerch = &miscutils::dbhconnect("$username");

        $sth_pl = $dbhmerch->prepare(
          qq{
            select username,orderid
            from billingstatus
            where orderid='$orderid'
            }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_pl->execute or die "Can't execute: $DBI::errstr";
        ( $chkusername, $chkorderid ) = $sth_pl->fetchrow;
        $sth_pl->finish;

        if ( $chkorderid ne "" ) {
          $sth_status = $dbhmerch->prepare(
            qq{
            insert into billingstatus
            (username,trans_date,amount,orderid,descr)
            values (?,?,?,?,?)
            }
            )
            or die "Can't prepare: $DBI::errstr";
          $sth_status->execute( "$chkusername", "$today", "-$amount", "$orderid", "$descr $returncodes{$descr}" ) or die "Can't execute: $DBI::errstr";
          $sth_status->finish;
        }
        $dbhmerch->disconnect;
      }

    }

  } elsif ( ( $operation eq "return" ) && ( $finalstatus eq "pending" ) && ( $respcode =~ /^(PENDING|HOLD|SUBMITTED)$/ ) ) {
    print "ffff  $orderid  $transid\n";
    my $sthfail = $dbh2->prepare(
      qq{
            update trans_log set refnumber=?
            where orderid='$orderid'
            and trans_date>='$onemonthsago'
            and username='$username'
            and accttype in ('checking','savings')
            and finalstatus='locked'
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthfail->execute("$transid") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthfail->finish;

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $sthop = $dbh2->prepare(
      qq{
            update operation_log set refnumber=?
            where orderid='$orderid'
            and lastoptime>='$onemonthsagotime'
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and accttype in ('checking','savings')
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute("$transid") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;

    my $sthmisc = $dbh->prepare(
      qq{
            insert into batchfilesall
            (username,trans_date,orderid,transid,operation)
            values (?,?,?,?,?)
            }
      )
      or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthmisc->execute( "$username", "$today", "$orderid", "$transid", "$operation" )
      or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo, %result );
    $sthmisc->finish;

  } elsif ( $respcode eq "PENDING" ) {
  } elsif ( ( $operation eq "postauth" ) && ( $finalstatus eq "locked" ) && ( $respcode eq "TRANSMITTED" ) ) {
    $dontchecklockedcnt++;
  } elsif ( $respcode eq "TRANSMITTED" ) {
  } elsif ( $respcode eq "RETURNED" ) {
  } elsif ( $respcode eq "SUBMITTED" ) {
    $dontchecklockedcnt++;
  } elsif ( $respcode eq "HOLD" ) {
  } elsif ( $respcode eq "Fail" ) {
  } elsif ( ( $respcode eq "VOIDED" ) && ( $username eq "mystique" ) ) {
  } elsif ( $descr =~ /user does not have permissions to access/ ) {
    $usererrorflag = 1;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: barbara\@plugnpay.com\n";
    print MAILERR "Cc: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: securenetach - error user does not have access\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "orderid: $orderid\n";
    print MAILERR "result: $respcode\n";
    print MAILERR "descr: $descr\n";
    print MAILERR "file: $username$time.txt\n";
    close MAILERR;
  } else {
    print "respcode	$respcode unknown\n";
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: securenetach - unknown error\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "orderid: $orderid\n";
    print MAILERR "result: $respcode\n";
    print MAILERR "file: $username$time.txt\n";
    close MAILERR;
  }
  $dbh->disconnect;
  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/logs/securenetach/$fileyear/$username$time.txt" );
  print logfile "bbbb after database\n";
  close(logfile);

}

sub getbatchnum {
  $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sthinfo = $dbh->prepare(
    qq{
          select login,password
          from securenetach
          where username='$username'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $login, $password ) = $sthinfo->fetchrow;
  $sthinfo->finish;

  $dbh->disconnect;

  #$batchnum = $batchnum + 1;
  #if ($batchnum >= 998) {
  #  $batchnum = 1;
  #}

  #my $sthinfo = $dbh->prepare(qq{
  #        update securenetach set batchnum=?
  #        where username='$username'
  #        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  #$sthinfo->execute("$batchnum") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
  #$sthinfo->finish;

  #$batchnum = substr("0000" . $batchnum,-4,4);

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

  $origorderid = substr( $auth_code, 6,  10 );
  $cardtype    = substr( $auth_code, 16, 1 );
  $paymenttype = substr( $auth_code, 17, 10 );
  $paymenttype =~ s/ +$//;
  $ipaddress = substr( $auth_code, 27, 20 );
  $ipaddress =~ s/ +$//;
  print "dddd $operation\n";

  @bd = ();
  if ( ( $operation eq "auth" ) && ( $finalstatus eq "problem" ) && ( $authdescr =~ /must be voided/ ) ) {
  } elsif ( ( ( $operation eq "postauth" ) && ( $finalstatus eq "pending" ) && ( $transflags =~ /authonly/ ) )
    || ( ( $operation eq "return" ) && ( $returnflag == 1 ) ) ) {
  }

  #elsif ($operation eq "postauth") {
  #  $bd[0] = "<XML>";
  #  $bd[1] = "<REQUEST>";
  #  $bd[2] = "<ACTION>SET_PAYMENT</ACTION>";
  #}
  elsif ( $operation eq "return" ) {

    #$transseqnum = &securenetach::gettransid($username);

    @bd = ();

    $bd[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>";    # stx

    $bd[1] = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">";
    $bd[2] = "<s:Body>";
    $bd[3] = "<ProcessTransaction xmlns=\"http://gateway.securenet.com/API/Contracts\">";
    $bd[4] = "<TRANSACTION xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\">";

    my ( $curr, $amt ) = split( / /, $amount );
    $bd[6] = "<AMOUNT>$amt</AMOUNT>";

    #$bd[6] = "<AUTHCODE/>";
    #$bd[7] = "<AUTO i:nil=\"true\"/>";
    #$bd[8] = "<CARD i:nil=\"true\"/>";

    $bd[7]  = "<CASHBACK_AMOUNT>0.00</CASHBACK_AMOUNT>";
    $bd[10] = "<CHECK>";
    $bd[11] = "<ABACODE>$routenum</ABACODE>";
    $bd[12] = "<ACCOUNTNAME>$card_name</ACCOUNTNAME>";
    $bd[13] = "<ACCOUNTNUM>$acctnum</ACCOUNTNUM>";

    $seccode = substr( $auth_code, 6, 3 );
    $seccode =~ tr/a-z/A-Z/;
    if ( $seccode eq "" ) {
      $seccode = "PPD";
    }

    my $acttype = $accttype;
    $acttype =~ s/ //g;
    $acttype =~ tr/a-z/A-Z/;
    if ( ( ( $seccode eq "CCD" ) || ( $securenetach::datainfo{'commcardtype'} ne "" ) ) && ( $acttype eq "CHECKING" ) ) {
      $acttype = "BCHECK";
    } elsif ( ( ( $seccode eq "CCD" ) || ( $securenetach::datainfo{'commcardtype'} ne "" ) ) && ( $acttype eq "SAVINGS" ) ) {
      $acttype = "BSAVE";
    }
    $bd[15] = "<ACCOUNTTYPE>$acttype</ACCOUNTTYPE>";

    # $securenetach::datainfo{'bankname'}
    #$bd[16] = "<BANKNAME/>";

    #if ($securenetach::datainfo{'checknum'} ne "") {
    #  $bd[17] = "<CHECKNUM>$securenetach::datainfo{'checknum'}</CHECKNUM>";
    #}
    #if ($securenetach::datainfo{'micr'} ne "") {
    #  $bd[18] = "<MICRDATA>$securenetach::datainfo{'micr'}</MICRDATA>";
    #}

    $bd[19] = "<SECCODE>$seccode</SECCODE>";

    #$bd[19] = "<ADDITIONALINFO i:nil=\"true\"/>";
    $bd[20] = "</CHECK>";

    my $tcode = "0500";    # return
    $bd[21] = "<CODE>$tcode</CODE>";

    #$bd[22] = "<CUSTOMERID/>";

    #$securenetach::ipaddress = substr($ENV{'REMOTE_ADDR'},0,23);
    #$securenetach::ipaddress = "209.51.176.25";
    #$bd[23] = "<CUSTOMERIP>$securenetach::ipaddress</CUSTOMERIP>";

    #$bd[37] = "<CUSTOMER_SHIP i:nil=\"true\"/>";
    $bd[38] = "<DCI>0</DCI>";

    #$bd[39] = "<DEVICECODE/>";

    #$bd[40] = "<ENCRYPTION>";
    #$bd[41] = "<ENCRYPTIONMODE>0</ENCRYPTIONMODE>";
    #$bd[42] = "<KEYID i:nil=\"true\"/>";
    #$bd[43] = "<KSI i:nil=\"true\"/>";
    #$bd[44] = "</ENCRYPTION>";

    #$bd[45] = "<ENTRYSOURCE/>";
    #$bd[46] = "<HOTEL i:nil=\"true\"/>";
    #$bd[47] = "<INDUSTRYSPECIFICDATA>0</INDUSTRYSPECIFICDATA>";
    $bd[48] = "<INSTALLMENT_SEQUENCENUM>0</INSTALLMENT_SEQUENCENUM>";

    #$bd[49] = "<INVOICEDESC/>";
    #$bd[50] = "<INVOICENUM/>";
    #$bd[51] = "<LEVEL2 i:nil=\"true\"/>";
    #$bd[52] = "<LEVEL3 i:nil=\"true\"/>";
    #$bd[53] = "<MARKETSPECIFICDATA i:nil=\"true\"/>";

    $bd[54] = "<MERCHANT_KEY>";
    $bd[55] = "<GROUPID>0</GROUPID>";
    $bd[56] = "<SECUREKEY>$loginpw</SECUREKEY>";
    $bd[57] = "<SECURENETID>$loginun</SECURENETID>";

    #$bd[58] = "<ADDITIONALINFO i:nil=\"true\"/>";
    $bd[59] = "</MERCHANT_KEY>";

    $bd[60] = "<METHOD>ECHECK</METHOD>";

    #$bd[61] = "<MPI i:nil=\"true\"/>";
    $bd[62] = "<NOTE>$orderid</NOTE>";
    $bd[63] = "<ORDERID>$orderid" . "1</ORDERID>";
    $bd[64] = "<OVERRIDE_FROM>0</OVERRIDE_FROM>";

    #$bd[65] = "<PAYMENTID/>";
    #$bd[66] = "<PETROLEUM i:nil=\"true\"/>";
    #$bd[67] = "<PRODUCTS i:nil=\"true\"/>";

    #if ($securenetach::operation =~ /^(reauth|void)$/) {
    $bd[68] = "<REF_TRANSID>$refnumber</REF_TRANSID>";

    #}

    $bd[69] = "<RETAIL_LANENUM>0</RETAIL_LANENUM>";

    #$bd[70] = "<SECONDARY_MERCHANT_KEY i:nil=\"true\"/>";
    #$bd[71] = "<SERVICE i:nil=\"true\"/>";
    #$bd[72] = "<SOFTDESCRIPTOR/>";

    $bd[73] = "<TEST>FALSE</TEST>";

    $bd[74] = "<TOTAL_INSTALLMENTCOUNT>0</TOTAL_INSTALLMENTCOUNT>";
    $bd[75] = "<TRANSACTION_SERVICE>0</TRANSACTION_SERVICE>";

    #$bd[76] = "<USERDEFINED i:nil=\"true\"/>";

    $bd[77] = "<DEVELOPERID>10000298</DEVELOPERID>";

    #$bd[78] = "<TERMINAL i:nil=\"true\"/>";
    #$bd[79] = "<VERSION>1</VERSION>";
    #$bd[80] = "<HEALTHCARE i:nil=\"true\"/>";
    #$bd[81] = "<IMAGE i:nil=\"true\"/>";
    $bd[82] = "</TRANSACTION>";
    $bd[83] = "</ProcessTransaction>";
    $bd[84] = "</s:Body>";
    $bd[85] = "</s:Envelope>";
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
    $message = $message . $var . "\n";

    #$message = $message . " " x $indent . $var . "\n";
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

  my $messagestr = $msg;

  if ( $messagestr =~ /ABANumber>([0-9]+)<\/ABANumber/ ) {
    $routenum = $1;
    $xs       = "x" x length($routenum);
    $messagestr =~ s/ABANumber>[0-9]+<\/ABANumber/ABANumber>$xs<\/ABANumber/;
  }
  if ( $messagestr =~ /AccountNumber>([0-9]+)<\/AccountNumber/ ) {
    $acctnum = $1;
    $xs      = "x" x length($acctnum);
    $messagestr =~ s/AccountNumber>[0-9]+<\/AccountNumber/AccountNumber>$xs<\/AccountNumber/;
  }
  if ( $messagestr =~ /Username>([0-9]+)<\/Username/ ) {
    $data = $1;
    $xs   = "x" x length($data);
    $messagestr =~ s/Username>[0-9]+<\/Username/Username>$xs<\/Username/;
  }
  if ( $messagestr =~ /Password>([0-9]+)<\/Password/ ) {
    $data = $1;
    $xs   = "x" x length($data);
    $messagestr =~ s/Password>[0-9]+<\/Password/Password>$xs<\/Password/;
  }

  my $tmpcardnum = "$routenum $acctnum";
  $tmpcardnum =~ s/[^0-9 ]//g;
  my $tmpcardlen    = length($tmpcardnum);
  my $shacardnumber = "";
  if ( ( $tmpcardlen > 12 ) && ( $tmpcardlen < 40 ) ) {
    my $cc = new PlugNPay::CreditCard($tmpcardnum);
    $shacardnumber = $cc->getCardHash();
  }

  $mytime = gmtime( time() );
  my $chkmessage = $msg;
  $chkmessage =~ s/\>\</\>\n\</g;
  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/logs/securenetach/$fileyear/$username$time.txt" );
  print logfile "$username  $orderid  $routenum  $acctnum  $shacardnumber\n";
  print logfile "$mytime send: $chkmessage\n\n";
  print "$mytime send:\n$chkmessage\n\n";
  print logfile "sequencenum: $sequencenum retries: $retries\n";
  close(logfile);

  Net::SSLeay::load_error_strings();
  Net::SSLeay::SSLeay_add_ssl_algorithms();
  Net::SSLeay::randomize('/etc/passwd');

  #my $mime_type = 'application/xml; charset="utf-8"';
  my $mime_type = 'application/x-www-form-urlencoded';

  #$msg = "IN=" . $msg;
  my $len = length($msg);

  # xxxx
  my $un      = "Demo";
  my $pw      = "Demo";
  my $content = "Content-Type: $mime_type\r\n" . "Content-Length: $len\r\n\r\n$msg";

  #my $req = "POST $path HTTP/1.0\r\nHost: $host\r\n" . "Accept: */*\r\n$content";
  my $req = "POST $path HTTP/1.0\r\nHost: $host:$port\r\n" . "Accept: */*\r\n";
  $req .= "Authorization: Basic " . &MIME::Base64::encode( "$un:$pw", "\r\n" ) . "$content";

  print "send:\n$req\n";

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
  $res = Net::SSLeay::connect($ssl) or &securenetacherror("$!");

  #$res = Net::SSLeay::connect($ssl) and Net::SSLeay::die_if_ssl_error("ssl connect");

  #open(TMPFILE,">>/home/p/pay1/logfiles/ciphers.txt");
  #print TMPFILE __FILE__ . ": " . Net::SSLeay::get_cipher($ssl) . "\n";
  #close(TMPFILE);

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/logs/securenetach/$fileyear/$username$time.txt" );
  print logfile "cccc socket connected\n";
  close(logfile);

  # Exchange data
  $res = Net::SSLeay::ssl_write_all( $ssl, $req );    # Perl knows how long $msg is
  Net::SSLeay::die_if_ssl_error("ssl write");

  #shutdown S, 1;  # Half close --> No more output, sends EOF to server

  my $response = "";

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/logs/securenetach/$fileyear/$username$time.txt" );
  print logfile "dddd data written\n";
  close(logfile);

  #shutdown S, 1;  # Half close --> No more output, sends EOF to server
  my ( $rin, $rout, $temp );
  vec( $rin, $temp = fileno(S), 1 ) = 1;
  $count = 8;
  while ( $count && select( $rout = $rin, undef, undef, 80.0 ) ) {
    $got      = Net::SSLeay::read($ssl);    # Perl returns undef on failure
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

  my $messagestr = $response;
  if ( $messagestr =~ /ABANumber>([0-9]+)<\/ABANumber/ ) {
    $routenum = $1;
    $xs       = "x" x length($routenum);
    $messagestr =~ s/ABANumber>[0-9]+<\/ABANumber/ABANumber>$xs<\/ABANumber/;
  }
  if ( $messagestr =~ /AccountNumber>([0-9]+)<\/AccountNumber/ ) {
    $acctnum = $1;
    $xs      = "x" x length($acctnum);
    $messagestr =~ s/AccountNumber>[0-9]+<\/AccountNumber/AccountNumber>$xs<\/AccountNumber/;
  }

  $mytime = gmtime( time() );
  my $chkmessage = $messagestr;
  $chkmessage =~ s/\>\</\>\n\</g;
  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/logs/securenetach/$fileyear/$username$time.txt" );
  print logfile "$username  $orderid\n";
  print logfile "$mytime recv: $chkmessage\n\n";
  print "$mytime recv:\n$chkmessage\n\n";
  close(logfile);

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
  if ( ( $enclength > 1024 ) || ( $enclength < 30 ) ) {
    $errmsg = "could not decrypt";
  }

  $mylen = length($cardnumber);
  if ( ( $mylen < 11 ) || ( $mylen > 32 ) ) {
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
            and accttype in ('checking','savings')
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
            and accttype in ('checking','savings')
            }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthop->execute("$errmsg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthop->finish;

}

sub processproblem {

  #yyyyyyyyyyyyyyyyyyyyyy

  $file = "$time$batchnum";

  %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

  my $sth1 = $dbh2->prepare(
    qq{
          select orderid
          from trans_log
          where orderid='$orderid'
          and trans_date>='$threemonthsago'
          and username='$username'
          and operation='$operation'
          and descr='$descr'
       }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth1->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ($chkorderid) = $sth1->fetchrow;
  $sth1->finish;

  $emailflag = 1;
  if ( $chkorderid ne "" ) {
    $emailflag = 0;
  }

  print "aa username: $username\n";
  print "aa orderid: $orderid\n";
  print "aa operation: $operation\n";
  print "aa descr: $descr\n";
  print "aa file: $file\n";

  # yyyy
  #open(logfile,">>/home/p/pay1/batchfiles/logs/securenetach/chk$username.txt");
  #print logfile "aa username: $username\n";
  #print logfile "aa orderid: $orderid\n";
  #print logfile "aa operation: $operation\n";
  #print logfile "aa descr: $descr\n";
  #print logfile "aa file: $file\n";
  #print logfile "aa threemonthsago: $threemonthsago\n";
  #print logfile "aa threemonthsagotime: $threemonthsagotime\n";
  #print logfile "aa emailflag: $file\n\n";
  #close(logfile);

  my $sthfail = $dbh2->prepare(
    qq{
          update trans_log set finalstatus='problem',result=?,descr=?
          where orderid='$orderid'
          and trans_date>='$threemonthsago'
          and username='$username'
          and operation='$operation'
          and accttype in ('checking','savings')
       }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthfail->execute( "$file", "$descr" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthfail->finish;

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";
  my $sthop = $dbh2->prepare(
    qq{
          update operation_log set $operationstatus='problem',batchfile=?,descr=?
          where orderid='$orderid'
          and lastoptime>='$threemonthsagotime'
          and username='$username'
          and (voidstatus is NULL or voidstatus ='')
          and accttype in ('checking','savings')
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthop->execute( "$file", "$descr" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthop->finish;

  my $sthop2 = $dbh2->prepare(
    qq{
          update operation_log set lastopstatus='problem'
          where orderid='$orderid'
          and lastoptime>='$threemonthsagotime'
          and username='$username'
          and lastop='$operation'
          and accttype in ('checking','savings')
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthop2->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthop2->finish;

  $pnpcompany = "Plug and Pay";
  $pnpemail   = "accounting\@plugnpay.com";

  my $sth_res = $dbh->prepare(
    qq{
        select reseller,merchemail from customers
        where username='$username'
        }
    )
    or die "Can't do: $DBI::errstr";
  $sth_res->execute or die "Can't execute: $DBI::errstr";
  ( $reseller, $email ) = $sth_res->fetchrow;
  $sth_res->finish;

  if ( $plcompany{$reseller} ne "" ) {
    $privatelabelflag    = 1;
    $privatelabelcompany = $plcompany{$reseller};
    $privatelabelemail   = $plemail{$reseller};
  } else {
    $privatelabelflag    = 0;
    $privatelabelcompany = $pnpcompany;
    $privatelabelemail   = $pnpemail;
  }

  $sth_tl = $dbh2->prepare(
    qq{
          select acct_code3
          from trans_log
          where orderid='$orderid'
          and operation='postauth'
          }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_tl->execute or die "Can't execute: $DBI::errstr";
  ($acct_code3) = $sth_tl->fetchrow;
  $sth_tl->finish;

  if ( $acct_code3 eq "recurring" ) {
    $dbhmerch = &miscutils::dbhconnect("$username");

    $sth_pl = $dbhmerch->prepare(
      qq{
          select username,orderid
          from billingstatus
          where orderid='$orderid'
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_pl->execute or die "Can't execute: $DBI::errstr";
    ( $chkusername, $chkorderid ) = $sth_pl->fetchrow;
    $sth_pl->finish;

    if ( $chkorderid ne "" ) {
      $sth_status = $dbhmerch->prepare(
        qq{
          insert into billingstatus
          (username,trans_date,amount,orderid,descr)
          values (?,?,?,?,?)
          }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_status->execute( "$chkusername", "$today", "-$amount", "$orderid", "$descr" ) or die "Can't execute: $DBI::errstr";
      $sth_status->finish;
    }
    $dbhmerch->disconnect;
  }

  print "privatelabelcompany: $privatelabelcompany\n";
  print "email: $email\n";
  print "orderid: $orderid\n";
  print "reason: $descr\n";

  if ( $emailflag == 1 ) {
    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: $email\n";
    print MAIL "Bcc: cprice\@plugnpay.com\n";
    print MAIL "Bcc: barbara\@plugnpay.com\n";
    print MAIL "From: $privatelabelemail\n";
    print MAIL "Subject: $privatelabelcompany - securenetach Order $username $orderid failed\n";
    print MAIL "\n";
    print MAIL "$username\n\n";
    print MAIL "We would like to inform you that order $orderid failed\n";
    print MAIL "today.\n\n";
    print MAIL "Orderid: $orderid\n\n";
    print MAIL "Card Name: $card_name\n\n";
    print MAIL "Amount: $amount\n\n";

    if ( $authtime1 ne "" ) {
      $authdate = substr( $authtime1, 4, 2 ) . "/" . substr( $authtime1, 6, 2 ) . "/" . substr( $authtime1, 0, 4 );
      print outfile "Auth Date: $authdate\n";
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

  if ( $username =~ /^(pnpsmart|ach2)/ ) {
    print "$username $orderid $batchid $twomonthsago $descr<br>\n";

    #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
    #print achfile "$remoteuser $todaytime select username from billingstatus where orderid='$orderid'\n";
    #close(achfile);
    $sth_sel = $dbh->prepare(
      qq{
          select username,card_type from billingstatus
          where orderid='$orderid' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_sel->execute or die "Can't execute: $DBI::errstr";
    ( $merchant, $chkcard_type ) = $sth_sel->fetchrow;
    $sth_sel->finish;
    print "cccc$merchant $orderid $chkcard_type<br>\n";

    if ( $chkcard_type eq "reseller" ) {
      $sth_sel2 = $dbh->prepare(
        qq{
            select reseller from customers
            where username='$merchant'
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_sel2->execute or die "Can't execute: $DBI::errstr";
      ($merchant) = $sth_sel2->fetchrow;
      $sth_sel2->finish;
    } else {

      #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
      #print achfile "$remoteuser $todaytime update pending set card_type='check' where username='$merchant'\n";
      #close(achfile);
      my $sth_pend = $dbh->prepare(
        qq{ 
            update pending
            set card_type='check'
            where username='$merchant'
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_pend->execute or die "Can't execute: $DBI::errstr";
      $sth_pend->finish;

      #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
      #print achfile "$remoteuser $todaytime update customers set accttype='check' where username='$merchant'\n";
      #close(achfile);
      my $sth_cust = $dbh->prepare(
        qq{
            update customers 
            set accttype='check' 
            where username='$merchant' 
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_cust->execute or die "Can't execute: $DBI::errstr";
      $sth_cust->finish;
    }

    # yyyy

    #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
    #print achfile "$remoteuser $todaytime select merchemail,reseller,company from customers where username='$merchant'\n";
    #close(achfile);
    my $sth_cust = $dbh->prepare(
      qq{
          select email,reseller,company
          from customers 
          where username='$merchant' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_cust->execute or die "Can't execute: $DBI::errstr";
    ( $email, $reseller, $company ) = $sth_cust->fetchrow;
    $sth_cust->finish;

    #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
    #print achfile "$remoteuser $todaytime select company,email from privatelabel where username='$reseller'\n";
    #close(achfile);
    $sth_pl = $dbh->prepare(
      qq{
            select company,email
            from privatelabel
            where username='$reseller'
            }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_pl->execute or die "Can't execute: $DBI::errstr";
    ( $plcompany, $plemail ) = $sth_pl->fetchrow;
    $sth_pl->finish;

    if ( $plcompany ne "" ) {
      $privatelabelflag    = 1;
      $privatelabelcompany = $plcompany;
      $privatelabelemail   = $plemail;
    } else {
      $privatelabelflag    = 0;
      $privatelabelcompany = "Plug & Pay Technologies, Inc.";
      $privatelabelemail   = "accounting\@plugnpay.com";
    }

    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: $email\n";
    print MAIL "Bcc: cprice\@plugnpay.com,barbara\@plugnpay.com,michelle\@plugnpay.com\n";
    print MAIL "From: $privatelabelemail\n";
    print MAIL "Subject: Monthly Billing - $privatelabelcompany - $username\n";
    print MAIL "\n";
    print MAIL "$company\n";
    print MAIL "$orderid\n\n";

    print MAIL "The attempt to bill your checking account for your monthly gateway fee has failed.\n";
    print MAIL "There is a returned check fee of \$20.00 in addition to your monthly gateway fee.\n";
    print MAIL "If payment is not received by the end of the month then your account will be closed.\n";
    print MAIL "Once your account is closed it cannot be reopened until we have received payment.\n\n";

    print MAIL "To remit payment by check:\n";
    print MAIL "Please include your username in the memo area of your check.\n";
    print MAIL "Send check payment to:\n";
    print MAIL "Plug \& Pay Technologies, Inc.\n";
    print MAIL "1019 Ft. Salonga Rd. ste 10\n";
    print MAIL "Northport, NY 11768\n\n";

    print MAIL "To pay  by credit card:\n";
    print MAIL "Complete the Billing Authorization form located in your administration area.\n";
    print MAIL "Click on the link labeled Billing Authorization.\n";
    print MAIL "Print, complete the credit card section, sign and fax to the number on the form.\n\n";

    print MAIL "Contact 800-945-2538 if you have any questions.\n";

    close(MAIL);

    my $sth_pend = $dbh->prepare(
      qq{ 
          update pending 
          set status=''  
          where transorderid='$orderid' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_pend->execute or die "Can't execute: $DBI::errstr";
    $sth_pend->finish;

    # xxxx 08/11/2004  and result='success' added
    my $sth_statusa = $dbh->prepare(
      qq{
          select username,orderid,amount,card_type,descr,paidamount,transorderid
          from billingstatus
          where orderid='$orderid'
          and result='success'
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_statusa->execute or die "Can't execute: $DBI::errstr";
    $sth_statusa->bind_columns( undef, \( $busername, $borderid, $bamount, $bcard_type, $bdescr, $chkpaidamount, $btransorderid ) );

    while ( $sth_statusa->fetch ) {
      if ( $chkpaidamount ne "" ) {
        $sth_status3 = $dbh->prepare(
          qq{
            insert into billingreport
            (username,orderid,trans_date,amount,card_type,descr,paidamount,transorderid)
            values (?,?,?,?,?,?,?,?)
            }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_status3->execute( "$busername", "$borderid", "$today", "-$bamount", "$bcard_type", "$bdescr problem", "-$chkpaidamount", "$btransorderid" )
          or die "Can't execute: $DBI::errstr";
        $sth_status3->finish;
      } else {
        $sth_status3 = $dbh->prepare(
          qq{
            insert into billingreport
            (username,orderid,trans_date,amount,card_type,descr,transorderid)
            values (?,?,?,?,?,?,?)
            }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_status3->execute( "$busername", "$borderid", "$today", "-$bamount", "$bcard_type", "$bdescr problem", "$btransorderid" )
          or die "Can't execute: $DBI::errstr";
        $sth_status3->finish;
      }
    }
    $sth_statusa->finish;

    #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
    #print achfile "$remoteuser $todaytime update billingstatus set result='problem' where orderid='$orderid'\n";
    #close(achfile);
    $sth_status = $dbh->prepare(
      qq{
          update billingstatus  
          set result='problem' 
          where orderid='$orderid' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_status->execute or die "Can't execute: $DBI::errstr";
    $sth_status->finish;

    $errortype = "Return Fee: $descr";
    $fee       = "20.00";
    $type      = "check";

    $sthchk = $dbh->prepare(
      qq{
            select orderid
            from pending
            where username='$merchant'
            and orderid='$orderid'
            and descr like 'Return Fee%'
            }
      )
      or die "Can't prepare: $DBI::errstr";
    $sthchk->execute or die "Can't execute: $DBI::errstr";
    ($chkorderid) = $sthchk->fetchrow;
    $sthchk->finish;

    if ( $chkorderid eq "" ) {

#open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt"); print achfile "$remoteuser $todaytime insert into pending orderid=$orderid,username=$merchant,amount=$fee,descr=$errortype,trans_date=$today,card_type=$type\n";
#close(achfile);
      $sth_status = $dbh->prepare(
        qq{
              insert into pending 
              (orderid,username,amount,descr,trans_date,card_type)
              values (?,?,?,?,?,?) 
              }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_status->execute( "$orderid", "$merchant", "$fee", "$errortype", "$today", "$type" ) or die "Can't execute: $DBI::errstr";
      $sth_status->finish;
    }
  } else {

    $sth_tl = $dbh2->prepare(
      qq{
            select acct_code3
            from trans_log 
            where orderid='$orderid'
            and operation='auth' 
            }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_tl->execute or die "Can't execute: $DBI::errstr";
    ($acct_code3) = $sth_tl->fetchrow;
    $sth_tl->finish;

    if ( $acct_code3 eq "recurring" ) {
      $dbhmerch = &miscutils::dbhconnect("$username");

      $sth_pl = $dbhmerch->prepare(
        qq{
            select username,orderid
            from billingstatus 
            where orderid='$orderid' 
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_pl->execute or die "Can't execute: $DBI::errstr";
      ( $chkusername, $chkorderid ) = $sth_pl->fetchrow;
      $sth_pl->finish;

      if ( $chkorderid ne "" ) {
        $sth_status = $dbhmerch->prepare(
          qq{
            insert into billingstatus
            (username,trans_date,amount,orderid,descr)
            values (?,?,?,?,?) 
            }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_status->execute( "$chkusername", "$today", "-$amount", "$orderid", "$descr" ) or die "Can't execute: $DBI::errstr";
        $sth_status->finish;
      }
      $dbhmerch->disconnect;
    }
  }

  #yyyyyyyyyyyyyyyyyyyyyy

}

sub processreturn {

  #yyyyyyyyyyyyyyyyyyyyyy

  $file = "$time$batchnum";

  %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

  my $sth1 = $dbh2->prepare(
    qq{
          select orderid
          from trans_log
          where orderid='$orderid'
          and trans_date>='$threemonthsago'
          and username='$username'
          and operation='$operation'
          and descr='$descr'
       }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth1->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ($chkorderid) = $sth1->fetchrow;
  $sth1->finish;

  $emailflag = 1;
  if ( $chkorderid ne "" ) {
    $emailflag = 0;
  }

  print "aa username: $username\n";
  print "aa orderid: $orderid\n";
  print "aa operation: $operation\n";
  print "aa descr: $descr\n";
  print "aa file: $file\n";

  # yyyy
  #open(logfile,">>/home/p/pay1/batchfiles/logs/securenetach/chk$username.txt");
  #print logfile "aa username: $username\n";
  #print logfile "aa orderid: $orderid\n";
  #print logfile "aa operation: $operation\n";
  #print logfile "aa descr: $descr\n";
  #print logfile "aa file: $file\n";
  #print logfile "aa threemonthsago: $threemonthsago\n";
  #print logfile "aa threemonthsagotime: $threemonthsagotime\n";
  #print logfile "aa emailflag: $file\n\n";
  #close(logfile);

  my $sthfail = $dbh2->prepare(
    qq{
          update trans_log set finalstatus='badcard',result=?,descr=?
          where orderid='$orderid'
          and trans_date>='$threemonthsago'
          and username='$username'
          and operation='$operation'
          and accttype in ('checking','savings')
       }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthfail->execute( "$file", "$descr" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthfail->finish;

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";
  my $sthop = $dbh2->prepare(
    qq{
          update operation_log set $operationstatus='badcard',batchfile=?,descr=?
          where orderid='$orderid'
          and lastoptime>='$threemonthsagotime'
          and username='$username'
          and (voidstatus is NULL or voidstatus ='')
          and accttype in ('checking','savings')
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthop->execute( "$file", "$descr" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthop->finish;

  my $sthop2 = $dbh2->prepare(
    qq{
          update operation_log set lastopstatus='badcard'
          where orderid='$orderid'
          and lastoptime>='$threemonthsagotime'
          and username='$username'
          and lastop='$operation'
          and accttype in ('checking','savings')
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthop2->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthop2->finish;

  $pnpcompany = "Plug and Pay";
  $pnpemail   = "accounting\@plugnpay.com";

  my $sth_res = $dbh->prepare(
    qq{
        select reseller,merchemail from customers
        where username='$username'
        }
    )
    or die "Can't do: $DBI::errstr";
  $sth_res->execute or die "Can't execute: $DBI::errstr";
  ( $reseller, $email ) = $sth_res->fetchrow;
  $sth_res->finish;

  if ( $plcompany{$reseller} ne "" ) {
    $privatelabelflag    = 1;
    $privatelabelcompany = $plcompany{$reseller};
    $privatelabelemail   = $plemail{$reseller};
  } else {
    $privatelabelflag    = 0;
    $privatelabelcompany = $pnpcompany;
    $privatelabelemail   = $pnpemail;
  }

  $sth_tl = $dbh2->prepare(
    qq{
          select acct_code3
          from trans_log
          where orderid='$orderid'
          and operation='postauth'
          }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_tl->execute or die "Can't execute: $DBI::errstr";
  ($acct_code3) = $sth_tl->fetchrow;
  $sth_tl->finish;

  if ( $acct_code3 eq "recurring" ) {
    $dbhmerch = &miscutils::dbhconnect("$username");

    $sth_pl = $dbhmerch->prepare(
      qq{
          select username,orderid
          from billingstatus
          where orderid='$orderid'
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_pl->execute or die "Can't execute: $DBI::errstr";
    ( $chkusername, $chkorderid ) = $sth_pl->fetchrow;
    $sth_pl->finish;

    if ( $chkorderid ne "" ) {
      $sth_status = $dbhmerch->prepare(
        qq{
          insert into billingstatus
          (username,trans_date,amount,orderid,descr)
          values (?,?,?,?,?)
          }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_status->execute( "$chkusername", "$today", "-$amount", "$orderid", "$descr" ) or die "Can't execute: $DBI::errstr";
      $sth_status->finish;
    }
    $dbhmerch->disconnect;
  }

  print "privatelabelcompany: $privatelabelcompany\n";
  print "email: $email\n";
  print "orderid: $orderid\n";
  print "reason: $descr\n";

  if ( $emailflag == 1 ) {
    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: $email\n";
    print MAIL "Bcc: cprice\@plugnpay.com\n";
    print MAIL "Bcc: barbara\@plugnpay.com\n";
    print MAIL "From: $privatelabelemail\n";
    print MAIL "Subject: $privatelabelcompany - securenetach Order $username $orderid failed\n";
    print MAIL "\n";
    print MAIL "$username\n\n";
    print MAIL "We would like to inform you that order $orderid received a Return notice\n";
    print MAIL "today.\n\n";
    print MAIL "Orderid: $orderid\n\n";
    print MAIL "Card Name: $card_name\n\n";
    print MAIL "Amount: $amount\n\n";

    if ( $authtime1 ne "" ) {
      $authdate = substr( $authtime1, 4, 2 ) . "/" . substr( $authtime1, 6, 2 ) . "/" . substr( $authtime1, 0, 4 );
      print outfile "Auth Date: $authdate\n";
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

  if ( $username =~ /^(pnpsmart|ach2)/ ) {
    print "$username $orderid $batchid $twomonthsago $descr<br>\n";

    #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
    #print achfile "$remoteuser $todaytime select username from billingstatus where orderid='$orderid'\n";
    #close(achfile);
    $sth_sel = $dbh->prepare(
      qq{
          select username,card_type from billingstatus
          where orderid='$orderid' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_sel->execute or die "Can't execute: $DBI::errstr";
    ( $merchant, $chkcard_type ) = $sth_sel->fetchrow;
    $sth_sel->finish;
    print "cccc$merchant $orderid $chkcard_type<br>\n";

    if ( $chkcard_type eq "reseller" ) {
      $sth_sel2 = $dbh->prepare(
        qq{
            select reseller from customers
            where username='$merchant'
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_sel2->execute or die "Can't execute: $DBI::errstr";
      ($merchant) = $sth_sel2->fetchrow;
      $sth_sel2->finish;
    } else {

      #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
      #print achfile "$remoteuser $todaytime update pending set card_type='check' where username='$merchant'\n";
      #close(achfile);
      my $sth_pend = $dbh->prepare(
        qq{ 
            update pending
            set card_type='check'
            where username='$merchant'
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_pend->execute or die "Can't execute: $DBI::errstr";
      $sth_pend->finish;

      #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
      #print achfile "$remoteuser $todaytime update customers set accttype='check' where username='$merchant'\n";
      #close(achfile);
      my $sth_cust = $dbh->prepare(
        qq{
            update customers 
            set accttype='check' 
            where username='$merchant' 
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_cust->execute or die "Can't execute: $DBI::errstr";
      $sth_cust->finish;
    }

    # yyyy

    #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
    #print achfile "$remoteuser $todaytime select merchemail,reseller,company from customers where username='$merchant'\n";
    #close(achfile);
    my $sth_cust = $dbh->prepare(
      qq{
          select email,reseller,company
          from customers 
          where username='$merchant' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_cust->execute or die "Can't execute: $DBI::errstr";
    ( $email, $reseller, $company ) = $sth_cust->fetchrow;
    $sth_cust->finish;

    #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
    #print achfile "$remoteuser $todaytime select company,email from privatelabel where username='$reseller'\n";
    #close(achfile);
    $sth_pl = $dbh->prepare(
      qq{
            select company,email
            from privatelabel
            where username='$reseller'
            }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_pl->execute or die "Can't execute: $DBI::errstr";
    ( $plcompany, $plemail ) = $sth_pl->fetchrow;
    $sth_pl->finish;

    if ( $plcompany ne "" ) {
      $privatelabelflag    = 1;
      $privatelabelcompany = $plcompany;
      $privatelabelemail   = $plemail;
    } else {
      $privatelabelflag    = 0;
      $privatelabelcompany = "Plug & Pay Technologies, Inc.";
      $privatelabelemail   = "accounting\@plugnpay.com";
    }

    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: $email\n";
    print MAIL "Bcc: cprice\@plugnpay.com,barbara\@plugnpay.com,michelle\@plugnpay.com\n";
    print MAIL "From: $privatelabelemail\n";
    print MAIL "Subject: Monthly Billing - $privatelabelcompany - $username\n";
    print MAIL "\n";
    print MAIL "$company\n";
    print MAIL "$orderid\n\n";

    print MAIL "The attempt to bill your checking account for your monthly gateway fee has failed.\n";
    print MAIL "There is a returned check fee of \$20.00 in addition to your monthly gateway fee.\n";
    print MAIL "If payment is not received by the end of the month then your account will be closed.\n";
    print MAIL "Once your account is closed it cannot be reopened until we have received payment.\n\n";

    print MAIL "To remit payment by check:\n";
    print MAIL "Please include your username in the memo area of your check.\n";
    print MAIL "Send check payment to:\n";
    print MAIL "Plug \& Pay Technologies, Inc.\n";
    print MAIL "1019 Ft. Salonga Rd. ste 10\n";
    print MAIL "Northport, NY 11768\n\n";

    print MAIL "To pay  by credit card:\n";
    print MAIL "Complete the Billing Authorization form located in your administration area.\n";
    print MAIL "Click on the link labeled Billing Authorization.\n";
    print MAIL "Print, complete the credit card section, sign and fax to the number on the form.\n\n";

    print MAIL "Contact 800-945-2538 if you have any questions.\n";

    close(MAIL);

    my $sth_pend = $dbh->prepare(
      qq{ 
          update pending 
          set status=''  
          where transorderid='$orderid' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_pend->execute or die "Can't execute: $DBI::errstr";
    $sth_pend->finish;

    # xxxx 08/11/2004  and result='success' added
    my $sth_statusa = $dbh->prepare(
      qq{
          select username,orderid,amount,card_type,descr,paidamount,transorderid
          from billingstatus
          where orderid='$orderid'
          and result='success'
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_statusa->execute or die "Can't execute: $DBI::errstr";
    $sth_statusa->bind_columns( undef, \( $busername, $borderid, $bamount, $bcard_type, $bdescr, $chkpaidamount, $btransorderid ) );

    while ( $sth_statusa->fetch ) {
      if ( $chkpaidamount ne "" ) {
        $sth_status3 = $dbh->prepare(
          qq{
            insert into billingreport
            (username,orderid,trans_date,amount,card_type,descr,paidamount,transorderid)
            values (?,?,?,?,?,?,?,?)
            }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_status3->execute( "$busername", "$borderid", "$today", "-$bamount", "$bcard_type", "$bdescr problem", "-$chkpaidamount", "$btransorderid" )
          or die "Can't execute: $DBI::errstr";
        $sth_status3->finish;
      } else {
        $sth_status3 = $dbh->prepare(
          qq{
            insert into billingreport
            (username,orderid,trans_date,amount,card_type,descr,transorderid)
            values (?,?,?,?,?,?,?)
            }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_status3->execute( "$busername", "$borderid", "$today", "-$bamount", "$bcard_type", "$bdescr problem", "$btransorderid" )
          or die "Can't execute: $DBI::errstr";
        $sth_status3->finish;
      }
    }
    $sth_statusa->finish;

    #open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt");
    #print achfile "$remoteuser $todaytime update billingstatus set result='badcard' where orderid='$orderid'\n";
    #close(achfile);
    $sth_status = $dbh->prepare(
      qq{
          update billingstatus  
          set result='badcard' 
          where orderid='$orderid' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_status->execute or die "Can't execute: $DBI::errstr";
    $sth_status->finish;

    $errortype = "Return Fee: $descr";
    $fee       = "20.00";
    $type      = "check";

    $sthchk = $dbh->prepare(
      qq{
            select orderid
            from pending
            where username='$merchant'
            and orderid='$orderid'
            and descr like 'Return Fee%'
            }
      )
      or die "Can't prepare: $DBI::errstr";
    $sthchk->execute or die "Can't execute: $DBI::errstr";
    ($chkorderid) = $sthchk->fetchrow;
    $sthchk->finish;

    if ( $chkorderid eq "" ) {

#open(achfile,">>/home/p/pay1/batchfiles/$devprod/securenetach/achlog.txt"); print achfile "$remoteuser $todaytime insert into pending orderid=$orderid,username=$merchant,amount=$fee,descr=$errortype,trans_date=$today,card_type=$type\n";
#close(achfile);
      $sth_status = $dbh->prepare(
        qq{
              insert into pending 
              (orderid,username,amount,descr,trans_date,card_type)
              values (?,?,?,?,?,?) 
              }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_status->execute( "$orderid", "$merchant", "$fee", "$errortype", "$today", "$type" ) or die "Can't execute: $DBI::errstr";
      $sth_status->finish;
    }
  } else {

    $sth_tl = $dbh2->prepare(
      qq{
            select acct_code3
            from trans_log 
            where orderid='$orderid'
            and operation='auth' 
            }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_tl->execute or die "Can't execute: $DBI::errstr";
    ($acct_code3) = $sth_tl->fetchrow;
    $sth_tl->finish;

    if ( $acct_code3 eq "recurring" ) {
      $dbhmerch = &miscutils::dbhconnect("$username");

      $sth_pl = $dbhmerch->prepare(
        qq{
            select username,orderid
            from billingstatus 
            where orderid='$orderid' 
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_pl->execute or die "Can't execute: $DBI::errstr";
      ( $chkusername, $chkorderid ) = $sth_pl->fetchrow;
      $sth_pl->finish;

      if ( $chkorderid ne "" ) {
        $sth_status = $dbhmerch->prepare(
          qq{
            insert into billingstatus
            (username,trans_date,amount,orderid,descr)
            values (?,?,?,?,?) 
            }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_status->execute( "$chkusername", "$today", "-$amount", "$orderid", "$descr" ) or die "Can't execute: $DBI::errstr";
        $sth_status->finish;
      }
      $dbhmerch->disconnect;
    }
  }

  #yyyyyyyyyyyyyyyyyyyyyy

}

sub pidcheck {
  open( infile, "/home/p/pay1/batchfiles/$devprod/securenetach/pid.txt" );
  $chkline = <infile>;
  chop $chkline;
  close(infile);

  if ( $pidline ne $chkline ) {
    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/logs/securenetach/$fileyear/$username$time$pid.txt" );
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
    print MAILERR "Subject: securenetach - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

