#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SFTP::Foreign;
use miscutils;
use rsautils;
use SHA;

$devprod = "logs";

# del aware returns file comes at 6:00am

$ENV{PATH} = ".:/usr/ucb:/usr/bin:/usr/local/bin";

#$redofile = "ARTN0403482716PLUG4099.ACH";
#$redofile = "returnexample.txt";
#$redofile = "pnp-results.20100322221504";
#$redofile = "pnp-20110721-033036-returns.ach.txt";

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

print "\n\n$today\n\n";

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/p/pay1/batchfiles/$devprod/citynat/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/p/pay1/batchfiles/$devprod/citynat/$fileyearonly");
  system("chmod 0700 /home/p/pay1/batchfiles/$devprod/citynat/$fileyearonly");
}
if ( !-e "/home/p/pay1/batchfiles/$devprod/citynat/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/p/pay1/batchfiles/$devprod/citynat/$filemonth");
  system("chmod 0700 /home/p/pay1/batchfiles/$devprod/citynat/$filemonth");
}
if ( !-e "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/p/pay1/batchfiles/$devprod/citynat/$fileyear");
  system("chmod 0700 /home/p/pay1/batchfiles/$devprod/citynat/$fileyear");
}
if ( !-e "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: citynat - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/citynat/$fileyear.\n\n";
  close MAILERR;
  print "Couldn't create directory logs/citynat/$fileyear\n";
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

$batchfile = substr( $redofile, 3, 14 );

if ( $redofile ne "" ) {
  $filedate = &getfiledate("$redofile");
  $fileyear = substr( $filedate, 0, 4 ) . "/" . substr( $filedate, 4, 2 ) . "/" . substr( $filedate, 6, 2 );
  print "filedate: $filedate\n";
  print "fileyear: $fileyear\n";
  print "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$redofile\n";

  if ( -e "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$redofile" ) {
    &processfile($redofile);
    $dbh->disconnect;
    $dbh2->disconnect;
    exit;
  }
}

#  my $sthbatch1 = $dbh->prepare(qq{
#        select distinct c.username,c.merchant_id
#        from customers c, batchfilesfifth b
#        where b.status='locked'
#        and c.username=b.username
#        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
#  $sthbatch1->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
#  $sthbatch1->bind_columns(undef,\($user,$mid));
#
#  while ($sthbatch1->fetch) {
#    $newmid = substr($mid,0,7);
#    $newuserarray{$newmid} = $user;
#  }
#  $sthbatch1->finish;

#my $sthbatch = $dbh->prepare(qq{
#      select distinct filename
#      from batchfilesfifth
#      where status='locked'
#      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
#$sthbatch->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
#$sthbatch->bind_columns(undef,\($batchfile));

#$batchcnt = 0;
#while ($sthbatch->fetch) {
#  $filename = $batchfile;
#  $batchcnt++;
#print "aaaa $filename  $batchcnt\n";
#}
#$sthbatch->finish;

#if ($batchcnt < 1) {
#  print "More/less than one locked batch  $batchcnt   exiting\n";
#  exit;
#}

my $ftpun = 'plugdp';
my $host  = 'fc1.citynational.com';

my %args = (
  user => "MSOD-001057",
  port => 1022,                                                             # only use with Net::SFTP::Foreign
  more => [ -i => '/home/p/pay1/batchfiles/prod/fdmsemvcan/.ssh/id_rsa' ]
);

#more => [@opts] );

#$ftp = Net::FTP->new("$fdmsaddr", 'Timeout' => 2400, 'Debug' => 1, 'Port' => "21");
#$ftp = Net::SFTP::Foreign->new('host' => "$host",'user' => $ftpun, 'password' => $ftppw, 'timeout' => 30, more => '-v');
#$ftp = Net::SFTP::Foreign->new('host' => "$host",'user' => $ftpun, 'password' => $ftppw, 'timeout' => 30);
#my @opts = ('-v','-i','/home/p/pay1/.ssh/id_rsa');     # put '-v' at the begginning for debugging
my %args = (
  user => "$ftpun",
  port => 22,
  more => [ -i => '/home/p/pay1/batchfiles/prod/citynat/.ssh/id_rsa' ]
);

#more => [@opts] );
my $ftp = Net::SFTP::Foreign->new( "$host", %args );

#$ftp->error and die "cannot connect: " . $ftp->error;
if ( $ftp eq "" ) {
  print "Host $host username $username and key don't work<br>\n";
  exit;

  #$ftp = Net::FTP->new("$fdmsaddr", 'Timeout' => 2400, 'Debug' => 1, 'Port' => "21");
  #if ($ftp eq "") {
  #  exit;
  #}
}

$ftp->error and die "SSH connection failed: " . $ftp->error;

print "logged in\n";

#if ($ftp->login("$ftpun","$ftppw") eq "") {
#  print "Username $ftpun and password don't work<br>\n";
#  print "failure";
#  exit;
#}

#$ftp->quot("SITE FILETYPE=JES");

print "aaaa\n";

if ( $redofile ne "" ) {
  $filedate = &getfiledate("$redofile");
  $fileyear = substr( $filedate, 0, 4 ) . "/" . substr( $filedate, 4, 2 ) . "/" . substr( $filedate, 6, 2 );
  &checkdir("$filedate");

  my $ls = $ftp->cwd();
  print "$ls\n";

  #if ($redofile =~ /returns/) {
  $ls = $ftp->ls("From CNB/");

  #}
  #else {
  #  $ls = $ftp->ls("/users/pnp/results");
  #}
  $ftp->error and die "SSH command failed: " . $ftp->error;

  #my @files = $ftp->ls("/in/$achfilename");

  my $file1flag = 0;
  my $file2flag = 0;
  foreach my $var (@$ls) {
    print "bb " . $var->{"filename"} . "\n";
  }

  if ( !-e "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$redofile" ) {
    if ( $redofile =~ /returns/ ) {
      $ftp->get( "/users/pnp/returns/$redofile", "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$redofile" );
    } else {
      $ftp->get( "/users/pnp/results/$redofile", "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$redofile" );
    }
    $ftp->error and die "SSH command failed: " . $ftp->error;
    chmod( 0600, "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$redofile" );
  }

  #$ftp->quit();
  $ftp->disconnect;

  &processfile($redofile);

  &processsuccesses();

  $dbh->disconnect;
  $dbh2->disconnect;
  exit;
}

print "bbbb\n";

my $ls = $ftp->cwd();
print "$ls\n";
my $ls = $ftp->ls("From CNB/");
$ftp->error and die "SSH command failed: " . $ftp->error;

#my @files = $ftp->ls("/in/$achfilename");

my $file1flag = 0;
my $file2flag = 0;
foreach my $var (@$ls) {
  $filename = $var->{"filename"};

  if ( $filename =~ /.ACH$/ ) {
    print "cc $filename\n";
  }

  if ( length($filename) < 4 ) {
    next;
  }
  if ( $filename =~ /20101|2011/ ) {
    print "bbb " . $var->{"filename"} . "\n";
  }

  if ( $filename !~ /.ACH$/ ) {
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

  if ( ( !-e "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename" ) && ( !-e "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename.txt" ) ) {
    print "getting file From CNB/$filename   /home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename\n";
    $ftp->get( "From CNB/$filename", "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename", 'copy_perm' => 0, 'copy_time' => 0 );
    $ftp->error and die "SSH command failed: " . $ftp->error;
    chmod( 0600, "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename" );
    @filenamearray = ( @filenamearray, $filename );
  }

  #if (-e "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$var") {
  #  $ftp->rename("$var","../Done/$var");
  #}
}

print "cccc\n";

#$ftp->quit();
$ftp->disconnect;

print "dddd\n";

foreach $filename (@filenamearray) {
  print "processing: $filename\n";
  &processfile($filename);
}

&processsuccesses();
&processfailures();

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
  open( infile,   "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename" );
  open( outfile2, ">/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename.out" );

  #if ($filename =~ /return/) {
  open( outfile3, ">/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/t$filename" );

  #}
  while (<infile>) {
    $line = $_;
    chop $line;

    print "$line\n";

    #if ($filename =~ /return/) {
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
    print outfile2 "$tmpline\n";

    #if ($line =~ /\",\"/) {
    #  ($merchantnum,$d1,$date,$tcode,$routenum,$acctnum,$amount,$refnumber,$name,$rcode,$nocinfo) = split(/","/,$line);
    #}
    #else {
    #  ($merchantnum,$d1,$date,$tcode,$routenum,$acctnum,$amount,$refnumber,$name,$rcode,$nocinfo) = split(/,/,$line);
    #}
    #$returnflag = 1;
    #$merchantnum =~ s/"//g;
    #$nocinfo =~ s/"//g;
    #$tdate = "20" . $date;
    #}
    #else {
    #  ($name,$refnumber,$d1,$d2,$d3,$d4,$amount,$tcode,$date,$commtype,$tcode,$routenum,$acctnum) = split(/\|/,$line);
    #  $returnflag = 0;
    #  $processflag = 1;
    #
    #      $name =~ s/ +$//g;
    #      $acctnum =~ s/ +$//g;
    #
    #      my $tmpline = $line;
    #      my $xs = "x" x length($routenum);
    #      $tmpline =~ s/$routenum/$xs/;
    #      my $xs = "x" x length($acctnum);
    #      $tmpline =~ s/$acctnum/$xs/;
    #      print outfile2 "$tmpline\n";
    #
    #      $date = substr($date,0,4) . substr($date,5,2) . substr($date,8,2);
    #
    #      $batchfilename = $filename;
    #      $batchfilename =~ s/[^0-9]//g;
    #
    #      if (length($refnumber) < 6) {
    #        next;
    #      }
    #    }

    print "dddd\n";

    #$xs = "x" x length($oldcardnumber);
    #$line =~ s/$oldcardnumber/$xs/;
    #$xs = "x" x length($newcardnumber);
    #$line =~ s/$newcardnumber/$xs/;
    #print outfile "$line\n";

    if ( $processflag == 1 ) {
      print "processflag == 1\n";

      $cardnumber = "$routenum $acctnum";
      $sha1       = new SHA;
      $sha1->reset;
      $sha1->add($cardnumber);
      $shacardnumber = $sha1->hexdigest();

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

      if ( $newcardnumber ne "" ) {
        $cardnumber = "$newcardnumber";
      } else {
        $cardnumber = "$oldcardnumber";
      }

      if ( $newexp ne "" ) {
        $exp = "$newexp";
      } else {
        $exp = "$oldexp";
      }

      my $encdata = "";
      if ( ( ( $newcardnumber ne "" ) || ( $newexp ne "" ) ) && ( $cardnumber ne "" ) && ( $exp ne "" ) ) {
        ($encdata) = &rsautils::rsa_encrypt_card( "$exp $cardnumber", '/home/p/pay1/pwfiles/keys/key', 'log' );
      }

      print "\n$threemonthsago\n";
      print "$refnumber\n";

      my $sthord = $dbh->prepare(
        qq{
              select username,orderid,status,operation
              from batchfilescity
              where trans_date>='$threemonthsago'
              and refnumber='$refnumber'
              }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthord->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      ( $username, $orderid, $status, $operation ) = $sthord->fetchrow;
      $sthord->finish;
      print "username: $username\n";
      print "orderid: $orderid\n";
      print "status: $status\n";
      print "operation: $operation\n";

      if ( $returnflag != 1 ) {
        if ( $orderid ne "" ) {
          my $sthupd = $dbh->prepare(
            qq{
              update batchfilescity
              set status='locked'
              where trans_date>='$threemonthsago'
              and orderid='$orderid'
              and username='$username'
              and status='locked'
              }
            )
            or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
          $sthupd->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
          $sthupd->finish;
        }
        next;
      }
      print "merchantnum: $merchantnum\n";
      print "threemonthsago: $threemonthsago\n";
      print "refnumber: $refnumber\n";
      print "$username $orderid $status $operation\n";

      print outfile3 "$username $orderid $operation $status $amount $refnumber $rcode\n";

      if ( ( $orderid eq "" ) && ( $refnumber !~ /^(FLI|FLS|PTS|FLO|WIN|FLW|OPT|ICN|SEL|Q)/ ) ) {
        open( MAIL, "| /usr/lib/sendmail -t" );
        print MAIL "To: cprice\@plugnpay.com\n";
        print MAIL "From: dcprice\@plugnpay.com\n";
        print MAIL "Subject: citynat - bad file\n";
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
      } elsif ( ( $orderid eq "" ) && ( $refnumber =~ /^(FLI|FLS|PTS|FLO|WIN|FLW|OPT|ICN|SEL)/ ) ) {

        # ignore as these are not ours
      } elsif ( $rcode =~ /^C/ ) {
        &processnoc( "$username", "$orderid", "$operation", "$name", "$rcode", "$nocinfo" );
      } elsif ( $rcode =~ /^R/ ) {

        #where trans_date>='$threemonthsago'
        my $sthupd = $dbh->prepare(
          qq{
          update batchfilescity
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
        print MAILERR "To: cprice\@plugnpay.com\n";
        print MAILERR "From: dcprice\@plugnpay.com\n";
        print MAILERR "Subject: citynat - getfiles.pl - FAILURE\n";
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
  close(infile);
  close(outfile2);
  if ( $filename =~ /return/ ) {
    close(outfile3);
  }

  #unlink "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename";
}

sub getfiledate {
  my ($filename) = @_;

  my $filedate = "";
  if ( $filename =~ /^ARTN([0-9]{6})/ ) {
    $mmddyy = $1;
    $filedate = "20" . substr( $mmddyy, 4, 2 ) . substr( $mmddyy, 0, 4 );

    #if ($filedate !~ /^20/) {
    #  $filedate = "20" . substr($filedate,0,6);
    #}
  }

  return $filedate;
}

sub processsuccesses {
  print "process successes\n";
  my $sthbatch = $dbh->prepare(
    qq{
        select username,orderid,operation
        from batchfilescity
        where trans_date>='$threemonthsago'
        and trans_date<='$sevendaysago'
        and status='locked'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthbatch->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthbatch->bind_columns( undef, \( $username, $orderid, $operation ) );

  $batchcnt = 0;
  while ( $sthbatch->fetch ) {
    &processsuccess( $username, $orderid, $operation );

    my $sthupd = $dbh->prepare(
      qq{
        update batchfilescity
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
  my $sthbatch = $dbh->prepare(
    qq{
        select username,orderid,operation
        from batchfilescity
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
    print MAILERR "Subject: citynat - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "The following orders did not receive a pending file from citynat:\n";
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
  open( outfile, ">>/home/p/pay1/batchfiles/$devprod/citynat/returns/$today" . "summary.txt" );
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
        select reseller,merchemail from customers
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

  if ( $username =~ /^(pnpcitynat|ach2)/ ) {
    print "aaaa\n";

    my $sth_status = $dbh->prepare(
      qq{
          select username,orderid,trans_date,amount,card_type,descr,commission,paidamount,paiddate,transorderid,checknum
          from billingstatus
          where orderid='$orderid'
          and result='hold'
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_status->execute or die "Can't execute: $DBI::errstr";
    $sth_status->bind_columns( undef, \( $busername, $borderid, $btrans_date, $bamount, $bcard_type, $bdescr, $bcommission, $bpaidamount, $bpaiddate, $btransorderid, $bchecknum ) );

    while ( $sth_status->fetch ) {
      print "billing username: $busername $borderid\n";
      my $sth_insert = $dbh->prepare(
        qq{
              insert into billingreport
              (username,orderid,trans_date,amount,card_type,descr,commission,paidamount,paiddate,transorderid,checknum)
              values (?,?,?,?,?,?,?,?,?,?,?)
              }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_insert->execute( "$busername", "$borderid", "$btrans_date", "$bamount", "$bcard_type", "$bdescr", "$bcommission", "$bpaidamount", "$bpaiddate", "$btransorderid", "$bchecknum" )
        or die "Can't execute: $DBI::errstr";
      $sth_insert->finish;
    }
    $sth_status->finish;

    my $sth_status = $dbh->prepare(
      qq{
          update billingstatus
          set result='success'
          where orderid='$orderid'
          and result='hold'
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_status->execute or die "Can't execute: $DBI::errstr";
    $sth_status->finish;

    my $sth_status = $dbh->prepare(
      qq{
          select orderid from pending 
          where transorderid='$orderid'
          and status='locked' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_status->execute or die "Can't execute: $DBI::errstr";
    $sth_status->bind_columns( undef, \($oid) );

    while ( $sth_status->fetch ) {
      my $sth_upd = $dbh->prepare(
        qq{
            update quickbooks 
            set result='success',trans_date='$today'
            where orderid='$orderid'
            and result='pending' 
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_upd->execute or die "Can't execute: $DBI::errstr";
      $sth_upd->finish;
    }
    $sth_status->finish;

    $sth_status = $dbh->prepare(
      qq{
          delete from pending 
          where transorderid='$orderid'
          and status='locked' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_status->execute or die "Can't execute: $DBI::errstr";
    $sth_status->finish;

    #$updstatus = "success";
  }
}

sub processreturn {
  my ( $username, $orderid, $operation, $card_name, $rcode, $filedate ) = @_;

  $descr = "$rcode: " . $returncodes{"$rcode"};
  $descr =~ s/'//g;

  %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

  $sth_email = $dbh->prepare(
    qq{
        select emailflag from citynat
        where username='$username'
        }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_email->execute or die "Can't execute: $DBI::errstr";
  ($sendemailflag) = $sth_email->fetchrow;
  $sth_email->finish;

  #and trans_date>='$threemonthsago'
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

  #and trans_date>='$threemonthsago'
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
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/citynat/chk$username.txt" );
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

  #and trans_date>='$threemonthsago'
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

  #if ($chkorderid eq "") {
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

  #}

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  #and lastoptime>='$threemonthsagotime'
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
        select reseller,merchemail from customers
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
    print MAIL "Subject: $privatelabelcompany - citynat Order $username $orderid failed\n";
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

  if ( $username =~ /^(pnpcitynat|ach2)/ ) {
    print "$username $orderid $batchid $twomonthsago $descr<br>\n";
    $sth_sel = $dbh->prepare(
      qq{
          select username,card_type from billingstatus
          where orderid='$orderid' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_sel->execute or die "Can't execute: $DBI::errstr";
    ( $merchant, $chkcard_type ) = $sth_sel->fetchrow;
    $sth_sel->finish;
    print "cccc$merchant $orderid $chkcard_type<br>\n";

    if ( $chkcard_type eq "reseller" ) {
      $sth_sel2 = $dbh->prepare(
        qq{
            select reseller from customers
            where username='$merchant'
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_sel2->execute or die "Can't execute: $DBI::errstr";
      ($merchant) = $sth_sel2->fetchrow;
      $sth_sel2->finish;
    } else {
      my $sth_pend = $dbh->prepare(
        qq{ 
            update pending
            set card_type='check'
            where username='$merchant'
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_pend->execute or die "Can't execute: $DBI::errstr";
      $sth_pend->finish;

      my $sth_cust = $dbh->prepare(
        qq{
            update customers 
            set accttype='check' 
            where username='$merchant' 
            }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_cust->execute or die "Can't execute: $DBI::errstr";
      $sth_cust->finish;
    }

    my $sth_cust = $dbh->prepare(
      qq{
          select email,reseller,company
          from customers 
          where username='$merchant' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_cust->execute or die "Can't execute: $DBI::errstr";
    ( $email, $reseller, $company ) = $sth_cust->fetchrow;
    $sth_cust->finish;

    $sth_pl = $dbh->prepare(
      qq{
            select company,email
            from privatelabel
            where username='$reseller'
            }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_pl->execute or die "Can't execute: $DBI::errstr";
    ( $plcompany, $plemail ) = $sth_pl->fetchrow;
    $sth_pl->finish;

    if ( $plcompany ne "" ) {
      $privatelabelflag    = 1;
      $privatelabelcompany = $plcompany;
      $privatelabelemail   = $plemail;
    } else {
      $privatelabelflag    = 0;
      $privatelabelcompany = "Plug & Pay Technologies, Inc.";
      $privatelabelemail   = "accounting\@plugnpay.com";
    }

    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: $email\n";
    print MAIL "Bcc: cprice\@plugnpay.com,accounting\@plugnpay.com,michelle\@plugnpay.com\n";
    print MAIL "From: $privatelabelemail\n";
    print MAIL "Subject: Monthly Billing - $privatelabelcompany - $username\n";
    print MAIL "\n";
    print MAIL "$company\n";
    print MAIL "$orderid\n\n";

    print MAIL "The attempt to bill your checking account for your monthly gateway fee has failed.\n";
    print MAIL "There is a returned check fee of \$20.00 in addition to your monthly gateway fee.\n";
    print MAIL "If payment is not received by the end of the month then your account will be closed.\n";
    print MAIL "Once your account is closed it cannot be reopened until we have received payment.\n\n";

    print MAIL "To remit payment by check:\n";
    print MAIL "Please include your username in the memo area of your check.\n";
    print MAIL "Send check payment to:\n";
    print MAIL "Plug \& Pay Technologies, Inc.\n";
    print MAIL "1019 Ft. Salonga Rd. ste 10\n";
    print MAIL "Northport, NY 11768\n";

    print MAIL "To pay  by credit card:\n";
    print MAIL "Complete the Billing Authorization form located in your administration area.\n";
    print MAIL "Click on the link labeled Billing Authorization.\n";
    print MAIL "Print, complete the credit card section, sign and fax to the number on the form.\n\n";

    print MAIL "Contact 800-945-2538 if you have any questions.\n";

    #print MAIL "The attempt to bill your checking account failed. There is a returned check\n";
    #print MAIL "fee of \$20.00. If payment is not received by the end of the month then your\n";
    #print MAIL "account will be closed. Once your account is closed it cannot be reopened\n";
    #print MAIL "until we have received payment. When mailing a check please include your\n";
    #print MAIL "username in the memo area of your check.\n\n";
    #print MAIL "Contact 1-800-945-2538 if you have any questions or wish to arrange payment.\n\n";

    #if ($plcompany eq "") {
    #  print MAIL "Billing Address:\n";
    #  print MAIL "Plug \& Pay Technologies, Inc.\n";
    #  print MAIL "1363\-26 Veterans Hwy\n";
    #  print MAIL "Hauppauge, NY  11788\n";
    #  print MAIL "1\-800\-945\-2538\n\n";
    #}

    close(MAIL);

    #where username='$merchant'
    #and transorderid='$orderid'
    my $sth_pend = $dbh->prepare(
      qq{ 
          update pending 
          set status=''  
          where transorderid='$orderid' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_pend->execute or die "Can't execute: $DBI::errstr";
    $sth_pend->finish;

    # xxxx 08/11/2004  and result='success' added
    my $sth_statusa = $dbh->prepare(
      qq{
          select username,orderid,amount,card_type,descr,paidamount,transorderid
          from billingstatus
          where orderid='$orderid'
          and result='success'
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_statusa->execute or die "Can't execute: $DBI::errstr";
    $sth_statusa->bind_columns( undef, \( $busername, $borderid, $bamount, $bcard_type, $bdescr, $chkpaidamount, $btransorderid ) );

    while ( $sth_statusa->fetch ) {
      if ( $chkpaidamount ne "" ) {
        $sth_status3 = $dbh->prepare(
          qq{
            insert into billingreport
            (username,orderid,trans_date,amount,card_type,descr,paidamount,transorderid)
            values (?,?,?,?,?,?,?,?)
            }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_status3->execute( "$busername", "$borderid", "$today", "-$bamount", "$bcard_type", "$bdescr problem", "-$chkpaidamount", "$btransorderid" )
          or die "Can't execute: $DBI::errstr";
        $sth_status3->finish;
      } else {
        $sth_status3 = $dbh->prepare(
          qq{
            insert into billingreport
            (username,orderid,trans_date,amount,card_type,descr,transorderid)
            values (?,?,?,?,?,?,?)
            }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_status3->execute( "$busername", "$borderid", "$today", "-$bamount", "$bcard_type", "$bdescr problem", "$btransorderid" )
          or die "Can't execute: $DBI::errstr";
        $sth_status3->finish;
      }
    }
    $sth_statusa->finish;

    $sth_status = $dbh->prepare(
      qq{
          update billingstatus  
          set result='badcard' 
          where orderid='$orderid' 
          }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_status->execute or die "Can't execute: $DBI::errstr";
    $sth_status->finish;

    $errortype = "Return Fee: $descr";
    $fee       = "20.00";
    $type      = "check";

    $sthchk = $dbh->prepare(
      qq{
            select orderid
            from pending
            where username='$merchant'
            and orderid='$orderid'
            and descr like 'Return Fee%'
            }
      )
      or die "Can't prepare: $DBI::errstr";
    $sthchk->execute or die "Can't execute: $DBI::errstr";
    ($chkorderid) = $sthchk->fetchrow;
    $sthchk->finish;

    if ( $chkorderid eq "" ) {
      $sth_status = $dbh->prepare(
        qq{
              insert into pending 
              (orderid,username,amount,descr,trans_date,card_type)
              values (?,?,?,?,?,?) 
              }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_status->execute( "$orderid", "$merchant", "$fee", "$errortype", "$today", "$type" ) or die "Can't execute: $DBI::errstr";
      $sth_status->finish;
    }
  } else {

    $sth_tl = $dbh2->prepare(
      qq{
            select acct_code3
            from trans_log 
            where orderid='$orderid'
            and operation='auth' 
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
  }

}

sub checkdir {
  my ($date) = @_;

  #print "checking $date\n";

  $fileyear = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 );
  $filemonth = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 );
  $fileyearonly = substr( $date, 0, 4 );

  if ( !-e "/home/p/pay1/batchfiles/$devprod/citynat/$fileyearonly" ) {
    print "creating $fileyearonly\n";
    system("mkdir /home/p/pay1/batchfiles/$devprod/citynat/$fileyearonly");
    chmod( 0700, "/home/p/pay1/batchfiles/$devprod/citynat/$fileyearonly" );
  }
  if ( !-e "/home/p/pay1/batchfiles/$devprod/citynat/$filemonth" ) {
    print "creating $filemonth\n";
    system("mkdir /home/p/pay1/batchfiles/$devprod/citynat/$filemonth");
    chmod( 0700, "mkdir /home/p/pay1/batchfiles/$devprod/citynat/$filemonth" );
  }
  if ( !-e "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear" ) {
    print "creating $fileyear\n";
    system("mkdir /home/p/pay1/batchfiles/$devprod/citynat/$fileyear");
    chmod( 0700, "mkdir /home/p/pay1/batchfiles/$devprod/citynat/$fileyear" );
  }
  if ( !-e "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear" ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: citynat - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Couldn't create directory logs/citynat/$fileyear.\n\n";
    close MAILERR;
    exit;
  }

}

