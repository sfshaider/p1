#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use smpsutils;
use isotables;
use Time::Local;

# fifththird version 1.1

$devprod     = "prod";
$devprodlogs = "logs";

# 2017 fall time change, to prevent genfiles from running twice
# exit if time is between 6am gmt and 7am gmt
my $timechange = "20171105020000";    # 2am eastern on the morning of the time change (1am to 1am to 2am)

my $str6am  = $timechange + 40000;                 # str represents 6am gmt
my $str7am  = $timechange + 50000;                 # str represents 7am gmt
my $time6am = &miscutils::strtotime("$str6am");    # 6am gmt
my $time7am = &miscutils::strtotime("$str7am");    # 7am gmt
my $now     = time();

if ( ( $now >= $time6am ) && ( $now < $time7am ) ) {
  print "exiting due to fall time change\n";
  exit;
}

if ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fifththird/genfiles.pl'`;
if ( $cnt > 1 ) {
  print "genfiles.pl already running, exiting...\n";

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fifththird - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

# batch cutoff times: 2:30am, 8am, 11:15am, 5pm M-F     12pm Sat   12pm, 7pm Sun

#$checkstring = " and t.username='testfifth'";
#$checkstring = " and t.username<>'printerpix'";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

my ( $sec, $min, $hour, $day1, $month, $year, $wday, $yday, $isdst ) = gmtime( time() );
my ( $sec, $min, $hour, $day2, $month, $year, $wday, $yday, $isdst ) = localtime( time() );
if ( $day1 != $day2 ) {
  print "GMT day ($day1) and local day ($day2) do not match, try again after midnight local\n";
}

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
( $dummy, $today, $todaytime ) = &miscutils::genorderid();

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/p/pay1/batchfiles/logs/fifththird/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/p/pay1/batchfiles/logs/fifththird/$fileyearonly");
  chmod( 0700, "/home/p/pay1/batchfiles/logs/fifththird/$fileyearonly" );
}
if ( !-e "/home/p/pay1/batchfiles/logs/fifththird/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/p/pay1/batchfiles/logs/fifththird/$filemonth");
  chmod( 0700, "/home/p/pay1/batchfiles/logs/fifththird/$filemonth" );
}
if ( !-e "/home/p/pay1/batchfiles/logs/fifththird/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/p/pay1/batchfiles/logs/fifththird/$fileyear");
  chmod( 0700, "/home/p/pay1/batchfiles/logs/fifththird/$fileyear" );
}
if ( !-e "/home/p/pay1/batchfiles/logs/fifththird/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fifththird - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/fifththird/$fileyear.\n\n";
  close MAILERR;
  exit;
}

( $d1, $d2, $ttime ) = &miscutils::genorderid();
$filename = "$ttime";

$batch_flag = 1;
$file_flag  = 1;

$dbh  = &miscutils::dbhconnect("pnpmisc");
$dbh2 = &miscutils::dbhconnect("pnpdata");

#  local $sthinfo = $dbh->prepare(qq{
#        select f.username,f.banknum,c.currency
#        from fifththird f, customers c
#        where c.username=f.username
#        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
#  $sthinfo->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
#  $sthinfo->bind_columns(undef,\($username,$banknum,$currency));
#  while ($sthinfo->fetch) {
#    if ($currency eq "") {
#      $currency = "usd";
#    }
#    $banknumarray{$username} = $banknum;
#    $currencyarray{$username} = $currency;
#  }
#  $sthinfo->finish;

$sthtrans = $dbh2->prepare(
  qq{
        select t.username,count(t.username),min(o.trans_date)
        from trans_log t, operation_log o
        where t.trans_date>='$onemonthsago'
        $checkstring
        and t.finalstatus='pending'
        and (t.accttype is NULL or t.accttype ='' or t.accttype='credit')
        and o.orderid=t.orderid
        and o.username=t.username
        and o.lastoptime>='$onemonthsagotime'
        and o.lastopstatus='pending'
        and o.processor='fifththird'
        group by t.username
  }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthtrans->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthtrans->bind_columns( undef, \( $user, $usercount, $usertdate ) );
$mycnt = 0;
while ( $sthtrans->fetch ) {
  $mycnt++;
  print "aaaa $user  $usercount  $usertdate\n";
  @userarray = ( @userarray, $user );
  $userbankarray{"$banknumarray{$user} $currencyarray{$user} $user"} = 1;
  $usercountarray{$user}                                             = $usercount;
  $starttdatearray{$user}                                            = $usertdate;
}
$sthtrans->finish;

#if ($mycnt > 1) {
#  open(MAILTMP,"| /usr/lib/sendmail -t");
#  print MAILTMP "To: cprice\@plugnpay.com\n";
#  print MAILTMP "From: dcprice\@plugnpay.com\n";
#  print MAILTMP "Subject: fifththird - more than one batch\n";
#  print MAILTMP "\n";
#  print MAILTMP "There are more than one fifththird batches.\n";
#  close MAILTMP;
#}

foreach $key ( sort keys %userbankarray ) {
  ( $banknum, $currency, $username ) = split( / /, $key );
  ( $d1, $d2, $time ) = &miscutils::genorderid();

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprodlogs/fifththird/batchusers.txt" );
  print logfile "$todaytime $banknum $currency $username $time\n";
  close(logfile);

  if ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) {
    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/logs/fifththird/$fileyear/$username$time.txt" );
    print logfile "stopgenfiles\n";
    print "stopgenfiles\n";
    close(logfile);
    unlink "/home/p/pay1/batchfiles/$devprodlogs/fifththird/batchfile.txt";
    last;
  }

  umask 0033;
  open( batchfile, ">/home/p/pay1/batchfiles/$devprodlogs/fifththird/genfiles.txt" );
  print batchfile "$username\n";
  close(batchfile);

  print "bbbb $username  $banknum\n";
  umask 0033;
  open( batchfile, ">/home/p/pay1/batchfiles/$devprodlogs/fifththird/batchfile.txt" );
  print batchfile "$username\n";
  close(batchfile);

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  local $sthcust = $dbh->prepare(
    qq{
        select merchant_id,pubsecret,proc_type,status,currency,company,city,state,zip,tel,features
        from customers
        where username='$username'
        }
    )
    or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthcust->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $merchant_id, $terminal_id, $proc_type, $status, $currency, $company, $city, $state, $zip, $phone, $features ) = $sthcust->fetchrow;
  $sthcust->finish;

  if ( $currency eq "" ) {
    $currency = "usd";
  }

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/logs/fifththird/$fileyear/$username$time.txt" );
  print "cccc $username $usercountarray{$username} $starttransdate\n";
  print logfile "$username $usercountarray{$username} $starttransdate $currency\n";
  close(logfile);

  if ( $status ne "live" ) {
    next;
  }

  # sweeptime
  my %feature = ();
  if ( $features ne "" ) {
    my @array = split( /\,/, $features );
    foreach my $entry (@array) {
      my ( $name, $value ) = split( /\=/, $entry );
      $feature{$name} = $value;
    }
  }

  # sweeptime
  $sweeptime = $feature{'sweeptime'};    # sweeptime=1:EST:19   dstflag:timezone:time
  print "sweeptime: $sweeptime\n";
  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/logs/fifththird/$fileyear/$username$time$pid.txt" );
      print logfile "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      close(logfile);
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      open( logfile, ">>/home/p/pay1/batchfiles/logs/fifththird/$fileyear/$username$time$pid.txt" );
      print logfile "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      close(logfile);
      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  print "gmt today: $todaytime\n";
  print "est today: $esttime\n";
  print "est yesterday: $yesterday\n";
  print "settletime: $settletime\n";
  print "sweeptime: $sweeptime\n";

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/logs/fifththird/$fileyear/$username$time$pid.txt" );
  print "$username\n";
  print logfile "$username  group: $batchgroup  sweeptime: $sweeptime  settletime: $settletime\n";
  print logfile "$features\n";
  close(logfile);

  local $sthinfo = $dbh->prepare(
    qq{
        select industrycode,dcctype
        from fifththird
        where username='$username'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $industrycode, $dcctype ) = $sthinfo->fetchrow;
  $sthinfo->finish;

  $sthtrans = $dbh2->prepare(
    qq{
        select orderid,operation,trans_date,trans_time,enccardnumber,length,amount,auth_code,avs,finalstatus,transflags
        from trans_log
        where trans_date>='$onemonthsago'
        and username='$username'
        and (accttype is NULL or accttype ='' or accttype='credit')
        and operation IN ('postauth','return','void')
        and finalstatus NOT IN ('problem')
        and (duplicate IS NULL or duplicate ='')
        order by orderid,trans_time DESC
    }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthtrans->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthtrans->bind_columns( undef, \( $orderid, $operation, $trans_date, $trans_time, $enccardnumber, $length, $amount, $auth_code, $avs_code, $finalstatus, $transflags ) );

  while ( $sthtrans->fetch ) {
    if ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) {
      unlink "/home/p/pay1/batchfiles/$devprodlogs/fifththird/batchfile.txt";
      last;
    }

    $settletimenum = &miscutils::strtotime($trans_time);
    my ( $ssec, $smin, $shour, $sday, $smonth, $syear, $swday, $syday, $sisdst ) = localtime($settletimenum);
    if ( $syear + 1900 >= 2011 ) {
      $settledate = sprintf( "%04d%02d%02d", $syear + 1900, $smonth + 1, $sday );
    }

    if ( $operation eq "void" ) {
      $orderidold = $orderid;
      next;
    }
    if ( ( $orderid eq $orderidold ) || ( $finalstatus ne "pending" ) ) {
      $orderidold = $orderid;
      next;
    }

    if ( ( $sweeptime ne "" ) && ( $trans_time > $sweeptime ) ) {
      $orderidold = $orderid;
      next;    # transaction is newer than sweeptime
    }

    $orderidold = $orderid;

    #xxxx
    print "$orderid $operation $amount\n\n";

    umask 0077;
    open( logfile, ">>/home/p/pay1/batchfiles/logs/fifththird/$fileyear/$username$time.txt" );
    print logfile "$orderid $operation\n";
    close(logfile);

    $enccardnumber = &smpsutils::getcardnumber( $username, $orderid, "fifththird", $enccardnumber );

    $sthamt = $dbh2->prepare(
      qq{
          select origamount
          from operation_log
          where orderid='$orderid'
          and username='$username' 
          and trans_date>='$twomonthsago'
          and (authstatus='success'
          or forceauthstatus='success')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthamt->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ($origamount) = $sthamt->fetchrow;
    $sthamt->finish;

    if ( ( $username ne $usernameold ) && ( $batch_flag == 0 ) ) {
      &batchtrailer();
      $batch_flag = 1;
    }

    if ( ( ( $banknum ne $banknumold ) || ( $currency ne $currencyold ) ) && ( $file_flag == 0 ) ) {
      &filetrailer();
      $file_flag = 1;
    }

    if ( $file_flag == 1 ) {
      &fileheader();
    }

    if ( $batch_flag == 1 ) {
      &batchheader();
    }

    local $sthinfo = $dbh2->prepare(
      qq{
        update trans_log set finalstatus='locked',result=?
	where username='$username'
	and trans_date>='$twomonthsago'
	and orderid='$orderid'
	and finalstatus='pending'
	and operation='$operation'
        and (accttype is NULL or accttype ='' or accttype='credit')
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthinfo->execute("$time$summaryid") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthinfo->finish;

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    my $sthop = $dbh2->prepare(
      qq{
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending'
          where orderid='$orderid'
          and username='$username'
          and $operationstatus ='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute("$time$summaryid") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;

    # insert into batchfilesfifth

    $batchreccnt++;
    $filereccnt++;
    $recseqnum++;
    $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

    $card_type = &smpsutils::checkcard($cardnumber);
    if ( ( $cardnumber =~ /^36/ ) && ( length($cardnumber) == 14 ) ) {
      $card_type = 'mc';
    }

    &batchdetail();

    if ( $transseqnum >= 998 ) {
      &batchtrailer();
      $batch_flag = 1;
    }

    if ( $batchcount >= 998 ) {
      &filetrailer();
      $file_flag = 1;
    }

    $banknumold     = $banknum;
    $currencyold    = $currency;
    $usernameold    = $username;
    $merchant_idold = $merchant_id;
    $batchidold     = "$time$summaryid";
    print "usernameold: $usernameold\n";
    print "batchidold: $batchidold\n";
  }
  $sthtrans->finish;
}

if ( $batch_flag == 0 ) {
  &batchtrailer();
  $batch_flag = 1;
}

if ( $file_flag == 0 ) {
  &filetrailer();
  $file_flag = 1;
}

$dbh->disconnect;
$dbh2->disconnect;

unlink "/home/p/pay1/batchfiles/$devprodlogs/fifththird/batchfile.txt";

umask 0033;
open( batchfile, ">/home/p/pay1/batchfiles/$devprodlogs/fifththird/genfiles.txt" );
close(batchfile);

$mytime = gmtime( time() );
umask 0077;
open( outfile, ">>/home/p/pay1/batchfiles/$devprodlogs/fifththird/ftplog.txt" );
print outfile "\n\n$mytime\n";
close(outfile);

#system("/home/p/pay1/batchfiles/$devprodlogs/fifththird/putfiles.pl >> /home/p/pay1/batchfiles/$devprodlogs/fifththird/ftplog.txt 2>\&1");

if ( ( $filecount > 0 ) && ( $filecount < 20 ) ) {
  for ( $myi = 0 ; $myi <= $filecount ; $myi++ ) {
    system("/home/p/pay1/batchfiles/$devprod/fifththird/putfiles.pl >> /home/p/pay1/batchfiles/$devprodlogs/fifththird/ftplog.txt 2>\&1");
    &miscutils::mysleep(40);
    system("/home/p/pay1/batchfiles/$devprod/fifththird/getfiles.pl >> /home/p/pay1/batchfiles/$devprodlogs/fifththird/ftplog.txt 2>\&1");
    &miscutils::mysleep(20);
  }
}

exit;

sub batchdetail {

  $origoperation = "";
  if ( $operation eq "postauth" ) {
    $sthdate = $dbh2->prepare(
      qq{
          select authtime,authstatus,forceauthtime,forceauthstatus
          from operation_log
          where orderid='$orderid'
          and username='$username'
          and lastoptime>='$onemonthsagotime'
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthdate->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ( $authtime, $authstatus, $forceauthtime, $forceauthstatus ) = $sthdate->fetchrow;
    $sthdate->finish;

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
      open( logfile, ">>/home/p/pay1/batchfiles/logs/fifththird/$fileyear/$username$time.txt" );
      print logfile "Error in batch detail: couldn't find trans_time $username $twomonthsago $orderid $trans_time\n";
      close(logfile);
      return;
    }
  }

  $transseqnum++;
  $transseqnum = substr( "0" x 6 . $transseqnum, -6, 6 );

  local $sthinfo = $dbh->prepare(
    qq{
        insert into batchfilesfifth
	(username,filename,filenum,batchname,batchnum,detailnum,trans_date,orderid,status)
        values (?,?,?,?,?,?,?,?,?)
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute( "$username", "$filename", "$newfilenum", "$summaryid", "$batchnum", "$transseqnum", "$today", "$orderid", "pending" )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthinfo->finish;

  $addendum = 0;

  $transtime = substr( $trans_time, 8, 6 );

  #$transamt = substr($amount,4);
  ( $transcurr, $transamt ) = split( / /, $amount );
  $transcurr =~ tr/a-z/A-Z/;
  $transexp = $isotables::currencyUSD2{$transcurr};
  $transamt = sprintf( "%010d", ( ( $transamt * ( 10**$transexp ) ) + .0001 ) );

  #$transamt = sprintf("%010d",(($transamt * 100) + .0001));

  $clen = length($cardnumber);
  $cabbrev = substr( $cardnumber, 0, 4 );

  $tcode     = substr( $tcode . " " x 2,     0, 2 );
  $transtime = substr( $transtime . " " x 6, 0, 6 );

  #$authsrc = substr($authsrc . " " x 1,0,1);
  $authresp = substr( $authresp . " " x 2, 0, 2 );
  $avs_code = substr( $avs_code . " " x 1, 0, 1 );

  # yyyy
  $dccinfo     = substr( $auth_code, 185, 27 );
  $dccoptout   = substr( $dccinfo,   0,   1 );    # optout (1)  amount (12)  currency (3)  0's (3)  rate (7)  exponent (1)
  $dccamount   = substr( $dccinfo,   1,   12 );
  $dcccurrency = substr( $dccinfo,   13,  3 );
  $dccrate     = substr( $dccinfo,   19,  7 );
  $dccexponent = substr( $dccinfo,   26,  1 );

  $detailcount++;
  @bd    = ();
  $bd[0] = "40";                                  # transaction code (2a)
  if ( $operation eq "return" ) {
    $ttype = "06";
  } else {
    $ttype = "05";
  }
  $bd[1] = $ttype;                                # transaction type (2a)
  $bd[2] = $transseqnum;                          # batch transaction number (6a)
  $bd[3] = "0";                                   # addendum sequence number (1n)
  $ccard = substr( $cardnumber . " " x 19, 0, 19 );
  $bd[4] = $ccard;                                # cardholder number (19a)
  $bd[5] = " ";                                   # memo post flag (1a)

  # xxxx 10/03/2006
  $oid = substr( "0" x 11 . $orderid, -11, 11 );
  $bd[6] = $oid;                                  # draft locator number (11a)
                                                  #$tdate = substr($trans_time,4,4) . substr($trans_time,2,2);
  $tdate = substr( $settledate, 4, 4 ) . substr( $settledate, 2, 2 );
  $bd[7] = $tdate;                                # transaction date - MMDDYY (6n)
  $amt2 = $transamt;

  # xxxx 06/27/2006
  if ( $transflags =~ /multicurrency/ ) {
    ( $d1, $amt2 ) = split( / /, $amount );
    $exponent = $isotables::currency8402{$dcccurrency};
    $amt2     = $amt2 * $dccrate * ( .1**$dccexponent );
    $amt2     = sprintf( "%d", ( ( $amt2 * ( 10**$exponent ) ) + .5001 ) );

    #$amt2 = sprintf("%d", $amt2 + .5001);
    $amt2 = substr( "0" x 10 . $amt2, -10, 10 );
  }
  $batchamt = $amt2;
  $transamt40 = $amt2 * ( .1**$exponent );
  print "exponent: $exponent\n";
  $bd[8] = $amt2;    # transaction amount (10n)
  $authsrc = substr( $auth_code,         99, 1 );
  $authsrc = substr( $authsrc . " " x 1, 0,  1 );
  if ( $authsrc eq " " ) {
    $authsrc = "5";
  }
  $bd[9] = $authsrc;    # authorization src (1a)
  $authcode = substr( $auth_code . " " x 6, 0, 6 );

  # xxxx temp to see if this fixes ax return problems
  if ( ( $card_type eq "ax" ) && ( $operation eq "return" ) ) {
    $authcode = "      ";
  }
  $bd[10] = $authcode;    # authorization number (6a)
  $bd[11] = " " x 10;     # discretionary data (10a)
  $eci = substr( $auth_code,     98, 1 );
  $eci = substr( $eci . " " x 1, 0,  1 );
  if ( ( $industrycode !~ /^(retail|restaurant|grocery)$/ ) && ( $eci eq " " ) ) {
    $eci = "1";
  }
  $bd[12] = $eci;         # mail/phone indicator (1a)

  $magstripetrack = substr( $auth_code, 54, 1 );
  $magstripetrack = substr( $magstripetrack . " " x 1, 0, 1 );

  #if ($magstripetrack =~ /^(1|2)$/) {}
  if ( $industrycode =~ /^(retail|restaurant)$/ ) {
    $poscapability = "2";
  } else {
    $poscapability = "9";
  }
  $bd[13] = $poscapability;    # pos terminal capability (1a)

  if ( $magstripetrack =~ /^(1|2)$/ ) {
    $posentry = "90";
  } else {
    $posentry = "01";
  }
  $bd[14] = $posentry;         # pos entry mode (2a)

  if ( $transflags =~ /moto/ ) {
    $cardholderid = "4";
  } elsif ( $industrycode =~ /retail/ ) {
    $cardholderid = "1";
  } else {
    $cardholderid = "4";
  }
  $bd[15] = $cardholderid;     # cardholder id method (1a)

  foreach $var (@bd) {
    print outfile "$var";

    $xs = $cardnumber;
    $xs =~ s/[0-9]/x/g;
    $var =~ s/$cardnumber/$xs/;
    print outfile2 "$var";

  }
  print outfile "\n";
  print outfile2 "\n";

  if ( $card_type eq "vi" ) {
    if ( ( $operation eq "postauth" ) && ( $origoperation ne "forceauth" ) ) {
      $detailcount++;
      @bd    = ();
      $bd[0] = "41";            # transaction code (2a)
      $bd[1] = "  ";            # reserved (2a)
      $bd[2] = $transseqnum;    # batch transaction number (6a)
      $addendum++;
      $bd[3] = $addendum;       # addendum sequence number (1n)
      $bd[4] = "1";             # format version number (1n)

      # yyyyy
      $dccinfo = substr( $auth_code, 185, 27 );

      #$dccoptout = substr($dccinfo,0,1);
      #$dccamount = substr($dccinfo,1,12);
      #$dccrate = substr($dccinfo,14,7);
      #$dcccurrency = substr($dccinfo,22,3);
      $dccoptout   = substr( $dccinfo, 0,  1 );    # optout (1)  amount (12)  currency (3)  0's (3)  rate (7)  exponent (1)
      $dccamount   = substr( $dccinfo, 1,  12 );
      $dcccurrency = substr( $dccinfo, 13, 3 );
      $dccrate     = substr( $dccinfo, 19, 7 );
      $dccexponent = substr( $dccinfo, 26, 1 );

      if ( ( $dccrate > 0 ) && ( $dccoptout eq "N" ) ) {
        $origamt  = $dccamount;
        $origcurr = $dcccurrency;
      } elsif ( $transflags =~ /multicurrency/ ) {
        ( $origcurr, $origamt ) = split( / /, $origamount );
        $origcurr =~ tr/a-z/A-Z/;
        $exponent = $isotables::currencyUSD2{$origcurr};
        $origcurr = $isotables::currencyUSD840{$origcurr};
        $origamt  = sprintf( "%012d", ( ( $origamt * ( 10**$exponent ) ) + .0001 ) );
      } else {
        ( $origcurr, $origamt ) = split( / /, $origamount );
        $origamt = sprintf( "%012d", ( ( $origamt * 100 ) + .0001 ) );
        $origcurr =~ tr/a-z/A-Z/;
        $origcurr = $isotables::currencyUSD840{$origcurr};
      }
      $amt2 = $origamt;

      # xxxx 06/27/2006
      #if ($transflags =~ /multicurrency/) {
      #  $amt2 = $amt2 * $dccrate * (.1 ** $dccexponent);
      #  $amt2 = sprintf("%d", $amt2 + .5001);
      #  $amt2 = substr("0" x 10 . $amt2,-10,10);
      #}
      $bd[5] = $amt2;    # authorized amount (12n)
      $origcurr = substr( $origcurr . " " x 3, 0, 3 );
      $bd[6] = $origcurr;    # authorized currency (3n)
      $aci = substr( $auth_code,     100, 1 );
      $aci = substr( $aci . " " x 1, 0,   1 );
      $bd[7] = $aci;         # authorization characteristics indicator (1a)
      $pass = substr( $auth_code,      6, 2 );
      $pass = substr( $pass . " " x 2, 0, 2 );
      $bd[8] = $pass;        # authorization response code (2a)
      $transid = substr( $auth_code,          101, 15 );
      $transid = substr( $transid . " " x 15, 0,   15 );
      $bd[9] = $transid;     # transaction identifier (15a)
      $validationcode = substr( $auth_code, 116, 4 );
      $validationcode = substr( $validationcode . " " x 4, 0, 4 );
      $bd[10] = $validationcode;    # validation code (4a)
      $categorycode = substr( $auth_code, 120, 4 );
      $categorycode = substr( $categorycode . " " x 4, 0, 4 );
      $bd[11] = $categorycode;      # merchant category code (4a)
      $transamt = substr( "0" x 12 . $transamt, -12, 12 );

      if ( ( $dccrate > 0 ) && ( $dccoptout eq "N" ) ) {
        $totauthamt = $dccamount;
      } else {
        $totauthamt = $transamt;
      }
      $amt2 = $totauthamt;

      # xxxx 06/27/2006
      #if ($transflags =~ /multicurrency/) {
      #  $amt2 = $amt2 * $dccrate * (.1 ** $dccexponent);
      #  $amt2 = sprintf("%d", $amt2 + .5001);
      #  $amt2 = substr("0" x 10 . $amt2,-10,10);
      #}
      $bd[12] = $amt2;      # total authorized amount (12n)
      $bd[13] = " ";        # cardholder activated terminal indicator (1a)
      $bd[14] = "     ";    # cash back (5n)
      $avs_code = substr( $avs_code . " ", 0, 1 );
      $bd[15] = $avs_code;    # avs response code (1a)
      $cvvresp = substr( $cvvresp . " ", 0, 1 );
      $bd[16] = $cvvresp;     # cvv response code (1a)

      if ( ( $card_type eq "vi" ) && ( $transflags =~ /(bill|install|recurring)/ ) ) {
        $bd[17] = "B";        # bill payment indicator (1a)
      } else {
        $bd[17] = " ";        # bill payment indicator (1a)
      }

      $cardlevelres = substr( $auth_code, 213, 2 );
      $cardlevelres = substr( $cardlevelres . " " x 2, 0, 2 );
      if ( $cardlevres =~ /[0-9]/ ) {
        $cardlevelres = substr( $auth_code, 225, 2 );
        $cardlevelres = substr( $cardlevelres . " " x 2, 0, 2 );
      }
      $bd[18] = $cardlevelres;    # card level results (2a)

      $bd[19] = " " x 4;          # reserved (4a)

      foreach $var (@bd) {
        print outfile "$var";
        print outfile2 "$var";
      }
      print outfile "\n";
      print outfile2 "\n";
    }

    if ( ( $transflags =~ /moto/ ) || ( $industrycode !~ /^(retail|restaurant|grocery)$/ ) ) {
      if ( ( $operation eq "postauth" ) && ( $origoperation ne "forceauth" ) ) {
        $detailcount++;
        @bd    = ();
        $bd[0] = "41";            # transaction code (2a)
        $bd[1] = "  ";            # reserved (2a)
        $bd[2] = $transseqnum;    # batch transaction number (6a)
        $addendum++;
        $bd[3] = $addendum;       # addendum sequence number (1n)
        $bd[4] = "2";             # format version number (1n)
        $avs_code = substr( $avs_code . " " x 1, 0, 1 );
        $bd[5] = $avs_code;       # avs response code (1a)
        $phone =~ s/[^0-9a-zA-Z]//g;
        $phone = substr( $phone . " " x 10, 0, 10 );
        $bd[6] = $phone;          # merchant telephone number (10n)
        $bd[7] = "1";             # purchase identifier format code (1n)
        $purchaseid = substr( $orderid . " " x 25, 0, 25 );
        $bd[8] = $purchaseid;     # purchase identifier (25n)

        if ( $transflags =~ /digital/ ) {
          $purchasetype = "D";
        } else {
          $purchasetype = "P";
        }
        $bd[9]  = $purchasetype;    # purchase type (1n)
        $bd[10] = " " x 30;         # reserved (30a)

        foreach $var (@bd) {
          print outfile "$var";
          print outfile2 "$var";
        }
        print outfile "\n";
        print outfile2 "\n";
      }
    }

    $detailcount++;
    @bd    = ();
    $bd[0] = "41";            # transaction code (2a)
    $bd[1] = "  ";            # reserved (2a)
    $bd[2] = $transseqnum;    # batch transaction number (6a)
    $addendum++;
    $bd[3] = $addendum;       # addendum sequence number (1n)
    $bd[4] = "9";             # format version number (1n)
    $bd[5] = "1";             # format version record type (1n)
    $tax    = substr( $auth_code,     15,  10 );
    $tax    = substr( "0" x 9 . $tax, -9,  9 );
    $taxind = substr( $auth_code,     212, 1 );

    if ( $taxind eq "2" ) {
      $taxind = "2";
      $tax    = "0" x 9;
    } elsif ( $tax == 0 ) {
      $taxind = "0";
    } else {
      $taxind = "1";
    }
    $bd[6] = $taxind;    # sales tax collected indicator (1a)
    $bd[7] = $tax;       # sales tax amount (9n)
    $bd[8] = " ";        # reserved (1a)
    $ponumber = substr( $auth_code,           25, 17 );
    $ponumber = substr( $ponumber . " " x 17, 0,  17 );
    $bd[9]  = $ponumber;    # customer reference id (17n)
    $bd[10] = " " x 8;      # reserved (8a)
    $bd[11] = "0";          # national tax collected indicator (1a)
    $bd[12] = "0" x 9;      # national tax amount (9n)
    $bd[13] = "0" x 9;      # other tax (9n)
    $bd[14] = " " x 12;     # reserved (12a)

    foreach $var (@bd) {
      print outfile "$var";
      print outfile2 "$var";
    }
    print outfile "\n";
    print outfile2 "\n";
  }

  if ( ( $card_type eq "vi" ) && ( $transflags =~ /install/ ) ) {
    $detailcount++;
    @bd    = ();
    $bd[0] = "41";            # transaction code (2a)
    $bd[1] = "  ";            # reserved (2a)
    $bd[2] = $transseqnum;    # batch transaction number (6a)
    $addendum++;
    $bd[3] = $addendum;       # addendum sequence number (1n)
    $bd[4] = "A";             # format version number (1n)
    $bd[5] = "1";             # format version record type (1n)

    $totalinstallamt = substr( $auth_code, 248, 12 );
    $totalinstallamt = substr( "0" x 12 . $totalinstallamt, -12, 12 );
    print "totalinstallamt: $totalinstallamt\n";
    $bd[6] = $totalinstallamt;    # total amount of all installments (12n)

    $transcurr =~ tr/a-z/A-Z/;
    $installcurr = $isotables::currencyUSD840{$transcurr};
    $installcurr = substr( $installcurr . " " x 3, 0, 3 );
    $bd[7]       = $installcurr;                             # currency code (3a)

    $numinstall = substr( $auth_code,            260, 3 );
    $numinstall = substr( "0" x 3 . $numinstall, -3,  3 );
    $bd[8] = $numinstall;                                    # number of installments (3)

    $installamt = substr( $auth_code,             263, 12 );
    $installamt = substr( "0" x 12 . $installamt, -12, 12 );
    $bd[9] = $installamt;                                    # installment amount (12n)

    $installnum = substr( $auth_code,            275, 3 );
    $installnum = substr( "0" x 3 . $installnum, -3,  3 );
    $bd[10] = $installnum;                                   # installment number (3)

    $installfreq = substr( $auth_code,         278, 1 );
    $installfreq = substr( $installfreq . " ", 0,   1 );
    $bd[11] = $installfreq;                                  # installment frequency (1a) B, M, W

    $bd[12] = " " x 33;                                      # reserved (33a)

    foreach $var (@bd) {
      print outfile "$var";
      print outfile2 "$var";
    }
    print outfile "\n";
    print outfile2 "\n";
  }

  if ( $card_type eq "mc" ) {
    if ( ( $operation eq "postauth" ) && ( $origoperation ne "forceauth" ) ) {
      $detailcount++;
      @bd    = ();
      $bd[0] = "41";            # transaction code (2a)
      $bd[1] = "  ";            # reserved (2a)
      $bd[2] = $transseqnum;    # batch transaction number (6a)
      $addendum++;
      $bd[3] = $addendum;       # addendum sequence number (1n)
      $bd[4] = "1";             # format version number (1n)
      $banknetrefnum = substr( $auth_code, 124, 9 );
      $banknetrefnum = substr( $banknetrefnum . " " x 9, 0, 9 );
      $bd[5] = $banknetrefnum;    # banknet reference number (9a)
      $banknetdate = substr( $auth_code,             133, 4 );
      $banknetdate = substr( $banknetdate . " " x 4, 0,   4 );
      $bd[6] = $banknetdate;      # banknet date (4a)
      $categorycode = substr( $auth_code, 120, 4 );
      $categorycode = substr( $categorycode . " " x 4, 0, 4 );
      $bd[7] = $categorycode;     # merchant category code (4a)

      if ( ( $transflags !~ /(moto|recurring|install|bill)/ ) && ( $industrycode !~ /(retail|restaurant|grocery)/ ) ) {
        $catlevel = "6";
      } else {
        $catlevel = " ";
      }
      $bd[8] = $catlevel;         # cardholder activated terminal level (1a)
      $terminal_id = substr( $terminal_id . " " x 8, 0, 8 );
      $bd[9] = $terminal_id;      # terminal id (8a)
      $cvvresp = substr( $cvvresp . " ", 0, 1 );
      $bd[10] = $cvvresp;         # cvv response code (1a)
      $bd[11] = " " x 41;         # reserved (41a)

      foreach $var (@bd) {
        print outfile "$var";
        print outfile2 "$var";
      }
      print outfile "\n";
      print outfile2 "\n";
    }

    $detailcount++;
    @bd    = ();
    $bd[0] = "41";                # transaction code (2a)
    $bd[1] = "  ";                # reserved (2a)
    $bd[2] = $transseqnum;        # batch transaction number (6a)
    $addendum++;
    $bd[3] = $addendum;           # addendum sequence number (1n)
    $bd[4] = "9";                 # format version number (1n)
    $bd[5] = "1";                 # format version record type (1n)
    $ponumber = substr( $auth_code,           25, 17 );
    $ponumber = substr( $ponumber . " " x 17, 0,  17 );
    $bd[6] = $ponumber;           # customer reference id (17n)
    $tax    = substr( $auth_code,     15,  10 );
    $tax    = substr( "0" x 9 . $tax, -9,  9 );
    $taxind = substr( $auth_code,     212, 1 );

    if ( $taxind eq "2" ) {
      $taxind = "2";
      $tax    = "0" x 9;
    } elsif ( $tax == 0 ) {
      $taxind = "0";
    } else {
      $taxind = "1";
    }
    $bd[7] = $taxind;    # sales tax collected indicator (1a)
    $bd[8] = $tax;       # sales tax amount (9n)
    $freight = substr( $auth_code,         137, 9 );
    $freight = substr( "0" x 9 . $freight, -9,  9 );
    $bd[9] = $freight;    # freight amount (9n)
    $duty = substr( $auth_code,      146, 9 );
    $duty = substr( "0" x 9 . $duty, -9,  9 );
    $bd[10] = $duty;      # duty amount (9n)
    $bd[11] = "0";        # national tax collected indicator (1a)
    $bd[12] = "0" x 9;    # national tax amount (9n)
    $shipfromzip = substr( $auth_code, 155, 9 );
    $shipfromzip = substr( $shipfromzip . " " x 10, 0, 10 );
    $bd[13] = $shipfromzip;    # ship from postal code (10n)
    $bd[14] = " " x 2;         # reserved (2a)

    foreach $var (@bd) {
      print outfile "$var";
      print outfile2 "$var";
    }
    print outfile "\n";
    print outfile2 "\n";

    $detailcount++;
    @bd    = ();
    $bd[0] = "41";             # transaction code (2a)
    $bd[1] = "  ";             # reserved (2a)
    $bd[2] = $transseqnum;     # batch transaction number (6a)
    $addendum++;
    $bd[3] = $addendum;        # addendum sequence number (1n)
    $bd[4] = "9";              # format version number (1n)
    $bd[5] = "2";              # format version record type (1n)
    $shiptozip = substr( $auth_code,            164, 9 );
    $shiptozip = substr( $shiptozip . " " x 10, 0,   10 );
    $bd[6] = $shiptozip;       # destination postal code (10a)
    $country = substr( $auth_code, 173, 2 );

    if ( $country eq "  " ) {
      $country = "US";
    }
    $country =~ tr/a-z/A-Z/;
    $country  = $isotables::countryUS840{$country};
    $country  = substr( $country . " " x 3, 0, 3 );
    $bd[7]    = $country;                                # destination country code (3a)
    $bd[8]    = " " x 4;                                 # merchant type (4a)
    $bd[9]    = " " x 10;                                # merchant location postal code (10a)
    $bd[10]   = " " x 15;                                # merchant tax id (15a)
    $bd[11]   = " " x 3;                                 # merchant state/province code (3a)
    $ponumber = substr( $auth_code, 25, 17 );
    $ponumber = substr( $ponumber . " " x 17, 0, 17 );
    $bd[12]   = $ponumber;                               # merchant reference number (17a)
    $bd[13]   = " " x 5;                                 # reserved (5a)

    foreach $var (@bd) {
      print outfile "$var";
      print outfile2 "$var";
    }
    print outfile "\n";
    print outfile2 "\n";
  }

  if ( $card_type eq "ax" ) {
    $transid = substr( $auth_code, 101, 15 );
    $transid =~ s/ //g;
    if ( ( ( ( $operation eq "postauth" ) && ( $origoperation ne "forceauth" ) ) && ( $transid ne "" ) ) || ( $operation eq "return" ) ) {
      $detailcount++;
      @bd    = ();
      $bd[0] = "41";            # transaction code (2a)
      $bd[1] = "  ";            # reserved (2a)
      $bd[2] = $transseqnum;    # batch transaction number (6a)
      $addendum++;
      $bd[3] = $addendum;       # addendum sequence number (1n)
      $bd[4] = "1";             # format version number (1n)
      $bd[5] = "1";             # format version record type (1n)
      $transid = substr( $transid . " " x 15, 0, 15 );

      if ( $operation eq "return" ) {
        $transid = "0" x 15;
      }
      $bd[6] = $transid;        # transaction identifier (15n)
      $bd[7] = "20";            # transaction format code (2a)
      if ( $transflags =~ /moto/ ) {
        $mediacode = "03";
      } elsif ( $transflags =~ /recurring|install|bill/ ) {
        $mediacode = "05";
      } elsif ( $industrycode eq "retail" ) {
        $mediacode = "01";
      } else {
        $mediacode = "04";
      }
      $bd[8] = $mediacode;      # media code (2a)
      $transcurr =~ tr/a-z/A-Z/;
      $transcurr = substr( $transcurr . " " x 3, 0, 3 );
      $bd[9] = $transcurr;      # currency code (3a)
      $terminal_id = substr( $terminal_id . " " x 8, 0, 8 );
      $bd[10] = $terminal_id;    # terminal id (8a)

      $poscodes = substr( $auth_code,           215, 12 );
      $poscodes = substr( $poscodes . " " x 12, 0,   12 );

      #if ($poscodes !~ /[0-9]{12}/) {
      #  $poscodes = substr($auth_code,213,12);
      #  $poscodes = substr($poscodes . " " x 12,0,12);
      #}
      if ( $operation eq "return" ) {
        $poscodes = "200120100000";
      }
      $bd[11] = $poscodes;    # pos entry codes (12a)

      #$magstripetrack = substr($auth_code,54,1);
      #$magstripetrack = substr($magstripetrack . " " x 1,0,1);
      #if ($magstripetrack =~ /^(1|2)$/) {
      #  $poscapability = "2";
      #}
      #else {
      #  $poscapability = "6";
      #}
      #$bd[11] = $poscapability;		# card data input capability (1a)
      #$bd[12] = "0";			# cardholder authentication (1a)
      #$bd[13] = "0";			# card capture capability (1a)
      #if ($transflags =~ /moto/) {
      #  $openv = "3";
      #}
      #elsif ($industrycode eq "retail") {
      #  $openv = "1";
      #}
      #else {
      #  $openv = "5";
      #}
      #$bd[14] = $openv;			# operating environment (1a)
      #if ($transflags =~ /moto/) {
      #  $cardholdpres = "2";
      #  $cardpres = "0";
      #}
      #elsif ($transflags =~ /recurring|install|bill/) {
      #  $cardholdpres = "9";
      #  $cardpres = "0";
      #}
      #elsif ($industrycode eq "retail") {
      #  $cardholdpres = "0";
      #  $cardpres = "1";
      #}
      #else {
      #  $cardholdpres = "1";
      #  $cardpres = "0";
      #}
      #$bd[15] = $cardholdpres;	# cardholder present (1a)
      #$bd[16] = $cardpres;		# card present (1a)
      #if ($magstripetrack =~ /^(1|2)$/) {
      #  $inputmode = "2";
      #}
      #else {
      #  $inputmode = "6";
      #}
      #$bd[17] = $inputmode;		# card data input mode (1a)
      #$bd[18] = "0";			# cardmember authentication (1a)
      #$bd[19] = "0";			# cardmember authentication entity (1a)
      #$bd[20] = "0";			# card data output capability (1a)
      #$bd[21] = "0";			# terminal output capability (1a)
      #$bd[22] = "0";			# PIN capture capability (1a)
      $bd[23] = " " x 25;    # reserved (25a)

      foreach $var (@bd) {
        print outfile "$var";
        print outfile2 "$var";
      }
      print outfile "\n";
      print outfile2 "\n";
    }

    #$detailcount++;
    #@bd = ();
    #$bd[0] = "42";			# transaction code (2a)
    #$bd[1] = "  ";			# reserved (2a)
    #$bd[2] = $transseqnum;		# batch transaction number (6a)
    #$addendum++;
    #$bd[3] = $addendum;		# addendum sequence number (1n)
    #$bd[4] = "1";			# format version number (1n)
    #$descr = substr($company . " " x 23,0,23);
    #$bd[5] = $descr;			# amex charge descriptor (23a)
    #$bd[6] = " " x 45;       		# reserved (45a)

    #foreach $var (@bd) {
    #  print outfile "$var";
    #}
    #print outfile "\n";
  }

  # not supported yet?
  if ( (1) && ( $card_type eq "ds" ) ) {
    $detailcount++;
    @bd    = ();
    $bd[0] = "41";            # transaction code (2a)
    $bd[1] = "  ";            # reserved (2a)
    $bd[2] = $transseqnum;    # batch transaction number (6a)
    $addendum++;
    $bd[3] = $addendum;       # addendum sequence number (1n)
    $bd[4] = "1";             # format version number (1n)

    # cashback not supported yet
    $cashback = substr( $auth_code, 234, 12 );
    $cashback =~ s/ //g;
    $cashback = substr( "0" x 12 . $cashback, -12, 12 );

    #$cashback = "0" x 12;
    $bd[5] = $cashback;       # cashback (12n)

    $bd[6] = "N";             # parial shipment ind (1a)
    my $authdate = "";
    my $authmmdd = "";
    my $authtime = "";
    my $authyear = "";
    if ( $operation eq "postauth" ) {
      $authdate = substr( $auth_code, 279, 14 );
      $authmmdd = substr( $authdate,  4,   4 );
      $authtime = substr( $authdate,  8,   6 );
      $authyear = substr( $authdate,  0,   4 );
    }
    $authmmdd = substr( $authmmdd . " " x 4, 0, 4 );
    $authtime = substr( $authtime . " " x 6, 0, 6 );
    $authyear = substr( $authyear . " " x 4, 0, 4 );
    $bd[7] = $authmmdd;    # auth date (4a)
    $bd[8] = $authtime;    # auth time (6a)
    $bd[9] = " " x 16;     # discover merchant number (16a)
    $categorycode = substr( $auth_code, 120, 4 );
    $categorycode = substr( $categorycode . " " x 4, 0, 4 );
    $bd[10] = $categorycode;    # merchant category code (4a)
    $bd[11] = $authyear;        # auth date year (4a)
    my ( $sec, $min, $hour, $day2, $month, $year, $wday, $yday, $isdst ) = localtime( time() );
    $ltranstime = sprintf( "%02d%02d%02d", $hour, $min, $sec );
    $bd[12] = $ltranstime;      # transaction time (6a)
    $pcode = substr( $auth_code, 293, 6 );
    $bd[13] = $pcode;           # processing code (6a)
    $tracenum = substr( $auth_code, 59, 6 );
    $bd[14] = $tracenum;        # system trace audit number stan (6n)
    $trackstatus = substr( $auth_code,          246, 2 );
    $trackstatus = substr( $trackstatus . "  ", 0,   2 );
    $bd[15] = $trackstatus;     # track 1 and 2 data ind (2n)
    $bd[16] = " ";              # reserved (1a)

    foreach $var (@bd) {
      print outfile "$var";
      print outfile2 "$var";
    }
    print outfile "\n";
    print outfile2 "\n";

    $detailcount++;
    @bd    = ();
    $bd[0] = "41";              # transaction code (2a)
    $bd[1] = "  ";              # reserved (2a)
    $bd[2] = $transseqnum;      # batch transaction number (6a)
    $addendum++;
    $bd[3] = $addendum;         # addendum sequence number (1n)
    $bd[4] = "2";               # format version number (1n)
    $bd[5] = "  ";              # pos entry mode (2n)
    $bd[6] = " ";               # pin entry capability (1n)
    $bd[7] = " " x 13;          # posdatacode (13a)
    $bd[8] = "  ";              # auth response code (2a)
    $transid = substr( $auth_code,          101, 15 );
    $transid = substr( $transid . " " x 15, 0,   15 );
    $bd[9]  = $transid;         # network reference id (15a)
    $bd[10] = " ";              # avs response code (1a)
    $bd[11] = "0" x 12;         # sales tax (12n)
    $bd[12] = " " x 22;         # reserved (22a)

    foreach $var (@bd) {
      print outfile "$var";
      print outfile2 "$var";
    }
    print outfile "\n";
    print outfile2 "\n";

  }

  my $conveniencefee = substr( $auth_code, 227, 7 );
  if ( $conveniencefee > 0 ) {
    $detailcount++;
    @bd    = ();
    $bd[0] = "47";            # transaction code (2a)
    $bd[1] = "  ";            # reserved (2a)
    $bd[2] = $transseqnum;    # batch transaction number (6a)
    $addendum++;
    $bd[3] = $addendum;       # addendum sequence number (1n)
    $bd[4] = "1";             # format version number (1n)

    $conveniencefee = substr( "0" x 7 . $conveniencefee, -7, 7 );
    $bd[5] = $conveniencefee;    # convenience fee (7n)

    $bd[6] = " " x 61;           # reserved (61a)

    foreach $var (@bd) {
      print outfile "$var";
      print outfile2 "$var";
    }
    print outfile "\n";
    print outfile2 "\n";
  }

  $dccinfo = " " x 27;
  if ( ( $operation eq "postauth" ) || ( $transflags =~ /multicurrency/ ) ) {
    $dccinfo = substr( $auth_code, 185, 27 );

    # yyyyy
    #$dccoptout = substr($dccinfo,0,1);
    #$dccamount = substr($dccinfo,1,12);
    #$dccexponent = substr($dccinfo,13,1);
    #$dccrate = substr($dccinfo,14,7);
    #$dcccurrency = substr($dccinfo,22,3);
    $dccoptout   = substr( $dccinfo, 0,  1 );    # optout (1)  amount (12)  currency (3)  0's (3)  rate (7)  exponent (1)
    $dccamount   = substr( $dccinfo, 1,  12 );
    $dcccurrency = substr( $dccinfo, 13, 3 );
    $dccrate     = substr( $dccinfo, 19, 7 );
    $dccexponent = substr( $dccinfo, 26, 1 );

    #$dccexponent = substr($dccinfo,24,1);
    #$dccexponent = $isotables::currency8402{"$dcccurrency"};
    print "auth_code: $auth_code\n";
    print "dccinfo: $dccinfo\n";
    print "dccoptout: $dccoptout\n";
    print "dccamount: $dccamount\n";
    print "dccrate: $dccrate\n";
    print "dcccurrency: $dcccurrency\n";
    print "dccexponent: $dccexponent\n";
  }

  if ( ( ( $operation eq "postauth" ) && ( $dcccurrency > 0 ) )
    || ( ( $dccoptout eq "M" ) && ( $dcccurrency > 0 ) ) ) {

    if ( $dccoptout eq "M" ) {
      $finaltransamt = $transamt;
    } elsif ( $industrycode eq "restaurant" ) {
      $finaltransamt = $transamt * $dccrate * ( .1**$dccexponent );
    } else {
      $finaltransamt = $dccamount;
    }
    $finaltransamt = sprintf( "%d", $finaltransamt + .5001 );
    $finaltransamt = substr( "0" x 12 . $finaltransamt, -12, 12 );

    if ( $dccrate > 0 ) {
      $detailcount++;
      @bd          = ();
      $bd[0]       = "52";                                      # transaction code (2a)
      $bd[1]       = "  ";                                      # reserved (2a)
      $transseqnum = substr( "0" x 6 . $transseqnum, -6, 6 );
      $bd[2]       = $transseqnum;                              # batch transaction number (6a)
      $addendum++;
      $bd[3] = $addendum;                                       # addendum sequence number (1n)
      $bd[4] = "1";                                             # format version number (1n)

      if ( $transflags =~ /multicurrency/ ) {
        $dccoptin = "M";
      } elsif ( $dccoptout eq "N" ) {
        $dccoptin = "Y";
      } else {
        $dccoptin = "N";
      }
      $bd[5] = $dccoptin;                                       # dcc participation indicator (1a)
      if ( $transflags =~ /multicurrency/ ) {
        print "$operation  $transflags\n";
        if ( $operation eq "return" ) {
          $sthamt = $dbh2->prepare(
            qq{
          select returnamount
          from operation_log
          where orderid='$orderid'
          and username='$username' 
          and trans_date>='$twomonthsago'
          and (returnstatus is not NULL and returnstatus<>'')
          }
            )
            or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
          $sthamt->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
          ($origamount) = $sthamt->fetchrow;
          $sthamt->finish;
          print "$origamount  $transflags\n";
        }
        ($origcurr) = split( / /, $origamount );
        $origcurr =~ tr/a-z/A-Z/;
        $dcccurrency = $isotables::currencyUSD840{$origcurr};
      }
      $dcccurrency = substr( "0" x 3 . $dcccurrency, -3, 3 );
      $bd[6] = $dcccurrency;    # currency conversion code (3a)

      print "dccrate: $dccrate\n";
      if ( $transflags =~ /multicurrency/ ) {
        $invrate = 1 / ( $dccrate * ( .1**$dccexponent ) );
        print "invratea: $invrate\n";
        $invrate = $invrate * ( 10**$dccexponent );
        print "invrateb: $invrate\n";
        $invrate = sprintf( "%d", $invrate + .50001 );
        $ratelen = length($invrate);
        print "invrate: $invrate\n";
        if ( $ratelen > 9 ) {
          $invrate = $invrate * ( .1**( $ratelen - 9 ) );
          $invrate = sprintf( "%d", $invrate + .0001 );
          $dccexponent = $dccexponent - ( $ratelen - 9 );
        }
        print "newrate: $newrate\n";
        $newrate = substr( "0" x 10 . $invrate, -10, 10 );
      } else {
        $newrate = substr( "0" x 10 . $dccrate, -10, 10 );
      }
      $bd[7] = $newrate;    # currency conversion rate (10n)
      $dccexponent = substr( "0" . $dccexponent, -1, 1 );
      $bd[8] = $dccexponent;    # currency exponent (1n)

      #if ($transflags =~ /multicurrency/) {
      #$dccamount = sprintf("%012d",($transamt40 * ($newrate * (.1 ** ($dccexponent)))) + .5001);
      $dccamount = sprintf( "%012d", ( $transamt40 * ( 10**$transexp ) * ( $newrate * ( .1**($dccexponent) ) ) ) + .5001 );
      print "cccc $transamt40  $transexp  $newrate  $dccexponent  $dccamount\n";

      #}
      $dccamount = substr( "0" x 11 . $dccamount, -11, 11 );
      $bd[9]  = $dccamount;    # foreign transaction amount (11n)
      $bd[10] = " " x 42;      # reserved (42a)
      print "dccamount: $dccamount\n";

      foreach $var (@bd) {
        print outfile "$var";
        print outfile2 "$var";
      }
      print outfile "\n";
      print outfile2 "\n";
    }
  }

  # xxxx 06/27/2006
  #if ($transflags =~ /multicurrency/) {
  #  $amt2 = $amt2 * $dccrate * (.1 ** $dccexponent);
  #  $amt2 = sprintf("%d", $amt2 + .5001);
  #}

  #open(batchfile,">>/home/p/pay1/batchfiles/$devprodlogs/fifththird/tempfile.txt");
  #print batchfile "$orderid  $amt2  $dccrate  $dccexponent  $transamt\n";
  #close(batchfile);

  #$amt2 = $transamt;
  $amt2 = $batchamt;
  if ( $operation eq "postauth" ) {
    $batchtotalamt = $batchtotalamt + $amt2;
    $batchtotalcnt = $batchtotalcnt + 1;
    $batchsalesamt = $batchsalesamt + $amt2;
    $batchsalescnt = $batchsalescnt + 1;
    $filetotalamt  = $filetotalamt + $amt2;
    $filetotalcnt  = $filetotalcnt + 1;
    $filesalesamt  = $filesalesamt + $amt2;
    $filesalescnt  = $filesalescnt + 1;
  } else {
    $batchtotalamt = $batchtotalamt - $amt2;
    $batchtotalcnt = $batchtotalcnt + 1;
    $batchretamt   = $batchretamt + $amt2;
    $batchretcnt   = $batchretcnt + 1;
    $filetotalamt  = $filetotalamt - $amt2;
    $filetotalcnt  = $filetotalcnt + 1;
    $fileretamt    = $fileretamt + $amt2;
    $fileretcnt    = $fileretcnt + 1;
  }

}

sub batchheader {
  $batch_flag  = 0;
  $detailcount = 0;

  $batchcount++;

  print "aaaa$batchnum\n";
  $batchnum = $batchnum + 1;
  if ( $batchnum >= 9999 ) {
    $batchnum = 1;
  }
  print "bbbb$batchnum\n";

  $batchreccnt = 1;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );
  $batchnum  = substr( "0" x 6 . $batchnum,    -6, 6 );
  $batchdate = $createdate;
  $batchdate = substr( $batchdate . " " x 6,   0,  6 );
  $batchtime = $createtime;
  $batchtime = substr( $batchtime . " " x 6,   0,  6 );

  $transseqnum   = 0;
  $batchtotalcnt = 0;
  $batchtotalamt = 0;
  $batchretcnt   = 0;
  $batchretamt   = 0;
  $batchsalescnt = 0;
  $batchsalesamt = 0;

  @bh      = ();
  $bh[0]   = "10";                                                # tran code (2a)
  $bh[1]   = $batchnum;                                           # relative batch # (6a)
  $bh[2]   = $createdate;                                         # process date - YYMMDD (6n)
  $mid     = substr( "4445" . $merchant_id . " " x 16, 0, 16 );
  $bh[3]   = $mid;                                                # store merchant number (16a)
  $company = substr( $company . " " x 25, 0, 25 );
  $bh[4]   = $company;                                            # merchant name (25a)
  $city    = substr( $city . " " x 13, 0, 13 );
  $bh[5]   = $city;                                               # merchant city (13a)
  $state   = substr( $state . " " x 2, 0, 2 );
  $bh[6]   = $state;                                              # merchant state (2a)
  $bh[7]   = "    ";                                              # SIC code (4a)
  $bh[8]   = "E";                                                 # transaction type (1a)
  $zip     = substr( $zip . " " x 5, 0, 5 );
  $bh[9]   = $zip;                                                # merchant zip (5a)

  foreach $var (@bh) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "\n";
  print outfile2 "\n";

  @bh      = ();
  $bh[0]   = "11";                                                # tran code (2a)
  $company = substr( $company . " " x 25, 0, 25 );
  $bh[1]   = $company;                                            # merchant name (25a)
  if ( $industrycode eq "restaurant" ) {
    $formatcode = "12";
  } else {
    $formatcode = "10";
  }
  $bh[2] = $formatcode;                                           # amex format code (2a)
  $bh[3] = " " x 10;                                              # amex service establishment # (10a)
  $city = substr( $city . " " x 18, 0, 18 );
  $bh[4] = $city;                                                 # merchant city (18a)
  $bh[5] = "50100010056";                                         # amex inv batch code, inv sub code, process control id (11a)
  $bh[6] = " " x 12;                                              # filler (12a)

  foreach $var (@bh) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "\n";
  print outfile2 "\n";
}

sub batchtrailer {
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

  $batchretcnt = substr( "0000000" . $batchretcnt,     -6,  6 );
  $batchretamt = substr( "00000000000" . $batchretamt, -11, 11 );
  $batchreccnt = substr( "0000000" . $batchreccnt,     -7,  7 );

  $batchtotalamtstr = $batchtotalamt;
  if ( $batchtotalamt < 0 ) {
    $batchtotalamt    = 0 - $batchtotalamt;
    $batchtotalamtstr = 0 - $batchtotalamt;
    $batchtotalamtstr = $batchtotalamtstr . "-";
    my $mychar = substr( $batchtotalamt, -1, 1 );
    $batchtotalamt = substr( $batchtotalamt, 0, length($batchtotalamt) - 1 );
    if ( $mychar eq "0" ) {
      $batchtotalamt = $batchtotalamt . "}";
    } elsif ( $mychar eq "1" ) {
      $batchtotalamt = $batchtotalamt . "J";
    } elsif ( $mychar eq "2" ) {
      $batchtotalamt = $batchtotalamt . "K";
    } elsif ( $mychar eq "3" ) {
      $batchtotalamt = $batchtotalamt . "L";
    } elsif ( $mychar eq "4" ) {
      $batchtotalamt = $batchtotalamt . "M";
    } elsif ( $mychar eq "5" ) {
      $batchtotalamt = $batchtotalamt . "N";
    } elsif ( $mychar eq "6" ) {
      $batchtotalamt = $batchtotalamt . "O";
    } elsif ( $mychar eq "7" ) {
      $batchtotalamt = $batchtotalamt . "P";
    } elsif ( $mychar eq "8" ) {
      $batchtotalamt = $batchtotalamt . "Q";
    } elsif ( $mychar eq "9" ) {
      $batchtotalamt = $batchtotalamt . "R";
    }
  }
  if ( $batchsalesamt < 0 ) {
    $batchsalesamt = 0 - $batchsalesamt;
  }
  if ( $batchretamt < 0 ) {
    $batchretamt = 0 - $batchretamt;
  }

  $batchtotalamt = substr( "0" x 10 . $batchtotalamt, -10, 10 );
  $batchsalescnt = substr( "0" x 6 . $batchsalescnt,  -6,  6 );
  $batchsalesamt = substr( "0" x 10 . $batchsalesamt, -10, 10 );
  $batchretcnt   = substr( "0" x 6 . $batchretcnt,    -6,  6 );
  $batchretamt   = substr( "0" x 10 . $batchretamt,   -10, 10 );
  $batchcount    = substr( "0" x 6 . $batchcount,     -6,  6 );
  $batchnum      = substr( "0" x 6 . $batchnum,       -6,  6 );
  $detailcount   = substr( "0" x 6 . $detailcount,    -6,  6 );

  #if ($filetotalamt < 0) {
  #  $filetotalamt = 0 - $filetotalamt;
  #}

  @bt     = ();
  $bt[0]  = "80";              # tran code (2a)
  $bt[1]  = $batchnum;         # relative batch # (6a)
  $bt[2]  = $createdate;       # process date - YYMMDD (6n)
  $bt[3]  = $detailcount;      # record count (6)
  $bt[4]  = $batchtotalamt;    # net batch total amount - no decimal (10n)
  $bt[5]  = $batchsalescnt;    # sale transaction count (6n)
  $bt[6]  = $batchsalesamt;    # sale total amount (10n)
  $bt[7]  = $batchretcnt;      # return transaction count (6n)
  $bt[8]  = $batchretamt;      # return total amount (10n)
  $bt[9]  = $createdate;       # date batch closed (6n)
  $bt[10] = $createtime;       # time batch closed (4n)
  $bt[11] = " " x 8;           # filler (8a)

  foreach $var (@bt) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "\n";
  print outfile2 "\n";

}

sub fileheader {
  print "in fileheader\n";
  $batchcount = 0;
  $filecount++;

  $file_flag = 0;
  local $sthinfo = $dbh->prepare(
    qq{
        select filenum
        from fifththird
        where username='fifththird'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ($filenum) = $sthinfo->fetchrow;
  $sthinfo->finish;

  #if ($batchdate != $today) {
  #  $filenum = 0;
  #}
  $filenum = $filenum + 1;
  if ( $filenum > 998 ) {
    $filenum = 1;
  }

  $filename = &miscutils::incorderid($filename);

  local $sthinfo = $dbh->prepare(
    qq{
        update fifththird set filenum=?
	where username='fifththird'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute("$filenum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthinfo->finish;

  umask 0077;
  open( outfile,  ">/home/p/pay1/batchfiles/logs/fifththird/$fileyear/$filename" );
  open( outfile2, ">/home/p/pay1/batchfiles/logs/fifththird/$fileyear/$filename.txt" );

  $customerid = substr( $customerid . " " x 10, 0, 10 );

  $filesalescnt = 0;
  $filesalesamt = 0;
  $fileretcnt   = 0;
  $fileretamt   = 0;
  $filereccnt   = 1;
  $filetotalamt = 0;
  $filetotalcnt = 0;
  $recseqnum    = 1;
  $recseqnum    = substr( "0000000" . $recseqnum, -7, 7 );
  $fileid       = substr( $fileid . " " x 20, 0, 20 );

  @fh         = ();
  $fh[0]      = "00";                                          # transaction code (2n)
  $fh[1]      = "000001";                                      # relative file number (6n)
  $createdate = substr( $today, 2, 6 );
  $fh[2]      = $createdate;                                   # process date - YYMMDD (6n)
  $fh[3]      = "00099";                                       # originating id (5n)
  $fh[4]      = "04200031";                                    # destination id (8n)
  $fh[5]      = $createdate;                                   # creation date - YYMMDD (6n)
  $createtime = substr( $todaytime, 8, 4 );
  $fh[6]      = $createtime;                                   # creation time - HHMM (4n)
  $filenum    = substr( "0" x 3 . $filenum, -3, 3 );
  $julian     = substr( "0" x 3 . $julian, -3, 3 );
  $newfilenum = substr( $today, 0, 4 ) . $julian . $filenum;
  $fh[7]      = $newfilenum;                                   # file submission number - YYYYDDDSSS (10a)
  $fh[8]      = " " x 23;                                      # filler (23a)
  $fh[9]      = " " x 10;                                      # reserved (10a)

  foreach $var (@fh) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "\n";
  print outfile2 "\n";

}

sub filetrailer {
  if ( $filetotalamt < 0 ) {
    $filetotalamtstr = sprintf( "%.2f", ( $filetotalamt / 100 ) - .0001 );
  } else {
    $filetotalamtstr = sprintf( "%.2f", ( $filetotalamt / 100 ) + .0001 );
  }

  if ( $filetotalamt < 0 ) {
    $filetotalamt = 0 - $filetotalamt;
    my $mychar = substr( $filetotalamt, -1, 1 );
    $filetotalamt = substr( $filetotalamt, 0, length($filetotalamt) - 1 );
    if ( $mychar eq "0" ) {
      $filetotalamt = $filetotalamt . "}";
    } elsif ( $mychar eq "1" ) {
      $filetotalamt = $filetotalamt . "J";
    } elsif ( $mychar eq "2" ) {
      $filetotalamt = $filetotalamt . "K";
    } elsif ( $mychar eq "3" ) {
      $filetotalamt = $filetotalamt . "L";
    } elsif ( $mychar eq "4" ) {
      $filetotalamt = $filetotalamt . "M";
    } elsif ( $mychar eq "5" ) {
      $filetotalamt = $filetotalamt . "N";
    } elsif ( $mychar eq "6" ) {
      $filetotalamt = $filetotalamt . "O";
    } elsif ( $mychar eq "7" ) {
      $filetotalamt = $filetotalamt . "P";
    } elsif ( $mychar eq "8" ) {
      $filetotalamt = $filetotalamt . "Q";
    } elsif ( $mychar eq "9" ) {
      $filetotalamt = $filetotalamt . "R";
    }
  }
  if ( $filesalesamt < 0 ) {
    $filesalesamt = 0 - $filesalesamt;
  }
  if ( $fileretamt < 0 ) {
    $fileretamt = 0 - $fileretamt;
  }

  $filereccnt++;
  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

  $filetotalamt = substr( "0" x 10 . $filetotalamt, -10, 10 );
  $filesalescnt = substr( "0" x 6 . $filesalescnt,  -6,  6 );
  $filesalesamt = substr( "0" x 10 . $filesalesamt, -10, 10 );
  $fileretcnt   = substr( "0" x 6 . $fileretcnt,    -6,  6 );
  $fileretamt   = substr( "0" x 10 . $fileretamt,   -10, 10 );
  $batchcount   = substr( "0" x 6 . $batchcount,    -6,  6 );

  @ft    = ();
  $ft[0] = "90";             # tran code (2a)
  $ft[1] = "000001";         # relative file # (6a)
  $ft[2] = $createdate;      # process date - YYMMDD (6n)
  $ft[3] = $batchcount;      # batch count (6)
  $ft[4] = $filetotalamt;    # net file total amount - no decimal (10n)
  $ft[5] = $filesalescnt;    # sale transaction count (6n)
  $ft[6] = $filesalesamt;    # sale total amount (10n)
  $ft[7] = $fileretcnt;      # return transaction count (6n)
  $ft[8] = $fileretamt;      # return total amount (10n)
  $ft[9] = " " x 18;         # filler (18a)

  #$filereccnt = substr("000000" . $filereccnt,-6,6);
  #$ft[4] = $filereccnt;		# file record count (6n)

  foreach $var (@ft) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "\n";
  print outfile2 "\n";

  close(outfile);
  close(outfile2);

  print "filenum: $newfilenum  today: $today  amt: $filetotalamtstr  cnt: $filetotalcnt\n";

  local $sthinfo = $dbh->prepare(
    qq{
        update batchfilesfifth
        set amount=?,count=?
        where trans_date='$today'
        and filenum='$newfilenum'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute( "$filetotalamtstr", "$filetotalcnt" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthinfo->finish;
}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  print "origtime: $origtime $timezone1\n";

  if ( length($origtime) != 14 ) {
    return $origtime;
  }

  # timezone  hours  week of month  day of week  month  time   hours  week of month  day of week  month  time
  %timezonearray = (
    'EST', '-4,2,0,3,02:00, -5,1,0,11,02:00',    # 4 hours starting 2nd Sunday in March at 2am, 5 hours starting 1st Sunday in November at 2am
    'CST', '-5,2,0,3,02:00, -6,1,0,11,02:00',    # 5 hours starting 2nd Sunday in March at 2am, 6 hours starting 1st Sunday in November at 2am
    'MST', '-6,2,0,3,02:00, -7,1,0,11,02:00',    # 6 hours starting 2nd Sunday in March at 2am, 7 hours starting 1st Sunday in November at 2am
    'PST', '-7,2,0,3,02:00, -8,1,0,11,02:00',    # 7 hours starting 2nd Sunday in March at 2am, 8 hours starting 1st Sunday in November at 2am
    'GMT', ''
  );

  if ( ( $timezone1 eq $timezone2 ) || ( ( $timezone1 ne "GMT" ) && ( $timezone2 ne "GMT" ) ) ) {
    return $origtime;
  } elsif ( $timezone1 eq "GMT" ) {
    $timezone = $timezone2;
  } else {
    $timezone = $timezone1;
  }

  if ( $timezonearray{$timezone} eq "" ) {
    return $origtime;
  }

  my ( $hours1, $times1, $wday1, $month1, $time1, $hours2, $times2, $wday2, $month2, $time2 ) = split( /,/, $timezonearray{$timezone} );

  my $origtimenum =
    timegm( substr( $origtime, 12, 2 ), substr( $origtime, 10, 2 ), substr( $origtime, 8, 2 ), substr( $origtime, 6, 2 ), substr( $origtime, 4, 2 ) - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $newtimenum = $origtimenum;
  if ( $timezone1 eq "GMT" ) {
    $newtimenum = $origtimenum + ( 3600 * $hours1 );
  }

  my $timenum = timegm( 0, 0, 0, 1, $month1 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month1 happens on wday $wday\n";

  if ( $wday1 < $wday ) {
    $wday1 = 7 + $wday1;
  }
  my $mday1 = ( 7 * ( $times1 - 1 ) ) + 1 + ( $wday1 - $wday );
  my $timenum1 = timegm( 0, substr( $time1, 3, 2 ), substr( $time1, 0, 2 ), $mday1, $month1 - 1, substr( $origtime, 0, 4 ) - 1900 );

  #print "time1: $time1\n\n";

  print "The $times1 Sunday of month $month1 happens on the $mday1\n";

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month2 happens on wday $wday\n";

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  print "The $times2 Sunday of month $month2 happens on the $mday2\n";

  #print "origtimenum: $origtimenum\n";
  #print "newtimenum:  $newtimenum\n";
  #print "timenum1:    $timenum1\n";
  #print "timenum2:    $timenum2\n";
  my $zoneadjust = "";
  if ( $dstflag == 0 ) {
    $zoneadjust = $hours1;
  } elsif ( ( $newtimenum >= $timenum1 ) && ( $newtimenum < $timenum2 ) ) {
    $zoneadjust = $hours1;
  } else {
    $zoneadjust = $hours2;
  }

  if ( $timezone1 ne "GMT" ) {
    $zoneadjust = -$zoneadjust;
  }

  print "zoneadjust: $zoneadjust\n";
  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  print "newtime: $newtime $timezone2\n\n";
  return $newtime;

}

