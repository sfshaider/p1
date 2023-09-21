#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;

if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
  exit;
}

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
$twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 8 ) );
$onemonthsago     = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$onemonthsagotime = $onemonthsago . "000000";
$starttransdate   = $onemonthsago - 10000;

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
( $dummy, $today, $todaytime ) = &miscutils::genorderid();

$fileyear = substr( $today, 0, 4 );
if ( !-e "/home/pay1/batchfiles/logs/fdmsintl/$fileyear" ) {
  system("mkdir /home/pay1/batchfiles/logs/fdmsintl/$fileyear");
}
if ( !-e "/home/pay1/batchfiles/logs/fdmsintl/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsintl - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/fdmsintl/$fileyear.\n\n";
  close MAILERR;
  exit;
}

$mytime = gmtime( time() );
open( outfile, ">>/home/pay1/batchfiles/logs/fdmsintl/ftplog.txt" );
print outfile "\n\n$mytime\n";
close(outfile);

for ( $myi = 0 ; $myi <= 30 ; $myi++ ) {

  $cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'fdmsintl/genfiles.pl'`;
  if ( $cnt > 0 ) {
    print "fdmsintl/genfiles.pl running, exiting...\n";
    exit;
  }

  $cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'putget.pl'`;
  if ( $cnt > 1 ) {
    print "putget.pl already running, exiting...\n";
    exit;
  }

  my $dbquerystr = <<"dbEOM";
      select count(distinct(filename))
      from batchfilesfdmsi
      where status in ('pending','locked')
      and username not like 'testfdmsi%'
dbEOM
  my @dbvalues = ();
  my @sth_batch2valarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $filecnt = $sth_batch2valarray[0];

  print "filecnt: $filecnt\n";

  if ( $filecnt == 0 ) {
    exit;
  }

  system("/home/pay1/batchfiles/prod/fdmsintl/putfiles.pl");
  &miscutils::mysleep(120);
  system("/home/pay1/batchfiles/prod/fdmsintl/getfiles.pl");
  &miscutils::mysleep(20);
}

exit;
