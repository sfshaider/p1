#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );

( $d1, $today ) = &miscutils::genorderid();
my $printstr = "\ntoday: $today\n";
&procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

$ttime = &miscutils::strtotime($today);
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 6 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
my $printstr = "yesterday: $yesterday\n";
&procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime( time() );
$todaylocal = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my $dbquerystr = <<"dbEOM";
        select distinct filename
        from batchfilesncb
        where trans_date>=?
        and status='pending'
dbEOM
my @dbvalues = ("$yesterday");
my @sthbatchvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthbatchvalarray) ; $vali = $vali + 1 ) {
  ($filename) = @sthbatchvalarray[ $vali .. $vali + 0 ];

  $files = $files . "$filename ";
}

if ( $files ne "" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: ncb - putfiles problem\n";
  print MAILERR "\n";
  print MAILERR "files: $files\n";
  print MAILERR "putfiles.pl problem. Check ftplog.txt\n\n";
  close MAILERR;
  exit;
}

exit;

