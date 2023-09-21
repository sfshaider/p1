#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use lib $ENV{'PNP_PERL_PROCESSOR_LIB'};

use procutils;

my $time = time();

my @infilestrarray = &procutils::fileread( "$username", "fdmslcr", "/home/pay1/batchfiles/logs/fdmslcr", "accesstime.txt" );
$modtime = $infilestrarray[0];
chop $modtime;

if ( $modtime eq "" ) {
  my @infilestrarray = &procutils::fileread( "$username", "fdmslcr", "/home/pay1/batchfiles/logs/fdmslcr", "accesstime.txt" );
  $modtime = $infilestrarray[0];
  chop $modtime;
}

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

if ( $delta > 120 ) {

  $logfilestr = "";
  $logfilestr .= "delta: $delta  killing fdmslcrserver.pl\n";
  &procutils::filewrite( "$username", "fdmslcr", "/home/pay1/batchfiles/logs/fdmslcr", "serverlogmsg.txt", "append", "", $logfilestr );

  $line = `\ps -e -o'pid args' | grep 'fdmslcrserver.pl' | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'fdmslcrserver.pl'`;
if ( $cnt < 1 ) {
  exec 'batchfiles/prod/fdmslcr/fdmslcrserver.pl';
}

exit;

