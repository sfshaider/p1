#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SFTP::Foreign;
use Net::SFTP::Foreign::Constants qw(:flags);
use miscutils;

$devprod = "devlogs";

# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-HRXCW001@test-gw-na.firstdataclients.com	# test
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-HRXCW001@test2-gw-na.firstdataclients.com	# test
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-HRXCW001@prod-gw-na.firstdataclients.com	# prod
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-HRXCW001@prod2-gw-na.firstdataclients.com	# prod
#### sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-HRXCW001@prod2-gw-na.firstdataclients.com	# production

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
print "\n\ntoday: $mytime    putfiles\n";

if ( ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/pay1/batchfiles/$devprod/fdmsrctok/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdmsrctok/putfiles.pl'`;
if ( $cnt > 1 ) {
  print "putfiles.pl already running, exiting...\n";
  exit;
}

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

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
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsrctok - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory $devprod/fdmsrctok/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$dbh = &miscutils::dbhconnect("pnpmisc");

# clean out batchfiles
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
my $deletedate = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

local $sthdel = $dbh->prepare(
  qq{
      delete from batchfilesfdmsrc
      where trans_date<'$deletedate'
      and processor='fdmsrctok'
      }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthdel->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthdel->finish;

# fdmsrctok can only send one result at a time
local $sth_batch2 = $dbh->prepare(
  qq{
      select distinct filename
      from batchfilesfdmsrc
      where status='locked'
      and processor='fdmsrctok'
      }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sth_batch2->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sth_batch2->bind_columns( undef, \($filename) );

$filecnt = 0;
while ( $sth_batch2->fetch ) {
  $filecnt++;
}
$sth_batch2->finish;

if ( $filecnt >= 3 ) {
  print "You need to run getfiles.pl successfully before you can run putfiles.pl, exiting\n";
  $dbh->disconnect;

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsrctok - putfiles FAILURE\n";
  print MAILERR "\n";
  print MAILERR "You need to run getfiles.pl successfully before you can run putfiles.pl, exiting\n\n";
  close MAILERR;
  exit;
}

$mytime = gmtime( time() );
print "$mytime trying to connect to $fdmsaddr $port\n";

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

$mytime = gmtime( time() );
print "$mytime connected\n";

# xxxx test   username not like 'testfdmsrct' for production
local $sth_batch = $dbh->prepare(
  qq{
        select distinct filename
        from batchfilesfdmsrc
        where status='pending'
        and processor='fdmsrctok'
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sth_batch->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sth_batch->bind_columns( undef, \($filename) );

$mycnt = 0;
while ( $sth_batch->fetch ) {
  $mycnt++;
  if ( $mycnt > 2 ) {
    last;
  }

  print "$filename\n";
  my $fileyear = substr( $filename, 0, 4 ) . "/" . substr( $filename, 4, 2 ) . "/" . substr( $filename, 6, 2 );

  print "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$filename\n";
  $lines  = `ls -l /home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$filename`;
  $mytime = gmtime( time() );
  print "$mytime bbbb $lines bbbb\n";

  if ( -e "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$filename" ) {
    print "before put file   /home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$filename  /GPTD5808.$filename.txt\n";
    $ftp->put( "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$filename", "/GPTD5808.$filename.txt", 'copy_perm' => 0, 'copy_time' => 0 ) or die "put failed: " . $ftp->error;
    rename "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$filename", "/home/pay1/batchfiles/$devprod/fdmsrctok/$fileyear/$filename" . "sav";

    # note the inbound (GPTD5808), outbound (xxxxxxxx) job ids as well as the time in eastern for the transmission team in case of an issue
    open( OUTFILE, ">/home/pay1/batchfiles/logs/fdmsrctok/ftpissue.txt" );
    my $savtime = localtime( time() );
    print OUTFILE "\n\nin case of an issue:\n";
    print OUTFILE "call to start a ticket then email  l2batchsupport\@firstdata.com  with details\n\n";
    print OUTFILE "filename: $fileext.$filename.txt\n\n";
    print OUTFILE "Plug \& Pay did not get an acknowledgement file\n";
    print OUTFILE "for the last settlement we uploaded. We opened a\n";
    print OUTFILE "trouble ticket. Here is information that might help\n";
    print OUTFILE "you find the file in question.\n\n";
    print OUTFILE "mailbox: NAGW\-HRXCW001\n";
    print OUTFILE "inbound job name: GPTD5808\n";
    print OUTFILE "outbound job name: xxxxxxxx\n";
    print OUTFILE "time: $savtime\n\n";
    close(OUTFILE);

    print "after put file\n";
  }

  local $sth_upd = $dbh->prepare(
    qq{
        update batchfilesfdmsrc
        set status='locked'
        where status='pending'
        and filename='$filename'
        and processor='fdmsrctok'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth_upd->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth_upd->finish;

  $files = $ftp->ls("/");

  if ( @$files == 0 ) {
    print "aa no report files\n";
  }
  foreach $var (@$files) {
    my $yearmonthdec = substr( $filename, 0, 8 );
    my $fname = $var->{"filename"};
    if ( $fname =~ /$yearmonthdec/ ) {
      print "aa " . $var->{"filename"};
      print "            bb " . $var->{"longname"} . "\n";
    }

    $filenm = $var->{"filename"};
    if ( $filenm =~ /$filename/ ) {

    }
  }

  # only do one putfiles for every getfiles
  last;

}
$sth_batch->finish;

print "\n";

$dbh->disconnect;

exit;

