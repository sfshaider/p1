#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use procutils;
use rsautils;
use isotables;
use smpsutils;
use Math::BigInt;
use Math::BigFloat;

$devprod     = "prod";
$devprodlogs = "logs";

$batchsalesamt = Math::BigInt->new(0);
$batchretamt   = Math::BigInt->new(0);
$filesalesamt  = Math::BigInt->new(0);
$fileretamt    = Math::BigInt->new(0);

#$checkstring = "and t.username IN ('jncbnation') ";
#$checkstring = " and t.username<>'flowjmd' ";
$checkstring = "and t.username not IN ('flowjmd','xjncbnation') ";

if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'ncb/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: ncb - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 14 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
my $printstr = "two months ago: $twomonthsago\n";
&procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );
( $dummy, $today, $todaytime ) = &miscutils::genorderid();

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime( time() );
$todaylocal = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/logs/ncb/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/ncb/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/logs/ncb/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/logs/ncb/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/ncb/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/logs/ncb/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/logs/ncb/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/logs/ncb/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/logs/ncb/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/logs/ncb/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: ncb - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Batch program terminated unsuccessfully.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;
$errorflag  = 0;

# xxxx
#my $checkstring = "and t.username='ncbjamaica1'";

my $dbquerystr = <<"dbEOM";
        select t.username,min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>=?
        and t.trans_date<=?
        $checkstring
        and t.finalstatus='pending'
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastoptime>=?
        and o.lastopstatus='pending'
        and (o.voidstatus is NULL or o.voidstatus ='')
        and o.processor='ncb'
        group by t.username
dbEOM
my @dbvalues = ( "$onemonthsago", "$today", "$onemonthsagotime" );
my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 2 ) {
  ( $user, $tdate ) = @sthtransvalarray[ $vali .. $vali + 1 ];

  @userarray = ( @userarray, $user );
  $starttdatearray{$user} = $tdate;
  my $printstr = "$user $tdate\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
}

foreach $username (@userarray) {
  if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
    unlink "/home/pay1/batchfiles/$devprodlogs/ncb/batchfile.txt";
    last;
  }
  my $printstr = "$username\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprodlogs/ncb", "genfiles.txt", "write", "", $batchfilestr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$username\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprodlogs/ncb", "batchfile.txt", "write", "", $batchfilestr );

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  my $fileyear = substr( $todaytime, 0, 4 ) . "/" . substr( $todaytime, 4, 2 ) . "/" . substr( $todaytime, 6, 2 );
  my $fileyymmdd = substr( $todaytime, 0, 8 );
  &checkdir($fileyymmdd);

  umask 0077;
  $logfilestr = "";
  $logfilestr .= "$username\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$todaytime.txt", "append", "", $logfilestr );

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,currency,company,city,country,zip
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $merchant_id, $terminal_id, $proc_type, $status, $mcurrency, $mcompany, $mcity, $mcountry, $mzip ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $printstr = "aaaa $username $status\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  if ( $status ne "live" ) {
    next;
  }
  my $printstr = "bbbb\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  $midarray{"$username"} = $merchant_id;

  my $dbquerystr = <<"dbEOM";
        select bankid,categorycode
        from ncb
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $bankid, $categorycode ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $bankid = "019995";

  my $dbquerystr = <<"dbEOM";
        select o.orderid,o.lastop,o.trans_date,o.lastoptime,o.enccardnumber,o.length,o.amount,o.auth_code,o.avs,o.transflags,o.lastopstatus,o.card_exp,o.origamount
        from trans_log t, operation_log o
        where t.trans_date>=?
        and t.username=?
        and t.finalstatus in ('pending')
        and t.operation in ('postauth','return')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastop=t.operation
        and o.processor='ncb'
        and o.lastop in ('postauth','return')
        and o.lastopstatus in ('pending')
        and (o.accttype is NULL or o.accttype='' or o.accttype='credit')
        and (o.voidstatus is NULL or o.voidstatus ='')
        order by substr(o.amount,1,3),o.orderid
dbEOM
  my @dbvalues = ( "$onemonthsago", "$username" );
  my @sthtransvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthtransvalarray) ; $vali = $vali + 13 ) {
    ( $orderid, $operation, $trans_date, $trans_time, $enccardnumber, $enclength, $amount, $auth_code, $avs_code, $transflags, $finalstatus, $cardexp, $origamount ) =
      @sthtransvalarray[ $vali .. $vali + 12 ];

    if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
      unlink "/home/pay1/batchfiles/$devprodlogs/ncb/batchfile.txt";
      last;
    }

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "ncb", $enccardnumber );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $enclength, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $errflag = &errorchecking();
    if ( $errflag == 1 ) {
      next;
    }

    my $fileyear = substr( $todaytime, 0, 4 ) . "/" . substr( $todaytime, 4, 2 ) . "/" . substr( $todaytime, 6, 2 );
    my $fileyymmdd = substr( $todaytime, 0, 8 );
    &checkdir($fileyymmdd);

    umask 0077;
    $logfilestr = "";
    $logfilestr .= "$orderid $operation $amount  old: $currencyold\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$todaytime.txt", "append", "", $logfilestr );

    $chkcurrency = substr( $amount, 0, 3 );

    if ( ( ( $username ne $usernameold ) || ( $chkcurrency ne $currencyold ) ) && ( $batch_flag == 0 ) ) {
      &batchtrailer();
      $batch_flag = 1;
    }

    # xxxx all transactions in one batch
    #if (($banknum ne $banknumold) && ($file_flag == 0)) {
    #  &filetrailer();
    #  $file_flag = 1;
    #}

    if ( $file_flag == 1 ) {
      &fileheader();
    }
    my $printstr = "gggg\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

    if ( $batch_flag == 1 ) {
      &batchheader();
    }

    $batchreccnt++;
    $filereccnt++;
    $recseqnum++;
    my $printstr = "hhhh\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

    my $dbquerystr = <<"dbEOM";
        update trans_log set finalstatus='success',result=?
	where orderid=?
	and username=?
	and trans_date>=?
	and finalstatus='pending'
        and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$filename", "$orderid", "$username", "$twomonthsago" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='success',lastopstatus='success',batchfile=?,batchnum=?,detailnum=?,batchinfo=?,batchstatus='pending'
          where orderid=?
          and username=?
          and $operationstatus='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
dbEOM
    my @dbvalues = ( "$filename", "$batchnum", "$recseqnum", "$batchheader", "$orderid", "$username" );
    &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    # commented out for test only
    my $shortbatchheader = substr( $batchheader, 0, 80 );
    my $dbquerystr = <<"dbEOM";
        insert into batchfilesncb
	(username,banknum,filename,batchnum,batchheader,trans_date,orderid,status,detailnum)
        values (?,?,?,?,?,?,?,?,?)
dbEOM
    my %inserthash = (
      "username",   "$username", "banknum", "$banknum", "filename", "$filename", "batchnum",  "$batchnum", "batchheader", "$shortbatchheader",
      "trans_date", "$today",    "orderid", "$orderid", "status",   "pending",   "detailnum", "$recseqnum"
    );
    &procutils::dbinsert( $username, $orderid, "pnpmisc", "batchfilesncb", %inserthash );

    &batchdetail();

    if ( $transseqnum >= 998 ) {
      &batchtrailer();
      $batch_flag = 1;
    }

    if ( $batchcount >= 998 ) {
      &filetrailer();
      $file_flag = 1;
    }

    $banknumold  = $banknum;
    $usernameold = $username;
    $currencyold = $chkcurrency;

  }

}

if ( $batch_flag == 0 ) {
  &batchtrailer();
  $batch_flag = 1;
}

if ( $file_flag == 0 ) {
  &filetrailer();
  $file_flag = 1;
}

unlink "/home/pay1/batchfiles/$devprodlogs/ncb/batchfile.txt";

umask 0033;
$batchfilestr = "";
&procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprodlogs/ncb", "genfiles.txt", "write", "", $batchfilestr );

# use this for test only
if (0) {
  my $logdir  = "/home/pay1/batchfiles/logs/ncb/$fileyear";
  my $file2   = $filename . "rep";
  my @files   = ( "$filename", "$file2" );
  my $message = "";
  foreach (@files) {
    $message .= $_ . "\n";
    $message .= `uuencode $logdir/$_ $_`;
  }
  my $email = "CrossleyAG\@JNCB.com";

  open( 'MAIL', "| /usr/lib/sendmail -t" );
  print MAIL "To: " . $email . "\n";
  print MAIL "Cc:nodenterpriseuat\@jncb.com\n";
  print MAIL "Bcc:dprice\@plugnpay.com\n";
  print MAIL "From: support\@plugnpay.com\n";
  print MAIL "Subject: Requested Files\n";
  print MAIL "\n";
  print MAIL "$message\n";
  close('MAIL');
}

system("/home/pay1/batchfiles/$devprod/ncb/putfiles.pl >> /home/pay1/batchfiles/$devprodlogs/ncb/ftplog.txt 2>\&1");

exit;

sub batchheader {
  my $printstr = "batchheader\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  $batch_flag = 0;

  $batchcount++;
  $netamount = 0;
  $netcount  = 0;

  #local $sthinfo = $dbh->prepare(qq{
  #        select batchid
  #        from ncb
  #        where username='$username'
  #        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  #$sthinfo->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
  #($batchnum) = $sthinfo->fetchrow;
  #$sthinfo->finish;

  #$batchnum = $batchnum + 1;
  #if ($batchnum >= 9999) {
  #  $batchnum = 1;
  #}

  #local $sthinfo = $dbh->prepare(qq{
  #        update ncb set batchid=?
  #	  where username='$username'
  #          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  #  $sthinfo->execute("$batchnum") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
  #  $sthinfo->finish;

  $batchreccnt = 1;
  $filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );
  $batchdate = $createdate;
  $batchdate = substr( $batchdate . " " x 6, 0, 6 );
  $batchtime = $createtime;
  $batchtime = substr( $batchtime . " " x 6, 0, 6 );

  @bh        = ();
  $bh[0]     = "BH";                                     # record id
  $batchnum  = substr( "0" x 4 . $batchcount, -4, 4 );
  $bh[1]     = $batchnum;                                # batch seq number (4n)
  $tdy       = substr( $todaylocal, 2 );
  $bh[2]     = $tdy;                                     # batch date (6n) YYMMDD
  $mcurrency = $chkcurrency;
  $mcurrency =~ tr/a-z/A-Z/;
  my $currcode = $isotables::currencyUSD840{$mcurrency};
  $currcode = substr( $currcode . " " x 3, 0, 3 );
  $bh[3] = $currcode;                                    # transaction currency (3n)
  my $expcode = $isotables::currencyUSD2{$mcurrency};
  $expcode = substr( $expcode . " ", 0, 1 );
  $bh[4] = $expcode;                                     # transaction decimals (1n)
  $mid = substr( $merchant_id . "0" x 15, 0, 15 );
  $bh[5] = $mid;                                         # merchant id (15a)
  $mcompany =~ s/[^0-9a-zA-Z \-,\.]//g;
  $merchname = substr( $mcompany . " " x 15, 0, 15 );
  $bh[6] = $merchname;                                   # merchant name (15a)
  $merchcity = substr( $mcity . " " x 13, 0, 13 );
  $bh[7] = $merchcity;                                   # merchant city (13a)
  $bankid = substr( "0" x 6 . $bankid, -6, 6 );
  $bh[8] = $bankid;                                      # acquirer bin (6n)
  $merchcountry = substr( $mcountry . " " x 3, 0, 3 );
  $merchcountry =~ tr/a-z/A-Z/;
  $bh[9]  = $merchcountry;                               # merchant country (3a)
  $bh[10] = "0" x 5;                                     # commission percent (5n)
  $bh[11] = "0" x 9;                                     # commission amount (9n)
  $categorycode = substr( $categorycode . "0" x 4, 0, 4 );
  $bh[12] = $categorycode;                               # merchant category (4n)
  $merchzip = substr( $mzip . " " x 5, 0, 5 );

  # xxxxxx
  $merchzip = "00000";
  $bh[13]   = $merchzip;                                 # merchant zip code (5a)

  $batchheader = "";

  my $fileyear = substr( $filename, 0, 4 ) . "/" . substr( $filename, 4, 2 ) . "/" . substr( $filename, 6, 2 );
  my $fileyymmdd = substr( $filename, 0, 8 );
  &checkdir($fileyymmdd);

  umask 0077;

  $outfilestr  = "";
  $outfile2str = "";
  foreach $var (@bh) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";

    my $printstr = "$var";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

    $batchheader = $batchheader . $var;
  }
  $outfilestr  .= "\r\n";
  $outfile2str .= "\r\n";

  my $printstr = "\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename",     "append", "", $outfilestr );
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename.txt", "append", "", $outfile2str );

  $outfile4str = "";
  $outfile4str .= "$batchheader  $recseqnum  $username\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename.log", "append", "", $outfile4str );

  $transseqnum   = 0;
  $batchsalescnt = 0;

  #$batchsalesamt = 0;
  $batchsalesamt = Math::BigInt->new("0");
  $batchretcnt   = 0;

  #$batchretamt = 0;
  $batchretamt = Math::BigInt->new("0");

}

sub batchdetail {
  my $printstr = "batchdetail\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  $recseqnum   = substr( "0000000" . $recseqnum, -7, 7 );
  $transseqnum = $transseqnum + 1;
  $transseqnum = substr( "000" . $transseqnum, -3, 3 );

  $card_type = &smpsutils::checkcard($cardnumber);

  if ( $card_type eq "vi" ) {
    $authsrc = substr( $auth_code, 6, 1 );

    #$authresp = substr($auth_code,7,2);
    $authresp = substr( $auth_code, 29, 2 );
  } else {
    $authsrc  = " ";
    $authresp = "  ";
  }

  $transdate = substr( $trans_time, 4, 4 ) . substr( $trans_time, 2, 2 );
  $transtime = substr( $trans_time, 8, 6 );
  $authcode  = substr( $auth_code,  0, 6 );
  if ( ( $proc_type =~ /^(authonly|authpostauth)$/ ) && ( $operation eq "postauth" ) ) {
    $tcode = "03";
  } elsif ( ( $proc_type =~ "authcapture" ) && ( $operation eq "postauth" ) ) {
    $tcode = "01";
  } elsif ( $operation eq "return" ) {
    $tcode = "06";
  }

  $transseqnum = substr( $transseqnum . " " x 3, 0, 3 );
  $tcode       = substr( $tcode . " " x 2,       0, 2 );
  $cardnumber  = substr( $cardnumber . " " x 19, 0, 19 );
  $transdate   = substr( $transdate . " " x 6,   0, 6 );
  $transtime   = substr( $transtime . " " x 6,   0, 6 );
  $authcode    = substr( $authcode . " " x 6,    0, 6 );
  $authsrc     = substr( $authsrc . " " x 1,     0, 1 );
  $authresp    = substr( $authresp . " " x 2,    0, 2 );
  $avs_code    = substr( $avs_code . " " x 1,    0, 1 );

  $ltime = &miscutils::strtotime($trans_time);
  if ( $ltime ne "" ) {
    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($ltime);
    $year     = $year + 1900;
    $year     = substr( $year, 2, 2 );
    $trantime = sprintf( "%02d%02d%02d%02d%02d%02d", $year, $month + 1, $day, $hour, $min, $sec );
  } else {
    $trantime = substr( $trans_time, 2, 12 );
  }

  $datestr = substr( $trantime, 2, 2 ) . "/" . substr( $trantime, 4, 2 ) . "/" . substr( $trantime, 0, 2 );

  $authcode = substr( $auth_code, 0, 6 );
  ( $curr, $amt ) = split( / /, $amount );
  if ( $operation eq "return" ) {
    $amt = -$amt;
  }
  $newreportline = sprintf( "%-12s   %-20s   %-12s   %-4s%-10s   %-20s   %-12s   %-12s", $datestr, $cardnumber, $card_type, $curr, $amt, $merchant_id, $terminal_id, $authcode );

  #$newreportline = sprintf("%-12s   %-20s   %-12s   %-12s   %-20s   %-12s   %-4s%-10s",
  #    $datestr,$merchant_id,$terminal_id,$card_type,$cardnumber,$authcode,$curr,$amt);
  @reportline = ( @reportline, $newreportline );

  if ( $username =~ /^(mosseljama1|mosselusdp)$/ ) {
    @reportlinemos = ( @reportlinemos, $newreportline );
  }

  $newreportline = sprintf( "%-12s   %-20s   %-12s   %-12s   %-20s   %-4s%-10s   %-12s", $datestr, $merchant_id, $terminal_id, $card_type, $cardnumber, $curr, $amt, $authcode );
  @reportline2 = ( @reportline2, $newreportline );

  @bd    = ();
  $bd[0] = "TX";    # record type (2a) 0
  $bd[1] = " ";     # payment system indicator (1a) 2
                    # xxxx carol 01/02/2007
  if ( ( $operation ne "return" ) && ( $amount ne $origamount ) ) {
    $bd[2] = 'R';    # transaction identifier O = original, R = reversal (1a) 3
  } else {
    $bd[2] = 'O';    # transaction identifier O = original, R = reversal (1a)
  }
  if ( $operation eq "return" ) {
    $bd[3] = '09';    # transaction code (2n) 4
  } else {
    $bd[3] = '01';    # transaction code (2n)
  }
  $cardnum = substr( $cardnumber . " " x 19, 0, 19 );
  $bd[4] = $cardnum;    # card number (19n) 6
  $bd[5] = "0" x 3;     # card sequence number (3n) xxx 25
  $bd[6] = "0";         # magnetic track read (1n) 28
  $exp = substr( $cardexp, 3, 2 ) . substr( $cardexp, 0, 2 );
  $bd[7] = $exp;        # card expiration date YYMM (4n) 29

  $bd[8] = $trantime;       # transaction date & time YYMMDDhhmmss (6n) 33
  $bd[9] = '0000000000';    # tip amount (10n) 39
  my ( $currency, $origamt ) = split( / /, $origamount );
  $currency =~ tr/a-z/A-Z/;
  my $exponent = $isotables::currencyUSD2{$currency};

  my $bigamt = Math::BigFloat->new($origamt);
  $bigamt = ( $bigamt * ( 10**$exponent ) ) + .0001;
  my $bigamtstr = $bigamt->bstr();
  $bigamtstr =~ s/\.[0-9]*$//;
  $origamt = $bigamtstr;

  #$origamt = sprintf("%d", ($origamt * (10 ** $exponent)) + .0001);
  $origamt = substr( "0" x 12 . $origamt, -12, 12 );

  my ( $currency, $transamt ) = split( / /, $amount );
  $currency =~ tr/a-z/A-Z/;
  my $exponent = $isotables::currencyUSD2{$currency};

  my $bigamt = Math::BigFloat->new($transamt);
  $bigamt = ( $bigamt * ( 10**$exponent ) ) + .0001;
  my $bigamtstr = $bigamt->bstr();
  $bigamtstr =~ s/\.[0-9]*$//;
  $transamt = $bigamtstr;

  #$transamt = sprintf("%d", ($transamt * (10 ** $exponent)) + .0001);
  $transamt = substr( "0" x 12 . $transamt, -12, 12 );

  # xxxx carol 01/03/2007
  if ( ( $operation ne "return" ) && ( $transamt ne $origamt ) ) {

    #if ($origamt ne $transamt) {}
    my $bigamt  = Math::BigInt->new($origamt);
    my $bigamt2 = Math::BigInt->new($transamt);
    $bigamt  = $bigamt - $bigamt2;
    $diffamt = $bigamt;

    #$diffamt = $origamt - $transamt;
    $diffamt = substr( "0" x 12 . $diffamt, -12, 12 );
  } else {
    $diffamt = "0" x 12;
  }

  if ( $operation eq "return" ) {
    $origamt = $transamt;
  }
  $bd[10] = $origamt;    # transaction amount (12n) 49
  $bd[11] = $diffamt;    # reversed amount (12n) 61
  $authcode = substr( $auth_code,          0, 6 );
  $authcode = substr( $authcode . " " x 6, 0, 6 );
  if ( $operation eq "return" ) {
    $authcode = "      ";
  }
  $bd[12] = $authcode;    # authorization code (6a) 73
  $bd[13] = " " x 10;     # voucher number (10a) 79
  $tid = substr( $terminal_id . " " x 8, 0, 8 );
  $bd[14] = $tid;         # terminal identification (8a) 89
  $tracenum = substr( $auth_code,          6, 6 );
  $tracenum = substr( $tracenum . " " x 6, 0, 6 );
  $bd[15] = $tracenum;    # stan (6n) 97

  if ( $card_type eq "mc" ) {
    $posdata = '100050S00000';
  } else {
    $posdata = "0" x 12;
  }
  $bd[16] = $posdata;     # pos data code (12n) 103
  $refnum = substr( $auth_code,         12, 12 );
  $refnum = substr( $refnum . " " x 12, 0,  12 );
  $bd[17] = $refnum;      # retrieval reference number (12n) 115

  my $postermcap = substr( $auth_code, 36, 1 );
  if ( $postermcap eq "" ) {
    $postermcap = " ";
  }
  $bd[18] = $postermcap;    # pos terminal capability (1a) 127

  if ( $card_type eq "mc" ) {
    $posentry = "81";
  } else {
    $posentry = "00";
  }
  $bd[19] = $posentry;      # pos entry mode (2a) 128
  $bd[20] = " ";            # authorization source (1a) 130
  $bd[21] = "0" x 12;       # cashback amount (12n) 131
  $bd[22] = "0" x 15;       # ps2000 transaction identifier (15n) 143
  $respcode = substr( $auth_code,          24, 2 );
  $respcode = substr( $respcode . " " x 2, 0,  2 );
  $bd[23] = $respcode;      # authorization response code (2a) 158
  $bd[24] = "    ";         # validation code (4a) 160
  $currency =~ tr/a-z/A-Z/;
  my $currcode = $isotables::currencyUSD840{$currency};
  $currcode = substr( $currcode . " " x 3, 0, 3 );
  $bd[25] = $currcode;      # authorization currency code (3a) 164
  $bd[26] = " ";            # authorization characteristic indicator (1a) 167
  $bd[27] = " ";            # market specific auth data indicator (1a) 168
  $bd[28] = " " x 9;        # banknet reference number (9a) 169
  $bd[29] = "0000";         # banknet date (4n) 178
  $bd[30] = "003000";       # atm account selection (6a) same as processing code BM #3 182

  my $eci = substr( $auth_code, 37, 1 );
  if ( $card_type eq "mc" ) {
    $eci = " ";
  } elsif ( ( $eci eq "" ) || ( $eci eq " " ) ) {
    $eci = "7";
  }
  $bd[31] = $eci;           # moto/ecommerce indicator (1a) 188
  $bd[32] = "0" x 8;        # exchange rate (8n) 189
  $bd[33] = $currcode;      # settlement currency (3n) 197
  $bd[34] = $exponent;      # settlement currency decimals (1n) 200
  $bd[35] = $transamt;      # settlement amount in settlement currency (12n) 201
  $bd[36] = "0" x 8;        # commission (8n) 213
  $bd[37] = "0" x 12;       # commission amount (12n) 221
  $bd[38] = $currcode;      # transaction currency (3n) 233
  $bd[39] = " ";            # sms indicator (1a)
  $bd[40] = " ";            # vsdc indicator (1a)
  $newbatchnum = substr( "0" x 10 . $batchnum, -10, 10 );
  $bd[41] = $newbatchnum;    # batch number (10n)
  $bd[42] = "0" x 6;         # invoice number (6n)
  $bd[43] = " ";             # avs response code (1a)

  if ( $operation eq "return" ) {
    $bd[44] = "003000";      # processing code (6n)
  } elsif ( ( $operation eq "postauth" ) && ( $origamt ne $transamt ) ) {
    $bd[44] = "0" x 6;       # processing code (6n)
                             # xxxxxxx
    $bd[44] = "003000";      # processing code (6n)
  } else {
    $bd[44] = "0" x 6;       # processing code (6n) xxx
                             # xxxxxxx
    $bd[44] = "003000";      # processing code (6n)
  }
  $trantype = substr( $auth_code,          30, 2 );
  $trantype = substr( $trantype . " " x 2, 0,  2 );
  if ( ( $operation eq "postauth" ) && ( $trantype ne "11" ) && ( $transamt ne $origamt ) ) {
    $trantype = "02";        # reversal
  } elsif ( ( $operation eq "postauth" ) && ( $trantype ne "11" ) ) {
    $trantype = "00";        # postauth - not quasi cash
  } elsif ( $operation eq "return" ) {
    $trantype = "20";        # return
  }
  $bd[45] = $trantype;       # transaction type (2a)
  $tdate = substr( $trantime, 0, 6 );
  $bd[46] = $tdate;          # terminal transaction date (6n)
  $bd[47] = "0" x 6;         # terminal capability profile (6h)
  $bd[48] = $currcode;       # terminal country code (3n)
  my $printstr = "transamt: $transamt\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "newbatchnum: $newbatchnum\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "trantime: $trantime\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  $bd[49] = " " x 8;         # terminal serial number (8a)
  $bd[50] = "0" x 8;         # unpredictable number (8h)
  $bd[51] = "0" x 4;         # application transaction counter (4h)
  $bd[52] = "0" x 4;         # application interchange profile (4h)
  $bd[53] = "0" x 16;        # cryptogram (16h)
  $bd[54] = "00";            # derivation key index (2h)
  $bd[55] = "00";            # cryptogram version (2h)
  $bd[56] = "0" x 10;        # terminal verification results (10h)
  $bd[57] = "0" x 8;         # card verification results (8h)
  $bd[58] = "0" x 10;        # issuer script 1 results (10h)
  $bd[59] = "00";            # card authentication results code (2h)
  $bd[60] = "0";             # CCPS transaction indicator (1n)
  $bd[61] = "0";             # card authentication reliability indicaor (1n)
  $bd[62] = "0" x 32;        # visa discretionary data (32h)
  $bd[63] = "0" x 32;        # issuer discretionary data (32h)
  $bd[64] = "0" x 16;        # authorization response cryptogram (ARPC) (16h)
  $bd[65] = "0" x 4;         # ARPC response code (4h)
  $bd[66] = "0" x 12;        # cryptogram amount (21n)
  $bd[67] = "0" x 3;         # cryptogram currency code (3n)
  $bd[68] = "0" x 12;        # cryptogram cashback amount (12n)

  if ( $card_type eq "mc" ) {
    my $ucafdata = substr( $auth_code, 38, 3 );
    if ( $ucafdata eq "" ) {
      $ucafdata = "910";
    }
    $bd[69] = $ucafdata;     # UCAF security level indicator (3n)

    my $cavv = substr( $auth_code, 41, 64 );
    if ( $cavv eq "" ) {
      $cavv = " " x 64;
    }
    $bd[70] = $cavv;         # UCAF data (62a)
  } else {
    $bd[69] = "000";         # UCAF security level indicator (1n)
    $bd[70] = "0" x 64;      # UCAF data (64a)
  }

  if (0) {
    $bd[69] = "   ";         # UCAF security level indicator (3n)
    $bd[70] = " " x 64;      # UCAF data (64a)
    $bd[71] = " " x 3;       # installement period (3n)
    $bd[72] = " " x 3;       # installment offset (3n)
    $bd[73] = " " x 100;     # text data (100a)
    my $xid = substr( $auth_code, 41, 40 );
    if ( $xid eq "" ) {
      $xid = " " x 40;
    }
    $bd[74] = $xid;          # XID data vi (40a)
  }

  my $fileyear = substr( $filename, 0, 4 ) . "/" . substr( $filename, 4, 2 ) . "/" . substr( $filename, 6, 2 );
  umask 0077;
  $outfilestr  = "";
  $outfile2str = "";
  foreach $var (@bd) {
    $outfilestr .= "$var";
    $cardnumber =~ s/ //g;
    $xs = "x" x length($cardnumber);
    $var =~ s/$cardnumber/$xs/;
    $outfile2str .= "$var";
    my $printstr = "$var";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  }
  $outfilestr  .= "\r\n";
  $outfile2str .= "\r\n";

  my $printstr = "\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename",     "append", "", $outfilestr );
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename.txt", "append", "", $outfile2str );

  my ( $curr, $amt ) = split( / /, $amount );
  $fileamt    = Math::BigFloat->new($amt);
  $fileamt    = ( $fileamt * 1000.0 ) + .0001;
  $fileamtstr = $fileamt->bstr();
  $fileamtstr =~ s/\.[0-9]*$//;
  $newfileamt = Math::BigInt->new($fileamtstr);

  #$fileamt = sprintf("%d", (($amt * 1000) + .0001));

  if ( $operation eq "postauth" ) {
    $batchsalesamt = $batchsalesamt + $transamt;
    $batchsalescnt = $batchsalescnt + 1;
    $filesalesamt  = $filesalesamt + bint($newfileamt);
    $filesalescnt  = $filesalescnt + 1;
    $netamount     = $netamount + $transamt;
    $netcount      = $netcount + 1;
  } else {
    $batchretamt = $batchretamt + $transamt;
    $batchretcnt = $batchretcnt + 1;
    $fileretamt  = $fileretamt + bint($newfileamt);
    $fileretcnt  = $fileretcnt + 1;
    $netamount   = $netamount - $transamt;
    $netcount    = $netcount + 1;
  }
}

sub bint { Math::BigInt->new(shift); }

sub batchtrailer {
  my $printstr = "batchtrailer\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

  $batchsalescnt = substr( "0000" . $batchsalescnt,   -4,  4 );
  $batchsalesamt = substr( "0" x 14 . $batchsalesamt, -14, 14 );
  $batchretcnt   = substr( "0000" . $batchretcnt,     -4,  4 );
  $batchretamt   = substr( "0" x 14 . $batchretamt,   -14, 14 );
  $batchreccnt   = substr( "0" x 6 . $batchreccnt,    -6,  6 );
  $addendumcnt   = substr( "0" x 6 . $addendumcnt,    -6,  6 );

  @bt    = ();
  $bt[0] = "BT";              # record id (2a)
  $bt[1] = $batchsalescnt;    # DB transaction count (4n)
  $bt[2] = $batchretcnt;      # CR transaction count (4n)
  $bt[3] = $batchsalesamt;    # net DB amount (14n)
  $bt[4] = $batchretamt;      # net CR amount (14n)
  $bt[5] = $addendumcnt;      # addendum transaction count (6n)

  my $fileyear = substr( $filename, 0, 4 ) . "/" . substr( $filename, 4, 2 ) . "/" . substr( $filename, 6, 2 );
  umask 0077;
  $outfilestr  = "";
  $outfile2str = "";
  foreach $var (@bt) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
    my $printstr = "$var";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  }
  $outfilestr  .= "\r\n";
  $outfile2str .= "\r\n";

  my $printstr = "\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename",     "append", "", $outfilestr );
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename.txt", "append", "", $outfile2str );
}

sub fileheader {
  my $printstr = "fileheader\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  $batchcount = 0;

  $file_flag = 0;
  my $dbquerystr = <<"dbEOM";
        select fileid
        from ncb
        where username='ncb'
dbEOM
  my @dbvalues = ();
  ($filenum) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $filenum = $filenum + 1;

  if ( $filenum > 99999 ) {
    $filenum = 1;
  }

  my $dbquerystr = <<"dbEOM";
        update ncb set fileid=?
	where username='ncb'
dbEOM
  my @dbvalues = ("$filenum");
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  #($filename) = &miscutils::genorderid();
  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
  $filename = sprintf( "%04d%02d%02d%02d%02d%02d%05d", $lyear + 1900, $lmonth + 1, $lday, $lhour, $lmin, $lsec, $$ );

  $filesalescnt = 0;

  #$filesalesamt = 0;
  $filesalesamt = Math::BigInt->new("0");
  $fileretcnt   = 0;

  #$fileretamt = 0;
  $fileretamt = Math::BigInt->new("0");
  $filereccnt = 1;
  $recseqnum  = 1;
  $recseqnum  = substr( "0000000" . $recseqnum, -7, 7 );

  @fh         = ();
  $fh[0]      = "FH";                                  # record type (a2)
  $fileid     = "NCB-Ecommerce";
  $fileid     = substr( $fileid . " " x 17, 0, 17 );
  $fh[1]      = $fileid;                               # file id (a17)
  $refdate    = substr( $todaylocal, 2, 6 );
  $filenum    = substr( "0" x 7 . $filenum, -7, 7 );
  $filerefnum = "EC" . $refdate . $filenum;
  $fh[2]      = $filerefnum;                           # file ref number (a15)
  $fh[3]      = " " x 6;                               # file tape number (a6)
  $fh[4]      = $todaylocal;                           # creation date (a8)
  $fh[5]      = "VER53a";                              # pos file version (a6)

  my $fileyear = substr( $filename, 0, 4 ) . "/" . substr( $filename, 4, 2 ) . "/" . substr( $filename, 6, 2 );
  my $fileyymmdd = substr( $filename, 0, 8 );
  &checkdir($fileyymmdd);

  umask 0077;
  $outfilestr  = "";
  $outfile2str = "";
  foreach $var (@fh) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
    my $printstr = "$var";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  }
  $outfilestr  .= "\r\n";
  $outfile2str .= "\r\n";
  my $printstr = "\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb",        "miscdebug.txt", "append", "misc", $printstr );
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename",     "write",  "",     $outfilestr );
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename.txt", "write",  "",     $outfile2str );

}

sub filetrailer {

  $filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

  $filesalescnt = substr( "0000000" . $filesalescnt, -7,  7 );
  $filesalesamt = substr( "0" x 16 . $filesalesamt,  -16, 16 );
  $fileretcnt   = substr( "0000000" . $fileretcnt,   -7,  7 );
  $fileretamt   = substr( "0" x 16 . $fileretamt,    -16, 16 );
  $filereccnt   = substr( "00000000" . $filereccnt,  -8,  8 );
  $netcount     = substr( "0" x 6 . $netcount,       -6,  6 );
  $batchcount   = substr( "0" x 4 . $batchcount,     -4,  4 );

  $filetotcnt = $filesalescnt + $fileretcnt;
  $filetotcnt = substr( "0" x 6 . $filetotcnt, -6, 6 );

  $datestr = substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 ) . "/" . substr( $today, 0, 4 );

  #if ($username =~ /^(mosseljama1|mosselusdp)$/) {
  #  @reportlinemos = (@reportlinemos,$newreportline);
  #}
  my $fileyear = substr( $filename, 0, 4 ) . "/" . substr( $filename, 4, 2 ) . "/" . substr( $filename, 6, 2 );
  umask 0077;
  $outfilestr  = "";
  $outfile2str = "";
  $outfile3str = "";
  $outfilestr  .= "         E-Commerce Settlement FIle Transaction Summary\r\n";
  $outfile2str .= "         E-Commerce Settlement FIle Transaction Summary\r\n";
  $outfile3str .= "         E-Commerce Settlement FIle Transaction Summary\r\n";
  $outfilestr  .= "                 National Commercial Bank Ja. Ltd\r\n\r\n";
  $outfile2str .= "                 National Commercial Bank Ja. Ltd\r\n\r\n";
  $outfile3str .= "                 National Commercial Bank Ja. Ltd\r\n\r\n";
  $outfilestr  .= "Report Date: $datestr\r\n\r\n";
  $outfile2str .= "Report Date: $datestr\r\n\r\n";
  $outfile3str .= "Report Date: $datestr\r\n\r\n";

  $newreportline = sprintf( "%-12s   %-20s   %-12s   %-12s   %-20s   %-12s   %-12s", "Date", "Card Number", "Card Type", "Amount", "Merchant ID", "Terminal ID", "Auth Code" );

  #$newreportline = sprintf("%-12s   %-20s   %-12s   %-12s   %-20s   %-12s   %-12s",
  #        "Date","Merchant ID","Terminal_id","Card Type","Card Number","Auth Code","Amount");
  $outfilestr  .= "$newreportline\r\n";
  $outfile2str .= "$newreportline\r\n";
  $outfile3str .= "$newreportline\r\n";

  foreach $line ( sort @reportline ) {
    $outfilestr .= "$line\r\n";
    ( $dummy, $cardnumber ) = split( / +/, $line );
    $xs = "x" x length($cardnumber);
    $line =~ s/$cardnumber/$xs/;
    $outfile2str .= "$line\r\n";
  }

  foreach $line ( sort @reportlinemos ) {
    ( $dummy, $cardnumber ) = split( / +/, $line );
    $xs = "x" x length($cardnumber);
    $line =~ s/$cardnumber/$xs/;
    $outfile3str .= "$line\r\n";
  }

  foreach $line ( sort @reportline2 ) {
    ( $date, $mid, $tid, $cardtype, $cardnum, $curr, $amt, $authcode ) = split( / +/, $line );
    $summary{"$mid $date $cardtype $curr"} = $summary{"$mid $date $cardtype $curr"} + $amt;
    $summarycurr{"$curr"}                  = $summarycurr{"$curr"} + $amt;
    $count{"$mid $date $cardtype $curr"}   = $count{"$mid $date $cardtype $curr"} + 1;
    $merch{"$date $mid $curr"}++;
  }

  foreach $key ( sort keys %merch ) {
    ( $date, $mid, $curr ) = split( / /, $key );

    if ( $date ne $dateold ) {
      $outfilestr  .= "\r\n\r\n$date\r\n\r\n";
      $outfile2str .= "\r\n\r\n$date\r\n\r\n";
      $outfile3str .= "\r\n\r\n$date\r\n\r\n";
    }

    if ( ( $mid ne $midold ) || ( $date ne $dateold ) ) {
      $outfilestr  .= "Summary for Merchant $mid:  VISA           MASTERCARD     AMEX           KEYCARD\r\n";
      $outfile2str .= "Summary for Merchant $mid:  VISA           MASTERCARD     AMEX           KEYCARD\r\n";
      if ( ( $mid eq $midarray{'mosseljama1'} ) || ( $mid eq $midarray{'mosselusdp'} ) ) {
        $outfile3str .= "Summary for Merchant $mid:  VISA           MASTERCARD     AMEX           KEYCARD\r\n";
      }
    }
    $dateold = $date;
    $midold  = $mid;

    $newreportline = sprintf(
      "TRANSACTIONS:                          %-12s   %-12s   %-12s   %-12s",
      $count{"$mid $date vi $curr"},
      $count{"$mid $date mc $curr"},
      $count{"$mid $date ax $curr"},
      $count{"$mid $date kc $curr"}
    );
    $outfilestr  .= "$newreportline\r\n";
    $outfile2str .= "$newreportline\r\n";
    if ( ( $mid eq $midarray{'mosseljama1'} ) || ( $mid eq $midarray{'mosselusdp'} ) ) {
      $outfile3str .= "$newreportline\r\n";
    }

    if ( $summary{"$mid $date vi $curr"} >= 0 ) {
      $amt1 = sprintf( "%8.2f", ( $summary{"$mid $date vi $curr"} + .0001 ) );
    } else {
      $amt1 = sprintf( "%8.2f", ( $summary{"$mid $date vi $curr"} - .0001 ) );
    }

    if ( $summary{"$mid $date mc $curr"} >= 0 ) {
      $amt2 = sprintf( "%8.2f", ( $summary{"$mid $date mc $curr"} + .0001 ) );
    } else {
      $amt2 = sprintf( "%8.2f", ( $summary{"$mid $date mc $curr"} - .0001 ) );
    }

    if ( $summary{"$mid $date ax $curr"} >= 0 ) {
      $amt3 = sprintf( "%8.2f", ( $summary{"$mid $date ax $curr"} + .0001 ) );
    } else {
      $amt3 = sprintf( "%8.2f", ( $summary{"$mid $date ax $curr"} - .0001 ) );
    }

    if ( $summary{"$mid $date kc $curr"} >= 0 ) {
      $amt4 = sprintf( "%8.2f", ( $summary{"$mid $date kc $curr"} + .0001 ) );
    } else {
      $amt4 = sprintf( "%8.2f", ( $summary{"$mid $date kc $curr"} - .0001 ) );
    }

    $newreportline = sprintf( "AMOUNT:             $curr            %-12s   %-12s   %-12s   %-12s", $amt1, $amt2, $amt3, $amt4 );
    $outfilestr  .= "$newreportline\r\n";
    $outfile2str .= "$newreportline\r\n";
    if ( ( $mid eq $midarray{'mosseljama1'} ) || ( $mid eq $midarray{'mosselusdp'} ) ) {
      $outfile3str .= "$newreportline\r\n";
    }

  }

  # new 12/02/2008
  $outfilestr  .= "\r\nCurrency Totals:\r\n";
  $outfile2str .= "\r\nCurrency Totals:\r\n";
  if ( ( $mid eq $midarray{'mosseljama1'} ) || ( $mid eq $midarray{'mosselusdp'} ) ) {
    $outfile3str .= "\r\nCurrency Totals:\r\n";
  }

  foreach $curr ( sort keys %summarycurr ) {
    if ( $summarycurr{"$curr"} >= 0 ) {
      $amt5 = sprintf( "%10.2f", ( $summarycurr{"$curr"} + .0001 ) );
    } else {
      $amt5 = sprintf( "%10.2f", ( $summarycurr{"$curr"} - .0001 ) );
    }

    $newreportline = sprintf( "%s: %-14s", $curr, $amt5 );
    $outfilestr  .= "$newreportline\r\n";
    $outfile2str .= "$newreportline\r\n";
    if ( ( $mid eq $midarray{'mosseljama1'} ) || ( $mid eq $midarray{'mosselusdp'} ) ) {
      $outfile3str .= "$newreportline\r\n";
    }
  }

  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename" . "rep",        "write", "", $outfilestr );
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename" . "rep.txt",    "write", "", $outfile2str );
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename" . "repmos.txt", "write", "", $outfile3str );

  @ft    = ();
  $ft[0] = "FT";             # record id (2a)
  $ft[1] = $batchcount;      # batch count (4n)
  $ft[2] = $filetotcnt;      # TX count (6n)
  $ft[3] = $filesalesamt;    # net DB amount (16n) three decimal places
  $ft[4] = $fileretamt;      # net CR amount (16n) three decimal places

  my $fileyear = substr( $filename, 0, 4 ) . "/" . substr( $filename, 4, 2 ) . "/" . substr( $filename, 6, 2 );
  umask 0077;
  $outfilestr  = "";
  $outfile2str = "";

  foreach $var (@ft) {
    $outfilestr  .= "$var";
    $outfile2str .= "$var";
    my $printstr = "$var";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  }
  $outfilestr  .= "\r\n";
  $outfile2str .= "\r\n";
  my $printstr = "\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename",     "append", "", $outfilestr );
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb/$fileyear", "$filename.txt", "append", "", $outfile2str );

  # use this for test only
  if (0) {

    my $logdir = "/home/pay1/batchfiles/logs/ncb/$fileyear";
    my $file2  = $filename . "rep";
    my @files  = ( "$filename", "$file2" );

    my $message = "";
    foreach (@files) {
      $message .= $_ . "\n";
      $message .= `uuencode $logdir/$_ $_`;
    }

    #my $email = "CrossleyAG\@JNCB.com,nodenterpriseuat\@jncb.com";
    #my $email = "dprice\@plugnpay.com";

    open( 'MAIL', "| /usr/lib/sendmail -t" );
    print MAIL "To: arnoldrn\@JNCB.com\n";
    print MAIL "Bcc:cprice\@plugnpay.com\n";
    print MAIL "From: support\@plugnpay.com\n";
    print MAIL "Subject: ncb test settlement file  $filename\n";
    print MAIL "\n";
    print MAIL "$message\n";
    close('MAIL');

    #open(MAIL,"| /usr/lib/sendmail -t");
    #print MAIL "To: arnoldrn\@JNCB.com\n";
    #print MAIL "From: settlement\@plugnpay.com\n";
    #print MAIL "Subject: ncb test settlement file  $filename\n";
    #print MAIL "\n";

    #open(infile1,"/home/pay1/batchfiles/logs/ncb/$fileyear/$filename.txt");
    #while (<infile1>) {
    #  print MAIL $_;
    #}
    #close(infile1);

    #print MAIL "\n\n\n";

    #open(infile2,"/home/pay1/batchfiles/logs/ncb/$fileyear/$filename" . "rep.txt");
    #while (<infile2>) {
    #  print MAIL $_;
    #}
    #close(infile2);

    #close(MAIL);
  }

}

sub errorchecking {
  my $mylen = length($cardnumber);
  my $amt = substr( $amount, 4 );

  # check for bad card numbers
  if ( ( $enclength > 1024 ) || ( $enclength < 30 ) ) {
    $descr = 'could not decrypt card';
  } elsif ( ( $mylen < 13 ) || ( $mylen > 20 ) ) {
    $descr = 'bad card length';
  } elsif ( $cardnumber eq "4111111111111111" ) {
    $descr = 'test card number';
  } elsif ( $amt == 0 ) {
    $descr = 'amount = 0.00';
  } else {
    return 0;
  }

  my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='problem',descr=?
          where orderid=?
          and username=?
          and trans_date>=?
          and finalstatus='pending'
dbEOM
  my @dbvalues = ( "$descr", "$orderid", "$username", "$onemonthsago" );
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
  my @dbvalues = ( "$descr", "$orderid", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  return 1;
}

sub checkdir {
  my ($date) = @_;

  my $printstr = "checking $date\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  $fileyear = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 );
  $filemonth = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 );
  $fileyearonly = substr( $date, 0, 4 );

  if ( !-e "/home/pay1/batchfiles/logs/ncb/$fileyearonly" ) {
    my $printstr = "creating $fileyearonly\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/logs/ncb/$fileyearonly");
  }
  if ( !-e "/home/pay1/batchfiles/logs/ncb/$filemonth" ) {
    my $printstr = "creating $filemonth\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/logs/ncb/$filemonth");
  }
  if ( !-e "/home/pay1/batchfiles/logs/ncb/$fileyear" ) {
    my $printstr = "creating $fileyear\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/logs/ncb/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/logs/ncb/$fileyear" ) {
    system("mkdir /home/pay1/batchfiles/logs/ncb/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/logs/ncb/$fileyear" ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: ncb - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Couldn't create directory logs/ncb/$fileyear.\n\n";
    close MAILERR;
    exit;
  }

}
