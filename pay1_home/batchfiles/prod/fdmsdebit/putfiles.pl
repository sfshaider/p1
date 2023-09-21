#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SFTP::Foreign;
use Net::SFTP::Foreign::Constants qw(:flags);
use miscutils;
use procutils;

$devprod = "logs";

# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI004@test-gw-na.firstdataclients.com	# test
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI004@test2-gw-na.firstdataclients.com	# test
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI004@prod-gw-na.firstdataclients.com	# prod
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI004@prod2-gw-na.firstdataclients.com	# prod
#### sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI004@prod2-gw-na.firstdataclients.com	# production

# passwd  prod

#Name:   www.mftcat.firstdataclients.com
#Address: 216.66.216.10

#$fdmsaddr = "test2-gw-na.firstdataclients.com";  # test server
$fdmsaddr = "prod2-gw-na.firstdataclients.com";    # production server
$port     = 6522;

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = substr( "000" . $julian, -3, 3 );

( $dummy, $today ) = &miscutils::genorderid();

$mytime = gmtime( time() );
my $printstr = "\n\ntoday: $mytime    putfiles\n";
&procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/fdmsdebit/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdmsdebit/putfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "putfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
  exit;
}

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

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
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsdebit - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory $devprod/fdmsdebit/$fileyear.\n\n";
  close MAILERR;
  exit;
}

# clean out batchfiles
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
my $deletedate = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my $dbquerystr = <<"dbEOM";
      delete from batchfilesfdmsrc
      where trans_date<?
      and processor='fdmsdebit'
dbEOM
my @dbvalues = ("$deletedate");
&procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

# fdmsdebit can only send one result at a time
my $dbquerystr = <<"dbEOM";
      select distinct filename
      from batchfilesfdmsrc
      where status='locked'
      and processor='fdmsdebit'
dbEOM
my @dbvalues = ();
my @sth_batch2valarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

$filecnt = 0;
for ( my $vali = 0 ; $vali < scalar(@sth_batch2valarray) ; $vali = $vali + 1 ) {
  ($filename) = @sth_batch2valarray[ $vali .. $vali + 0 ];

  $filecnt++;
}

if ( $filecnt >= 3 ) {
  my $printstr = "You need to run getfiles.pl successfully before you can run putfiles.pl, exiting\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsdebit - putfiles FAILURE\n";
  print MAILERR "\n";
  print MAILERR "You need to run getfiles.pl successfully before you can run putfiles.pl, exiting\n\n";
  close MAILERR;
  exit;
}

$mytime = gmtime( time() );
my $printstr = "$mytime trying to connect to $fdmsaddr $port\n";
&procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
  my $printstr = "failure";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
  exit;
}

$mytime = gmtime( time() );
my $printstr = "$mytime connected\n";
&procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

# xxxx test   username not like 'testfdmscec' for production
my $dbquerystr = <<"dbEOM";
        select distinct filename
        from batchfilesfdmsrc
        where status='pending'
        and processor='fdmsdebit'
dbEOM
my @dbvalues = ();
my @sth_batchvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

$mycnt = 0;
for ( my $vali = 0 ; $vali < scalar(@sth_batchvalarray) ; $vali = $vali + 1 ) {
  ($filename) = @sth_batchvalarray[ $vali .. $vali + 0 ];

  $mycnt++;
  if ( $mycnt > 2 ) {
    last;
  }

  my $printstr = "$filename\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

  my $fileyear = substr( $filename, 0, 4 ) . "/" . substr( $filename, 4, 2 ) . "/" . substr( $filename, 6, 2 );

  my $printstr = "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear/$filename\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

  $lines  = `ls -l /home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear/$filename.txt`;
  $mytime = gmtime( time() );
  my $printstr = "$mytime bbbb $lines bbbb\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

  if ( -e "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear/$filename.txt" ) {
    my $msg = &procutils::fileencread( "putfiles", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear", "$filename", "" );

    if ( length($msg) > 60 ) {
      my $printstr = "before put file   /home/pay1/batchfiles/$devprod/fdmsdebit/$fileyear/$filename  /CI000405.$filename.txt\n";
      &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

      $ftp->put_content( "$msg", "/CI000405.$filename.txt" );
    }

    my $printstr = "after put file\n";
    $printstr .= "status: " . $ftp->status . "\n";
    $printstr .= "error: " . $ftp->error . "\n";
    print "$printstr\n";
    &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

    # note the inbound job id as well as the time in eastern for the transmission team in case of an issue
    $OUTFILEstr = "";
    my $savtime = localtime( time() );
    $OUTFILEstr .= "\n\nin case of an issue:\n";
    $OUTFILEstr .= "call to start a ticket then email  l2batchsupport\@firstdata.com  with details\n\n";
    $OUTFILEstr .= "filename: /CI000405.$filename.txt\n\n";
    $OUTFILEstr .= "Plug \& Pay did not get an acknowledgement file\n";
    $OUTFILEstr .= "for the last settlement we uploaded. We opened a\n";
    $OUTFILEstr .= "trouble ticket. Here is information that might help\n";
    $OUTFILEstr .= "you find the file in question.\n\n";
    $OUTFILEstr .= "mailbox:          NAGW\-GAGVI004\n";
    $OUTFILEstr .= "inbound job name: CI000405\n";
    $OUTFILEstr .= "time:             $savtime\n\n";
    &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/logs/fdmsdebit", "ftpissue.txt", "write", "", $OUTFILEstr );

    if ( $ftp->error ) {
      print "error, " . $ftp->error . ", exiting...";
      exit;
    }
  }

  my $dbquerystr = <<"dbEOM";
        update batchfilesfdmsrc
        set status='locked'
        where status='pending'
        and filename=?
        and processor='fdmsdebit'
dbEOM
  my @dbvalues = ("$filename");
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $files = $ftp->ls("/");

  if ( @$files == 0 ) {
    my $printstr = "aa no report files\n";
    &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );
  }
  foreach $var (@$files) {
    my $yearmonthdec = substr( $filename, 0, 8 );
    my $fname = $var->{"filename"};

    my $printstr = "aa " . $var->{"filename"} . "\n";
    &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

    $filenm = $var->{"filename"};

  }

  # only do one putfiles for every getfiles
}

my $printstr = "\n";
&procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/$devprod/fdmsdebit", "ftplog.txt", "append", "misc", $printstr );

exit;

