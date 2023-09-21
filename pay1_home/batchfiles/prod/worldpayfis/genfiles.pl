#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;
use isotables;
use smpsutils;
use worldpayfis;

$devprod = "logs";

my $group = $ARGV[0];
if ( $group eq "" ) {
  $group = "0";
}

if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/worldpayfis/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'worldpayfis/genfiles.pl $group'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl $group already running, exiting...\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: worldpayfis - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

my $checkuser = &procutils::fileread( "$username", "worldpayfis", "/home/pay1/batchfiles/$devprod/worldpayfis", "genfiles$group.txt" );
chop $checkuser;

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>='$checkuser'";
}

#$checkstring = "and t.username='aaaa'";
#$checkstring = "and t.username in ('aaaa','aaaa')";

$socketopenflag = 0;

#my $logfilestr = "ii in genfilestst.pl\n";
#&procutils::filewrite("$worldpayfis::username","worldpayfis","/home/pay1/batchfiles/$devprod/worldpayfis","goscript.txt","append","",$logfilestr);

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

if ( !-e "/home/pay1/batchfiles/$devprod/worldpayfis/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/worldpayfis/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/worldpayfis/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/worldpayfis/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/worldpayfis/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/worldpayfis/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/worldpayfis/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/worldpayfis/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/worldpayfis/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/worldpayfis/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: worldpayfis - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/worldpayfis/$fileyear.\n\n";
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
        and t.finalstatus in ('pending','locked')
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.processor='worldpayfis'
        and o.lastoptime>=?
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user $usercount $usertdate\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );

  #my $logfilestr = "ii $user $usercount $usertdate\n";
  #&procutils::filewrite("$worldpayfis::username","worldpayfis","/home/pay1/batchfiles/$devprod/worldpayfis","goscript.txt","append","",$logfilestr);

  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

foreach $username ( sort @userarray ) {
  if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/worldpayfis/stopgenfiles.txt" ) ) {
    unlink "/home/pay1/batchfiles/$devprod/worldpayfis/batchfile.txt";
    last;
  }

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/$devprod/worldpayfis", "genfiles$group.txt", "write", "", $checkinstr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/$devprod/worldpayfis", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};

  my $printstr = "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );

  if ( $usercountarray{$username} > 2000 ) {
    $batchcntuser = 500;    # worldpayfis recommends batches smaller than 500
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
        select merchant_id,pubsecret,proc_type,company,addr1,city,state,zip,tel,status
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $company, $address, $city, $state, $zip, $tel, $status ) = &procutils::merchread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
        select accounttoken,acceptorid,industrycode,batchtime,accountid
        from worldpayfis
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $accounttoken, $acceptorid, $industrycode, $batchgroup, $accountid ) = &procutils::merchread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  # xxxx temporary
  #$accountid = "1087133";
  #$accounttoken = "6A2F21BD4BDD49544AFAF989BA7FF9BA997167377D73414A94D0C149285396B465B54D01";
  #$acceptorid = "874767717";
  #$terminal_id = "0060810007";

  if ( $status ne "live" ) {
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
  } elsif ( ( $group eq "0" ) && ( $batchgroup ne "" ) && ( $batchgroup ne "0" ) ) {
    next;
  } elsif ( $group !~ /^(0|1|2|3|4)$/ ) {
    next;
  }

  umask 0077;
  $logfilestr = "";
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );

  $logfilestr .= "$username\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/$devprod/worldpayfis/$fileyear", "$username$time.txt", "write", "", $logfilestr );

  my $printstr = "aaaa $starttransdate $onemonthsagotime $username\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );

  $batch_flag = 0;
  $netamount  = 0;
  $hashtotal  = 0;
  $batchcnt   = 1;
  $recseqnum  = 0;

  #$message = &sendbatchclose("query");
  #$message = &sendbatchclose("close","2");
  #$response = &sendmessage($message);
  #&endbatchclose($response,"query");
  #exit;

  #select orderid
  #from operation_log
  #where trans_date>=?
  #and lastoptime>=?
  #and username=?
  #and lastopstatus in ('pending','locked')
  #and lastop IN ('auth','postauth','return')
  #and processor='worldpayfis'
  #and (voidstatus is NULL or voidstatus ='')
  #and (accttype is NULL or accttype ='' or accttype='credit')
  my $dbquerystr = <<"dbEOM";
        select o.orderid
        from operation_log o, trans_log t
        where t.trans_date>=?
        and t.username=?
        and t.operation in ('auth','postauth','xreturn')
        and t.finalstatus in ('pending','locked')
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastop=t.operation
        and o.lastopstatus='pending'
        and o.processor='worldpayfis'
        and (o.voidstatus is NULL or o.voidstatus ='')
        and (o.accttype is NULL or o.accttype ='' or o.accttype='credit')
dbEOM
  my @dbvalues = ( "$onemonthsago", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  @orderidarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 1 ) {
    ($orderid) = @sthtransvalarray[ $vali .. $vali + 0 ];

    #my $logfilestr = "jj $orderid\n";
    #&procutils::filewrite("$worldpayfis::username","worldpayfis","/home/pay1/batchfiles/$devprod/worldpayfis","goscript.txt","append","",$logfilestr);

    #@orderidarray = (@orderidarray,$orderid);
    $orderidarray[ ++$#orderidarray ] = $orderid;
  }

  foreach $orderid ( sort @orderidarray ) {
    if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/worldpayfis/stopgenfiles.txt" ) ) {
      unlink "/home/pay1/batchfiles/$devprod/worldpayfis/batchfile.txt";
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
    } elsif ( $authstatus eq "success" ) {
      $origoperation = "auth";
    } else {
      $origoperation = "";
    }

    if ( $postauthstatus eq "success" ) {
      $chkreturntime = $postauthtime;
    } elsif ( $authstatus eq "success" ) {
      $chkreturntime = $authtime;
    }

    # xxxx temporary comment out this for testing
    # only do returns on existing transactions if they are more than 1 day old
    #my $time1 = &miscutils::strtotime($chkreturntime);
    #my $time2 = time();
    #if (($operation eq "return") && ($transflags !~ /payment/) && ($origoperation ne "") && ($time2 < $time1 + (3600 * 24))) {
    #  next;
    #}

    # don't do original returns on locked transactions
    if ( ( $operation eq "return" ) && ( $transflags =~ /payment/ ) && ( $finalstatus eq "locked" ) ) {
      next;
    } elsif ( ( $operation eq "return" ) && ( $returnflag eq "yes" ) && ( $postauthstatus eq "" ) && ( $finalstatus eq "locked" ) ) {
      next;
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/$devprod/worldpayfis/$fileyear", "$username$time.txt", "append", "", $logfilestr );

    my $printstr = "$orderid $operation $auth_code $refnumber\n";
    &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );
    print "cccccccc $orderid $operation $auth_code $refnumber\n";

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "worldpayfis", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $card_type = &smpsutils::checkcard($cardnumber);

    $errorflag = &errorchecking();
    my $printstr = "cccc $errorflag\n";
    &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );
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

  $operation = "query";
  $message   = &sendbatchclose("query");
  $response  = &sendmessage($message);
  &endbatchclose( $response, "query" );

}

if ( ( !-e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) && ( !-e "/home/pay1/batchfiles/$devprod/worldpayfis/stopgenfiles.txt" ) ) {
  umask 0033;
  $checkinstr = "";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/$devprod/worldpayfis", "genfiles$group.txt", "write", "", $checkinstr );
}

unlink "/home/pay1/batchfiles/$devprod/worldpayfis/batchfile.txt";

$socketopenflag = 0;

exit;

sub sendmessage {
  my ($msg) = @_;

  my $host = "transaction.elementexpress.com";
  if ( $username eq "testworld" ) {
    $host = "certtransaction.elementexpress.com";
  }
  my $port = "443";
  my $path = "";

  my $messagestr = $msg;
  my $xs         = "x" x length($cardnumber);
  $messagestr =~ s/CardNumber>[0-9]+<\/CardNumber/CardNumber>$xs<\/CardNumber/;

  my %terminaltypehash            = ( "0", "Unknown",         "1", "PointOfSale", "2", "ECommerce", "3", "MOTO" );
  my %terminalcapabilitycodehash  = ( "3", "MagstripeReader", "5", "KeyEntered" );
  my %terminalenvironmentcodehash = ( "2", "LocalAttended",   "6", "Ecommerce" );
  my %cardpresentcodehash         = ( "3", "NotPresent",      "2", "Present" );
  my %cvvpresencecodehash         = ( "1", "NotProvided",     "2", "Provided", "3", "Illegible", "4", "CustomerIllegible" );
  my %cardinputcodehash           = ( "2", "MagstripeRead",   "4", "ManualKeyed", "5", "MagstripeFailure" );
  my %cardholderpresentcodehash   = ( "2", "Present",         "4", "MailOrder", "5", "PhoneOrder", "7", "ECommerce" );
  my %motoecicodehash =
    ( "1", "NotUed", "2", "Single", "3", "Recurring", "4", "Installment", "5", "SecureElectronicCommerce", "6", "NonAuthenticatedSecureTransaction", "7", "NonAuthenticatedSecureECommerceTransaction" );
  my %consentcodehash    = ( "1", "FaceToFace", "2", "Phone", "3", "Internet" );
  my %marketcodehash     = ( "3", "ECommerce",  "7", "Retail" );
  my %paymenttypehash    = ( "1", "Recurring",  "2", "Installment", "3", "CardHolderInitiated", "4", "CredentialOnFile" );
  my %submissiontypehash = ( "1", "Initial",    "3", "Resubmission", "4", "ReAuthorization", "4", "DelayedCharges", "6", "NoShow", "2", "Subsequent" );
  my %hsaamttypehash     = ( "2", "Healthcare", "3", "Transit", "4", "Copayment", "5", "OriginalAmount", "7", "Prescription", "8", "Vision", "9", "Clinic", "10", "Dental" );

  #my %xhash = ("x","x","x","x","x","x","x","x","x","x","x","x","x","x","x","x","x","x");

  $messagestr =~ s/\n/;;;;/g;
  $messagestr =~ s/(<TerminalType>)([023])(<.+?>)/$1$2$3    \t\t\t# $terminaltypehash{$2}/;
  $messagestr =~ s/(<TerminalCapabilityCode>)([35])(<.+?>)/$1$2$3    \t# $terminalcapabilitycodehash{$2}/;
  $messagestr =~ s/(<TerminalEnvironmentCode>)([26])(<.+?>)/$1$2$3    \t# $terminalenvironmentcodehash{$2}/;
  $messagestr =~ s/(<CardPresentCode>)([23])(<.+?>)/$1$2$3    \t# $cardpresentcodehash{$2}/;
  $messagestr =~ s/(<CVVPresenceCode>)([1234])(<.+?>)/$1$2$3    \t# $cvvpresencecodehash{$2}/;
  $messagestr =~ s/(<CardInputCode>)([245])(<.+?>)/$1$2$3    \t\t# $cardinputcodehash{$2}/;
  $messagestr =~ s/(<CardholderPresentCode>)([2457])(<.+?>)/$1$2$3    \t# $cardholderpresentcodehash{$2}/;
  $messagestr =~ s/(<MotoECICode>)([234567])(<.+?>)/$1$2$3    \t\t# $motoecicodehash{$2}/;
  $messagestr =~ s/(<ConsentCode>)([123])(<.+?>)/$1$2$3    \t\t# $consentcodehash{$2}/;
  $messagestr =~ s/(<MarketCode>)([37])(<.+?>)/$1$2$3    \t\t# $marketcodehash{$2}/;
  $messagestr =~ s/(<PaymentType>)([0123456])(<.+?>)/$1$2$3    \t\t# $paymenttypehash{$2}/;
  $messagestr =~ s/(<SubmissionType>)([0123456])(<.+?>)/$1$2$3    \t\t# $submissiontypehash{$2}/;
  $messagestr =~ s/(<Healthcare.*?AmountType>)([012345789]+)(<.+?>)/$1$2$3    \t\t# $hsaamttypehash{$2}/g;
  $messagestr =~ s/;;;;/\n/g;

  my $dnserrorflag = "";
  my $dest_ip      = gethostbyname($host);
  if ( ( $username ne "testworld" ) && ( $dest_ip eq "" ) ) {
    $host         = "74.120.157.10";
    $dnserrorflag = " dns error";
  }

  my $temptime = gmtime( time() );
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$temptime $orderid$dnserrorflag\n$temptime send: $messagestr\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/$devprod/worldpayfis/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  my $len        = length($msg);
  my %sslheaders = ();
  $sslheaders{'Host'}       = "$host:$port";
  $sslheaders{'User-Agent'} = 'PlugNPay';

  #$sslheaders{'Authorization'} = "Basic " . &MIME::Base64::encode("$loginun\:$loginpw");
  $sslheaders{'Content-Type'}   = 'text/xml';
  $sslheaders{'Content-Length'} = $len;

  #my ($response) = &procutils::sendsslmsg("processor_worldpayfis",$host,$port,$path,$msg,"direct",%sslheaders);
  $response = "";

  eval { ( $response, $header, %resulthash ) = &procutils::sendsslmsg( "processor_worldpayfis", $host, $port, $path, $msg, "direct", %sslheaders ); };
  if ($@) {
    my $err = $@;
    print "err: $@\n";

    umask 0011;
    $mytime        = gmtime( time() );
    $logfiletmpstr = "";
    $logfiletmpstr .= "$mytime err: $err\n\n";
    &procutils::filewrite( "$username", "moneris", "/home/pay1/batchfiles/$devprod/worldpayfis/$fileyear", "$username$time.txt", "append", "", $logfiletmpstr );
  }

  #my $tmpresp = $msg;
  #$tmpresp =~ s/\n/\ncc /g;
  #my $logfilestr = "aa  $username $orderid $operation\n";	# dont have a testnum to fill in
  #$logfilestr .= "cc $tmpresp\n";
  #$tmpresp = $response;
  #$tmpresp =~ s/\n//g;
  #$logfilestr .= "dd $tmpresp\n\n";
  #&procutils::filewrite("$worldpayfis::username","worldpayfis","/home/pay1/batchfiles/$devprod/worldpayfis","goscript.txt","append","",$logfilestr);

  my $temptime = gmtime( time() );
  umask 0077;
  $logfilestr = "";
  my $responsestr = $response;
  $responsestr =~ s/></>\n</g;
  $logfilestr .= "$temptime recv: $responsestr\n\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/$devprod/worldpayfis/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  return $response;
}

sub endbatchclose {
  my ( $response, $op ) = @_;

  my $tcode = "";
  if ( $op eq "query" ) {
    $tcode = "BatchTotalsQuery";
  } elsif ( $op eq "close" ) {
    $tcode = "BatchClose";
  }

  my $data = $response;
  $data =~ s/\r{0,1}\n//g;
  $data =~ s/>\s*</>;;;;</g;
  my @tmpfields  = split( /;;;;/, $data );
  my %temparray2 = ();
  my $levelstr   = "";
  foreach my $var (@tmpfields) {
    if ( $var =~ /<\!/ ) {
    } elsif ( $var =~ /<\?/ ) {
    } elsif ( $var =~ /<(.+)>(.*)</ ) {
      my $var2 = $1;
      my $var3 = $2;
      $var2 =~ s/ .*$//;
      if ( $temparray2{"$levelstr$var2"} eq "" ) {
        $temparray2{"$levelstr$var2"} = $var3;
      } else {
        $temparray2{"$levelstr$var2"} = $temparray2{"$levelstr$var2"} . "," . $var3;
      }
    } elsif ( $var =~ /<\/(.+)>/ ) {
      $levelstr =~ s/,[^,]*?,$/,/;
    } elsif ( ( $var =~ /<(.+)>/ ) && ( $var !~ /<\?/ ) && ( $var !~ /\/>/ ) ) {
      my $var2 = $1;
      $var2 =~ s/ .*$//;
      $levelstr = $levelstr . $var2 . ",";
    }
  }

  my $logfilestr = "";
  $logfilestr .= "username   $username\n";
  $logfilestr .= "batchquery:\n";
  foreach my $key ( sort keys %temparray2 ) {
    print "$key: $temparray2{$key}\n";
    $logfilestr .= "$key: $temparray2{$key}\n";
  }
  $logfilestr .= "\n";

  my $hostbatchid = $temparray2{ "$tcode" . "Response,Response,Batch,HostBatchID" };
  my $hostitemid  = $temparray2{ "$tcode" . "Response,Response,Batch,HostItemID" };

  $logfilestr .= "hostbatchid: $hostbatchid\n\n";

  umask 0077;
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/$devprod/worldpayfis/$fileyear", "$username$time.txt", "append", "", $logfilestr );

}

sub endbatch {
  my ($response) = @_;

  my $data = $response;
  $data =~ s/\r{0,1}\n//g;
  $data =~ s/>\s*</>;;;;</g;
  my @tmpfields  = split( /;;;;/, $data );
  my %temparray2 = ();
  my $levelstr   = "";
  foreach my $var (@tmpfields) {
    if ( $var =~ /<\!/ ) {
    } elsif ( $var =~ /<\?/ ) {
    } elsif ( $var =~ /<(.+)>(.*)</ ) {
      my $var2 = $1;
      my $var3 = $2;
      $var2 =~ s/ .*$//;
      if ( $temparray2{"$levelstr$var2"} eq "" ) {
        $temparray2{"$levelstr$var2"} = $var3;
      } else {
        $temparray2{"$levelstr$var2"} = $temparray2{"$levelstr$var2"} . "," . $var3;
      }
    } elsif ( $var =~ /<\/(.+)>/ ) {
      $levelstr =~ s/,[^,]*?,$/,/;
    } elsif ( ( $var =~ /<(.+)>/ ) && ( $var !~ /<\?/ ) && ( $var !~ /\/>/ ) ) {
      my $var2 = $1;
      $var2 =~ s/ .*$//;
      $levelstr = $levelstr . $var2 . ",";
    }
  }
  foreach my $key ( sort keys %temparray2 ) {
    print "$key: $temparray2{$key}\n";
  }

  $errorflag = "";
  $respcode  = $temparray2{ "$tcode" . "Response,Response,ExpressResponseCode" };    #: 0
                                                                                     #$respcode = $temparray2{"$tcode" . "Response,Response,HostResponseCode"};        #: 000

  my $msg  = $temparray2{ "$tcode" . "Response,Response,ExpressResponseMessage" };   #: Approved
  my $msg2 = $temparray2{ "$tcode" . "Response,Response,HostResponseMessage" };      #: AP

  my $errrespcode  = $temparray2{"Response,Response,ExpressResponseCode"};
  my $errrespdescr = $temparray2{"Response,Response,ExpressResponseMessage"};
  if ( $errrespcode ne "" ) {
    $appmssg = "$errrespdescr";
  } else {
    $appmssg = "$msg$msg2";
  }

  $transid    = $temparray2{ "$tcode" . "Response,Response,Transaction,TransactionID" };
  $nettransid = $temparray2{ "$tcode" . "Response,Response,Transaction,NetworkTransactionID" };

  #$worldpayfis::appcode = $temparray2{"$tcode" . "Response,Response,Transaction,ApprovalNumber"};       #: 000055

  #$timest = $temparray{'TimeStamp'};
  #my $advice = $temparray{'Advice'};

  #if ($errrespcode ne "") {
  #$errorflag = $temparray{'Type'};
  #$appmssg = $temparray{'Type'} . " " . $temparray{'Number'} . " " . $temparray{'Message'} . " " . $temparray{'Advice'};
  #$appmssg = substr($appmssg,0,64);
  #}

  # xxxx temporary for testing only
  #my $transid = substr($auth_code,128,15);
  $transid =~ s/ //g;
  $ttype = $operation;
  if ( ( $operation eq "return" ) && ( $origoperation !~ /auth/ ) ) {
    $ttype = "credit";
  } elsif ( $operation eq "return" ) {
    $ttype = "return";
  } elsif ( ( $operation eq "postauth" ) && ( $forceauthstatus eq "success" ) ) {
    $ttype = "force";
  } elsif ( $operation eq "postauth" ) {
    $ttype = "completion";
  }
  $ttype = substr( $ttype . " " x 10, 0, 10 );
  $ccnum = substr( $cardnumber,       0, 4 ) . "xxxx";
  $namt  = $amount;
  $namt =~ s/[a-z ]//g;
  $errmsg = substr( $result{'MErrMsg'}, 0, 30 );
  open( outfilea, ">>/home/pay1/batchfiles/devlogs/worldpayfis/scriptresults.txt" );
  print outfilea "$ttype	$ccnum	$namt	$transid	$respcode $appmssg	$transflags\n";
  close(outfilea);

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "orderid   $orderid\n";
  $logfilestr .= "respcode   $respcode  $operation\n";
  $logfilestr .= "appmssg   $appmssg\n";
  $logfilestr .= "timestamp   $timestamp\n";
  $logfilestr .= "result   $time$batchnum\n\n\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/$devprod/worldpayfis/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  if ( $respcode =~ /^(0)$/ ) {

    $newauthcode = $auth_code;

    if ( $newauthcode eq "" ) {
      $newauthcode = $temparray2{ "$tcode" . "Response,Response,Transaction,ApprovalNumber" };
      $newauthcode = substr( $newauthcode . " " x 6, 0, 6 );
      $newauthcode = $newauthcode . " " x 137;
    }

    if ( $nettransid ne "" ) {
      $nettransid = substr( $nettransid . " " x 20, 0, 20 );
      $newauthcode = substr( $newauthcode, 0, 6 ) . $nettransid . substr( $newauthcode, 26 );
    }

    if ( $transid ne "" ) {
      $transid = substr( $transid . " " x 15, 0, 15 );
      $newauthcode = substr( $newauthcode, 0, 128 ) . $transid . substr( $newauthcode, 143 );
    }

    print "newauthcode: $newauthcode\n";

    my $printstr = "$respcode  $orderid  $onemonthsago  $time$batchnum  $username\n";
    &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?,auth_code=?
            where orderid=?
            and trans_date>=?
            and result=?
            and username=?
            and finalstatus='locked'
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$newauthcode", "$orderid", "$onemonthsago", "$time$batchnum", "$username" );
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
    print MAILERR "Subject: worldpayfis - AUTH ERROR\n";
    print MAILERR "\n";
    print MAILERR "Set to pending:\n";
    print MAILERR "username: $username\n";
    print MAILERR "orderid: $orderid\n";
    print MAILERR "operation: $operation\n";
    print MAILERR "result: $respcode: $appmssg\n\n";
    print MAILERR "batchtransdate: $batchtransdate\n";
    close MAILERR;

  } elsif ( $respcode ne "" ) {
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
      print MAILERR "Subject: worldpayfis - AUTH ERROR\n";
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
    print MAILERR "Subject: worldpayfis - DATA ERROR\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: data error\n\n";
    print MAILERR "batchtransdate: $batchtransdate\n";
    close MAILERR;
  } elsif ( $respcode eq "PENDING" ) {
  } else {
    my $printstr = "respcode	$respcode unknown\n";
    &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: worldpayfis - unkown error\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "result: $resp\n";
    print MAILERR "orderid: $orderid\n";
    print MAILERR "file: $username$time.txt\n";
    close MAILERR;

    if ( $origreturnflag == 1 ) {
      open( MAILWIRE, "| /usr/lib/sendmail -t" );
      print MAILWIRE "To: support\@worldpayfis.com\n";
      print MAILWIRE "From: cprice\@plugnpay.com\n";
      print MAILWIRE "Bcc: cprice\@plugnpay.com\n";
      print MAILWIRE "Subject: Plug & Pay - worldpayfis - transaction status\n";
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
          from worldpayfis
          where username=?
dbEOM
  my @dbvalues = ("$username");
  ($batchnum) = &procutils::merchread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = $batchnum + 1;
  if ( $batchnum >= 998 ) {
    $batchnum = 1;
  }

  my $dbquerystr = <<"dbEOM";
          update worldpayfis set batchnum=?
          where username=?
dbEOM
  my @dbvalues = ( "$batchnum", "$username" );
  &procutils::merchupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = substr( "0000" . $batchnum, -4, 4 );

}

sub sendbatchclose {
  my ( $op, $hostbatchid ) = @_;

  if ( $op eq "query" ) {
    $tcode = "BatchTotalsQuery";
  } elsif ( $op eq "close" ) {
    $tcode = "BatchClose";
  }

  @bd    = ();
  $bd[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>";                  # stx
  $bd[1] = "<$tcode xmlns=\"https://transaction.elementexpress.com\">";    # cert

  $bd[4] = "<Credentials>";
  $bd[5] = "<AccountID>$accountid</AccountID>";
  $bd[6] = "<AccountToken>$accounttoken</AccountToken>";
  $bd[7] = "<AcceptorID>$merchant_id</AcceptorID>";
  $bd[9] = "</Credentials>";

  $bd[10] = "<Application>";
  $bd[11] = "<ApplicationID>10279</ApplicationID>";
  $bd[12] = "<ApplicationName>PNP</ApplicationName>";
  $bd[13] = "<ApplicationVersion>1.00</ApplicationVersion>";
  $bd[16] = "</Application>";

  $bd[20] = "<Terminal>";
  $bd[21] = "<TerminalID>$terminal_id</TerminalID>";
  $bd[22] = "</Terminal>";

  $bd[23] = "<Batch>";
  if ( $op eq "query" ) {
    $bd[24] = "<BatchQueryType>0</BatchQueryType>";    # 0 Total
  } elsif ( $op eq "close" ) {
    $bd[24] = "<BatchCloseType>1</BatchCloseType>";    # 1 Force
  }
  $bd[25] = "<HostBatchID>$hostbatchid</HostBatchID>";
  $bd[26] = "</Batch>";

  $bd[27] = "</$tcode>";

  my $message = "";
  my $indent  = 0;
  foreach $var (@bd) {
    if ( $var eq "" ) {
      next;
    }
    if ( $var =~ /^<\/.*>/ ) {
      $indent--;
    }
    if ( $var !~ /></ ) {
      $message = $message . "\t" x $indent . $var . "\n";
    }
    if ( ( $var !~ /\// ) && ( $var != /<?/ ) ) {
      $indent++;
    }
    if ( $indent < 0 ) {
      $indent = 0;
    }
  }

  return $message;
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

  @bd = ();

  #$transid = substr($orderid,0,26);

  my $extramarketdata = substr( $auth_code, 39, 20 );
  $extramarketdata =~ s/ //g;

  $currency = substr( $amount, 0, 3 );
  $currency =~ tr/a-z/A-Z/;
  if ( $currency eq "" ) {
    $currency = "USD";
  }
  my $exponent = $isotables::currencyUSD2{$currency};
  $amt = sprintf( "%d", ( substr( $amount, 4 ) * ( 10**$exponent ) ) + .0001 );
  my $authcode = substr( $auth_code, 0, 6 );

  my $cardname = $card_name;

  #$cardname =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  $cardname =~ s/[^(?:\P{L}\p{L}*)+0-9\.\']/ /g;

  $bd[0] = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>";    # stx

  $tcode = "";
  my %ophash = (
    "credit,auth,",        "CreditCardAuthorization", "credit,reauth,",       "CreditCardReversal",                "credit,reauth,incr",   "CreditCardIncrementalAuthorization",
    "credit,forceauth,",   "CreditCardForce",         "credit,postauth,",     "CreditCardAuthorizationCompletion", "credit,query,",        "TransactionQuery",
    "credit,void,",        "CreditCardReversal",      "credit,return,",       "CreditCardReturn",                  "credit,return,new",    "CreditCardCredit",
    "credit,auth,avsonly", "CreditCardAVSOnly",       "credit,auth,gettoken", "TokenCreateWithTransID",            "credit,auth,balance",  "CreditCardBalanceInquiry",
    "credit,query,",       "TransactionQuery",        "check,auth,",          "CheckSale",                         "check,return,",        "CheckCredit",
    "check,return,new",    "CheckReturn",             "check,void,",          "CheckReversal",                     "check,query,",         "CheckQuery",
    "gift,auth,",          "GiftCardSale",            "gift,auth,balance",    "GiftCardBalanceInquiry",            "gift,postauth,",       "GiftCardAuthorizationCompletion",
    "gift,return,new",     "GiftCardCredit",          "gift,return,issue",    "GiftCardIssue",                     "gift,return,activate", "GiftCardActivate",
    "gift,return,reload",  "GiftCardReload",          "gift,return,",         "GiftCardReturn",                    "gift,reauth,",         "GiftCardReversal",
    "gift,void,",          "GiftCardReversal",
  );

  my $cardpath = "credit";
  if ( $transflags =~ /debit/ ) {
    $cardpath = "debit";
  } elsif ( $transflags =~ /gift/ ) {
    $cardpath = "gift";
  } elsif ( $accttype =~ /(checking|savings)/ ) {
    $cardpath = "check";
  }

  my $opflag = "";
  if ( $transflags =~ /(incr|avsonly|gettoken|balance|issue|activate|reload)/ ) {
    $opflag = $1;
    if ( ( $amount !~ / 0\.00/ ) && ( $transflags =~ /(avsonly|balance)/ ) ) {
      $opflag = "";
    }
  }

  if ( ( $operation eq "return" ) && ( $origoperation !~ /auth/ ) ) {
    $opflag = "new";
  }
  print "$operation  $origoperation\n";
  print "dddd $cardpath,$operation,$opflag\n";

  my $newop = $operation;
  if ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
    $newop = "forceauth";
  }

  $tcode = $ophash{"$cardpath,$newop,$opflag"};

  my $transid = substr( $auth_code, 128, 15 );
  $transid =~ s/ //g;

  # xxxx temporary
  $bd[1] = "<$tcode xmlns=\"https://transaction.elementexpress.com\">";    # cert
                                                                           #$bd[1] = "<$tcode xmlns=\"http://transaction.elementexpress.com\">";	# production

  $bd[4] = "<Credentials>";
  $bd[5] = "<AccountID>$accountid</AccountID>";
  $bd[6] = "<AccountToken>$accounttoken</AccountToken>";
  $bd[7] = "<AcceptorID>$merchant_id</AcceptorID>";

  #$bd[8] = "<NewAccoutToken>$jobid</NewAccoutToken>";
  $bd[9] = "</Credentials>";

  $bd[10] = "<Application>";
  $bd[11] = "<ApplicationID>10279</ApplicationID>";
  $bd[12] = "<ApplicationName>PNP</ApplicationName>";
  $bd[13] = "<ApplicationVersion>1.00</ApplicationVersion>";

  #$bd[14] = "<HostApplicationID>$jobid</HostApplicationID>";
  #$bd[15] = "<HostDeveloperID>$jobid</HostDeveloperID>";
  $bd[16] = "</Application>";

  $bd[20] = "<Terminal>";
  $bd[21] = "<TerminalID>$terminal_id</TerminalID>";

  #my $termtype = "1";	# PointOfSale
  #if ($transflags =~ /moto/) {
  #  $termtype = "3";		# MOTO
  #}
  #elsif ($industrycode !~ /(retail|restaurant)/) {
  #  $termtype = "2";		# ECommerce
  #}

  my $termtype = "2";    # ECommerce
  if ( ( $industrycode =~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $termtype = "1";     # PointOfSale
  } elsif ( ( $transflags =~ /(recur|install)/ ) && ( $transflags !~ /init/ ) ) {
    $termtype = "3";     # MOTO
  } elsif ( $transflags =~ /moto/ ) {
    $termtype = "3";     # MOTO
  }
  $bd[22] = "<TerminalType>$termtype</TerminalType>";

  my $magstripetrack = substr( $auth_code, 118, 1 );
  $magstripetrack =~ s/ //g;

  my $termcap = "5";     # KeyEntered
                         #if ($magstripetrack =~ /^(1|2)/) {}
  if ( $industrycode =~ /^(retail|restaurant)/ ) {
    $termcap = "3";      # MagstripeReader
  }
  $bd[23] = "<TerminalCapabilityCode>$termcap</TerminalCapabilityCode>";

  my $termenv = "6";     # Ecommerce
  if ( ( $industrycode =~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $termenv = "2";      # LocalAttended
  } elsif ( ( $transflags =~ /(recur|install)/ ) && ( $transflags !~ /init/ ) ) {
    $termenv = "2";      # LocalAttended
  } elsif ( $transflags =~ /moto/ ) {
    $termenv = "2";      # LocalAttended
  }
  $bd[24] = "<TerminalEnvironmentCode>$termenv</TerminalEnvironmentCode>";

  my $cardpres = "3";    # NotPresent
  if ( ( $industrycode =~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $cardpres = "2";     # Present
  }
  $bd[25] = "<CardPresentCode>$cardpres</CardPresentCode>";

  #if ($operation eq "return") {
  my $cvvpresence = "";
  if ( $cvvresp ne "" ) {
    $cvvpresence = "2";    # Provided
  } else {
    $cvvpresence = "1";    # NotProvided
  }
  $cvvpresence = "0";                                            # NotProvided
  $bd[26] = "<CVVPresenceCode>$cvvpresence</CVVPresenceCode>";

  #}

  #$bd[27] = "<CVVResponseType>$jobid</CVVResponseType>";

  my $cardinputcode = "4";    # ManualKeyed
  if (
    ( $magstripetrack =~ /^(1|2)/ )
    && ( ( $operation eq "postauth" )
      || ( ( $operation eq "return" ) && ( $opflag eq "new" ) )
      || ( ( $operation eq "void" ) && ( ( $reason eq "timeout" ) || ( $datainfo{'transflags'} =~ /timeout/ ) ) ) )
    ) {
    $cardinputcode = "2";     # MagstripeRead
  }

  #elsif ($magstripetrack =~ /^(0)/) {}
  elsif ( $industrycode =~ /(retail|restaurant)/ ) {
    $cardinputcode = "5";     # ManualKeyedMagstripeFailure
  }
  $bd[28] = "<CardInputCode>$cardinputcode</CardInputCode>";

  my $cardholderpres = "7";    # ECommerce
  if ( ( $transflags =~ /(recur|install|xincr|resub|delay|reauth|noshow|mit)/ ) && ( $transflags !~ /init/ ) ) {
    $cardholderpres = "6";     # StandingAuth
  } elsif ( ( $industrycode =~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $cardholderpres = "2";     # Present
  } elsif ( $transflags =~ /mail/ ) {
    $cardholderpres = "4";     # MailOrder
  } elsif ( $transflags =~ /moto/ ) {
    $cardholderpres = "5";     # PhoneOrder
  }
  $bd[29] = "<CardholderPresentCode>$cardholderpres</CardholderPresentCode>";

  my $eci      = substr( $auth_code, 161 + 1, 1 );
  my $deviceid = substr( $auth_code, 414,     4 );
  $deviceid =~ s/ //g;

  my $cavvresp = substr( $auth_code, 328, 1 );
  $cavvresp =~ s/ //g;

  my $motoecicode = "7";       # NonAuthenticatedSecureECommerceTransaction
  if ( ( $transflags =~ /recur/ ) && ( $transflags !~ /init/ ) ) {
    $motoecicode = "3";        # Recurring
  } elsif ( ( $transflags =~ /install/ ) && ( $transflags !~ /init/ ) ) {
    $motoecicode = "4";        # Installment
  } elsif ( $transflags =~ /moto/ ) {
    $motoecicode = "2";        # Single
  } elsif ( $transflags =~ /bill/ ) {
    $motoecicode = "2";        # Single
  } elsif ( $eci =~ /(5)/ ) {
    $motoecicode = "5";        # SecureElectronicCommerce
  } elsif ( $cavvresp ne "" ) {
    $motoecicode = "6";        # NonAuthenticatedSecureTransaction
  } elsif ( $industrycode =~ /(retail|restaurant)/ ) {
    $motoecicode = "1";        # NotUsed
  }
  $bd[30] = "<MotoECICode>$motoecicode</MotoECICode>";

  my $consentcode = "3";       # Internet
  if ( ( $industrycode =~ /(retail|restaurant)/ ) && ( $transflags !~ /moto/ ) ) {
    $consentcode = "1";        # FaceToFace
  } elsif ( $transflags =~ /moto/ ) {
    $consentcode = "2";        # Phone
  }
  $bd[31] = "<ConsentCode>$consentcode</ConsentCode>";

  #$bd[32] = "<TerminalEncryptionFormat>$jobid</TerminalEncryptionFormat>";
  #$bd[33] = "<TerminalSerialNumber>$jobid</TerminalSerialNumber>";

  my $deviceid = substr( $auth_code, 414, 4 );
  $deviceid =~ s/ //g;
  $deviceid = substr( "0" x 4 . $deviceid, -4, 4 );
  if ( $deviceid = "0000" ) {
    $deviceid = "0001";
  }
  $bd[34] = "<LaneNumber>$deviceid</LaneNumber>";
  $bd[35] = "</Terminal>";

  #$bd[30] = "<BIN>";
  #$bd[31] = "<BINTypeCode>$jobid</BINTypeCode>";
  #$bd[32] = "<BINTypeValue>$jobid</BINTypeValue>";
  #$bd[33] = "<BINDecorator>$jobid</BINDecorator>";
  #$bd[34] = "</BIN>";

  if ( $transid eq "" ) {
    $bd[40] = "<Card>";
    my $cardnum = substr( $cardnumber, 0, 19 );
    $bd[41] = "<CardNumber>$cardnum</CardNumber>";

    my $monthexp = substr( $exp, 0, 2 );
    my $yrexp    = substr( $exp, 3, 2 );
    $bd[42] = "<ExpirationMonth>$monthexp</ExpirationMonth>";
    $bd[43] = "<ExpirationYear>$yrexp</ExpirationYear>";

    #my $cardname = $card_name;
    #$cardname =~  s/[^(?:\P{L}\p{L}*)+0-9\.\']/ /g;
    #$bd[44] = "<CardholderName>$cardname</CardholderName>";

    #$bd[45] = "<Track1Data>$jobid</Track1Data>";
    #$bd[46] = "<Track2Data>$jobid</Track2Data>";
    #$bd[47] = "<Track3Data>$jobid</Track3Data>";

    #$bd[48] = "<MagneprintData>$jobid</MagneprintData>";
    #$bd[49] = "<PINBlock>$jobid</PINBlock>";

    #$bd[50] = "<AVSResponseCode>$avs_code</AVSResponseCode>";
    #$bd[51] = "<CVV>$cvvresp</CVV>";
    #$bd[52] = "<CVVResponseCode>$cvvresp</CVVResponseCode>";

    #$bd[53] = "<CAVV>$worldpayfis::datainfo{'cavv'}</CAVV>";
    $bd[54] = "<CAVVResponseCode>$cavvresp</CAVVResponseCode>";

    #$bd[55] = "<XID>$worldpayfis::datainfo{'xid'}</XID>";

    #$bd[56] = "<KeySerialNumber>$jobid</KeySerialNumber>";
    #$bd[57] = "<CardLogo>$jobid</CardLogo>";
    #$bd[58] = "<EncryptedTrack1Data>$jobid</EncryptedTrack1Data>";
    #$bd[59] = "<EncryptedTrack2Data>$jobid</EncryptedTrack2Data>";
    #$bd[60] = "<EncryptedCardData>$jobid</EncryptedCardData>";
    #$bd[61] = "<CardDataKeySerialNumber>$jobid</CardDataKeySerialNumber>";
    #$bd[62] = "<EncryptedFormat>$jobid</EncryptedFormat>";
    #$bd[63] = "<TruncatedCardNumber>$jobid</TruncatedCardNumber>";
    #$bd[64] = "<CardNumberMasked>$jobid</CardNumberMasked>";
    #$bd[65] = "<Cryptogram>$jobid</Cryptogram>";
    #$bd[66] = "<WalletType>$jobid</WalletType>";
    #$bd[67] = "<ElectronicCommerceIndicator>$worldpayfis::datainfo{'eci'}</ElectronicCommerceIndicator>";
    #$bd[68] = "<BIN>$jobid</BIN>";
    #$bd[69] = "<CardLevelResults>$jobid</CardLevelResults>";
    $bd[70] = "</Card>";
  }

  if ( ( $operation eq "return" ) && ( $origoperation !~ /auth/ ) && ( $transflags =~ /(checking|savings)/ ) ) {
    my $swipeind = "M";
    my ( $micr, $routenum, $acctnum ) = split( /,/, $securenetach::datainfo{'card-number'} );
    my $checknum = $securenetach::datainfo{'checknum'};

    my ( $micr, $routenum, $acctnum, $checknum ) = &micrdecode( $micr, $routenum, $acctnum, $checknum );

    #print "micr: $micr\n";
    #print "routenum: $routenum\n";
    #print "acctnum: $acctnum\n";
    #print "checknum: $checknum\n\n";

    if ( $micr ne "" ) {
      $securenetach::datainfo{'card-number'} = "$micr,$routenum,$acctnum";
    }
    if ( $micr =~ /[toaduTOADU]/ ) {
      $swipeind = "S";
    }

    $bd[80] = "<CheckAccountClass>";
    $bd[81] = "<AccountType>$jobid</AccountType>";
    $bd[82] = "<AccountNumber>$jobid</AccountNumber>";
    $bd[83] = "<RoutingNumber>$jobid</RoutingNumber>";
    $bd[84] = "</CheckAccountClass>";

    $bd[90] = "<DemandDepositAccountClass>";
    $bd[91] = "<DDAAccountType>$jobid</DDAAccountType>";
    $bd[92] = "<AccountNumber>$jobid</AccountNumber>";
    $bd[93] = "<RoutingNumber>$jobid</RoutingNumber>";
    $bd[94] = "<CheckNumber>$jobid</CheckNumber>";
    $bd[95] = "<CheckType>$jobid</CheckType>";
    $bd[96] = "<TruncatedAccountNumber>$jobid</TruncatedAccountNumber>";
    $bd[97] = "<TruncatedRoutingNumber>$jobid</TruncatedRoutingNumber>";
    $bd[98] = "</DemandDepositAccountClass>";
  }

  my $commflag = substr( $auth_code, 221, 1 );
  if ( $commflag eq "1" ) {
    $bd[120] = "<Address>";
    $card_name =~ s/[^a-zA-Z0-9 \.,]//g;
    $card_name =~ s/^ +//g;
    $card_name =~ s/ +$//g;
    $bd[121] = "<BillingName>$card_name</BillingName>";

    #$bd[122] = "<BillingEmail>$jobid</BillingEmail>";
    #$bd[123] = "<BillingPhone>$jobid</BillingPhone>";
    #$bd[124] = "<BillingAddress1>$worldpayfis::datainfo{'card-address'}</BillingAddress1>";
    #$bd[125] = "<BillingAddress2>$jobid</BillingAddress2>";
    #$bd[126] = "<BillingCity>$worldpayfis::datainfo{'card-city'}</BillingCity>";
    #$bd[127] = "<BillingState>$worldpayfis::datainfo{'card-state'}</BillingState>";
    #$bd[128] = "<BillingZipcode>$worldpayfis::datainfo{'card-zip'}</BillingZipcode>";
    #$bd[129] = "<ShippingName>$jobid</ShippingName>";
    #$bd[130] = "<ShippingEmail>$jobid</ShippingEmail>";
    #$bd[131] = "<ShippingPhone>$jobid</ShippingPhone>";
    #$bd[132] = "<ShippingAddress1>$worldpayfis::datainfo{'address'}</ShippingAddress1>";
    #$bd[133] = "<ShippingAddress2>$jobid</ShippingAddress2>";
    #$bd[134] = "<ShippingCity>$worldpayfis::datainfo{'city'}</ShippingCity>";
    #$bd[135] = "<ShippingState>$worldpayfis::datainfo{'state'}</ShippingState>";
    my $shipzip = substr( $auth_code, 92, 9 );
    $shipzip =~ s/ //g;
    $bd[136] = "<ShippingZipcode>$shipzip</ShippingZipcode>";

    #$bd[137] = "<AddressEditAllowed>$jobid</AddressEditAllowed>";
    $bd[138] = "</Address>";
  }

  #$bd[140] = "<Identification>";
  #$bd[141] = "<BirthDate>$jobid</BirthDate>";
  #$bd[142] = "<DriversLicenseNumber>$jobid</DriversLicenseNumber>";
  #$bd[143] = "<DriversLicenseState>$jobid</DriversLicenseState>";
  #$bd[144] = "<TaxIDNumber>$jobid</TaxIDNumber>";
  #$bd[145] = "</Identification>";

  #$bd[150] = "<Parameters>";
  #$bd[151] = "<TransactionDateTimeBegin>$jobid</TransactionDateTimeBegin>";
  #$bd[152] = "<TransactionDateTimeEnd>$jobid</TransactionDateTimeEnd>";
  #$bd[153] = "<TerminalID>$jobid</TerminalID>";
  #$bd[154] = "<ApplicationID>$jobid</ApplicationID>";
  #$bd[155] = "<ApprovalNumber>$jobid</ApprovalNumber>";
  #$bd[156] = "<ApprovedAmount>$jobid</ApprovedAmount>";
  #$bd[157] = "<ExpressTransactionDate>$jobid</ExpressTransactionDate>";
  #$bd[158] = "<ExpressTransactionTime>$jobid</ExpressTransactionTime>";
  #$bd[159] = "<HostBatchID>$jobid</HostBatchID>";
  #$bd[160] = "<HostItemID>$jobid</HostItemID>";
  #$bd[161] = "<HostReversalQueueID>$jobid</HostReversalQueueID>";
  #$bd[162] = "<OriginalAuthorizedAmount>$jobid</OriginalAuthorizedAmount>";
  #$bd[163] = "<ReferenceNumber>$jobid</ReferenceNumber>";
  #$bd[164] = "<ShiftID>$jobid</ShiftID>";
  #$bd[165] = "<SourceTransactionID>$jobid</SourceTransactionID>";
  #$bd[166] = "<TerminalType>$jobid</TerminalType>";
  #$bd[167] = "<TrackingID>$jobid</TrackingID>";
  #$bd[168] = "<TransactionAmount>$jobid</TransactionAmount>";
  #$bd[169] = "<TransactionSetupID>$jobid</TransactionSetupID>";
  #$bd[170] = "<TransactionStatus>$jobid</TransactionStatus>";
  #$bd[171] = "<TransactionType>$jobid</TransactionType>";
  #$bd[172] = "<XID>$jobid</XID>";
  #$bd[173] = "<ReverseOrder>$jobid</ReverseOrder>";
  #$bd[174] = "</Parameters>";

  #$bd[180] = "<PaymentAccount>";
  #$bd[181] = "<PaymentAccountID>$jobid</PaymentAccountID>";
  #$bd[182] = "<PaymentAccountType>$jobid</PaymentAccountType>";
  #$bd[183] = "<PaymentAccountReferenceNumber>$jobid</PaymentAccountReferenceNumber>";
  #$bd[184] = "<TransactionSetupID>$jobid</TransactionSetupID>";
  #$bd[185] = "<PASSUpdaterBatchStatus>$jobid</PASSUpdaterBatchStatus>";
  #$bd[186] = "<PASSUpdaterOption>$jobid</PASSUpdaterOption>";
  #$bd[187] = "</PaymentAccount>";

  #$bd[190] = "<PaymentAccountParameters>";
  #$bd[191] = "<PaymentAccountID>$jobid</PaymentAccountID>";
  #$bd[192] = "<PaymentAccountType>$jobid</PaymentAccountType>";
  #$bd[193] = "<PaymentAccountReferenceNumber>$jobid</PaymentAccountReferenceNumber>";
  #$bd[194] = "<PaymentBrand>$jobid</PaymentBrand>";
  #$bd[195] = "<ExpiratinMonthBegin>$jobid</ExpiratinMonthBegin>";
  #$bd[196] = "<ExpirationMonthEnd>$jobid</ExpirationMonthEnd>";
  #$bd[197] = "<ExpirationYearBegin>$jobid</ExpirationYearBegin>";
  #$bd[198] = "<ExpirationYearEnd>$jobid</ExpirationYearEnd>";
  #$bd[199] = "<TransactionSetupID>$jobid</TransactionSetupID>";
  #$bd[200] = "<PASSUpdaterDateTimeBegin>$jobid</PASSUpdaterDateTimeBegin>";
  #$bd[201] = "<PASSUpdaterDateTimeEnd>$jobid</PASSUpdaterDateTimeEnd>";
  #$bd[202] = "<PASSUpdaterBatchStatus>$jobid</PASSUpdaterBatchStatus>";
  #$bd[203] = "<PASSUpdaterOption>$jobid</PASSUpdaterOption>";
  #$bd[204] = "<PASSUpdaterStatus>$jobid</PASSUpdaterStatus>";
  #$bd[205] = "</PaymentAccountParameters>";

  #$bd[210] = "<Token>";
  #$bd[211] = "<TokenID>$jobid</TokenID>";
  #$bd[212] = "<TokenProvider>$jobid</TokenProvider>";
  #$bd[213] = "<TokenNewlyGenerated>$jobid</TokenNewlyGenerated>";
  #$bd[214] = "<VaultID>$jobid</VaultID>";
  #$bd[215] = "<TAProviderID>$jobid</TAProviderID>";
  #$bd[216] = "</Token>";

  $bd[220] = "<Transaction>";

  if ( $transid ne "" ) {
    $transid =~ s/ //g;
    $bd[221] = "<TransactionID>$transid</TransactionID>";
  }

  #$currency = substr($amount,0,3);
  #$currency =~ tr/a-z/A-Z/;
  #if ($currency eq "") {
  #  $currency = "USD";
  #}
  #my $exponent = $isotables::currencyUSD2{$currency};
  #$amt = sprintf("%d", (substr($amount,4) * (10 ** $exponent)) + .0001);

  #my $exponent = $isotables::currencyUSD2{$currency2};
  $amount = substr( $amount, 4 );
  $bd[222] = "<TransactionAmount>$amount</TransactionAmount>";

  if ( ( $operation =~ /(void|reauth|postauth)/ ) && ( ( $operation ne "postauth" ) || ( $origoperation ne "forceauth" ) ) ) {
    my $origamt = substr( $origamount, 4 );
    $bd[223] = "<OriginalAuthorizedAmount>$origamt</OriginalAuthorizedAmount>";
  }

  my $tax = substr( $auth_code, 49, 10 );    # 0.00
  $tax =~ s/ //g;
  if ( $tax > 0.00 ) {
    $bd[224] = "<SalesTaxAmount>$tax</SalesTaxAmount>";
  }

  print "bbbbbbbb $auth_code\n";
  my $gratuity = substr( $auth_code, 282, 8 );
  $gratuity =~ s/ //g;
  if ( $gratuity > 0.00 ) {
    $bd[225] = "<TipAmount>$gratuity</TipAmount>";
  }

  my $cashback = substr( $auth_code, 120, 7 );
  $cashback =~ s/ //g;
  if ( $cashback > 0.00 ) {
    $bd[226] = "<CashBackAmount>$cashback</CashBackAmount>";
  }

  if ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
    my $authcode = substr( $auth_code, 0, 6 );
    $authcode =~ s/ //g;
    $bd[227] = "<ApprovalNumber>$authcode</ApprovalNumber>";
  }

  #$bd[228] = "<ClerkNumber>$jobid</ClerkNumber>";
  #$bd[229] = "<ShiftID>$jobid</ShiftID>";

  $bd[230] = "<ReferenceNumber>$orderid</ReferenceNumber>";

  #my $reversaltype = "";
  #if ($transflags =~ /timeout/) {
  #  $reversaltype = "System";
  #}
  #elsif ($operation eq "reauth") {
  #  $reversaltype = "Partial";
  #}
  #elsif ($operation eq "void") {
  #  $reversaltype = "Full";
  #}
  #$bd[231] = "<ReversalType>$reversaltype</ReversalType>";

  my $marketcode = "3";    # ECommerce
  if ( $industrycode eq "retail" ) {
    $marketcode = "7";     # Retail
  } elsif ( $industrycode eq "restaurant" ) {
    $marketcode = "4";     # FoodRestaurant
  } elsif ( ( $transflags =~ /(recur|install)/ ) && ( $transflags !~ /init/ ) ) {
    $marketcode = "2";     # DirectMarketing
  } elsif ( $transflags =~ /moto/ ) {
    $marketcode = "2";     # DirectMarketing
  }
  $bd[232] = "<MarketCode>$marketcode</MarketCode>";

  #$bd[233] = "<AcquirerData>$jobid</AcquirerData>";
  my $billflag = "0";      # False
  if ( $transflags =~ /(bill|debt|recur|install)/ ) {
    $billflag = "1";       # True
  }
  $bd[234] = "<BillPaymentFlag>$billflag</BillPaymentFlag>";

  #$bd[235] = "<DuplicateCheckDisableFlag>1</DuplicateCheckDisableFlag>";		# True
  #$bd[236] = "<DuplicateOverrideFlag>$jobid</DuplicateOverrideFlag>";
  if ( $transflags =~ /override/ ) {
    $bd[235] = "<DuplicateOverrideFlag>1</DuplicateOverrideFlag>";
  } elsif ( $transflags !~ /dupchk/ ) {
    $bd[235] = "<DuplicateCheckDisableFlag>1</DuplicateCheckDisableFlag>";    # True
  }

  my $recurringflag = "0";                                                    # False
  if ( ( $transflags =~ /(recur|install)/ ) && ( $transflags !~ /init/ ) ) {
    $recurringflag = "1";                                                     # True
  }
  $bd[237] = "<RecurringFlag>$recurringflag</RecurringFlag>";

  $bd[238] = "<TicketNumber>$orderid</TicketNumber>";                         # user defined (50a)

  my $commflag = substr( $auth_code, 221, 1 );
  if ( $commflag eq "1" ) {
    $bd[239] = "<CommercialCardCustomerCode>$orderid</CommercialCardCustomerCode>";    # (25)
  }

  #$bd[240] = "<TransactionStatusCode>$jobid</TransactionStatusCode>";
  #$bd[241] = "<TransactionStatus>$jobid</TransactionStatus>";
  #$bd[242] = "<TransactionSetupID>$jobid</TransactionSetupID>";
  #$bd[243] = "<ApprovedAmount>$jobid</ApprovedAmount>";
  #$bd[244] = "<ConvenienceFeeAmount>$jobid</ConvenienceFeeAmount>";
  #$bd[245] = "<PartialApprovedFlag>$jobid</PartialApprovedFlag>";
  #$bd[246] = "<MerchantVerificationValue>$jobid</MerchantVerificationValue>";
  #$bd[247] = "<CommercialCardResponseCode>$jobid</CommercialCardResponseCode>";
  #$bd[248] = "<BalanceAmount>$jobid</BalanceAmount>";
  #$bd[249] = "<BalanceCurrencyCode>$jobid</BalanceCurrencyCode>";
  #$bd[250] = "<BillPayerAccountNumber>$jobid</BillPayerAccountNumber>";

  $bd[251] = "<DCCRequested>$jobid</DCCRequested>";
  $bd[252] = "<ConversionRate>$jobid</ConversionRate>";
  $bd[253] = "<ForeignCurrencyCode>$jobid</ForeignCurrencyCode>";
  $bd[254] = "<ForeignTransactionAmount>$jobid</ForeignTransactionAmount>";

  if ( $operation ne "postauth" ) {
    my $surcharge = substr( $auth_code, 418, 8 );
    $surcharge =~ s/ //g;
    if ( $surcharge ne "" ) {
      $bd[256] = "<SurchargeAmount>$surcharge</SurchargeAmount>";
    }
  }

  #if ($operation ne "postauth") {
  my $convfee = substr( $auth_code, 426, 8 );
  $convfee =~ s/ //g;
  if ( $convfee ne "" ) {
    $bd[257] = "<ConvenienceFeeAmount>$convfee</ConvenienceFeeAmount>";
  }

  #}

  #$bd[257] = "<AlternateMCC>$jobid</AlternateMCC>";
  #$bd[258] = "<MerchantSuppliedTransactionID>$jobid</MerchantSuppliedTransactionID>";
  #$bd[259] = "<DuplicateTransactionID>$jobid</DuplicateTransactionID>";
  #$bd[260] = "<DuplicateApprovalNumber>$jobid</DuplicateApprovalNumber>";
  #$bd[261] = "<DuplicateHostItemID>$jobid</DuplicateHostItemID>";
  #$bd[262] = "<PINlessPOSConversationIndicator>$jobid</PINlessPOSConversationIndicator>";
  #$bd[263] = "<NetworkLabel>$jobid</NetworkLabel>";
  #$bd[264] = "<NOCDate>$jobid</NOCDate>";
  #$bd[265] = "<DateProcessed>$jobid</DateProcessed>";
  #$bd[266] = "<FundedDate>$jobid</FundedDate>";
  #$bd[267] = "<ReturnDate>$jobid</ReturnDate>";

  my $marketdata = substr( $auth_code, 179, 38 );
  $marketdata =~ s/ +$//;
  if ( $marketdata ne "" ) {
    my $company = substr( $marketdata, 0, 25 );
    $company =~ s/ +$//;
    my $phone = substr( $marketdata, 25 );
    $phone =~ s/^ +//;
    $bd[268] = "<MerchantDescriptor>$company</MerchantDescriptor>";
    $bd[269] = "<MerchantDescriptorCity>$phone</MerchantDescriptorCity>";
    $bd[270] = "<MerchantDescriptorState>$state</MerchantDescriptorState>";
  }

  my $paymenttype = "";
  if ( $transflags =~ /recur/ ) {
    $paymenttype = "1";    # Recurring
  } elsif ( $transflags =~ /install/ ) {
    $paymenttype = "2";    # Installment
  } elsif ( $transflags =~ /(cit|init)/ ) {
    $paymenttype = "3";    # CardHolderInitiated
  } elsif ( $transflags =~ /(mit|incr|noshow|delay|resub|reauth)/ ) {
    $paymenttype = "4";    # CredentialOnFile
  }
  $bd[271] = "<PaymentType>$paymenttype</PaymentType>";

  my $submissiontype = "";
  if ( $transflags =~ /init/ ) {
    $submissiontype = "1";    # Initial
  } elsif ( $transflags =~ /resub/ ) {
    $submissiontype = "3";    # Resubmission
  } elsif ( $transflags =~ /reauth/ ) {
    $submissiontype = "4";    # ReAuthorization
  } elsif ( $transflags =~ /delay/ ) {
    $submissiontype = "5";    # DelayedCharges
  } elsif ( $transflags =~ /noshow/ ) {
    $submissiontype = "6";    # NoShow
  } elsif ( $transflags =~ /(recur|install|cit|mit)/ ) {
    $submissiontype = "2";    # Subsequent
  }
  $bd[272] = "<SubmissionType>$submissiontype</SubmissionType>";

  my $nettransid = "";

  #if ($operation =~ /(reauth|postauth|void)/) {
  #  $nettransid = substr($auth_code,6,20);
  #}
  if ( ( $transflags =~ /(recur|install|mit|cit|incr|resub|delay|reauth|noshow)/ ) && ( $transflags !~ /(notcof|init)/ ) ) {
    $nettransid = substr( $auth_code, 6, 20 );

    #$nettransid = substr($origauthcode,6,20);
    $nettransid =~ s/ //g;
  }
  $bd[273] = "<NetworkTransactionID>$nettransid</NetworkTransactionID>";

  my $logfilestr =
    "$orderid $operation  cardhpres: $cardholderpres termtype: $termtype  termenv: $termenv  marketcode: $marketcode recurflag: $recurringflag $transflags  $industrycode  $nettransid  $tcode\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/$devprod/worldpayfis", "scriptresults.txt", "append", "", $logfilestr );

  #$bd[274] = "<TypeOfGoods>$jobid</TypeOfGoods>";
  #$bd[275] = "<PAR>$jobid</PAR>";		# payment account reference token (35a)
  #$bd[276] = "<SystemTraceAuditNumber>$jobid</SystemTraceAuditNumber>";
  #$bd[277] = "<RetrievalReferenceNumber>$jobid</RetrievalReferenceNumber>";
  $bd[278] = "</Transaction>";

  #$bd[280] = "<TransactionSetup>";
  #$bd[281] = "<TransactionSetupID>$jobid</TransactionSetupID>";
  #$bd[282] = "<TransactionSetupMethod>$jobid</TransactionSetupMethod>";
  #$bd[283] = "<Device>$jobid</Device>";
  #$bd[284] = "<Embedded>$jobid</Embedded>";
  #$bd[285] = "<CVVRequired>$jobid</CVVRequired>";
  #$bd[286] = "<AutoReturn>$jobid</AutoReturn>";
  #$bd[287] = "<CompanyName>$jobid</CompanyName>";
  #$bd[288] = "<LogoURL>$jobid</LogoURL>";
  #$bd[289] = "<Tagline>$jobid</Tagline>";
  #$bd[290] = "<WelcomeMessage>$jobid</WelcomeMessage>";
  #$bd[291] = "<ReturnURL>$jobid</ReturnURL>";
  #$bd[292] = "<ReturnURLTitle>$jobid</ReturnURLTitle>";
  #$bd[293] = "<OrderDetails>$jobid</OrderDetails>";
  #$bd[294] = "<ProcessTransactionTitle>$jobid</ProcessTransactionTitle>";
  #$bd[295] = "<ValidationCode>$jobid</ValidationCode>";
  #$bd[296] = "<DeviceInputCode>$jobid</DeviceInputCode>";
  #$bd[297] = "<CustomCss>$jobid</CustomCss>";
  #$bd[298] = "</TransactionSetup>";

  if ( (0) && ( $worldpayfis::datainfo{'healthamt'} ne "" ) && ( $worldpayfis::datainfo{'transitamt'} ne "" ) ) {

    my @amtarray = ();
    if ( $worldpayfis::datainfo{'healthamt'} ne "" ) {
      push( @amtarray, "Healthcare", $worldpayfis::datainfo{'healthamt'} );
    }
    if ( $worldpayfis::datainfo{'clinicalamt'} ne "" ) {
      push( @amtarray, "Clinic", $worldpayfis::datainfo{'clinicalamt'} );
    }
    if ( $worldpayfis::datainfo{'copayamt'} ne "" ) {
      push( @amtarray, "Copayment", $worldpayfis::datainfo{'copayamt'} );
    }
    if ( $worldpayfis::datainfo{'dentalamt'} ne "" ) {
      push( @amtarray, "Dental", $worldpayfis::datainfo{'dentalamt'} );
    }
    if ( $worldpayfis::datainfo{'rxamt'} ne "" ) {
      push( @amtarray, "Prescription", $worldpayfis::datainfo{'rxamt'} );
    }
    if ( $worldpayfis::datainfo{'visionamt'} ne "" ) {
      push( @amtarray, "Vision", $worldpayfis::datainfo{'visionamt'} );
    }
    if ( $worldpayfis::datainfo{'transitamt'} ne "" ) {
      push( @amtarray, "Transit", $worldpayfis::datainfo{'transitamt'} );
    }
    if ( $worldpayfis::datainfo{'cashback'} ne "" ) {
      push( @amtarray, "CashOver", $worldpayfis::datainfo{'cashback'} );
    }

    $bd[300] = "<Healthcare>";

    if ( $amtarray[0] ne "" ) {
      my $amtsign = "+";
      if ( $amtarray[1] =~ /\-/ ) {
        $amtsign = "-";
      }
      my $amt = $amtarray[1];
      $amt =~ s/\-//;
      $bd[301] = "<HealthcareFirstAccountType>NotSpecified</HealthcareFirstAccountType>";
      $bd[302] = "<HealthcareFirstAmountType>$amtarray[0]</HealthcareFirstAmountType>";

      #$bd[303] = "<HealthcareFirstCurrencyCode>$worldpayfis::currency</HealthcareFirstCurrencyCode>";
      $bd[304] = "<HealthcareFirstAmountSign>$amtsign</HealthcareFirstAmountSign>";
      $bd[305] = "<HealthcareFirstAmount>$amt</HealthcareFirstAmount>";
    }

    if ( $amtarray[2] ne "" ) {
      my $amtsign = "+";
      if ( $amtarray[3] =~ /\-/ ) {
        $amtsign = "-";
      }
      my $amt = $amtarray[3];
      $amt =~ s/\-//;
      $bd[306] = "<HealthcareSecondAccountType>$NotSpecified</HealthcareSecondAccountType>";
      $bd[307] = "<HealthcareSecondAmountType>$amtarray[2]</HealthcareSecondAmountType>";

      #$bd[308] = "<HealthcareSecondCurrencyCode>$worldpayfis::currency</HealthcareSecondCurrencyCode>";
      $bd[309] = "<HealthcareSecondAmountSign>$amtsign</HealthcareSecondAmountSign>";
      $bd[310] = "<HealthcareSecondAmount>$amt</HealthcareSecondAmount>";
    }

    if ( $amtarray[4] ne "" ) {
      my $amtsign = "+";
      if ( $amtarray[5] =~ /\-/ ) {
        $amtsign = "-";
      }
      my $amt = $amtarray[5];
      $amt =~ s/\-//;
      $bd[311] = "<HealthcareThirdAccountType>NotSpecified</HealthcareThirdAccountType>";
      $bd[312] = "<HealthcareThirdAmountType>$amtarray[4]</HealthcareThirdAmountType>";

      #$bd[313] = "<HealthcareThirdCurrencyCode>$worldpayfis::currency</HealthcareThirdCurrencyCode>";
      $bd[314] = "<HealthcareThirdAmountSign>$amtsign</HealthcareThirdAmountSign>";
      $bd[315] = "<HealthcareThirdAmount>$amt</HealthcareThirdAmount>";
    }

    if ( $amtarray[6] ne "" ) {
      my $amtsign = "+";
      if ( $amtarray[7] =~ /\-/ ) {
        $amtsign = "-";
      }
      my $amt = $amtarray[7];
      $amt =~ s/\-//;
      $bd[316] = "<HealthcareFourthAccountType>NotSpecified</HealthcareFourthAccountType>";
      $bd[317] = "<HealthcareFourthAmountType>$amtarray[6]</HealthcareFourthAmountType>";

      #$bd[318] = "<HealthcareFourthCurrencyCode>$worldpayfis::currency</HealthcareFourthCurrencyCode>";
      $bd[319] = "<HealthcareFourthAmountSign>$amtsign</HealthcareFourthAmountSign>";
      $bd[320] = "<HealthcareFourthAmount>$amt</HealthcareFourthAmount>";
    }

    $bd[321] = "</Healthcare>";
  }

  $bd[330] = "</$tcode>";

  my $message = "";
  my $indent  = 0;
  foreach $var (@bd) {
    if ( $var eq "" ) {
      next;
    }
    if ( $var =~ /^<\/.*>/ ) {
      $indent--;
    }
    if ( $var !~ /></ ) {
      $message = $message . "\t" x $indent . $var . "\n";
    }
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
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );
  ($message2) = unpack "H*", $printmessage;
  my $printstr = "$message2\n\n";
  &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );

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

  if ( ( $operation ne "return" ) && ( $chkauthcode eq "" ) ) {

    my $printstr = "dddd $username $orderid $operation $chkauthcode $auth_code $refnumber\n";
    &procutils::filewrite( "$username", "worldpayfis", "/home/pay1/batchfiles/devlogs/worldpayfis", "miscdebug.txt", "append", "misc", $printstr );

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

  #if ($cardnumber eq "4111111111111111") {
  #  &errormsg($username,$orderid,$operation,'test card number');
  #  return 1;
  #}

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

