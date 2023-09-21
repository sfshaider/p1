#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;
use isotables;
use smpsutils;
use wirecard;

$devprod = "logs";

if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/wirecard/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'wirecard/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: wirecard - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

my $checkuser = &procutils::fileread( "$username", "wirecard", "/home/pay1/batchfiles/$devprod/wirecard", "genfiles.txt" );
chop $checkuser;

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>='$checkuser'";
}

#$checkstring = "and t.username='aaaa'";

$socketopenflag = 0;

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

if ( !-e "/home/pay1/batchfiles/$devprod/wirecard/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/wirecard/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/wirecard/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/wirecard/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/wirecard/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/wirecard/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/wirecard/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/wirecard/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/wirecard/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/wirecard/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: wirecard - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/wirecard/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;

# xxxx
#and t.username='paragont'
# and t.username<>'friendfind6'
# homeclip should not be batched, it shares the same account as golinte1
my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        and t.trans_date<=?
        $checkstring
and t.username NOT IN ('ventnordat','ventnordat1')
        and t.finalstatus in ('pending','locked')
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.processor='wirecard'
        and o.lastoptime>=?
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user $usercount $usertdate\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );

  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

foreach $username ( sort @userarray ) {
  if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/wirecard/stopgenfiles.txt" ) ) {
    unlink "/home/pay1/batchfiles/$devprod/wirecard/batchfile.txt";
    last;
  }

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/$devprod/wirecard", "genfiles.txt", "write", "", $checkinstr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/$devprod/wirecard", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};

  my $printstr = "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );

  if ( $usercountarray{$username} > 2000 ) {
    $batchcntuser = 500;    # wirecard recommends batches smaller than 500
  } elsif ( $usercountarray{$username} > 1000 ) {
    $batchcntuser = 500;
  } elsif ( $usercountarray{$username} > 600 ) {
    $batchcntuser = 200;
  } elsif ( $usercountarray{$username} > 300 ) {
    $batchcntuser = 100;
  } else {
    $batchcntuser = 50;
  }

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  %errorderid    = ();
  $detailnum     = 0;
  $batchsalesamt = 0;
  $batchsalescnt = 0;
  $batchretamt   = 0;
  $batchretcnt   = 0;
  $batchcnt      = 1;

  my $dbquerystr = <<"dbEOM";
        select c.merchant_id,c.pubsecret,c.proc_type,c.company,c.addr1,c.city,c.state,c.zip,c.tel,c.status,w.country,w.loginun,w.loginpw,w.returnflag
        from customers c, wirecard w
        where c.username=?
        and w.username=c.username
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $company, $address, $city, $state, $zip, $tel, $status, $country, $loginun, $loginpw, $returnflag ) =
    &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $status ne "live" ) {
    next;
  }

  umask 0077;
  $logfilestr = "";
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr .= "$username\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/$devprod/wirecard/$fileyear", "$username$time.txt", "write", "", $logfilestr );

  my $printstr = "aaaa $starttransdate $onemonthsagotime $username\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );

  $batch_flag = 0;
  $netamount  = 0;
  $hashtotal  = 0;
  $batchcnt   = 1;
  $recseqnum  = 0;

  my $dbquerystr = <<"dbEOM";
        select orderid
        from operation_log
        where trans_date>=?
        and lastoptime>=?
        and username=?
        and lastopstatus in ('pending','locked')
        and lastop IN ('auth','postauth','return')
        and (voidstatus is NULL or voidstatus ='')
        and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$starttransdate", "$onemonthsagotime", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  @orderidarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 1 ) {
    ($orderid) = @sthtransvalarray[ $vali .. $vali + 0 ];

    #@orderidarray = (@orderidarray,$orderid);
    $orderidarray[ ++$#orderidarray ] = $orderid;
  }

  foreach $orderid ( sort @orderidarray ) {
    if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/wirecard/stopgenfiles.txt" ) ) {
      unlink "/home/pay1/batchfiles/$devprod/wirecard/batchfile.txt";
      last;
    }

    # operation_log should only have one orderid per username
    if ( $orderid eq $chkorderidold ) {
      next;
    }
    $chkorderidold = $orderid;

    my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,
                 auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,origamount,
                 forceauthstatus,card_name,card_addr,card_city,card_state,card_zip,
                 card_country,postauthstatus,returntime,postauthtime,authtime,authstatus
          from operation_log
          where orderid=?
          and username=?
          and trans_date>=?
          and lastoptime>=?
          and lastopstatus in ('pending','locked')
          and lastop IN ('auth','postauth','return')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$starttransdate", "$onemonthsagotime" );
    ( $orderid,   $operation,  $trans_date,  $trans_time,   $enccardnumber,  $enclength,  $exp,             $amount,    $auth_code,
      $avs_code,  $refnumber,  $finalstatus, $cvvresp,      $transflags,     $origamount, $forceauthstatus, $card_name, $card_addr,
      $card_city, $card_state, $card_zip,    $card_country, $postauthstatus, $returntime, $postauthtime,    $authtime,  $authstatus
    )
      = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $orderid eq "" ) {
      next;
    }

    if ( ( $proc_type eq "authcapture" ) && ( $operation eq "postauth" ) ) {
      next;
    }

    if ( ( $transflags =~ /capture/ ) && ( $operation eq "postauth" ) ) {
      next;
    }

    if ( $forceauthstatus eq "success" ) {
      $origoperation = "forceauth";
    } elsif ( $operation eq "return" ) {
      $origoperation = "return";
    } else {
      $origoperation = "auth";
    }

    if ( $postauthstatus eq "success" ) {
      $chkreturntime = $postauthtime;
    } elsif ( $authstatus eq "success" ) {
      $chkreturntime = $authtime;
    }

    # only do returns on existing transactions if they are more than 1 day old
    my $time1 = &miscutils::strtotime($chkreturntime);
    my $time2 = time();
    if ( ( $operation eq "return" ) && ( $transflags !~ /payment/ ) && ( $origoperation ne "return" ) && ( $time2 < $time1 + ( 3600 * 24 ) ) ) {
      next;
    }

    # don't do original returns on locked transactions
    if ( ( $operation eq "return" ) && ( $transflags =~ /payment/ ) && ( $finalstatus eq "locked" ) ) {
      next;
    } elsif ( ( $operation eq "return" ) && ( $returnflag eq "yes" ) && ( $postauthstatus eq "" ) && ( $finalstatus eq "locked" ) ) {
      next;
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/$devprod/wirecard/$fileyear", "$username$time.txt", "append", "", $logfilestr );
    my $printstr = "$orderid $operation $auth_code $refnumber\n";
    &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "wirecard", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $card_type = &smpsutils::checkcard($cardnumber);

    $errorflag = &errorchecking();
    my $printstr = "cccc $errorflag\n";
    &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
    if ( $errorflag == 1 ) {
      next;
    }

    if ( $batchcnt == 1 ) {
      $batchnum = "";

      #&getbatchnum();
    }

    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='locked',result=?,detailnum=?
	    where orderid=?
	    and trans_date>=?
	    and finalstatus in ('pending','locked')
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
          and $operationstatus in ('pending','locked')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time$batchnum", "$detailnum", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $message = &batchdetail();

    $response = &sendmessage($message);

    &endbatch($response);

    if ( $batchcnt >= $batchcntuser ) {
      $errorrecseqnum = -1;
      %errorderid     = ();
      $detailnum      = 0;
      $batchsalesamt  = 0;
      $batchsalescnt  = 0;
      $batchretamt    = 0;
      $batchretcnt    = 0;
      $batchcnt       = 1;
    }

    # xxxxxxxxx
    #$myi++;
    #if ($myi >= 1) {
    #last;
    #}
  }

  if ( $batchcnt > 1 ) {
    %errorderid = ();
    $detailnum  = 0;
  }
}

if ( ( !-e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) && ( !-e "/home/pay1/batchfiles/$devprod/wirecard/stopgenfiles.txt" ) ) {
  umask 0033;
  $checkinstr = "";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/$devprod/wirecard", "genfiles.txt", "write", "", $checkinstr );
}

unlink "/home/pay1/batchfiles/$devprod/wirecard/batchfile.txt";

$socketopenflag = 0;

exit;

sub sendmessage {
  my ($msg) = @_;

  my $host = "c3.wirecard.com";
  my $port = "443";
  my $path = "/secure/ssl-gateway";
  if ( $username eq "testwire" ) {
    $host = "c3-test.wirecard.com";
    $port = "443";
    $path = "/secure/ssl-gateway";
  }

  my $messagestr = $msg;
  my $xs         = "x" x length($cardnumber);
  $messagestr =~ s/CreditCardNumber>[0-9]+<\/CreditCardNumber/CreditCardNumber>$xs<\/CreditCardNumber/;

  my $temptime = gmtime( time() );
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$temptime $orderid\n$temptime send: $messagestr\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/$devprod/wirecard/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  my $len        = length($msg);
  my %sslheaders = ();
  $sslheaders{'Host'}           = "$host:$port";
  $sslheaders{'User-Agent'}     = 'PlugNPay';
  $sslheaders{'Authorization'}  = "Basic " . &MIME::Base64::encode("$loginun\:$loginpw");
  $sslheaders{'Content-Type'}   = 'text/xml';
  $sslheaders{'Content-Length'} = $len;
  my ($response) = &procutils::sendsslmsg( "processor_wirecard", $host, $port, $path, $msg, "direct", %sslheaders );

  my $temptime = gmtime( time() );
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$temptime recv: $response\n\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/$devprod/wirecard/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  return $response;
}

sub endbatch {
  my ($response) = @_;

  my @tmpfields = split( /\n/, $response );
  my %temparray = ();
  foreach my $var (@tmpfields) {
    if ( $var =~ /<(.+)>(.*)</ ) {
      $temparray{$1} = $2;
    }
  }

  $errorflag = "";
  $respcode  = $temparray{'FunctionResult'};
  $timest    = $temparray{'TimeStamp'};
  $appmssg   = $temparray{'Type'} . " " . $temparray{'Number'} . " " . $temparray{'Message'};
  my $advice = $temparray{'Advice'};

  if ( $respcode eq "" ) {
    $errorflag = $temparray{'Type'};
    $appmssg   = $temparray{'Type'} . " " . $temparray{'Number'} . " " . $temparray{'Message'} . " " . $temparray{'Advice'};
    $appmssg   = substr( $appmssg, 0, 64 );
  }

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "orderid   $errorderid{$errorrecseqnum}\n";
  $logfilestr .= "respcode   $respcode  $operation\n";
  $logfilestr .= "appmssg   $appmssg\n";
  $logfilestr .= "timestamp   $timestamp\n";
  $logfilestr .= "result   $time$batchnum\n\n\n";

  my $printstr = "orderid   $orderid\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "respcode   $respcode\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "appmssg   $appmssg\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "timestamp   $timestamp\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "result   $time$batchnum\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard",            "miscdebug.txt",      "append", "misc", $printstr );
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/$devprod/wirecard/$fileyear", "$username$time.txt", "append", "",     $logfilestr );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  if ( ( $respcode =~ /^(ACK|PENDING)$/ )
    || ( ( $operation eq "postauth" ) && ( $finalstatus eq "locked" ) && ( $respcode eq "NOK" ) && ( $appmssg =~ /Invalid transaction flow/ ) )
    || ( ( $operation eq "postauth" ) && ( $finalstatus eq "locked" ) && ( $respcode eq "NOK" ) && ( $advice =~ /The sum of amounts of all/ ) ) ) {

    if ( ( $operation eq "postauth" ) && ( $advice !~ /The sum of amounts of all/ ) ) {
      $newauthcode  = $temparray{'AuthorizationCode'};
      $newauthcode  = substr( $newauthcode . " " x 8, 0, 8 );
      $newauthcode  = $newauthcode . substr( $auth_code, 8 );
      $newrefnumber = $temparray{'GuWID'};
    } else {
      $newauthcode  = $auth_code;
      $newrefnumber = $refnumber;
    }
    if ( $newauthcode eq "" ) {
      $newauthcode = $temparray{'AuthorizationCode'};
      $newauthcode = substr( $newauthcode . " " x 8, 0, 8 );
      $newauthcode = $newauthcode . substr( $auth_code, 8 );
    }
    if ( $newrefnumber eq "" ) {
      $newrefnumber = $temparray{'GuWID'};
    }

    if ( ( $operation ne "auth" ) || ( ( $operation eq "auth" ) && ( $respcode eq "ACK" ) ) ) {

      my $printstr = "$respcode  $orderid  $onemonthsago  $time$batchnum  $username\n";
      &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
      my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?,auth_code=?,refnumber=?
            where orderid=?
            and trans_date>=?
            and result=?
            and username=?
            and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$time", "$newauthcode", "$newrefnumber", "$orderid", "$onemonthsago", "$time$batchnum", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='success',lastopstatus='success',$operationtime=?,lastoptime=?,auth_code=?,refnumber=?
            where orderid=?
            and lastoptime>=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$time", "$time", "$newauthcode", "$newrefnumber", "$orderid", "$onemonthsagotime", "$username", "$time$batchnum" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
    }

  } elsif ( ( ( $operation eq "auth" ) && ( $respcode eq "NOK" ) && ( $appmssg =~ /DATA_ERROR 546 Could/ ) )
    || ( ( $operation eq "auth" ) && ( $respcode eq "NOK" ) && ( $appmssg =~ /DATA_ERROR 547 Value of/ ) )
    || ( ( $operation eq "auth" ) && ( $respcode eq "NOK" ) && ( $appmssg =~ /temporarily not available/ ) ) ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='pending',descr=?
            where orderid=?
            and trans_date>=?
            and username=?
            and (accttype is NULL or accttype ='' or accttype='credit')
            and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$respcode: $appmssg", "$orderid", "$onemonthsago", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='pending',lastopstatus='pending',descr=?
            where orderid=?
            and lastoptime>=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$respcode: $appmssg", "$orderid", "$onemonthsagotime" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: wirecard - AUTH ERROR\n";
    print MAILERR "\n";
    print MAILERR "Set to pending:\n";
    print MAILERR "username: $username\n";
    print MAILERR "orderid: $orderid\n";
    print MAILERR "operation: $operation\n";
    print MAILERR "result: $respcode: $appmssg\n\n";
    print MAILERR "batchtransdate: $batchtransdate\n";
    close MAILERR;

  } elsif ( $respcode eq "NOK" ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where orderid=?
            and trans_date>=?
            and username=?
            and (accttype is NULL or accttype ='' or accttype='credit')
            and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$respcode: $appmssg", "$orderid", "$onemonthsago", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and lastoptime>=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$respcode: $appmssg", "$orderid", "$onemonthsagotime" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $operation eq "auth" ) {
      open( MAILERR, "| /usr/lib/sendmail -t" );
      print MAILERR "To: cprice\@plugnpay.com\n";
      print MAILERR "From: dcprice\@plugnpay.com\n";
      print MAILERR "Subject: wirecard - AUTH ERROR\n";
      print MAILERR "\n";
      print MAILERR "username: $username\n";
      print MAILERR "orderid: $orderid\n";
      print MAILERR "operation: $operation\n";
      print MAILERR "result: $respcode: $appmssg\n\n";
      print MAILERR "batchtransdate: $batchtransdate\n";
      close MAILERR;
    }

  } elsif ( $errorflag eq "DATA_ERROR" ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='pending',descr=?
            where orderid=?
            and trans_date>=?
            and username=?
            and (accttype is NULL or accttype ='' or accttype='credit')
            and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$respcode: $appmssg", "$orderid", "$onemonthsago", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='pending',lastopstatus='pending',descr=?
            where orderid=?
            and lastoptime>=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$respcode: $appmssg", "$orderid", "$onemonthsagotime" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: wirecard - DATA ERROR\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: data error\n\n";
    print MAILERR "batchtransdate: $batchtransdate\n";
    close MAILERR;
  } elsif ( $respcode eq "PENDING" ) {
  } else {
    my $printstr = "respcode	$respcode unknown\n";
    &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: wirecard - unkown error\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $resp\n";
    print MAILERR "orderid: $orderid\n";
    print MAILERR "file: $username$time.txt\n";
    close MAILERR;

    if ( $origreturnflag == 1 ) {
      open( MAILWIRE, "| /usr/lib/sendmail -t" );
      print MAILWIRE "To: support\@wirecard.com\n";
      print MAILWIRE "From: cprice\@plugnpay.com\n";
      print MAILWIRE "Bcc: cprice\@plugnpay.com\n";
      print MAILWIRE "Subject: Plug & Pay - Wirecard - transaction status\n";
      print MAILWIRE "\n";
      print MAILWIRE "We did not receive status on a transaction. Can you tell me if this transaction was successful?\n";
      print MAILWIRE "\n";
      print MAILWIRE "Here are the transaction details:\n";
      print MAILWIRE "\n";
      print MAILWIRE "Username: $username (for our internal use)\n";
      print MAILWIRE "OrderID: $orderid (for our internal use)\n";
      print MAILWIRE "Date GMT: $datestr\n";
      print MAILWIRE "BusinessCaseSignature: $merchant_id\n";
      print MAILWIRE "TransactionID: $transid\n";
      print MAILWIRE "Currency: $currency\n";
      print MAILWIRE "Amount: $amt\n";
      print MAILWIRE "\n";
      print MAILWIRE "\n";
      print MAILWIRE "Thankyou,\n";
      print MAILWIRE "Carol Price\n";
      print MAILWIRE "Plug & Pay Technologies, Inc.\n";
      print MAILWIRE "cprice\@plugnpay.com\n";
      close MAILWIRE;

      &miscutils::mysleep(60);
    }

  }

}

sub getbatchnum {
  my $dbquerystr = <<"dbEOM";
          select batchnum
          from wirecard
          where username=?
dbEOM
  my @dbvalues = ("$username");
  ($batchnum) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = $batchnum + 1;
  if ( $batchnum >= 998 ) {
    $batchnum = 1;
  }

  my $dbquerystr = <<"dbEOM";
          update wirecard set batchnum=?
          where username=?
dbEOM
  my @dbvalues = ( "$batchnum", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = substr( "0000" . $batchnum, -4, 4 );

}

sub batchdetail {

  $currency = substr( $amount, 0, 3 );
  $currency =~ tr/a-z/A-Z/;
  my $exponent = $isotables::currencyUSD2{$currency};
  $transamt = substr( $amount, 4 );
  $transamt = $transamt * ( 10**$exponent );
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

  $datestr = gmtime( time() );

  @bd    = ();
  $bd[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>";                              # stx
  $bd[1] = "<WIRECARD_BXML xmlns:xsi=\"http://www.w3.org/1999/XMLSchema-instance\"";
  $bd[2] = "xsi:noNamespaceSchemaLocation=\"wirecard.xsd\">";
  $bd[3] = "<W_REQUEST>";
  $bd[4] = "<W_JOB>";

  #$jobid = substr($auth_code,8,24);
  #$jobid =~ s/ +$//g;
  #if ($jobid eq "") {
  $jobid = "Job 1";

  #}

  $bd[5] = "<JobID>$jobid</JobID>";
  $bd[6] = "<BusinessCaseSignature>$merchant_id</BusinessCaseSignature>";    # business case signature (12a)

  $origreturnflag = 0;
  if ( ( $operation eq "return" ) && ( $transflags =~ /payment/ ) && ( $postauthstatus eq "" ) ) {
    $origreturnflag = 1;

    $bd[7] = "<FNC_CC_OCT>";
    $tid = substr( $terminal_id . " " x 10, 0, 10 );
    $bd[8] = "<FunctionID>Return 1</FunctionID>";                            # function id (32a)
    $bd[9] = "<CC_TRANSACTION>";
    $transid = substr( $orderid, 0, 26 );
    $bd[10]  = "<TransactionID>Trans $transid</TransactionID>";
    $bd[11]  = "<CountryCode>$country</CountryCode>";

    my $extramarketdata = substr( $auth_code, 39, 20 );
    $extramarketdata =~ s/ //g;
    $bd[12] = "<Usage>$extramarketdata</Usage>";

    $currency = substr( $amount, 0, 3 );
    $currency =~ tr/a-z/A-Z/;
    if ( $currency eq "" ) {
      $currency = "USD";
    }
    my $exponent = $isotables::currencyUSD2{$currency};
    $amt = sprintf( "%d", ( substr( $amount, 4 ) * ( 10**$exponent ) ) + .0001 );
    $bd[13] = "<Amount>$amt</Amount>";
    $bd[14] = "<Currency>$currency</Currency>";
    $bd[15] = "<CREDIT_CARD_DATA>";
    my $cardnum = substr( $cardnumber, 0, 19 );
    $bd[16] = "<CreditCardNumber>$cardnum</CreditCardNumber>";
    my $authcode = substr( $auth_code, 0, 6 );

    my $yrexp = "20" . substr( $exp, 3, 2 );
    my $monthexp = substr( $exp, 0, 2 );
    $bd[17] = "<ExpirationYear>$yrexp</ExpirationYear>";
    $bd[18] = "<ExpirationMonth>$monthexp</ExpirationMonth>";

    my $cardname = $card_name;

    #$cardname =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
    $cardname =~ s/[^(?:\P{L}\p{L}*)+0-9\.\']/ /g;
    $bd[19] = "<CardHolderName>$cardname</CardHolderName>";

    my $cardstartdate = substr( $auth_code, 32, 5 );
    $cardstartdate =~ s/ //g;
    my $cardissuenum = substr( $auth_code, 37, 2 );
    $cardissuenum =~ s/ //g;
    if ( $cardstartdate ne "" ) {

      # cardstartdate format MM/YY
      my $cardstartmonth = substr( $cardstartdate, 0, 2 );
      my $cardstartyear = "20" . substr( $cardstartdate, 3, 2 );
      $bd[20] = "<CardStartYear>$cardstartyear</CardStartYear>";
      $bd[21] = "<CardStartMonth>$cardstartmonth</CardStartMonth>";

      if ( $cardissuenum ne "" ) {
        $bd[22] = "<CardIssueNumber>$cardissuenum</CardIssueNumber>";
      }
    }

    $bd[23] = "</CREDIT_CARD_DATA>";

    #$bd[24] = "<RECURRING_TRANSACTION>";
    #$bd[25] = "<Type>Single</Type>";
    #$bd[26] = "</RECURRING_TRANSACTION>";

    $bd[39] = "</CC_TRANSACTION>";
    $bd[40] = "</FNC_CC_OCT>";
  } elsif ( ( $operation eq "return" ) && ( $returnflag eq "yes" ) && ( $postauthstatus eq "" ) ) {
    $origreturnflag = 1;

    $bd[7] = "<FNC_CC_REFUND>";
    $tid = substr( $terminal_id . " " x 10, 0, 10 );
    $bd[8] = "<FunctionID>Return 1</FunctionID>";    # function id (32a)
    $bd[9] = "<CC_TRANSACTION>";
    $transid = substr( $orderid, 0, 26 );
    $bd[10]  = "<TransactionID>Trans $transid</TransactionID>";
    $bd[11]  = "<CountryCode>$country</CountryCode>";

    my $extramarketdata = substr( $auth_code, 39, 20 );
    $extramarketdata =~ s/ //g;
    $bd[12] = "<Usage>$extramarketdata</Usage>";

    $currency = substr( $amount, 0, 3 );
    $currency =~ tr/a-z/A-Z/;
    if ( $currency eq "" ) {
      $currency = "USD";
    }
    my $exponent = $isotables::currencyUSD2{$currency};
    $amt = sprintf( "%d", ( substr( $amount, 4 ) * ( 10**$exponent ) ) + .0001 );
    $bd[13] = "<Amount>$amt</Amount>";
    $bd[14] = "<Currency>$currency</Currency>";
    $bd[15] = "<CREDIT_CARD_DATA>";
    my $cardnum = substr( $cardnumber, 0, 19 );
    $bd[16] = "<CreditCardNumber>$cardnum</CreditCardNumber>";
    my $authcode = substr( $auth_code, 0, 6 );

    my $yrexp = "20" . substr( $exp, 3, 2 );
    my $monthexp = substr( $exp, 0, 2 );
    $bd[17] = "<ExpirationYear>$yrexp</ExpirationYear>";
    $bd[18] = "<ExpirationMonth>$monthexp</ExpirationMonth>";

    my $cardname = $card_name;

    #$cardname =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
    $cardname =~ s/[^(?:\P{L}\p{L}*)+0-9\.\']/ /g;
    $bd[19] = "<CardHolderName>$cardname</CardHolderName>";

    my $cardstartdate = substr( $auth_code, 32, 5 );
    $cardstartdate =~ s/ //g;
    my $cardissuenum = substr( $auth_code, 37, 2 );
    $cardissuenum =~ s/ //g;
    if ( $cardstartdate ne "" ) {

      # cardstartdate format MM/YY
      my $cardstartmonth = substr( $cardstartdate, 0, 2 );
      my $cardstartyear = "20" . substr( $cardstartdate, 3, 2 );
      $bd[20] = "<CardStartYear>$cardstartyear</CardStartYear>";
      $bd[21] = "<CardStartMonth>$cardstartmonth</CardStartMonth>";

      if ( $cardissuenum ne "" ) {
        $bd[22] = "<CardIssueNumber>$cardissuenum</CardIssueNumber>";
      }
    }

    $bd[23] = "</CREDIT_CARD_DATA>";

    $bd[24] = "<RECURRING_TRANSACTION>";
    $bd[25] = "<Type>Single</Type>";
    $bd[26] = "</RECURRING_TRANSACTION>";

    #$bd[47] = "<CONTACT_DATA>";
    #$bd[48] = "<IPAddress>$ipaddress</IPAddress>";
    #$bd[49] = "</CONTACT_DATA>";
    $bd[39] = "</CC_TRANSACTION>";
    $bd[40] = "</FNC_CC_REFUND>";
  } elsif ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
    $bd[7] = "<FNC_CC_CAPTURE_AUTHORIZATION type=\"non-referenced\">";
    $tid = substr( $terminal_id . " " x 10, 0, 10 );
    $bd[8] = "<FunctionID>Force 1</FunctionID>";    # function id (32a)
    $bd[9] = "<CC_TRANSACTION>";
    $transid = substr( $orderid, 0, 26 );
    $bd[10]  = "<TransactionID>Trans $transid</TransactionID>";
    $bd[11]  = "<CountryCode>$country</CountryCode>";

    my $extramarketdata = substr( $auth_code, 39, 20 );
    $extramarketdata =~ s/ //g;
    $bd[12] = "<Usage>$extramarketdata</Usage>";

    $currency = substr( $amount, 0, 3 );
    $currency =~ tr/a-z/A-Z/;
    if ( $currency eq "" ) {
      $currency = "USD";
    }
    my $exponent = $isotables::currencyUSD2{$currency};
    $amt = sprintf( "%d", ( substr( $amount, 4 ) * ( 10**$exponent ) ) + .0001 );
    $bd[13] = "<Amount>$amt</Amount>";
    $bd[14] = "<Currency>$currency</Currency>";
    $bd[15] = "<CREDIT_CARD_DATA>";
    my $cardnum = substr( $cardnumber, 0, 19 );
    $bd[16] = "<CreditCardNumber>$cardnum</CreditCardNumber>";
    my $authcode = substr( $auth_code, 0, 6 );
    $bd[17] = "<AuthorizationCode>$authcode</AuthorizationCode>";

    my $yrexp = "20" . substr( $exp, 3, 2 );
    my $monthexp = substr( $exp, 0, 2 );
    $bd[18] = "<ExpirationYear>$yrexp</ExpirationYear>";
    $bd[19] = "<ExpirationMonth>$monthexp</ExpirationMonth>";

    my $cardname = $card_name;

    #$cardname =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
    $cardname =~ s/[^(?:\P{L}\p{L}*)+0-9\.\']/ /g;
    $bd[20] = "<CardHolderName>$cardname</CardHolderName>";

    my $cardstartdate = substr( $auth_code, 32, 5 );
    $cardstartdate =~ s/ //g;
    my $cardissuenum = substr( $auth_code, 37, 2 );
    $cardissuenum =~ s/ //g;
    if ( $cardstartdate ne "" ) {

      # cardstartdate format MM/YY
      my $cardstartmonth = substr( $cardstartdate, 0, 2 );
      my $cardstartyear = "20" . substr( $cardstartdate, 3, 2 );
      $bd[21] = "<CardStartYear>$cardstartyear</CardStartYear>";
      $bd[22] = "<CardStartMonth>$cardstartmonth</CardStartMonth>";

      if ( $cardissuenum ne "" ) {
        $bd[23] = "<CardIssueNumber>$cardissuenum</CardIssueNumber>";
      }
    }

    $bd[24] = "</CREDIT_CARD_DATA>";

    if ( $transflags =~ /recinitial/ ) {
      $bd[25] = "<RECURRING_TRANSACTION>";
      $bd[26] = "<Type>Initial</Type>";
      $bd[27] = "</RECURRING_TRANSACTION>";
    } elsif ( $transflags =~ /recurring/ ) {
      $bd[25] = "<RECURRING_TRANSACTION>";
      $bd[26] = "<Type>Repeated</Type>";
      $bd[27] = "</RECURRING_TRANSACTION>";
    }

    #else {
    #  $bd[24] = "<RECURRING_TRANSACTION>";
    #  $bd[25] = "<Type>Single</Type>";
    #  $bd[26] = "</RECURRING_TRANSACTION>";
    #}

    my ( $fname, $lname ) = split( / /, $card_name );
    $fname =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
    $lname =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
    $bd[28] = "<CORPTRUSTCENTER_DATA>";
    $bd[29] = "<ADDRESS>";
    $bd[30] = "<FirstName>$fname</FirstName>";
    $bd[31] = "<LastName>$lname</LastName>";
    $bd[32] = "<Address1>$card_addr</Address1>";
    $bd[33] = "<Address2></Address2>";
    $bd[34] = "<State>$card_state</State>";
    $bd[35] = "<City>$card_city</City>";
    $bd[36] = "<Country>$card_country</Country>";
    $bd[37] = "<ZipCode>$card_zip</ZipCode>";

    #$bd[43] = "<Email>$datainfo{'email'}</Email> ";
    #$bd[44] = "<Phone>$datainfo{'phone'}</Phone>";
    $bd[38] = "</ADDRESS>";
    $bd[39] = "</CORPTRUSTCENTER_DATA>";

    #$bd[47] = "<CONTACT_DATA>";
    #$bd[48] = "<IPAddress>$ipaddress</IPAddress>";
    #$bd[49] = "</CONTACT_DATA>";
    $bd[40] = "</CC_TRANSACTION>";
    $bd[41] = "</FNC_CC_CAPTURE_AUTHORIZATION>";
  } else {

    #if (($operation eq "postauth") && ($finalstatus eq "locked")) {
    #  $bd[7] = "<FNC_CC_QUERY>";
    #  $bd[8] = "<FunctionID>Capturing Preauthorization</FunctionID>";	# function id (32a)
    #}
    if ( $operation eq "return" ) {
      $bd[7] = "<FNC_CC_BOOKBACK>";
      $bd[8] = "<FunctionID>Bookback</FunctionID>";    # function id (32a)
    } elsif ( $operation eq "auth" ) {
      $bd[7] = "<FNC_CC_QUERY>";
      $bd[8] = "<FunctionID>Query</FunctionID>";       # function id (32a)
    } else {
      $bd[7] = "<FNC_CC_CAPTURING>";
      $bd[8] = "<FunctionID>Capturing Preauthorization</FunctionID>";    # function id (32a)
    }
    $tid = substr( $terminal_id . " " x 10, 0, 10 );
    $bd[9] = "<CC_TRANSACTION>";
    if ( $operation eq "auth" ) {
      $transid = substr( $orderid, 0, 26 );
      $bd[10] = "<ReferenceTransactionID>Trans $transid</ReferenceTransactionID>";

      #my $newtime = &miscutils::strtotime($trans_time) + (3600 * 2) - 60;	# their time is gmt + 2 hours (changed to +1 hour on Sun Oct 26 2009)
      my $newtime = &miscutils::strtotime($trans_time) + ( 3600 * 1 ) - 60;    # their time is gmt + 2 hours (changed to +1 hour on Sun Oct 26 2009)
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($newtime);
      my $starttime = sprintf( "%04d-%02d-%02d %02d:%02d:%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );

      $newtime = &miscutils::strtotime($trans_time) + ( 3600 * 2 ) + ( 60 * 14 );    # (changed to +1 hour on Sun Oct 26 2009)
                                                                                     #$newtime = &miscutils::strtotime($trans_time) + (3600 * 1) + (60 * 14); 	# (changed to +1 hour on Sun Oct 26 2009)
                                                                                     #my $now = time() + (3600 * 2);	# their time is gmt + 2 hours (changed to +1 hour on Sun Oct 26 2009)
      my $now = time() + ( 3600 * 1 );                                               # their time is gmt + 2 hours (changed to +1 hour on Sun Oct 26 2009)
      my $printstr = "now: $now\n";
      &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
      my $printstr = "newtime: $newtime\n";
      &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
      if ( $newtime > $now ) {
        $newtime = $now - 10;

        #$newtime = $now - (3600 * 11);
      }
      my $printstr = "newtime: $newtime\n";
      &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
      ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($newtime);
      my $endtime = sprintf( "%04d-%02d-%02d %02d:%02d:%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );

      $bd[11] = "<StartTime>$starttime</StartTime>";
      $bd[12] = "<EndTime>$endtime</EndTime>";
      my $printstr = "start: $starttime\n";
      &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
      my $printstr = "end: $endtime\n";
      &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
    } else {
      $transid = substr( $orderid, 0, 26 );
      $bd[10] = "<TransactionID>Trans $transid</TransactionID>";
      if ( $transflags !~ /recurring/ ) {
        $bd[11] = "<CountryCode>$country</CountryCode>";
      }

      my $extramarketdata = substr( $auth_code, 39, 20 );
      $extramarketdata =~ s/ //g;
      $bd[12] = "<Usage>$extramarketdata</Usage>";

      $currency = substr( $amount, 0, 3 );
      $currency =~ tr/a-z/A-Z/;

      #$amt = sprintf("%d", (substr($amount,4) * 100) + .0001);
      my $exponent = $isotables::currencyUSD2{$currency};
      $amt = sprintf( "%d", ( substr( $amount, 4 ) * ( 10**$exponent ) ) + .0001 );
      $bd[13] = "<Amount>$amt</Amount>";
      $bd[14] = "<Currency>$currency</Currency>";
      $bd[15] = "<GuWID>$refnumber</GuWID>";
      my $authcode = substr( $auth_code, 0, 8 );
      $authcode =~ s/ //g;
      $bd[16] = "<AuthorizationCode>$authcode</AuthorizationCode>";
    }
    $bd[17] = "</CC_TRANSACTION>";

    #if (($operation eq "postauth") && ($finalstatus eq "locked")) {
    #  $bd[17] = "</FNC_CC_QUERY>";
    #}
    if ( $operation eq "return" ) {
      $bd[18] = "</FNC_CC_BOOKBACK>";
    } elsif ( $operation eq "auth" ) {
      $bd[18] = "</FNC_CC_QUERY>";
    } else {
      $bd[18] = "</FNC_CC_CAPTURING>";
    }
  }
  $bd[42] = "</W_JOB>";
  $bd[43] = "</W_REQUEST>";
  $bd[44] = "</WIRECARD_BXML>";

  my $message = "";
  my $indent  = 0;
  foreach $var (@bd) {
    if ( $var eq "" ) {
      next;
    }
    if ( $var =~ /^<\/.*>/ ) {
      $indent--;
    }
    $message = $message . " " x $indent . $var . "\n";
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
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
  ($message2) = unpack "H*", $printmessage;
  my $printstr = "$message2\n\n";
  &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );

  $message1 = $printmessage;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;

  #print "$message1\n$message2\n\n";
}

sub errorchecking {
  my $chkauthcode = substr( $auth_code, 0, 8 );
  $authcode =~ s/ //g;

  #if ((($chkauthcode eq "") && ($operation ne "auth")) || (($refnumber eq "") && ($origoperation ne "forceauth"))) {
  if ( ( ( $operation ne "return" ) || ( ( $returnflag ne "yes" ) && ( $transflags !~ /payment/ ) ) )
    && ( ( ( $chkauthcode eq "" ) && ( $operation ne "auth" ) ) || ( ( $refnumber eq "" ) && ( $origoperation ne "forceauth" ) ) ) ) {
    my $printstr = "dddd $username $orderid $operation $chkauthcode $auth_code $refnumber\n";
    &procutils::filewrite( "$username", "wirecard", "/home/pay1/batchfiles/devlogs/wirecard", "miscdebug.txt", "append", "misc", $printstr );
    &errormsg( $username, $orderid, $operation, 'missing auth code or reference number' );
    return 1;
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

sub errormsg {
  my ( $username, $orderid, $operation, $errmsg ) = @_;

  my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where orderid=?
            and trans_date>=?
            and username=?
            and finalstatus='pending'
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
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$errmsg", "$orderid", "$username", "$onemonthsagotime" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

}

