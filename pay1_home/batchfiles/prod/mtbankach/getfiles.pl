#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SFTP::Foreign;
use miscutils;
use rsautils;
use PlugNPay::CreditCard;

$devprod = "logs";

$ENV{PATH} = ".:/usr/ucb:/usr/bin:/usr/local/bin";

my $redofile = "ACH_RETURNS11252014.TXT";
$redofile = "";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );

( $d1, $today, $todaytime ) = &miscutils::genorderid();
$ttime = &miscutils::strtotime($today);

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 44 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 8 ) );
$fourdaysago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 7 ) );
$sevendaysago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$twomonthsagotime = $twomonthsago . "000000";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 30 * 12 ) );
$threemonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$threemonthsagotime = $threemonthsago . "000000";

my $root_file_path = "/home/p/pay1/batchfiles/logs/mtbankach";

print "\n\nTODAY:$today\n\n";

&checkdir($today);

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/p/pay1/batchfiles/logs/mtbankach/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/p/pay1/batchfiles/logs/mtbankach/$fileyearonly");
  system("chmod 0700 /home/p/pay1/batchfiles/logs/mtbankach/$fileyearonly");
}
if ( !-e "/home/p/pay1/batchfiles/logs/mtbankach/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/p/pay1/batchfiles/logs/mtbankach/$filemonth");
  system("chmod 0700 /home/p/pay1/batchfiles/logs/mtbankach/$filemonth");
}
if ( !-e "/home/p/pay1/batchfiles/logs/mtbankach/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/p/pay1/batchfiles/logs/mtbankach/$fileyear");
  system("chmod 0700 /home/p/pay1/batchfiles/logs/mtbankach/$fileyear");
}
if ( !-e "/home/p/pay1/batchfiles/logs/mtbankach/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: mtbankach - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/mtbankach/$fileyear.\n\n";
  close MAILERR;
  print "Couldn't create directory logs/mtbankach/$fileyear\n";
  exit;
}

%returncodes = (
  "R01", "Insufficient Funds",                               "R02", "Account Closed",
  "R03", "No Account",                                       "R04", "Invalid Account Number",
  "R06", "Returned per ODFI's Request",                      "R07", "Authorization Revoked by Customer",
  "R08", "Payment Stopped or Stop Payment on Item",          "R09", "Uncollected Funds",
  "R10", "Customer Advises Not Authorized or other",         "R11", "Check Truncation Entry Return",
  "R12", "Branch Sold to Another DFI",                       "R14", "Representative Payee Deceased or other",
  "R15", "Beneficiary or Account Holder Deceased",           "R16", "Account Frozen",
  "R17", "File Record Edit Criteria",                        "R20", "Non-Transaction Account",
  "R21", "Invalid Company ID",                               "R22", "Invalid Individual ID Number",
  "R23", "Credit Entry Refused by Receiver",                 "R24", "Duplicate Entry",
  "R29", "Corporate Customer Advises Not Authorized",        "R31", "Permissible Return Entry",
  "R33", "Return of XCK Entry",                              "R40", "Return of ENR Entry by Federal Government Agency",
  "R41", "Invalid Transaction Code",                         "R42", "Routing Number/Check Digit Error",
  "R43", "Invalid DFI Account Number",                       "R44", "Invalid Individual ID Number",
  "R45", "Invalid Individual Name/Company Name",             "R46", "Invalid Representative Payee Indicator",
  "R47", "Duplicate Enrollment",                             "R61", "Misrouted Return",
  "R62", "Incorrect Trace Number",                           "R63", "Incorrect Dollar Amount",
  "R64", "Incorrect Individual Identification",              "R65", "Incorrect Transaction Code",
  "R66", "Incorrect Company Identification",                 "R67", "Duplicate Return",
  "R68", "Untimely Return",                                  "R69", "Multiple Errors",
  "R70", "Permissible Return Entry Not Accepted",            "R71", "Misrouted Dishonored Return",
  "R72", "Untimely Dishonored Return",                       "R73", "Timely Original Return",
  "R74", "Corrected Return",                                 "R13", "RDFI Not Qualified to Participate",
  "R18", "Improper Effective Entry Date",                    "R19", "Amount Field Error",
  "R25", "Addenda Error",                                    "R26", "Mandatory Field Error",
  "R27", "Trace Number Error",                               "R28", "Routing Number Check Digit Error",
  "R30", "RDFI Not Participant in Check Truncation Program", "R32", "RDFI Non-Settlement",
  "R34", "Limited Participation DFI",                        "R35", "Return of Improper Debit Entry",
  "R36", "Return of Improper Credit Entry",                  "C01", "Incorrect DFI Account Number",
  "C02", "Incorrect Routing Number",                         "C03", "Incorrect Routing Number, DFI Account Number",
  "C04", "Incorrect Individual Name/Receiving Company Name", "C05", "Incorrect Transaction Code",
  "C06", "Incorrect DFI Account Number, Transaction Code",   "C07", "Incorrect Routing Number, DFI Account Number, Trans Code",
  "C08", "Reserved",                                         "C09", "Incorrect Individual Identification Number",
  "C10", "Incorrect Company Name",                           "C11", "Incorrect Company Identification",
  "C12", "Incorrect Company Name, Company Identification",   "C13", "Addenda Format Error"
);

$dbh  = &miscutils::dbhconnect("pnpmisc");
$dbh2 = &miscutils::dbhconnect("pnpdata");

if ( $redofile ne "" ) {
  my $filedate = &getfiledate("$redofile");
  my $fileyear = substr( $filedate, 0, 4 ) . "/" . substr( $filedate, 4, 2 ) . "/" . substr( $filedate, 6, 2 );
  print "filedate: $filedate\n";
  print "fileyear: $fileyear\n";
  print "home/p/pay1/batchfiles/logs/mtbankach/$fileyear/$redofile\n";

  if ( -e "/home/p/pay1/batchfiles/logs/mtbankach/$fileyear/$redofile" ) {
    &processfile($redofile);
    $dbh->disconnect;
    $dbh2->disconnect;
    exit;
  }
}

my @filenamearray = ();

@filenamearray = &getFile();

#@filenamearray = ('ACH_RETURNS05042016.TXT');

print "cccc\n";

#exit;

foreach $filename (@filenamearray) {
  print "processing: $filename\n";
  &processfile($filename);
}

&processsuccesses();

## Keep below commented out.  Used for when bank acknowledges each transaction
#&processfailures();

$dbh->disconnect;
$dbh2->disconnect;

exit;

sub processfile {
  my ($filename) = @_;

  print "in processfile\n";

  $filedate = &getfiledate("$filename");
  $fileyear = substr( $filedate, 0, 4 ) . "/" . substr( $filedate, 4, 2 ) . "/" . substr( $filedate, 6, 2 );

  print "filename: $filename\n";
  print "fileyear: $fileyear\n";
  $detailflag = 0;
  $batchflag  = 0;
  $fileflag   = 0;
  $returnflag = 0;
  $batchnum   = "";

  my $merchantnum = "";
  my $date        = "";
  my $tcode       = "";
  my $routenum    = "";
  my $acctnum     = "";
  my $amount      = "";
  my $refnumber   = "";
  my $name        = "";
  my $rcode       = "";
  my $nocinfo     = "";
  my $processflag = 0;
  umask 0077;

  open( INFILE,   "/home/p/pay1/batchfiles/logs/mtbankach/$fileyear/$filename" );
  open( OUTFILE2, ">/home/p/pay1/batchfiles/logs/mtbankach/$fileyear/$filename.out" );
  open( OUTFILE3, ">/home/p/pay1/batchfiles/logs/mtbankach/$fileyear/t$filename" );

  while (<INFILE>) {
    $line = $_;
    chop $line;
    print "$line\n";
    $returnflag = 1;
    if ( $line =~ /^52/ ) {
      $processflag = 0;
      $merchantnum = "";
      $tdate       = substr( $line, 70, 6 );
      print "merchantnum: $merchantnum\n";
      print "tdate: $tdate\n";
    } elsif ( $line =~ /^6/ ) {
      $processflag = 0;
      $tcode       = substr( $line, 1, 2 );
      $routenum    = substr( $line, 3, 9 );
      $acctnum     = substr( $line, 12, 17 );
      $amount      = substr( $line, 29, 10 );
      $refnumber   = substr( $line, 39, 15 );
      $name        = substr( $line, 54, 18 );

      print "refnumber: $refnumber\n";
      print "name: $name\n";
    } elsif ( $line =~ /^79/ ) {
      $processflag = 1;
      $rcode       = substr( $line, 3, 3 );
      $tracenum    = substr( $line, 14, 7 );
      $newroutenum = substr( $line, 35, 9 );
      $newacctnum  = substr( $line, 44, 16 );
      $newroutenum =~ s/ //g;
      $newacctnum =~ s/ //g;
      $nocinfo = substr( $line, 35, 42 );

      print "merchantnum: $merchantnum\n";
      print "tcode: $tcode\n";

      #print "routenum: $routenum\n";
      #print "newroutenum: $newroutenum\n";
      #print "acctnum: $acctnum\n";
      #print "newacctnum: $newacctnum\n";
      #print "nocinfo: $nocinfo\n";

      print "amount: $amount\n";
      print "name: $name\n";
      print "rcode: $rcode\n";
      print "tracenum: $tracenum\n";
      print "refnumber: $refnumber\n";
    } else {
      $processflag = 0;
    }

    my $tmpline = $line;
    if ( length($routenum) > 4 ) {
      my $xs = "x" x length($routenum);
      $tmpline =~ s/$routenum/$xs/;
    }
    if ( length($acctnum) > 4 ) {
      my $xs = "x" x length($acctnum);
      $tmpline =~ s/$acctnum/$xs/;
    }
    if ( length($newroutenum) > 4 ) {
      my $xs = "x" x length($newroutenum);
      $tmpline =~ s/$newroutenum/$xs/;
    }
    if ( length($newacctnum) > 4 ) {
      my $xs = "x" x length($newacctnum);
      $tmpline =~ s/$newacctnum/$xs/;
    }
    print OUTFILE2 "$tmpline\n";

    print "dddd\n";

    if ( $processflag == 1 ) {
      print "processflag == 1\n";
      $routenum =~ s/[^0-9]//g;
      $acctnum =~ s/[^0-9]//g;

      $cardnumber = "$routenum $acctnum";
      my $cc             = new PlugNPay::CreditCard($cardnumber);
      my $shacardnumber  = $cc->getCardHash();
      my @cardHashes     = $cc->getCardHashArray();
      my $cardHashQmarks = '?' . ',?' x ($#cardHashes);

      #print "batchfilename: $batchfilename\n";
      #print "tdate: $tdate\n";
      #print "returnflag: $returnflag\n";
      #print "routenum: $routenum\n";
      #print "acctnum: $acctnum\n";
      #print "shacardnumber: $shacardnumber\n";
      #print "amount: $amount\n";
      #print "refnumber: $refnumber\n";
      #print "rcode: $rcode\n";
      #print "nocinfo: $nocinfo\n";

      print "\n$threemonthsago\n";
      print "$refnumber\n";

      my $sthord = $dbh->prepare(
        qq{
            select username,orderid,status,operation
            from batchfilesmtbank
            where trans_date>=?
            and refnumber=?
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthord->execute( $threemonthsago, $refnumber ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      ( $username, $orderid, $status, $operation ) = $sthord->fetchrow;
      $sthord->finish;
      print "batchfilesmtbank SEARCH: OID:$orderid, ST:$status, OP:$operation\n";

      if ( $refnumber eq "000000000000001" ) {
        my $db_amt = sprintf( "usd %.2f", $amount / 100 );
        print "RN:$routenum AN:$acctnum, SHA:$shacardnumber, AMT:$db_amt\n";
        ### Search for transaction in trans_log
        #exit;
        my $sth = $dbh2->prepare(
          qq{
            select orderid,finalstatus,operation
            from trans_log
            where trans_date>=?
            and shacardnumber in ($cardHashQmarks)
            and amount=?
            and operation=?
            }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sth->execute( $threemonthsago, @cardHashes, $db_amt, 'postauth' ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        ( $orderid, $status, $operation ) = $sth->fetchrow;
        $sth->finish;
        print "TRANS LOG SEARCH:$orderid,$status,$operation\n";
      }

      ### Search for chargeback transaction in trans_log
      my $sth = $dbh2->prepare(
        qq{
          select orderid
          from trans_log
          where trans_date>=?
          and orderid=?
          and operation=?
          }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute( $threemonthsago, $orderid, 'chargeback' ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      my ($chargeback_test) = $sth->fetchrow;
      $sth->finish;
      print "CHRG BCK TEST:$chargeback_test\n";

      if ( $chargeback_test ne "" ) {
        print "Chargeback already exists - skipping\n";
        next;
      }

      print "username:$username\n";
      print "orderid:$orderid\n";
      print "status:$status\n";
      print "operation:$operation\n";
      print "returnflg:$returnflag\n";
      print "rcode:$rcode\n";

      if ( $returnflag != 1 ) {
        if ( $orderid ne "" ) {
        }
        next;
      }

      print "merchantnum: $merchantnum\n";
      print "threemonthsago: $threemonthsago\n";
      print "refnumber: $refnumber\n";
      print "$username $orderid $status $operation\n";

      print OUTFILE3 "$username $orderid $operation $status $amount $refnumber $rcode\n";

      if ( $orderid eq "" ) {
        print "ORDERID NOT FOUND\n";

        open( MAIL, "| /usr/lib/sendmail -t" );
        print MAIL "To: dprice\@plugnpay.com\n";
        print MAIL "From: dprice\@plugnpay.com\n";
        print MAIL "Subject: mtbankach - bad file\n";
        print MAIL "\n";
        print MAIL "File has a non-existent orderid.\n";
        print MAIL "file: $file\n";
        print MAIL "twomonthsago: $twomonthsago\n";
        print MAIL "usernames: $usernames\n";
        print MAIL "transid: $transid\n";
        print MAIL "filename: $filename\n\n";
        print MAIL "merchantnum: $merchantnum\n\n";
        print MAIL "refnumber: $refnumber\n\n";
        print MAIL "amount: $amount\n";
        print MAIL "name: $name\n";
        print MAIL "tdate: $tdate\n";
        $mydescr = "$rcode: " . $returncodes{"$rcode"};
        $mydescr =~ s/'//g;
        print MAIL "descr: $mydescr\n";
        close(MAIL);
      } elsif ( $rcode =~ /^C/ ) {
        print "PROCESSUNG NOC UN:$username, OID:$orderid, OP:$operation, NAME:$name, RCODE:$rcode, NOCINFO:$nocinfo\n";

        #&processnoc("$username","$orderid","$operation","$name","$rcode","$nocinfo");
      } elsif ( $rcode =~ /^R/ ) {
        print "PROCESSING RETURN, UN:$username, OID:$orderid, OP:$operation\n";
        my $sthupd = $dbh->prepare(
          qq{
          update batchfilesmtbank
          set status='done'
          where orderid='$orderid'
          and username='$username'
          and operation='$operation'
          and status='locked'
          }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sthupd->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sthupd->finish;

        &processreturn( "$username", "$orderid", "$operation", "$name", "$rcode", "$filedate" );
      } else {
        open( MAILERR, "| /usr/lib/sendmail -t" );
        print MAILERR "To: dprice\@plugnpay.com\n";
        print MAILERR "From: dprice\@plugnpay.com\n";
        print MAILERR "Subject: mtbankach - getfiles.pl - FAILURE\n";
        print MAILERR "\n";
        print MAILERR "invalid rcode\n\n";
        print MAILERR "filename: $filename\n\n";
        print MAILERR "merchantnum: $merchantnum\n\n";
        print MAILERR "refnumber: $refnumber\n\n";
        print MAILERR "username: $username\n\n";
        print MAILERR "orderid: $orderid\n\n";
        print MAILERR "operation: $operation\n\n";
        print MAILERR "rcode: $rcode\n\n";
        close MAILERR;
      }
    }
  }
  close(INFILE);
  close(OUTFILE2);
  close(OUTFILE3);

}

sub getfiledate {
  my ($filename) = @_;
  my $filedate = "";
  if ( $filename =~ /^ACH_RETURNS([0-9]{4})([0-9]{4})/ ) {
    $filedate = $2 . $1;
  }
  return $filedate;
}

sub processsuccesses {
  my $sthbatch = $dbh->prepare(
    qq{
        select username,orderid,operation
        from batchfilesmtbank
        where trans_date>=?
        and trans_date<=?
        and status=?
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthbatch->execute( $threemonthsago, $sevendaysago, 'locked' ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthbatch->bind_columns( undef, \( $username, $orderid, $operation ) );

  $batchcnt = 0;
  while ( $sthbatch->fetch ) {
    if ( $operation eq "" ) {
      $operation = 'postauth';
    }
    &processsuccess( $username, $orderid, $operation );

    my $sthupd = $dbh->prepare(
      qq{
        update batchfilesmtbank
        set status='done'
        where trans_date>='$threemonthsago'
        and orderid='$orderid'
        and username='$username'
        and operation='$operation'
        and status='locked'
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sthupd->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sthupd->finish;
  }
  $sthbatch->finish;
}

sub processfailures {
  ###  Don't think this is needed
  my $sthbatch = $dbh->prepare(
    qq{
        select username,orderid,operation
        from batchfilesmtbank
        where trans_date>='$threemonthsago'
        and trans_date<='$fourdaysago'
        and status='locked'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthbatch->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthbatch->bind_columns( undef, \( $username, $orderid, $operation ) );

  my @failurearray = ();
  my $mycount      = 0;
  while ( $sthbatch->fetch ) {
    $failurearray[ ++$#failurearray ] = "$username $orderid $operation";
    $mycount++;
  }
  $sthbatch->finish;

  if ( $mycount > 0 ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: mtbankach - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "The following orders did not receive a pending file from mtbankach:\n";
    foreach my $var (@failurearray) {
      print MAILERR "$var\n";
    }
    close(MAILERR);
  }
}

sub processnoc {
  my ( $username, $orderid, $operation, $name, $noccode, $nocinfo ) = @_;

  $nocdesc = $returncodes{"$noccode"};

  print "$cardnumber";
  print "$nocinfo\n";
  print "username: $username\n";
  print "orderid: $orderid\n";
  print "nocinfo: $nocinfo\n";
  print "oldroute: $oldroute\n";
  print "oldacct: $oldacct\n";
  print "noccode: $noccode\n";
  print "nocdesc: $nocdesc\n";

  umask 0077;
  open( outfile, ">>/home/p/pay1/batchfiles/$devprod/mtbankach/returns/$today" . "summary.txt" );
  print outfile "\nfile: $file\n";
  print outfile "usernames: $usernames\n";
  print outfile "username: $username\n";
  print outfile "orderid: $orderid\n";
  print outfile "descr: $noccode: $nocdesc\n";
  close(outfile);

  $newacct = "";
  $newrout = "";
  if ( $noccode eq "C01" ) {
    $newacct = substr( $nocinfo, 0, 17 );
    $newacct =~ s/ //g;
    $descr = "New Route Number: $newrout New Account Number: $newacct";
  } elsif ( $noccode eq "C02" ) {
    $newrout = substr( $nocinfo, 0, 9 );
    $newrout = $nocinfo;
    $newrout =~ s/ //g;
    $descr = "New Route Number: $newrout New Account Number: $newacct";
  } elsif ( $noccode eq "C03" ) {
    $newrout = substr( $nocinfo, 0, 9 );
    $newacct = substr( $nocinfo, 9, 17 );
    $newrout =~ s/ //g;
    $newacct =~ s/ //g;
    $descr = "New Route Number: $newrout New Account Number: $newacct";
  } elsif ( $noccode eq "C04" ) {
    $newname = substr( $nocinfo, 0, 22 );
    $newname =~ s/ //g;
    $descr = "New Individual/Company Name: $newname";
  } elsif ( $noccode eq "C05" ) {
    $newtcode = substr( $nocinfo, 0, 2 );
    $newtcode =~ s/ //g;
    %tcodes = ( "27", "checking", "37", "savings", "22", "checking", "32", "savings" );
    $descr = "New Account type: $tcodes{$newtcode}";
  } elsif ( $noccode eq "C06" ) {

    # must use savings as the account type
    $newacct = substr( $nocinfo, 0, 17 );
    $newacct =~ s/ //g;
    $newtcode = substr( $nocinfo, 17, 2 );
    $newtcode =~ s/ //g;
    %tcodes = ( "27", "checking", "37", "savings", "22", "checking", "32", "savings" );
    $descr = "New Account Number: $newacct New Account Type: $tcodes{$newtcode}";

    #($newacct,$newaccttype) = split(/   /,$nocinfo);
    #$newacct =~ s/ //g;
  } elsif ( $noccode eq "C07" ) {

    # must use savings as the account type
    $newrout = substr( $nocinfo, 0, 9 );
    $newrout =~ s/ //g;
    $newacct = substr( $nocinfo, 9, 17 );
    $newacct =~ s/ //g;
    $newtcode = substr( $nocinfo, 26, 2 );
    $newtcode =~ s/ //g;
    %tcodes = ( "27", "checking", "37", "savings", "22", "checking", "32", "savings" );
    $descr = "New Route Number: $newrout New Account Number: $newacct New Account Type: $tcodes{$newtcode}";

    #($newacct,$newaccttype) = split(/   /,$nocinfo);
    #$newacct =~ s/ //g;
  } else {

    #$nocinfo = substr($line2,44,42);
  }

  $pnpcompany = "Plug and Pay";
  $pnpemail   = "accounting\@plugnpay.com";

  my $sth_res = $dbh->prepare(
    qq{
      select reseller,techemail from customers
      where username='$username' 
      }
    )
    or die "Can't do: $DBI::errstr";
  $sth_res->execute or die "Can't execute: $DBI::errstr";
  ( $reseller, $email ) = $sth_res->fetchrow;
  $sth_res->finish;

  $descr = "New Route Number: $newrout New Account Number: $newacct";
  if ( $newaccttype eq "37" ) {
    $descr = $descr . " Must use savings";
  }
  $error = "$noccode: $nocdesc";

  %datainfo = ( "username", "$username", "today", "$today", "orderid", "$orderid", "name", "$name", "descr", "$descr", "error", "$error" );

  my $sth_chk = $dbh->prepare(
    qq{
      select orderid from achnoc
      where orderid='$orderid'
      and username='$username'
      and error like '$noccode\%'
      }
    )
    or die "Can't do: $DBI::errstr";
  $sth_chk->execute or die "Can't execute: $DBI::errstr";
  ($chkorderid) = $sth_chk->fetchrow;
  $sth_chk->finish;

  if ( $chkorderid eq "" ) {
    my $sth_ins = $dbh->prepare(
      qq{
        insert into achnoc 
        (username,trans_date,orderid,name,descr,error)
        values (?,?,?,?,?,?) 
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth_ins->execute( "$username", "$today", "$orderid", "$name", "$descr", "$error" )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sth_ins->finish;

    if ( $emailedmerch{$username} eq "" ) {
      $emailedmerch{$username} = "yes";

      if ( $plcompany{$reseller} ne "" ) {
        $privatelabelflag    = 1;
        $privatelabelcompany = $plcompany{$reseller};
        $privatelabelemail   = $plemail{$reseller};
      } else {
        $privatelabelflag    = 0;
        $privatelabelcompany = $pnpcompany;
        $privatelabelemail   = $pnpemail;
      }

      open( MAIL, "| /usr/lib/sendmail -t" );
      print MAIL "To: $email\n";
      print MAIL "Bcc: cprice\@plugnpay.com\n";
      print MAIL "From: $privatelabelemail\n";
      print MAIL "Subject: $privatelabelcompany - Notification of Change - $username\n";
      print MAIL "\n";
      print MAIL "We received a Notification of Change for some customers. If you do any more\n";
      print MAIL "electronic checking transactions for these customers, please use the new information\n";
      print MAIL "to prevent fees from being charged.\n\n";
      print MAIL "The new information can be found at:\n\n";
      print MAIL "https://pay1.plugnpay.com/admin/noc.cgi\n";
      print MAIL "\nThankyou,\n";
      print MAIL "$privatelabelcompany\n";
      close(MAIL);
    }
  }

}

sub processsuccess {
  my ( $username, $orderid, $operation ) = @_;
  print "cccc $orderid $twomonthsago $twomonthsagotime $username $operation\n";

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  my $sthpass = $dbh2->prepare(
    qq{
          update trans_log set finalstatus='success'
          where orderid='$orderid'
          and trans_date>='$twomonthsago'
          and username='$username'
          and operation='$operation'
          and finalstatus in ('pending','locked')
          and accttype in ('checking','savings')
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthpass->execute() or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthpass->finish;

  %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
  my $sthop = $dbh2->prepare(
    qq{
          update operation_log set $operationstatus='success',lastopstatus='success'
          where orderid='$orderid'
          and lastoptime>='$twomonthsagotime'
          and username='$username'
          and lastop='$operation'
          and $operationstatus in ('pending','locked')
          and accttype in ('checking','savings')
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthop->execute() or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );

}

sub processreturn {
  my ( $username, $orderid, $operation, $card_name, $rcode, $filedate ) = @_;

  $descr = "$rcode: " . $returncodes{"$rcode"};
  $descr =~ s/'//g;

  print "In processreturn: UN:$username, OID:$orderid, OP:$operation, NAME:$card_name, RCODE:$rcode, FD:$filedate\n";

  %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

  #my $sth_email = $dbh->prepare(qq{
  #      select emailflag from mtbankach
  #      where username='$username'
  #      }) or die "Can't prepare: $DBI::errstr";
  #$sth_email->execute or die "Can't execute: $DBI::errstr";
  #($sendemailflag) = $sth_email->fetchrow;
  #$sth_email->finish;

  my $sth1 = $dbh2->prepare(
    qq{
          select orderid
          from trans_log
          where orderid='$orderid'
          and username='$username'
          and operation='$operation'
          and descr='$descr'
       }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth1->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ($chkorderid) = $sth1->fetchrow;
  $sth1->finish;

  $emailflag = 1;
  if ( ( $sendemailflag eq "no" ) || ( $chkorderid ne "" ) ) {
    $emailflag = 0;
  }

  #$emailflag = 0;

  my $sth2 = $dbh2->prepare(
    qq{
          select card_name,acct_code,acct_code2,acct_code3,acct_code4,amount,accttype,result
          from trans_log
          where orderid='$orderid'
          and username='$username'
          and operation='$operation'
       }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth2->execute or &miscutils::errmaildie( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $card_name, $acct_code1, $acct_code2, $acct_code3, $acct_code4, $amount, $accttype, $batchid ) = $sth2->fetchrow;
  $sth2->finish;

  print "aa username: $username\n";
  print "aa orderid: $orderid\n";
  print "aa operation: $operation\n";
  print "aa amount: $amount\n";
  print "aa rcode: $rcode\n";
  print "aa descr: $descr\n";
  print "aa filename: $filename\n";
  print "aa emailflag: $emailflag\n";

  umask 0077;
  open( logfile, ">>/home/p/pay1/batchfiles/logs/mtbankach/chk$username.txt" );
  print logfile "aa username: $username\n";
  print logfile "aa orderid: $orderid\n";
  print logfile "aa operation: $operation\n";
  print logfile "aa amount: $amount\n";
  print logfile "aa descr: $descr\n";
  print logfile "aa filename: $filename\n";
  print logfile "aa twomonthsago: $twomonthsago\n";
  print logfile "aa twomonthsagotime: $twomonthsagotime\n";
  print logfile "aa emailflag: $emailflag\n\n";
  close(logfile);

  my $sthfail = $dbh2->prepare(
    qq{
          update trans_log set finalstatus='badcard',descr=?
          where orderid='$orderid'
          and username='$username'
          and operation='$operation'
          and accttype in ('checking','savings')
       }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthfail->execute("$descr") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthfail->finish;

  ( $curr, $price ) = split( / /, $amount );
  if ( $operation ne "return" ) {
    $price = $curr . " -" . $price;
  }

  my $yearmonthdayhms = $filedate . "000000";

  my $sthfail2 = $dbh2->prepare(
    qq{
        insert into trans_log
        (username,orderid,operation,trans_date,trans_time,batch_time,descr,amount,accttype,card_name,result,acct_code,acct_code2,acct_code3,acct_code4)
        values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthfail2->execute(
    "$username", "$orderid",   "chargeback", "$filedate",   "$yearmonthdayhms", "$todaytime",  "$descr", "$price",
    "$accttype", "$card_name", "$batchid",   "$acct_code1", "$acct_code2",      "$acct_code3", "$acct_code4"
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthfail2->finish;

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  my $sthop = $dbh2->prepare(
    qq{
          update operation_log set lastopstatus='badcard',$operationstatus='badcard',descr=?
          where orderid='$orderid'
          and username='$username'
          and accttype in ('checking','savings')
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthop->execute("$descr") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthop->finish;

  $pnpcompany = "Plug and Pay";
  $pnpemail   = "accounting\@plugnpay.com";

  my $sth_res = $dbh->prepare(
    qq{
        select reseller,techemail from customers
        where username='$username'
        }
    )
    or die "Can't do: $DBI::errstr";
  $sth_res->execute or die "Can't execute: $DBI::errstr";
  ( $reseller, $email ) = $sth_res->fetchrow;
  $sth_res->finish;

  if ( $plcompany{$reseller} ne "" ) {
    $privatelabelflag    = 1;
    $privatelabelcompany = $plcompany{$reseller};
    $privatelabelemail   = $plemail{$reseller};
  } else {
    $privatelabelflag    = 0;
    $privatelabelcompany = $pnpcompany;
    $privatelabelemail   = $pnpemail;
  }

  $sth_tl = $dbh2->prepare(
    qq{
          select acct_code3
          from trans_log
          where orderid='$orderid'
          and operation='postauth'
          }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_tl->execute or die "Can't execute: $DBI::errstr";
  ($acct_code3) = $sth_tl->fetchrow;
  $sth_tl->finish;

  if ( $acct_code3 eq "recurring" ) {
    $dbhmerch = &miscutils::dbhconnect("$username");

    $sth_pl = $dbhmerch->prepare(
      qq{
          select username,orderid
          from billingstatus
          where orderid='$orderid'
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_pl->execute or die "Can't execute: $DBI::errstr";
    ( $chkusername, $chkorderid ) = $sth_pl->fetchrow;
    $sth_pl->finish;

    if ( $chkorderid ne "" ) {
      $sth_status = $dbhmerch->prepare(
        qq{
          insert into billingstatus
          (username,trans_date,amount,orderid,descr)
          values (?,?,?,?,?)
          }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_status->execute( "$chkusername", "$today", "-$amount", "$orderid", "$descr" ) or die "Can't execute: $DBI::errstr";
      $sth_status->finish;
    }
    $dbhmerch->disconnect;
  }

  print "privatelabelcompany: $privatelabelcompany\n";
  print "email: $email\n";
  print "orderid: $orderid\n";
  print "reason: $descr\n";

  if ( $emailflag == 1 ) {
    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: $email\n";
    print MAIL "Bcc: cprice\@plugnpay.com\n";
    print MAIL "Bcc: barbara\@plugnpay.com\n";

    #print MAIL "Bcc: accounting\@plugnpay.com\n";
    print MAIL "From: $privatelabelemail\n";
    print MAIL "Subject: $privatelabelcompany - mtbankach Order $username $orderid failed\n";
    print MAIL "\n";
    print MAIL "$username\n\n";
    print MAIL "We would like to inform you that order $orderid received a Return notice\n";
    print MAIL "today.\n\n";
    print MAIL "Orderid: $orderid\n\n";
    print MAIL "Card Name: $card_name\n\n";
    print MAIL "Amount: $amount\n\n";

    if ( $authtime1 ne "" ) {
      $authdate = substr( $authtime1, 4, 2 ) . "/" . substr( $authtime1, 6, 2 ) . "/" . substr( $authtime1, 0, 4 );
      print outfile "Auth Date: $authdate\n";
    }
    print MAIL "Reason: $descr\n\n";
    if ( $acct_code1 ne "" ) {
      print MAIL "AcctCode1: $acct_code1\n\n";
    }
    if ( $acct_code2 ne "" ) {
      print MAIL "AcctCode2: $acct_code2\n\n";
    }
    if ( $acct_code3 ne "" ) {
      print MAIL "AcctCode3: $acct_code3\n\n";
    }
    print MAIL "Plug & Pay Technologies\n";
    close(MAIL);
  }

}

sub checkdir {
  my ($date) = @_;

  my $fileyear = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 );
  my $filemonth = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 );
  my $fileyearonly = substr( $date, 0, 4 );

  if ( !-e "/home/p/pay1/batchfiles/logs/mtbankach/$fileyearonly" ) {
    print "creating $fileyearonly\n";
    system("mkdir /home/p/pay1/batchfiles/logs/mtbankach/$fileyearonly");
    chmod( 0700, "/home/p/pay1/batchfiles/logs/mtbankach/$fileyearonly" );
  }
  if ( !-e "/home/p/pay1/batchfiles/logs/mtbankach/$filemonth" ) {
    print "creating $filemonth\n";
    system("mkdir /home/p/pay1/batchfiles/logs/mtbankach/$filemonth");
    chmod( 0700, "mkdir /home/p/pay1/batchfiles/logs/mtbankach/$filemonth" );
  }
  if ( !-e "/home/p/pay1/batchfiles/logs/mtbankach/$fileyear" ) {
    print "creating $fileyear\n";
    system("mkdir /home/p/pay1/batchfiles/logs/mtbankach/$fileyear");
    chmod( 0700, "mkdir /home/p/pay1/batchfiles/logs/mtbankach/$fileyear" );
  }
  if ( !-e "/home/p/pay1/batchfiles/logs/mtbankach/$fileyear" ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dprice\@plugnpay.com\n";
    print MAILERR "Subject: mtbankach - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Couldn't create directory logs/mtbankach/$fileyear.\n\n";
    close MAILERR;
    exit;
  }

}

sub email {
  my ( $username, $message ) = @_;

  my ( $junk1, $junk2, $message_time ) = &miscutils::genorderid();
  my $dbh_email = &miscutils::dbhconnect("emailconf");
  my $sth_email = $dbh_email->prepare(
    qq{
          insert into message_que2
          (message_time,username,status,format,body)
          values (?,?,?,?,?)
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckkutils::query );
  $sth_email->execute( $message_time, $username, "pending", 'text', $message ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckkutils::query );
  $sth_email->finish;
  $dbh_email->disconnect;

}

sub getFile {

  #my $ftphost = "secureftp.mandtbank.com";
  #my $ftpusername = "SOVRAN";
  #my $ftppassword = "s1o2v3r4";
  #my $remotedir = "/SOVRAN/ACH_OUT/SSH_OT";

  my $ftphost     = "mft.mtb.com";
  my $ftpusername = "PlugPay";
  my $ftppassword = "GnRLhU0K";
  my $remotedir   = "/ACH_OUT";

  my $filemask      = "";
  my $debug_level   = 9;
  my @filenamearray = ();

  my $sftp = Net::SFTP::Foreign->new( 'host' => "$ftphost", 'user' => $ftpusername, 'password' => $ftppassword, 'timeout' => 240 );
  if ( $sftp eq "" ) {
    print "Host $ftphost username $ftpusername and password don't work\n";
    exit;
  }

  if ( $sftp->error ) {
    print "SSH connection failed: " . $sftp->error . "  trying again...\n";
    $sftp = Net::SFTP::Foreign->new( 'host' => "$ftphost", 'user' => $ftpusername, 'password' => $ftppassword, 'timeout' => 240 );
  }

  $sftp->error and die "SSH connection failed: " . $sftp->error;

  print "aaaa\n";

  my $file_list = $sftp->ls("$remotedir/");

  foreach my $filehash (@$file_list) {
    my $filename = $$filehash{'filename'};

    print "DIR LISTING FN:$filename\n";

    if ( $filename =~ /^ACH/ ) {
      print "cc $filename\n";
    } else {
      next;
    }
    if ( length($filename) < 4 ) {
      next;
    }
    $filedate = &getfiledate("$filename");
    $fileyear = substr( $filedate, 0, 4 ) . "/" . substr( $filedate, 4, 2 ) . "/" . substr( $filedate, 6, 2 );
    &checkdir("$filedate");

    my $timestr = &miscutils::strtotime($filedate);
    my $now     = time();
    if ( $now - $timestr > ( 3600 * 24 * 10 ) ) {
      next;
    }

    @filenamearray = ( @filenamearray, $filename );

    ## Only 1 file download allowed per session so reconnecting
    #foreach my $filename (@filenamearray) {

    print "Reconnecting, Attempting to download $filename\n";

    $filedate = &getfiledate("$filename");
    $fileyear = substr( $filedate, 0, 4 ) . "/" . substr( $filedate, 4, 2 ) . "/" . substr( $filedate, 6, 2 );

    if ( ( !-e "$root_file_path/$fileyear/$filename" ) && ( !-e "$root_file_path/$fileyear/$filename.txt" ) ) {
      print "getting file From $remotedir/$filename -->  $root_file_path/$fileyear/$filename\n";
      $sftp->get( "$remotedir/$filename", "$root_file_path/$fileyear/$filename", 'copy_perm' => 0, 'copy_time' => 0 );
      $sftp->error and die "SSH command failed: " . $sftp->error;
      chmod( 0600, "$root_file_path/$fileyear/$filename" );
    }

    $sftp->disconnect;
  }

  return @filenamearray;

}

