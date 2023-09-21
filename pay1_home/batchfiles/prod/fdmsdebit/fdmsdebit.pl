#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use lib $ENV{'PNP_PERL_PROCESSOR_LIB'};

use procutils;

$time = time();

my $modtime = &procutils::fileread( "$username", "fdmsdebit", "/home/pay1/batchfiles/logs/fdmsdebit", "accesstime.txt" );
chop $modtime;

if ( $modtime eq "" ) {
  $modtime = &procutils::fileread( "$username", "fdmsdebit", "/home/pay1/batchfiles/logs/fdmsdebit", "accesstime.txt" );
  chop $modtime;
}

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

if ( $delta > 120 ) {

  $logfilestr = "";
  $logfilestr .= "delta: $delta  killing fdmsdebitserver.pl\n";
  &procutils::filewrite( "$username", "fdmsdebit", "/home/pay1/batchfiles/logs/fdmsdebit", "serverlogmsg.txt", "append", "", $logfilestr );

  $line = `\ps -e -o'pid args' | grep 'fdmsdebitserver.pl' | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'fdmsdebitserver.pl'`;
if ( $cnt < 1 ) {
  exec 'batchfiles/prod/fdmsdebit/fdmsdebitserver.pl';
}

exit;

