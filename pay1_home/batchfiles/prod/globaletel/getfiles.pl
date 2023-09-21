#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};

#use Net::FTP;
use miscutils;
use procutils;
use rsautils;
use SHA;

#use Net::FTPSSL;
use Net::SFTP::Foreign;

$devprod = "logs";

#$ftpaddr = "ftp.eftchecks.com";   # production server
$ftpaddr = "SFTP.eftchecks.com";    # production server

#$redofile = "PlugNPay_Merchant_Change_Report_04-21-2017.csv";
#$redofile = "PlugNPay_Merchant_Change_Report_04-30-2015.csv";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );

( $d1, $today, $todaytime ) = &miscutils::genorderid();
$ttime = &miscutils::strtotime($today);

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 44 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 4 ) );
$fourdaysago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 7 ) );
$sevendaysago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 10 ) );
$tendaysago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 90 * 6 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$twomonthsagotime = $twomonthsago . "000000";

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 90 * 6 ) );
$threemonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

my $printstr = "\n\n\n";
&procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

if ( !-e "/home/pay1/batchfiles/$devprod/globaletel/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/globaletel/$fileyearonly");
  system("chmod go-rwx /home/pay1/batchfiles/$devprod/globaletel/$fileyearonly");
}
if ( !-e "/home/pay1/batchfiles/$devprod/globaletel/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/globaletel/$filemonth");
  system("chmod go-rwx /home/pay1/batchfiles/$devprod/globaletel/$filemonth");
}
if ( !-e "/home/pay1/batchfiles/$devprod/globaletel/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/globaletel/$fileyear");
  system("chmod go-rwx /home/pay1/batchfiles/$devprod/globaletel/$fileyear");
}
if ( !-e "/home/pay1/batchfiles/$devprod/globaletel/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: globaletel - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/globaletel/$fileyear.\n\n";
  close MAILERR;
  exit;
}

%returncodes = (
  "R01", "Insufficient Funds",                               "R02", "Account Closed",
  "R03", "No Account",                                       "R04", "Invalid Account Number",
  "R06", "Returned per ODFIs Request",                       "R07", "Authorization Revoked by Customer",
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

$batchfile = substr( $redofile, 4, 14 );

my $printstr = "redofile: $redofile\n";
&procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

if ( $redofile ne "" ) {
  $fileyear = substr( $redofile, -8, 4 ) . "/" . substr( $redofile, -14, 2 ) . "/" . substr( $redofile, -11, 2 );
  my $printstr = "fileyear: $fileyear\n";
  $printstr .= "/home/pay1/batchfiles/$devprod/globaletel/$fileyear/$redofile\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  if ( -e "/home/pay1/batchfiles/$devprod/globaletel/$fileyear/$redofile" ) {
    my $printstr = "redofile exists already, exiting\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );
    &processfile($redofile);

    #&processsuccesses();

    exit;
  }
}

my $ftpun = 'PlugNPay';
my $ftppw = 'rpj1PX2cc9$eR';

#$ftp = Net::FTP->new("$ftpaddr", 'Timeout' => 2400, 'Debug' => 1, 'Port' => "21");
#$ftp = Net::FTPSSL->new("$ftpaddr", Port => 21, Encryption => EXP_CRYPT, Debug => 1);
$ftp = Net::SFTP::Foreign->new( 'host' => "$ftpaddr", 'user' => $ftpun, 'password' => $ftppw, 'port' => 22, 'timeout' => 30 );
$ftp->error and die "cannot connect: " . $ftp->error;

if ( $ftp eq "" ) {
  my $printstr = "Host $host is no good<br>\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  #$ftp = Net::FTP->new("$ftpaddr", 'Timeout' => 2400, 'Debug' => 1, 'Port' => "21");
  $ftp = Net::FTPSSL->new( "$ftpaddr", Port => 21, Encryption => EXP_CRYPT, Debug => 1 );
  if ( $ftp eq "" ) {
    exit;
  }
}

#if ($ftp->login("$ftpun","$ftppw") eq "") {
#  print "Username $ftpun and password don't work<br>\n";
#  print "failure";
#  exit;
#}

my $printstr = "logged in\n";
&procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

if ( $redofile ne "" ) {
  $fileyear = substr( $redofile, -8, 4 ) . "/" . substr( $redofile, -14, 2 ) . "/" . substr( $redofile, -11, 2 );
  $fileyymmdd = substr( $redofile, -8, 4 ) . substr( $redofile, -14, 2 ) . substr( $redofile, -11, 2 );

  #$ftp->cwd("Done");
  #my @temparray = $ftp->ls("*");
  #my @temparray = $ftp->nlst("*");
  #foreach $var (@temparray) {
  #  print "aaaa $var\n";
  #}

  my $ls = $ftp->ls("*");
  foreach my $var (@$ls) {
    $fn = $var->{"filename"};

    my $printstr = "aaaa $var\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );
  }

  &checkdir($fileyymmdd);

  if ( !-e "/home/pay1/batchfiles/$devprod/globaletel/$fileyear/$redofile.out" ) {

    #$ftp->get("/Outgoing/$redofile","/home/pay1/batchfiles/$devprod/globaletel/$fileyear/$redofile");
    my $outboxfilestr = $ftp->get_content("Outgoing/$redofile");

    my $printstr = "status: " . $ftp->status . "\n";
    if ( $ftp->error ) {
      $printstr = "error: " . $ftp->error . "\n";
    }
    $printstr .= "\n";
    &procutils::filewrite( "globaletel", "getfile", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

    my $fileencstatus = &procutils::fileencwrite( "globaletel", "getfiles", "/home/pay1/batchfiles/$devprod/globaletel/$fileyear", "$redofile", "write", "", $outboxfilestr );

    my $outfiletxtstr = "fileencwrite $fileyear/$redofile  status: $fileencstatus\n";    # create a basic file so we know the file is stored in enc area
    &procutils::filewrite( "globaletel", "getfiles", "/home/pay1/batchfiles/$devprod/globaletel/$fileyear", "$redofile", "write", "", $outfiletxtstr );

    system("chmod go-rwx /home/pay1/batchfiles/$devprod/globaletel/$fileyear/*");
  }

  &processfile($redofile);

  exit;
}

$ftp->setcwd("Outgoing");

#my @temparray = $ftp->ls();
#my @temparray = $ftp->ls("*");
#my @temparray = $ftp->nlst("*");

my $ls = $ftp->ls("*");
foreach my $var (@$ls) {
  $fn = $var->{"filename"};
  if ( $fn !~ /.csv$/ ) {
    next;
  }

  my $printstr = "bbbb $fn\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  (@temparray) = ( @temparray, $fn );
}

foreach $var (@temparray) {
  my $printstr = "aaaa $var\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  if ( $var !~ /.csv$/ ) {
    next;
  }

  $fileyear = substr( $var, -8, 4 ) . "/" . substr( $var, -14, 2 ) . "/" . substr( $var, -11, 2 );
  $fileyymmdd = substr( $var, -8, 4 ) . substr( $var, -14, 2 ) . substr( $var, -11, 2 );

  #if ($var =~ /...\.20/) {
  #  #$fileyear = substr($var,4,4);
  #  $fileyear = substr($var,4,4) . "/" . substr($var,8,2) . "/" . substr($var,10,2);
  #}
  #else {
  #  #$fileyear = "20" . substr($var,4,2);
  #  $fileyear = "20" . substr($var,4,2) . "/" . substr($var,6,2) . "/" . substr($var,8,2);
  #  $fileyymmdd = "20" . substr($var,4,6);
  #}

  &checkdir($fileyymmdd);

  my $printstr = "fileyymmdd: $fileyymmdd\n";
  $printstr .= "fileyear: $fileyear\n";
  $printstr .= "var: $var\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  if ( ( !-e "/home/pay1/batchfiles/$devprod/globaletel/$fileyear/$var.out" ) && ( !-e "/home/pay1/batchfiles/$devprod/globaletel/$fileyear/$var.txt" ) ) {

    my $printstr = "get $fileyear/$var\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

    #$ftp->get("/Outgoing/$var","/home/pay1/batchfiles/$devprod/globaletel/$fileyear/$var") or die "file transfer failed: " . $ftp->error . "\n";
    #$ftp->get("/Outgoing/$var","/home/pay1/batchfiles/$devprod/globaletel/$fileyear/$var", copy_perm => 0, copy_time => 0) or die "file transfer failed: " . $ftp->error . "\n";
    my $outboxfilestr = $ftp->get_content("Outgoing/$var");

    my $printstr = "status: " . $ftp->status . "\n";
    if ( $ftp->error ) {
      $printstr = "error: " . $ftp->error . "\n";
    }
    $printstr .= "\n";
    &procutils::filewrite( "globaletel", "getfile", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

    my $fileencstatus = &procutils::fileencwrite( "globaletel", "getfiles", "/home/pay1/batchfiles/$devprod/globaletel/$fileyear", "$var", "write", "", $outboxfilestr );

    my $outfiletxtstr = "fileencwrite $fileyear/$var  status: $fileencstatus\n";    # create a basic file so we know the file is stored in enc area
    &procutils::filewrite( "globaletel", "getfiles", "/home/pay1/batchfiles/$devprod/globaletel/$fileyear", "$var", "write", "", $outfiletxtstr );

    system("chmod go-rwx /home/pay1/batchfiles/$devprod/globaletel/$fileyear/*");

    @filenamearray = ( @filenamearray, $var );
  }

  if ( -e "/home/pay1/batchfiles/$devprod/globaletel/$fileyear/$var" ) {
    $ftp->rename( "$var", "$var.done" );
  }

  #    }
  #$d1 = <stdin>;
}

foreach $filename (@filenamearray) {
  &processfile($filename);
}

#&processsuccesses();
#&processfailures();

exit;

sub processfile {
  my ($filename) = @_;

  my $printstr = "in processfile\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  #if ($filename =~ /...\.20/) {
  #$fileyear = substr($filename,4,4);
  $fileyear = substr( $filename, -8, 4 ) . "/" . substr( $filename, -14, 2 ) . "/" . substr( $filename, -11, 2 );
  $fileyearmonthdayhms = substr( $filename, -8, 4 ) . substr( $filename, -14, 2 ) . substr( $filename, -11, 2 ) . "120101";

  #}
  #else {
  #  #$fileyear = "20" . substr($filename,4,2);
  #  $fileyear = "20" . substr($filename,4,2) . "/" . substr($filename,6,2) . "/" . substr($filename,8,2);
  #  $fileyearmonthdayhms = "20" . substr($filename,4,12);
  #}
  #print "$filename\n";
  #print "$fileyearmonthdayhms\n";

  my $printstr = "filename: $filename\n";
  $printstr .= "fileyear: $fileyear\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  $detailflag = 0;
  $batchflag  = 0;
  $fileflag   = 0;
  $returnflag = 0;
  $batchnum   = "";
  my $infilestr = &procutils::fileencread( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel/$fileyear", "$filename" );
  my @infilestrarray = split( /\n/, $infilestr );

  umask 0077;
  $outfile2str = "";
  $outfile3str = "";
  foreach (@infilestrarray) {
    $line = $_;
    chop $line;

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

    my $line2 = $line;
    $line2 =~ s/^((.*?\",\"){8})(.*?\",\".*?\",\")(.*)$/$1xxxxxxxxx\",\"xxxxxx\",\"$4/;
    $outfile3str .= "$line2\n";

    if ( $filename =~ /\.rej$/ ) {
      if ( $line =~ /\",\"/ ) {
        ( $merchantnum, $d1, $date, $tcode, $routenum, $acctnum, $amount, $refnumber, $name, $rcode, $nocinfo ) = split( /","/, $line );
      } else {
        ( $merchantnum, $d1, $date, $tcode, $routenum, $acctnum, $amount, $refnumber, $name, $rcode, $nocinfo ) = split( /,/, $line );
      }
      $returnflag = 1;
      $merchantnum =~ s/"//g;
      $nocinfo =~ s/"//g;
    } elsif ( $filename =~ /\.csv$/ ) {

      #if ($line =~ /\",\"/) {
      ( $date, $d1, $d2, $company, $d16, $checkstatus, $fundingstatus, $refnumber, $routenum, $acctnum, $d5, $amount, $d7, $d8, $name, $d9, $d10, $d11, $orderid, $d12, $d13, $d14, $d15, $rcode, $nocinfo )
        = split( /","/, $line );

      #}
      #else {
      #  ($date,$d1,$d2,$tcode,$routenum,$acctnum,$amount,$refnumber,$name,$rcode,$nocinfo) = split(/,/,$line);
      #}
      $tcode = "";

      #$nocinfo = "";    # don't know where this goes
      $nocinfo =~ s/\"//g;
      $date =~ s/\"//g;
      $date =~ s/^([0-9])\//0$1\//;
      $date =~ s/\/([0-9])\//\/0$1\//;

      if ( $refnumber =~ /^AUTH/ ) {
        $operation = "auth";

        #$refnumber =~ s/AUTH NUM //;
        #$refnumber =~ s/-//;
      } elsif ( ( $checkstatus =~ /Reject/ ) && ( $fundingstatus eq "No Credit" ) ) {
        $operation = "auth";
      } else {
        $operation = "return";

        #$refnumber = "";
      }

      my $printstr = "merchnum: $merchantnum  $username  $orderid  $operation  $rcode  $date  $refnumber\n";
      &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

      $returnflag = 1;
      $merchantnum =~ s/"//g;
      $nocinfo =~ s/"//g;

      $username = "";
      if ( $orderid =~ / / ) {
        ( $username, $orderid ) = split( / /, $orderid );
      }

    } else {
      if ( $line =~ /\",\"/ ) {
        ( $merchantnum, $d1, $d2, $d3, $d4, $d5, $date, $refnumber, $name, $d9, $d10, $tcode ) = split( /","/, $line );
      } else {
        ( $merchantnum, $d1, $d2, $d3, $d4, $d5, $date, $refnumber, $name, $d9, $d10, $tcode ) = split( /,/, $line );
      }
      $returnflag = 0;
      $merchantnum =~ s/"//g;
      $tcode =~ s/"//g;

      my $tmpline = $line;
      my $xs      = "x" x length($d9);
      $tmpline =~ s/$d9/$xs/;

      #my $xs = "x" x length($d10);
      #$tmpline =~ s/$d10/$xs/;
      $outfile2str .= "$tmpline\n";
    }

    $tdate = substr( $date, 6, 4 ) . substr( $date, 0, 2 ) . substr( $date, 3, 2 );

    #$xs = "x" x length($oldcardnumber);
    #$line =~ s/$oldcardnumber/$xs/;
    #$xs = "x" x length($newcardnumber);
    #$line =~ s/$newcardnumber/$xs/;
    #print outfile "$line\n";

    $cardnumber = "$routenum $acctnum";

    #$sha1 = new SHA;
    #$sha1->reset;
    #$sha1->add($cardnumber);
    #$shacardnumber = $sha1->hexdigest();

    my $printstr = "merchnum: $merchantnum  $username  $orderid  $operation  $rcode  $tdate  $refnumber\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

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
      ($encdata) = &rsautils::rsa_encrypt_card( "$exp $cardnumber", '/home/pay1/pwfiles/keys/key', 'log' );
    }

    my $printstr = "orderid: $orderid\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

    #and processor='globaletel'
    if ( $username eq "" ) {
      my $dbquerystr = <<"dbEOM";
              select username,orderid,finalstatus,operation
              from trans_log
              where trans_date>=?
              and orderid=?
              and operation=?
              and accttype in ('checking','savings')
              order by trans_time DESC
dbEOM
      my @dbvalues = ( "$threemonthsago", "$orderid", "$operation" );
      ( $username, $orderid, $status, $operation ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    } else {
      my $dbquerystr = <<"dbEOM";
              select orderid,finalstatus,operation
              from trans_log
              where trans_date>=?
              and username=?
              and orderid=?
              and operation=?
              and accttype in ('checking','savings')
dbEOM
      my @dbvalues = ( "$threemonthsago", "$username", "$orderid", "$operation" );
      ( $orderid, $status, $operation ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    }

    if ( $returnflag != 1 ) {

      #if ($orderid ne "") {
      #  my $sthupd = $dbh->prepare(qq{
      #      update batchfilespdata
      #      set status='locked1'
      #      where trans_date>='$threemonthsago'
      #      and orderid='$orderid'
      #      and username='$username'
      #      and status='locked'
      #      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      #  $sthupd->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      #  $sthupd->finish;
      #}
      next;
    }

    $outfile2str .= "$username $orderid $operation $status $amount $refnumber $checkstatus $rcode\n";

    #if ($orderid eq "") {
    #
    #        my $sth_res2 = $dbh->prepare(qq{
    #              select username
    #              from globaletel
    #              where merchantnum='$merchantnum'
    #              }) or die "Can't do: $DBI::errstr";
    #        $sth_res2->execute or die "Can't execute: $DBI::errstr";
    #        ($username) = $sth_res2->fetchrow;
    #        $sth_res2->finish;

    #        my $sth_res2 = $dbh2->prepare(qq{
    #              select orderid,operation
    #              from trans_log
    #              where trans_date>='$twomonthsago'
    #              and username='$username'
    #              and refnumber='$refnumber'
    #              and accttype in ('checking','savings')
    #              }) or die "Can't do: $DBI::errstr";
    #        $sth_res2->execute or die "Can't execute: $DBI::errstr";
    #        ($orderid,$operation) = $sth_res2->fetchrow;
    #        $sth_res2->finish;
    #      }

    #if (($filename =~ /\.rej$/) && ($rcode eq "")) {
    #}

    if ( $rcode =~ /^C/ ) {
      my $printstr = "processnoc\n";
      &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );
      &processnoc( "$username", "$orderid", "$operation", "$name", "$rcode", "$nocinfo" );
    } elsif ( ( $rcode =~ /^(R|X)/ ) || ( $checkstatus =~ /^(Cancelled|Rejected)/ ) || ( $fundingstatus =~ /^(Cancelled|Returned|Chargeback|No Credit)/ ) ) {
      my $printstr = "processreturn\n";
      &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

      if ( $rcode eq "" ) {
        $rcode = "$checkstatus, $fundingstatus";
      }

      $outfile2str .= "$username $orderid $operation $name $status $amount $refnumber $rcode $nocinfo\n";
      &processreturn( "$username", "$orderid", "$operation", "$name", "$rcode", "$fileyearmonthdayhms", "$nocinfo" );
    } elsif ( $refnumber =~ /AUTH|ACCEPTED/ ) {

      # successful transaction
    } else {
      my $printstr = "sendemail\n";
      &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );
      open( MAILERR, "| /usr/lib/sendmail -t" );
      print MAILERR "To: cprice\@plugnpay.com\n";
      print MAILERR "From: dcprice\@plugnpay.com\n";
      print MAILERR "Subject: globaletel - getfiles.pl - FAILURE\n";
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

    if ( $orderid eq "" ) {
      open( MAIL, "| /usr/lib/sendmail -t" );
      print MAIL "To: cprice\@plugnpay.com\n";
      print MAIL "From: dcprice\@plugnpay.com\n";
      print MAIL "Subject: globaletel - bad file\n";
      print MAIL "\n";
      print MAIL "File has a non-existent orderid.\n";
      print MAIL "file: $file\n";
      print MAIL "twomonthsago: $twomonthsago\n";
      print MAIL "usernames: $usernames\n";
      print MAIL "transid: $transid\n";
      print MAILERR "filename: $filename\n\n";
      print MAILERR "merchantnum: $merchantnum\n\n";
      print MAILERR "refnumber: $refnumber\n\n";
      close(MAIL);
    }
  }

  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel/$fileyear", "$filename.txt", "write", "", $outfile2str );
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel/$fileyear", "$filename.out", "write", "", $outfile3str );

  #unlink "/home/pay1/batchfiles/$devprod/globaletel/$fileyear/$filename";
}

exit;

sub processsuccesses {
  my $sevendays = $sevendaysago;
  if ( $username eq "pnpdata" ) {
    $sevendays = $tendaysago;
  }

  my $dbquerystr = <<"dbEOM";
        select username,orderid,operation
        from batchfilespdata
        where trans_date>=?
        and trans_date<=?
        and status='locked1'
dbEOM
  my @dbvalues = ( "$threemonthsago", "$sevendays" );
  my @sthbatchvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchcnt = 0;
  for ( my $vali = 0 ; $vali < scalar(@sthbatchvalarray) ; $vali = $vali + 3 ) {
    ( $username, $orderid, $operation ) = @sthbatchvalarray[ $vali .. $vali + 2 ];

    &processsuccess( $username, $orderid, $operation );

    my $dbquerystr = <<"dbEOM";
        update batchfilespdata
        set status='done'
        where trans_date>=?
        and orderid=?
        and username=?
        and operation=?
        and status='locked1'
dbEOM
    my @dbvalues = ( "$threemonthsago", "$orderid", "$username", "$operation" );
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  }

}

sub processfailures {
  my $dbquerystr = <<"dbEOM";
        select username,orderid,operation
        from batchfilespdata
        where trans_date>=?
        and trans_date<=?
        and status='locked'
dbEOM
  my @dbvalues = ( "$threemonthsago", "$fourdaysago" );
  my @sthbatchvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my @failurearray = ();
  my $mycount      = 0;
  for ( my $vali = 0 ; $vali < scalar(@sthbatchvalarray) ; $vali = $vali + 3 ) {
    ( $username, $orderid, $operation ) = @sthbatchvalarray[ $vali .. $vali + 2 ];

    my $dbquerystr = <<"dbEOM";
            select lastopstatus
            from operation_log 
            where orderid=?
dbEOM
    my @dbvalues = ("$orderid");
    ($chkfinalstatus) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $chkfinalstatus eq "locked" ) {
      $failurearray[ ++$#failurearray ] = "$username $orderid $operation";
      $mycount++;
    } elsif ( $chkfinalstatus =~ /^(success|badcard|problem)$/ ) {
      my $dbquerystr = <<"dbEOM";
            update batchfilespdata
            set status='done'
            where trans_date>=?
            and orderid=?
            and username=?
            and status='locked'
            and operation=?
dbEOM
      my @dbvalues = ( "$threemonthsago", "$orderid", "$username", "$operation" );
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    }
  }

  if ( $mycount > 0 ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: globaletel - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "The following orders did not receive a pending file from globaletel:\n";
    foreach my $var (@failurearray) {
      print MAILERR "$var\n";
    }
    close(MAILERR);
  }
}

sub processnoc {
  my ( $username, $orderid, $operation, $name, $noccode, $nocinfo ) = @_;

  $nocdesc = $returncodes{"$noccode"};

  my $printstr = "";
  $printstr .= "username: $username\n";
  $printstr .= "orderid: $orderid\n";

  #$printstr .= "oldroute: $oldroute\n";
  #$printstr .= "oldacct: $oldacct\n";
  $printstr .= "noccode: $noccode\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  umask 0077;
  $outfilestr .= "\nfile: $file\n";
  $outfilestr .= "usernames: $usernames\n";
  $outfilestr .= "username: $username\n";
  $outfilestr .= "orderid: $orderid\n";
  $outfilestr .= "descr: $noccode: $nocdesc\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel/returns", "$today" . "summary.txt", "append", "", $outfilestr );

  $newacct = "";
  $newrout = "";
  if ( $noccode eq "C01" ) {

    #$nocinfo = substr($line2,44,17);
    $newacct = $nocinfo;
    $newacct =~ s/ //g;
  } elsif ( $noccode eq "C02" ) {

    #$nocinfo = substr($line2,44,9);
    $newrout = $nocinfo;
    $newrout =~ s/ //g;
  } elsif ( $noccode eq "C03" ) {

    #$nocinfo = substr($line2,44,29);
    ( $newrout, $newacct ) = split( /\s+/, $nocinfo );
    $newacct =~ s/ //g;
  } elsif ( $noccode eq "C06" ) {

    # must use savings as the account type
    #$nocinfo = substr($line2,44,29);
    #($newacct,$newaccttype) = split(/   /,$nocinfo);
    #$newacct =~ s/ //g;
  } else {

    #$nocinfo = substr($line2,44,42);
  }

  $pnpcompany = "Plug and Pay";
  $pnpemail   = "accounting\@plugnpay.com";

  my $dbquerystr = <<"dbEOM";
        select reseller,merchemail from customers
        where username=? 
dbEOM
  my @dbvalues = ("$username");
  ( $reseller, $email ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $descr = "New Route Number: $newrout New Account Number: $newacct";
  if ( $newaccttype eq "37" ) {
    $descr = $descr . " Must use savings";
  }
  $error = "$noccode: $nocdesc";

  %datainfo = ( "username", "$username", "today", "$today", "orderid", "$orderid", "name", "$name", "descr", "$descr", "error", "$error" );

  my $dbquerystr = <<"dbEOM";
        select orderid from achnoc
        where orderid=?
        and username=?
        and error like ?
dbEOM
  my @dbvalues = ( "$orderid", "$username", "$noccode\%" );
  ($chkorderid) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $chkorderid eq "" ) {
    my $dbquerystr = <<"dbEOM";
          insert into achnoc 
          (username,trans_date,orderid,name,descr,error)
          values (?,?,?,?,?,?) 
dbEOM

    my %inserthash = ( "username", "$username", "trans_date", "$today", "orderid", "$orderid", "name", "$name", "descr", "$descr", "error", "$error" );
    &procutils::dbinsert( $username, $orderid, "pnpmisc", "achnoc", %inserthash );

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
  my $printstr = "cccc $orderid $twomonthsago $twomonthsagotime $username $operation\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";

  my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='success'
          where orderid=?
          and trans_date>=?
          and username=?
          and operation=?
          and finalstatus in ('pending','locked')
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$orderid", "$twomonthsago", "$username", "$operation" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );
  my $dbquerystr = <<"dbEOM";
          update operation_log set $operationstatus='success',lastopstatus='success'
          where orderid=?
          and lastoptime>=?
          and username=?
          and lastop=?
          and $operationstatus in ('pending','locked')
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$orderid", "$twomonthsagotime", "$username", "$operation" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  if ( $username =~ /^(pnppdata|ach2)/ ) {
    my $printstr = "aaaa\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

    my $dbquerystr = <<"dbEOM";
          select username,orderid,trans_date,amount,card_type,descr,commission,paidamount,paiddate,transorderid,checknum
          from billingstatus
          where orderid=?
          and result='hold'
dbEOM
    my @dbvalues = ("$orderid");
    my @sth_statusvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    for ( my $vali = 0 ; $vali < scalar(@sth_statusvalarray) ; $vali = $vali + 11 ) {
      ( $busername, $borderid, $btrans_date, $bamount, $bcard_type, $bdescr, $bcommission, $bpaidamount, $bpaiddate, $btransorderid, $bchecknum ) = @sth_statusvalarray[ $vali .. $vali + 10 ];

      my $printstr = "billing username: $busername $borderid\n";
      &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );
      my $dbquerystr = <<"dbEOM";
              insert into billingreport
              (username,orderid,trans_date,amount,card_type,descr,commission,paidamount,paiddate,transorderid,checknum)
              values (?,?,?,?,?,?,?,?,?,?,?)
dbEOM

      my %inserthash = (
        "username",  "$busername",  "orderid",      "$borderid",      "trans_date", "$btrans_date", "amount",     "$bamount",
        "card_type", "$bcard_type", "descr",        "$bdescr",        "commission", "$bcommission", "paidamount", "$bpaidamount",
        "paiddate",  "$bpaiddate",  "transorderid", "$btransorderid", "checknum",   "$bchecknum"
      );
      &procutils::dbinsert( $username, $orderid, "pnpmisc", "billingreport", %inserthash );

    }

    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime update billingstatus set result='success' where orderid=? and result='hold'\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "achlog.txt", "append", "", $achfilestr );
    my $printstr = " ";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

    my $dbquerystr = <<"dbEOM";
          update billingstatus
          set result='success'
          where orderid=?
          and result='hold'
dbEOM
    my @dbvalues = ("$orderid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    my $dbquerystr = <<"dbEOM";
          select orderid from pending 
          where transorderid=?
          and status='locked' 
dbEOM
    my @dbvalues = ("$orderid");
    my @sth_statusvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    for ( my $vali = 0 ; $vali < scalar(@sth_statusvalarray) ; $vali = $vali + 1 ) {
      ($oid) = @sth_statusvalarray[ $vali .. $vali + 0 ];

      my $dbquerystr = <<"dbEOM";
            update quickbooks 
            set result='success',trans_date=?
            where orderid=?
            and result='pending' 
dbEOM
      my @dbvalues = ( "$today", "$orderid" );
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    }

    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime delete from pending where transorderid='$orderid' and status='locked'\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "achlog.txt", "append", "", $achfilestr );

    my $dbquerystr = <<"dbEOM";
          delete from pending 
          where transorderid=?
          and status='locked' 
dbEOM
    my @dbvalues = ("$orderid");
    &procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    #$updstatus = "success";
  }
}

sub processreturn {
  my ( $username, $orderid, $operation, $card_name, $rcode, $yearmonthdayhms, $descr ) = @_;

  if ( ( length($rcode) == 3 ) && ( $descr ne "" ) ) {
    $descr = "$rcode: " . $descr;
  } elsif ( $descr ne "" ) {
    $descr = $descr;
  } elsif ( $rcode =~ /^X/ ) {
    $descr = "$rcode: " . $descr;
  } elsif ( length($rcode) == 3 ) {
    $descr = "$rcode: " . $returncodes{"$rcode"};
  } else {
    $descr = $rcode;
  }

  my $printstr = "processreturn $username $orderid $rcode $descr\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  %datainfo = ( "orderid", "$orderid", "username", "$username", "operation", "$operation", "descr", "$descr" );

  my $dbquerystr = <<"dbEOM";
          select lastop,lastopstatus,descr
          from operation_log
          where orderid=?
          and trans_date>=?
          and username=?
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$orderid", "$twomonthsago", "$username" );
  ( $chklastop, $chklastopstatus, $chkdescr ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  if ( ( $chklastop eq "void" ) && ( $chklastopstatus eq "success" ) && ( $chkdescr =~ /A: VOID ACCEPTED/ ) ) {
    return;
  }

  my $dbquerystr = <<"dbEOM";
          select orderid
          from trans_log
          where orderid=?
          and trans_date>=?
          and username=?
          and descr=?
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$orderid", "$twomonthsago", "$username", "$descr" );
  ($chkorderid) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $emailflag = 1;
  if ( $chkorderid ne "" ) {
    $emailflag = 0;
  }

  my $dbquerystr = <<"dbEOM";
          select card_name,acct_code,acct_code2,acct_code3,amount,accttype,result
          from trans_log
          where orderid=?
          and username=?
          and trans_date>=?
          and operation=?
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$orderid", "$username", "$twomonthsago", "$operation" );
  ( $card_name, $acct_code1, $acct_code2, $acct_code3, $amount, $accttype, $batchid ) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  #and processor='globaletel'

  my $printstr = "twomonthsago: $twomonthsago\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  my $dbquerystr = <<"dbEOM";
          update trans_log set finalstatus='badcard',descr=?
          where orderid=?
          and trans_date>=?
          and username=?
          and operation=?
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$descr", "$orderid", "$twomonthsago", "$username", "$operation" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  my $price = $amount;
  if ( $operation ne "return" ) {
    ( $curr, $price ) = split( / /, $amount );
    $price = $curr . " -" . $price;
  }

  my $tdate = substr( $yearmonthdayhms, 0, 8 );
  my $printstr = "$username $orderid $tdate $yearmonthdayhms $todaytime $descr $price $accttype $card_name $batchid\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  my $dbquerystr = <<"dbEOM";
          insert into trans_log
          (username,orderid,operation,trans_date,trans_time,batch_time,descr,amount,accttype,card_name,result)
          values (?,?,?,?,?,?,?,?,?,?,?)
dbEOM

  my %inserthash = (
    "username",   "$username",        "orderid",    "$orderid",   "operation", "chargeback", "trans_date", "$tdate",
    "trans_time", "$yearmonthdayhms", "batch_time", "$todaytime", "descr",     "$descr",     "amount",     "$price",
    "accttype",   "$accttype",        "card_name",  "$card_name", "result",    "$batchid"
  );
  &procutils::dbinsert( $username, $orderid, "pnpdata", "trans_log", %inserthash );

  $operationstatus = $operation . "status";
  $operationtime   = $operation . "time";
  my $dbquerystr = <<"dbEOM";
          update operation_log set lastopstatus='badcard',$operationstatus='badcard',descr=?
          where orderid=?
          and lastoptime>=?
          and username=?
          and accttype in ('checking','savings')
dbEOM
  my @dbvalues = ( "$descr", "$orderid", "$twomonthsagotime", "$username" );
  &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  $pnpcompany = "Plug and Pay";
  $pnpemail   = "accounting\@plugnpay.com";

  my $dbquerystr = <<"dbEOM";
        select reseller,merchemail from customers
        where username=?
dbEOM
  my @dbvalues = ("$username");
  ( $reseller, $email ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $plcompany{$reseller} ne "" ) {
    $privatelabelflag    = 1;
    $privatelabelcompany = $plcompany{$reseller};
    $privatelabelemail   = $plemail{$reseller};
  } else {
    $privatelabelflag    = 0;
    $privatelabelcompany = $pnpcompany;
    $privatelabelemail   = $pnpemail;
  }

  my $dbquerystr = <<"dbEOM";
          select acct_code3
          from trans_log
          where orderid=?
          and username=?
          and operation='postauth'
dbEOM
  my @dbvalues = ( "$orderid", "$username" );
  ($acct_code3) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  if ( $acct_code3 eq "recurring" ) {

    my $dbquerystr = <<"dbEOM";
          select username,orderid
          from billingstatus
          where orderid=?
dbEOM
    my @dbvalues = ("$orderid");
    ( $chkusername, $chkorderid ) = &procutils::dbread( $username, $orderid, "$username", $dbquerystr, @dbvalues );

    if ( $chkorderid ne "" ) {
      my $dbquerystr = <<"dbEOM";
          insert into billingstatus
          (username,trans_date,amount,orderid,descr)
          values (?,?,?,?,?)
dbEOM

      my %inserthash = ( "username", "$chkusername", "trans_date", "$today", "amount", "-$amount", "orderid", "$orderid", "descr", "$descr" );
      &procutils::dbinsert( $username, $orderid, "$username", "billingstatus", %inserthash );

    }

  }

  my $printstr = "privatelabelcompany: $privatelabelcompany\n";
  $printstr .= "email: $email\n";
  $printstr .= "orderid: $orderid\n";
  $printstr .= "reason: $descr\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  if ( $emailflag == 1 ) {
    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: $email\n";
    print MAIL "Bcc: cprice\@plugnpay.com\n";
    print MAIL "Bcc: michelle\@plugnpay.com\n";
    print MAIL "From: $privatelabelemail\n";
    print MAIL "Subject: $privatelabelcompany - globaletel Order $username $orderid failed\n";
    print MAIL "\n";
    print MAIL "$username\n\n";
    print MAIL "We would like to inform you that order $orderid received a Return notice\n";
    print MAIL "today.\n\n";
    print MAIL "Orderid: $orderid\n\n";
    print MAIL "Card Name: $card_name\n\n";
    print MAIL "Amount: $amount\n\n";

    if ( $authtime1 ne "" ) {
      $authdate = substr( $authtime1, 4, 2 ) . "/" . substr( $authtime1, 6, 2 ) . "/" . substr( $authtime1, 0, 4 );
      print MAIL "Auth Date: $authdate\n";
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

  if ( $username =~ /^(pnppdata|ach2)/ ) {
    my $printstr = "$username $orderid $batchid $twomonthsago $descr<br>\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );
    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime select username from billingstatus where orderid=?\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "achlog.txt", "append", "", $achfilestr );
    my $dbquerystr = <<"dbEOM";
          select username,card_type from billingstatus
          where orderid=? 
dbEOM
    my @dbvalues = ("$orderid");
    ( $merchant, $chkcard_type ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    my $printstr = "cccc$merchant $orderid $chkcard_type<br>\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

    if ( $chkcard_type eq "reseller" ) {
      my $dbquerystr = <<"dbEOM";
            select reseller from customers
            where username=?
dbEOM
      my @dbvalues = ("$merchant");
      ($merchant) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    } else {
      $achfilestr = "";
      $achfilestr .= "$remoteuser $todaytime update pending set card_type='check' where username='$merchant'\n";
      &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "achlog.txt", "append", "", $achfilestr );
      my $dbquerystr = <<"dbEOM";
            update pending
            set card_type='check'
            where username=?
dbEOM
      my @dbvalues = ("$merchant");
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      $achfilestr = "";
      $achfilestr .= "$remoteuser $todaytime update customers set accttype='check' where username='$merchant'\n";
      &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "achlog.txt", "append", "", $achfilestr );
      my $dbquerystr = <<"dbEOM";
            update customers 
            set accttype='check' 
            where username=? 
dbEOM
      my @dbvalues = ("$merchant");
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    }

    # yyyy

    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime select merchemail,reseller,company from customers where username='$merchant'\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "achlog.txt", "append", "", $achfilestr );
    my $dbquerystr = <<"dbEOM";
          select email,reseller,company
          from customers 
          where username=? 
dbEOM
    my @dbvalues = ("$merchant");
    ( $email, $reseller, $company ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime select company,email from privatelabel where username='$reseller'\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "achlog.txt", "append", "", $achfilestr );
    my $dbquerystr = <<"dbEOM";
            select company,email
            from privatelabel
            where username=?
dbEOM
    my @dbvalues = ("$reseller");
    ( $plcompany, $plemail ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

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
    print MAIL "Bcc: accounting\@plugnpay.com\n";
    print MAIL "Bcc: michelle\@plugnpay.com\n";
    print MAIL "Bcc: cprice\@plugnpay.com\n";
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

    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime update pending set status='' where username='$merchant' and transorderid='$orderid' \n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "achlog.txt", "append", "", $achfilestr );

    #where username='$merchant'
    #and transorderid='$orderid'
    my $dbquerystr = <<"dbEOM";
          update pending 
          set status=''  
          where transorderid=? 
dbEOM
    my @dbvalues = ("$orderid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    # xxxx 08/11/2004  and result='success' added
    my $dbquerystr = <<"dbEOM";
          select username,orderid,amount,card_type,descr,paidamount,transorderid
          from billingstatus
          where orderid=?
          and result='success'
dbEOM
    my @dbvalues = ("$orderid");
    my @sth_statusavalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    for ( my $vali = 0 ; $vali < scalar(@sth_statusavalarray) ; $vali = $vali + 7 ) {
      ( $busername, $borderid, $bamount, $bcard_type, $bdescr, $chkpaidamount, $btransorderid ) = @sth_statusavalarray[ $vali .. $vali + 6 ];

      if ( $chkpaidamount ne "" ) {
        my $dbquerystr = <<"dbEOM";
            insert into billingreport
            (username,orderid,trans_date,amount,card_type,descr,paidamount,transorderid)
            values (?,?,?,?,?,?,?,?)
dbEOM

        my %inserthash = (
          "username",  "$busername",  "orderid", "$borderid",       "trans_date", "$today",          "amount",       "-$bamount",
          "card_type", "$bcard_type", "descr",   "$bdescr problem", "paidamount", "-$chkpaidamount", "transorderid", "$btransorderid"
        );
        &procutils::dbinsert( $username, $orderid, "pnpmisc", "billingreport", %inserthash );

      } else {
        my $dbquerystr = <<"dbEOM";
            insert into billingreport
            (username,orderid,trans_date,amount,card_type,descr,transorderid)
            values (?,?,?,?,?,?,?)
dbEOM

        my %inserthash =
          ( "username", "$busername", "orderid", "$borderid", "trans_date", "$today", "amount", "-$bamount", "card_type", "$bcard_type", "descr", "$bdescr problem", "transorderid", "$btransorderid" );
        &procutils::dbinsert( $username, $orderid, "pnpmisc", "billingreport", %inserthash );

      }
    }

    $achfilestr = "";
    $achfilestr .= "$remoteuser $todaytime update billingstatus set result='badcard' where orderid=?\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "achlog.txt", "append", "", $achfilestr );
    my $dbquerystr = <<"dbEOM";
          update billingstatus  
          set result='badcard' 
          where orderid=? 
dbEOM
    my @dbvalues = ("$orderid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $errortype = "Return Fee: $descr";
    $fee       = "20.00";
    $type      = "check";

    my $dbquerystr = <<"dbEOM";
            select orderid
            from pending
            where username=?
            and orderid=?
            and descr like 'Return Fee%'
dbEOM
    my @dbvalues = ( "$merchant", "$orderid" );
    ($chkorderid) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    if ( $chkorderid eq "" ) {
      $achfilestr = "";
      &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "achlog.txt", "append", "", $achfilestr );
      my $dbquerystr = <<"dbEOM";
              insert into pending 
              (orderid,username,amount,descr,trans_date,card_type)
              values (?,?,?,?,?,?) 
dbEOM

      my %inserthash = ( "orderid", "$orderid", "username", "$merchant", "amount", "$fee", "descr", "$errortype", "trans_date", "$today", "card_type", "$type" );
      &procutils::dbinsert( $username, $orderid, "pnpmisc", "pending", %inserthash );

    }
  } else {

    my $dbquerystr = <<"dbEOM";
            select acct_code3
            from trans_log 
            where orderid=?
            and operation='auth' 
dbEOM
    my @dbvalues = ("$orderid");
    ($acct_code3) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    if ( $acct_code3 eq "recurring" ) {

      my $dbquerystr = <<"dbEOM";
            select username,orderid
            from billingstatus 
            where orderid=? 
dbEOM
      my @dbvalues = ("$orderid");
      ( $chkusername, $chkorderid ) = &procutils::dbread( $username, $orderid, "$username", $dbquerystr, @dbvalues );

      if ( $chkorderid ne "" ) {
        my $dbquerystr = <<"dbEOM";
            insert into billingstatus
            (username,trans_date,amount,orderid,descr)
            values (?,?,?,?,?) 
dbEOM

        my %inserthash = ( "username", "$chkusername", "trans_date", "$today", "amount", "-$amount", "orderid", "$orderid", "descr", "$descr" );
        &procutils::dbinsert( $username, $orderid, "$username", "billingstatus", %inserthash );

      }

    }
  }

}

sub checkdir {
  my ($date) = @_;

  my $printstr = "checking $date\n";
  &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );

  $fileyear = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 );
  $filemonth = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 );
  $fileyearonly = substr( $date, 0, 4 );

  if ( !-e "/home/pay1/batchfiles/$devprod/globaletel/$fileyearonly" ) {
    my $printstr = "creating $fileyearonly\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/globaletel/$fileyearonly");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/globaletel/$filemonth" ) {
    my $printstr = "creating $filemonth\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/globaletel/$filemonth");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/globaletel/$fileyear" ) {
    my $printstr = "creating $fileyear\n";
    &procutils::filewrite( "$username", "globaletel", "/home/pay1/batchfiles/$devprod/globaletel", "ftplog.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/globaletel/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/globaletel/$fileyear" ) {
    system("mkdir /home/pay1/batchfiles/$devprod/globaletel/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/globaletel/$fileyear" ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: globaletel - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Couldn't create directory logs/globaletel/$fileyear.\n\n";
    close MAILERR;
    exit;
  }

}

