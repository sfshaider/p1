#!/usr/local/bin/perl

$| = 1;

use lib '/home/p/pay1/perl_lib';
use Net::FTP;
use miscutils;
use smpsutils;
use isotables;
use IO::Socket;
use Socket;

$filename = $ARGV[0];

if ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'globalctf/genfiles.pl'`;
if ( $cnt > 1 ) {
  print "genfiles.pl already running, exiting...\n";

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: globalctf - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

print "in genfiles.pl\n";

# batch cutoff times: 2:30am, 8am, 11:15am, 5pm M-F     12pm Sat   12pm, 7pm Sun

#$checkstring = " and t.username='testctf'";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 10 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 6 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

#my ($sec,$min,$hour,$day1,$month,$year,$wday,$yday,$isdst) = gmtime(time());
#my ($sec,$min,$hour,$day2,$month,$year,$wday,$yday,$isdst) = localtime(time());
#if ($day1 != $day2) {
#  print "GMT day ($day1) and local day ($day2) do not match, try again after midnight local\n";
#}

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
( $dummy, $today, $todaytime ) = &miscutils::genorderid();

$fileyear = substr( $today, 0, 4 );
if ( !-e "/home/p/pay1/batchfiles/globalctf/logs/$fileyear" ) {
  system("mkdir /home/p/pay1/batchfiles/globalctf/logs/$fileyear");
}
if ( !-e "/home/p/pay1/batchfiles/globalctf/logs/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: globalctf - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory globalctf/logs/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$test = "no";
$host = "209.51.176.199";    # Source IP address

$primaryipaddress = '64.69.201.195';     # primary server
$primaryport      = '14133';             # primary server
$primaryhost      = "209.51.176.199";    # Source IP address

$ipaddress1 = '64.69.203.195';           # secondary server
$port1      = '18582';                   # secondary server

#$port1 = '14133';
$host1 = "processor-host";               # Source IP address

$ipaddress2 = '64.69.203.195';           # secondary server
$port2      = '14133';                   # secondary server
$host2      = "209.51.176.199";          # Source IP address

$testipaddress = '64.69.205.190';        # test server
$testport      = '18695';                # test server
$testhost      = "209.51.176.199";       # Source IP address

$ipaddress = $primaryipaddress;
$port      = $primaryport;

if ( $filename ne "" ) {

  #  $message = "";
  #  open(infile,"/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename");
  #  while(<infile>) {
  #    $line = $_;
  #    #chop $line;
  #print "cccc\n";
  #    $message = $message . $line;

#$str = "010120202020303133300250601c4d4947523030331c63353430353938303030303030313139311c303830391c66431c74381c6f504e5030303030312e301c62471c61303030303030323330341c77401c65371c6a3132333435313233341c6b3132332041646472204c6e1c6d3030303030331c7864301c787032303039303230363232343932353132310303";
#$message = pack "H*", $str;

  #&socketread(2);
  #}
  #  close(infile);

  #  my $stx = pack "H2", "02";
  #  my $etx = pack "H2", "03";

  #  $message = $stx . $message . $etx;

  #  $len = length($message);
  #  $len = substr("0000" . $len,-4,4);
  #  $header = pack "H4A4A4", "0101","    ",$len;
  #  $trailer = pack "H2", "03";

  #  $message = $header . $message . $trailer;
  #  &socketwrite($message);

  #print "dddd\n";
  #  &socketread(12);
  #  close(SOCK);

  #print "eeee\n";
  exit;
}

$batch_flag = 1;
$file_flag  = 1;

$dbh  = &miscutils::dbhconnect("pnpmisc");
$dbh2 = &miscutils::dbhconnect("pnpdata");

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
        and o.processor='globalctf'
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
  $userarray{$user}       = 1;
  $usercountarray{$user}  = $usercount;
  $starttdatearray{$user} = $usertdate;
}
$sthtrans->finish;

#if ($mycnt > 1) {
#  open(MAILTMP,"| /usr/lib/sendmail -t");
#  print MAILTMP "To: cprice\@plugnpay.com\n";
#  print MAILTMP "From: dcprice\@plugnpay.com\n";
#  print MAILTMP "Subject: globalctf - more than one batch\n";
#  print MAILTMP "\n";
#  print MAILTMP "There are more than one globalctf batches.\n";
#  close MAILTMP;
#}

foreach $username ( sort keys %userarray ) {

  #($banknum,$currency,$username) = split(/ /,$key);
  ( $d1, $d2, $time ) = &miscutils::genorderid();
  print "bbbb $username\n";

  if ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) {
    open( logfile, ">>/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$username$time.txt" );
    print logfile "stopgenfiles\n";
    print "stopgenfiles\n";
    close(logfile);
    unlink "/home/p/pay1/batchfiles/globalctf/batchfile.txt";
    last;
  }

  open( batchfile, ">/home/p/pay1/batchfiles/globalctf/genfiles.txt" );
  print batchfile "$username\n";
  close(batchfile);

  print "bbbb $username  $banknum\n";
  open( batchfile, ">/home/p/pay1/batchfiles/globalctf/batchfile.txt" );
  print batchfile "$username\n";
  close(batchfile);

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  local $sthcust = $dbh->prepare(
    qq{
        select merchant_id,pubsecret,proc_type,status,currency,company,city,state,zip,tel,country
        from customers
        where username='$username'
        }
    )
    or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthcust->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $merchant_id, $terminal_id, $proc_type, $status, $currency, $company, $city, $state, $mzip, $phone, $mcountry ) = $sthcust->fetchrow;
  $sthcust->finish;

  if ( $currency eq "" ) {
    $currency = "usd";
  }

  open( logfile, ">>/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$username$time.txt" );
  print "cccc $username $usercountarray{$username} $starttransdate\n";
  print logfile "$username $usercountarray{$username} $starttransdate $currency\n";
  close(logfile);

  if ( $status ne "live" ) {
    next;
  }

  local $sthinfo = $dbh->prepare(
    qq{
        select username,industrycode,taxid1,taxid2,taxid3
        from globalctf
        where username='$username'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $username, $industrycode, $taxid1, $taxid2, $taxid3 ) = $sthinfo->fetchrow;
  $sthinfo->finish;

  $sthtrans = $dbh2->prepare(
    qq{
        select orderid,operation,trans_date,trans_time,enccardnumber,card_exp,length,amount,auth_code,avs,finalstatus,transflags
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
  $sthtrans->bind_columns( undef, \( $orderid, $operation, $trans_date, $trans_time, $enccardnumber, $exp, $length, $amount, $auth_code, $avs_code, $finalstatus, $transflags ) );

  while ( $sthtrans->fetch ) {
    if ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) {
      unlink "/home/p/pay1/batchfiles/globalctf/batchfile.txt";
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

    $orderidold = $orderid;

    #xxxx
    print "$orderid $operation $amount\n\n";

    open( logfile, ">>/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$username$time.txt" );
    print logfile "$orderid $operation\n";
    close(logfile);

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

    if ( ( ( $username ne $usernameold ) || ( $banknum ne $banknumold ) || ( $currency ne $currencyold ) ) && ( $file_flag == 0 ) ) {
      &filetrailer();
      $file_flag = 1;
    }

    if ( $file_flag == 1 ) {
      &fileheader();
    }

    if ( $batch_flag == 1 ) {
      &batchheader();
    }

    $batchreccnt++;
    $filereccnt++;

    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
    print "$cardnumber\n";

    $card_type = &smpsutils::checkcard($cardnumber);
    if ( ( $cardnumber =~ /^36/ ) && ( length($cardnumber) == 14 ) ) {
      $card_type = 'mc';
    }

    &batchdetail();

    local $sthinfo = $dbh2->prepare(
      qq{
        update trans_log set finalstatus='locked',result=?,refnumber=?
	where username='$username'
	and trans_date>='$twomonthsago'
	and orderid='$orderid'
	and finalstatus='pending'
	and operation='$operation'
        and (accttype is NULL or accttype ='' or accttype='credit')
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthinfo->execute( "$filename", "$refnum" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthinfo->finish;

    $operationstatus = $operation . "status";
    $operationtime   = $operation . "time";
    my $sthop = $dbh2->prepare(
      qq{
          update operation_log set $operationstatus='locked',lastopstatus='locked',batchfile=?,batchstatus='pending',refnumber=?
          where orderid='$orderid'
          and username='$username'
          and $operationstatus ='pending'
          and (voidstatus is NULL or voidstatus ='')
          and (accttype is NULL or accttype ='' or accttype='credit')
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthop->execute( "$filename", "$refnum" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthop->finish;

    #if ($transseqnum >= 6) {}
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

unlink "/home/p/pay1/batchfiles/globalctf/batchfile.txt";

open( batchfile, ">/home/p/pay1/batchfiles/globalctf/genfiles.txt" );
close(batchfile);

$mytime = gmtime( time() );
open( outfile, ">>/home/p/pay1/batchfiles/globalctf/ftplog.txt" );
print outfile "\n\n$mytime\n";
close(outfile);

#system("/home/p/pay1/batchfiles/globalctf/putfiles.pl >> /home/p/pay1/batchfiles/globalctf/ftplog.txt 2>\&1");

if ( ( $filecount > 0 ) && ( $filecount < 10 ) ) {
  for ( $myi = 0 ; $myi <= $filecount ; $myi++ ) {
    system("/home/p/pay1/batchfiles/globalctf/putfiles.pl >> /home/p/pay1/batchfiles/globalctf/ftplog.txt 2>\&1");
    &miscutils::mysleep(40);
    system("/home/p/pay1/batchfiles/globalctf/getfiles.pl >> /home/p/pay1/batchfiles/globalctf/ftplog.txt 2>\&1");
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
      open( logfile, ">>/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$username$time.txt" );
      print logfile "Error in batch detail: couldn't find trans_time $username $twomonthsago $orderid $trans_time\n";
      close(logfile);
      return;
    }
  }

  $transseqnum++;
  $transseqnum = substr( "0" x 6 . $transseqnum, -6, 6 );

  $linenum++;

  local $sthinfo = $dbh->prepare(
    qq{
        insert into batchfilesctf
	(username,trans_date,orderid,filename,detailnum,status,operation)
        values (?,?,?,?,?,?,?)
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute( "$username", "$today", "$orderid", "$filename", "$linenum", "pending", "$operation" )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthinfo->finish;

  local $sthinfo = $dbh->prepare(
    qq{
          select rocnum
          from globalctf
          where username='$username'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ($refnum) = $sthinfo->fetchrow;
  $sthinfo->finish;

  $refnum = $refnum + 1;
  if ( $refnum > 999998 ) {
    $refnum = 1;
  }

  local $sthinfo = $dbh->prepare(
    qq{
          update globalctf set rocnum=?
          where username='$username'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute("$refnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
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

  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

  @bd             = ();
  $bd[0]          = "H1";                           # record code (2a)
  $magstripetrack = substr( $auth_code, 108, 1 );
  if ( $operation eq "return" ) {
    $ttype = "3";
  } elsif ( $origoperation eq "forceauth" ) {
    $ttype = "2";
  } elsif ( $magstripetrack =~ /1|2/ ) {
    $ttype = "0";
  } else {
    $ttype = "1";
  }
  $bd[1] = "$ttype";                                # transaction type (1n)
  $commcardtype = substr( $auth_code, 21, 1 );
  $commcardtype =~ s/ //g;
  if ( ( $commcardtype eq "1" ) || ( $transflags =~ /level3/ ) ) {
    $bd[2] = "P";                                   # purchase indicator (1a)
  } else {
    $bd[2] = "C";                                   # purchase indicator (1a)
  }

  $transid = substr( $auth_code,          6, 15 );
  $transid = substr( $transid . " " x 15, 0, 15 );
  $bd[3] = "$transid";                              # transaction id (15a)

  print "auth_code: $auth_code\n";
  $authcode = substr( $auth_code,          0, 6 );
  $authcode = substr( $authcode . " " x 6, 0, 6 );
  $bd[4] = "$authcode";                             # authorization code (6a)
  $refnum = substr( "0" x 6 . $refnum, -6, 6 );
  $bd[5] = "$refnum";                               # sequence number ROC (6n)
  $cardnum = substr( $cardnumber . " " x 20, 0, 20 );
  $bd[6] = "$cardnum";                              # card number (20n)
  $expdate = substr( $exp, 0, 2 ) . substr( $exp, 3, 2 );
  $expdate = substr( $expdate . " " x 4, 0, 4 );
  $bd[7] = "$expdate";                              # expiration date MMYY (4n)
  $bd[8] = "  ";                                    # filler (2a)
  $avs = substr( $auth_code, 22, 1 );
  $avs = substr( $avs . " ", 0,  1 );
  $bd[9] = "$avs";                                  # avs result code (1a)

  $ponumber = substr( $auth_code, 23, 25 );
  $ponumber =~ s/ //g;
  if ( $ponumber ne "" ) {
    $ponumber = substr( $ponumber . " " x 25, 0, 25 );
  } else {
    $ponumber = substr( $orderid . " " x 25, 0, 25 );
  }

  #$custcode = substr($auth_code,23,25);
  #$custcode =~ s/ //g;
  #if ($custcode eq "") {
  #  $custcode = $ponumber;
  #}
  #$custcode = substr($custcode . " " x 25,0,25);
  if ( ( $commcardtype ne "1" ) && ( $transflags !~ /level3/ ) ) {
    $ponumber = " " x 25;
  }
  $bd[10] = "$ponumber";    # customer code purchase number amex ref number (25a)

  $bd[11] = "  ";           # filler (2a)

  ( $d1, $transamount ) = split( / /, $origamount );
  $transamount = sprintf( "%d", ( $transamount * 100 ) + .0001 );
  $transamount = substr( "0" x 10 . $transamount, -10, 10 );
  if ( ( $operation ne "return" ) && ( $transamount eq "0000000000" ) ) {
    $transamount = " " x 10;
  }
  $bd[12] = "$transamount";    # authorization amount (10n)

  $bd[13] = "  ";              # filler (2a)

  ( $currency, $transamount ) = split( / /, $amount );
  $transamount = sprintf( "%d", ( $transamount * 100 ) + .0001 );
  $transamount = substr( "0" x 10 . $transamount, -10, 10 );
  $bd[14] = "$transamount";    # settle amount (10n)

  $bd[15] = "  ";              # filler (2a)
  if ( $trans_time eq "" ) {
    $lyear = substr( $lyear, -2, 2 );
    $transdate = sprintf( "%02d%02d%02d", $lyear, $lmonth + 1, $lday );
    $transtime = sprintf( "%02d%02d", $lhour, $lmin );
  } else {
    my $loctime = &miscutils::strtotime($trans_time);
    my ( $llsec, $llmin, $llhour, $llday, $llmonth, $llyear, $wday, $yday, $isdst ) = localtime($loctime);
    $llyear = substr( $llyear, -2, 2 );
    $transdate = sprintf( "%02d%02d%02d", $llyear, $llmonth + 1, $llday );
    $transtime = sprintf( "%02d%02d", $llhour, $llmin );
  }
  $bd[16] = "$transdate";      # transaction date YYMMDD (6n)
  $bd[17] = "$transtime";      # transaction time HHMM (4n)
  $bd[18] = " " x 7;           # filler (7a)
  $bd[19] = "\r\n";            # crlf (2a)

  foreach $var (@bd) {
    $message = $message . $var;

    #print outfile "$var";

    $xs = $cardnumber;
    $xs =~ s/[0-9]/x/g;
    $var =~ s/$cardnumber/$xs/;
    print outfile2 "$var";

  }

  $h2record = "";
  $h3record = "";
  if ( ( $card_type eq "ax" )
    || ( ( ( $industrycode !~ /retail|restaurant/ ) || ( $transflags =~ /moto/ ) || ( $commcardtype eq "1" ) || ( $transflags =~ /level3/ ) ) && ( $card_type =~ /vi|mc|ax/ ) ) ) {
    $recseqnum++;
    $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

    $linenum++;

    @bd = ();
    $bd[0] = "H2";    # record code (2a)
    my $orderdate = substr( $trans_time, 4, 2 ) . substr( $trans_time, 6, 2 ) . substr( $trans_time, 2, 2 );
    $orderdate = substr( $orderdate . " " x 6, 0, 6 );
    $bd[1] = "$orderdate";    # ship/order date MMDDYY (6n)
    $bd[2] = "  ";            # filler (2a)
    $bd[3] = "x" x 10;        # discount amount (10a)		#filled in later
    $bd[4] = "  ";            # filler (2a)
    $freightamt = substr( $auth_code,             58, 10 );
    $freightamt = substr( $freightamt . " " x 10, 0,  10 );
    $bd[5] = "$freightamt";    # freight amount (10n)
    $bd[6] = "  ";             # filler (2a)
    $dutyamt = substr( $auth_code,          48, 10 );
    $dutyamt = substr( $dutyamt . " " x 10, 0,  10 );
    $bd[7] = "$dutyamt";       # duty amount (10n)
    $bd[8] = "  ";             # filler (2a)
    $tax = substr( $auth_code,      68, 10 );
    $tax = substr( $tax . " " x 10, 0,  10 );
    $bd[9]  = "$tax";          # sales tax amount1 (10n)
    $bd[10] = "  ";            # filler (2a)
    $bd[11] = "0" x 10;        # sales tax amount2 (10n)
    $bd[12] = "  ";            # filler (2a)
    $bd[13] = "0" x 10;        # sales tax amount3 (10n)

    if ( ( $card_type eq "vi" ) && ( $mcountry ne "US" ) ) {
      $taxid1 = substr( $taxid1 . " " x 20, 0, 20 );
    } else {
      $taxid1 = " " x 20;
    }
    $bd[14] = $taxid1;         # tax id 1 (20a)
    $taxid2 = substr( $taxid2 . " " x 20, 0, 20 );
    $bd[15] = $taxid2;         # tax id 2 (20a)
    $bd[16] = " " x 6;         # filler (6n)
    $bd[17] = "\r\n";          # crlf (2a)

    $h2record = "";
    foreach $var (@bd) {
      $h2record = $h2record . $var;

      #print outfile "$var";

      #$xs = $cardnumber;
      #$xs =~ s/[0-9]/x/g;
      #$var =~ s/$cardnumber/$xs/;
      #print outfile2 "$var";

    }

    local $sthinfo = $dbh->prepare(
      qq{
          select taxinvnum
          from globalctf
          where username='$username'
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthinfo->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ($taxinvnum) = $sthinfo->fetchrow;
    $sthinfo->finish;

    $taxinvnum = $taxinvnum + 1;
    if ( $taxinvnum > 999998 ) {
      $taxinvnum = 1;
    }

    local $sthinfo = $dbh->prepare(
      qq{
          update globalctf set taxinvnum=?
          where username='$username'
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthinfo->execute("$taxinvnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthinfo->finish;

    $recseqnum++;
    $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

    $linenum++;

    @bd     = ();
    $bd[0]  = "H3";                                  # record code (2a)
    $taxid3 = substr( $taxid3 . " " x 20, 0, 20 );
    $bd[1]  = $taxid3;                               # tax id 3 (20a)
    if ( ( ( $commcardtype eq "1" ) || ( $transflags =~ /level3/ ) ) && ( $card_type eq "vi" ) && ( $transflags !~ /notexempt/ ) && ( $transflags =~ /exempt/ ) ) {
      $taxind = "0";
    } elsif ( ( ( $commcardtype eq "1" ) || ( $transflags =~ /level3/ ) ) && ( $card_type eq "vi" ) ) {
      $taxind = "1";
    } elsif ( ( ( $commcardtype eq "1" ) || ( $transflags =~ /level3/ ) ) && ( $card_type eq "mc" ) && ( $transflags !~ /notexempt/ ) && ( $transflags =~ /exempt/ ) ) {
      $taxind = "N";
    } elsif ( ( ( $commcardtype eq "1" ) || ( $transflags =~ /level3/ ) ) && ( $card_type eq "mc" ) && ( $tax == 0 ) ) {
      $taxind = "N";
    } elsif ( ( ( $commcardtype eq "1" ) || ( $transflags =~ /level3/ ) ) && ( $card_type eq "mc" ) ) {
      $taxind = "Y";
    } else {
      $taxind = " ";
    }
    $bd[2] = "$taxind";    # tax indicator 1 (1a)
    $bd[3] = " ";          # tax indicator 2 (1a)
    $bd[4] = " ";          # tax indicator 3 (1a)
    $commoditycode = substr( $auth_code, 104, 4 );
    $commoditycode = substr( $commoditycode . " " x 4, 0, 4 );
    $bd[5] = "$commoditycode";    # summary commodity code (4a)

    $shipzip = "";
    if ( ( ( $card_type eq "ax" ) && ( $commcardtype eq "1" ) ) || ( $transflags =~ /level3/ ) ) {
      $shipzip = substr( $auth_code, 78, 9 );
    }
    $shipzip = substr( $shipzip . " " x 9, 0, 9 );
    $bd[6] = "$shipzip";          # destination zip code (9a)

    $merchzip = "";
    if ( $transflags =~ /level3/ ) {
      $merchzip = $mzip;
    }
    $merchzip = substr( $merchzip . " " x 9, 0, 9 );
    $bd[7] = "$merchzip";         # ship from zip code (9a)

    print "mcountry: $mcountry\n";
    $merchcountry = $mcountry;
    $merchcountry =~ tr/a-z/A-Z/;
    $merchcountry = $isotables::countryUS840{$merchcountry};
    $merchcountry = substr( $merchcountry . " " x 3, 0, 3 );
    print "merchcountry: $merchcountry\n";
    $bd[8] = "$merchcountry";     # destination country code (3a)

    if ( ( $commcardtype eq "1" ) || ( $transflags =~ /level3/ ) ) {
      $ticketnum = substr( $auth_code, 109, 6 );    # tracenum
    } else {
      $ticketnum = substr( $auth_code, 23, 17 );    # porderid
    }
    $ticketnum = substr( $ticketnum . " " x 17, 0, 17 );
    $bd[9] = "$ticketnum";                          # supplier order number (17a)

    if ( ( $card_type eq "vi" ) && ( $mcountry ne "US" ) ) {
      $taxinvnum = substr( "0" x 15 . $taxinvnum, -15, 15 );
    } else {
      $taxinvnum = " " x 15;
    }
    $bd[10] = $taxinvnum;                           # tax/invoice number (15a)
    $bd[11] = "xxx";                                # total addendum (3n)
    $bd[12] = "0" x 20;                             # customer number (20a)
    $bd[13] = " " x 17;                             # edi transaction order (17a)
    $bd[14] = "    ";                               # filler (4a)
    $bd[15] = "\r\n";                               # crlf (2a)

    $h3record = "";
    foreach $var (@bd) {
      $h3record = $h3record . $var;

      #print outfile "$var";

      #$xs = $cardnumber;
      #$xs =~ s/[0-9]/x/g;
      #$var =~ s/$cardnumber/$xs/;
      #print outfile2 "$var";

    }
  }

  # level3 - one 1320 record for each item purchased
  $level3cnt       = 0;
  $axcnt           = 0;
  $discounttotamt  = 0;
  $lineitemrecords = "";

  if ( ( $transflags =~ /level3/ ) || ( ( $card_type eq "ax" ) && ( $transflags !~ /level3/ ) && ( $commcardtype eq "1" ) ) ) {
    print "select from orderdetails where orderid=$orderid  $username\n";

    $sthdetails = $dbh2->prepare(
      qq{ 
          select item,quantity,cost,description,unit,customa,customb,customc,customd
          from orderdetails
          where orderid='$orderid' 
          and username='$username'
    }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthdetails->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthdetails->bind_columns( undef, \( $item, $quantity, $cost, $descr, $unit, $customa, $customb, $customc, $customd ) );

    while ( $sthdetails->fetch ) {

      if ( $card_type eq "ax" ) {
        $descra = $descr;
        $descra =~ s/[^a-zA-Z0-9 \-_\/]//g;
        $descra =~ tr/a-z/A-Z/;
        $descra = substr( $descra . " " x 40, 0, 40 );
        $axdescr[$axcnt] = $descra;
        $axcnt++;
        next;
      }

      $level3cnt++;

      print "aaaa $item  $quantity  $cost  $descr  $unit\n";
      $item =~ tr/a-z/A-Z/;
      $item = substr( $item . " " x 15, 0, 15 );
      $descra = $descr;
      $descra =~ s/[^a-zA-Z0-9 \-_\/]//g;
      $descra =~ tr/a-z/A-Z/;
      $descra = substr( $descra . " " x 35, 0, 35 );
      if ( $card_type eq "vi" ) {
        $quantity = sprintf( "%d", ( $quantity * 10000 ) + .0001 );
      } else {
        $quantity = sprintf( "%d", ($quantity) + .0001 );
      }
      $quantity = substr( "0" x 12 . $quantity, -12, 12 );
      $unit     = substr( $unit . " " x 3,      0,   3 );
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
      $netind   = "N";
      $unitcost = sprintf( "%d", ( $cost * 10000 ) + .0001 );
      $unitcost = substr( "0" x 12 . $unitcost, -12, 12 );

      $discountamt  = 0;
      $discountflag = "N";
      if ( $customa != 0 ) {
        $discountflag = "Y";
        $discountamt  = $customa;
      }
      $discountamt = sprintf( "%d", ( $discountamt * 100 ) + .0001 );
      $discountamt = substr( "0" x 10 . $discountamt, -10, 10 );

      $discounttotamt = $discounttotamt + $discountamt;
      print "discountamt: $discountamt\n";
      print "discounttotamt: $discounttotamt\n";

      #$taxamt = 0;
      #if ($customb ne "") {
      #  $taxamt = $customb;
      #  $taxamt = sprintf("%d", ($taxamt*100)+.0001);
      #}

      $taxamt = $customb;
      if ( $taxamt ne "" ) {
        $taxamt = sprintf( "%d", ( $taxamt * 100 ) + .0001 );
      }
      $taxamt = substr( "0" x 10 . $taxamt, -10, 10 );

      $commoditycode = $customc;
      $commoditycode = substr( $customc . " " x 15, 0, 15 );

      if ( $card_type eq "vi" ) {
        $extcost = ( $unitcost * $quantity / 1000000 ) - $discountamt;
      } else {
        $extcost = ( $unitcost * $quantity / 100 );
      }
      $extcost = sprintf( "%d", $extcost + .0001 );

      $extcost = substr( "0" x 10 . $extcost, -10, 10 );

      #if ($customd ne "") {
      #  $extcost = sprintf("%d", ($customd*100)+.0001);
      #  $extcost = substr("0" x 13 . $extcost,-13,13);
      #}

      print "aaaaaaaaaaaa       $card_type  $item  $cost      $quantity * $unitcost - $discountamt = $extcost\n";

      $recseqnum++;
      $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

      $linenum++;

      @bd     = ();
      $bd[0]  = "L1";                                # record code (2a)
      $bd[1]  = "$item";                             # item product code (15a)
      $bd[2]  = "$descra";                           # item description (35a)
      $bd[3]  = "$debitind";                         # item indicator (1a)
      $bd[4]  = "N";                                 # item net/gross indicator (1a)
      $bd[5]  = "  ";                                # item type of supply (2a)
      $bd[6]  = "$quantity";                         # item quantity (12n)
      $unit   = substr( $unit . " " x 12, 0, 12 );
      $bd[7]  = "$unit";                             # item unit of measure (12a)
      $bd[8]  = "$unitcost";                         # item unit amount (12n)
      $bd[9]  = "  ";                                # filler (2a)
      $bd[10] = "$extcost";                          # item extended amt (10n)
      $bd[11] = "$commoditycode";                    # item commodity code (15a)
      $bd[12] = " " x 7;                             # filler (7a)
      $bd[13] = "\r\n";                              # crlf (2a)

      foreach $var (@bd) {
        $lineitemrecords = $lineitemrecords . $var;

        #print outfile "$var";
        #print outfile2 "$var";
      }

      $recseqnum++;
      $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

      $linenum++;

      @bd    = ();
      $bd[0] = "L2";      # record code (2a)
      $bd[1] = "    ";    # item tax type (4a)

      my $taxrate = 0;
      if ( $extcost > 0 ) {
        $taxrate = $taxamt / $extcost;
        $taxrate = sprintf( "%d", ( $taxrate * 100 ) + .0001 );
      }
      print "aaaa:\n";
      print "taxamt: $taxamt\n";
      print "extcost: $extcost\n";
      print "taxrate: $taxrate\n";
      $taxrate = substr( "0" x 5 . $taxrate, -5, 5 );
      print "taxrate: $taxrate\n";
      $bd[2] = "$taxrate";         # item tax rate applied (5n)
      $bd[3] = "  ";               # filler (2a)
      $bd[4] = "$taxamt";          # item tax amount (10n)
      $bd[5] = "$discountflag";    # item discount indicator (1a)
      $bd[6] = "  ";               # filler (2a)
      $bd[7] = "$discountamt";     # item discount amount (10n)
      $level3cnt = substr( "0" x 3 . $level3cnt, -3, 3 );
      $bd[8]  = "$level3cnt";      # addendum sequence (3n)
      $bd[9]  = " " x 87;          # filler (87a)
      $bd[10] = "\r\n";            # crlf (2a)

      foreach $var (@bd) {
        $lineitemrecords = $lineitemrecords . $var;

        #print outfile "$var";
        #print outfile2 "$var";
      }

    }

    if ( ( $card_type eq "ax" ) && ( $transflags !~ /level3/ ) ) {
      $recseqnum++;
      $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

      $linenum++;

      $level3cnt++;

      @bd = ();
      $bd[0] = "LA";    # record code (2a)
      $axdescr[0] = substr( $axdescr[0] . " " x 40, 0, 40 );
      $axdescr[1] = substr( $axdescr[1] . " " x 40, 0, 40 );
      $axdescr[2] = substr( $axdescr[2] . " " x 40, 0, 40 );
      $axdescr[3] = substr( $axdescr[3] . " " x 40, 0, 40 );
      $bd[1] = "$axdescr[0]";    # item description 1 (40a)
      $bd[2] = "$axdescr[1]";    # item description 2 (40a)
      $bd[3] = " " x 44;         # filler (44a)
      $bd[4] = "\r\n";           # crlf (4a)

      foreach $var (@bd) {
        $lineitemrecords = $lineitemrecords . $var;

        #print outfile "$var";
        #print outfile2 "$var";
      }

      $recseqnum++;
      $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

      $linenum++;

      @bd    = ();
      $bd[0] = "LB";             # record code (2a)
      $bd[1] = "$axdescr[2]";    # item description 3 (40a)
      $bd[2] = "$axdescr[3]";    # item description 4 (40a)
      $bd[3] = " " x 44;         # filler (44a)
      $bd[4] = "\r\n";           # crlf (4a)

      foreach $var (@bd) {
        $lineitemrecords = $lineitemrecords . $var;

        #print outfile "$var";
        #print outfile2 "$var";
      }

    }

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
  print "discounttotamt: $discounttotamt\n";

  $discounttotamt = substr( "0" x 10 . $discounttotamt, -10, 10 );
  $h2record =~ s/xxxxxxxxxx/$discounttotamt/g;
  $message = $message . $h2record;

  $level3cnt = substr( "0" x 3 . $level3cnt, -3, 3 );
  $h3record =~ s/xxx/$level3cnt/g;
  $message = $message . $h3record;
  $message = $message . $lineitemrecords;

  print outfile2 "$h2record";
  print outfile2 "$h3record";
  print outfile2 "$lineitemrecords";
}

sub batchheader {
  $batch_flag  = 0;
  $detailcount = 0;

  $batchcount++;

  #local $sthinfo = $dbh->prepare(qq{
  #        select batchnum
  #        from transinfo
  #        where username='globalctf'
  #        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  #$sthinfo->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
  #($batchnum) = $sthinfo->fetchrow;
  #$sthinfo->finish;

  print "aaaa$batchnum\n";
  $batchnum = $batchnum + 1;
  if ( $batchnum >= 9999 ) {
    $batchnum = 1;
  }
  print "bbbb$batchnum\n";

  #local $sthinfo = $dbh->prepare(qq{
  #        update transinfo set batchnum=?
  #	  where username='globalctf'
  #          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  #  $sthinfo->execute("$batchnum") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
  #  $sthinfo->finish;

  $batchreccnt = 1;
  $batchnum    = substr( "0" x 6 . $batchnum, -6, 6 );
  $batchdate   = $createdate;
  $batchdate   = substr( $batchdate . " " x 6, 0, 6 );
  $batchtime   = $createtime;
  $batchtime   = substr( $batchtime . " " x 6, 0, 6 );

  $transseqnum   = 0;
  $batchtotalcnt = 0;
  $batchtotalamt = 0;
  $batchretcnt   = 0;
  $batchretamt   = 0;
  $batchsalescnt = 0;
  $batchsalesamt = 0;

  #@bh = ();
  #$bh[0] = "11";		# tran code (2a)
  #$bh[7] = "\r\n";		# crlf (2a)

  #foreach $var (@bh) {
  #  print outfile "$var";
  #  print outfile2 "$var";
  #}
}

sub batchtrailer {
  $batchreccnt++;
  $filereccnt++;

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

  #@bt = ();
  #$bt[0] = "80";		# tran code (2a)
  #$bt[1] = $batchnum;		# relative batch # (6a)
  #$bt[12] = "\r\n";		# crlf (2a)

  #foreach $var (@bt) {
  #  print outfile "$var";
  #  print outfile2 "$var";
  #}

}

sub fileheader {
  print "in fileheader\n";
  $batchcount = 0;
  $filecount++;
  $message = "";

  $file_flag = 0;
  local $sthinfo = $dbh->prepare(
    qq{
        select filenum
        from globalctf
        where username='globalctf'
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

  ( $d1, $d2, $ttime ) = &miscutils::genorderid();
  $filename = "$ttime";

  local $sthinfo = $dbh->prepare(
    qq{
        update globalctf set filenum=?
	where username='globalctf'
       }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthinfo->execute("$filenum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthinfo->finish;

  open( outfile,  ">/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename" );
  open( outfile2, ">/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.txt" );

  $customerid = substr( $customerid . " " x 10, 0, 10 );

  $linenum      = 0;
  $filesalescnt = 0;
  $filesalesamt = 0;
  $fileretcnt   = 0;
  $fileretamt   = 0;
  $filereccnt   = 1;
  $filetotalamt = 0;
  $filetotalcnt = 0;
  $fileid       = substr( $fileid . " " x 20, 0, 20 );

  $recseqnum = 1;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

  $linenum++;

  @fh    = ();
  $fh[0] = "~";           # batch type (1a)
  $fh[1] = "NDCPP3  ";    # application (8a)
  $fh[2] = "V004";        # version (4a)
  $fh[3] = "        ";    # sub version (8a)
  $fh[4] = "T";           # error level indicator (1a)
  $fh[5] = "0" x 20;      # customer id (20a)
  $fh[6] = " " x 84;      # filler (84a)
  $fh[7] = "\r\n";        # crlf (2a)

  $fileheaderstr = "";
  foreach $var (@fh) {
    $fileheaderstr = $fileheaderstr . $var;

    #print outfile "$var";
    print outfile2 "$var";
  }

  ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
  $lyear = $lyear + 1900;
  $ltrantime = sprintf( "%02d%02d%02d", $lhour, $lmin, $lsec );

  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

  $linenum++;

  @fh        = ();
  $fh[0]     = "F1";                                                    # record code (2a)
  $tid       = substr( $terminal_id . " " x 20, 0, 20 );
  $fh[1]     = "$tid";                                                  # terminal id (20a)
  $fh[2]     = " " x 4;                                                 # reserved (4a)
  $ltrandate = sprintf( "%02d%02d%04d", $lmonth + 1, $lday, $lyear );
  $fh[3]     = "$ltrandate";                                            # date MMDDYYYY (8n)
  $fh[4]     = "xxxxxxx";                                               # record count (7n)    filled in later
  $fh[5]     = "000000";                                                # reserved - date MMDDYYYY (6a)
  $fh[6]     = "00000000";                                              # reserved - time HHMMSSHH (8a)
  $fh[7]     = "0000";                                                  # reserved - device number (4a)
  $fh[8]     = "  ";                                                    # filler (2a)
  $filenum   = substr( "0" x 3 . $filenum, -3, 3 );
  $fh[9]     = "$filenum";                                              # file sequence number (3n)
  $fh[10]    = " " x 62;                                                # filler (62a) ???? 67
  $fh[11]    = "\r\n";                                                  # crlf (2a)

  #$createdate = substr($today,2,6);
  #$fh[2] = $createdate;		# process date - YYMMDD (6n)
  #$createtime = substr($todaytime,8,4);
  #$fh[6] = $createtime;		# creation time - HHMM (4n)
  #$filenum = substr("0" x 3 . $filenum,-3,3);
  #$julian = substr("0" x 3 . $julian,-3,3);
  #$newfilenum = substr($today,0,4) . $julian . $filenum;
  #$fh[7] = $newfilenum;		# file submission number - YYYYDDDSSS (10a)

  foreach $var (@fh) {
    $fileheaderstr = $fileheaderstr . $var;

    #print outfile "$var";
    print outfile2 "$var";
  }

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

  $filetotalamt = substr( "0" x 10 . $filetotalamt, -10, 10 );
  $filesalescnt = substr( "0" x 6 . $filesalescnt,  -6,  6 );
  $filesalesamt = substr( "0" x 10 . $filesalesamt, -10, 10 );
  $fileretcnt   = substr( "0" x 6 . $fileretcnt,    -6,  6 );
  $fileretamt   = substr( "0" x 10 . $fileretamt,   -10, 10 );
  $batchcount   = substr( "0" x 6 . $batchcount,    -6,  6 );

  $recseqnum++;
  $recseqnum = substr( "0000000" . $recseqnum, -7, 7 );

  @ft         = ();
  $ft[0]      = "T1";                                                    # record code (2a)
  $tid        = substr( $terminal_id . " " x 20, 0, 20 );
  $ft[1]      = "$tid";                                                  # terminal id (20a)
  $ft[2]      = "    ";                                                  # reserved (4a)
  $ltrandate  = sprintf( "%02d%02d%04d", $lmonth + 1, $lday, $lyear );
  $ft[3]      = "$ltrandate";                                            # date (8n)
  $filereccnt = substr( "0" x 7 . $recseqnum, -7, 7 );
  $ft[4]      = "$filereccnt";                                           # record count (7n)
  $ft[5]      = " " x 85;                                                # reserved (85a)
  $ft[6]      = "\r\n";                                                  # crlf (2a)

  foreach $var (@ft) {
    $message = $message . $var;

    #print outfile "$var";
    print outfile2 "$var";
  }

  $fileheaderstr =~ s/xxxxxxx/$recseqnum/;
  $message = $fileheaderstr . $message;
  print outfile "$message";

  close(outfile);
  close(outfile2);

  print "filenum: $newfilenum  today: $today  amt: $filetotalamtstr  cnt: $filetotalcnt\n";

}

sub update {

  $mytime   = gmtime( time() );
  $message2 = $response;
  $message2 =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  open( logfile, ">>/home/p/pay1/batchfiles/globalctf/serverlogmsg.txt" );
  print logfile "$mytime recv: $message2\n";
  $message2 = unpack "H*", $response;
  print logfile "response2: $message2\n";
  close(logfile);
  print "$mytime recv: $message2\n";

  $header  = substr( $response, 0,  11 );
  $trailer = substr( $response, -1, 1 );
  $tmpstr = unpack "H*", $header;
  print "header: $tmpstr\n";
  $tmpstr = unpack "H*", $trailer;
  print "trailer: $tmpstr\n";
  if ( ( $header !~ /^.*\x02$/ ) || ( $trailer ne "\x03" ) ) {
    print "code does not have stx or etx\n";
    $tmpstr = unpack "H*", $header;
    print "header: $tmpstr\n";
    $tmpstr = unpack "H*", $trailer;
    print "trailer: $tmpstr\n";
    exit;
  }

  $chkresponse = $response;
  $chkresponse =~ s/^.*\x02//;
  $chkresponse =~ s/\x03$//;
  (@fields) = split( /\x1c/, $chkresponse );
  foreach $var (@fields) {
    my $tag = substr( $var, 0, 1 );
    my $data = substr( $var, 1 );
    $temparray{$tag} = $data;
  }

  foreach $key ( sort keys %temparray ) {
    print "aa $key $temparray{$key}\n";
  }

  $rsequencenum = $temparray{'M'};

  return;

  #$temp = unpack "H*", $tempmsg;
  #$cnumlen = unpack "H2", $tempmsg;
  #$cnum = substr($temp,2,$cnumlen);
  #$pcode = substr($temp,2+$cnumlen,6);
  #$seqindx = $idx + 4 + 6 + ($cnumlen/2);
  #$sseq = unpack "H6", substr($message,$seqindx,6);
  #print "temp: $temp\ncnumlen: $cnumlen\ncnum: $cnum\npcode: $pcode\nsseq: $sseq\n";
  #print "$sequencenum\n";

  #open(logfile,">>/home/p/pay1/batchfiles/globalctf/serverlogmsg.txt");
  #print logfile "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  #close(logfile);
  $checkmessage = $response;
  $checkmessage =~ s/\x1c/\[1c\]/g;
  $checkmessage =~ s/\x1e/\[1e\]/g;

  #open(logfile,">>/home/p/pay1/batchfiles/globalctf/serverlogmsg.txt");
  #print logfile "response: $checkmessage\n";
  #close(logfile);

  #&timecheck("before update");
  if ( $timecheckfirstflag2 == 1 ) {
    $timecheckstart2     = time();
    $timecheckfirstflag2 = 0;
  }

  $sstatus{"$rsequencenum"} = "done";

  # yyyy
  $msg = pack "L", $sprocessid{"$rsequencenum"} + 0;
  $msg = $msg . $response;
  if ( msgsnd( $msqidb, $msg, &IPC_NOWAIT ) == NULL ) {
    open( logfile, ">>/home/p/pay1/batchfiles/globalctf/serverlogmsg.txt" );
    print logfile "a: snd failure $!\n";
    close(logfile);
    print "problem $sprocessid{$rsequencenum}\n";
    close(SOCK);
    exit;
  } else {

    #open(logfile,">>/home/p/pay1/batchfiles/globalctf/serverlogmsg.txt");
    #print logfile "a: snd success response $sprocessid{$rsequencenum}\n";
    #close(logfile);
  }

  delete $susername{$rsequencenum};
  delete $strans_time{$rsequencenum};
  delete $smessage{$rsequencenum};
  delete $sretries{$rsequencenum};
  delete $sorderid{$rsequencenum};
  delete $sprocessid{$rsequencenum};
  delete $svoidmessage{$rsequencenum};

  $timecheckend2   = time();
  $timecheckdelta2 = $timecheckend2 - $timecheckstart2;

  ( $d1, $d2, $temptime ) = &miscutils::genorderid();
  $checkmessage = $response;
  $checkmessage =~ s/\x1c/\[1c\]/g;
  $checkmessage =~ s/\x1e/\[1e\]/g;

  #open(tempfile,">>/home/p/pay1/batchfiles/globalctf/serverlog.txt");
  #print tempfile "$temptime $checkmessage\n";
  #close(tempfile);
}

