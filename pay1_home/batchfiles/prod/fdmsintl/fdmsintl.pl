#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use lib $ENV{'PNP_PERL_PROCESSOR_LIB'};

use procutils;

$time = time();

my $modtime = &procutils::fileread( "$username", "fdmsintl", "/home/pay1/batchfiles/logs/fdmsintl", "accesstime.txt" );
chop $modtime;

if ( $modtime eq "" ) {
  $modtime = &procutils::fileread( "$username", "fdmsintl", "/home/pay1/batchfiles/logs/fdmsintl", "accesstime.txt" );
  chop $modtime;
}

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

system('/home/pay1/batchfiles/logs/fdmsintl/secondary check');

if ( $delta > 120 ) {
  $logfilestr = "";
  $logfilestr .= "delta: $delta  killing fdmsintlserver.pl\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/logs/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );

  $line = `\ps -e -o'pid args' | grep 'fdmsintlserver.pl' | grep -v grep | grep -v vim`;
  my $printstr = "$line\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'fdmsintlserver.pl'`;
if ( $cnt < 1 ) {
  exec 'batchfiles/prod/fdmsintl/fdmsintlserver.pl';
}

exit;

