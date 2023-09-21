#!/bin/env perl

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use Net::SFTP::Foreign;
use miscutils;
use procutils;
use File::Copy;

$devprod = "logs";

$ftphost = "206.253.180.37";    #### DCP 20100528 via IN
$host    = "processor-host";

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

my $logProc = "paytechsalem2";
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 60 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;

( $d1, $today, $time ) = &miscutils::genorderid();
$ttime = &miscutils::strtotime($today);
$mmdd = substr( $today, 4, 4 );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 6 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

my $mytime   = gmtime( time() );
my $printstr = "$mytime in getfiles\n";
my $logData = { 'mytime' => "$mytime", 'msg' => "$printstr" };
# &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
&procutils::writeDataLog( $username, $logProc, "ftplog", $logData );

if ( !-e "/home/pay1/batchfiles/$devprod/paytechsalem2/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  my $logData = { 'fileyearonly' => "$fileyearonly", 'msg' => "$printstr" };
  # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
  &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );
  system("mkdir /home/pay1/batchfiles/$devprod/paytechsalem2/$fileyearonly");
  system("chmod go-rwx /home/pay1/batchfiles/$devprod/paytechsalem2/$fileyearonly");
}
if ( !-e "/home/pay1/batchfiles/$devprod/paytechsalem2/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  my $logData = { 'filemonth' => "$filemonth", 'msg' => "$printstr" };
  # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
  &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );
  system("mkdir /home/pay1/batchfiles/$devprod/paytechsalem2/$filemonth");
  system("chmod go-rwx /home/pay1/batchfiles/$devprod/paytechsalem2/$filemonth");
}
if ( !-e "/home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  my $logData = { 'fileyear' => "$fileyear", 'msg' => "$printstr" };
  # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
  &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );
  system("mkdir /home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear");
  system("chmod go-rwx /home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear");
}
if ( !-e "/home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: paytechsalem2 - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/paytechsalem2/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$ftpun = 'pnptec';      # production
$ftppw = 'ikj78tge';    # production

#$ftpun = 'pnptectest';          # test
#$ftppw = 'ajk9lpnf';            # test

$ftpflag = 0;

# xxxx
if ( $redofile eq "" ) {
  if ( $ftpflag == 0 ) {

    $ftp = Net::SFTP::Foreign->new( 'host' => "$ftphost", 'user' => $ftpun, 'password' => $ftppw, 'port' => 22, 'timeout' => 30 );

    $ftp->error and die "cannot connect: " . $ftp->error;
    if ( $ftp eq "" ) {
      my $printstr = "Host $host is no good<br>\n";
      my $logData = { 'msg' => "$printstr" };
      # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
      &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );
      exit;
    }

    my $printstr = "logged in\n";
    my $logData = { 'msg' => "$printstr" };
    # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
    &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );

    $ftpflag = 1;
  }

  if ( $ftp eq "" ) {
    my $printstr = "Host $host is no good<br>\n";
    my $logData = { 'msg' => "$printstr" };
    # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
    &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );
    exit;
  }

  $mode = "A";

  my $ls = $ftp->ls("prod/data/292961");

  my $fn = "";
  if ( @$ls == 0 ) {
    my $printstr = "aa no report files\n";
    my $logData = { 'msg' => "$printstr" };
    # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
    &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );
  }
  my $printstr = "bb " . $var->{"filename"} . "\n";
  my $logData = { 'bb' => $var->{"filename", 'msg' => "$printstr" } };
  # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
  &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );

  foreach my $var (@$ls) {
    $fn = $var->{"filename"};
    if ( $fn !~ /.out/ ) {
      next;
    }
    my $printstr = "aa var: $fn\n";
    my $logData = { 'aaVar' => "$fn", 'msg' => "$printstr" };
    # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
    &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );
    (@list) = ( @list, $fn );

    $templen = length($fn);
    if ( $templen < 4 ) {
      next;
    }
    $ftp->get( "prod/data/292961/$fn", "/home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear/$fn" );
    system("chmod go-rwx /home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear/*");

    my $outboxfilestr = $ftp->get_content("prod/data/292961/$fn");

    my $printstr = "status: " . $ftp->status . "\n";
    if ( $ftp->error ) {
      $printstr = "error: " . $ftp->error . "\n";
    }
    $printstr .= "\n";
    my $logData = { 'status' => $ftp->status, 'error' => $ftp->error, 'msg' => "$printstr" };
    # &procutils::filewrite( "paytechsalem2", "accountupd", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
    &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );

    my $fileencstatus = &procutils::fileencwrite( "paytechsalem2", "getfiles", "/home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear", "$fn", "write", "", $outboxfilestr );

    my $outfiletxtstr = "fileencwrite status: $fileencstatus /home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear/$fn\n";    # create a basic file so we know the file is stored in enc area
    my $logData = { 'fileencstatus' => "$fileencstatus", 'directory' => "/home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear/$fn", 'msg' => "$outfiletxtstr" };
    # &procutils::filewrite( "paytechsalem2", "getfiles", "/home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear", "$fn.txt", "write", "", $outfiletxtstr );
    &procutils::writeDataLog( $username, $logProc, "$fn", $logData );

    $newvar = $fn;
    $newvar =~ s/\.out/\.old/g;
    $ftp->rename( "prod/data/292961/$fn", "prod/data/292961/$newvar" );
  }

} else {
  $redofile =~ s/.done//g;
  $fileyear = substr( $redofile, 0, 10 );
  $redofile = substr( $redofile, 11 );

  (@list) = "$redofile";
  my $printstr = "bbbb $redofile\n";
  my $logData = { 'redofile' => "$redofile", 'msg' => "$printstr" };
  # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
  &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );
}

foreach $filename (@list) {
  my $printstr = "$fileyear $filename  /home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear/$filename\n";
  my $logData = { 'fileyear' => "$fileyear", 'filename' => "$filename", 'directory' => "/home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear/$filename", 'msg' => "$printstr" };
  # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
  &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );

  $templen = length($filename);
  if ( $templen < 4 ) {
    next;
  }

  my $infilestr = &procutils::fileencread( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear", "$filename" );
  my @infilestrarray = split( /\n/, $infilestr );

  umask 0077;
  $outfilestr = "";
  $passflag   = 0;
  $failflag   = 0;
  @batchfail  = ();
  foreach (@infilestrarray) {
    $line = $_;
    chop $line;

    if ( $line =~ /^S/ ) {
      ( $d1, $divisionnum, $detailnum, $action, $mop, $acctnum, $exp, $amount, $currency, $respcode, $transtype, $cvv, $tdate, $auth_code, $avs_code, $depositflag, $fraudind, $encflag, $recurringind ) =
        unpack "A1A10A22A2A2A19A4A12A3A3A1A1A6A6A2A1A1A3A2", $line;

      $divisionnum =~ s/^0{4}//g;

      $acctnum =~ s/ //g;
      $xs = "x" x length($acctnum);
      $line =~ s/$acctnum/$xs/;
      $outfilestr .= "$line\n";

      my $printstr = "\ndivisionnum: $divisionnum\n";
      $printstr .= "detailnum: $detailnum\n";
      my $logData = { 'divisionnum' => "$divisionnum", 'detailnum' => "$detailnum", 'msg' => "$printstr" };
      # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
      &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );

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
            and processor='paytechsalem2'
dbEOM
        my @dbvalues = ("$divisionnum");
        ($username) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

        $divarray{"$divisionnum"} = $username;
      } else {
        $username = $divarray{"$divisionnum"};
      }

      if ( $depositflag eq "N" ) {
        open( MAILERR, "| /usr/lib/sendmail -t" );
        print MAILERR "To: cprice\@plugnpay.com\n";
        print MAILERR "From: dcprice\@plugnpay.com\n";
        print MAILERR "Subject: paytechsalem2 - $username FAILURE\n";
        print MAILERR "\n";
        print MAILERR "Batch failed for $username .\n\n";
        print MAILERR "filename: $filename\n\n";
        print MAILERR "division number: $divisionnum\n\n";
        close MAILERR;
      }

      # xxxx
      my $dbquerystr = <<"dbEOM";
          select orderid,filename
          from batchfilessalem
          where detailnum=?
          and username=?
          and trans_date>=?
          and status='locked'
dbEOM
      my @dbvalues = ( "$detailnum", "$username", "$twomonthsago" );
      ( $orderid, $batchfilename ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      my $dbquerystr = <<"dbEOM";
          update batchfilessalem
          set status='done'
          where detailnum=?
          and username=?
          and status='locked'
          and trans_date>=?
dbEOM
      my @dbvalues = ( "$detailnum", "$username", "$twomonthsago" );
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      my $printstr = "username: $username\n";
      $printstr .= "orderid: $orderid\n";
      $printstr .= "detailnum: $detailnum\n";
      $printstr .= "twomonthsago: $twomonthsago\n";
      my $logData = { 'username' => "$username", 'orderid' => "$orderid", 'detailnum' => "$detailnum", 'twomonthsago' => "$twomonthsago", 'msg' => "$printstr" };
      # &procutils::filewrite( "$username", "paytechsalem2", "/home/pay1/batchfiles/$devprod/paytechsalem2", "ftplog.txt", "append", "misc", $printstr );
      &procutils::writeDataLog( $username, $logProc, "ftplog", $logData );

      my $dbquerystr = <<"dbEOM";
            update trans_log
            set finalstatus=?,descr=?
            where orderid=?
            and username=?
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

  unlink "/home/pay1/batchfiles/$devprod/paytechsalem2/$fileyear/$filename";
}

foreach $filename ( keys %unlinkarray ) {
  $year = substr( $filename, 0, 4 );
  unlink "/home/pay1/batchfiles/$devprod/paytechsalem2/$year/$filename";
}

