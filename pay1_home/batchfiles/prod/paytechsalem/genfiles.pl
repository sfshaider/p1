#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use procutils;
use rsautils;
use isotables;
use smpsutils;

$devprod     = "prod";
$devprodlogs = "logs";

if ( -e "/home/pay1/batchfiles/$devprodlogs/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'paytechsalem/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: paytechsalem - genfiles already running\n";
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
&procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprodlogs/paytechsalem", "pid.txt", "write", "", $outfilestr );

&miscutils::mysleep(2.0);

my $chkline = &procutils::fileread( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprodlogs/paytechsalem", "pid.txt" );
chop $chkline;

if ( $pidline ne $chkline ) {
  my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
  $printstr .= "$pidline\n";
  $printstr .= "$chkline\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: paytechsalem - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

$checkstring  = "and username not in ('bouldercou')";
$checkstring2 = "and t.username not in ('bouldercou')";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d",       $year + 1900, $month + 1, $day );
$onemonthsagotime = sprintf( "%04d%02d%02d000000", $year + 1900, $month + 1, $day );
$starttransdate   = $onemonthsago - 10000;

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - 3600 );
$onehourago = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
my $printstr = "One hour ago: $onehourago\n";
&procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 60 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
my $printstr = "two months ago: $twomonthsago\n";
&procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

( $dummy, $today, $todaytime ) = &miscutils::genorderid();
$neworderid = $todaytime;

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/logs/paytechsalem/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/paytechsalem/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/logs/paytechsalem/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/logs/paytechsalem/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/paytechsalem/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/logs/paytechsalem/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/logs/paytechsalem/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/paytechsalem/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/logs/paytechsalem/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/logs/paytechsalem/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: paytechsalem - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory paytechsalem/logs/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;
$errorflag  = 0;

my $printstr = "cccc\n";
&procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
my $dbquerystr = <<"dbEOM";
        select distinct username
        from trans_log
        where trans_date>=?
        and finalstatus = 'locked'
        and (accttype is NULL or accttype ='' or accttype='credit')
        $checkstring
dbEOM
my @dbvalues = ("$onemonthsago");
my @stherrorvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@stherrorvalarray) ; $vali = $vali + 1 ) {
  ($user) = @stherrorvalarray[ $vali .. $vali + 0 ];

  my $dbquerystr = <<"dbEOM";
        select status,processor
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $chkstatus, $chkprocessor ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( ( $chkstatus eq "live" ) && ( $chkprocessor eq "paytechsalem" ) ) {
    my $printstr = "b: $user\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
    $erroruserflag{$user} = "yes";
    $errorflag = 1;
  }

}

if ( $errorflag == 1 ) {

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: paytechsalem - Batch Error\n";
  print MAILERR "\n";
  print MAILERR "Locked records found.\n\n";
  foreach $key ( sort keys %erroruserflag ) {
    print MAILERR "username: $key\n";
  }
  close MAILERR;

}

my $printstr = "dddd\n";
$printstr .= "$onemonthsago  $onemonthsagotime\n";
&procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

# xxxx
my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        $checkstring2
        and t.finalstatus='pending'
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastoptime>=?
        and o.lastopstatus='pending'
        and o.processor='paytechsalem' 
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

foreach $username (@userarray) {
  if ( -e "/home/pay1/batchfiles/$devprodlogs/stopgenfiles.txt" ) {
    unlink "/home/pay1/batchfiles/$devprodlogs/paytechsalem/batchfile.txt";
    last;
  }

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprodlogs/paytechsalem", "genfiles.txt", "write", "", $batchfilestr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprodlogs/paytechsalem", "batchfile.txt", "write", "", $batchfilestr );

  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/logs/paytechsalem/$fileyear", "t$todaytime.txt", "append", "", $logfilestr );

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  my $dbquerystr = <<"dbEOM";
        select c.merchant_id,c.pubsecret,c.proc_type,c.currency,c.status,c.zip,c.country,
               p.industrycode,p.divisions
        from customers c, paytechsalem p
        where c.username=?
        and p.username=c.username
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $currency, $status, $mzip, $mcountry, $industrycode, $divisions ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $status ne "live" ) {
    next;
  }

  (%divisionarray) = split( /,/, $divisions );

  if ( $currency eq "" ) {
    $currency = "usd";
  }

  my $dbquerystr = <<"dbEOM";
        select orderid
        from operation_log
        where trans_date>=?
        and trans_date<=?  
        and lastoptime>=?
        and username=?
        and lastop in ('postauth','return')
        and lastopstatus='pending'
        and (voidstatus is NULL or voidstatus ='')
        and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$starttransdate", "$today", "$onemonthsagotime", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  @orderidarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 1 ) {
    ($orderid) = @sthtransvalarray[ $vali .. $vali + 0 ];

    $orderidarray[ ++$#orderidarray ] = $orderid;
  }

  $mintrans_date = $today;

  foreach $orderid ( sort @orderidarray ) {

    # operation_log should only have one orderid per username
    if ( $orderid eq $chkorderidold ) {
      next;
    }
    $chkorderidold = $orderid;

    my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,
                 auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,card_zip,
                 authtime,authstatus,forceauthtime,forceauthstatus,reauthtime,reauthstatus,
                 card_name,card_addr,card_city,card_state,card_country,origamount
          from operation_log
          where orderid=?
          and username=?
          and trans_date>=?
          and trans_date<=?  
          and lastoptime>=?
          and lastoptime<?
          and lastop in ('postauth','return')
          and lastopstatus in ('pending')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$orderid", "$username", "$starttransdate", "$today", "$onemonthsagotime", "$onehourago" );
    ( $orderid,         $operation,  $trans_date,   $trans_time, $enccardnumber, $length,    $card_exp,   $amount,       $auth_code,
      $avs_code,        $refnumber,  $finalstatus,  $cvvresp,    $transflags,    $card_zip,  $authtime,   $authstatus,   $forceauthtime,
      $forceauthstatus, $reauthtime, $reauthstatus, $card_name,  $card_addr,     $card_city, $card_state, $card_country, $origamount
    )
      = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $orderid eq "" ) {
      next;
    }

    if ( -e "/home/pay1/batchfiles/$devprodlogs/stopgenfiles.txt" ) {
      unlink "/home/pay1/batchfiles/$devprodlogs/paytechsalem/batchfile.txt";
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
    my $printstr = "$orderid   $orderidold  $operation\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

    if ( $checkdup{"$operation $orderid"} == 1 ) {
      next;
    }
    $checkdup{"$operation $orderid"} = 1;

    if ( ( $authtime ne "" ) && ( $authstatus eq "success" ) ) {
      $trans_time    = $authtime;
      $origoperation = "auth";
    } elsif ( ( $forceauthtime ne "" ) && ( $forceauthstatus eq "success" ) ) {
      $trans_time    = $forceauthtime;
      $origoperation = "forceauth";
    } else {
      $trans_time    = "";
      $origoperation = "";
      $origamount    = "";
    }

    if ( ( $reauthtime ne "" ) && ( $reauthstatus eq "success" ) ) {
      $reauthflag = 1;
    } else {
      $reauthflag = 0;
    }

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "paytechsalem", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $errflag = &errorchecking();
    if ( $errflag == 1 ) {
      next;
    }

    $card_type = &smpsutils::checkcard($cardnumber);

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/logs/paytechsalem/$fileyear", "t$todaytime.txt", "append", "", $logfilestr );

    $commcardtype = substr( $auth_code, 73, 12 );
    $commcardtype =~ s/ //g;
    my $printstr = "commcardtype: $commcardtype\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

    if ( ( $card_type eq "ax" ) && ( $commcardtype ne "" ) ) {
      my $dbquerystr = <<"dbEOM";
            select shipname,shipaddr1,shipaddr2,shipcity,shipstate,shipzip,shipcountry
            from ordersummary
            where orderid=?
            and username=?
dbEOM
      my @dbvalues = ( "$orderid", "$username" );
      ( $ship_name, $ship_addr1, $ship_addr2, $ship_city, $ship_state, $ship_zip, $ship_country ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    }

    if ( ( $username ne $usernameold ) && ( $batch_flag == 0 ) ) {
      &batchtrailer();
      $batch_flag = 1;
      &pidcheck();
    }

    if ( $file_flag == 1 ) {
      &fileheader();
    }

    if ( $batch_flag == 1 ) {
      $batchsalescnt  = 0;
      $batchsalesamt  = 0;
      $batchretcnt    = 0;
      $batchretamt    = 0;
      $batchtotamt    = 0;
      $batchreccnt    = 1;
      $batchdetreccnt = 0;
      $batch_flag     = 0;
      $recseqnum      = 0;
    }

    my $dbquerystr = <<"dbEOM";
        update trans_log set finalstatus='locked',result=?
	where orderid=?
	and trans_date>=?
	and username=?
	and finalstatus='pending'
        and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$ttime", "$orderid", "$twomonthsago", "$username" );
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
    my @dbvalues = ( "$ttime", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    &batchdetail();

    if ( $batchdetreccnt >= 50 ) {
      &batchtrailer();
      $batch_flag = 1;
      &pidcheck();
    }

    if ( $batchcount >= 998 ) {
      &filetrailer();
      $file_flag = 1;
    }

    $banknumold  = $banknum;
    $usernameold = $username;
  }

}

if ( $batch_flag == 0 ) {
  &batchtrailer();
  $batch_flag = 1;
  &pidcheck();
}

if ( $file_flag == 0 ) {
  &filetrailer();
  $file_flag = 1;
}

unlink "/home/pay1/batchfiles/$devprodlogs/paytechsalem/batchfile.txt";

umask 0033;
$batchfilestr = "";
&procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprodlogs/paytechsalem", "genfiles.txt", "write", "", $batchfilestr );

system("/home/pay1/batchfiles/$devprod/paytechsalem/putfiles.pl");

exit;

sub batchheader {
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0" x 9 . $recseqnum, -9, 9 );

  @bh    = ();
  $bh[0] = 'M';         # constant (7a)
  $bh[1] = " " x 22;    # merchant name can use default (22n)
  $bh[2] = " " x 4;     # filler (4a)
  $bh[3] = " " x 13;    # merchant city customer service number can use default (13a)
  $bh[4] = ' ' x 80;    # filler (80a)

  foreach $var (@bh) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
  }
  $outfilestr  .= "\n";
  $outfile2str .= "\n";
}

sub batchtrailer {
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0" x 9 . $recseqnum, -9, 9 );

  $batchsalescnt  = substr( "0000000" . $batchsalescnt, -6,  6 );
  $batchsalesamt  = substr( "0" x 14 . $batchsalesamt,  -14, 14 );
  $batchretcnt    = substr( "0000000" . $batchretcnt,   -6,  6 );
  $batchretamt    = substr( "0" x 14 . $batchretamt,    -14, 14 );
  $batchtotamt    = substr( "0" x 14 . $batchtotamt,    -14, 14 );
  $batchdetreccnt = substr( "0" x 9 . $batchdetreccnt,  -9,  9 );

  @bt     = ();
  $bt[0]  = 'B RECS=';          # constant (7a)
  $bt[1]  = $recseqnum;         # batch record count (9n)
  $bt[2]  = ' ';                # filler (1a)
  $bt[3]  = 'ORDS=';            # constant (5a)
  $bt[4]  = $batchdetreccnt;    # batch order count (9n)
  $bt[5]  = ' ';                # filler (1a)
  $bt[6]  = '$TOT=';            # constant (5a)
  $bt[7]  = $batchtotamt;       # batch amount total (14n)
  $bt[8]  = ' ';                # filler (1a)
  $bt[9]  = '$SALE=';           # constant (6a)
  $bt[10] = $batchsalesamt;     # batch amount sales (14n)
  $bt[11] = ' ';                # filler (1a)
  $bt[12] = '$REFUND=';         # constant (8a)
  $bt[13] = $batchretamt;       # batch amount refunds (14n)
  $bt[14] = ' ' x 25;           # reserved (25a)

  foreach $var (@bt) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
  }
  $outfilestr  .= "\n";
  $outfile2str .= "\n";
}

sub fileheader {
  $filesalescnt = 0;
  $filesalesamt = 0;
  $fileretcnt   = 0;
  $fileretamt   = 0;
  $filetotamt   = 0;
  $filereccnt   = 0;
  $recseqnum    = 0;
  $batchcount   = 0;

  $file_flag = 0;

  ( $d1, $d2, $ttime ) = &miscutils::genorderid();
  $filename = "$ttime";

  umask 0077;
  $outfilestr  = "";
  $outfile2str = "";

  @fh     = ();
  $fh[0]  = "PID=";                   # constant (4a)
  $fh[1]  = '292961';                 # presenter's id (6n)
  $fh[2]  = ' ';                      # filler (1a)
  $fh[3]  = 'PLUG120S';               # pid password (8a)
  $fh[4]  = ' ';                      # filler (1a)
  $fh[5]  = 'SID=';                   # constant (4a)
  $fh[6]  = '292961';                 # submitter's id (6n)
  $fh[7]  = ' ';                      # filler (1a)
  $fh[8]  = 'PAYS120S';               # sid password (8a)
  $fh[9]  = ' ';                      # filler (1a)
  $fh[10] = 'START';                  # constant (5a)
  $fh[11] = '  ';                     # filler (2a)
  $cdate  = substr( $today, 2, 6 );
  $fh[12] = $cdate;                   # creation date (6a)
  $fh[13] = ' ';                      # filler (1a)
  $fh[14] = '3.0.0';                  # revision number (5a)
  $fh[15] = ' ';                      # filler (1a)
  $fh[16] = ' ' x 11;                 # submission number (11a)
  $fh[17] = ' ' x 41;                 # filler (41a)
  $fh[18] = ' ' x 8;                  # merchant space (8a)

  foreach $var (@fh) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
  }
  $outfilestr  .= "\n";
  $outfile2str .= "\n";
}

sub filetrailer {

  $filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0" x 9 . $recseqnum, -9, 9 );

  $filesalescnt  = substr( "0000000" . $filesalescnt, -7,  7 );
  $filesalesamt  = substr( "0" x 14 . $filesalesamt,  -14, 14 );
  $fileretcnt    = substr( "0000000" . $fileretcnt,   -7,  7 );
  $fileretamt    = substr( "0" x 14 . $fileretamt,    -14, 14 );
  $filetotamt    = substr( "0" x 14 . $filetotamt,    -14, 14 );
  $filedetreccnt = substr( "0" x 9 . $filedetreccnt,  -9,  9 );
  $filereccnt    = substr( "0" x 9 . $filereccnt,     -9,  9 );

  @ft     = ();
  $ft[0]  = 'T RECS=';         # constant (7a)
  $ft[1]  = $filereccnt;       # file record count (9n)
  $ft[2]  = ' ';               # filler (1a)
  $ft[3]  = 'ORDS=';           # constant (5a)
  $ft[4]  = $filedetreccnt;    # file order count (9n)
  $ft[5]  = ' ';               # filler (1a)
  $ft[6]  = '$TOT=';           # constant (5a)
  $ft[7]  = $filetotamt;       # file amount total (14n)
  $ft[8]  = ' ';               # filler (1a)
  $ft[9]  = '$SALE=';          # constant (6a)
  $ft[10] = $filesalesamt;     # file amount sales (14n)
  $ft[11] = ' ';               # filler (1a)
  $ft[12] = '$REFUND=';        # constant (8a)
  $ft[13] = $fileretamt;       # file amount refunds (14n)
  $ft[14] = ' ' x 25;          # reserved (25a)

  foreach $var (@ft) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
  }
  $outfilestr  .= "\n";
  $outfile2str .= "\n";

  @ft      = ();
  $ftr[0]  = "PID=";                   # constant (4a)
  $ftr[1]  = '292961';                 # presenter's id (6n)
  $ftr[2]  = ' ';                      # filler (1a)
  $ftr[3]  = 'PLUG120S';               # pid password (8a)
  $ftr[4]  = ' ';                      # filler (1a)
  $ftr[5]  = 'SID=';                   # constant (4a)
  $ftr[6]  = '292961';                 # submitter's id (6n)
  $ftr[7]  = ' ';                      # filler (1a)
  $ftr[8]  = 'PAYS120S';               # sid password (8a)
  $ftr[9]  = ' ';                      # filler (1a)
  $ftr[10] = 'END';                    # constant (3a)
  $ftr[11] = '  ';                     # filler (2a)
  $cdate   = substr( $today, 2, 6 );
  $ftr[12] = $cdate;                   # creation date (6a)
  $ftr[13] = ' ' x 69;                 # reserved (69a)

  foreach $var (@ftr) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
  }
  $outfilestr  .= "\n";
  $outfile2str .= "\n";

  &procutils::fileencwrite( "$username", "paytechsalem", "/home/pay1/batchfiles/logs/paytechsalem/$fileyear", "$filename", "write", "", $outfilestr );
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/logs/paytechsalem/$fileyear", "$filename.txt", "write", "", $outfile2str );
}

sub batchdetail {
  $batchdetreccnt++;
  $filedetreccnt++;
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;

  $transamt = substr( $amount, 4 );
  $transamt = $transamt * 100;

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
  $batchtotamt = $batchtotamt + $transamt;
  $filetotamt  = $filetotamt + $transamt;

  $morderid = substr( $auth_code, 45, 22 );
  $morderid =~ s/ //g;
  if ( $morderid eq "" ) {
    $neworderid = &miscutils::incorderid($neworderid);
    $morderid   = $neworderid;
    $morderid   = substr( $morderid, -8, 8 ) . "0" x 14;    # first 8 chars must be unique
  }

  my $dbquerystr = <<"dbEOM";
        insert into batchfilessalem
	(username,filename,trans_date,orderid,status,detailnum)
        values (?,?,?,?,?,?)
dbEOM
  my %inserthash = ( "username", "$username", "filename", "$ttime", "trans_date", "$today", "orderid", "$orderid", "status", "pending", "detailnum", "$morderid" );
  &procutils::dbinsert( $username, $orderid, "pnpmisc", "batchfilessalem", %inserthash );

  $clen = length($cardnumber);
  $cabbrev = substr( $cardnumber, 0, 4 );

  if ( $card_type eq "vi" ) {
    $cardtype = 'VI';    # visa
  } elsif ( $card_type eq "mc" ) {
    $cardtype = 'MC';    # mastercard
  } elsif ( $card_type eq "ax" ) {
    $cardtype = 'AX';    # amex
  } elsif ( $card_type eq "dc" ) {
    $cardtype = 'DD';    # diners club/carte blanche
  } elsif ( $card_type eq "ds" ) {
    $cardtype = 'DI';    # discover
  } elsif ( $card_type eq "jc" ) {
    $cardtype = 'JC';    # jcb
  } elsif ( $cardnumber =~ / / ) {
    $cardtype = 'EC';    # discover
  }

  if ( $cardnumber =~ / / ) {
    $cardtype = 'EC';    # discover
  } else {
    $cardtype = $card_type;
    $cardtype =~ tr/a-z/A-Z/;
  }

  $transamt = substr( "0" x 12 . $transamt, -12, 12 );

  @bd          = ();
  $bd[0]       = 'S';                                          # constant (1a)
  $divisionnum = substr( "0" x 10 . $merchant_id, -10, 10 );
  if ( $divisionarray{"$card_type"} ne "" ) {
    $divisionnum = $divisionarray{"$card_type"};
    $divisionnum = substr( "0" x 10 . $divisionnum, -10, 10 );
  }
  $bd[1] = $divisionnum;                                       # division number (10n)
                                                               #$morderid = substr($morderid . " " x 22,0,22);
  $morderid = substr( $morderid . " " x 22, 0, 22 );
  $bd[2] = $morderid;                                          # merchants order number (22a)
  if ( $operation eq "postauth" ) {
    $action = "DP";
  } elsif ( $operation eq "return" ) {
    $action = "RF";
  }
  $bd[3] = $action;                                            # action (2a)
  if ( $cardtype eq "DS" ) {
    $cardtype = "DI";
  }
  if ( $cardtype eq "DC" ) {
    $cardtype = "DD";
  }
  $bd[4] = $cardtype;                                          # method of payment (2a)
  $cardnum = substr( $cardnumber . " " x 19, 0, 19 );
  $bd[5] = $cardnum;                                           # account number (19a)
  $expdate = substr( $card_exp, 0, 2 ) . substr( $card_exp, 3, 2 );
  $expdate = substr( $expdate . " " x 4, 0, 4 );
  $bd[6]        = $expdate;                                    # expiration date (4a)
  $bd[7]        = $transamt;                                   # amount (12n)
  $cardcurrency = $currency;
  $cardcurrency =~ tr/a-z/A-Z/;
  $currencycode = $isotables::currencyUSD840{$cardcurrency};

  if ( $currencycode eq "" ) {
    $currencycode = "840";
  }
  $bd[8] = $currencycode;                                      # currency code (3n)
  $respcode = substr( $auth_code,          6, 3 );
  $respcode = substr( $respcode . " " x 3, 0, 3 );
  my $printstr = "operation: $operation\n";
  $printstr .= "origoperation: $origoperation\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
  if ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
    $respcode = "100";
  } elsif ( $operation eq "return" ) {
    $respcode = "   ";
  }
  $bd[9] = $respcode;                                          # response reason code (3n)
  $eci = substr( $auth_code, 44, 1 );
  $eci =~ s/ //g;
  my $printstr = "eci: $eci\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
  if ( $transflags =~ /recurring/ ) {
    $bd[10] = '2';                                             # transaction type 2 = recurring, 1 = moto, 7 = secure ecommerce (1a)
  } elsif ( $transflags =~ /install/ ) {
    $bd[10] = '3';                                             # transaction type 2 = recurring, 1 = moto, 7 = secure ecommerce (1a)
  } elsif ( $transflags =~ /moto/ ) {
    $bd[10] = '1';                                             # transaction type 2 = recurring, 1 = moto, 7 = secure ecommerce (1a)
  } elsif ( $industrycode eq "retail" ) {
    $bd[10] = 'R';                                             # transaction type R = retail, 1 = moto, 7 = secure ecommerce (1a)
  } elsif ( ( $eci ne "" ) && ( $eci ne " " ) ) {
    $bd[10] = $eci;                                            # transaction type 2 = recurring, 1 = moto, 7 = secure ecommerce (1a)
  } else {
    $bd[10] = '7';                                             # transaction type 2 = recurring, 1 = moto, 7 = secure ecommerce (1a)
  }
  $bd[11] = ' ';                                               # reserved (1a)
  if ( ( $operation eq "postauth" ) && ( $origoperation eq "forceauth" ) ) {
    $ltime = &miscutils::strtotime($trans_time);
    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($ltime);
    $year  = $year + 1900;
    $year  = substr( $year, 2, 2 );
    $tdate = sprintf( "%02d%02d%02d", $year, $month + 1, $day );
  } elsif ( $operation eq "postauth" ) {
    $tdate = substr( $auth_code, 9, 6 );
  } elsif ( $operation eq "return" ) {
    $tdate = "";
  } else {
    $tdate = substr( $trans_date, 2 );
  }
  $tdate = substr( $tdate . " " x 6, 0, 6 );
  $bd[12] = $tdate;    # response date (6n)
  $authcode = substr( $auth_code . " " x 6, 0, 6 );
  if ( $operation eq "return" ) {
    $authcode = "     ";
  }
  $bd[13] = $authcode;    # authorization/verification code (6a)
  $avs_code = substr( $avs_code . "  ", 0, 2 );
  $bd[14] = $avs_code;    # avs response code (2a)
  $bd[15] = ' ';          # reserved (1a)
  my $paymentind = ' ';
  if ( $transflags =~ /bill/ ) {
    $paymentind = 'Y';
  }
  $bd[16] = $paymentind;    # payment indicator (1a)
  $bd[17] = '   ';          # encryption flag (3a)
  $bd[18] = ' ' x 13;       # reserved (13a)
  $bd[19] = ' ' x 8;        # merchant space (8a)

  foreach $var (@bd) {
    $outfilestr .= "$var";
  }

  $outfile2str .= "$username $orderid\n";
  $bd[5] =~ s/[0-9]/x/g;
  foreach $var (@bd) {
    $outfile2str .= "$var";
  }

  $outfilestr  .= "\n";
  $outfile2str .= "\n";

  $reqcashback = substr( $auth_code, 121, 12 );
  $reqcashback =~ s/ //g;
  $cashback = substr( $auth_code, 133, 12 );
  $cashback =~ s/ //g;
  my $printstr = "reqcashback: $reqcashback\n";
  $printstr .= "cashback: $cashback\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
  if ( ( $card_type eq "ds" ) && ( ( $cashback > 0 ) || ( $reqcashback > 0 ) ) ) {
    $reqcashback = substr( "0" x 12 . $reqcashback, -12, 12 );
    $cashback    = substr( "0" x 12 . $cashback,    -12, 12 );
    $bdds[0] = 'PCO001' . $reqcashback . $cashback;    # cashback
    $bdds[1] = ' ' x 90;                               # reserved (90a)

    foreach $var (@bdds) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }
    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  if ( $card_type eq "sw" ) {
    @bdsw         = ();
    $bdsw[0]      = 'ESW001';                          # constant (6a)
    $cardissuenum = substr( $auth_code, 67, 2 );
    $cardissuenum =~ s/ //g;
    if ( $cardissuenum ne "" ) {
      $cardissuenum = substr( $cardissuenum . " " x 2, 0, 2 );
      $bdsw[1] = "    " . $cardissuenum;               # card issue number (2n)
    } else {
      $cardstartdate = substr( $auth_code, 69, 4 );
      $cardstartdate = substr( $cardstartdate . " " x 4, 0, 4 );
      $bdsw[1] = $cardstartdate . "  ";                # card start date (4n)
    }
    $bdsw[2] = " " x 108;                              # card reserved (108a)

    foreach $var (@bdsw) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }
    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  $xid = substr( $auth_code, 145, 40 );
  $xid =~ s/ //g;
  $cavv = substr( $auth_code, 185, 32 );
  $cavv =~ s/ //g;

  if ( ( $card_type eq "vi" ) && ( $cavv ne "" ) ) {
    @bdsw    = ();
    $bdsw[0] = 'EVI002';                            # constant (6a)
    $xid     = substr( $xid . " " x 40, 0, 40 );
    $bdsw[1] = $xid;                                # xid (40a)
    $cavv    = substr( $cavv . " " x 40, 0, 40 );
    $bdsw[2] = $cavv;                               # cavv (40a)
    $bdsw[3] = " ";                                 # cavv response code (only Salem populates this) (1a)
    $bdsw[4] = " " x 33;                            # card reserved (33a)

    foreach $var (@bdsw) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }
    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  if ( ( $card_type eq "mc" ) && ( $cavv ne "" ) ) {
    @bdsw    = ();
    $bdsw[0] = 'EMC002';                            # constant (6a)
    $cavv    = substr( $cavv . " " x 32, 0, 32 );
    $bdsw[1] = $cavv;                               # cavv (32a)
    $bdsw[2] = " " x 82;                            # card reserved (82a)

    foreach $var (@bdsw) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }
    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  if ( ( $commcardtype ne "" ) || ( $transflags =~ /level3/ ) ) {
    if ( $card_type eq "ax" ) {

      my $dbquerystr = <<"dbEOM";
            select item,quantity,cost,description,unit,customa,customb,customc,customd
            from orderdetails
            where orderid=? 
            and username=?
dbEOM
      my @dbvalues = ( "$orderid", "$username" );
      my @sthdetailsvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      $axcnt   = 0;
      @axdescr = ();
      for ( my $vali = 0 ; $vali < scalar(@sthdetailsvalarray) ; $vali = $vali + 9 ) {
        ( $item, $quantity, $cost, $descr, $unit, $customa, $customb, $customc, $customd ) = @sthdetailsvalarray[ $vali .. $vali + 8 ];

        if ( $card_type eq "ax" ) {
          $descra = $descr;
          $descra =~ s/[^a-zA-Z0-9 \-_\/]//g;
          $descra =~ tr/a-z/A-Z/;
          $descra = substr( $descra . " " x 40, 0, 40 );
          $axdescr[$axcnt] = $descra;
          $axcnt++;
          next;
        }
      }

      if ( $axcnt > 0 ) {
        $axdescr[0] = substr( $axdescr[0] . " " x 40, 0, 40 );
        $axdescr[1] = substr( $axdescr[1] . " " x 40, 0, 40 );
        $axdescr[2] = substr( $axdescr[2] . " " x 40, 0, 40 );
        $axdescr[3] = substr( $axdescr[3] . " " x 40, 0, 40 );

        @bdab    = ();
        $bdab[0] = 'EAX';          # constant (1a)
        $bdab[1] = '001';          # constant (1a)
        $bdab[2] = $axdescr[0];    # TAA addendum 1 (40a)
        $bdab[3] = $axdescr[1];    # TAA addendum 2 (40a)
        $bdab[4] = ' ' x 34;       # reserved (34a)

        foreach $var (@bdab) {
          $outfilestr  .= "$var";
          $outfile2str .= "$var";
        }
        $outfilestr  .= "\n";
        $outfile2str .= "\n";

        @bdab    = ();
        $bdab[0] = 'EAX';          # constant (1a)
        $bdab[1] = '002';          # constant (1a)
        $bdab[2] = $axdescr[2];    # TAA addendum 1 (40a)
        $bdab[3] = $axdescr[3];    # TAA addendum 2 (40a)
        $bdab[4] = ' ' x 34;       # reserved (34a)

        foreach $var (@bdab) {
          $outfilestr  .= "$var";
          $outfile2str .= "$var";
        }
        $outfilestr  .= "\n";
        $outfile2str .= "\n";
      }
    }
  }

  if ( $industrycode eq "retail" ) {
    @bdrt     = ();
    $bdrt[0]  = 'PRR001';                                # constant (6a)
    $deviceid = substr( $auth_code, 225, 8 );
    $deviceid = substr( $deviceid . " " x 16, 0, 16 );

    $bdrt[1] = $deviceid;                                # terminal id (16a)
    $bid = substr( $todaytime,      -14, 14 );
    $bid = substr( $bid . " " x 14, 0,   14 );
    $bdrt[2] = $bid;                                     # batch id (14a)
    $bdrt[3] = " " x 84;                                 # card reserved (108a)

    foreach $var (@bdrt) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }
    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  @bdp = ();
  if ( ( $commcardtype ne "" ) || ( $transflags =~ /level3/ ) ) {
    my $dbquerystr = <<"dbEOM";
          select shipname,shipaddr1,shipaddr2,shipcity,shipstate,shipzip,shipcountry
          from ordersummary
          where orderid=?
          and username=?
dbEOM
    my @dbvalues = ( "$orderid", "$username" );
    ( $ship_name, $ship_addr1, $ship_addr2, $ship_city, $ship_state, $ship_zip, $ship_country ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $ponumber = substr( $auth_code, 15, 17 );
    $ponumber =~ s/[^0-9a-zA-Z\-]//g;
    $ponumber =~ tr/a-z/A-Z/;
    $ponumber = substr( $ponumber . " " x 17, 0,  17 );
    $tax      = substr( $auth_code,           32, 12 );
    $bdp[0]    = 'PPC001';     # constant (6a)
    $bdp[1]    = $ponumber;    # ponumber (17a)
    $bdp[2]    = $tax;         # tax (12a)
    $bdp[3]    = ' ' x 38;     # amex level2 requestor name (38a)
    $bdp[4]    = ' ' x 15;     # amex level2 destination zip, sent in A record (15a)
    $exemptind = "N";
    if ( ( $tax == 0 ) && ( $transflags !~ /notexempt/ ) ) {
      $exemptind = "Y";
    }
    $bdp[5] = $exemptind;      # tax exempt indicator (1a)
    $bdp[6] = ' ' x 31;        # spaces (31a)

    foreach $var (@bdp) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }
    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

  if ( $transflags =~ /level3/ ) {

    @bdp     = ();
    $bdp[0]  = 'PP0001';                       # constant (6a)
    $freight = substr( $auth_code, 97, 12 );
    if ( $card_type eq "mc" ) {
      $freight = substr( "0" x 9 . $freight, -9, 9 );
    } else {
      $freight = substr( "0" x 12 . $freight, -12, 12 );
    }
    $bdp[2] = $freight;                        # freight (9a)
    $duty = substr( $auth_code, 85, 12 );
    if ( $card_type eq "mc" ) {
      $duty = substr( "0" x 9 . $duty, -9, 9 );
    } else {
      $duty = substr( "0" x 12 . $duty, -12, 12 );
    }
    $bdp[3] = $duty;                           # duty (9a)
    $shipzip = substr( $ship_zip . " " x 10, 0, 10 );
    $bdp[4] = $shipzip;                        # destination zip (10a)
    if ( $ship_country eq "" ) {
      $ship_country = "US";
    }
    $countrycode = $ship_country;
    $countrycode =~ tr/a-z/A-Z/;
    $countrycode = $isotables::countryUSUSA{"$countrycode"};
    $bdp[5]      = $countrycode;                               # destination country (3a)
    $shipfromzip = substr( $mzip . " " x 10, 0, 10 );
    $bdp[6]      = $shipfromzip;                               # ship from zip (10a)

    if ( $card_type eq "mc" ) {
      $bdp[7]  = " " x 15;                                     # alternate tax id (15a)
      $bdp[8]  = " " x 9;                                      # alternate tax amount (9a)
      $bdp[9]  = " " x 9;                                      # reserved (9a)
      $bdp[10] = " " x 12;                                     # vat tax amount (12a)
      $bdp[11] = " " x 28;                                     # spaces (28a)
    } else {

      $discount = "0" x 12;
      $bdp[7]   = $discount;                                   # discount amount (12a)
      $bdp[8]   = " " x 12;                                    # vat tax amount (12a)
      $bdp[9]   = " " x 4;                                     # vat tax rate (4n)
      $bdp[10]  = " " x 4;                                     # shipping vat rate (4n)
      $bdp[11]  = " " x 35;                                    # spaces (35a)
    }

    foreach $var (@bdp) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }
    $outfilestr  .= "\n";
    $outfile2str .= "\n";

    my $printstr = "select from orderdetails where orderid=$orderid  $username\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

    my $dbquerystr = <<"dbEOM";
          select item,quantity,cost,description,unit,customa,customb,customc,customd
          from orderdetails
          where orderid=? 
          and username=?
dbEOM
    my @dbvalues = ( "$orderid", "$username" );
    my @sthdetailsvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $recordcnt = 1;
    for ( my $vali = 0 ; $vali < scalar(@sthdetailsvalarray) ; $vali = $vali + 9 ) {
      ( $item, $quantity, $cost, $descr, $unit, $customa, $customb, $customc, $customd ) = @sthdetailsvalarray[ $vali .. $vali + 8 ];

      my $printstr = "aaaa $item  $quantity  $cost  $descr  $unit\n";
      &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
      $recordcnt++;

      @bdp       = ();
      $bdp[0]    = 'PP1';                                 # product record identifier (3a)
      $recordcnt = substr( "000" . $recordcnt, -3, 3 );
      $bdp[1]    = $recordcnt;                            # product record sequence number (3n)

      my $addtldata = "";
      $item =~ tr/a-z/A-Z/;

      $item = substr( $item . " " x 12, 0, 12 );
      $descr =~ s/[^a-zA-Z0-9 \-\/]//g;
      $descr =~ tr/a-z/A-Z/;
      if ( $card_type eq "mc" ) {
        $quantity = sprintf( "%d", ($quantity) + .0001 );
      } else {
        $quantity = sprintf( "%d", ( $quantity * 10000 ) + .0001 );
      }
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
      $netind = "N";
      $unitcost = sprintf( "%d", ( $cost * 10000 ) + .0001 );

      $discountamt = 0;
      if ( $customa ne "" ) {
        $discountamt = $customa;
        $discountamt = sprintf( "%d", ( $discountamt * 100 ) + .0001 );
      }

      if ( $card_type eq "mc" ) {
        $extcost = ( $unitcost * $quantity / 100 ) - $discountamt;
      } else {
        $extcost = ( $unitcost * $quantity / 1000000 ) - $discountamt;
      }

      # new 04/12/2006
      $extcost = sprintf( "%d", $extcost + .0001 );

      $chkamounts = $chkamounts + $extcost;

      $discountamt = $customa;
      if ( $discountamt ne "" ) {
        $discountamt = sprintf( "%d", ( $discountamt * 100 ) + .0001 );
      }

      $taxrate = 0;
      $taxamt  = $customb;
      if ( $taxamt ne "" ) {
        if ( $taxamt < 0 ) {
          $taxamt = 0 - $taxamt;
        }
        $taxamt = sprintf( "%d", ( $taxamt * 100 ) + .0001 );

        if ( $card_type eq "vi" ) {
          $taxrate = ( $taxamt / $extcost ) * 10000;
        } else {
          $taxrate = ( $taxamt / $extcost ) * 100000;
        }
        $taxrate = sprintf( "%d", $taxrate + .0001 );
      }
      if ( $card_type eq "mc" ) {
        $taxrate = substr( "0" x 5 . $taxrate, -5, 5 );
      } else {
        $taxrate = substr( "0" x 4 . $taxrate, -4, 4 );
      }

      $commoditycode = $customc;
      if ( $commoditycode ne "" ) {
        $commoditycode =~ s/[^a-zA-Z0-9 ]//g;
      }

      if ( $card_type eq "mc" ) {
        $descr         = substr( $descr . " " x 35,         0,   35 );
        $quantity      = substr( "0" x 5 . $quantity,       -5,  5 );
        $unit          = substr( $unit . " " x 3,           0,   3 );
        $taxamt        = substr( "0" x 9 . $taxamt,         -9,  9 );
        $extcost       = substr( "0" x 9 . $extcost,        -9,  9 );
        $discountamt   = substr( "0" x 9 . $discountamt,    -9,  9 );
        $commoditycode = substr( $commoditycode . " " x 12, 0,   12 );
        $unitcost      = substr( "0" x 12 . $unitcost,      -12, 12 );
      } else {
        $descr         = substr( $descr . " " x 26,         0,   26 );
        $quantity      = substr( "0" x 12 . $quantity,      -12, 12 );
        $unit          = substr( $unit . " " x 12,          0,   12 );
        $taxamt        = substr( "0" x 12 . $taxamt,        -12, 12 );
        $extcost       = substr( "0" x 12 . $extcost,       -12, 12 );
        $discountamt   = substr( "0" x 12 . $discountamt,   -12, 12 );
        $commoditycode = substr( $commoditycode . " " x 12, 0,   12 );
        $unitcost      = substr( "0" x 12 . $unitcost,      -12, 12 );
      }

      $mcountry =~ tr/a-z/A-Z/;
      if ( ( $card_type eq "mc" ) && ( $mcountry eq "US" ) || ( $mcountry eq "" ) ) {
        $unitcost      = " " x 12;
        $commoditycode = " " x 12;
      }
      my $printstr = "mcountry: $mcountry $unitcost $commoditycode\n";
      &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

      $bdp[2] = $descr;       # description (35a)
      $bdp[3] = $item;        # product code (12a)
      $bdp[4] = $quantity;    # quantity (5a)
      $bdp[5] = $unit;        # unit of measure (3a)
      $bdp[6] = $taxamt;      # tax amount (9a)
      $bdp[7] = $taxrate;     # tax rate (5a)
      if ( $card_type eq "mc" ) {
        $bdp[8] = " " x 45;    # spaces (28a)
      } else {
        $bdp[8] = " " x 36;    # spaces (36a)
      }

      foreach $var (@bdp) {
        $outfilestr  .= "$var";
        $outfile2str .= "$var";
      }
      $outfilestr  .= "\n";
      $outfile2str .= "\n";

      @bdp       = ();
      $bdp[0]    = 'PP2';                                 # product record identifier (3a)
      $recordcnt = substr( "000" . $recordcnt, -3, 3 );
      $bdp[1]    = $recordcnt;                            # product record sequence number (3n)

      $bdp[2] = $extcost;                                 # line item total amount (9n)
      $bdp[3] = $discountamt;                             # discount amount (9n)
      if ( $card_type eq "mc" ) {
        $bdp[4]      = "N";                               # gross/net indicator item amount does not incl tax (1a)
        $bdp[5]      = "    ";                            # tax type applied (4a)
        $discountind = "N";
        if ( $discountamt > 0 ) {
          $discountind = "Y";
        }
        $bdp[6] = $discountind;                           # discount indicator (1a)
      }
      $bdp[7] = $commoditycode;                           # item commodity code (12a)
      $bdp[8] = $unitcost;                                # unit cost (12n)

      $bdp[9] = " " x 66;                                 # spaces (66a)

      foreach $var (@bdp) {
        $outfilestr  .= "$var";
        $outfile2str .= "$var";
      }
      $outfilestr  .= "\n";
      $outfile2str .= "\n";

    }

  }

  $card_country =~ tr/a-z/A-Z/;
  if ( $card_country eq "" ) {
    $card_country = "US";
  }
  $card_country = substr( $card_country . "  ", 0, 2 );

  $card_zip = substr( $card_zip, 0, 8 );
  if ( ( $operation ne "return" ) && ( $card_country =~ /^(US|CA|GB|UK)$/ ) && ( $card_zip ne "" ) ) {
    @bdab    = ();
    $bdab[0] = 'A';    # constant (1a)
    $bdab[1] = 'B';    # constant (1a)
    if ( ( $card_addr eq "" ) && ( $card_city eq "" ) && ( $card_state eq "" ) ) {
      $zip  = substr( $card_zip . " " x 45,             0, 45 );
      $addr = substr( $zip . $card_country . " " x 118, 0, 118 );
      $bdab[2] = $addr;    # address line (118a)
    } else {
      $card_name =~ s/^(.*) ([^ ]+)$/$1 *$2/;
      $card_name = substr( $card_name . " " x 30, 0, 30 );
      $bdab[2] = $card_name;       # address line zip code (30a)
      $bdab[3] = ' ';              # telephone type (1a)
      $bdab[4] = ' ' x 14;         # telephone number (14a)
      $bdab[5] = $card_country;    # country code (2a)
      $bdab[6] = ' ' x 71;         # reserved (71a)

      foreach $var (@bdab) {
        $outfilestr  .= "$var";
        $outfile2str .= "$var";
      }
      $outfilestr  .= "\n";
      $outfile2str .= "\n";

      my $recnum = 1;
      if ( $card_addr ne "" ) {
        @bdab    = ();
        $bdab[0] = 'A';            # constant (1a)
        $recnum++;
        $bdab[1] = $recnum;        # constant (1a)
        $card_addr =~ s/^ +//g;
        $card_addr = substr( $card_addr . " " x 118, 0, 118 );
        $bdab[2] = $card_addr;     # address line (118a)

        foreach $var (@bdab) {
          $outfilestr  .= "$var";
          $outfile2str .= "$var";
        }
        $outfilestr  .= "\n";
        $outfile2str .= "\n";
      }

      if ( ( $card_city ne "" ) || ( $card_state ne "" ) || ( $card_zip ne "" ) ) {
        @bdab    = ();
        $bdab[0] = 'A';            # constant (1a)
        $recnum++;
        $bdab[1] = $recnum;                            # constant (1a)
        $addr = "$card_city, $card_state $card_zip";
        $addr = substr( $addr . " " x 118, 0, 118 );
        $bdab[2] = $addr;                              # address line (118a)

        foreach $var (@bdab) {
          $outfilestr  .= "$var";
          $outfile2str .= "$var";
        }
        $outfilestr  .= "\n";
        $outfile2str .= "\n";
      }
    }
  }

  if ( ( $card_type eq "ax" ) && ( $commcardtype ne "" ) ) {

    @bdab    = ();
    $bdab[0] = 'A';    # constant (1a)
    $bdab[1] = 'S';    # constant (1a)
    $ship_name =~ s/^(.*) ([^ ]+)$/$1 *$2/;
    $ship_name = substr( $ship_name . " " x 30, 0, 30 );
    $bdab[2] = $ship_name;    # address line zip code (30a)
    $bdab[3] = ' ';           # telephone type (1a)
    $bdab[4] = ' ' x 14;      # telephone number (14a)
    $ship_country =~ tr/a-z/A-Z/;
    $ship_country = substr( $ship_country . "  ", 0, 2 );
    $bdab[5] = $ship_country;    # country code (2a)
    $bdab[6] = ' ' x 71;         # reserved (71a)

    foreach $var (@bdab) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }
    $outfilestr  .= "\n";
    $outfile2str .= "\n";

    $nextext = 2;
    if ( $ship_addr1 ne "" ) {
      @bdab      = ();
      $bdab[0]   = 'A';                                         # constant (1a)
      $bdab[1]   = $nextext;                                    # constant (1a)
      $ship_addr = substr( $ship_addr1 . " " x 118, 0, 118 );
      $bdab[2]   = $ship_addr;                                  # address line (118a)

      foreach $var (@bdab) {
        $outfilestr  .= "$var";
        $outfile2str .= "$var";
      }
      $outfilestr  .= "\n";
      $outfile2str .= "\n";
      $nextext++;
    }

    if ( $ship_addr2 ne "" ) {
      @bdab      = ();
      $bdab[0]   = 'A';                                         # constant (1a)
      $bdab[1]   = $nextext;                                    # constant (1a)
      $ship_addr = substr( $ship_addr2 . " " x 118, 0, 118 );
      $bdab[2]   = $ship_addr;                                  # address line (118a)

      foreach $var (@bdab) {
        $outfilestr  .= "$var";
        $outfile2str .= "$var";
      }
      $outfilestr  .= "\n";
      $outfile2str .= "\n";
      $nextext++;
    }

    @bdab    = ();
    $bdab[0] = 'A';                                             # constant (1a)
    $bdab[1] = $nextext;                                        # constant (1a)
    $addr    = "$ship_city, $ship_state $ship_zip";
    $addr    = substr( $addr . " " x 118, 0, 118 );
    $bdab[2] = $addr;                                           # address line (118a)

    foreach $var (@bdab) {
      $outfilestr  .= "$var";
      $outfile2str .= "$var";
    }
    $outfilestr  .= "\n";
    $outfile2str .= "\n";
  }

}

sub errorchecking {
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

  $clen      = length($cardnumber);
  $cabbrev   = substr( $cardnumber, 0, 4 );
  $card_type = &smpsutils::checkcard($cardnumber);
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
            and $operationstatus='pending'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$errmsg", "$orderid", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

}

sub pidcheck {
  my $chkline = &procutils::fileread( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprodlogs/paytechsalem", "pid.txt" );
  chop $chkline;

  if ( $pidline ne $chkline ) {
    umask 0077;
    $logfilestr = "";
    $logfilestr .= "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $logfilestr .= "$pidline\n";
    $logfilestr .= "$chkline\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/logs/paytechsalem/$fileyear", "$username$time$pid.txt", "append", "", $logfilestr );

    my $printstr = "genfiles.pl already running, pid alterred by another program, exiting...\n";
    $printstr .= "$pidline\n";
    $printstr .= "$chkline\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: paytechsalem - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

