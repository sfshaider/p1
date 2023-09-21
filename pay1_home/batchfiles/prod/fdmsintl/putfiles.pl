#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SFTP::Foreign;
use Net::SFTP::Foreign::Constants qw(:flags);
use miscutils;
use procutils;

$devprod = "logs";

#### sftp -oIdentityFile=.ssh/id_rsa -oPort=1022 MSOD-000533@204.194.126.57	# test    old
#### sftp -oIdentityFile=.ssh/id_rsa -oPort=1022 MSOF-000533@204.194.128.58	# production    old

# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI002@test-gw-na.firstdataclients.com     # test
# sftp -oIdentityFile=.sshnew/id_rsa -oPort=6522 NAGW-GAGVI002@test2-gw-na.firstdataclients.com    # test
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI002@prod-gw-na.firstdataclients.com     # prod
# sftp -oIdentityFile=.sshnew/id_rsa -oPort=6522 NAGW-GAGVI002@prod2-gw-na.firstdataclients.com    # prod
#### sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI002@prod2-gw-na.firstdataclients.com # production

#$fdmsaddr = "204.194.126.57";  # test server
#$fdmsaddr = "204.194.128.58";  # production server
#$port = 1022;
$host = "processor-host";

#$fdmsaddr = "test2-gw-na.firstdataclients.com";  # test server
$fdmsaddr = "prod-gw-na.firstdataclients.com";    # production server

#$fdmsaddr = "prod2-gw-na.firstdataclients.com";  # production server
$port = 6522;

# every day at 1:00pm est things don't work
# don't send batches at these times
my ( $mysec, $mymin, $myhour ) = localtime( time() );
$chktime = sprintf( "%02d%02d", $myhour, $mymin );
if ( ( $chktime >= 1255 ) && ( $chktime < 1305 ) ) {
  my $printstr = "It's $chktime, must wait 10 minutes to continue\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
  &miscutils::mysleep(600);

  my ( $mysec, $mymin, $myhour ) = localtime( time() );
  $chktime2 = sprintf( "%02d%02d", $myhour, $mymin );
  $mytime = gmtime( time() );
  umask 0077;
}

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = substr( "000" . $julian, -3, 3 );

( $dummy, $today ) = &miscutils::genorderid();

$mytime = gmtime( time() );
my $printstr = "\n\ntoday: $mytime    putfiles\n";
&procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

if ( ( -e "/home/pay1/batchfiles/$devprod/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/fdmsintl/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdmsintl/putfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "putfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
  exit;
}

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$fileyearonly");
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$filemonth");
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$fileyear");
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsintl - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory fdmsintl/$devprod/$fileyear.\n\n";
  close MAILERR;
  exit;
}

if (1) {

  # clean out batchfiles
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
  my $deletedate = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

  my $dbquerystr = <<"dbEOM";
      delete from batchfilesfdmsi
      where trans_date<?
dbEOM
  my @dbvalues = ("$deletedate");
  &procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  # fdmsintl can only send one result at a time
  my $dbquerystr = <<"dbEOM";
      select distinct filename
      from batchfilesfdmsi
      where status='locked'
      and username not like 'testfdmsi%'
dbEOM
  my @dbvalues = ();
  my @sth_batch2valarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $filecnt = 0;
  for ( my $vali = 0 ; $vali < scalar(@sth_batch2valarray) ; $vali = $vali + 1 ) {
    ($filename) = @sth_batch2valarray[ $vali .. $vali + 0 ];

    my $printstr = "ee $filename\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
    $filecnt++;
  }

  if ( $filecnt >= 1 ) {

    $filefoundflag = 0;
    $filechkcnt    = 0;

    my $printstr = "You need to run getfiles.pl successfully before you can run putfiles.pl, exiting\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdmsintl - putfiles FAILURE\n";
    print MAILERR "\n";
    print MAILERR "You need to run getfiles.pl successfully before you can run putfiles.pl, exiting\n\n";
    close MAILERR;
    exit;
  }

}

$first_flag = 1;

&ftpconnect($fdmsaddr);
my $printstr = "connected\n";
&procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

my $dbquerystr = <<"dbEOM";
        select distinct filename,batchheader
        from batchfilesfdmsi
        where status='pending'
        and username not like 'testfdmsi%'
dbEOM
my @dbvalues = ();
my @sth_batchvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

$mycnt = 0;
for ( my $vali = 0 ; $vali < scalar(@sth_batchvalarray) ; $vali = $vali + 2 ) {
  ( $filename, $fileext ) = @sth_batchvalarray[ $vali .. $vali + 1 ];

  $mycnt++;
  if ( $mycnt > 1 ) {
    last;
  }

  my $printstr = "$filename\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
  my $fileyear = substr( $filename, 0, 4 ) . "/" . substr( $filename, 4, 2 ) . "/" . substr( $filename, 6, 2 );
  my $printstr = "fileyear: $fileyear\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  my $printstr = "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear/$filename\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  my $dbquerystr = <<"dbEOM";
        update batchfilesfdmsi
        set status='locked'
        where status='pending'
        and filename=?
        and username not like 'testfdmsi%'
dbEOM
  my @dbvalues = ("$filename");
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $printstr = "before fileencread /home/pay1/batchfiles/$devprod/fdmsintl/$fileyear/$filename\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  my $msg = &procutils::fileencread( "putfiles", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear", "$filename", "" );

  my $printstr = "after fileencread\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  if ( length($msg) > 60 ) {
    my $printstr = "before put file   /home/pay1/batchfiles/$devprod/fdmsintl/$fileyear/$filename  /$fileext.$filename.txt\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

    $ftp->put_content( "$msg", "/$fileext.$filename.txt" );

    my $printstr = "after put file\n";
    $printstr .= "status: " . $ftp->status . "\n";
    $printstr .= "error: " . $ftp->error . "\n";
    print "$printstr\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
  }

  # note the inbound (RCDMPLGx), outbound (MRDXMPLx) job ids as well as the time in eastern for the transmission team in case of an issue
  my $mrd = "MRDXMPLC";
  if ( $fileext ne "RCDMPLGS" ) {
    $mrd = "MRDXMPL" . substr( $fileext, 7, 1 );
  }
  $OUTFILEstr = "";
  my $savtime = localtime( time() );
  $OUTFILEstr .= "\n\nin case of an issue:\n";
  $OUTFILEstr .= "call to start a ticket then email  l2batchsupport\@firstdata.com  with details\n\n";
  $OUTFILEstr .= "filename: $fileext.$filename.txt\n\n";
  $OUTFILEstr .= "Plug \& Pay did not get an acknowledgement file\n";
  $OUTFILEstr .= "for the last settlement we uploaded. We opened a\n";
  $OUTFILEstr .= "trouble ticket. Here is information that might help\n";
  $OUTFILEstr .= "you find the file in question.\n\n";
  $OUTFILEstr .= "mailbox: NAGW\-GAGVI002\n";
  $OUTFILEstr .= "inbound job name: $fileext\n";
  $OUTFILEstr .= "outbound job name: $mrd\n";
  $OUTFILEstr .= "time: $savtime\n\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/logs/fdmsintl", "ftpissue.txt", "write", "", $OUTFILEstr );

  $mytime = gmtime( time() );
  my $printstr = "$mytime dddd after update batchfilesfdmsi\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  my $ls = $ftp->ls("/");    # can only ls directories
  if ( @$ls == 0 ) {
    my $printstr = "aa no report files\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
  }
  foreach $var (@$ls) {
    my $yearmonthdec = substr( $filename, 0, 8 );
    my $fname = $var->{"filename"};
    if ( $fname =~ /$yearmonthdec/ ) {
      my $printstr = "aa " . $var->{"filename"};
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
      my $printstr = "            bb " . $var->{"longname"} . "\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
    }

    $filenm = $var->{"filename"};
    if ( $filenm =~ /$filename/ ) {

      unlink "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear/$filename" . "sav";
    }
  }

  # only do one putfiles for every getfiles

  &miscutils::mysleep(30);    # was 120
}

my $printstr = "\n";
&procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

exit;

sub ftpconnect {
  my ($fdmsaddr) = @_;

  $mytime = gmtime( time() );
  my $printstr = "$mytime trying to connect to $fdmsaddr $port\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  my %args = (
    user     => "NAGW-GAGVI002",
    password => '5HXm19Etm',
    port     => 6522,
    key_path => '/home/pay1/batchfiles/prod/fdmsintl/.sshnew/id_rsa'
  );

  $ftp = Net::SFTP::Foreign->new( "$fdmsaddr", %args );

  $ftp->error and die "error: " . $ftp->error;

  if ( $ftp eq "" ) {
    my $printstr = "Username $ftpun and key don't work<br>\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
    my $printstr = "failure";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
    exit;
  }

  $mytime = gmtime( time() );
  my $printstr = "$mytime connected\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

}

