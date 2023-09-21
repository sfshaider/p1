#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SFTP::Foreign;
use Net::SFTP::Foreign::Constants qw(:flags);
use miscutils;

$devprod = "devlogs";

# mailbox name NAGW-HRXCW001
# Job name RCDMPNPS   for uploading files
# Job name MRDXMPNP   for downloading files

# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-HRXCW001@test-gw-na.firstdataclients.com     # test
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-HRXCW001@test2-gw-na.firstdataclients.com    # test
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-HRXCW001@prod-gw-na.firstdataclients.com     # prod
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-HRXCW001@prod2-gw-na.firstdataclients.com    # prod
#### sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-HRXCW001@prod2-gw-na.firstdataclients.com # production

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdmsrctok/getfiles.pl'`;
if ( $cnt > 1 ) {
  print "get.pl already running, exiting...\n";
  exit;
}

#$fdmsaddr = "test2-gw-na.firstdataclients.com";  # test server
$fdmsaddr = "prod2-gw-na.firstdataclients.com";    # production server
$port     = 6522;
$host     = "processor-host";

my $mytime = gmtime( time() );
print "\n$mytime in getfiles.pl\n\n";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );

( $d1, $today, $todaytime ) = &miscutils::genorderid();
$ttime = &miscutils::strtotime($today);

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsrctok/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsrctok/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsrctok/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsrctok/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsrctok - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/fdmsrctok/$fileyear.\n\n";
  close MAILERR;
  exit;
}

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 54 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

$dbh  = &miscutils::dbhconnect("pnpmisc");
$dbh2 = &miscutils::dbhconnect("pnpdata");

%errcode = (
  "0",  "Debit Q Record (Record was received).",
  "1",  "Merchant Record missing or invalid.",
  "2",  "N (Descriptor) Record missing or invalid.",
  "3",  "Invalid Record id.",
  "4",  "Total 1 Record missing or information invalid.",
  "5",  "Total 2 Record missing or information invalid.",
  "7",  "B Record missing or information invalid.",
  "8",  "Detail Accepted for Deposit (Transaction Codes 5, 6 and 7).",
  "9",  "Detail Record Bypassed.",
  "10", "Invalid Cardholder Account Number.",
  "11", "Invalid Transaction Code or not Entitled to card product.",
  "12", "Invalid Transaction Amount, or over Master file/Job limit.",
  "13", "Invalid Transaction Date.",
  "14", "Invalid Authorization Date or Code.",
  "15", "Invalid Card Expiration Date/Expired Card (DirectSolutions only).",
  "16", "Invalid Reference Number.",
  "17", "Record Out of Sequence.",
  "18", "Duplicate Batch Number.",
  "19", "Additional AMEX Records not available or incorrect.",
  "20", "Approved & deposit accepted (Transaction Codes 8 or 9.)",
  "21", "Approved (Transaction Code A - F, J, R)",
  "22", "Declined - Closed Account, Expired Card, Delinquent, Over the Credit Limit, etc. (DirectSolutions only) Also used to denote Invalid Authorization Reversal Request.",
  "23", "Declined (Pick-up) -Collection status, lost or stolen card. (DirectSolutions only)",
  "24", "Referral (DirectSolutions only).",
  "25", "Invalid Foreign Detail - Non-numeric dollar amount or invalid minor amount",
  "26", "Invalid foreign detail - incorrect currency code",
  "27", "Transaction rejected - duplicate/previously submitted",
  "30", "Total Sales amount out of balance or not numeric.",
  "31", "Total Credit (return) amount out of balance or not numeric.",
  "32", "Total Cash Advance amount out of balance or not numeric.",
  "33", "Total Sales Auth amount out of balance or not numeric.",
  "34", "Total Cash Advance Auth. amount out of balance or not numeric.",
  "35", "(PTS) Discover Full Service Sales will reject if the Acquirer ID and/or Processor ID fields have a value of zeroes or blank. Note: Please contact your RM for further assistance.",
  "36", "(PTS) Discover sales will reject if Processing code field in XV01 record is invalid or record not supplied for Discover Full service entitled merchants.",
  "37", "(PTS) For discover full service merchant- cash back amount in XV06 record is greater than $100 Note: Cash back amount must be less than transaction amount.",
  "40", "(PTS) E record MCC not valid. (DirectSolutions)Total No. Sales Auth. Request out of balance or not numeric.",
  "44", "(PTS) Addendum item out of Balance (Voyager/Wright Express) (DirectSolutions)Total No. Diners Club Auth. Request out of balance or not numeric",
  "45", "(PTS) Detail out of balance w Addendum (Voyager/Wright Express) (DirectSolutions)Total No. Discover Auth. Request out of balance or not numeric",
  "46", "Total No. Private Label Auth. Request out of balance or not numeric.",
  "47", "Total No. Address Verification Request out of balance or not numeric.",
  "48", "Detail was re-authorized. (Direct Solutions).",
  "49", "Detail held for 'Delay Retry'.",
  "50", "Detail held for 'Optional Referral'. (Direct Solutions)",
  "52", "Signature Capture Data Rejected, Detail Accepted.- Warning only",
  "62", "Signature Capture Data Rejected, invalid signature detail or over 500 bytes",
  "70", "(PTS) Invalid or Missing product code (Voyager/Wright Express) (DirectSolutions)Total No. Cash Advance Auth. Request out of balance or not numeric",
  "70", "Signature Capture Data Rejected, Detail Rejected.",
  "71", "(PTS) Invalid or Missing Qty/sale amount (Voyager/Wright Express) (DirectSolutions)Total No. American Express Auth. Request out of balance or not numeric.",
  "71", "(PTS) XD50 Passenger name equal spaces (warning only)",
  "72", "(Direct Solutions) Total No. Carte Blanche Auth. Request out of balance or not numeric.",
  "72", "(PTS) XD56 Travel date not valid - Warning only./ airline itinerary- invalid city of origin",
  "73", "(PTS) XD56 Airport Destination equal spaces or zeroes- Warning only",
  "74", "(PTS) airline itinerary invalid 2nd, 3rd, 4th trip leg information",
  "75", "(PTS) XD52 Ticket number = Spaces or zeroes - Warning only",
  "80", "Address Verification request (See preceding 'V' Record). (DirectSolutions).",
  "81", "Address Verification error (See preceding 'V' Record). DirectSolutions.",
  "82", "Conditional Deposit rejected due to AVS Result (See preceding 'V' Record). DirectSolutions",
  "83", "Address Verification requested, however, no input Address Verification ('V') Record present. DirectSolutions",
  "84", "Conditional Deposit rejected due to CVV2/CVC2 result. Result = N (not matched) or Result = S (CVV2/CVC2 should be on the card, but it was indicated that it was not present. DirectSolutions",
  "91", "Unable to detox",
  "95", "Merchant not allowed to use token type submitted",
  "98", "Submission (file) Accepted. (Note there could be rejects for individual items within the file).",
  "99", "Submission (file) rejected."
);

if ( $redofile ne "" ) {
  &processfile($redofile);
  $dbh->disconnect;
  $dbh2->disconnect;
  exit;
}

my $sthbatch = $dbh->prepare(
  qq{
        select distinct filename,filenum
        from batchfilesfdmsrc
        where status='locked'
        and processor='fdmsrctok'
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthbatch->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthbatch->bind_columns( undef, \( $filename, $filenum ) );

$batchcnt = 0;
while ( $sthbatch->fetch ) {
  $batchcnt++;
  print "aaaa $filename  $filenum  $batchcnt\n";
}
$sthbatch->finish;

if ( $batchcnt < 1 ) {
  print "More/less than one locked batch  $batchcnt   exiting\n";

  my $sthbatch2 = $dbh->prepare(
    qq{
          select distinct filename
          from batchfilesfdmsrc
          where status='pending'
          and processor='fdmsrctok'
          order by filename
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthbatch2->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ($chkfilename) = $sthbatch2->fetchrow;
  $sthbatch2->finish;

  my $filenamehour = substr( $chkfilename, 0, 10 );
  my $todayhour    = substr( $todaytime,   0, 10 );
  if ( ( $chkfilename ne "" ) && ( ( $todayhour - $filenamehour ) > 1 ) ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdmsrctok - getfiles FAILURE\n";
    print MAILERR "\n";
    print MAILERR "More/less than one locked batch  $batchcnt  $filename\n\n";
    print MAILERR "Oldest pending file is: $chkfilename\n\n";
    print MAILERR "Debug: $todayhour $filenamehour\n\n";
    close MAILERR;
  }

  exit;
}

my %args = (
  user     => "NAGW-HRXCW001",
  password => 'B43AXtcc4',
  port     => 6522,
  key_path => '/home/pay1/batchfiles/prod/fdmsrctok/.ssh/id_rsa'
);

$ftp = Net::SFTP::Foreign->new( "$fdmsaddr", %args );

$ftp->error and die "error: " . $ftp->error;

if ( $ftp eq "" ) {
  print "Username $ftpun and key don't work<br>\n";
  print "failure";
  exit;
}

print "logged in\n";

$fileyear = substr( $filename, -14, 4 );

my $files = $ftp->ls('/available') or die "ls error: " . $ftp->error;

if ( @$files == 0 ) {
  print "aa no report files\n";
}
foreach $var (@$files) {

  $filename = $var->{"filename"};
  print "aaaa $filename bbbb\n";
  if ( $filename !~ /GPTD5808/ ) {
    next;
  }

  my $fileyear = substr( $filename, 13, 4 ) . "/" . substr( $filename, 9, 2 ) . "/" . substr( $filename, 11, 2 );
  my $fileyymmdd = substr( $filename, 13, 4 ) . substr( $filename, 9, 2 ) . substr( $filename, 11, 2 );

  print "fileyear: $fileyear\n";
  print "fileyymmdd: $fileyymmdd\n";

  &checkdir($fileyymmdd);

  print "filename: $filename\n";
  print "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$filename\n";
  $ftp->get( "available/$filename", "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$filename", copy_perm => 0, copy_time => 0 ) or die "file transfer failed: " . $ftp->error;

  @filenamearray = ( @filenamearray, $filename );
  $mycnt++;
  if ( $mycnt > 0 ) {
    last;
  }

}

$ftp->disconnect();

foreach $filename (@filenamearray) {
  &processfile( $filename, $today );
}

$dbh->disconnect;
$dbh2->disconnect;

exit;

sub processfile {
  my ($filename) = @_;
  print "in processfile\n";

  # GPTD5808.12192017.152828.TXT
  my $fileyear = substr( $filename, -15, 4 ) . "/" . substr( $filename, -19, 2 ) . "/" . substr( $filename, -17, 2 );

  $sth3 = $dbh->prepare(
    qq{
        select amount,username,batchnum,filename,filenum
        from batchfilesfdmsrc
        where status='locked'
        and processor='fdmsrctok'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth3->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth3->bind_columns( undef, \( $amount, $username, $batchnum, $batchfile, $filenum ) );

  $batchcnt = 0;
  $batchamt = 0;
  while ( $sth3->fetch ) {
    $batchcnt++;
  }
  $sth3->finish;

  print "filename: $filename\n";
  $detailflag = 0;
  $batchflag  = 0;
  $fileflag   = 0;
  $batchnum   = "";
  $filenum    = "";

  $problemamt      = 0;
  $problemsalesamt = 0;
  $problemretamt   = 0;

  $chkfilecnt  = 0;
  $chkfileamt  = 0;
  $chksalesamt = 0;
  $chkretamt   = 0;

  my %failarray = ();
  open( infile, "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$filename" );
  print "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$filename";
  umask 0077;
  open( outfile, ">/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$filename.done" );
  while (<infile>) {
    $line = $_;
    chop $line;
    print "$line\n";

    if ( $line =~ /^A/ ) {
      $cardnumber = substr( $line, 1, 16 );    # was 19
      $cardnumber =~ tr/\{ABCDEFGHI/0123456789/;
      $cardnumber =~ s/ //g;
      $tcode  = substr( $line, 17, 1 );
      $amount = substr( $line, 18, 8 );
      $amount =~ tr/\{ABCDEFGHI/0123456789/;
      $amount =~ s/ //g;
      $date = substr( $line, 26, 4 );
      $date =~ tr/\{ABCDEFGHI/0123456789/;
      $auth_code = substr( $line, 30, 6 );
      $auth_code =~ s/ //g;
      $authdate = substr( $line, 36, 4 );
      $authdate =~ tr/\{ABCDEFGHI/0123456789/;
      $appcode = substr( $line, 40, 4 );
      $appcode =~ tr/\{ABCDEFGHI/0123456789/;
      $appcode = $appcode + 0;
      $refnumber = substr( $line, 44, 8 );
      $refnumber =~ tr/\{ABCDEFGHI/0123456789/;
      $recseqnum = substr( $line, 52, 6 );
      $recseqnum =~ tr/\{ABCDEFGHI/0123456789/;
      $merchname = substr( $line, 58, 19 );

      print "refnumber: $refnumber\n";
      print "amount: $amount\n";
      print "tcode: $tcode\n";
      print "appcode: $appcode\n";
      print "auth_code: $auth_code\n";

      my $xslen = length($cardnumber);
      $xs = "x" x $xslen;
      $line =~ s/$cardnumber/$xs/;

      $failarray{"$refnumber $cardnumber $amount $tcode $appcode $auth_code"} = 1;

      print outfile "$line\n";
      next;
    } elsif ( $line =~ /^B/ ) {
      $salesamt = substr( $line, 1, 9 );
      $salesamt =~ tr/\{ABCDEFGHI/0123456789/;
      $retamt = substr( $line, 10, 9 );
      $retamt =~ tr/\{ABCDEFGHI/0123456789/;
      $cashamt = substr( $line, 19, 9 );
      $cashamt =~ tr/\{ABCDEFGHI/0123456789/;
      $respcode = substr( $line, 28, 4 );
      $respcode =~ tr/\{ABCDEFGHI/0123456789/;
      $filler    = substr( $line, 32, 5 );
      $recseqnum = substr( $line, 37, 6 );
      $recseqnum =~ tr/\{ABCDEFGHI/0123456789/;
      $submissionid = substr( $line,         43, 9 );
      $filenum      = substr( $submissionid, 0,  6 );
      $filler       = substr( $line,         52, 8 );
      $depauthamt   = substr( $line,         60, 9 );
      $depauthamt =~ tr/\{ABCDEFGHI/0123456789/;
      $cashauthamt = substr( $line, 69, 9 );
      $cashauthamt =~ tr/\{ABCDEFGHI/0123456789/;
      $ackind = substr( $line, 78, 1 );
      print "filenum: $filenum\n";
      print "salesamt: $salesamt\n";
      print "retamt: $retamt\n";
      print "cashamt: $cashamt\n";
      print "respcode: $respcode\n";
      print "filler: $filler\n";
      print "recseqnum: $recseqnum\n";
      print "submissionid: $submissionid\n";
      print "filler: $filler\n";
      print "depauthamt: $depauthamt\n";
      print "ackind: $ackind\n";
      $fileflag = 1;
    }
    print outfile "$line\n";

    if ( $fileamt =~ /^(.+)-$/ ) {
      $fileamt = "-" . $1;
    }
    print "dddd: $batchamt  $fileamt  $filebadamt  $fileflag  $username  $batchfile  $batchnum  $descr\n";

    if ( $fileflag == 1 ) {
      print outfile "\n\n";

      my $sthord = $dbh->prepare(
        qq{
            select orderid,count,amount,filename
            from batchfilesfdmsrc
            where trans_date>='$yesterday'
            and processor='fdmsrctok'
            and filenum='$filenum'
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthord->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      ( $chkorderid, $chkfilecnt, $amount, $batchfile ) = $sthord->fetchrow;
      $sthord->finish;

      print "eeee: $filenum  $detailnum  $batchnum  $chkfilecnt  $chkfileamt  $chkorderid\n";

      local $sth = $dbh->prepare(
        qq{
          update batchfilesfdmsrc set status='done'
          where filenum='$filenum'
          and status='locked'
          and processor='fdmsrctok'
          }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sth->finish;

      unlink "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$batchfile" . "sav";

      foreach my $key ( sort keys %failarray ) {
        ( $refnumber, $cardnumber, $amount, $tcode, $appcode, $auth_code ) = split( / /, $key );

        my $sthord = $dbh->prepare(
          qq{
              select orderid,username,batchname,operation,amount
              from batchfilesfdmsrc
              where trans_date>='$yesterday'
              and filenum='$filenum'
              and detailnum='$refnumber'
              and processor='fdmsrctok'
              }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sthord->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        ( $orderid, $username, $batchname, $operation, $amount ) = $sthord->fetchrow;
        $sthord->finish;
        print "fail: $filenum $refnumber $orderid $errormsg\n";

        $oidsub   = substr( $orderid, -10, 10 );
        $errormsg = "$appcode: $errcode{$appcode}";
        $errormsg = substr( $errormsg, 0, 64 );
        if ( $operation eq "postauth" ) {
          $problemsalesamt = $problemsalesamt + $amount;
        } else {
          $problemretamt = $problemretamt + $amount;
        }

        if ( ( $orderid ne "" ) && ( $errormsg !~ /DUP/ ) ) {
          my $sth_trans = $dbh2->prepare(
            qq{
                  update trans_log
                  set finalstatus='problem',descr=?
                  where orderid='$orderid'
                  and username='$username'
                  and operation='$operation'
                  and (duplicate is NULL or duplicate ='')
                  and (accttype is NULL or accttype='' or accttype='credit')
                  }
            )
            or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
          $sth_trans->execute("$errormsg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
          $sth_trans->finish;

          my $operationstatus = $operation . 'status';
          my $operationtime   = $operation . 'time';

          my $sthop1 = $dbh2->prepare(
            qq{
                  update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
                  where orderid='$orderid'
                  and username='$username'
                  and processor='fdmsrctok'
                  and lastop='$operation'
                  and (accttype is NULL or accttype='' or accttype='credit')
                  }
            )
            or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
          $sthop1->execute("$errormsg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
          $sthop1->finish;

          print outfile "$username $orderid $operation $amount $errormsg\n";
          print "$username $orderid $operation $amount $errormsg\n";

        }
      }
    }

    if ( ( $fileflag == 1 ) && ( $chkorderid ne "" ) ) {
      print "\n\nsuccessful: filenum: $filenum  $batchfile\n\n";

      print "yesterday: $yesterday\n";
      my $sthord = $dbh->prepare(
        qq{
            select orderid,username,operation,amount
            from batchfilesfdmsrc
            where trans_date>='$yesterday'
            and filenum='$filenum'
            and processor='fdmsrctok'
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthord->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthord->bind_columns( undef, \( $orderid, $username, $operation, $amount ) );

      while ( $sthord->fetch ) {
        $chkfilecnt = $chkfilecnt + 1;
        if ( $operation eq "postauth" ) {
          $chksalesamt = $chksalesamt + $amount;
          $chkfileamt  = $chkfileamt + $amount;
        } else {
          $chkretamt  = $chkretamt + $amount;
          $chkfileamt = $chkfileamt - $amount;
        }

        if ( $respcode eq "0098" ) {

          my $sth_trans = $dbh2->prepare(
            qq{
                update trans_log
                set finalstatus='success',trans_time=?
                where orderid='$orderid'
                and username='$username'
                and operation='$operation'
                and finalstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
                }
            )
            or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
          $sth_trans->execute("$todaytime") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
          $sth_trans->finish;

          my $operationstatus = $operation . "status";
          my $operationtime   = $operation . "time";

          my $sthop = $dbh2->prepare(
            qq{
                update operation_log set $operationstatus='success',lastopstatus='success',$operationtime=?,lastoptime=?
                where orderid='$orderid'
                and username='$username'
                and processor='fdmsrctok'
                and lastop='$operation'
                and lastopstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
                }
            )
            or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
          $sthop->execute( "$todaytime", "$todaytime" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
          $sthop->finish;
        }
      }
      $sthord->finish;
    }

    if ( $fileflag == 1 ) {
      print outfile "$username\n";
      print outfile "$filenum\n";
      print outfile "\n";

      $fileamt  = sprintf( "%.2f", ( $fileamt / 100 ) + .0005 );
      $salesamt = sprintf( "%.2f", ( $salesamt / 100 ) + .0005 );
      $retamt   = sprintf( "%.2f", ( $retamt / 100 ) + .0005 );
      print outfile "File amount: $fileamt\n";
      print outfile "File sales: $salesamt\n";
      print outfile "File returns: $retamt\n";
      print outfile "\n";

      $chkfileamt  = sprintf( "%.2f", $chkfileamt + .0005 );
      $chksalesamt = sprintf( "%.2f", $chksalesamt + .0005 );
      $chkretamt   = sprintf( "%.2f", $chkretamt + .0005 );
      print outfile "DB amount: $chkfileamt\n";
      print outfile "DB sales: $chksalesamt\n";
      print outfile "DB returns: $chkretamt\n";
      print outfile "\n";

      $problemsalesamt = sprintf( "%.2f", $problemsalesamt + .0005 );
      $problemretamt   = sprintf( "%.2f", $problemretamt + .0005 );
      print outfile "problem sales: $problemsalesamt\n";
      print outfile "problem returns: $problemretamt\n";
      print outfile "\n";

      print "$username\n";
      print "$filenum\n";
      print "\n";

      print "File amount: $fileamt\n";
      print "File sales: $salesamt\n";
      print "File returns: $retamt\n";
      print "\n";

      print "DB amount: $chkfileamt\n";
      print "DB sales: $chksalesamt\n";
      print "DB returns: $chkretamt\n";
      print "\n";

      print "problem sales: $problemsalesamt\n";
      print "problem returns: $problemretamt\n";
      print "\n";

      print "\n";
    }
  }
  close(infile);
  close(outfile);
}

exit;

sub checkdir {
  my ($date) = @_;

  print "checking $date\n";

  $fileyear = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 );
  $filemonth = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 );
  $fileyearonly = substr( $date, 0, 4 );

  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyearonly" ) {
    print "creating $fileyearonly\n";
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsrctok/$fileyearonly");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsrctok/$filemonth" ) {
    print "creating $filemonth\n";
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsrctok/$filemonth");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear" ) {
    print "creating $fileyear\n";
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear" ) {
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear" ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdmsrctok - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Couldn't create directory logs/fdmsrctok/$fileyear.\n\n";
    close MAILERR;
    exit;
  }

}

