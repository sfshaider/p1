#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use rsautils;
use smpsutils;
use isotables;
use epx;

$devprod = "logs";

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'epx/genfiles.pl $group'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );
  exit;
}

if ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) {
  exit;
}

my @checkinstrarray = &procutils::flagread( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "genfiles.txt" );
$checkuser = $checkinstrarray[0];
chop $checkuser;

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  $checkstring = "";
} else {
  $checkstring = "and t.username>='$checkuser'";
}

#$checkstring = "and t.username='aaaa'";
#$checkstring = "and t.username in ('aaaa','aaaa')";

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

if ( !-e "/home/pay1/batchfiles/$devprod/epx/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/epx/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/epx/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/epx/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/epx/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/epx/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/epx/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/epx/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/epx/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/epx/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: epx - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory epx/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 0;
$file_flag  = 1;

my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        and t.trans_date<=?
        $checkstring
        and t.finalstatus in ('pending','locked')
        and (t.accttype is NULL or t.accttype='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.processor='epx'
        and o.lastoptime>=?
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 3 ) {
  ( $user, $usercount, $usertdate ) = @sthtransvalarray[ $vali .. $vali + 2 ];

  my $printstr = "$user $usercount $usertdate\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );
  @userarray = ( @userarray, $user );
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}

#if (($checkstring ne "") && ($#userarray < 1)) {
#  $chkuser = $checkstring;
#  $chkuser =~ s/^.*\'(.*)\'.*/$1/g;
#  print "$chkuser\n";
#  @userarray = (@userarray,$chkuser);
#}

foreach $username ( sort @userarray ) {
  if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/epx/stopgenfiles.txt" ) ) {

    #unlink "/home/pay1/batchfiles/$devprod/epx/batchfile.txt";
    &procutils::flagwrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "batchfile.txt", "unlink", "", "" );
    last;
  }

  umask 0033;
  $checkinstr = "";
  $checkinstr .= "$username\n";
  &procutils::flagwrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "genfiles.txt", "write", "", $checkinstr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::flagwrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};

  my $printstr = "$username $usercountarray{$username} $starttransdate\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );

  ( $dummy, $today, $time ) = &miscutils::genorderid();

  umask 0077;
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );

  $logfilestr = "";
  $logfilestr .= "$username\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  %errorderid    = ();
  $detailnum     = 0;
  $batchsalesamt = 0;
  $batchsalescnt = 0;
  $batchretamt   = 0;
  $batchretcnt   = 0;
  $batchcnt      = 1;

  my $dbquerystr = <<"dbEOM";
        select c.merchant_id,c.pubsecret,c.proc_type,c.company,c.addr1,c.city,c.state,c.zip,c.tel,c.status,
        e.bankid,e.dbanum,e.industrycode,e.currencies
        from customers c, epx e
        where c.username=?
        and e.username=c.username
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $company, $address, $city, $state, $zip, $tel, $status, $bankid, $dbanum, $industrycode, $currencies ) =
    &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $printstr = "$username $status\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );

  if ( $status ne "live" ) {
    next;
  }

  %currarray = ();
  if ( $currencies ne "" ) {
    (%currarray) = split( /,/, $currencies );
  }

  my $printstr = "aaaa $starttransdate $onemonthsagotime $username\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );

  $batch_flag = 0;
  $netamount  = 0;
  $hashtotal  = 0;
  $batchcnt   = 1;
  $recseqnum  = 0;

  my $dbquerystr = <<"dbEOM";
        select o.orderid,o.amount
        from trans_log t, operation_log o
        where t.trans_date>=?
        and t.username=?
        and t.finalstatus in ('pending')
        and t.operation in ('auth','postauth','return','forceauth')
        and (t.accttype is NULL or t.accttype='' or t.accttype='credit')
        and (t.duplicate is NULL or t.duplicate='')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastop=t.operation
        and o.processor='epx'
        and o.lastop in ('auth','postauth','return','forceauth')
        and (o.voidstatus is NULL or o.voidstatus ='')
        order by substr(o.amount,1,3),o.orderid
dbEOM
  my @dbvalues = ( "$onemonthsago", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  %orderidarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 2 ) {
    ( $orderid, $amount ) = @sthtransvalarray[ $vali .. $vali + 1 ];
    my $curr = substr( $amount, 0, 3 );
    $orderidarray{"$curr $orderid"} = 1;
  }

  foreach $orderid ( sort keys %orderidarray ) {
    ( $curr, $orderid ) = split( / /, $orderid );

    my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,card_exp,amount,auth_code,avs,refnumber,lastopstatus,cvvresp,transflags,origamount,forceauthstatus,
          card_name,card_addr,card_city,card_state,card_zip,card_country
          from operation_log
          where trans_date>=?
          and orderid=?
          and username=?
          and lastoptime>=?
          and lastopstatus in ('pending')
          and lastop IN ('auth','postauth','return','forceauth')
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$starttransdate", "$orderid", "$username", "$onemonthsagotime" );
    ( $orderid,     $operation, $trans_date, $trans_time, $enccardnumber,   $enclength, $exp,       $amount,    $auth_code,  $avs_code, $refnumber,
      $finalstatus, $cvvresp,   $transflags, $origamount, $forceauthstatus, $card_name, $card_addr, $card_city, $card_state, $card_zip, $card_country
    )
      = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/epx/stopgenfiles.txt" ) ) {

      #unlink "/home/pay1/batchfiles/$devprod/epx/batchfile.txt";
      &procutils::flagwrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "batchfile.txt", "unlink", "", "" );
      last;
    }

    if ( ( $proc_type eq "authcapture" ) && ( $operation eq "postauth" ) ) {
      next;
    }

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation\n";
    &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx/$fileyear", "$username$time.txt", "append", "", $logfilestr );

    my $printstr = "$orderid $operation $auth_code $refnumber\n";
    &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "epx", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $card_type = &smpsutils::checkcard($cardnumber);
    if ( $card_type eq "dc" ) {
      $card_type = "mc";
    }

    # xxxx
    #if (($username eq "variousinc3") && ($forceauthstatus ne "") && ($operation eq "postauth")) {
    #  next;
    #}

    $errorflag = &errorchecking();
    my $printstr = "cccc $errorflag\n";
    &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );
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
	    and finalstatus='pending'
	    and username=?
            and (accttype is NULL or accttype='' or accttype='credit')
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
          and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time$batchnum", "$detailnum", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my ($currency) = split( / /, $amount );
    if ( $currarray{"$currency"} ne "" ) {
      $dbanum = $currarray{"$currency"};
    }

    if ( ( $batch_flag == 1 ) && ( $dbanum ne $dbanumold ) ) {
      %errorderid = ();
      $detailnum  = 0;
      $dbanumsav  = $dbanum;
      $dbanum     = $dbanumold;
      &batchtrailer();
      $dbanum = $dbanumsav;

      $response = &sendmessage($message);

      my $printstr = "$response\n";
      &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );
    }

    $batch_flag = 1;
    &batchdetail();

    $response = &sendmessage($message);

    &endbatch($response);

    $dbanumold = $dbanum;
  }

  # xxxx
  if ( $batchcnt > 0 ) {
    %errorderid = ();
    $detailnum  = 0;

    # xxxx temp if commented out
    &batchtrailer();

    $response = &sendmessage($message);

    my $printstr = "$response\n";
    &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );
  }
}

if ( !( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) && !( -e "/home/pay1/batchfiles/$devprod/epx/stopgenfiles.txt" ) ) {
  umask 0033;
  $checkinstr = "";
  &procutils::flagwrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "genfiles.txt", "write", "", $checkinstr );
}

#unlink "/home/pay1/batchfiles/$devprod/epx/batchfile.txt";
&procutils::flagwrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "batchfile.txt", "unlink", "", "" );

exit;

sub endbatch {
  my ($response) = @_;

  print "in endbatch\n";

  $response =~ s/\n/ /g;
  $response =~ s/></>;</g;
  my @tmpfields = split( /;/, $response );
  my %temparray = ();
  my $levelstr  = "";
  foreach my $var (@tmpfields) {
    if ( $var =~ /<(.+)>(.*)</ ) {
      my $var2 = $1;
      my $var3 = $2;
      $var2 =~ s/FIELD KEY=//;
      $var2 =~ s/\"//g;
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

  $respcode = $temparray{'RESPONSE,FIELDS,AUTH_RESP'};
  my $message = $temparray{'RESPONSE,FIELDS,AUTH_RESP_TEXT'};
  $err_msg = "$respcode: $message";
  my $statusid = $temparray{'XML,REQUEST,RESPONSE,ROW,STATUSID'};

  $refnumber = $temparray{'RESPONSE,FIELDS,AUTH_GUID'};

  print "$orderid $operation $respcode  $err_msg\n";

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "orderid   $orderid\n";
  $logfilestr .= "respcode   $respcode\n";
  $logfilestr .= "err_msg   $err_msg\n";
  $logfilestr .= "result   $time$batchnum\n\n\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  my $printstr = "orderid   $orderid\n";
  $printstr .= "transseqnum   $transseqnum\n";
  $printstr .= "respcode   $respcode\n";
  $printstr .= "err_msg   $err_msg\n";
  $printstr .= "result   $time$batchnum\n\n\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  if ( $respcode =~ /^(00|76)$/ ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='success',trans_time=?,refnumber=?
            where orderid=?
            and trans_date>=?
            and result=?
            and username=?
            and finalstatus='locked'
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$refnumber", "$orderid", "$onemonthsago", "$time$batchnum", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    my $printstr = "update operation_log  $orderid  $onemonthsagotime  $operation  $username  $time$batchnum\n";
    &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );

    %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='success',lastopstatus='success',lastoptime=?,refnumber=?
            where orderid=?
            and lastoptime>=?
            and username=?
            and batchfile=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$time", "$refnumber", "$orderid", "$onemonthsagotime", "$username", "$time$batchnum" );
    print "$dbquerystr\n";
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
  } elsif ( ( $respcode =~ /^[0-9]{2}$/ ) || ( $respcode =~ /^(ED|S7)$/ ) || ( $err_msg =~ /\: DECLINE/ ) ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where orderid=?
            and trans_date>=?
            and username=?
            and (accttype is NULL or accttype='' or accttype='credit')
            and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$err_msg", "$orderid", "$onemonthsago", "$username" );
    print "$dbquerystr\n";
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and lastoptime>=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$err_msg", "$orderid", "$onemonthsagotime" );
    print "$dbquerystr\n";
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $operation eq "return" ) {
      open( MAILERR, "| /usr/lib/sendmail -t" );
      print MAILERR "To: barbara\@plugnpay.com\n";
      print MAILERR "From: dcprice\@plugnpay.com\n";
      print MAILERR "Subject: epx - genfiles.pl FAILURE\n";
      print MAILERR "\n";
      print MAILERR "Failed return:\n";
      print MAILERR "username: $username\n";
      print MAILERR "orderid: $orderid\n";
      close MAILERR;
    }

    #open(MAILERR,"| /usr/lib/sendmail -t");
    #print MAILERR "To: cprice\@plugnpay.com\n";
    #print MAILERR "From: dcprice\@plugnpay.com\n";
    #print MAILERR "Subject: epx - FORMAT ERROR\n";
    #print MAILERR "\n";
    #print MAILERR "username: $username\n";
    #print MAILERR "result: format error\n\n";
    #print MAILERR "batchtransdate: $batchtransdate\n";
    #close MAILERR;
  } elsif ( ( $respcode =~ /RR/ ) || ( ( $operation eq "postauth" ) && ( $respcode eq "" ) ) || ( $operation eq "forceauth" ) ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='pending',descr=?
            where orderid=?
            and trans_date>=?
            and username=?
            and (accttype is NULL or accttype='' or accttype='credit')
            and finalstatus='locked'
dbEOM
    my @dbvalues = ( "$err_msg", "$orderid", "$onemonthsago", "$username" );
    print "$dbquerystr\n";
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='pending',lastopstatus='pending',descr=?
            where orderid=?
            and lastoptime>=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$err_msg", "$orderid", "$onemonthsagotime" );
    print "$dbquerystr\n";
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  } elsif ( $respcode eq "PENDING" ) {
  } else {
    my $printstr = "respcode	$respcode unknown\n";
    &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: epx - unknown error\n";
    print MAILERR "\n";
    print MAILERR "username: $username\n";
    print MAILERR "orderid: $orderid\n";
    print MAILERR "result: $respcode\n";
    print MAILERR "file: $username$time.txt\n";
    close MAILERR;

    &miscutils::mysleep(60.0);
  }
  print "done with endbatch\n";
}

sub getbatchnum {
  my $dbquerystr = <<"dbEOM";
          select batchnum
          from epx
          where username=?
dbEOM
  my @dbvalues = ("$username");
  ($batchnum) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = $batchnum + 1;
  if ( $batchnum >= 998 ) {
    $batchnum = 1;
  }

  my $dbquerystr = <<"dbEOM";
          update epx set batchnum=?
          where username=?
dbEOM
  my @dbvalues = ( "$batchnum", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchnum = substr( "0000" . $batchnum, -4, 4 );

}

sub batchtrailer {
  @bt = ();

  #CUST_NBR=9009
  #MERCH_NBR=900912
  #DBA_NBR=1
  #TERMINAL_NBR=1

  #TRAN_NBR=16
  #TRAN_TYPE=CCEZ

  #BATCH_ID=0

  $bt[0] = "<DETAIL CUST_NBR=\"$bankid\" MERCH_NBR=\"$merchant_id\" DBA_NBR=\"$dbanum\" TERMINAL_NBR=\"$terminal_id\">";

  if ( $transflags =~ /moto/ ) {
    $tcode = "CCMZ";
  } elsif ( $industrycode =~ /^(retail|restaurant)$/ ) {
    $tcode = "CCRZ";
  } else {
    $tcode = "CCEZ";
  }
  $bt[1] = "<TRAN_TYPE>$tcode</TRAN_TYPE>";
  $bt[2] = "<BATCH_ID>0</BATCH_ID>";
  $bt[3] = "<TRAN_NBR>0</TRAN_NBR>";

  $bt[4] = "</DETAIL>";

  $message = "";
  my $indent = 0;
  foreach $var (@bt) {
    if ( $var =~ /^<\/.*>/ ) {
      $indent--;
    }
    $message = $message . $var;

    #$message = $message . " " x $indent . $var . "\n";
    if ( ( $var !~ /\// ) && ( $var != /<?/ ) ) {
      $indent++;
    }
    if ( $indent < 0 ) {
      $indent = 0;
    }
  }

}

sub batchdetail {

  $origoperation = "";
  my $dbquerystr = <<"dbEOM";
          select authtime,authstatus,forceauthtime,forceauthstatus
          from operation_log 
          where orderid=? 
          and username=? 
dbEOM
  my @dbvalues = ( "$orderid", "$username" );
  ( $authtime, $authstatus, $forceauthtime, $forceauthstatus ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

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

  if ( $operation eq "postauth" ) {
    if ( $trans_time < 1000 ) {
      umask 0077;
      $logfilestr = "";
      $logfilestr .= "Error in batch detail: couldn't find trans_time $username $twomonthsago $orderid $trans_time\n";
      &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx/$fileyear", "$username$time.txt", "append", "", $logfilestr );
      $dberrorflag = 1;
      return;
    }
  }

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

  $transseqnum = &smpsutils::gettransid( $username, "epx", $orderid );

  @bd = ();

  if ( ( $operation eq "return" ) && ( $origoperation !~ /auth/ ) ) {

    # return from scratch, includes card info
    $bd[1] = "<DETAIL CUST_NBR=\"$bankid\" MERCH_NBR=\"$merchant_id\" DBA_NBR=\"$dbanum\" TERMINAL_NBR=\"$terminal_id\">";

    if ( $transflags =~ /moto/ ) {
      $tcode = "CCM9";
    } elsif ( $industrycode =~ /^(retail|restaurant)$/ ) {
      $tcode = "CCR9";
    } else {
      $tcode = "CCE9";
    }
    $bd[2] = "<TRAN_TYPE>$tcode</TRAN_TYPE>";
    $bd[3] = "<BATCH_ID>$today</BATCH_ID>";
    $transseqnum = sprintf( "%010d", $transseqnum );
    $bd[4] = "<TRAN_NBR>$transseqnum</TRAN_NBR>";

    ( $currency, $amount ) = split( / /, $amount );
    $amount = sprintf( "%.2f", $amount + .0001 );
    $bd[5] = "<AMOUNT>$amount</AMOUNT>";

    $bd[6] = "<ACCOUNT_NBR>$cardnumber</ACCOUNT_NBR>";
    $monthexp = substr( $exp, 0, 2 );
    $yearexp  = substr( $exp, 3, 2 );
    $bd[7]    = "<EXP_DATE>$yearexp$monthexp</EXP_DATE>";
    $bd[8]    = "<CARD_ENT_METH>X</CARD_ENT_METH>";

    my (@names) = split( / +/, $card_name, 3 );
    my $names0  = $names[0];
    my $names1  = $names[1];
    my $names2  = $names[2];

    my $firstname = "";
    my $lastname  = "";
    if ( $names[2] ne "" ) {
      $firstname = "$names0 $names1";
      $lastname  = "$names2";
    } else {
      $firstname = "$names0";
      $lastname  = "$names1";
      if ( $lastname eq "" ) {
        my $len = length($firstname) / 2;
        $lastname = substr( $firstname, $len );
        $firstname = substr( $firstname, 0, $len );
      }
    }
    $firstname = substr( $firstname, 0, 25 );
    $lastname  = substr( $lastname,  0, 25 );

    $bd[9]  = "<FIRST_NAME>$firstname</FIRST_NAME>";
    $bd[10] = "<LAST_NAME>$lastname</LAST_NAME>";
    $card_addr = substr( $card_addr, 0, 30 );
    $bd[11]    = "<ADDRESS>$card_addr</ADDRESS>";
    $bd[12]    = "<CITY>$card_city</CITY>";

    #$bd[13] = "<STATE>$card_state</STATE>";
    $bd[14] = "<ZIP_CODE>$card_zip</ZIP_CODE>";

    $currency =~ tr/a-z/A-Z/;
    if ( $currency ne "USD" ) {
      my $currncy = $isotables::currencyUSD840{$currency};
      $bd[15] = "<CURRENCY_CODE>$currncy</CURRENCY_CODE>";
    }

    $bd[16] = "</DETAIL>";
  } elsif ( $operation eq "return" ) {
    $bd[1] = "<DETAIL CUST_NBR=\"$bankid\" MERCH_NBR=\"$merchant_id\" DBA_NBR=\"$dbanum\" TERMINAL_NBR=\"$terminal_id\">";

    if ( $transflags =~ /moto/ ) {
      $tcode = "CCM9";
    } elsif ( $industrycode =~ /^(retail|restaurant)$/ ) {
      $tcode = "CCR9";
    } else {
      $tcode = "CCE9";
    }
    $bd[2] = "<TRAN_TYPE>$tcode</TRAN_TYPE>";
    $bd[3] = "<BATCH_ID>$today</BATCH_ID>";
    $transseqnum = sprintf( "%010d", $transseqnum );
    $bd[4] = "<TRAN_NBR>$transseqnum</TRAN_NBR>";

    $refnumber =~ s/ //g;
    $bd[5] = "<ORIG_AUTH_GUID>$refnumber</ORIG_AUTH_GUID>";
    $bd[6] = "<CARD_ENT_METH>Z</CARD_ENT_METH>";

    #my $origtransseqnum = substr($auth_code,6,10);
    #$origtransseqnum =~ s/ //g;
    #if ($origtransseqnum ne "") {
    #  $bd[6] = "<ORIG_BATCH_ID>$trans_date</ORIG_AUTH_GUID>";
    #  $bd[7] = "<ORIG_TRAN_NBR>$origtransseqnum</ORIG_TRAN_NBR>";
    #}

    ( $currency, $amount ) = split( / /, $amount );
    $amount = sprintf( "%.2f", $amount + .0001 );
    $bd[8] = "<AMOUNT>$amount</AMOUNT>";

    $currency =~ tr/a-z/A-Z/;
    if ( $currency ne "USD" ) {
      my $currncy = $isotables::currencyUSD840{$currency};
      $bd[9] = "<CURRENCY_CODE>$currncy</CURRENCY_CODE>";
    }

    $bd[11] = "</DETAIL>";
  } else {
    $bd[1] = "<DETAIL CUST_NBR=\"$bankid\" MERCH_NBR=\"$merchant_id\" DBA_NBR=\"$dbanum\" TERMINAL_NBR=\"$terminal_id\">";

    my $tcode = "";
    if ( $transflags =~ /moto/ ) {
      $tcode = "CCM4";
    } elsif ( $industrycode =~ /^(retail|restaurant)$/ ) {
      $tcode = "CCR4";
    } else {
      $tcode = "CCE4";
    }
    $bd[2] = "<TRAN_TYPE>$tcode</TRAN_TYPE>";

    if ( ( $origoperation eq "forceauth" ) && ( $operation eq "postauth" ) ) {
      $bd[3] = "<ACCOUNT_NBR>$cardnumber</ACCOUNT_NBR>";
      $expdate = substr( $exp, 3, 2 ) . substr( $exp, 0, 2 );
      $bd[4]   = "<EXP_DATE>$expdate</EXP_DATE>";
      $bd[5]   = "<CARD_ENT_METH>X</CARD_ENT_METH>";
      $auth_code = substr( $auth_code . " " x 6, 0, 6 );
      $bd[6] = "<AUTH_CODE>$auth_code</AUTH_CODE>";
    } else {
      $refnumber =~ s/ //g;
      $bd[3] = "<ORIG_AUTH_GUID>$refnumber</ORIG_AUTH_GUID>";
      $bd[4] = "<CARD_ENT_METH>Z</CARD_ENT_METH>";
    }

    $bd[8] = "<BATCH_ID>$today</BATCH_ID>";

    $transseqnum = sprintf( "%010d", $transseqnum );
    $bd[9] = "<TRAN_NBR>$transseqnum</TRAN_NBR>";

    ( $currency, $amount ) = split( / /, $amount );
    $amount = sprintf( "%.2f", $amount + .0001 );
    $bd[10] = "<AMOUNT>$amount</AMOUNT>";

    $currency =~ tr/a-z/A-Z/;
    if ( $currency ne "USD" ) {
      my $currncy = $isotables::currencyUSD840{$currency};
      $bd[11] = "<CURRENCY_CODE>$currncy</CURRENCY_CODE>";
    }

    $tax = substr( $auth_code, 71, 12 );
    $tax = sprintf( "%.2f", $tax + .0001 );
    if ( $tax > 0.0 ) {
      $bd[12] = "<TAX_AMT>$tax</TAX_AMT>";
    }

    $gratuity = substr( $auth_code, 59, 12 );
    $gratuity = sprintf( "%.2f", $gratuity + .0001 );
    if ( $gratuity > 0.0 ) {
      $bd[13] = "<TIP_AMT>$gratuity</TIP_AMT>";
    }

    $ponumber = substr( $auth_code, 83, 25 );
    $ponumber =~ s/ //g;
    if ( $ponumber ne "" ) {
      $bd[14] = "<INVOICE_NBR>$ponumber</INVOICE_NBR>";
    }

    #$bd[10] = "<ADDRESS>$epx::datainfo{'card-address'}</ADDRESS>";
    #$bd[11] = "<ZIP_CODE>$epx::datainfo{'card-zip'}</ZIP_CODE>";

    $bd[15] = "</DETAIL>";
  }

  $message = "";
  my $indent = 0;
  foreach $var (@bd) {
    if ( $var =~ /^<\/.*>/ ) {
      $indent--;
    }
    if ( $var !~ /></ ) {
      $message = $message . $var;
    }

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
  my $printstr = "$temp\n";
  ($message2) = unpack "H*", $printmessage;
  $printstr .= "$message2\n\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );

  $message1 = $printmessage;
  $message1 =~ s/\x1c/\[1c\]/g;
  $message1 =~ s/\x1e/\[1e\]/g;
  $message1 =~ s/\x03/\[03\]\n/g;

  #print "$message1\n$message2\n\n";
}

sub sendmessage {
  my ($msg) = @_;

  my $host = "secure.epx.com";

  #$host = "216.4.52.205";

  my $dnserror = "";
  my $dest_ip  = gethostbyname($host);
  if ( $dest_ip eq "" ) {
    $host     = "66.116.108.137";
    $dnserror = " dns error";
  }

  if ( $username eq "testepx" ) {
    $host = "secure.epxuap.com";
  }

  my $port = "8086";
  my $path = "/webTrans.aspx";

  $mytime = gmtime( time() );
  my $chkmessage = $msg;
  if ( ( length($cardnumber) >= 13 ) && ( length($cardnumber) <= 19 ) ) {
    $xs = "x" x length($cardnumber);
    $chkmessage =~ s/$cardnumber/$xs/;
  }
  $chkmessage =~ s/\>\</\>\n\</g;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username  $orderid\n";
  $logfilestr .= "$host:$path  $port$dnserror\n";
  $logfilestr .= "$mytime send: $chkmessage\n\n";
  $logfilestr .= "sequencenum: $sequencenum retries: $retries\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx/$fileyear", "$username$time.txt", "append", "", $logfilestr );

  my $printstr = "$mytime send: msg\n\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx", "miscdebug.txt", "append", "misc", $printstr );

  #my $scriptstr = "";
  #$scriptstr .= "$orderid  $operation  $transflags\n";
  #$scriptstr .= "$mytime send:\n\n$chkmessage\n\n";
  #&procutils::filewrite("$epx::username","epx","/home/pay1/batchfiles/$devprod/epx","scriptresults.txt","append","",$scriptstr);

  my $len = length($msg);

  my %sslheaders = ();
  $sslheaders{'Host'}           = "$host:$port";
  $sslheaders{'Accept'}         = "*/*";
  $sslheaders{'Content-Type'}   = 'application/x-www-form-urlencoded';
  $sslheaders{'Content-Length'} = $len;
  my ($response) = &procutils::sendsslmsg( "epx", $host, $port, $path, $msg, "noshutdown,nopost,noheaders,http10,got=<\/RESPONSE>", %sslheaders );

  $mytime = gmtime( time() );
  my $chkmessage = $response;
  $chkmessage =~ s/\>\</\>\n\</g;
  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username  $orderid\n";
  $logfilestr .= "$mytime recv: $chkmessage\n\n";
  my $printstr = "$mytime recv: msg\n\n";
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx",           "miscdebug.txt",      "append", "misc", $printstr );
  &procutils::filewrite( "$username", "epx", "/home/pay1/batchfiles/$devprod/epx/$fileyear", "$username$time.txt", "append", "",     $logfilestr );

  #my $scriptstr = "";
  #$scriptstr .= "$mytime recv:\n\n$chkmessage\n\n";
  #&procutils::filewrite("$epx::username","epx","/home/pay1/batchfiles/$devprod/epx","scriptresults.txt","append","",$scriptstr);

  return $response;
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

  if ( ( $username ne "testepx" ) && ( $cardnumber eq "4111111111111111" ) ) {
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

sub errormsg {
  my ( $username, $orderid, $operation, $errmsg ) = @_;

  my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where orderid=?
            and trans_date>=?
            and username=?
            and finalstatus='pending'
            and (accttype is NULL or accttype='' or accttype='credit')
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
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
  my @dbvalues = ( "$errmsg", "$orderid", "$username", "$onemonthsagotime" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

}

