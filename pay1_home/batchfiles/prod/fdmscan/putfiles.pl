#!/usr/local/bin/perl

$| = 1;

use lib '/home/p/pay1/perl_lib';
use Net::SFTP::Foreign;
use Net::SFTP::Foreign::Constants qw(:flags);

use Net::SFTP::Util;
use miscutils;

# passwd  prod

#Name:   www.mftcat.firstdataclients.com
#Address: 216.66.216.10

$fdmsaddr = "test2-gw-na.firstdataclients.com";    # test server

#$fdmsaddr = "prod-gw-na.firstdataclients.com";  # production server
$port = 6522;
$host = "processor-host";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = substr( "000" . $julian, -3, 3 );

( $dummy, $today ) = &miscutils::genorderid();

$mytime = gmtime( time() );
print "\n\ntoday: $mytime    putfiles\n";

if ( ( -e "/home/p/pay1/batchfiles/stopgenfiles.txt" ) || ( -e "/home/p/pay1/batchfiles/fdmscan/stopgenfiles.txt" ) ) {
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdmscan/putfiles.pl'`;
if ( $cnt > 1 ) {
  print "putfiles.pl already running, exiting...\n";
  exit;
}

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/p/pay1/batchfiles/fdmscan/logs/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/p/pay1/batchfiles/fdmscan/logs/$fileyearonly");
}
if ( !-e "/home/p/pay1/batchfiles/fdmscan/logs/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/p/pay1/batchfiles/fdmscan/logs/$filemonth");
}
if ( !-e "/home/p/pay1/batchfiles/fdmscan/logs/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/p/pay1/batchfiles/fdmscan/logs/$fileyear");
}
if ( !-e "/home/p/pay1/batchfiles/fdmscan/logs/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmscan - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory fdmscan/logs/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$dbh = &miscutils::dbhconnect("pnpmisc");

if (1) {

  # clean out batchfiles
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
  my $deletedate = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

  local $sthdel = $dbh->prepare(
    qq{
      delete from batchfilesfdmsc
      where trans_date<'$deletedate'
      }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthdel->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthdel->finish;

  # fdmscan can only send one result at a time
  local $sth_batch2 = $dbh->prepare(
    qq{
      select distinct filename
      from batchfilesfdmsc
      where status='locked'
      and username like 'testfdmscec%'
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

  if ( $filecnt >= 1 ) {
    print "You need to run getfiles.pl successfully before you can run putfiles.pl, exiting\n";
    $dbh->disconnect;

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdmscan - putfiles FAILURE\n";
    print MAILERR "\n";
    print MAILERR "You need to run getfiles.pl successfully before you can run putfiles.pl, exiting\n\n";
    close MAILERR;
    exit;
  }

}

$first_flag = 1;

$mytime = gmtime( time() );
print "$mytime trying to connect to $fdmsaddr $port\n";

my %args = (
  user     => "NAGW-GAGVI001",
  password => 'UXLq4iv62',
  port     => 6522,                                                     # only use with Net::SFTP::Foreign
  more     => [ -i => '/home/p/pay1/batchfiles/fdmscan/.ssh/id_rsa' ]
);

$ftp = Net::SFTP::Foreign->new( "$fdmsaddr", %args );

$ftp->error and die $ftp->error;

if ( $ftp eq "" ) {
  print "Username $ftpun and key don't work<br>\n";
  print "failure";
  exit;
}

$mytime = gmtime( time() );
print "$mytime connected\n";

$line = `netstat -an | grep $fdmsaddr`;
print "cccc $line cccc\n\n";

# xxxx test   username not like 'testfdmscec' for production
local $sth_batch = $dbh->prepare(
  qq{
        select distinct filename,batchheader
        from batchfilesfdmsc
        where status='pending'
        and username like 'testfdmscec%'
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sth_batch->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sth_batch->bind_columns( undef, \( $filename, $fileext ) );

$mycnt = 0;
while ( $sth_batch->fetch ) {
  $mycnt++;
  if ( $mycnt > 5 ) {
    last;
  }

  print "$filename\n";
  my $fileyear = substr( $filename, -14, 4 ) . "/" . substr( $filename, -10, 2 ) . "/" . substr( $filename, -8, 2 );

  print "/home/p/pay1/batchfiles/fdmscan/logs/$fileyear/$filename\n";
  $lines  = `ls -l /home/p/pay1/batchfiles/fdmscan/logs/$fileyear/$filename`;
  $mytime = gmtime( time() );
  print "$mytime bbbb $lines bbbb\n";

  if ( -e "/home/p/pay1/batchfiles/fdmscan/logs/$fileyear/$filename" ) {
    print "before put file   /home/p/pay1/batchfiles/fdmscan/logs/$fileyear/$filename  /RCDMPNPS.$filename.txt\n";
    $ftp->put( "/home/p/pay1/batchfiles/fdmscan/logs/$fileyear/$filename", "/RCDMPNPS.$filename.txt" );    # test and production

    if (0) {
      my $fh2 = $ftp->open( "RCDMPNPS.$filename.txt", SSH2_FXF_WRITE | SSH2_FXF_CREAT ) or die $ftp->error;

      open( infile, "/home/p/pay1/batchfiles/fdmscan/logs/$fileyear/$filename" );
      while (<infile>) {
        my $line = $_;
        $ftp->write( $fh2, $line );
      }
      close(infile);
    }

    $ftp->close($fh2);

    print "after put file\n";
  }

  print "$mytime aaaa $tmpstr\n";

  local $sth_upd = $dbh->prepare(
    qq{
        update batchfilesfdmsc
        set status='locked'
        where status='pending'
        and filename='$filename'
        and username like 'testfdmscec%'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth_upd->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth_upd->finish;

  my $files = $ftp->ls('/')
    or die "unable to retrieve directory: " . $sftp->error;

  if ( @$files == 0 ) {
    print "aa no report files\n";
  }
  foreach $var (@$files) {
    my $yearmonthdec = substr( $filename, 0, 8 );
    my $fname = $var->{"filename"};
    if ( $fname =~ /$yearmonthdec/ ) {
      print "aa " . $var->{"filename"} . "\n";
    }

    $filenm = $var->{"filename"};

  }

  # only do one putfiles for every getfiles
  #last;

  &miscutils::mysleep(60);
}
$sth_batch->finish;

print "\n";

$dbh->disconnect;

exit;

