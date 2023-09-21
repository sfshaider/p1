#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use smpsutils;
use rsautils;
use isotables;

$devprod = "logs";

# send details (0220 message)
# send header (processing code 920000)
# if response is not 00
# send details (0320 message)
# send trailer (processing code 960000)

my $group = $ARGV[0];
if ( $group eq "" ) {
  $group = "0";
}
my $printstr = "group: $group\n";
&procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );

if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'rbc/genfiles.pl $group'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: rbc - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

$hoststr = "processor-host";

my $checkuser = &procutils::fileread( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc", "genfiles$group.txt" );
chop $checkuser;

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>='$checkuser'";
}

#$checkstring = "and t.username='aaaa'";
#$checkstring = "and t.username in ('aaaa','aaaa')";

%errcode = (
  '0',  'Approved',              '2',  'ReferCardIssuer',  '3',  'InvalidMerchant',    '4',  'DoNotHonor',            '5',  'UnableToProcess',      '6',  'InvalidTransactionTerm',
  '8',  'IssuerTimeout',         '9',  'NoOriginal',       '10', 'UnableToReverse',    '12', 'InvalidTransaction',    '13', 'InvalidAmount',        '14', 'InvalidCard',
  '17', 'InvalidCaptureDate',    '18', 'NoMatchTotals',    '19', 'SystemErrorReenter', '20', 'NoFromAccount',         '21', 'NoToAccount',          '22', 'NoCheckingAccount',
  '23', 'NoSavingAccount',       '25', 'NoRecordOnFile',   '30', 'MessageFormatError', '39', 'TransactionNotAllowed', '41', 'HotCard',              '42', 'SpecialPickup',
  '43', 'HotCardPickUp',         '44', 'PickUpCard',       '45', 'TxnBackOff',         '51', 'NoFunds',               '54', 'ExpiredCard',          '55', 'IncorrectPIN',
  '57', 'TxnNotPermittedOnCard', '61', 'ExceedsLimit',     '62', 'RestrictedCard',     '63', 'MACKeyError',           '65', 'ExceedsFreqLimit',     '67', 'RetainCard',
  '68', 'LateResponse',          '75', 'ExceedsPINRetry',  '76', 'InvalidAccount',     '77', 'NoSharingArrangement',  '78', 'FunctionNotAvailable', '79', 'KeyValidationError',
  '82', 'InvalidCVV',            '84', 'InvalidLifeCycle', '87', 'PINKeyError',        '88', 'MACSyncError',          '89', 'SecurityViolation',    '91', 'SwitchNotAvailable',
  '92', 'InvalidIssuer',         '93', 'InvalidAcquirer',  '94', 'InvalidOriginator',  '96', 'SystemError',           '97', 'NoFundsTransfer',      '98', 'DuplicateReversal',
  '99', 'DuplicateTransaction'
);

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 60 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 180 ) );
$sixmonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 8 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
( $d1, $today, $time ) = &miscutils::genorderid();

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
my $filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
my $fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/rbc/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/rbc/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/rbc/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/rbc/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/rbc/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/rbc/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/rbc/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/rbc/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/rbc/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/rbc/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: rbc - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/rbc/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$response = "";    # don't delete

my $printstr = "aaaa\n";
&procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );

#$dbh = &miscutils::dbhconnect("pnpmisc");

# xxxx
# and username='pnprbc'
#select t.username,count(t.username)
#from trans_log t,customers c
#where t.trans_date>='$onemonthsago'
#and t.finalstatus = 'pending'
#and (t.accttype is NULL or t.accttype='credit')
#and t.username<>'vmicardserv'
#and c.username=t.username
#and c.processor='rbc'
#and c.status='live'
#group by t.username
my $dbquerystr = <<"dbEOM";
        select o.username,count(o.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        and t.trans_date<=?
        $checkstring
        and t.finalstatus in ('pending')
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastoptime>=?
        and (o.lastopstatus='locked' or o.lastopstatus='pending')
        and o.processor='rbc'
        group by o.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );
  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

my $printstr = "cccc\n";
&procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );

foreach $username ( sort @userarray ) {
  if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "stopgenfiles\n";
    &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc/$fileyear", "$username$time.txt", "append", "", $logfilestr );

    unlink "/home/pay1/batchfiles/$devprod/rbc/batchfile.txt";
    last;
  }

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc", "genfiles$group.txt", "write", "", $checkinstr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  umask 0077;

  my $printstr = "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );

  if ( $usercountarray{$username} > 2000 ) {
    $batchcntuser = 900;
  } elsif ( $usercountarray{$username} > 1000 ) {
    $batchcntuser = 500;
  } elsif ( $usercountarray{$username} > 600 ) {
    $batchcntuser = 200;
  } elsif ( $usercountarray{$username} > 300 ) {
    $batchcntuser = 100;
  } else {
    $batchcntuser = 100;
  }

  if ( $username =~ /^(icommerceg|icgcrossco)$/ ) {
    $batchcntuser = 1500;
  }

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,currency,switchtime
        from customers
        where username=?
        and processor='rbc'
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $status, $mcurrency, $switchtime ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
        select server,batchtime
        from rbc
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $server, $batchgroup ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $status ne "live" ) {
    next;
  }

  if ( ( $group eq "9" ) && ( $batchgroup ne "9" ) ) {
    next;
  } elsif ( ( $group eq "8" ) && ( $batchgroup ne "8" ) ) {
    next;
  } elsif ( ( $group eq "7" ) && ( $batchgroup ne "7" ) ) {
    next;
  } elsif ( ( $group eq "6" ) && ( $batchgroup ne "6" ) ) {
    next;
  } elsif ( ( $group eq "5" ) && ( $batchgroup ne "5" ) ) {
    next;
  } elsif ( ( $group eq "4" ) && ( $batchgroup ne "4" ) ) {
    next;
  } elsif ( ( $group eq "3" ) && ( $batchgroup ne "3" ) ) {
    next;
  } elsif ( ( $group eq "2" ) && ( $batchgroup ne "2" ) ) {
    next;
  } elsif ( ( $group eq "1" ) && ( $batchgroup ne "1" ) ) {
    next;
  } elsif ( ( $group eq "0" ) && ( $batchgroup ne "" ) ) {
    next;
  } elsif ( $group !~ /^(0|1|2|3|4|5|6|7|8|9)$/ ) {
    next;
  }

  $logfilestr = "";
  $logfilestr .= "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  # xxxx secondary

  my $printstr = "bbbb\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );

  $batch_flag = 1;
  @details    = ();

  my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,refnumber,lastopstatus,
                 cvvresp,transflags,card_zip,card_addr,
                 authtime,authstatus,forceauthtime,forceauthstatus
          from operation_log
          where trans_date>=?
          and trans_date<=?  
          and lastoptime>=?
          and username=?
          and lastop in ('postauth','return')
          and lastopstatus in ('pending')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
          order by lastopstatus,orderid
dbEOM
  my @dbvalues = ( "$starttransdate", "$today", "$onemonthsagotime", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $mintrans_date = $today;

  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 20 ) {
    ( $orderid,   $operation,   $trans_date, $trans_time, $enccardnumber, $enclength, $exp,      $amount,     $auth_code,     $avs_code,
      $refnumber, $finalstatus, $cvvresp,    $transflags, $card_zip,      $card_addr, $authtime, $authstatus, $forceauthtime, $forceauthstatus
    )
      = @sthtransvalarray[ $vali .. $vali + 19 ];

    if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {

      umask 0077;
      $logfilestr = "";
      $logfilestr .= "stopgenfiles\n";
      &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc/$fileyear", "$username$time.txt", "append", "", $logfilestr );

      unlink "/home/pay1/batchfiles/$devprod/rbc/batchfile.txt";
      last;
    }
    my $printstr = "dddd\n";
    &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );

    if ( $operation eq "void" ) {
      $orderidold = $orderid;
      next;
    }
    if ( ( $orderid eq $orderidold ) || ( $finalstatus !~ /^(pending)$/ ) ) {
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

    if ( ( $trans_date < $mintrans_date ) && ( $trans_date >= '19990101' ) ) {
      $mintrans_date = $trans_date;
    }

    #select amount
    #from trans_log
    #where orderid='$orderid'
    #and trans_date>='$twomonthsago'
    #and operation='auth'
    #and username='$username'
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

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "rbc", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $card_type = &smpsutils::checkcard($cardnumber);

    $errflag = &errorchecking();
    if ( $errflag == 1 ) {
      next;
    }

    umask 0077;
    $tmp = substr( $cardnumber, 0, 2 );
    $logfilestr = "";
    $logfilestr .= "$orderid $operation $transflags $amount $tmp\n";
    &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc/$fileyear", "$username$time.txt", "append", "", $logfilestr );

    if ( $batchcnt > 1 ) {
      @orderidarray = ();
      $batch_flag   = 1;
      $batchcnt     = 1;
      $datasentflag = 0;
      @details      = ();
      if ( $batcherrorflag == 1 ) {
        last;    # if batch error move on to next username
      }
    }

    if ( $batch_flag == 1 ) {

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
              from rbc
              where username=?
dbEOM
      my @dbvalues = ("$username");
      ( $chkuser, $batchnum ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      if ( $chkuser eq "" ) {

        $batchnum = $batchnum + 1;

        if ( $batchnum >= 998 ) {
          $batchnum = 1;
        }

        $batchnum = substr( "0" x 6 . $batchnum, -6, 6 );    # batch number (6n)
        $batchid  = substr( "0" x 3 . $batchnum, -3, 3 );    # batch number (6n)

        my $dbquerystr = <<"dbEOM";
              insert into rbc
              (username,batchnum)
              values (?,?)
dbEOM
        my %inserthash = ( "username", "$username", "batchnum", "$batchnum" );
        &procutils::dbinsert( $username, $orderid, "pnpmisc", "rbc", %inserthash );

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
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time$batchid", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    &batchdetail();
    if ( $socketerrorflag == 1 ) {
      last;    # if socket error stop altogether
    }

    if ( $batchcnt >= $batchcntuser ) {
      @orderidarray = ();
      $batch_flag   = 1;
      $batchcnt     = 1;
      $datasentflag = 0;
      @details      = ();
      if ( $batcherrorflag == 1 ) {
        last;    # if batch error move on to next username
      }
    }

    $finalstatusold = $finalstatus;

  }

  if ( ( ( $batchcnt > 1 ) || ( $datasentflag == 1 ) ) && ( $socketerrorflag == 0 ) ) {
    @orderidarray = ();
    $batch_flag   = 1;
    $batchcnt     = 1;
    $datasentflag = 0;
    @details      = ();
  }

  if ( $errorstr ne "" ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: barbara\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: rbc - genfiles.pl FAILURE\n";
    print MAILERR "\n";
    print MAILERR "errorstr: $errorstr\n";
    close MAILERR;

    $errorstr = "";
  }

}

#$sth->finish;

#$dbh->disconnect;

unlink "/home/pay1/batchfiles/$devprod/rbc/batchfile.txt";

if ( ( !-e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) && ( $socketerrorflag == 0 ) ) {
  umask 0033;
  $checkinstr = "";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc", "genfiles$group.txt", "write", "", $checkinstr );
}

exit;

sub mysleep {
  for ( $myi = 0 ; $myi <= 60 ; $myi++ ) {
    umask 0033;
    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc", "baccesstime.txt", "write", "", $outfilestr );

    select undef, undef, undef, 60.00;
  }
}

sub senderrmail {
  my ($message) = @_;

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: rbc - batch problem\n";
  print MAILERR "\n";
  print MAILERR "Username: $username\n";
  print MAILERR "\nLocked transactions found in trans_log and batchid's did not match.\n";
  print MAILERR " Or batch out of balance.\n\n";
  print MAILERR "$message.\n\n";
  print MAILERR "chkbatchid: $chkbatchid    batchid: $batchid\n";
  close MAILERR;

}

sub batchdetail {
  $transamt = substr( $amount, 4 );
  $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );
  $transamt = substr( "00000000" . $transamt, -8, 8 );

  $origoperation = "";
  if ( $operation eq "postauth" ) {

    #$sthdate = $dbh2->prepare(qq{
    #      select authtime,authstatus,forceauthtime,forceauthstatus
    #      from operation_log
    #      where orderid='$orderid'
    #      and username='$username'
    #      and lastoptime>='$onemonthsagotime'
    #      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
    #$sthdate->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
    #($authtime,$authstatus,$forceauthtime,$forceauthstatus) = $sthdate->fetchrow;
    #$sthdate->finish;

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
      &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc/$fileyear", "$username$time.txt", "append", "", $logfilestr );

      $socketerrorflag = 1;
      $dberrorflag     = 1;
      return;
    }
  }

  $datasentflag = 1;

  #@orderidarray = (@orderidarray,$orderid);
  $orderidarray[ ++$#orderidarray ] = $orderid;

  @bd = ();

  $len = length($cardnumber);
  if ( $len % 2 == 1 ) {
    $cardnumber = $cardnumber . "F";
    $len        = $len + 1;
  }
  $len = substr( "00" . $len, -2, 2 );
  $bd[2] = pack "H2H$len", $len, $cardnumber;    # primary acct number (19a) LLVAR 2
  $xscardnumorig = $bd[2];
  $xscardnum     = $bd[2];
  $xscardnum =~ s/./x/g;

  if ( $operation eq "return" ) {
    $bd[3] = pack "H6", '203000';                # processing code (6a) 3
  } else {
    $bd[3] = pack "H6", '003000';                # processing code (6a) 3
  }

  ( $currency, $transamount ) = split( / /, $amount );
  $transamount = sprintf( "%d", ( $transamount * 100 ) + .0001 );
  $transamount = substr( "0" x 12 . $transamount, -12, 12 );
  $bd[4] = pack "H12", $transamount;             # transaction amount (12n) 4

  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
  $lyear = substr( $lyear, -2, 2 );
  my $ltrandate = sprintf( "%02d%02d%02d", $lyear, $lmonth + 1, $lday );
  my $ltrantime = sprintf( "%02d%02d%02d", $lhour, $lmin,       $lsec );

  #$bd[7] = $ltrandate . $ltrantime;                   # transmission date/time (10n) 7

  #$seqnum++;
  #$seqnum = substr("0" x 6 . $seqnum,-6,6);
  #$bd[11] = pack "H6",$seqnum;                                        # system trace number (6n) 11
  if ( $finalstatus eq "locked" ) {
    $tracenum = substr( $auth_code, 6, 6 );
    $tracenum =~ s/ //g;
    $tracenum = substr( "0" x 6 . $tracenum, -6, 6 );
  } else {

    #$tracenum = "000000";
    #$tracenum = &rbc::gettransid("$username");
    $tracenum = &smpsutils::gettransid( "$username", "rbc", $orderid );
    $tracenum = substr( "0" x 6 . $tracenum, -6, 6 );
    if ( $tracenum eq "000000" ) {

      #$tracenum = &rbc::gettransid("$username");
      $tracenum = &smpsutils::gettransid( "$username", "rbc", $orderid );
      $tracenum = substr( "0" x 6 . $tracenum, -6, 6 );
    }
  }
  $bd[11] = pack "H6", $tracenum;    # system trace number (6n) 11

  $datetime = substr( $auth_code, 26, 10 );
  $datetime =~ s/ //g;
  my $printstr = "datetime: $datetime\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );
  if ( $datetime eq "" ) {
    $datetime = substr( $ltrandate, 2, 4 ) . $ltrantime;
    my $printstr = "datetime2: $datetime\n";
    &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );
  }
  my $printstr = "datetime: $datetime\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );
  $bd[12] = pack "H6", substr( $datetime, 4, 6 );    # time hhmmss (6n) 12
  $bd[13] = pack "H4", substr( $datetime, 0, 4 );    # date MMDD (4n) 13

  $expdate = substr( $exp, 3, 2 ) . substr( $exp, 0, 2 );
  $expdate = substr( "0000" . $expdate, -4, 4 );
  $bd[14] = pack "H4", $expdate;                     # expiration date YYMM (4n) 14

  $magstripetrack = substr( $auth_code, 38, 1 );
  my $printstr = "magstripetrack: $magstripetrack\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );
  if ( $magstripetrack eq "2" ) {
    $bd[22] = pack "H4", '0022';                     # pos entry mode (3a) 22
  } else {
    $bd[22] = pack "H4", '0012';                     # pos entry mode (3a) 22
  }

  $bd[24] = pack "H4", '0001';                       # network internation identifier NII (3n) 24

  $poscond = substr( $auth_code, 36, 2 );
  $poscond =~ s/ //g;
  if ( $poscond eq "" ) {
    if ( ( $industrycode eq "retail" ) && ( $transflags !~ /moto/ ) ) {
      $poscond = "00";                               # retail
    } else {
      $poscond = "08";                               # moto
    }
  }
  $poscond = substr( $poscond . " " x 2, 0, 2 );
  $bd[25] = pack "H2", $poscond;                     # pos condition code (2a) 25

  #$len = length($bankid);
  #$len = substr("00" . $len,-2,2);
  #$bd[32] = $len . $bankid;                   # acquiring institution id -  bank id(12n) LLVAR 32

  if ( ( $origoperation ne "forceauth" ) && ( $operation eq "postauth" ) ) {
    $refnum = substr( "0" x 12 . $refnumber, -12, 12 );
    $bd[37] = $refnum;    # reference number (12n) 37
  } else {
    ($refnum) = &miscutils::genorderid();
    $refnum = substr( $refnum, -12, 12 );
    $bd[37] = $refnum;    # reference number (12n) 37
  }
  $bd[37] = $refnum;      # retrieval reference number (12a) 37

  if ( $operation ne "return" ) {
    $authcode = substr( $auth_code,          0, 6 );
    $authcode = substr( $authcode . " " x 6, 0, 6 );
    $bd[38] = $authcode;    # authorization number (6n) 38
  }

  #$bd[39] = '00';					# response code (2n) 39

  #my $tid = substr($terminal_id . " " x 8,0,8);
  my $tid = substr( "0" x 8 . $terminal_id, -8, 8 );
  $bd[41] = $tid;    # terminal id (8a) 41

  $mid = substr( $merchant_id . " " x 15, 0, 15 );

  #$mid = substr("0" x 15 . $merchant_id,-15,15);
  #$mid = &ascii2ebcdic($mid);
  $bd[42] = $mid;    # card acceptor id code - terminal/merchant id (15a) 42

  if ( $operation eq "return" ) {
    $origmtype = "0220";
  } elsif ( $origoperation eq "forceauth" ) {
    $origmtype = "0220";
  } else {
    $origmtype = "0100";
  }
  $origtracenum = substr( $auth_code,              6,  6 );
  $origtracenum = substr( $origtracenum . "0" x 6, 0,  6 );
  $origrefnum   = substr( $auth_code,              12, 12 );
  $origrefnum   = substr( $origrefnum . "0" x 12,  0,  12 );

  $data = $origmtype . $origtracenum . $origrefnum;

  #my $len = length($data);
  #$len = substr("0000" . $len,-4,4);
  #$bd[60] = pack "H4A*",$len,$data;                  # additional data (100n) LLLVAR 60

  my ( $bitmap1, $bitmap2 ) = &generatebitmap(@bd);
  $bitmap1 = pack "H16", $bitmap1;
  if ( $bitmap2 ne "" ) {
    $bitmap2 = pack "H16", $bitmap2;
  }

  $message = pack "H4", '0220';                # message id (4n)
  $message = $message . $bitmap1 . $bitmap2;

  my $tmpmessage = "";                         # used for debugging only
  foreach $var (@bd) {
    $message    = $message . $var;
    $tmpmessage = "$tmpmessage $var";
  }

  $len = length($message);
  $len = pack "n", $len;

  $message = $len . $message;

  &decodebitmap($message);

  $response = &sendmessage($message);

  &decodebitmap($response);

  $msgcode  = substr( $response, 26, 4 );
  $respcode = $msgvalues[39];
  $tracenum = $msgvalues[11];

  if ( ( $msgvalues[39] ne "00" ) && ( $finalstatus ne "locked" ) ) {
    my $printstr = "error in detail: $msgvalues[39]\n";
    my $printstr = "    $msgvalues[48]\n";
    my $printstr = "    $msgvalues[60]\n";
    my $printstr = "    $msgvalues[62]\n";
    my $printstr = "    msg: $msgcode    seqnum: $msgvalues[11]   orderid: $batchoidarray{$msgvalues[11]}\n";
    &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "    msg: $msgcode    seqnum: $msgvalues[11]   orderid: $batchoidarray{$msgvalues[11]}\n";
    &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc/$fileyear", "$username$time.txt", "append", "", $logfilestr );

    if ( ( $msgcode eq "1330" ) && ( $batchoidarray{ $msgvalues[11] } ne "" ) ) {
      $errorrecord = $batchoidarray{ $msgvalues[11] };
      my $printstr = "update databases $errorrecord\n";
      &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );
    }
  }

  if ( $respcode eq "00" ) {
    $transamt = substr( $amount, 4 );
    $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );
    $transamt = substr( "00000000" . $transamt, -8, 8 );

    if ( ( ( $origoperation eq "forceauth" ) && ( $operation eq "postauth" ) ) || ( $operation eq "return" ) ) {
      $tracenum  = substr( "0" x 6 . $tracenum,   -6, 6 );
      $auth_code = substr( $auth_code . " " x 12, 0,  12 );
      $auth_code = substr( $auth_code, 0, 6 ) . $tracenum . substr( $auth_code, 12 );
    }

    my ( $d1, $d2, $ptime ) = &miscutils::genorderid();
    my $dbquerystr = <<"dbEOM";
          update trans_log set auth_code=?,finalstatus='success',trans_time=?
          where orderid=?
          and username=?
          and trans_date>=?
          and result=?
          and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$auth_code", "$ptime", "$orderid", "$username", "$onemonthsago", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set auth_code=?,$operationstatus='success',lastopstatus='success',$operationtime=?,lastoptime=?
            where orderid=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$auth_code", "$ptime", "$ptime", "$orderid", "$username", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  } elsif ( ( $respcode ne "" ) && ( $respcode ne "00" ) ) {
    my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='problem',descr=?
          where orderid=?
          and username=?
          and trans_date>=?
          and result=?
          and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$respcode: $errcode{$respcode}", "$orderid", "$username", "$onemonthsago", "$time$batchid" );
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
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$respcode: $errcode{$respcode}", "$orderid", "$username", "$time$batchid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch detail: $respcode $errcode{$respcode}\n";
    &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc/$fileyear", "$username$time.txt", "append", "", $logfilestr );
    $errorstr .= "$username $logfilestr";
  } else {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "Error in batch detail: No response from socket\n";
    &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc/$fileyear", "$username$time.txt", "append", "", $logfilestr );

    $socketerrorflag = 1;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: rbc - genfiles.pl FAILURE\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "orderid: $orderid\n";
    print MAILERR "filename: $username$time.txt\n";
    print MAILERR "No response from socket.\n\n";
    close MAILERR;
  }
}

sub sendmessage {
  my ($message) = @_;

  my $host = "pos.rbccaribbean.com";

  #my $host = "142.245.104.40";
  my $port = "11000";
  if ( $username eq "testrbc" ) {
    $host = "pos.sterbccaribbean.com";
    $port = "10000";
  }

  $checkmessage = $message;
  $messagestr   = $message;

  if ( $message !~ /^..\x08/ ) {
    &decodebitmap("$message");
    $messagestr = $message;
    $cardnum    = "";
    $xs         = "";
    if ( $msgvalues[2] ne "" ) {
      $cardnum    = $msgvalues[2];
      $cardnumidx = $msgvaluesidx[2];
      $cardnum =~ s/[^0-9]//g;
      $cardnumlen = length($cardnum);
      $xs = "x" x ( $cardnumlen / 2 );
      if ( $cardnumidx > 0 ) {
        $messagestr = substr( $message, 0, $cardnumidx ) . $xs . substr( $message, $cardnumidx + ( $cardnumlen / 2 ) );
      }
    }

    if ( $msgvalues[48] ne "" ) {    # cvv data
      $datalen = length( $msgvalues[48] );
      $dataidx = $msgvaluesidx[48];
      my $temp = $msgvalues[48];
      for ( my $newidx = 1 ; $newidx < $datalen ; ) {
        my $tag     = substr( $temp, $newidx + 0, 2 );
        my $taglen  = substr( $temp, $newidx + 2, 2 );
        my $tagdata = substr( $temp, $newidx + 4, $taglen );
        if ( $tag eq "92" ) {
          $cvv = $tagdata;
          if ( $taglen == 3 ) {
            $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 4 ) . 'xxx' . substr( $messagestr, $dataidx + $newidx + 4 + 3 );
          } elsif ( $taglen == 4 ) {
            $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 4 ) . 'xxxx' . substr( $messagestr, $dataidx + $newidx + 4 + 4 );
          }
        }
        $newidx = $newidx + 4 + $taglen;
      }
    }

    if ( $msgvalues[126] ne "" ) {    # cvv data
      $cvvdata    = $msgvalues[126];
      $cvvdataidx = $msgvaluesidx[126];
      $cvv        = substr( $cvvdata, 2, 4 );
      if ( $cvvdataidx > 0 ) {
        if ( $cvv =~ / [0-9]{3}/ ) {
          $messagestr = substr( $messagestr, 0, $cvvdataidx + 2 ) . ' xxx' . substr( $messagestr, $cvvdataidx + 2 + 4 );
        } elsif ( $cvv =~ /[0-9]{4}/ ) {
          $messagestr = substr( $messagestr, 0, $cvvdataidx + 2 ) . 'xxxx' . substr( $messagestr, $cvvdataidx + 2 + 4 );
        }
      }
    }
  }

  $dest_ip = gethostbyname($host);

  if ( $dest_ip eq "" ) {
    &miscutils::mysleep(20.0);
    $dest_ip = gethostbyname($host);
  }

  my $dest_ipaddress = Net::SSLeay::inet_ntoa($dest_ip);

  $messagestr =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $messagestr =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  umask 0077;
  my $mytime = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$host:$port  $path    $dest_ipaddress\n";
  $logfilestr .= "$mytime send: $messagestr\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  my %sslheaders = ();
  ( $response, $header, %resulthash ) = &procutils::sendsslmsg( "rbc", $host, $port, "", $message, "nopost,noheaders,noshutdown,len\>10", %sslheaders );

  if ( $response eq "failure" ) {
    $response = "";
  }

  $checkmessage = $response;
  if ( $response eq "" ) {
    $checkmessage = $resulthash{'MErrMsg'};
  }
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  umask 0077;
  my $mytime = gmtime( time() );
  $logfilestr = "";
  if ( $checkmessage eq "" ) {
    $logfilestr .= "$header\n";
  }
  $logfilestr .= "$mytime recv: $checkmessage    $resulthash{'MErrMsg'}\n\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/$devprod/rbc/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  return $response;
}

sub errorchecking {

  # check for bad card numbers
  if ( ( $enclength > 1024 ) || ( $enclength < 30 ) ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr='could not decrypt card'
            where orderid=?
            and username=?
            and trans_date>=?
            and finalstatus='pending'
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$onemonthsago" );
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
            and (accttype is NULL or accttype ='' or accttype='credit')
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
            and username=?
            and trans_date>=?
            and finalstatus='pending'
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$onemonthsago" );
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
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    return 1;
  }

  if ( ( $username ne "testrbc" ) && ( $cardnumber eq "4111111111111111" ) ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr='test card number'
            where orderid=?
            and username=?
            and trans_date>=?
            and finalstatus='pending'
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$onemonthsago" );
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
            and (accttype is NULL or accttype ='' or accttype='credit')
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
            and username=?
            and trans_date>=?
            and finalstatus='pending'
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$onemonthsago" );
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
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    return 1;
  }

  return 0;
}

sub decodemsg {
  my @msgarray = @_;

  $tempstr = unpack "H16", $msgarray[1];
  my $printstr = "\n\nbitmap1: $tempstr\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );

  my $end = 1;
  if ( $msgarray[1] =~ /^(8|9|A|B|C|D|E|F)/i ) {
    $tempstr = unpack "H16", $msgarray[2];
    my $printstr = "bitmap2: $tempstr\n";
    &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );
    $end = 2;
  }

  my $message = "";
  my $msg1    = "                                  ";
  my $msg2    = "";

  $myi    = 0;
  $bitnum = 0;
  for ( $myj = 1 ; $myj <= $end ; $myj++ ) {

    #$bitmaphalf = pack "H16", $msgarray[$myj];
    $bitmaphalf = $msgarray[$myj];
    $bitmapa = unpack "N", $bitmaphalf;

    #$bitmaphalf = pack "H16", substr($msgarray[$myj],8);
    $bitmaphalf = substr( $msgarray[$myj], 4 );
    $bitmapb = unpack "N", $bitmaphalf;

    $bitmaphalf = $bitmapa;

    foreach $var (@msgarray) {
      if ( $var ne "" ) {
        $checkmessage = $var;
        $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
        $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;

        #print "$checkmessage^";

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
  my $printstr = "$msg1\n$msg2\n";
  $printstr .= "\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );
}

sub decodebitmap {
  my ( $message, $findbit ) = @_;

  my @bitlenarray = "";
  $bitlenarray[2]   = "LLVAR";
  $bitlenarray[3]   = 6;
  $bitlenarray[4]   = 12;
  $bitlenarray[6]   = 12;
  $bitlenarray[7]   = 10;
  $bitlenarray[10]  = 8;
  $bitlenarray[11]  = 6;
  $bitlenarray[12]  = 6;
  $bitlenarray[13]  = 4;
  $bitlenarray[14]  = 4;
  $bitlenarray[15]  = 4;
  $bitlenarray[18]  = 4;
  $bitlenarray[19]  = 3;
  $bitlenarray[21]  = 3;
  $bitlenarray[22]  = 3;
  $bitlenarray[24]  = 3;
  $bitlenarray[25]  = 2;
  $bitlenarray[31]  = "LLVARa";
  $bitlenarray[32]  = "LLVAR";
  $bitlenarray[35]  = "LLVARa";
  $bitlenarray[37]  = "12a";
  $bitlenarray[38]  = "6a";
  $bitlenarray[39]  = "2a";
  $bitlenarray[41]  = "8a";
  $bitlenarray[42]  = "15a";
  $bitlenarray[43]  = "40a";
  $bitlenarray[44]  = 11;
  $bitlenarray[45]  = "LLVARa";
  $bitlenarray[47]  = "LLLVARa";
  $bitlenarray[48]  = "LLLVARa";
  $bitlenarray[49]  = 3;
  $bitlenarray[51]  = 3;
  $bitlenarray[53]  = 16;
  $bitlenarray[54]  = "LLLVARa";
  $bitlenarray[57]  = "3a";
  $bitlenarray[58]  = "LLLVARa";
  $bitlenarray[59]  = "LLLVARa";
  $bitlenarray[60]  = "LLLVARa";
  $bitlenarray[61]  = "LLLVARa";
  $bitlenarray[62]  = "LLLVARa";
  $bitlenarray[63]  = "LLLVARa";
  $bitlenarray[64]  = 64;
  $bitlenarray[70]  = 3;
  $bitlenarray[90]  = 42;
  $bitlenarray[95]  = "42a";
  $bitlenarray[120] = "LLLVARa";
  $bitlenarray[123] = "LLLVARa";
  $bitlenarray[126] = "LLLVARa";
  $bitlenarray[127] = "LLLVARa";

  my $idxstart = 4;                              # bitmap start point
  my $idx      = $idxstart;
  my $bitmap1  = substr( $message, $idx, 16 );

  #$bitmap1 = pack "H16", $bitmap1;
  my $bitmap = unpack "H16", $bitmap1;
  my $printstr = "\n\nbitmap1: $bitmap\n";
  &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );
  $idx = $idx + 8;

  #$idx = $idx + 16;

  my $end = 1;
  if ( $bitmap =~ /^(8|9|a|b|c|d|e|f)/ ) {
    $bitmap2 = substr( $message, $idx, 16 );

    #$bitmap2 = pack "H16", $bitmap2;
    $bitmap = unpack "H16", $bitmap2;
    my $printstr = "bitmap2: $bitmap\n";
    &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );

    my $removebit = pack "H*", "7fffffffffffffff";
    $bitmap1 = $bitmap1 & $removebit;

    $end = 2;
    $idx = $idx + 8;

    #$idx = $idx + 16;
  }

  @msgvalues    = ();
  @msgvaluesidx = ();
  my $myk           = 0;
  my $myi           = 0;
  my $bitnum        = 0;
  my $bigbitmaphalf = $bitmap1;
  my $wordflag      = 3;
  for ( $myj = 1 ; $myj <= $end ; $myj++ ) {
    my $bitmaphalfa = substr( $bigbitmaphalf, 0, 4 );
    my $bitmapa = unpack "N", $bitmaphalfa;

    my $bitmaphalfb = substr( $bigbitmaphalf, 4, 4 );
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

        #$bit = ($bitmaphalf >> (128 - $bitnum)) % 2;
        $bit = ( $bitmaphalf >> ( 128 - ( $wordflag * 32 ) - $bitnum ) ) % 2;
        $bitnum++;
        $bitmaphalfstr = pack "N", $bitmaphalf;
        $bitmaphalfstr = unpack "H*", $bitmaphalfstr;

        #print "aaaa $bit  $bitnum  $bitmaphalfstr\n";
        if ( $bitnum == 64 ) {
          last;
        }
      }
      if ( ( ( $bitnum == 64 ) || ( $bitnum == 128 ) ) && ( $bit == 0 ) ) {
        last;
      }

      my $tempstr = substr( $message, $idx, 8 );
      $tempstr = unpack "H*", $tempstr;
      $bitmaphalfstr = pack "N", $bitmaphalf;
      $bitmaphalfstr = unpack "H*", $bitmaphalfstr;

      #print "aaaa $tempstr    $bitmaphalfstr\n";

      my $idxold = $idx;

      my $idxlen1 = $bitlenarray[ $bitnum - 1 ];
      my $idxlen  = $idxlen1;
      if ( $idxlen1 eq "LLVAR" ) {
        $idxlen = substr( $message, $idx, 1 );
        $idxlen = unpack "H2", $idxlen;
        $idxlen = int( ( $idxlen / 2 ) + .5 );
        $idx = $idx + 1;
      } elsif ( $idxlen1 eq "LLVARa" ) {
        $idxlen = substr( $message, $idx, 1 );
        $idxlen = unpack "H2", $idxlen;
        $idx = $idx + 1;
      } elsif ( $idxlen1 eq "LLLVAR" ) {
        $idxlen = substr( $message, $idx, 2 );
        $idxlen = unpack "H4", $idxlen;
        $idxlen = int( ( $idxlen / 2 ) + .5 );
        $idx = $idx + 2;
      } elsif ( $idxlen1 eq "LLLVARa" ) {
        $idxlen = substr( $message, $idx, 2 );
        $idxlen = unpack "H4", $idxlen;
        $idx = $idx + 2;
      } elsif ( $idxlen1 =~ /a/ ) {
        $idxlen =~ s/a//g;
      } else {
        $idxlen = int( ( $idxlen / 2 ) + .5 );
      }
      my $value = substr( $message, $idx, $idxlen );
      if ( $idxlen1 !~ /a/ ) {
        $value = unpack "H*", $value;
      } else {

        #$value = &ebcdic2ascii($value);
      }
      $tmpbit = $bitnum - 1;
      my $printstr = "bit: $idxold  $tmpbit  $idxlen1 $idxlen  $value\n";
      &procutils::filewrite( "$username", "rbc", "/home/pay1/batchfiles/devlogs/rbc", "miscdebug.txt", "append", "misc", $printstr );

      $msgvalues[$tmpbit]    = "$value";
      $msgvaluesidx[$tmpbit] = "$idx";

      $myk++;
      if ( $myk > 26 ) {
        return -1, "";

        #exit;
      }
      if ( ( $findbit ne "" ) && ( $findbit == $bitnum - 1 ) ) {
        return $idx, $value;
      }
      $idx = $idx + $idxlen;
      if ( ( $bitnum == 64 ) || ( $bitnum >= 128 ) ) {
        last;
      }
    }
    $bigbitmaphalf = $bitmap2;
  }    # end for
       #print "\n";

  #my $tempstr = unpack "H*",$message;
  #print "$tempstr\n\n";

  #umask 0077;
  #open(logfile,">>/home/pay1/batchfiles/$devprod/rbc/bserverlogmsg.txt");
  #print logfile "\n";
  #for (my $i=0; $i<$#msgvalues; $i++) {
  #  if ($i == 2) {
  #    my $tempstr = $msgvalues[$i];
  #    $tempstr =~ s/[0-9]/x/g;
  #    print logfile "$i  $temp\n";
  #  }
  #  elsif ($msgvalues[$i] ne "") {
  #    print logfile "$i  $msgvalues[$i]\n";
  #  }
  #}
  #close(logfile);

  return @msgvalues;
}

sub generatebitmap {
  my (@msg) = @_;

  my $tempdata = "";
  my $message  = "";
  my $tempstr  = "";
  my $bitmap1  = "";
  my $bitmap2  = "";

  for ( my $i = 2 ; $i <= 128 ; $i++ ) {
    $tempdata = $tempdata << 1;
    if ( $msg[$i] ne "" ) {
      $tempdata = $tempdata | 1;
      $message  = $message . $msg[$i];
    } else {
    }
    $tempstr = pack "N", $tempdata;
    $tempstr = unpack "H32", $tempstr;

    #print "tempdata: $tempstr  $i\n";
    if ( $i == 32 ) {
      $bitmap1  = $tempstr;
      $tempdata = 0;
    } elsif ( $i == 64 ) {
      $bitmap1  = $bitmap1 . $tempstr;
      $tempdata = 0;
    } elsif ( $i == 96 ) {
      $bitmap2  = $tempstr;
      $tempdata = 0;
    } elsif ( $i == 128 ) {
      $bitmap2  = $bitmap2 . $tempstr;
      $tempdata = 0;
    }
  }
  if ( $bitmap2 ne "0000000000000000" ) {
    my $tempdata      = pack "H*", $bitmap1;
    my $marketdatabit = pack "H*", "8000000000000000";
    $bitmap1 = $tempdata | $marketdatabit;
    $bitmap1 = unpack "H64", $bitmap1;
  } else {
    $bitmap2 = "";
  }

  #print "bitmap1: $bitmap1\n";
  #print "bitmap2: $bitmap2\n";

  $bitmap1 =~ tr/a-z/A-Z/;
  $bitmap2 =~ tr/a-z/A-Z/;

  return $bitmap1, $bitmap2;
}

