#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use procutils;
use rsautils;
use smpsutils;

# With paymentdata you can only do one file per day

$devprod     = "prod";
$devprodlogs = "logs";

#$checkstring = " and username='testpdata'";

# xxxx
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 18 ) );
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

if ( !-e "/home/pay1/batchfiles/$devprodlogs/paymentdata/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprodlogs/paymentdata/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprodlogs/paymentdata/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprodlogs/paymentdata/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprodlogs/paymentdata/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprodlogs/paymentdata/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprodlogs/paymentdata/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprodlogs/paymentdata/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprodlogs/paymentdata/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprodlogs/paymentdata/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: paymentdata - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory paymentdata/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$filename = "$ttime";
$batchid  = $batchorderid;

umask 0077;
$outfilestr  = "";
$outfile2str = "";

if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
  unlink "/home/pay1/batchfiles/$devprodlogs/paymentdata/batchfile.txt";
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'paymentdata/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: paymentdata - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

$batch_flag = 1;
$file_flag  = 1;
$errorflag  = 0;

#my $sthbatch = $dbh->prepare(qq{
#      select distinct filename
#      from batchfilespdata
#      where trans_date>='$yesterday'
#      and status='locked'
#      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
#$sthbatch->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
#($chkfilename) = $sthbatch->fetchrow;
#$sthbatch->finish;

#if ($chkfilename ne "") {
#  print "have not received a results file for $chkfilename, exiting...\n";
#
#  open(MAILERR,"| /usr/lib/sendmail -t");
#  print MAILERR "To: cprice\@plugnpay.com\n";
#  print MAILERR "From: dcprice\@plugnpay.com\n";
#  print MAILERR "Subject: paymentdata - genfiles failure\n";
#  print MAILERR "\n";
#  print MAILERR "Exiting out of genfiles.pl because we have not received a results\n";
#  print MAILERR "file for $chkfilename\n\n";
#  close MAILERR;
#
#  exit;
#}

#local $sthpnp = $dbh->prepare(qq{
#        select enccardnumber,length
#        from paymentdata
#        where username='pnppaymentdatamstr'
#        }) or die __LINE__ . __FILE__ . "Can't prepare: $DBI::errstr";
#$sthpnp->execute or die __LINE__ . __FILE__ . "Can't execute: $DBI::errstr";
#($enccardnumber,$length) = $sthpnp->fetchrow;
#$sthpnp->finish;

#$cardnumber = &rsautils::rsa_decrypt_file($enccardnumber,$length,"print enccardnumber 497","/home/pay1/pwfiles/keys/key");
#($pnproutenum,$pnpacctnum) = split(/ /,$cardnumber);

#$pnproutenum = "061211168";
#$pnpacctnum = "815700";

# new info 11/07/2003  also need to change pnppaymentdatamstr
$pnproutenum = "091408598";
$pnpacctnum  = "1701352547";

my $printstr = "aaaa $twomonthsago $today\n";
&procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );

# xxxx
#and username='pnppaymentdatamstr'
#select distinct username
#from operation_log
#where trans_date>='$twomonthsago'
#$checkstring
#and trans_date<='$today'
#and processor='paymentdata'
#and lastopstatus='pending'
#and accttype in ('checking','savings')
my $dbquerystr = <<"dbEOM";
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        $checkstring
        and t.finalstatus='pending'
        and t.accttype in ('checking','savings')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.trans_date>=?
        and o.lastopstatus='pending'
        and o.processor='paymentdata'
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$twomonthsago" );
my @sthvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthvalarray) ; $vali = $vali + 3 ) {
  ( $username, $count, $starttransdate ) = @sthvalarray[ $vali .. $vali + 2 ];

  # xxxx
  @userarray = ( @userarray, $username );
  my $printstr = "bbbb $username\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );
  if (0) {

    my $dbquerystr = <<"dbEOM";
        select status
        from paymentdata
        where username=?
dbEOM
    my @dbvalues = ("$username");
    ($chkstatus) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    if ( $chkstatus eq "enabled" ) {
      my $printstr = "b: $username\n";
      &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );
      @userarray = ( @userarray, $username );
    }
  }
}

@oparray = ( 'postauth', 'return' );

foreach $username (@userarray) {
  if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
    unlink "/home/pay1/batchfiles/$devprodlogs/paymentdata/batchfile.txt";
    last;
  }

  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprodlogs/paymentdata", "genfiles.txt", "write", "", $batchfilestr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprodlogs/paymentdata", "batchfile.txt", "write", "", $batchfilestr );

  %checkdup = ();

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,company
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $chkstatus, $mcompany ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $printstr = "aaaa\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );
  if ( $chkstatus ne "live" ) {
    next;
  }

  my $printstr = "bbbb\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );

  # xxxx
  my $dbquerystr = <<"dbEOM";
        select merchantnum,status,seccodes
        from paymentdata
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchantnum, $chkstatus, $seccodes ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $chkstatus ne "enabled" ) {
    next;
  }

  #my %seccodearray = ();
  #my @values = split(/,/,$seccodes);
  #foreach my $seccode (@values) {
  #  $seccodearray{$seccode} = 1;
  #}

  #$cardnumber = &rsautils::rsa_decrypt_file($enccardnumber,$length,"print enccardnumber 497","/home/pay1/pwfiles/keys/key");
  #($merchroutenum,$merchacctnum) = split(/ /,$cardnumber);

  #$rlen = length($merchroutenum);
  #$alen = length($merchacctnum);
  #print "v: $rlen $alen\n";

  #  if (($rlen != 9) || ($alen < 2)) {
  #    next;
  #  }
  #print "v: $rlen $alen\n";

  #$filename++;

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "\n$username\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprodlogs/paymentdata/$fileyear", "t$filename.txt", "append", "", $logfilestr );

  my $printstr = "cccc $username\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );

  my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,enccardnumber,length,amount,
                 auth_code,avs,refnumber,lastopstatus,transflags,accttype,
		 card_name,card_addr,card_city,card_state,card_zip,card_country,
                 authtime,returntime
          from operation_log
          where trans_date>=?
          and trans_date<=?   
          and username=? 
          and lastop in ('postauth','return')
          and lastopstatus in ('pending') 
          and (voidstatus is NULL or voidstatus ='')
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$twomonthsago", "$today", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 21 ) {
    ( $orderid,    $operation, $trans_date, $trans_time, $enccardnumber, $length,     $amount,   $auth_code,    $avs_code, $refnumber, $finalstatus,
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
    if ( ( $orderid eq $orderidold ) || ( $finalstatus ne "pending" ) ) {
      $orderidold = $orderid;
      next;
    }

    if ( $checkdup{"$operation $orderid"} == 1 ) {
      next;
    }
    $checkdup{"$operation $orderid"} = 1;

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "paymentdata", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );
    ( $routenum, $acctnum ) = split( / /, $cardnumber );

    $errflag = &errorchecking();
    if ( $errflag == 1 ) {
      my $printstr = "cardnumber failed error checking\n";
      &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );
      next;
    }
    my $printstr = "aaaa$username $orderid $operation $op\n";
    &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation ";
    &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprodlogs/paymentdata/$fileyear", "t$filename.txt", "append", "", $logfilestr );

    $transamt = substr( $amount, 4 );
    $transamt = sprintf( "%.2f", $transamt + .0001 );
    my $printstr = "transamt: $transamt\n";
    &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );

    &batchdetail( $routenum, $acctnum, $orderid, $card_name, $transamt, $tcode );

  }

  #&procutils::filewrite("$username","paymentdata","/home/pay1/batchfiles/$devprodlogs/paymentdata/$fileyear","t$filename.txt","append","",$logfilestr);

}

&procutils::fileencwrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprodlogs/paymentdata/$fileyear", "$filename", "write", "", $outfilestr );
&procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprodlogs/paymentdata/$fileyear", "$filename.txt", "write", "", $outfile2str );

unlink "/home/pay1/batchfiles/$devprodlogs/paymentdata/batchfile.txt";

umask 0033;
$batchfilestr = "";
&procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprodlogs/paymentdata", "genfiles.txt", "write", "", $batchfilestr );

system("/home/pay1/batchfiles/$devprod/paymentdata/putfiles.pl");

exit;

sub errorchecking {
  my $errmsg = "";

  if ( $acctnum =~ /[^0-9]/ ) {
    $errmsg = "Account number can only contain numbers";
  } elsif ( $routenum =~ /[^0-9]/ ) {
    $errmsg = "Route number can only contain numbers";
  }

  $mod10 = &miscutils::mod10($cardnumber);
  if ( $mod10 ne "success" ) {
    $errmsg = "route number failed mod10 check";
  }

  # check for bad card numbers
  $mylen = length($cardnumber);
  my $printstr = "$mylen  $cardnumber\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/devlogs/paymentdata", "miscdebug.txt", "append", "misc", $printstr );
  if ( ( $mylen > 1024 ) || ( $mylen < 12 ) ) {
    $errmsg = "could not decrypt";
  } elsif ( ( $mylen < 11 ) || ( $mylen > 27 ) ) {
    $errmsg = "bad account length";
  }

  # check for 0 amount
  if ( $amount eq "usd 0.00" ) {
    $errmsg = "amount = 0.00";
  }

  if ( $errmsg ne "" ) {
    my $dbquerystr = <<"dbEOM";
            update trans_log set finalstatus='problem',descr=?
            where username=?
            and orderid=?
            and finalstatus='pending'
	    and accttype in ('checking','savings')
dbEOM
    my @dbvalues = ( "$errmsg", "$username", "$orderid" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    %datainfo        = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
    my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
            where orderid=?
            and username=?
            and $operationstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
	    and accttype in ('checking','savings')
dbEOM
    my @dbvalues = ( "$errmsg", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    return 1;
  }

  return 0;
}

sub batchdetail {
  my ( $routenum, $acctnum, $orderid, $card_name, $transamt, $tcode ) = @_;

  $batchdetreccnt++;
  $filedetreccnt++;
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;

  $recseqnum = substr( "0" x 7 . $recseqnum, -7, 7 );
  $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );

  if ( $tcode =~ /^(27|37)$/ ) {
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
  $batchtotcnt = $batchtotcnt + 1;
  $filetotamt  = $filetotamt + $transamt;

  #  $amt = sprintf("%.2f", ($transamt / 100) + .0001);

#local $sthpaymentdata = $dbh2->prepare(qq{
#      insert into paymentdatadetails
#	(username,filename,batchid,orderid,fileid,batchnum,detailnum,operation,amount,descr,trans_date,status,transfee,step,trans_time)
#        values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
#        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
#  $sthpaymentdata->execute("$username","$filename","$batchid","$orderid","$fileid","$batchnum","$recseqnum","$operation","$amt","$operation","$today","pending","$feerate","one","$todaytime") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
#  $sthpaymentdata->finish;

  @bd      = ();
  $bd[0]   = $merchantnum;                 # origin id (10a)
                                           #$originname = "PLUGnPAY";
  $company = substr( $mcompany, 0, 23 );
  $company =~ s/,//g;
  $bd[1] = $company;                       # origin name (23a)
                                           #$mid = substr($merchantnum . " " x 10,0,10);
  $bd[2] = $merchantnum;                   # batch id (10a)
                                           #$company = substr($mcompany . " " x 10,0,10);
  $marketdata = substr( $auth_code, 61, 20 );
  $marketdata =~ s/ //g;
  $marketdata =~ tr/a-z/A-Z/;
  $bd[3] = $marketdata;                    # batch name (32a)

  $seccode = substr( $auth_code, 6, 3 );
  $seccode =~ tr/a-z/A-Z/;
  if ( $seccode eq "" ) {
    $seccode = "PPD";
  }
  if ( $operation eq "return" ) {
    $seccode = "PPD";
  }
  $bd[4] = $seccode;                       # sec code (3a)

  $bd[5] = "PAYMENT";                      # description (10a)

  if ( $returntime ne "" ) {
    $ltime = &miscutils::strtotime($returntime);
  } else {
    $ltime = &miscutils::strtotime($authtime);
  }
  if ( $ltime ne "" ) {
    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($ltime);
    $year = $year + 1900;
    $trantime = sprintf( "%04d%02d%02d%02d%02d%02d", $year, $month + 1, $day, $hour, $min, $sec );
  }

  #else {
  #  $trantime = substr($trans_time,2,12);
  #}
  $ldate = substr( $trantime, 2, 6 );
  $bd[6] = $ldate;    # effective date (6a) YYMMDD
                      #$refnumber = &gettransid($username);
  $refnumber = &smpsutils::gettransid( $username, "paymentdata", $orderid );
  $refnumber = substr( "0" x 15 . $refnumber, -15, 15 );
  $bd[7] = $refnumber;    # customer id (15a)

  $card_name =~ s/[^a-zA-Z0-9 \.]//g;

  #$card_name = substr($card_name . " " x 15,0,15);
  $bd[8] = $card_name;    # name (15a)

  #$routenum = substr($routenum . " " x 9,0,9);
  $bd[9]  = $routenum;    # bank aba (9n or 80a)
  $bd[10] = $acctnum;     # bank account (17a)

  if ( ( $operation eq "return" ) && ( $accttype eq "savings" ) ) {
    $tcode = "32";
  } elsif ( $operation eq "return" ) {
    $tcode = "22";
  } elsif ( ( $operation eq "postauth" ) && ( $accttype eq "savings" ) ) {
    $tcode = "37";
  } elsif ( $operation eq "postauth" ) {
    $tcode = "27";
  }
  $bd[11] = $tcode;       # transaction code (2a)

  $transamt = substr( $amount, 4 );
  $transamt = sprintf( "%.2f", $transamt + .0001 );
  $transamt = substr( "0" x 10 . $transamt, -10, 10 );
  $bd[12] = $transamt;    # amount (10n)

  $oid = substr( $orderid, -20, 20 );

  #$oid = substr($oid . " " x 20,0,20);
  $bd[13] = $oid;         # optional (20n)
  $bd[14] = "  ";         # optional (2n)

  $message  = "";
  $message2 = "";
  $myi      = 0;
  foreach $var (@bd) {
    $message = $message . $var . ",";
    if ( ( $myi == 9 ) || ( $myi == 10 ) ) {
      $var =~ s/./x/g;
    }
    $message2 = $message2 . $var . ",";
    $myi++;
  }
  chop $message;
  chop $message2;
  $outfilestr  .= "$message\n";
  $outfile2str .= "$message2\n";

  my $dbquerystr = <<"dbEOM";
        insert into batchfilespdata
	(username,merchantnum,filename,trans_date,orderid,status,refnumber,operation,shacardnumber,amount)
        values (?,?,?,?,?,?,?,?,?,?)
dbEOM
  my %inserthash = (
    "username", "$username", "merchantnum", "$merchantnum", "filename",  "$filename",  "trans_date",    "$today",         "orderid", "$orderid",
    "status",   "pending",   "refnumber",   "$refnumber",   "operation", "$operation", "shacardnumber", "$shacardnumber", "amount",  "$transamt"
  );
  &procutils::dbinsert( $username, $orderid, "pnpmisc", "batchfilespdata", %inserthash );

  my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='locked',result=?,refnumber=?,trans_time=?
	  where orderid=?
	  and username=?
	  and operation>=?
	  and finalstatus='pending'
	  and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$batchid", "$refnumber", "$todaytime", "$orderid", "$username", "$operation" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";
  my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='locked',$operationtime=?,lastopstatus='locked',
                 batchfile=?,batchstatus='pending',refnumber=?,lastoptime=?
          where orderid=?
          and username=?
          and $operationstatus in ('pending')
          and (voidstatus is NULL or voidstatus ='')
	  and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$todaytime", "$batchid", "$refnumber", "$todaytime", "$orderid", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

}

