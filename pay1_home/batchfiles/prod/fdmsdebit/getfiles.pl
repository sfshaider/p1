#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SFTP::Foreign;
use Net::SFTP::Foreign::Constants qw(:flags);
use miscutils;
use procutils;

$devprod = "logs";

# mailbox name NAGW-GAGVI004
# Job name RCDMPNPS   for uploading files
# Job name MRDXMPNP   for downloading files

# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI004@test-gw-na.firstdataclients.com     # test
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI004@test2-gw-na.firstdataclients.com    # test
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI004@prod-gw-na.firstdataclients.com     # prod
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI004@prod2-gw-na.firstdataclients.com    # prod
#### sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI004@prod2-gw-na.firstdataclients.com # production

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdmsdebit/getfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "get.pl already running, exiting...\n";
  &procutils::filewrite( "getfiles", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
  exit;
}

#$fdmsaddr = "test2-gw-na.firstdataclients.com";  # test server
$fdmsaddr = "prod2-gw-na.firstdataclients.com";    # production server
$port     = 6522;
$host     = "processor-host";

#$redofile = "CO000405.190624132444.90624.03820.out";

my $mytime   = gmtime( time() );
my $printstr = "\n$mytime in getfiles.pl\n\n";
&procutils::filewrite( "getfiles", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 60 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );

( $d1, $today, $todaytime ) = &miscutils::genorderid();
$ttime = &miscutils::strtotime($today);

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsdebit/$fileyearonly");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyearonly" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsdebit/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsdebit/$filemonth");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsdebit/$filemonth" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear");
  chmod( 0700, "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear" );
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsdebit - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/fdmsdebit/$fileyear.\n\n";
  close MAILERR;
  exit;
}

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 24 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

%errmsg = (
  "000", "Paymentech received no answer from auth network",
  "100", "Approved",
  "101", "Account passed Paymentech negative file and data edit checks",
  "102", "Account passed external negative file",
  "103", "Passed prenote",
  "201", "Bad check digit, length, or other credit card problem",
  "202", "Amount sent was 0 or unreadable",
  "204", "Unidentifiable error",
  "225", "Data within transaction is incorrect",
  "227", "Specific and relevant data within transaction is absent",
  "231", "Division number incorrect",
  "233", "CC number does not match MOP tyep",
  "234", "Unique to Auth Recyce transactions. Order number already exists in system",
  "236", "Auth recycle host system temporarily unavailable",
  "238", "The currency type in the incoming record does not match the currency type stored in the system.",
  "239", "Method of payment is invalid for the division",
  "243", "Data is inaccurate or missing",
  "251", "Incorrect start date or card may require an issue number, but a start date was submitted",
  "252", "1-digit number submitted when a 2-digit number should have been sent",
  "260", "Card was authorized, but AVS did not match. The 100 was overwritten with a 260 per the merchants' request",
  "301", "Auth network couldn't reach the bank which issued the card",
  "302", "Insufficient funds",
  "303", "Generic decline - NO other information is being provided by the issuer",
  "401", "Issuer wants voice contact with cardholder",
  "402", "Approve/Decline",
  "501", "Card issuer wants card returned",
  "502", "Card reported as lost/stolen",
  "519", "Account number appears on negative file",
  "522", "Card has expired",
  "530", "Generic decline - NO other information is being provided by the issuer",
  "531", "Issuer has declined auth request because CVV2 edit failed",
  "591", "Bad check digit, length or ther credit card problem. Issuer generated",
  "592", "Amount sent was 0 or unreadable. Issuer generated",
  "594", "Unidentifiable error. Issuer generated",
  "602", "Card is bad, but passes Mod 10 check digit routine",
  "605", "Card has expired or bad date sent. Confirm proper date",
  "606", "Issuer does not allow this type of transaction",
  "607", "Amount not accepted by network",
  "750", "ABA transit routing number is invalid, fails check digit",
  "751", "Transit routing number not on list of current acceptable numbers",
  "752", "Missing name",
  "753", "Invalid account type",
  "754", "Bank account has been closed",
  "755", "Does not match any account for the customer at the bank",
  "756", "Customer or accountholder has died",
  "757", "Beneficiary on account has died",
  "758", "Transaction posting to account prohibited",
  "759", "Customer has refused to allow transaction",
  "760", "Banking institution does not accept ACH transactions",
  "763", "Account number is incorrect",
  "764", "Customer has notified their bank not to accept these transactions",
  "765", "customer has not authorized bank to accept these transactions",
  "766", "Invalid CECP action code. Pertains to Canadian ECP transactions only",
  "767", "Formatting of account number is incorrect",
  "768", "Invalid characters in account number",
  "802", "Issuer requires further data",
  "806", "Card has been restricted",
  "811", "Amex CID is incorrect",
  "813", "PIN for online debit transactions is incorrect",
  "825", "Account does not exist",
  "833", "Division number incorrecg",
  "834", "Method of payment is invalid for the division"
);

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
  "98", "Submission (file) Accepted. (Note there could be rejects for individual items within the file).",
  "99", "Submission (file) rejected."
);

if ( $redofile ne "" ) {
  &processfile($redofile);

  exit;
}

my $dbquerystr = <<"dbEOM";
        select distinct filename,filenum
        from batchfilesfdmsrc
        where status='locked'
        and processor='fdmsdebit'
dbEOM
my @dbvalues = ();
my @sthbatchvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

$batchcnt = 0;
for ( my $vali = 0 ; $vali < scalar(@sthbatchvalarray) ; $vali = $vali + 2 ) {
  ( $filename, $filenum ) = @sthbatchvalarray[ $vali .. $vali + 1 ];

  $batchcnt++;

  my $printstr = "aaaa $filename  $filenum  $batchcnt\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
}

if ( $batchcnt < 1 ) {
  my $printstr = "More/less than one locked batch  $batchcnt   exiting\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

  my $dbquerystr = <<"dbEOM";
          select distinct filename
          from batchfilesfdmsrc
          where status='pending'
          and processor='fdmsdebit'
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
    print MAILERR "Subject: fdmsdebit - getfiles FAILURE\n";
    print MAILERR "\n";
    print MAILERR "More/less than one locked batch  $batchcnt  $filename\n\n";
    print MAILERR "Oldest pending file is: $chkfilename\n\n";
    print MAILERR "Debug: $todayhour $filenamehour\n\n";
    close MAILERR;
  }

  exit;
}

my %args = (
  user     => "NAGW-GAGVI004",
  password => 'VQDeub431',
  port     => 6522,
  key_path => '/home/pay1/batchfiles/prod/fdmsdebit/.ssh/id_rsa'
);

$ftp = Net::SFTP::Foreign->new( "$fdmsaddr", %args );

$ftp->error and die "error: " . $ftp->error;

if ( $ftp eq "" ) {
  my $printstr = "Username $ftpun and key don't work<br>\n";
  $printstr .= "failure";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
  exit;
}

my $printstr = "logged in\n";
&procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

$fileyear = substr( $filename, -14, 4 );

my $files = $ftp->ls('/available') or die "ls error: " . $ftp->error;

if ( @$files == 0 ) {
  my $printstr = "aa no report files\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
}
foreach $var (@$files) {

  $filename = $var->{"filename"};

  my $printstr = "aaaa $filename bbbb\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

  if ( $filename !~ /CO000405/ ) {
    next;
  }

  my $fileyear = "20" . substr( $filename, 9, 2 ) . "/" . substr( $filename, 11, 2 ) . "/" . substr( $filename, 13, 2 );
  my $fileyymmdd = "20" . substr( $filename, 9, 2 ) . substr( $filename, 11, 2 ) . substr( $filename, 13, 2 );

  my $printstr = "fileyear: $fileyear\n";
  $printstr .= "fileyymmdd: $fileyymmdd\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

  &checkdir($fileyymmdd);

  if ( ( $filename =~ /\.out/ ) && ( !-e "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear/$filename.done" ) ) {
    my $printstr = "filename: $filename\n";
    $printstr .= "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear/$filename\n";
    &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

    $ftp->get( "available/$filename", "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear/$filename", copy_perm => 0, copy_time => 0 ) or die "file transfer failed: " . $ftp->error;

    @filenamearray = ( @filenamearray, $filename );
    $mycnt++;
    if ( $mycnt > 0 ) {
      last;
    }
  }
}

foreach $filename (@filenamearray) {
  &processfile( $filename, $today );
}

exit;

sub processfile {
  my ($filename) = @_;
  my $printstr = "in processfile\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

  # CO000405.12192017.152828.TXT
  my $fileyear = "20" . substr( $filename, 9, 2 ) . "/" . substr( $filename, 11, 2 ) . "/" . substr( $filename, 13, 2 );

  my $dbquerystr = <<"dbEOM";
        select amount,username,batchnum,filename,filenum
        from batchfilesfdmsrc
        where status='locked'
        and processor='fdmsdebit'
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
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
  $detailflag = 0;
  $batchflag  = 0;
  $fileflag   = 0;
  $batchnum   = "";
  $filenum    = "";

  my %failarray      = ();
  my $infilestr      = &procutils::fileread( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear", "$filename" );
  my @infilestrarray = split( /\n/, $infilestr );

  umask 0077;
  $outfilestr = "";
  foreach (@infilestrarray) {
    $line = $_;
    chop $line;

    if ( $line =~ /^S/ ) {
      ( $d1, $divisionnum, $detailnum, $action, $mop, $acctnum, $exp, $amount, $currency, $respcode, $transtype, $cvv, $tdate, $auth_code, $avs_code, $depositflag, $fraudind, $encflag, $recurringind ) =
        unpack "A1A10A22A2A2A19A4A12A3A3A1A1A6A6A2A1A1A3A2", $line;

      $divisionnum =~ s/^0{4}//g;
      $detailnum = substr( $detailnum, 0, 8 );

      $acctnum =~ s/ //g;
      $xs = "x" x length($acctnum);
      $line =~ s/$acctnum/$xs/;
      $outfilestr .= "$line\n";

      my $printstr = "\ndivisionnum: $divisionnum\n";
      $printstr .= "detailnum: $detailnum\n";
      &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

      print "divisionnum: $divisionnum\n";
      print "detailnum: $detailnum\n";
      print "depositflag: $depositflag\n";

      if ( $depositflag eq "N" ) {
        $finalstatus = 'problem';
      } elsif ( $depositflag eq "Y" ) {
        $finalstatus = 'success';
      }

      $username = "";
      if ( $divarray{"$divisionnum"} eq "" ) {
        my $dbquerystr = <<"dbEOM";
            select username
            from customers
            where merchant_id=?
            and processor='fdmsdebit'
dbEOM
        my @dbvalues = ("$divisionnum");
        ($username) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

        $divarray{"$divisionnum"} = $username;
      } else {
        $username = $divarray{"$divisionnum"};
      }
      print "username: $username\n";

      if ( $depositflag eq "N" ) {
        open( MAILERR, "| /usr/lib/sendmail -t" );
        print MAILERR "To: cprice\@plugnpay.com\n";
        print MAILERR "From: dcprice\@plugnpay.com\n";
        print MAILERR "Subject: fdmsdebit - $username FAILURE\n";
        print MAILERR "\n";
        print MAILERR "Batch failed for $username .\n\n";
        print MAILERR "filename: $filename\n\n";
        print MAILERR "division number: $divisionnum\n\n";
        close MAILERR;
      }

      # xxxx
      my $dbquerystr = <<"dbEOM";
          select orderid,filename
          from batchfilesfdmsrc
          where detailnum=?
          and username=?
          and trans_date>=?
          and status='locked'
          and processor='fdmsdebit'
dbEOM
      my @dbvalues = ( "$detailnum", "$username", "$twomonthsago" );
      ( $orderid, $batchfilename ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );
      print "orderid: $orderid\n";

      my $dbquerystr = <<"dbEOM";
          update batchfilesfdmsrc
          set status='done'
          where detailnum=?
          and username=?
          and status='locked'
          and trans_date>=?
            and processor='fdmsdebit'
dbEOM
      my @dbvalues = ( "$detailnum", "$username", "$twomonthsago" );
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      my $printstr = "username: $username  orderid: $orderid  finalstatus: $finalstatus\n";
      $printstr .= "twomonthsago: $twomonthsago\n";
      &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

      my $dbquerystr = <<"dbEOM";
            update trans_log
            set finalstatus=?,descr=?
            where orderid=?
            and username>=?
            and trans_date>=?
            and (accttype is NULL or accttype='' or accttype='credit')
            and finalstatus='locked'
dbEOM
      my @dbvalues = ( "$finalstatus", "$respcode: $errmsg{$respcode}", "$orderid", "$username", "$twomonthsago" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set postauthstatus=?,lastopstatus=?,descr=?
            where orderid=?
            and username=?
            and postauthstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$finalstatus", "$finalstatus", "$respcode: $errmsg{$respcode}", "$orderid", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
      my $dbquerystr = <<"dbEOM";
            update operation_log set returnstatus=?,lastopstatus=?,descr=?
            where orderid=?
            and username=?
            and returnstatus='locked'
            and (voidstatus is NULL or voidstatus ='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
      my @dbvalues = ( "$finalstatus", "$finalstatus", "$respcode: $errmsg{$respcode}", "$orderid", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      $unlinkarray{$batchfilename} = 1;

    } else {
      $outfilestr .= "$line\n";
    }

  }

  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear", "$filename.done", "write", "", $outfilestr );

  unlink "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear/$filename";
}

exit;

sub checkdir {
  my ($date) = @_;

  my $printstr = "checking $date\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

  $fileyear = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 );
  $filemonth = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 );
  $fileyearonly = substr( $date, 0, 4 );

  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyearonly" ) {
    my $printstr = "creating $fileyearonly\n";
    &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsdebit/$fileyearonly");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsdebit/$filemonth" ) {
    my $printstr = "creating $filemonth\n";
    &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsdebit/$filemonth");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear" ) {
    my $printstr = "creating $fileyear\n";
    &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear" ) {
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear" ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdmsdebit - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Couldn't create directory logs/fdmsdebit/$fileyear.\n\n";
    close MAILERR;
    exit;
  }

}

