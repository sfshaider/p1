#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;
use smpsutils;
use isotables;
use Time::Local;

$devprod = "logs";

$respcode = "";

$tmpfilestr = "";
&procutils::filewrite( "$username", "firstcarib", "", "flow.txt", "write", "", $tmpfilestr );

# plan etpay  version 2.0

if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'firstcarib/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: firstcarib - genfiles already running\n";
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
&procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/$devprod/firstcarib", "pid.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my $chkline = &procutils::fileread( "$username", "firstcarib", "/home/pay1/batchfiles/$devprod/firstcarib", "pid.txt" );
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
  $printstr .= "$pidline\n";
  $printstr .= "$chkline\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: firstcarib - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

#open(checkin,"/home/pay1/batchfiles/$devprod/firstcarib/genfiles.txt");
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
#$checkstring = "and t.username in ('aaaa','aaaa')";

# xxxx
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "      ";
$starttransdate   = $onemonthsago - 10000;

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

#print "two months ago: $twomonthsago\n";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $dummy, $today, $ttime ) = &miscutils::genorderid();

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/logs/firstcarib/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/firstcarib/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/logs/firstcarib/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/logs/firstcarib/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/firstcarib/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/logs/firstcarib/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/logs/firstcarib/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/firstcarib/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/logs/firstcarib/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/logs/firstcarib/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: firstcarib - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory firstcarib/logs/$fileyear.\n\n";
  close MAILERR;
  exit;
}

%errcode = (
  '000', 'Accepted',                                     '001', 'Accepted with identification',
  '003', 'Accepted (VIP)',                               '007', 'Accepted, ICC updating',
  '100', 'Do not honour',                                '101', 'Card expired',
  '102', 'Fraud detected',                               '104', 'Card has reserved use',
  '106', 'PIN tries number allowed exceeded',            '107', 'Refer to Card Issuer',
  '108', 'Refer to Card Issuer special conditions',      '109', 'Wrong business',
  '110', 'Wrong amount',                                 '111', 'Wrong card No. ',
  '112', 'Data linked to PIN required',                  '114', 'No account for type requested',
  '115', 'Function requested not undertaken',            '116', 'Insufficient funds',
  '117', 'PIN incorrect',                                '118', 'Card not recorded',
  '119', 'Transaction not authorised for Holder',        '120', 'Transaction not accepted by terminal',
  '121', 'Withdrawal limits exceeded',                   '122', 'Security violation',
  '123', 'Exceeding withdrawal authorised frequency',    '125', 'Card not in service',
  '126', 'Wrong PIN format',                             '127', 'Wrong PIN length',
  '128', 'Synchro error of PIN key',                     '129', 'Card counterfeit detected',
  '180', 'Shadow account not found',                     '181', 'Check account not found',
  '182', 'Saving account not found',                     '183', 'CVV invalid',
  '184', 'Date invalid',                                 '200', 'Do not honour, capture card',
  '201', 'Card expired, capture card',                   '202', 'Fraud detected, capture card',
  '204', 'Card has reserved use, capture',               '205', 'Card acceptor calls for acquirer security service, capture',
  '206', 'PIN validation tries number allowed exceeded', '207', 'Special Conditions, capture card',
  '208', 'Card lost, capture card',                      '209', 'Card stolen, capture card',
  '210', 'Card counterfeit detected, capture card',      '280', 'Alternative amount cancelled',
  '299', 'Capture card',                                 '300', 'Processing fulfilled',
  '301', 'Not supported by sender',                      '302', 'Unable to spot record in file',
  '303', 'Duplicate record, old record replaced',        '304', 'Zone control error',
  '305', 'File locked',                                  '306', 'Processing failed',
  '307', 'Format error',                                 '308', 'Duplicate processing, new record rejected',
  '309', 'File unknown',                                 '381', 'Record not found. Account not cut off. Withdrawal not processed',
  '382', 'Clearing balance record',                      '383', 'Updating balance',
  '385', 'Balance request',                              '480', 'Reversal correct',
  '481', 'Reversal amount incorrect',                    '482', 'Transaction already cancelled',
  '503', 'Totals not available',                         '500', 'Reconciliation succeeded',
  '581', 'Reconciliation already done',                  '582', 'Reconciliation procedure not available',
  '800', 'Cut-off in process',                           '880', 'Connection not accepted',
  '888', 'Send of cut-off',                              '902', 'Transaction invalid',
  '908', 'Transaction sender not referenced for switch', '909', 'System defect',
  '911', 'Issuer undue response',                        '912', 'Card issuer not available',
  '992', 'Issuer not found',                             '993', 'PINN verification not allowed',
  '994', 'Error in transaction processing',              '995', 'Error in server processing',
  '0',   'Accepted',                                     '1',   'Accepted with identification',
  '3',   'Accepted (VIP)',
);

$batch_flag = 1;
$file_flag  = 1;

# xxxx
#and t.username='paragont'
# homeclip should not be batched, it shares the same account as golinte1
my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        and t.trans_date<=?
        $checkstring
        and t.finalstatus in ('pending','locked')
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.processor='firstcarib'
        and o.lastoptime>=?
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user $usercount $usertdate\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );
  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

foreach $username ( sort @userarray ) {
  if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
    unlink "/home/pay1/batchfiles/$devprod/firstcarib/batchfile.txt";
    last;
  }

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/$devprod/firstcarib", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};

  my $printstr = "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  umask 0077;
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

  $logfilestr = "";
  $logfilestr .= "$username\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/logs/firstcarib/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  %errorderid    = ();
  $detailnum     = 0;
  $batchsalesamt = 0;
  $batchsalescnt = 0;
  $batchretamt   = 0;
  $batchretcnt   = 0;
  $batchcnt      = 1;

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,company,addr1,city,state,zip,tel,status,currency,country
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $company, $address, $city, $state, $zip, $tel, $status, $currency, $country ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
        select industrycode
        from firstcarib
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ($industrycode) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $opcode         = "handlePCBasedRequest";
  $opcoderesponse = "handlePCBasedRequestResponse";
  $cardcode       = "CardTransaction";
  if ( $industrycode ne "retail" ) {
    $opcode         = "handleEcomReconciliation";
    $opcoderesponse = "handleEcomReconciliationResponse";
    $cardcode       = "EODLoadTrx";
  }

  #if ($terminalnum eq "") {
  #  $terminalnum = "00000001";
  #}

  my $printstr = "$username $status\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

  if ( $status ne "live" ) {
    next;
  }

  if ( $currency eq "" ) {
    $currency = "usd";
  }

  my $printstr = "aaaa $starttransdate $onemonthsagotime $username\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

  $batch_flag = 0;
  $netamount  = 0;
  $hashtotal  = 0;
  $batchcnt   = 1;
  $recseqnum  = 0;
  @bigmessage = ();
  @bigarray   = ();
  @bigflow    = ();
  $flow       = ();

  %orderidarray    = ();
  %chkorderidarray = ();
  %inplanetarray   = ();
  %inoplogarray    = ();

  my $dbquerystr = <<"dbEOM";
        select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,
               auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,origamount,
               forceauthstatus
        from operation_log
        where trans_date>=?
        and lastoptime>=?
        and username=?
        and lastopstatus in ('pending','locked')
        and lastop IN ('auth','postauth','return','forceauth')
        and (voidstatus is NULL or voidstatus ='')
        and (accttype is NULL or accttype ='' or accttype='credit')
        order by orderid
dbEOM
  my @dbvalues = ( "$starttransdate", "$onemonthsagotime", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 16 ) {
    ( $orderid, $operation, $trans_date, $trans_time, $enccardnumber, $enclength, $exp, $amount, $auth_code, $avs_code, $refnumber, $finalstatus, $cvvresp, $transflags, $origamount, $forceauthstatus ) =
      @sthtransvalarray[ $vali .. $vali + 15 ];

    my $printstr = "$orderid\n";
    &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );
    if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
      unlink "/home/pay1/batchfiles/$devprod/firstcarib/batchfile.txt";
      last;
    }

    if ( ( $proc_type eq "authcapture" ) && ( $operation eq "postauth" ) ) {
      next;
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/logs/firstcarib/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
    my $printstr = "$orderid $operation $auth_code $refnumber\n";
    &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "firstcarib", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $errorflag = &errorchecking();
    if ( $errorflag == 1 ) {
      next;
    }

    if ( $batch_flag == 0 ) {
      &pidcheck();
      $batch_flag = 1;
      if ( $industrycode eq "retail" ) {
        %tracenumarray = ();
        &batchheader();
        if ( $respcode ne "800" ) {
          &miscutils::mysleep(600.0);
          &batchheader();
          if ( $respcode ne "800" ) {
            open( MAILERR, "| /usr/lib/sendmail -t" );
            print MAILERR "To: cprice\@plugnpay.com\n";
            print MAILERR "From: dcprice\@plugnpay.com\n";
            print MAILERR "Subject: firstcarib - genfiles failure\n";
            print MAILERR "\n";
            print MAILERR "username: $username\n";
            print MAILERR "1804 => $respcode, couldn't start batch, exiting\n";
            print MAILERR "file: $username$time$pid.txt\n";
            close MAILERR;
            exit;
          }
        }
      }
    }

    if (1) {
      my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='locked',result=?,detailnum=?
	    where orderid=?
	    and trans_date>=?
	    and finalstatus='pending'
	    and username=?
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$time$batchnum", "$detailnum", "$orderid", "$onemonthsago", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      $operationstatus = $operation . "status";
      $operationtime   = $operation . "time";
      my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending',detailnum=?
          where orderid=?
          and username=?
          and $operationstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$time$batchnum", "$detailnum", "$orderid", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    }

    &batchdetail();

  }

  if ( $batchcnt > 1 ) {
    %errorderid = ();
    $detailnum  = 0;

    if ( $industrycode eq "retail" ) {
      $response    = &sendbatchclose();
      %temparray   = &processresponse($response);
      $tmprespcode = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,TransActCd"};
      $tmpfilestr  = "";
      $tmpfilestr .= "       $respcode: $errmsg\n";
      $flow       .= "1520  $respcode: $errmsg\n";
      &procutils::filewrite( "$username", "firstcarib", "", "flow.txt", "append", "", $tmpfilestr );
    }

    if ( ( $respcode ne "500" ) || ( $industrycode ne "retail" ) ) {    # match
      $tmpfilestr = "";
      $tmpfilestr .= "$flowmessage\n";
      &procutils::filewrite( "$username", "firstcarib", "", "flow.txt", "append", "", $tmpfilestr );
      my $mycnt = 0;
      foreach $message (@bigmessage) {
        my $printstr = "xxxxxxxxxxxx            $mycnt  $#bigmessage\n";
        &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );
        if ( $mycnt == $#bigmessage ) {
          $message =~ s/FunctionCd>301<\/FunctionCd/FunctionCd>300<\/FunctionCd/;
        }
        ( $orderid, $origoperation, $operation ) = split( / /, $bigarray[$mycnt] );

        #$orderid = $bigarray[$mycnt];
        $orderid =~ s/ .*$//g;
        $response  = &sendmessage($message);
        %temparray = &processresponse($response);

        if ( $respcode eq "306" ) {
          &errormsg( $username, $orderid, $operation, "$respcode: $errmsg" );
        }

        $tmpfilestr = "";
        $tmpfilestr .= "$bigarray[$mycnt]       $respcode: $errmsg\n";
        &procutils::filewrite( "$username", "firstcarib", "", "flow.txt", "append", "", $tmpfilestr );
        $flow .= $bigflow[$mycnt] . " $respcode: $errmsg\n";
        $mycnt++;
      }

      $response   = &sendbatchclose();
      %temparray  = &processresponse($response);
      $tmpfilestr = "";
      $tmpfilestr .= "       $respcode: $errmsg\n";
      &procutils::filewrite( "$username", "firstcarib", "", "flow.txt", "append", "", $tmpfilestr );
      $flow .= "1520  $respcode: $errmsg\n";
    }

    #&sendbatchstatus();
    #if ($respcode eq "500") {
    &endbatch();

    #}

    $logfilestr = "";
    $logfilestr .= "\n\n$flow\n";
    &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/logs/firstcarib/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  }

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/$devprod/firstcarib", "genfiles.txt", "append", "", $checkinstr );
}

if ( !-e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  umask 0033;
  $checkinstr = "";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/$devprod/firstcarib", "genfiles.txt", "write", "", $checkinstr );
}

unlink "/home/pay1/batchfiles/$devprod/firstcarib/batchfile.txt";

exit;

sub processresponse {
  my ($response) = @_;

  $data = $response;
  $data =~ s/\r//g;
  $data =~ s/\n/ /g;
  $data =~ s/> *</>;;;</g;
  my @tmpfields = split( /;;;/, $data );
  my %temparray = ();
  my $levelstr  = "";
  foreach my $var (@tmpfields) {
    if ( $var =~ /<(.+)>(.*)</ ) {
      my $var2 = $1;
      my $val2 = $2;
      $var2 =~ s/ .*$//;
      $val2 =~ s/\&....;//g;
      if ( $temparray{"$levelstr$var2"} eq "" ) {
        $temparray{"$levelstr$var2"} = $val2;
      } else {
        $temparray{"$levelstr$var2"} = $temparray{"$levelstr$var2"} . "," . $val2;
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
    my $printstr = "aa $key    bb $temparray{$key}\n";
    &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );
  }

  $respcode  = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,TransActCd"};
  $appcode   = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,TransAprvCd"};
  $msgauthcd = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,MsgAuthCd"};
  $errmsg    = $errcode{"$respcode"};
  $err_msg   = "$respcode: $errmsg";

  #$batchnumber = $temparray{"s:Envelope,s:Body,BatchSettlementCloseResponse,BatchSettlementCloseResult,BatchSettlementCloseInfo,BatchNumber"};
  #$status = $temparray{"s:Envelope,s:Body,BatchSettlementCloseResponse,BatchSettlementCloseResult,BatchSettlementCloseInfo,Status"};
  #$respcode = $temparray{"s:Envelope,s:Body,BatchSettlementCloseResponse,BatchSettlementCloseResult,ResponseDetail,ResponseCode"};
  #$errmsg = $temparray{"s:Envelope,s:Body,BatchSettlementCloseResponse,BatchSettlementCloseResult,ResponseDetail,ResponseMessage"};
  #$refnum = $temparray{"s:Envelope,s:Body,BatchSettlementCloseResponse,BatchSettlementCloseResult,ResponseDetail,RetrievalReferenceNumber"};

  #$auth_code = $temparray{'EngineDocList,EngineDoc,OrderFormDoc,Transaction,AuthCode'};

  return %temparray;

}

sub endbatch {

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "orderid   $orderid\n";
  $logfilestr .= "respcode   $respcode\n";
  $logfilestr .= "err_msg   $err_msg\n";
  $logfilestr .= "result   $time$batchnum\n\n\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/logs/firstcarib/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  foreach $orderid ( sort keys %orderidarray ) {

    if ( $respcode eq "500" ) {

      #if ($operation eq "return") {
      #  $batchretamt = $batchretamt + $transamt;
      #  $batchretcnt = $batchretcnt + 1;
      #}
      #else {
      #  $batchsalesamt = $batchsalesamt + $transamt;
      #  $batchsalescnt = $batchsalescnt + 1;
      #}

      my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?,result=?
            where orderid=?
            and trans_date>=?
            and username=?
            and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$time", "$time$batchnum", "$orderid", "$onemonthsago", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='success',lastopstatus='success',lastoptime=?,batchfile=?
            where orderid=?
            and lastoptime>=?
            and username=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$time", "$time$batchnum", "$orderid", "$onemonthsagotime", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='success',lastopstatus='success',lastoptime=?,batchfile=?
            where orderid=?
            and lastoptime>=?
            and username=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$time", "$time$batchnum", "$orderid", "$onemonthsagotime", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
    } elsif ( $err_msg ne "" ) {
      $err_msg = substr( $err_msg, 0, 118 );

      my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?,result=?
            where orderid=?
            and trans_date>=?
            and username=?
            and (accttype is NULL or accttype ='' or accttype='credit')
            and finalstatus='locked'
dbEOM
      my @dbvalues = ( "$err_msg", "$time$batchnum", "$orderid", "$onemonthsago", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?,batchfile=?
            where orderid=?
            and username=?
            and lastoptime>=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$err_msg", "$time$batchnum", "$orderid", "$username", "$onemonthsagotime" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus='problem',lastopstatus='problem',descr=?,batchfile=?
            where orderid=?
            and username=?
            and lastoptime>=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$err_msg", "$time$batchnum", "$orderid", "$username", "$onemonthsagotime" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      #open(MAILERR,"| /usr/lib/sendmail -t");
      #print MAILERR "To: cprice\@plugnpay.com\n";
      #print MAILERR "From: dcprice\@plugnpay.com\n";
      #print MAILERR "Subject: firstcarib - FORMAT ERROR\n";
      #print MAILERR "\n";
      #print MAILERR "username: $username\n";
      #print MAILERR "result: format error\n\n";
      #print MAILERR "batchtransdate: $batchtransdate\n";
      #close MAILERR;
    } else {
      my $printstr = "respcode	$respcode unknown\n";
      &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );
      open( MAILERR, "| /usr/lib/sendmail -t" );
      print MAILERR "To: cprice\@plugnpay.com\n";
      print MAILERR "From: dcprice\@plugnpay.com\n";
      print MAILERR "Subject: firstcarib - unkown error\n";
      print MAILERR "\n";
      print MAILERR "username: $username\n";
      print MAILERR "result: $resp\n";
      print MAILERR "file: $username$time$pid.txt\n";
      close MAILERR;
    }
  }

}

sub batchheader {

  #local $sthinfo = $dbh->prepare(qq{
  #        select batchnum
  #        from firstcarib
  #        where username='$username'
  #        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  #$sthinfo->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
  #($batchnum) = $sthinfo->fetchrow;
  #$sthinfo->finish;

  #$batchnum = $batchnum + 1;
  #if ($batchnum >= 998) {
  #  $batchnum = 1;
  #}

  #local $sthinfo = $dbh->prepare(qq{
  #        update firstcarib set batchnum=?
  #        where username='$username'
  #        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  #$sthinfo->execute("$batchnum") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
  #$sthinfo->finish;

  @bh = ();

  $bh[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  $bh[1] =
    "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:ws=\"http://ws.gate.pay/\">\n";

  $bh[2] = "<soapenv:Body>\n";
  $bh[3] = "<ws:$opcode>\n";
  $bh[4] = "<$cardcode>\n";

  $bh[5] = "<MsgTypId>1804</MsgTypId>\n";

  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $lwday, $lyday, $lisdst ) = localtime( time() );
  $xmittime = "";
  if ( $industrycode eq "retail" ) {
    $lyear = substr( $lyear, -2, 2 );
    $xmittime = sprintf( "%02d%02d%02d%02d%02d", $lyear, $lmonth + 1, $lday, $lhour, $lmin );
  } else {
    $xmittime = sprintf( "%02d%02d%02d%02d%02d", $lmonth + 1, $lday, $lhour, $lmin, $lsec );
  }
  $bh[10] = "<XmitTs>$xmittime</XmitTs>\n";    # MMDDhhmmss

  $seqnum = &smpsutils::gettransid( "$username", "firstcarib", $orderid );
  $seqnum = substr( "0" x 6 . $seqnum, -6, 6 );
  $bh[11] = "<SysTraceAudNbr>$seqnum</SysTraceAudNbr>\n";

  my $lyr = substr( $lyear, -2, 2 );
  my $transts = sprintf( "%02d%02d%02d%02d%02d%02d", $lyr, $lmonth + 1, $lday, $lhour, $lmin, $lsec );
  $bh[12] = "<TransTs>$transts</TransTs>\n";    # YYMMDDHHMMSS

  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $lwday, $lyday, $lisdst ) = localtime( time() );

  $capdate = sprintf( "%02d%02d", $lmonth + 1, $lday );
  $bh[25] = "<CaptureDate>$capdate</CaptureDate>\n";    # Capture date MMDD
                                                        #$bh[15] = "<SettlementDate>$capdate</SettlementDate>\n";           	# Settlement date MMDD

  $bh[26] = "<FunctionCd>821</FunctionCd>\n";           # Function Code

  $bh[27] = "<MerTrmnlId>$terminal_id</MerTrmnlId>\n";  # Terminal ID

  my $mid = substr( $merchant_id . " " x 15, 0, 15 );
  $bh[28] = "<CardAcceptorId>$mid</CardAcceptorId>\n";    # xxxx
  $bh[29] = "<AcquirerId>000006</AcquirerId>\n";          # xxxx

  my $detail      = $company . $city . $state . $zip;
  my $countrycode = $isotables::countryUSUSA{$country};

  #$bs[29] = "<CardAcceptorDetail><![CDATA[$detail$countrycode]]></CardAcceptorDetail>\n";     # xxxx
  $bh[30] = "<CardAcceptorDetail>$detail$countrycode</CardAcceptorDetail>\n";    # xxxx

  #$bh[34] = "<Versions>\"\"</Versions>\n";
  $bh[34] = "<Versions>00000000000000000000000000000</Versions>\n";
  $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );

  #$msgauthcd = substr($auth_code,15,8);
  #$msgauthcd = s/ //g;
  #$bh[37] = "<MsgAuthCd>$msgauthcd</MsgAuthCd>\n";  # xxxx 8 bytes binary

  if ( $industrycode eq "retail" ) {
    $bh[36] = "<SecurityData>0001000000</SecurityData>\n";
  }

  $bh[37] = "</$cardcode>\n";
  $bh[38] = "</ws:$opcode>\n";

  $bh[39] = "<soapenv:/Body>\n";
  $bh[40] = "<soapenv:/Envelope>\n";

  $message   = &processmessage(@bh);
  $response  = &sendmessage($message);
  %temparray = &processresponse($response);

  #$errmsg = $temparray{"s:Envelope,s:Body,BatchSettlementCloseResponse,BatchSettlementCloseResult,ResponseDetail,ResponseCode"};
  $respcode = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,TransActCd"};

  #$errmsg = $respcode . ": " . $errcode{$respcode};
  $appcode   = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,TransAprvCd"};
  $msgauthcd = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,MsgAuthCd"};

  $tmpfilestr = "";
  $tmpfilestr .= "\n\n1804  $respcode: $errmsg\n";
  &procutils::filewrite( "$username", "firstcarib", "", "flow.txt", "append", "", $tmpfilestr );
  $flow .= "1804  $respcode: $errmsg\n";

}

sub batchdetail {

  $tempamount = $amount;

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

  @bd = ();

  $origoperation = "";
  if ( ( $operation eq "postauth" ) && ( $forceauthstatus eq "success" ) ) {
    $origoperation = "forceauth";
  }

  $eci = substr( $auth_code, 178, 1 );
  $eci =~ s/ //g;
  $posentry = substr( $auth_code, 179, 3 );
  $posentry =~ s/ //g;
  $poscond = substr( $auth_code, 182, 2 );
  $poscond =~ s/ //g;
  $postermcap = substr( $auth_code, 184, 1 );
  $postermcap =~ s/ //g;
  $cardholderid = substr( $auth_code, 185, 1 );
  $cardholderid =~ s/ //g;
  $magstripetrack = substr( $auth_code, 186, 1 );
  $magstripetrack =~ s/ //g;

  my $printstr = "bbbb $origoperation $operation $finalstatus\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

  $shortcard = substr( $cardnumber, 0, 4 );

  if ( ( $finalstatus eq "pending" ) && ( ( $operation eq "return" ) || ( $origoperation eq "forceauth" ) ) ) {
    $tmpfilestr = "";
    $tmpfilestr .= "$orderid $shortcard $origoperation $operation $finalstatus 1220\n";
    &procutils::filewrite( "$username", "firstcarib", "", "flow.txt", "append", "", $tmpfilestr );

    @bd = ();

    $bd[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    $bd[1] =
      "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:ws=\"http://ws.gate.pay/\">\n";

    $bd[2] = "<soapenv:Body>\n";
    $bd[3] = "<ws:$opcode>\n";
    $bd[4] = "<$cardcode>\n";

    $bd[5] = "<MsgTypId>1220</MsgTypId>\n";
    $bd[6] = "<CardNbr>$cardnumber</CardNbr>\n";
    if ( $operation eq "return" ) {
      $tcode = "200000";
    } else {
      $tcode = "000000";
    }
    $bd[7] = "<TransProcCd>$tcode</TransProcCd>\n";

    ( $currency, $transamt ) = split( / /, $amount );
    $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );

    #$transamt = substr("0" x 12 . $transamt,-12,12);
    my $curr = $currency;
    $curr =~ tr/a-z/A-Z/;
    $curr = $isotables::currencyUSD840{$curr};
    if ( $curr eq "" ) {
      $curr = "840";
    }
    $bd[8] = "<TransAmt>$transamt</TransAmt>\n";
    $bd[9] = "<SettlAmount>$transamt</SettlAmount>\n";

    my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $lwday, $lyday, $lisdst ) = localtime( time() );

    #$xmittime = sprintf("%02d%02d%02d%02d%02d",$lmonth+1,$lday,$lhour,$lmin,$lsec);
    $xmittime = "";
    if ( $industrycode eq "retail" ) {
      $lyear = substr( $lyear, -2, 2 );
      $xmittime = sprintf( "%02d%02d%02d%02d%02d", $lyear, $lmonth + 1, $lday, $lhour, $lmin );
    } else {
      $xmittime = sprintf( "%02d%02d%02d%02d%02d", $lmonth + 1, $lday, $lhour, $lmin, $lsec );
    }
    $bd[10] = "<XmitTs>$xmittime</XmitTs>\n";    # MMDDhhmmss

    $seqnum = &smpsutils::gettransid( "$username", "firstcarib", $orderid );
    $seqnum = substr( "0" x 6 . $seqnum, -6, 6 );
    $bd[11] = "<SysTraceAudNbr>$seqnum</SysTraceAudNbr>\n";
    $tracenumarray{"$orderid"} = $seqnum;

    my $lyr = substr( $lyear, -2, 2 );
    my $transts = sprintf( "%02d%02d%02d%02d%02d%02d", $lyr, $lmonth + 1, $lday, $lhour, $lmin, $lsec );
    $bd[12] = "<TransTs>$transts</TransTs>\n";    # YYMMDDHHMMSS

    $expdate = substr( $exp, 3, 2 ) . substr( $exp, 0, 2 );
    $bd[13] = "<CardExprDt>$expdate</CardExprDt>\n";    # YYMM

    $capdate = sprintf( "%02d%02d", $lmonth + 1, $lday );
    $bd[14] = "<CaptureDate>$capdate</CaptureDate>\n";          # Capture date MMDD
    $bd[15] = "<SettlementDate>$capdate</SettlementDate>\n";    # Settlement date MMDD

    $bd[16] = "<PointOfServiceData>\n";

    my $posentry = substr( $auth_code, 49, 12 );
    if ( ( $posentry ne "" ) && ( $posentry ne "            " ) && ( $posentry ne "000000000000" ) ) {
      $bd[17] = "<CardDataInpCpblCd>" . substr( $posentry, 0, 1 ) . "</CardDataInpCpblCd>\n";
      $bd[18] = "<CMAuthnCpblCd>" . substr( $posentry, 1, 1 ) . "</CMAuthnCpblCd>\n";
      $bd[19] = "<CardRetCpblCd>" . substr( $posentry, 2, 1 ) . "</CardRetCpblCd>\n";
      $bd[20] = "<OprEnvirCd>" . substr( $posentry, 3, 1 ) . "</OprEnvirCd>\n";
      $bd[21] = "<CMPresentCd>" . substr( $posentry, 4, 1 ) . "</CMPresentCd>\n";
      $bd[22] = "<CardPresentCd>" . substr( $posentry, 5, 1 ) . "</CardPresentCd>\n";
      $bd[23] = "<CardDataInpModeCd>" . substr( $posentry, 6, 1 ) . "</CardDataInpModeCd>\n";
      $bd[24] = "<CMAuthnMthdCd>" . substr( $posentry, 7, 1 ) . "</CMAuthnMthdCd>\n";
      $bd[25] = "<CMAuthnEnttyCd>" . substr( $posentry, 8, 1 ) . "</CMAuthnEnttyCd>\n";
      $bd[26] = "<CardDataOpCpblCd>" . substr( $posentry, 9, 1 ) . "</CardDataOpCpblCd>\n";
      $bd[27] = "<TrmnlOpCpblCd>" . substr( $posentry, 10, 1 ) . "</TrmnlOpCpblCd>\n";
      $bd[28] = "<PINCptrCpblCd>" . substr( $posentry, 11, 1 ) . "</PINCptrCpblCd>\n";
    } else {
      $bd[17] = "<CardDataInpCpblCd>1</CardDataInpCpblCd>\n";
      $bd[18] = "<CMAuthnCpblCd>0</CMAuthnCpblCd>\n";
      $bd[19] = "<CardRetCpblCd>0</CardRetCpblCd>\n";
      $bd[20] = "<OprEnvirCd>0</OprEnvirCd>\n";
      $bd[21] = "<CMPresentCd>5</CMPresentCd>\n";
      $bd[22] = "<CardPresentCd>0</CardPresentCd>\n";
      $bd[23] = "<CardDataInpModeCd>1</CardDataInpModeCd>\n";
      $bd[24] = "<CMAuthnMthdCd>0</CMAuthnMthdCd>\n";
      $bd[25] = "<CMAuthnEnttyCd>0</CMAuthnEnttyCd>\n";
      $bd[26] = "<CardDataOpCpblCd>1</CardDataOpCpblCd>\n";
      $bd[27] = "<TrmnlOpCpblCd>0</TrmnlOpCpblCd>\n";
      $bd[28] = "<PINCptrCpblCd>0</PINCptrCpblCd>\n";
    }

    $bd[29] = "</PointOfServiceData>\n";

    $bd[30] = "<FunctionCd>200</FunctionCd>\n";    # Function Code

    #$bd[31] = "<MerTrmnlId>$terminal_id</MerTrmnlId>\n";         	# Terminal ID
    if ( $industrycode eq "retail" ) {
      $bd[31] = "<MerTrmnlId>$terminal_id</MerTrmnlId>\n";    # Terminal ID
    } else {
      $bd[31] = "<CardAcceptorIdentification>\n";
      $bd[32] = "<MerId>$merchant_id</MerId>\n";              # Merchant ID   # xxxx
      $bd[33] = "</CardAcceptorIdentification>\n";
    }

    $bd[34] = "<TransCurrCd>$curr</TransCurrCd>\n";              # Currency Code
    $bd[35] = "<SettlementCurrCd>$curr</SettlementCurrCd>\n";    # Currency Code

    #$transactcd = substr($auth_code,12,3);
    #$bd[15] = "<TransActCd>$transactcd</TransActCd>\n";          	# Trans Act Code
    #my $mid = substr($firstcarib::merchant_id . " " x 15,0,15);
    #$bd[36] = "<CardAcceptorId>$mid</CardAcceptorId>\n"; # xxxx
    #my $detail = $firstcarib::company . $firstcarib::mcity . $firstcarib::mstate;
    #my $countrycode = $isotables::countryUSUSA{$firstcarib::mcountry};
    #$bd[37] = "<CardAcceptorDetail>$detail$countrycode</CardAcceptorDetail>\n";  # xxxx

    #$bd[37] = "<AddRspData></AddRspData>\n";  # xxxx

    #$bd[45] = "<SecurityData></SecurityData>\n";
    #$bd[34] = "<Versions>\"\"</Versions>\n";
    $bd[36] = "<Versions>00000000000000000000000000000</Versions>\n";
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );

    if ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
      $authcode = substr( $auth_code, 0, 6 );
      $bd[37] = "<TransAprvcd>$authcode</TransAprvcd>\n";
    }

    #$msgauthcd = substr($auth_code,15,8);
    #$msgauthcd = s/ //g;
    #$bd[37] = "<MsgAuthCd>$msgauthcd</MsgAuthCd>\n";  # xxxx 8 bytes binary

    if ( $industrycode eq "retail" ) {
      $bd[38] = "<SecurityData>0001000000</SecurityData>\n";
    }

    $bd[39] = "</$cardcode>\n";
    $bd[40] = "</ws:$opcode>\n";

    $bd[41] = "<soapenv:/Body>\n";
    $bd[42] = "<soapenv:/Envelope>\n";

    $message   = &processmessage(@bd);
    $response  = &sendmessage($message);
    %temparray = &processresponse($response);

    $errmsg    = $temparray{"s:Envelope,s:Body,BatchSettlementCloseResponse,BatchSettlementCloseResult,ResponseDetail,ResponseCode"};
    $respcode  = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,TransActCd"};
    $errmsg    = $respcode . ": " . $errcode{$respcode};
    $appcode   = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,TransAprvCd"};
    $msgauthcd = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,MsgAuthCd"};

    my $printstr = "1220 respcode: $respcode\n";
    &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );
    my $printstr = "1220 errmsg: $errmsg\n";
    &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

    $tmpfilestr = "";
    $tmpfilestr .= "        $respcode: $errmsg\n";
    &procutils::filewrite( "$username", "firstcarib", "", "flow.txt", "append", "", $tmpfilestr );

    $flow .= "$orderid $operation $finalstatus 1220  $respcode: $errmsg\n";

    if ( ( $operation ne "return" ) && ( $respcode ne "000" ) ) {
      &errormsg( $username, $orderid, $operation, "$respcode: $errmsg", "1220" );
    } elsif ( ( $operation ne "return" ) || ( $respcode eq "000" ) ) {

      # was else {}  3/20/2017
      &processsuccess( $username, $orderid, $operation, "$respcode: $errmsg", %temparray );
    }

  }

  if ( ( $finalstatus eq "pending" ) && ( ( $operation eq "return" ) || ( $origoperation eq "forceauth" ) ) ) {
    $transactcd = $respcode;
    $tracenum   = $seqnum;
    $authcode   = $appcode;
  } else {
    $transactcd = substr( $auth_code, 12, 3 );
    $tracenum   = substr( $auth_code, 6,  6 );    # trace audit number (6a)
    $authcode   = substr( $auth_code, 0,  6 );    # authorisation code (6a)
    $msgauthcd  = substr( $auth_code, 15, 8 );
  }

  my $printstr = "$transactcd  $tracenum  $authcode  $msgauthcd\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

  if ( ( ( $finalstatus eq "pending" ) && ( ( $operation eq "return" ) || ( $origoperation eq "forceauth" ) ) && ( $respcode eq "000" ) )
    || ( ( $operation eq "postauth" ) && ( $origoperation ne "forceauth" ) )
    || ( $finalstatus eq "locked" ) ) {

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

    $orderidarray{"$orderid"} = 1;

    @bd = ();

    $bd[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    $bd[1] =
      "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:ws=\"http://ws.gate.pay/\">\n";

    $bd[2] = "<soapenv:Body>\n";
    $bd[3] = "<ws:$opcode>\n";
    $bd[4] = "<$cardcode>\n";

    if ( $industrycode ne "retail" ) {
      $bd[15] = "<PointOfServiceData>\n";

      my $posentry = substr( $auth_code, 49, 12 );
      if ( ( $posentry ne "" ) && ( $posentry ne "            " ) && ( $posentry ne "000000000000" ) ) {
        $bd[16] = "<CardDataInpCpblCd>" . substr( $posentry, 0, 1 ) . "</CardDataInpCpblCd>\n";
        $bd[17] = "<CMAuthnCpblCd>" . substr( $posentry, 1, 1 ) . "</CMAuthnCpblCd>\n";
        $bd[18] = "<CardRetCpblCd>" . substr( $posentry, 2, 1 ) . "</CardRetCpblCd>\n";
        $bd[19] = "<OprEnvirCd>" . substr( $posentry, 3, 1 ) . "</OprEnvirCd>\n";
        $bd[20] = "<CMPresentCd>" . substr( $posentry, 4, 1 ) . "</CMPresentCd>\n";
        $bd[21] = "<CardPresentCd>" . substr( $posentry, 5, 1 ) . "</CardPresentCd>\n";
        $bd[22] = "<CardDataInpModeCd>" . substr( $posentry, 6, 1 ) . "</CardDataInpModeCd>\n";
        $bd[23] = "<CMAuthnMthdCd>" . substr( $posentry, 7, 1 ) . "</CMAuthnMthdCd>\n";
        $bd[24] = "<CMAuthnEnttyCd>" . substr( $posentry, 8, 1 ) . "</CMAuthnEnttyCd>\n";
        $bd[25] = "<CardDataOpCpblCd>" . substr( $posentry, 9, 1 ) . "</CardDataOpCpblCd>\n";
        $bd[26] = "<TrmnlOpCpblCd>" . substr( $posentry, 10, 1 ) . "</TrmnlOpCpblCd>\n";
        $bd[27] = "<PINCptrCpblCd>" . substr( $posentry, 11, 1 ) . "</PINCptrCpblCd>\n";
      } else {
        $bd[16] = "<CardDataInpCpblCd>1</CardDataInpCpblCd>\n";
        $bd[17] = "<CMAuthnCpblCd>0</CMAuthnCpblCd>\n";
        $bd[18] = "<CardRetCpblCd>0</CardRetCpblCd>\n";
        $bd[19] = "<OprEnvirCd>0</OprEnvirCd>\n";
        $bd[20] = "<CMPresentCd>5</CMPresentCd>\n";
        $bd[21] = "<CardPresentCd>0</CardPresentCd>\n";
        $bd[22] = "<CardDataInpModeCd>1</CardDataInpModeCd>\n";
        $bd[23] = "<CMAuthnMthdCd>0</CMAuthnMthdCd>\n";
        $bd[24] = "<CMAuthnEnttyCd>0</CMAuthnEnttyCd>\n";
        $bd[25] = "<CardDataOpCpblCd>1</CardDataOpCpblCd>\n";
        $bd[26] = "<TrmnlOpCpblCd>0</TrmnlOpCpblCd>\n";
        $bd[27] = "<PINCptrCpblCd>0</PINCptrCpblCd>\n";
      }

      $bd[28] = "</PointOfServiceData>\n";
    }

    $bd[29] = "<MsgTypId>1304</MsgTypId>\n";
    my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $lwday, $lyday, $lisdst ) = localtime( time() );

    #$xmittime = sprintf("%02d%02d%02d%02d%02d",$lmonth+1,$lday,$lhour,$lmin,$lsec);
    $xmittime = "";
    if ( $industrycode eq "retail" ) {
      $lyear = substr( $lyear, -2, 2 );
      $xmittime = sprintf( "%02d%02d%02d%02d%02d", $lyear, $lmonth + 1, $lday, $lhour, $lmin );
    } else {
      $xmittime = sprintf( "%02d%02d%02d%02d%02d", $lmonth + 1, $lday, $lhour, $lmin, $lsec );
    }
    $bd[30] = "<XmitTs>$xmittime</XmitTs>\n";    # MMDDhhmmss
    $capdate = sprintf( "%02d%02d", $lmonth + 1, $lday );
    $seqnum = &smpsutils::gettransid( "$username", "firstcarib", $orderid );
    $seqnum = substr( "0" x 6 . $seqnum, -6, 6 );
    $bd[31] = "<SysTraceAudNbr>$seqnum</SysTraceAudNbr>\n";

    my $lyr = substr( $lyear, -2, 2 );
    my $transts = sprintf( "%02d%02d%02d%02d%02d%02d", $lyr, $lmonth + 1, $lday, $lhour, $lmin, $lsec );
    $bd[32] = "<TransTs>$transts</TransTs>\n";    # YYMMDDHHMMSS

    $bd[33] = "<CaptureDate>$capdate</CaptureDate>\n";    # Capture date MMDD
    $bd[34] = "<FunctionCd>301</FunctionCd>\n";           # Function Code
                                                          #$transactcd = substr($auth_code,12,3);
    if ( ( $operation eq "return" ) && ( ( $transactcd eq "" ) || ( $transactcd eq "   " ) ) ) {
      $transactcd = "000";
    }
    $bd[35] = "<TransActCd>$transactcd</TransActCd>\n";    # Trans Act Code
    $bd[36] = "<TotalTrx>1</TotalTrx>\n";                  # Number of transactions in 1304 message

    #$bd[17] = "<MerTrmnlId>$terminal_id</MerTrmnlId>\n";         	# Terminal ID
    if ( $industrycode eq "retail" ) {
      $bd[37] = "<MerTrmnlId>$terminal_id</MerTrmnlId>\n";    # Terminal ID
    } else {
      $bd[37] = "<CardAcceptorIdentification>\n";
      $bd[38] = "<MerId>$merchant_id</MerId>\n";              # Merchant ID   # xxxx
      $bd[39] = "</CardAcceptorIdentification>\n";
    }

    #my $mid = substr($firstcarib::merchant_id . " " x 15,0,15);
    #$bd[36] = "<CardAcceptorId>$mid</CardAcceptorId>\n"; # xxxx
    #my $detail = $firstcarib::company . $firstcarib::mcity . $firstcarib::mstate;
    #my $countrycode = $isotables::countryUSUSA{$firstcarib::mcountry};
    #$bd[37] = "<CardAcceptorDetail>$detail$countrycode</CardAcceptorDetail>\n";  # xxxx

    #$bd[37] = "<AddRspData></AddRspData>\n";  # xxxx

    #$bd[45] = "<SecurityData></SecurityData>\n";
    if ( $industrycode eq "retail" ) {
      $bd[41] = "<SecurityData>0001000000</SecurityData>\n";

      #$bd[22] = "<Versions>\"\"</Versions>\n";
      $bd[42] = "<Versions>00000000000000000000000000000</Versions>\n";
    }
    $recseqnum = substr( "0" x 6 . $recseqnum, -6, 6 );
    $bd[43] = "<MsgNbr>$recseqnum</MsgNbr>\n";

    if ( $operation eq "return" ) {
      $msgtype = "1220";    # message type (4a)
    } elsif ( ( $origoperation eq "forceauth" ) && ( $operation eq "postauth" ) ) {
      $msgtype = "1220";
    } else {
      $msgtype = "1200";
    }

    if ( $operation eq "return" ) {
      $proccode = "200000";    # processing code (6a)
    } else {
      $proccode = "000000";
    }

    if ( $operation =~ /(forceauth|return)/ ) {
      $tracenum = $tracenumarray{"$orderid"};
    }
    $tracenum = substr( "0" x 6 . $tracenum, -6, 6 );

    # 10/30/2015
    if ( $tracenum eq "000000" ) {
      $tracenum = substr( $auth_code, 6, 6 );
    }

    ( $currency, $transamt ) = split( / /, $amount );
    $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );
    $transamt = substr( "0" x 12 . $transamt, -12, 12 );
    my $curr = $currency;
    $curr =~ tr/a-z/A-Z/;
    $curr = $isotables::currencyUSD840{$curr};
    if ( $curr eq "" ) {
      $curr = "840";
    }

    $tdate = substr( $trans_date, 6, 2 ) . substr( $trans_date, 4, 2 ) . substr( $trans_date, 2, 2 );    # transaction date DDMMYY (6n)

    #$authcode = substr($auth_code,0,6);		# authorisation code (6a)

    $exchrate = "0" x 25;                                                                                # exchange rate/date/origamt (25n)

    if ( $operation eq "return" ) {
      $offlineflag = "0";                                                                                # offline processing flag 2 = force, 1 = online, 0 = offline (1a)
    } elsif ( ( $origoperation eq "forceauth" ) && ( $operation eq "postauth" ) ) {
      $offlineflag = "2";
    } else {
      $offlineflag = "1";
    }

    $datarecord = $msgtype . $proccode . $tracenum . $cardnumber . "*" . $transamt . $curr . $transamt . $curr . $tdate . $authcode . $exchrate . $offlineflag . "\?";

    if ( $industrycode eq "retail" ) {
      $bd[44] = "<DataRecord>$datarecord</DataRecord>\n";
    }

    if ( $industrycode ne "retail" ) {
      $bd[44] = "<CardTransaction>\n";
      $bd[45] = "<MsgTypId>$msgtype</MsgTypId>\n";
      $bd[46] = "<CardNbr>$cardnumber</CardNbr>\n";
      $bd[47] = "<TransProcCd>$proccode</TransProcCd>\n";
      $bd[48] = "<TransAmt>$transamt</TransAmt>\n";
      $gmttime = substr( $auth_code, 39, 10 );
      $gmttime =~ s/ //g;
      if ( $gmttime eq "" ) {
        $gmttime = substr( $trans_time, 4, 10 );    # MMDDhhmmss
      }
      $bd[49] = "<XmitTs>$gmttime</XmitTs>\n";
      $bd[50] = "<SysTraceAudNbr>$tracenum</SysTraceAudNbr>\n";
      $expdate = substr( $exp, 3, 2 ) . substr( $exp, 0, 2 );
      $bd[51]  = "<CardExprDt>$expdate</CardExprDt>\n";
      $bd[52]  = "<TransAprvCd>$authcode</TransAprvCd>\n";
      $transactcode = substr( $auth_code, 12, 3 );
      $bd[53]       = "<TransActCd>$transactcode</TransActCd>\n";
      $bd[54]       = "<ServiceType>3</ServiceType>\n";
      $bd[55]       = "<TransCurrCd>$curr</TransCurrCd>\n";

      #$bd[64] = "<PointOfServiceData>\n";
      #$bd[65] = "<CardDataInpCpblCd>1</CardDataInpCpblCd>\n";
      #$bd[66] = "<CMAuthnCpblCd>0</CMAuthnCpblCd>\n";
      #$bd[67] = "<CardRetCpblCd>1</CardRetCpblCd>\n";
      #$bd[68] = "<OprEnvirCd>0</OprEnvirCd>\n";
      #$bd[71] = "<CMPresentCd>5</CMPresentCd>\n";
      #$bd[72] = "<CardPresentCd>0</CardPresentCd>\n";
      #$bd[73] = "<CardDataInpModeCd>1</CardDataInpModeCd>\n";
      #$bd[74] = "<CMAuthnMthdCd>0</CMAuthnMthdCd>\n";
      #$bd[75] = "<CMAuthnEnttyCd>0</CMAuthnEnttyCd>\n";
      #$bd[76] = "<CardDataOpCpblCd>1</CardDataOpCpblCd>\n";
      #$bd[77] = "<TrmnlOpCpblCd>0</TrmnlOpCpblCd>\n";
      #$bd[78] = "<PINCptrCpblCd>0</PINCptrCpblCd>\n";
      #$bd[79] = "</PointOfServiceData>\n";

      if ( $card_type eq "ax" ) {
        $bd[60] = "<AmexRetail>\n";
        $bd[61] = "<RetDepartName>MAIN</RetDepartName>\n";
        $bd[62] = "<RetailItems>\n";
        $bd[63] = "<TotalNbrItems>1</TotalNbrItems>\n";
        $bd[64] = "<RetailItem>\n";
        $bd[65] = "<RetItemNbr>1</RetItemNbr>\n";
        $bd[66] = "<RetItemDesc>Purchase</RetItemDesc>\n";
        $bd[67] = "<RetItemQnty>1</RetItemQnty>\n";
        $bd[68] = "<RetItemAmount>$transamt</RetItemAmount>\n";
        $bd[69] = "</RetailItem>\n";
        $bd[70] = "</RetailItems>\n";
        $bd[71] = "</AmexRetail>\n";
      }

      $bd[80] = "</CardTransaction>\n";

    }

    $lyear = substr( $lyear, -2, 2 );
    $actiondate = sprintf( "%02d%02d%02d", $lyear, $lmonth + 1, $lday );
    $bd[90] = "<ActionDate>$actiondate</ActionDate>\n";    # YYMMDD
    $bd[91] = "<FileName>TRANSACTION</FileName>\n";

    #$bd[37] = "<ICCCardData></ICCCardData>\n";  # xxxx

    #$msgauthcd = substr($auth_code,15,8);
    $msgauthcd =~ s/ //g;
    $bd[92] = "<MsgAuthCd>$msgauthcd</MsgAuthCd>\n";    # xxxx 8 bytes binary

    if ( $industrycode ne "retail" ) {
      $bd[93] = "<ServiceType>3</ServiceType>\n";       # 3 = retail
    }

    $bd[100] = "</$cardcode>\n";
    $bd[101] = "</ws:$opcode>\n";

    $bd[102] = "<soapenv:/Body>\n";
    $bd[103] = "<soapenv:/Envelope>\n";

    $message                      = &processmessage(@bd);
    $bigarray[ ++$#bigarray ]     = "$orderid $origoperation $operation $finalstatus 1304";
    $bigmessage[ ++$#bigmessage ] = $message;
    $flowmessage                  = $flowmessage . "$orderid $shortcard $origoperation $operation $finalstatus 1304\n";
    $bigflow[ ++$#bigflow ]       = "$orderid $operation $finalstatus 1304 ";
  }

}

sub sendmessage {
  my ($msg) = @_;

  #my $host = "216.109.156.66";
  #my $port = "8888";
  my $host = "209.18.96.146";
  my $port = "9998";

  #my $path = "/XmlAggService/RequestHandlerDelegate#handleRequest";
  my $path = "/XmlAggService/RequestHandlerService";
  if ( $username eq "testfirst" ) {
    $host = "10.10.21.66";
    $port = "9998";

    #$port = "8888";
  }

  my $messagestr = $msg;

  #my $xs = "x" x length($datainfo{'card-number'});
  $messagestr =~ s/\r{0,1}\n/;;;/g;
  if ( $messagestr =~ /CardNbr>([0-9]+?)<\/CardNbr/g ) {
    $cardnum = $1;
    $messagestr =~ s/$cardnum/xxxxxxxx/g;
  }
  $messagestr =~ s/[0-9]{15}\*/xxxxxxxxxxxxxxx\*/g;
  $messagestr =~ s/CardNbr>.*</CardNbr>xxxxxxxx</g;
  $messagestr =~ s/;;;/\n/g;

  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$username  $orderid\n";
  $logfilestr .= "$mytime send: $username $messagestr\n\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/$devprod/firstcarib", "serverlogmsg.txt", "append", "", $logfilestr );

  $mytime = gmtime( time() );
  my $chkmessage = $message;
  if ( ( length($cardnumber) >= 13 ) && ( length($cardnumber) <= 19 ) ) {
    $xs = "x" x length($cardnumber);
    $chkmessage =~ s/$cardnumber/$xs/g;
  }
  $chkmessage =~ s/CardNbr>.*</CardNbr>xxxxxxxx</g;
  $chkmessage =~ s/\>\<([^\/])/\>\n\<$1/g;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username  $orderid\n";
  $logfilestr .= "$mytime send: $chkmessage\n\n";
  my $printstr = "$mytime send:\n$chkmessage\n\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr .= "sequencenum: $sequencenum retries: $retries\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/logs/firstcarib/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  # old way retried connecting 4 times

  my $len        = length($msg);
  my %sslheaders = ();
  $sslheaders{'Host'}           = "$host:$port";
  $sslheaders{'Accept'}         = "*/*";
  $sslheaders{'User-Agent'}     = "PlugNPay";
  $sslheaders{'Referrer'}       = "https://pay1.plugnpay.com";
  $sslheaders{'Content-Type'}   = 'text/xml';
  $sslheaders{'Content-Length'} = $len;
  my ( $response, $header ) = &procutils::sendsslmsg( "firstcarib", $host, $port, $path, $msg, "nossl,noheaders,http10,got=<\/RESPONSE>,len<1", %sslheaders );

  $mytime = gmtime( time() );
  my $chkmessage = $response;
  if ( ( length($cardnumber) >= 13 ) && ( length($cardnumber) <= 19 ) ) {
    $xs = "x" x length($cardnumber);
    $chkmessage =~ s/$cardnumber/$xs/;
  }
  $chkmessage =~ s/\>\<([^\/])/\>\n\<$1/g;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username  $orderid\n";
  $logfilestr .= "$mytime recv: $chkmessage\n\n";

  #print "$mytime recv:\n$chkmessage\n\n";
  $logfilestr .= "sequencenum: $sequencenum retries: $retries\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/logs/firstcarib/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  return ($response);

}

sub sendbatchclose {

  $tmpfilestr = "";
  $tmpfilestr .= "1520\n";
  &procutils::filewrite( "$username", "firstcarib", "", "flow.txt", "append", "", $tmpfilestr );

  @bs = ();
  $bs[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  $bs[1] =
    "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:ws=\"http://ws.gate.pay/\">\n";

  $bs[2] = "<soapenv:Body>\n";
  $bs[3] = "<ws:$opcode>\n";
  $bs[4] = "<$cardcode>\n";

  if ( $industrycode ne "retail" ) {
    $bs[5] = "<PointOfServiceData>\n";

    #my $posentry = substr($auth_code,49,12);
    #if (($posentry ne "") && ($posentry ne "            ") && ($posentry ne "000000000000")) {
    #  $bs[6] = "<CardDataInpCpblCd>" . substr($posentry,0,1) . "</CardDataInpCpblCd>\n";
    #  $bs[7] = "<CMAuthnCpblCd>" . substr($posentry,1,1) . "</CMAuthnCpblCd>\n";
    #  $bs[8] = "<CardRetCpblCd>" . substr($posentry,2,1) . "</CardRetCpblCd>\n";
    #  $bs[9] = "<OprEnvirCd>" . substr($posentry,3,1) . "</OprEnvirCd>\n";
    #  $bs[10] = "<CMPresentCd>" . substr($posentry,4,1) . "</CMPresentCd>\n";
    #  $bs[11] = "<CardPresentCd>" . substr($posentry,5,1) . "</CardPresentCd>\n";
    #  $bs[12] = "<CardDataInpModeCd>" . substr($posentry,6,1) . "</CardDataInpModeCd>\n";
    #  $bs[13] = "<CMAuthnMthdCd>" . substr($posentry,7,1) . "</CMAuthnMthdCd>\n";
    #  $bs[14] = "<CMAuthnEnttyCd>" . substr($posentry,8,1) . "</CMAuthnEnttyCd>\n";
    #  $bs[15] = "<CardDataOpCpblCd>" . substr($posentry,9,1) . "</CardDataOpCpblCd>\n";
    #  $bs[16] = "<TrmnlOpCpblCd>" . substr($posentry,10,1) . "</TrmnlOpCpblCd>\n";
    #  $bs[17] = "<PINCptrCpblCd>" . substr($posentry,11,1) . "</PINCptrCpblCd>\n";
    #}
    #else {
    $bs[6]  = "<CardDataInpCpblCd>1</CardDataInpCpblCd>\n";
    $bs[7]  = "<CMAuthnCpblCd>0</CMAuthnCpblCd>\n";
    $bs[8]  = "<CardRetCpblCd>1</CardRetCpblCd>\n";
    $bs[9]  = "<OprEnvirCd>0</OprEnvirCd>\n";
    $bs[10] = "<CMPresentCd>5</CMPresentCd>\n";
    $bs[11] = "<CardPresentCd>0</CardPresentCd>\n";
    $bs[12] = "<CardDataInpModeCd>1</CardDataInpModeCd>\n";
    $bs[13] = "<CMAuthnMthdCd>0</CMAuthnMthdCd>\n";
    $bs[14] = "<CMAuthnEnttyCd>0</CMAuthnEnttyCd>\n";
    $bs[15] = "<CardDataOpCpblCd>1</CardDataOpCpblCd>\n";
    $bs[16] = "<TrmnlOpCpblCd>0</TrmnlOpCpblCd>\n";
    $bs[17] = "<PINCptrCpblCd>0</PINCptrCpblCd>\n";

    #}

    $bs[18] = "</PointOfServiceData>\n";

    $bs[19] = "<ServiceType>3</ServiceType>\n";
  }

  $bs[25] = "<MsgTypId>1520</MsgTypId>\n";

  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $lwday, $lyday, $lisdst ) = localtime( time() );

  if ( $industrycode eq "retail" ) {
    $lyear = substr( $lyear, -2, 2 );
    $xmittime = sprintf( "%02d%02d%02d%02d%02d", $lyear, $lmonth + 1, $lday, $lhour, $lmin );
    $bs[26] = "<XmitTs>$xmittime</XmitTs>\n";    # MMDDhhmmss
    $seqnum = &smpsutils::gettransid( "$username", "firstcarib", $orderid );
    $seqnum = substr( "0" x 6 . $seqnum, -6, 6 );
    $bs[27] = "<SysTraceAudNbr>$seqnum</SysTraceAudNbr>\n";

    my $lyr = substr( $lyear, -2, 2 );
    my $transts = sprintf( "%02d%02d%02d%02d%02d%02d", $lyr, $lmonth + 1, $lday, $lhour, $lmin, $lsec );
    $bs[28] = "<TransTs>$transts</TransTs>\n";    # YYMMDDHHMMSS

    $capdate = sprintf( "%02d%02d", $lmonth + 1, $lday );
    $bs[29] = "<CaptureDate>$capdate</CaptureDate>\n";          # Capture date MMDD
    $bs[30] = "<SettlementDate>$capdate</SettlementDate>\n";    # Settlement date MMDD
    $bs[31] = "<FunctionCd>500</FunctionCd>\n";                 # Function Code
  }

  #$transactcd = substr($auth_code,12,3);
  #$bs[9] = "<TransActCd>$transactcd</TransActCd>\n";          	# Trans Act Code
  if ( $industrycode eq "retail" ) {
    $bs[32] = "<MerTrmnlId>$terminal_id</MerTrmnlId>\n";    # Terminal ID
  } else {
    $bs[32] = "<CardAcceptorIdentification>\n";
    $bs[33] = "<MerId>$merchant_id</MerId>\n";              # Merchant ID   # xxxx
    $bs[34] = "</CardAcceptorIdentification>\n";
  }

  my $curr = $currency;
  $curr =~ tr/a-z/A-Z/;
  $curr = $isotables::currencyUSD840{$curr};
  if ( $curr eq "" ) {
    $curr = "840";
  }
  $bs[43] = "<TransCurrCd>$curr</TransCurrCd>\n";              # Currency Code
  $bs[44] = "<SettlementCurrCd>$curr</SettlementCurrCd>\n";    # Currency Code

  $batchsalescnt = substr( "0" x 10 . $batchsalescnt, -10, 10 );
  $batchretcnt   = substr( "0" x 10 . $batchretcnt,   -10, 10 );
  $batchsalesamt = substr( "0" x 16 . $batchsalesamt, -16, 16 );
  $batchretamt   = substr( "0" x 16 . $batchretamt,   -16, 16 );
  $hashtotal     = substr( "0" x 16 . $hashtotal,     -16, 16 );
  if ( $netamount < 0 ) {
    $netamount = 0 - $netamount;
    $netamount = substr( "0" x 16 . $netamount, -16, 16 );
    $addamount = substr( "0" x 12 . $netamount, -12, 12 );
    $netamount = "C" . $netamount;
  } else {
    $netamount = substr( "0" x 16 . $netamount, -16, 16 );
    $addamount = substr( "0" x 12 . $netamount, -12, 12 );
    $netamount = "D" . $netamount;
  }

  $bs[45] = "<RedempTrxNbr>00000000000000000000</RedempTrxNbr>\n";

  #$bs[15] = "<CrTrxNbr>$batchsalescnt</CrTrxNbr>\n";
  #$bs[16] = "<CrRevTrxNbr>$batchretcnt</CrRevTrxNbr>\n";
  $bs[46] = "<CrTrxNbr>$batchretcnt</CrTrxNbr>\n";
  $bs[47] = "<CrRevTrxNbr>0000000000</CrRevTrxNbr>\n";
  $bs[48] = "<DbTrxNbr>$batchsalescnt</DbTrxNbr>\n";     # purchase
  $bs[49] = "<DbRevTrxNbr>0000000000</DbRevTrxNbr>\n";

  $bs[50] = "<PayTrxNbr>0000000000</PayTrxNbr>\n";
  $bs[51] = "<PayRevTrxNbr>0000000000</PayRevTrxNbr>\n";

  #$bs[21] = "<CrAmount>$batchsalesamt</CrAmount>\n";
  #$bs[22] = "<CrRevAmount>$batchretamt</CrRevAmount>\n";
  $bs[52] = "<CrAmount>$batchretamt</CrAmount>\n";
  $bs[53] = "<CrRevAmount>0000000000000000</CrRevAmount>\n";

  $bs[54] = "<DbAmount>$batchsalesamt</DbAmount>\n";           # purchase
  $bs[55] = "<DbRevAmount>0000000000000000</DbRevAmount>\n";

  $bs[56] = "<NetReconAmount>$netamount</NetReconAmount>\n";

  my $curr = $currency;
  $curr =~ tr/a-z/A-Z/;
  $curr = $isotables::currencyUSD840{$curr};
  if ( $curr eq "" ) {
    $curr = "840";
  }

  #$bs[27] = "<AddAmount>0099$curr" . "D000000000000</AddAmount>\n";

  if ( $industrycode eq "retail" ) {
    $bs[58] = "<SecurityData>0001000000</SecurityData>\n";

    my $mid = substr( $merchant_id . " " x 15, 0, 15 );
    $bs[59] = "<CardAcceptorId>$mid</CardAcceptorId>\n";    # xxxx
    $bs[60] = "<AcquirerId>000006</AcquirerId>\n";          # xxxx

    my $detail      = $company . $city . $state . $zip;
    my $countrycode = $isotables::countryUSUSA{$country};

    #$bs[29] = "<CardAcceptorDetail><![CDATA[$detail$countrycode]]></CardAcceptorDetail>\n";     # xxxx
    $bs[61] = "<CardAcceptorDetail>$detail$countrycode</CardAcceptorDetail>\n";    # xxxx
    $bs[62] = "<Mcc>5921</Mcc>\n";                                                 # Merchant Category Code        # xxxx
                                                                                   #$bs[32] = "<Versions>\"\"</Versions>\n";
                                                                                   #$bs[32] = "<Versions>0000000000000000000000000000</Versions>\n";
    $bs[63] = "<Versions>00000000000000000000000000000</Versions>\n";
  }

  if ( $industrycode ne "retail" ) {
    $bs[64] = "<TotalTrx>1</TotalTrx>\n";                                          # Number of transactions in 1304 message
  }

  $bs[65] = "</$cardcode>\n";
  $bs[66] = "</ws:$opcode>\n";

  $bs[67] = "<soapenv:/Body>\n";
  $bs[68] = "<soapenv:/Envelope>\n";

  $message = &processmessage(@bs);
  my $printstr = "$message\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

  my $response = &sendmessage($message);
  my $printstr = "$response\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

  #%temparray = &processresponse($response);

  $tmpfilestr = "";
  $tmpfilestr .= "       	$oid	$refnum	batch close\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/$devprod/firstcarib", "scriptresults2.txt", "append", "", $tmpfilestr );

  return $response;
}

sub sendbatchstatus {
  @bs = ();

  $bs[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  $bs[1] =
    "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:i0=\"http://www.firstcaribment.net\">\n";

  $bs[2] = "<soap:Body>\n";

  $tcode = "BatchSettlementStatus";
  $bs[3] = "<i0:$tcode>\n";
  $bs[4] = "<i0:req>\n";

  $bs[5] = "<AccessInfo>\n";

  my $userid = $merchant_id;
  if ( $username !~ /skyhawket1|intelstrar1/ ) {
    $userid = substr( $userid, -12, 12 );
  }
  $bs[6] = "<User>$userid</User>\n";

  if ( $username eq "testplanet" ) {
    $bs[7] = "<Password>f0I!Rzh[A#1-</Password>\n";
  } else {
    $bs[7] = "<Password>45m7x\$9</Password>\n";
  }
  $bs[8] = "<ApplicationID>DirectLinkPlanet</ApplicationID>\n";
  $terminalnum = substr( "0" x 8 . $terminalnum, -8, 8 );
  $bs[9] = "<TerminalID>$terminalnum</TerminalID>\n";
  my $ipaddress = $ENV{'REMOTE_ADDR'};
  $ipaddress = "69.18.198.4";
  $bs[10]    = "<ClientIPAddress>$ipaddress</ClientIPAddress>\n";
  $bs[11]    = "</AccessInfo>\n";

  my ($oid) = &miscutils::genorderid();
  $oid = substr( $oid, -14, 14 );
  $bs[14] = "<i0:RequestIdentifier>$oid</i0:RequestIdentifier>\n";

  $bs[64] = "</i0:req>\n";
  $bs[65] = "</i0:$tcode>\n";

  $bs[66] = "</soap:Body>\n";
  $bs[67] = "</soap:Envelope>\n";

  $message = &processmessage(@bs);

  $response = &sendmessage($message);

  %temparray = &processresponse($response);

  $hostsalesamt    = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,HostSalesAmount"};
  $hostsalescnt    = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,HostSalesCount"};
  $hostrefundsamt  = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,HostRefundsAmount"};
  $hostrefundscnt  = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,HostRefundsCount"};
  $hostreversalamt = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,HostReversalAmount"};
  $hostreversalcnt = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,HostReversalCount"};
  $batchnumber     = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,BatchNumber"};
  $status          = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,BatchSettlementStatusInfo,Status"};
  $respcode        = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,ResponseDetail,ResponseCode"};
  $errmsg          = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,ResponseDetail,ResponseMessage"};
  $refnum          = $temparray{"s:Envelope,s:Body,BatchSettlementStatusResponse,BatchSettlementStatusResult,ResponseDetail,RetrievalReferenceNumber"};

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "sendinquiry:\n";
  $logfilestr .= "batchsalesamt: $batchsalesamt    $hostsalesamt\n";
  $logfilestr .= "batchsalescnt: $batchsalescnt    $hostsalescnt\n";
  $logfilestr .= "batchretamt: $batchretamt    $hostrefundsamt\n";
  $logfilestr .= "batchretcnt: $batchretcnt    $hostrefundscnt\n";

  $logfilestr .= "reversalamt: xxxx    $hostreversalamt\n";
  $logfilestr .= "reversalcnt: xxxx    $hostreversalcnt\n";

  $logfilestr .= "batchnum: $batchnum    $batchnumber\n";
  $logfilestr .= "respcode: $respcode\n";
  $logfilestr .= "errmsg: $errmsg\n";
  $logfilestr .= "status: $status\n";
  $logfilestr .= "refnum: $refnum\n";

  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/logs/firstcarib/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );
}

sub sendbatchstatusdetail {
  @bs = ();

  $bs[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  $bs[1] =
    "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:i0=\"http://www.firstcaribment.net\">\n";

  $bs[2] = "<soap:Body>\n";

  $tcode = "BatchSettlementStatusDetail";
  $bs[3] = "<i0:$tcode>\n";
  $bs[4] = "<i0:req>\n";

  $bs[5] = "<AccessInfo>\n";

  my $userid = $merchant_id;
  if ( $username !~ /skyhawket1|intelstrar1/ ) {
    $userid = substr( $userid, -12, 12 );
  }
  $bs[6] = "<User>$userid</User>\n";

  if ( $username eq "testplanet" ) {
    $bs[7] = "<Password>f0I!Rzh[A#1-</Password>\n";
  } else {
    $bs[7] = "<Password>45m7x\$9</Password>\n";
  }
  $bs[8] = "<ApplicationID>DirectLinkPlanet</ApplicationID>\n";
  $terminalnum = substr( "0" x 8 . $terminalnum, -8, 8 );
  $bs[9] = "<TerminalID>$terminalnum</TerminalID>\n";
  my $ipaddress = $ENV{'REMOTE_ADDR'};
  $ipaddress = "69.18.198.4";
  $bs[10]    = "<ClientIPAddress>$ipaddress</ClientIPAddress>\n";
  $bs[11]    = "</AccessInfo>\n";

  my ($oid) = &miscutils::genorderid();
  $oid = substr( $oid, -14, 14 );
  $bs[14] = "<i0:RequestIdentifier>$oid</i0:RequestIdentifier>\n";

  #if ($batchnum eq "") {
  #  $batchnum = "0";
  #}
  $bs[14] = "<i0:BatchNumber>0</i0:BatchNumber>\n";

  $bs[64] = "</i0:req>\n";
  $bs[65] = "</i0:$tcode>\n";

  $bs[66] = "</soap:Body>\n";
  $bs[67] = "</soap:Envelope>\n";

  $message = &processmessage(@bs);

  $response = &sendmessage($message);

  if ( $response eq "" ) {
    &mysleep(10);
    $response = &sendmessage($message);
  }

  %temparray = &processresponse($response);

  umask 0077;
  $logfilestr = "";

  $data = $response;
  $data =~ s/\n/;;;/g;
  $data =~ s/^.*<BatchSettlementStatusInfoDetail>//;
  $data =~ s/<\/BatchSettlementStatusInfoDetail>.*$//;
  $data =~ s/\&lt;/</g;
  $data =~ s/\&gt;/>/g;
  $data =~ s/\&\#xD;//g;
  $data =~ s/^.*?<Transaction/<Transaction/;
  $data =~ s/;;;<\/Batch>.*$//;
  $data =~ s/;;;<Batch.*?>//;
  my (@lines) = split( /;;;/, $data );

  foreach my $line (@lines) {
    ( $d1, $type, $d2, $amount, $d3, $currency, $d4, $refnum, $d5, $oid, $d6, $datestr ) = split( /"/, $line );

    my $printstr = "type: $type  amount: $amount  currency: $currency  refnum: $refnum  oid: $oid\n";
    &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

    $logfilestr .= "type: $type  amount: $amount  currency: $currency  refnum: $refnum  oid: $oid\n";

    $chkorderidarray{"$oid"} = 1;
    if ( $orderidarray{"$oid"} != 1 ) {
      $inplanetarray{"$oid"} = 1;
    }
  }

  $logfilestr .= "\n";

  foreach $oid ( sort keys %orderidarray ) {
    if ( $chkorderidarray{"$oid"} != 1 ) {
      $inoplogarray{"$oid"} = 1;
    }
  }

  $logfilestr .= "\n";
  $logfilestr .= "The following orderids are on planet's list, but not ours:\n";
  foreach $oid ( sort keys %inplanetarray ) {
    $logfilestr .= "$oid\n";
  }
  $logfilestr .= "\n";

  $logfilestr .= "The following orderids are on our list, but not planet's:\n";
  foreach $oid ( sort keys %inoplogarray ) {
    $logfilestr .= "$oid\n";
  }

  $logfilestr .= "\n";

  $tcoderesponse = $tcode . "Response";
  $tcoderesult   = $tcode . "Result";

  $hostsalesamt    = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,HostSalesAmount"};
  $hostsalescnt    = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,HostSalesCount"};
  $hostrefundsamt  = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,HostRefundsAmount"};
  $hostrefundscnt  = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,HostRefundsCount"};
  $hostreversalamt = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,HostReversalAmount"};
  $hostreversalcnt = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,HostReversalCount"};
  $batchnumber     = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,BatchNumber"};
  $status          = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,BatchSettlementStatusInfo,Status"};
  $respcode        = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseDetail,ResponseCode"};
  $errmsg          = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseDetail,ResponseMessage"};
  $refnum          = $temparray{"s:Envelope,s:Body,$tcoderesponse,$tcoderesult,ResponseDetail,RetrievalReferenceNumber"};

  $logfilestr .= "sendinquiry:\n";
  $logfilestr .= "batchsalesamt: $batchsalesamt    $hostsalesamt\n";
  $logfilestr .= "batchsalescnt: $batchsalescnt    $hostsalescnt\n";
  $logfilestr .= "batchretamt: $batchretamt    $hostrefundsamt\n";
  $logfilestr .= "batchretcnt: $batchretcnt    $hostrefundscnt\n";

  $logfilestr .= "reversalamt: xxxx    $hostreversalamt\n";
  $logfilestr .= "reversalcnt: xxxx    $hostreversalcnt\n";

  $logfilestr .= "batchnum: $batchnum    $batchnumber\n";
  $logfilestr .= "respcode: $respcode\n";
  $logfilestr .= "errmsg: $errmsg\n";
  $logfilestr .= "status: $status\n";
  $logfilestr .= "refnum: $refnum\n";

  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/logs/firstcarib/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

  if ( $response ne "" ) {
    return "success";
  } else {
    return "";
  }
}

sub processmessage {
  my (@msg) = @_;

  my $message = "";
  my $indent  = 0;
  foreach my $var (@msg) {
    if ( $var =~ /^<\/.*>/ ) {
      $indent--;
    }
    if ( $var eq "" ) {
      next;
    }

    #if ($var =~ /></) {
    #  next;
    #}
    #$message = $message . $var;
    $message = $message . " " x $indent . $var;
    if ( ( $var !~ /\// ) && ( $var != /<?/ ) ) {
      $indent++;
    }
    if ( $indent < 0 ) {
      $indent = 0;
    }
  }

  return $message;
}

sub printrecord {
  my ($printmessage) = @_;

  $temp = length($printmessage);
  my $printstr = "$temp\n";

  ($message2) = unpack "H*", $printmessage;

  $printstr .= "$message2\n\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

  $message1 = $printmessage;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;

  #print "$message1\n$message2\n\n";
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

sub processsuccess {
  my ( $username, $orderid, $operation, $errmsg, %temparray ) = @_;
  my $printstr = "in process success\n";
  &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

  $pass      = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,TransActCd"};
  $appcode   = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,TransAprvCd"};
  $msgauthcd = $temparray{"S:Envelope,S:Body,ns2:$opcoderesponse,$cardcode,MsgAuthCd"};

  $appcode   = substr( $appcode . " " x 6,  0, 6 );
  $tracenum  = substr( $tracenum . " " x 6, 0, 6 );
  $pass      = substr( $pass . "   ",       0, 3 );
  $msgauthcd = substr( $msgauthcd . "   ",  0, 8 );

  $appcode =~ s/\0/0/g;
  $pass =~ s/\0/0/g;
  $msgauthcd =~ s/\0/0/g;

  $auth_code = $appcode    # 0
    . $tracenum            # 6
    . $pass                # 12
    . $msgauthcd;          # 15

  my $dbquerystr = <<"dbEOM";
            update trans_log set auth_code=?
            where orderid=?
            and trans_date>=?
            and username=?
            and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$auth_code", "$orderid", "$onemonthsago", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";
  %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
  my $dbquerystr = <<"dbEOM";
            update operation_log set auth_code=?
            where orderid=?
            and username=?
            and lastoptime>=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$auth_code", "$orderid", "$username", "$onemonthsagotime" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

}

sub errormsg {
  my ( $username, $orderid, $operation, $errmsg, $errmsgtype ) = @_;

  if ( ( $operation eq "return" ) && ( $errmsgtype eq "1220" ) ) {
    return;
  }

  my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where orderid=?
            and trans_date>=?
            and username=?
            and finalstatus in ('locked','pending')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$errmsg", "$orderid", "$onemonthsago", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";
  %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
  my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and username=?
            and lastoptime>=?
            and $operationstatus in ('locked','pending')
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$errmsg", "$orderid", "$username", "$onemonthsagotime" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

}

sub pidcheck {
  my $chkline = &procutils::fileread( "$username", "firstcarib", "/home/pay1/batchfiles/$devprod/firstcarib", "pid.txt" );
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/logs/firstcarib/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $printstr .= "$pidline\n";
    $printstr .= "$chkline\n";
    &procutils::filewrite( "$username", "firstcarib", "/home/pay1/batchfiles/devlogs/firstcarib", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: firstcarib - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

