#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use procutils;
use smpsutils;
use SHA;

if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
  exit;
}

$devprod = "logs";

#$checkstring = " and username in ('ccservice','ccservicea','ccserviceb','ccservicec','dentalplans')";
#$checkstring = " and username='aaaa'";
#$overrideday = "22";	# format DD

# this is for deleting old records
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 93 ) );
$threemonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 12 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( time() + ( 90 * 24 * 3600 ) );
my $expired_testdate = sprintf( "%04d%02d", $year + 1900, $mon + 1 );

my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 2 * 24 * 3600 ) );
my $expired_startdate = sprintf( "%04d%02d", $year + 1900, $mon + 1 );

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
( $dummy, $today, $todaytime ) = &miscutils::genorderid();
$ttime = $todaytime;

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/pay1/batchfiles/$devprod/elavon/acctlogs/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear" );
}

#$fileyear = substr($today,0,4);
#if (! -e "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear") {
#  system("mkdir /home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear");
#  system("chmod go-rwx /home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear");
#}
if ( !-e "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: elavon - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory elavon/acctlogs/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$batch_flag = 1;
$file_flag  = 1;

# remove records that are more than three months old
my $dbquerystr = <<"dbEOM";
      delete from accountupd
      where trans_date<?
      or trans_date is NULL
dbEOM
my @dbvalues = ("$threemonthsago");
&procutils::dbdelete( "elavon", "accountupd", "pnpmisc", $dbquerystr, @dbvalues );

my $dbquerystr = <<"dbEOM";
      select username,features,processor,merchant_id
      from customers
      where status='live'
      and features like '%accountupdater%'
 $checkstring
      order by username
dbEOM
my @dbvalues = ();
my @sthvalarray = &procutils::dbread( 'elavon', 'accountupd', "pnpmisc", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthvalarray) ; $vali = $vali + 4 ) {
  ( $musername, $features, $processor, $mid ) = @sthvalarray[ $vali .. $vali + 3 ];

  print "$musername    $features\n";

  #use PlugNPay::Features;
  #my $accountFeatures = new PlugNPay::Features($mckutils::query{'publisher-name'},'general');
  #$accountFeatures->get('enhancedLogging')   ## Gets the value of the feature  'enhancedLogging'

  $features =~ /accountupdater=([a-z0-9]*)/;
  $database = $1;

  $usemerchacct = $musername;
  if ( $features =~ /accountupdatermerchant=([a-z0-9]*)/ ) {
    $usemerchacct = $1;
  }

  $schedule = "26";
  if ( $features =~ /accountupdatersched=([0-9\|]*)/ ) {
    $schedule = $1;
  }

  if ( $database eq "" ) {
    next;
  }

  #$usemerchacct = "pnpacctupd";

  if ( $usemerchacct ne "" ) {

    # get processor name and mid from customers table
    my $dbquerystr = <<"dbEOM";
          select username,processor,merchant_id
          from customers
          where username=?
dbEOM
    my @dbvalues = ("$usemerchacct");
    ( my $chkusername, $processor, $mid ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  }

  if ( $processor eq "elavon" ) {
    $userlist{"$usemerchacct $musername $database $mid $schedule"} = 1;
    my $printstr = "merchacct: $usemerchacct  musername: $musername    database: $database    $processor\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  }

}

foreach my $userkey ( sort keys %userlist ) {
  ( $usemerchacct, $musername, $database, $merchant_id, $schedule ) = split( / /, $userkey );
  my $printstr = "merchacct: $usemerchacct  musername: $musername    database: $database    processor: $processor  mid: $merchant_id  sched: $schedule\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  #local $sthinfo = $dbh->prepare(qq{
  #      select bankid,acctvmemberid,acctmmemberid,acctglobalid,acctvisamid
  #      from elavon
  #      where username='$username'
  #      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  #$sthinfo->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
  #($bankid,$acctvmemberid,$acctmmemberid,$acctglobalid,$acctvisamid) = $sthinfo->fetchrow;
  #$sthinfo->finish;

  ( $d1, $d2, $time ) = &miscutils::genorderid();

  if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
    $logfilestr = "";
    $logfilestr .= "stopgenfiles\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear", "$musername$time.txt", "append", "", $logfilestr );

    my $printstr = "stopgenfiles\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
    last;
  }

  my $printstr = "bbbb $musername  $banknum\n";
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );

  %dataarray = ();

  my (@schedulearray) = split( /\|/, $schedule );
  my $processflag = 0;
  for ( my $i = 0 ; $i < scalar(@schedulearray) ; $i++ ) {
    my $sched = substr( "00" . $schedulearray[$i], -2, 2 );
    if ( ( ( $overrideday eq "" ) && ( substr( $today, 6, 2 ) eq $sched ) ) || ( ( $overrideday ne "" ) && ( $overrideday eq "$sched" ) ) ) {
      $processflag = 1;
    }
  }

  if ( $processflag == 0 ) {
    next;
  }

  my $expdatestr = "";
  for ( my $i = $expired_startdate ; $i <= $expired_testdate ; $i++ ) {
    if ( $i =~ /13$/ ) {
      $i = $i + 100 - 12;
    }
    $expdatestr .= "\'" . substr( $i, 4, 2 ) . "/" . substr( $i, 2, 2 ) . "\'" . ",";
  }
  chop $expdatestr;

  if ( $expdatestr eq "" ) {
    exit;
  }
  if ( length($expdatestr) > 1024 ) {
    exit;
  }
  print "$expdatestr\n";

  print "select username,enccardnumber,length,exp from customer\n";

  #limit 20
  #where exp in ($expdatestr)
  my $dbquerystr = <<"dbEOM";
        select username,enccardnumber,length,exp
        from customer
dbEOM
  my @dbvalues = ();
  my @sthvalarray = &procutils::dbread( $username, $orderid, "$database", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthvalarray) ; $vali = $vali + 4 ) {
    ( $username, $enccardnumber, $length, $exp ) = @sthvalarray[ $vali .. $vali + 3 ];

    if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
      last;
    }

    if ( $exp eq "" ) {
      next;
    }
    my ( $mo, $yr ) = split( '\/', $exp );
    my $card_exp = "20" . $yr . $mo;

    #if (($card_exp < $expired_startdate) || ($card_exp > $expired_testdate)) {
    #  next;		# only do cards expiring within 60 days
    #}

    my ( $cardnumber, $newcardnumber, $newexp );

    $enccardnumber = &smpsutils::getcardnumber( $database, $username, 'bill_member', $enccardnumber, 'rec' );

    if ( $enccardnumber ne "" ) {
      $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );
    } else {
      next;
    }

    my $cc            = new PlugNPay::CreditCard($cardnumber);
    my $shacardnumber = $cc->getCardHash();

    $dataarray{"$username $cardnumber $card_exp $shacardnumber"} = 1;
  }

  foreach $key ( sort keys %dataarray ) {
    ( $username, $cardnumber, $card_exp, $shacardnumber ) = split( / /, $key, 4 );

    $card_type = &smpsutils::checkcard($cardnumber);
    if ( ( $cardnumber =~ /^36/ ) && ( length($cardnumber) == 14 ) ) {
      $card_type = 'mc';
    }

    if ( $card_type !~ /(vi|mc)/ ) {
      next;
    }

    if ( $card_type eq "" ) {
      next;
    }

    #if (($card_type ne "vi") && ($acctmmemberid eq "")) {
    #  next;
    #}

    #if ((($username ne $usernameold) || ($card_type ne $card_typeold)) && ($batch_flag == 0)) {}
    #if (($database ne $databaseold) && ($batch_flag == 0)) {}
    if ( ( $usemerchacct ne $usemerchacctold ) && ( $batch_flag == 0 ) ) {
      &batchtrailer();
      $batch_flag = 1;
    }

    #if (($file_flag == 0) && ($card_type ne $card_typeold)) {}
    #if ($file_flag == 0) {
    #  &filetrailer();
    #  $file_flag = 1;
    #}

    #if (($file_flag == 1) || ($card_type ne $card_typeold)) {}
    if ( $file_flag == 1 ) {
      &fileheader();
      $file_flag = 0;
    }

    if ( $batch_flag == 1 ) {
      &batchheader();
      $batch_flag = 0;
    }

    $recseqnum++;
    $recseqnum = substr( "0000000" . $recseqnum, -6, 6 );
    $transseqnum = $transseqnum + 1;

    my $dbquerystr = <<"dbEOM";
        insert into accountupd
        (username,orderid,trans_date,trans_time,status,filename,processor)
        values (?,?,?,?,?,?,?)
dbEOM

    my %inserthash = ( "username", "$database", "orderid", "$username", "trans_date", "$today", "trans_time", "$todaytime", "status", 'pending', "filename", "$filename", "processor", 'elavon' );
    &procutils::dbinsert( $username, $orderid, "pnpmisc", "accountupd", %inserthash );

    &batchdetail();

    if ( $recseqnum >= 999990 ) {
      &batchtrailer();
      $batch_flag = 1;
    }

    if ( $recseqnum >= 999990 ) {
      &filetrailer();
      $file_flag = 1;
    }

    $banknumold      = $banknum;
    $usemerchacctold = $usemerchacct;
    $merchant_idold  = $merchant_id;
    $batchidold      = "$time$summaryid";
    $card_typeold    = "$card_type";
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

system("/home/pay1/batchfiles/prod/elavon/putfiles.pl");

#$mytime = gmtime(time());
#open(outfile,">>/home/pay1/batchfiles/elavon/ftplog.txt");
#print outfile "\n\n$mytime\n";
#close(outfile);
#if (($filecount > 0) && ($filecount < 30)) {
#  for ($myi=0; $myi<=$filecount; $myi++) {
#    system("/home/pay1/batchfiles/elavon/putfiles.pl >> /home/pay1/batchfiles/elavon/ftplog.txt 2>\&1");
#    &miscutils::mysleep(60);
#    system("/home/pay1/batchfiles/elavon/getfiles.pl >> /home/pay1/batchfiles/elavon/ftplog.txt 2>\&1");
#    &miscutils::mysleep(20);
#  }
#}

exit;

sub batchdetail {
  @bd      = ();
  $bd[0]   = "501";                                     # record type (3a)
  $bd[1]   = "$recseqnum";                              # sequence number (6a)
  $bd[2]   = "04";                                      # transaction code (2a)
  $cardnum = substr( $cardnumber . " " x 16, 0, 16 );
  $bd[3]   = "$cardnum";                                # card number (16a)

  $exp = substr( $card_exp, 4, 2 ) . substr( $card_exp, 2, 2 );
  $exp = substr( $exp . " " x 4, 0, 4 );
  $bd[5] = "$exp";                                      # expiration date MMYY (4a)
  $bd[6] = "000000000000";                              # amount (12a)
  $bd[7] = "000000000000";                              # product code (12a)
                                                        #my $userdata = substr("$database $username" . " " x 30,0,30);
  my $refnumber = substr( $recseqnum . " " x 30, 0, 30 );
  $bd[8]  = $refnumber;                                 # user data (30a)
  $bd[9]  = "0";                                        # elavon token identifier (1a) 0 not an elavon token
  $bd[10] = "0";                                        # association token indicator (1a) 0 not an association token
  $bd[11] = "  ";                                       # token assurance level (2a)
  $tokenreqid = substr( $tokenreqid . " " x 11, 0, 11 );
  $bd[12] = $tokenreqid;                                # token requestor id (11a)

  $myi = 0;
  foreach $var (@bd) {
    $outfilestr .= "$var";
    if ( $myi == 3 ) {
      $var =~ s/[0-9]/x/g;
    }
    $outfiletxtstr .= "$var";
    $myi++;
  }
  $outfilestr    .= "\n";
  $outfiletxtstr .= "\n";

  $outfilerefstr .= "$database $username $refnumber\n";

  $batchreccnt++;
  $filereccnt++;
}

sub batchheader {

  $batchcount++;

  #$filereccnt++;

  $batchreccnt = 0;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -6, 6 );

  @bh    = ();
  $bh[0] = "300";                                      # record type (3a)
  $bh[1] = "$recseqnum";                               # sequence number (6a)
                                                       #$bankid = substr($bankid . " " x 6,0,6);
                                                       #$bh[2] = "$bankid";			# bank id (6n)
  $mid   = substr( $merchant_id . " " x 16, 0, 16 );
  $bh[2] = "$mid";                                     # merchant number (15a)
  $bh[3] = "734";                                      # merchant FI number (3a) only fill in if different from file FI number
  $bh[4] = " " x 72;                                   # reserved (72a)

  foreach $var (@bh) {
    $outfilestr    .= "$var";
    $outfiletxtstr .= "$var";
  }
  $outfilestr    .= "\n";
  $outfiletxtstr .= "\n";

  $transseqnum   = 0;
  $batchtotalcnt = 0;
}

sub batchtrailer {

  #$batchreccnt++;
  #$filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -6, 6 );

  $batchretcnt = substr( "0000000" . $batchretcnt,     -6,  6 );
  $batchretamt = substr( "00000000000" . $batchretamt, -11, 11 );
  $batchreccnt = substr( "0000000" . $batchreccnt,     -6,  6 );

  if ( $batchtotalamt >= 0 ) {
    $tcode = "70";
  } else {
    $tcode         = "71";
    $batchtotalamt = bint(0) - $batchtotalamt;
  }

  @bt     = ();
  $bt[0]  = "399";           # record type (3a)
  $bt[1]  = "$recseqnum";    # sequence number (6a)
  $bt[4]  = $batchreccnt;    # sales count  (6a)
  $bt[5]  = "0" x 12;        # sales amount (12a)
  $bt[6]  = "0" x 6;         # return count (6a)
  $bt[7]  = "0" x 12;        # return amount (12a)
  $bt[8]  = $batchreccnt;    # net count (6a)
  $bt[9]  = "0" x 12;        # net amount (12a)
  $bt[10] = "+";             # net sign (1a)
  $bt[11] = " " x 36;        # reserved (36a)

  foreach $var (@bt) {
    $outfilestr    .= "$var";
    $outfiletxtstr .= "$var";
  }
  $outfilestr    .= "\n";
  $outfiletxtstr .= "\n";

}

sub fileheader {
  $batchcount = 0;
  $filecount++;

  #local $sthinfo = $dbh->prepare(qq{
  #      select accttrans_date,acctfilenum
  #      from elavon
  #      where username='$username'
  #      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  #$sthinfo->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
  #($accttrans_date,$acctfilenum) = $sthinfo->fetchrow;
  #$sthinfo->finish;

  if ( $accttrans_date != $today ) {
    $acctfilenum = 0;
  }
  $acctfilenum = $acctfilenum + 1;
  if ( $acctfilenum > 998 ) {
    my $printstr = "<h3>You have exceeded the maximum allowable batches for today.</h3>\n";
    &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/devlogs/elavon", "miscdebug.txt", "append", "misc", $printstr );
  }

  $ttime++;

  $filename = "$musername$ttime";

  #"P8836yymmddhhmmss.uat";
  $filename = "P8836" . substr( $ttime, 2 ) . ".auc";

  $outfilestr    = "";
  $outfiletxtstr = "";
  $outfilerefstr = "";

  $filereccnt = 0;
  $recseqnum  = 1;
  $recseqnum  = substr( "0000000" . $recseqnum, -6, 6 );

  @fh    = ();
  $fh[0] = "100";           # record type (3a)
  $fh[2] = "$recseqnum";    # sequence number (6a)
                            #$acctglobalid = substr("0" x 4 . $acctglobalid,-4,4);
                            #$acctmemberid = substr("0" x 3 . $acctmmemberid,-3,3);
  $fh[3] = "734";           # FI number (3a)

  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime( time() );
  $year = substr( $year, -2, 2 );
  $todaylocal = sprintf( "%02d%02d%02d", $year, $month + 1, $day );
  $fh[4] = "$todaylocal";    # creation date YYMMDD (6n)
  $fh[5] = " " x 30;         # reserved (30a)
  $fh[6] = "N";              # deposit flag (1a) N - do not deposit
  $fh[7] = "218";            # file version (3a)
  $fh[8] = "Y";              # continue on invalid mid (1a) Y - yes
  $fh[9] = " " x 47;         # reserved (47a)

  foreach $var (@fh) {
    $outfilestr    .= "$var";
    $outfiletxtstr .= "$var";
  }
  $outfilestr    .= "\n";
  $outfiletxtstr .= "\n";

}

sub filetrailer {

  #$filereccnt++;
  $filereccnt = substr( "0000000" . $filereccnt, -6, 6 );
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -6, 6 );

  @ft     = ();
  $ft[0]  = "199";           # record type (3a)
  $ft[1]  = "$recseqnum";    # sequence number (6a)
  $ft[4]  = $filereccnt;     # sales count  (6a)
  $ft[5]  = "0" x 12;        # sales amount (12a)
  $ft[6]  = "0" x 6;         # return count (6a)
  $ft[7]  = "0" x 12;        # return amount (12a)
  $ft[8]  = $filereccnt;     # net count (6a)
  $ft[9]  = "0" x 12;        # net amount (12a)
  $ft[10] = "+";             # net sign (1a)
  $ft[11] = " " x 36;        # reserved (36a)

  foreach $var (@ft) {
    $outfilestr    .= "$var";
    $outfiletxtstr .= "$var";
  }
  $outfilestr    .= "\n";
  $outfiletxtstr .= "\n";

  my $status = &procutils::fileencwrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear", "$filename", "write", "", $outfilestr );
  $outfiletxtstr = "fileencwrite status: $status\n" . $outfiletxtstr;
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear", "$filename.txt", "write", "", $outfiletxtstr );
  &procutils::filewrite( "$username", "elavon", "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear", "$filename.ref", "write", "", $outfilerefstr );
}

