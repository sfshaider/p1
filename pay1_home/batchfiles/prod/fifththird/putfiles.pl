#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use Net::SFTP::Foreign;
use Net::SFTP::Foreign::Constants qw(:flags);
use miscutils;

#Prod: mft.ftpsllc.com
#QA: qamft.ftpsllc.com
#UN: PNPTSFTP
#PWD: 8RUspu6eCe6R

$devprod = "logs";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );

( $d1, $today ) = &miscutils::genorderid();
$ttime = &miscutils::strtotime($today);
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 10 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

print "\n\n\nin putfiles.pl\n";
print "$today $yesterday\n\n";

$fileyear = substr( $today, 0, 4 );

#$host = "qamft.ftpsllc.com";	# test
$host = "mft.ftpsllc.com";    # production

#$ftpun = 'PNPT0101';
$ftpun = 'PNPTSFTP';
$ftppw = '8RUspu6eCe6R';

$dbh = &miscutils::dbhconnect("pnpmisc");

# clean out batchfiles
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 180 ) );
my $deletedate = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

local $sthdel = $dbh->prepare(
  qq{
      delete from batchfilesfifth
      where trans_date<'$deletedate'
      }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthdel->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthdel->finish;

#$Net::SFTP::Foreign::debug = -1;

#my %args = (user => "$ftpun", password => "$ftppw", port => 6522,
#            key_path => '/home/pay1/batchfiles/prod/fdmsrctok/.ssh/id_rsa');
#my %args = (user => "$ftpun", password => "$ftppw", more => '-v');
my %args = ( user => "$ftpun", password => "$ftppw" );
$ftp = Net::SFTP::Foreign->new( "$host", %args );

$ftp->error and die "error: " . $ftp->error;

if ( $ftp eq "" ) {
  print "Username $ftpun and key don't work<br>\n";
  print "failure";
  exit;
}

#$Net::SFTP::Foreign::debug = -1;

$mytime = gmtime( time() );
print "$mytime connected\n";

#$ftp = Net::FTP->new("$host", 'Timeout' => 2400, 'Debug' => 1, 'Port' => "21");
#if ($ftp eq "") {
#  print "Host $host is no good<br>\n";
#  exit;
#}

#if ($ftp->login("$ftpun","$ftppw") eq "") {
#  print "Username $ftpun and password don't work<br>\n";
#  exit;
#}
#print "logged in\n";

$mode = "A";

#$ftp->type("$mode");
#$ftp->setcwd("'FTPNPT01'");

#$ftp->setcwd("Inbox") or die "Can't change directory\n";
#my $currentdir = $ftp->cwd();
#print "current dir: $currentdir\n";

local $sthbatch = $dbh->prepare(
  qq{
        select distinct filename
        from batchfilesfifth
        where trans_date>='$yesterday'
        and status='pending'
and username<>'testfifth'
        order by filename
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthbatch->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthbatch->bind_columns( undef, \($filename) );

while ( $sthbatch->fetch ) {
  print "$filename\n";

  $fileyear = substr( $filename, 0, 4 );
  $fileyear = substr( $filename, 0, 4 ) . "/" . substr( $filename, 4, 2 ) . "/" . substr( $filename, 6, 2 );

  print "put $filename PNPT_R0BCRPNP\n";
  $result = $ftp->put( "/home/pay1/batchfiles/$devprod/fifththird/$fileyear/$filename", "PNPT_R0BCRPNP", copy_perm => 0, copy_time => 0 ) or print "put failed: " . $ftp->error . "\n";    # production
  print "result: $result\n";

  my $files = $ftp->ls("/");

  if ( @$files == 0 ) {
    print "aa no report files\n";
  }
  foreach $var (@$files) {
    print "aa " . $var->{"filename"} . "\n";
  }

  if ( $result eq "1" ) {

    #rename "/home/pay1/batchfiles/$devprod/fifththird/$fileyear/$filename", "/home/pay1/batchfiles/$devprod/fifththird/$fileyear/$filename" . "sav";
    unlink "/home/pay1/batchfiles/$devprod/fifththird/$fileyear/$filename";
  }

  #$ftp->rename("home/292961/t$filename","home/292961/p$filename");

  local $sthupd = $dbh->prepare(
    qq{
        update batchfilesfifth
        set status='locked'
        where trans_date>='$yesterday'
        and status='pending'
        and filename='$filename'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthupd->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthupd->finish;
  last;
}
$sthbatch->finish;

#$ftp->quit;

$dbh->disconnect;

print "\n\n";

exit;

