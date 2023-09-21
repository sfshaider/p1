#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SFTP::Foreign;
use Net::SFTP::Foreign::Constants qw(:flags);
use miscutils;
use procutils;

$devprod = "logs";

# mailbox name NAGW-GAGVI001
# Job name RCDMPNPS   for uploading files
# Job name MRDXMPNP   for downloading files

# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI001@test-gw-na.firstdataclients.com     # test
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI001@test2-gw-na.firstdataclients.com    # test
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI001@prod-gw-na.firstdataclients.com     # prod
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI001@prod2-gw-na.firstdataclients.com    # prod
#### sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI001@prod2-gw-na.firstdataclients.com # production

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdmsnorth/getfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "get.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
  exit;
}

#$fdmsaddr = "test2-gw-na.firstdataclients.com";  # test server
$fdmsaddr = "prod2-gw-na.firstdataclients.com";    # production server
$port     = 6522;
$host     = "processor-host";

my $mytime   = gmtime( time() );
my $printstr = "\n$mytime in getfiles.pl\n\n";
&procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );

( $d1, $today, $todaytime ) = &miscutils::genorderid();
$ttime = &miscutils::strtotime($today);

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsnorth/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsnorth/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsnorth/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsnorth/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsnorth - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/fdmsnorth/$fileyear.\n\n";
  close MAILERR;
  exit;
}

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 24 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

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
  "28", "Single Credit Limit Exceeded",
  "29", "Cumulative Credit Limit Exceeded",
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
  "98", "Submission (file) Accepted. (Note there could be rejects for individual items within the file).",
  "99", "Submission (file) rejected."
);

if ( $redofile ne "" ) {
  &processfile($redofile);

  exit;
}

my $dbquerystr = <<"dbEOM";
        select distinct filename,filenum
        from batchfilesfdmsn
        where status='locked'
dbEOM
my @dbvalues = ();
my @sthbatchvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

$batchcnt = 0;
for ( my $vali = 0 ; $vali < scalar(@sthbatchvalarray) ; $vali = $vali + 2 ) {
  ( $filename, $filenum ) = @sthbatchvalarray[ $vali .. $vali + 1 ];

  $batchcnt++;
  my $printstr = "aaaa $filename  $filenum  $batchcnt\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
}

if ( $batchcnt < 1 ) {
  my $printstr = "More/less than one locked batch  $batchcnt   exiting\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

  my $dbquerystr = <<"dbEOM";
          select distinct filename
          from batchfilesfdmsn
          where status='pending'
          order by filename
dbEOM
  my @dbvalues = ();
  ($chkfilename) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $filenamehour = substr( $chkfilename, 0, 10 );
  my $todayhour    = substr( $todaytime,   0, 10 );
  if ( ( $chkfilename ne "" ) && ( ( $todayhour - $filenamehour ) > 1 ) ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdmsnorth - getfiles FAILURE\n";
    print MAILERR "\n";
    print MAILERR "More/less than one locked batch  $batchcnt  $filename\n\n";
    print MAILERR "Oldest pending file is: $chkfilename\n\n";
    print MAILERR "Debug: $todayhour $filenamehour\n\n";
    close MAILERR;
  }

  exit;
}

my %args = (
  user     => "NAGW-GAGVI001",
  password => 'UXLq4iv62',
  port     => 6522,
  key_path => '/home/pay1/batchfiles/prod/fdmsnorth/.ssh/id_rsa'
);

$ftp = Net::SFTP::Foreign->new( "$fdmsaddr", %args );

$ftp->error and die $ftp->error;

if ( $ftp eq "" ) {
  my $printstr = "Username $ftpun and key don't work<br>\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
  my $printstr = "failure";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
  exit;
}

my $printstr = "logged in\n";
&procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

$fileyear = substr( $filename, -14, 4 );

my $files = $ftp->ls('/available') or die "ls error: " . $ftp->error;

if ( @$files == 0 ) {
  my $printstr = "aa no report files\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
}
foreach $var (@$files) {

  $filename = $var->{"filename"};

  my $printstr = "aaaa $filename bbbb\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

  #GPTA00P.GB.GPTA5045.ACKFILE.20170503.055946

  if ( $filename !~ /GPTA5045/ ) {
    next;
  }

  my $fileyear = substr( $filename, -15, 4 ) . "/" . substr( $filename, -11, 2 ) . "/" . substr( $filename, -9, 2 );
  my $fileyymmdd = substr( $filename, -15, 4 ) . substr( $filename, -11, 2 ) . substr( $filename, -9, 2 );

  my $printstr = "fileyear: $fileyear\n";
  $printstr .= "fileyymmdd: $fileyymmdd\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

  &checkdir($fileyymmdd);

  my $printstr = "filename: $filename\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
  my $printstr = "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear/$filename\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

  $ftp->get( "available/$filename", "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear/$filename", copy_perm => 0, copy_time => 0 ) or die "file transfer failed: " . $ftp->error;

  @filenamearray = ( @filenamearray, $filename );
  $mycnt++;
  if ( $mycnt > 0 ) {
    last;
  }
}

foreach $filename (@filenamearray) {
  &processfile( $filename, $today );
}

exit;

sub processfile {
  my ($filename) = @_;
  my $printstr = "in processfile\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

  my $fileyear = substr( $filename, -15, 4 ) . "/" . substr( $filename, -11, 2 ) . "/" . substr( $filename, -9, 2 );

  my $dbquerystr = <<"dbEOM";
        select amount,username,batchnum,filename,filenum
        from batchfilesfdmsn
        where status='locked'
dbEOM
  my @dbvalues = ();
  my @sth3valarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $batchcnt = 0;
  $batchamt = 0;
  for ( my $vali = 0 ; $vali < scalar(@sth3valarray) ; $vali = $vali + 5 ) {
    ( $amount, $username, $batchnum, $batchfile, $filenum ) = @sth3valarray[ $vali .. $vali + 4 ];

    $batchcnt++;
  }

  my $printstr = "filename: $filename\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
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

  my %failarray      = ();
  my $infilestr      = &procutils::fileread( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear", "$filename" );
  my @infilestrarray = split( /\n/, $infilestr );

  umask 0077;
  $outfilestr = "";
  foreach (@infilestrarray) {
    $line = $_;
    chop $line;
    my $printstr = "$line\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

    if ( $line =~ /^A/ ) {
      $cardnumber = substr( $line, 1, 19 );
      $cardnumber =~ tr/\{ABCDEFGHI/0123456789/;
      $cardnumber =~ s/ //g;
      $tcode  = substr( $line, 20, 1 );
      $amount = substr( $line, 21, 8 );
      $amount =~ tr/\{ABCDEFGHI/0123456789/;
      $amount =~ s/ //g;
      $date = substr( $line, 29, 4 );
      $date =~ tr/\{ABCDEFGHI/0123456789/;
      $auth_code = substr( $line, 33, 6 );
      $auth_code =~ s/ //g;
      $authdate = substr( $line, 39, 4 );
      $authdate =~ tr/\{ABCDEFGHI/0123456789/;
      $appcode = substr( $line, 43, 4 );
      $appcode =~ tr/\{ABCDEFGHI/0123456789/;
      $appcode = $appcode + 0;
      $refnumber = substr( $line, 47, 8 );
      $refnumber =~ tr/\{ABCDEFGHI/0123456789/;
      $recseqnum = substr( $line, 55, 6 );
      $recseqnum =~ tr/\{ABCDEFGHI/0123456789/;
      $merchname = substr( $line, 61, 19 );

      my $xslen = length($cardnumber);
      $xs = "x" x $xslen;
      $line =~ s/$cardnumber/$xs/;

      $failarray{"$refnumber $cardnumber $amount $tcode $appcode $auth_code"} = 1;

      $outfilestr .= "$line\n";
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
      my $printstr = "filenum: $filenum\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "salesamt: $salesamt\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "retamt: $retamt\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "cashamt: $cashamt\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "respcode: $respcode\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "filler: $filler\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "recseqnum: $recseqnum\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "submissionid: $submissionid\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "filler: $filler\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "depauthamt: $depauthamt\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "ackind: $ackind\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      $fileflag = 1;
    }
    $outfilestr .= "$line\n";

    if ( $fileamt =~ /^(.+)-$/ ) {
      $fileamt = "-" . $1;
    }
    my $printstr = "dddd: $batchamt  $fileamt  $filebadamt  $fileflag  $username  $batchfile  $batchnum  $descr\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

    if ( $fileflag == 1 ) {
      $outfilestr .= "\n\n";

      my $dbquerystr = <<"dbEOM";
            select orderid,count,amount,filename
            from batchfilesfdmsn
            where trans_date>=?
            and filenum=?
dbEOM
      my @dbvalues = ( "$yesterday", "$filenum" );
      ( $chkorderid, $chkfilecnt, $amount, $batchfile ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      my $printstr = "eeee: $filenum  $detailnum  $batchnum  $chkfilecnt  $chkfileamt  $chkorderid\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

      my $dbquerystr = <<"dbEOM";
          update batchfilesfdmsn set status='done'
          where filenum=?
          and status='locked'
dbEOM
      my @dbvalues = ("$filenum");
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      unlink "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear/$batchfile" . "sav";

      foreach my $key ( sort keys %failarray ) {
        ( $refnumber, $cardnumber, $amount, $tcode, $appcode, $auth_code ) = split( / /, $key );

        my $dbquerystr = <<"dbEOM";
              select orderid,username,batchname,operation,amount
              from batchfilesfdmsn
              where trans_date>=?
              and filenum=?
              and detailnum=?
dbEOM
        my @dbvalues = ( "$yesterday", "$filenum", "$refnumber" );
        ( $orderid, $username, $batchname, $operation, $amount ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

        $oidsub   = substr( $orderid, -10, 10 );
        $errormsg = "$appcode: $errcode{$appcode}";
        $errormsg = substr( $errormsg, 0, 64 );
        if ( $operation eq "postauth" ) {
          $problemsalesamt = $problemsalesamt + $amount;
        } else {
          $problemretamt = $problemretamt + $amount;
        }

        if ( ( $orderid ne "" ) && ( $errormsg !~ /DUP/ ) ) {
          my $dbquerystr = <<"dbEOM";
                  update trans_log
                  set finalstatus='problem',descr=?
                  where orderid=?
                  and username=?
                  and operation=?
                  and (duplicate is NULL or duplicate ='')
                  and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
          my @dbvalues = ( "$errormsg", "$orderid", "$username", "$operation" );
          &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

          my $operationstatus = $operation . 'status';
          my $operationtime   = $operation . 'time';

          my $dbquerystr = <<"dbEOM";
                  update operation_log set $operationstatus='problem',lastopstatus='problem',descr=?
                  where orderid=?
                  and username=?
                  and processor='fdmsnorth'
                  and lastop=?
                  and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
          my @dbvalues = ( "$errormsg", "$orderid", "$username", "$operation" );
          &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

          $outfilestr .= "$username $orderid $operation $amount $errormsg\n";
          my $printstr = "$username $orderid $operation $amount $errormsg\n";
          &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

        }
      }
    }

    if ( ( $fileflag == 1 ) && ( $chkorderid ne "" ) ) {
      my $printstr = "\n\nsuccessful: filenum: $filenum  $batchfile\n\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

      my $printstr = "yesterday: $yesterday\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $dbquerystr = <<"dbEOM";
            select orderid,username,operation,amount
            from batchfilesfdmsn
            where trans_date>=?
            and filenum=?
dbEOM
      my @dbvalues = ( "$yesterday", "$filenum" );
      my @sthordvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      for ( my $vali = 0 ; $vali < scalar(@sthordvalarray) ; $vali = $vali + 4 ) {
        ( $orderid, $username, $operation, $amount ) = @sthordvalarray[ $vali .. $vali + 3 ];

        $chkfilecnt = $chkfilecnt + 1;
        if ( $operation eq "postauth" ) {
          $chksalesamt = $chksalesamt + $amount;
          $chkfileamt  = $chkfileamt + $amount;
        } else {
          $chkretamt  = $chkretamt + $amount;
          $chkfileamt = $chkfileamt - $amount;
        }

        if ( $respcode eq "0098" ) {

          my $dbquerystr = <<"dbEOM";
                update trans_log
                set finalstatus='success',trans_time=?
                where orderid=?
                and username=?
                and operation=?
                and finalstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
          my @dbvalues = ( "$todaytime", "$orderid", "$username", "$operation" );
          &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

          my $operationstatus = $operation . "status";
          my $operationtime   = $operation . "time";

          my $dbquerystr = <<"dbEOM";
                update operation_log set $operationstatus='success',lastopstatus='success',$operationtime=?,lastoptime=?
                where orderid=?
                and username=?
                and processor='fdmsnorth'
                and lastop=?
                and lastopstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
          my @dbvalues = ( "$todaytime", "$todaytime", "$orderid", "$username", "$operation" );
          &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

        }
      }

    }

    if ( $fileflag == 1 ) {
      $outfilestr .= "$username\n";
      $outfilestr .= "$filenum\n";
      $outfilestr .= "\n";

      $fileamt  = sprintf( "%.2f", ( $fileamt / 100 ) + .0005 );
      $salesamt = sprintf( "%.2f", ( $salesamt / 100 ) + .0005 );
      $retamt   = sprintf( "%.2f", ( $retamt / 100 ) + .0005 );
      $outfilestr .= "File amount: $fileamt\n";
      $outfilestr .= "File sales: $salesamt\n";
      $outfilestr .= "File returns: $retamt\n";
      $outfilestr .= "\n";

      $chkfileamt  = sprintf( "%.2f", $chkfileamt + .0005 );
      $chksalesamt = sprintf( "%.2f", $chksalesamt + .0005 );
      $chkretamt   = sprintf( "%.2f", $chkretamt + .0005 );
      $outfilestr .= "DB amount: $chkfileamt\n";
      $outfilestr .= "DB sales: $chksalesamt\n";
      $outfilestr .= "DB returns: $chkretamt\n";
      $outfilestr .= "\n";

      $problemsalesamt = sprintf( "%.2f", $problemsalesamt + .0005 );
      $problemretamt   = sprintf( "%.2f", $problemretamt + .0005 );
      $outfilestr .= "problem sales: $problemsalesamt\n";
      $outfilestr .= "problem returns: $problemretamt\n";
      $outfilestr .= "\n";

      my $printstr = "$username\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "$filenum\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

      my $printstr = "File amount: $fileamt\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "File sales: $salesamt\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "File returns: $retamt\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

      my $printstr = "DB amount: $chkfileamt\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "DB sales: $chksalesamt\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "DB returns: $chkretamt\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

      my $printstr = "problem sales: $problemsalesamt\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "problem returns: $problemretamt\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

      my $printstr = "\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
    }
  }

  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear", "$filename.txt", "write", "", $outfilestr );

  unlink "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear/$filename";
}

exit;

sub checkdir {
  my ($date) = @_;

  my $printstr = "checking $date\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );

  $fileyear = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 );
  $filemonth = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 );
  $fileyearonly = substr( $date, 0, 4 );

  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyearonly" ) {
    my $printstr = "creating $fileyearonly\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsnorth/$fileyearonly");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsnorth/$filemonth" ) {
    my $printstr = "creating $filemonth\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsnorth/$filemonth");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear" ) {
    my $printstr = "creating $fileyear\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "ftplog.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear" ) {
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsnorth/$fileyear" ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdmsnorth - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Couldn't create directory logs/fdmsnorth/$fileyear.\n\n";
    close MAILERR;
    exit;
  }

}

