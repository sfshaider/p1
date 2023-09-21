#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use lib $ENV{'PNP_PERL_PROCESSOR_LIB'};

#use miscutils;
use procutils;

$time = time();

#($d1,$d2,$d3,$d4,$d5,$d6,$d7,$d8,$d9,$modtime) = stat "/home/pay1/batchfiles/transid/accesstime.txt";
my $modtime = &procutils::fileread( "$username", "transid", "/home/pay1/batchfiles/logs/transid", "accesstime.txt" );
chop $modtime;

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

if ( $delta > 120 ) {
  $logfilestr = "";
  $logfilestr .= "delta: $delta  killing transidserver.pl\n";
  &procutils::filewrite( "$username", "transid", "/home/pay1/batchfiles/logs/transid", "serverlogmsg.txt", "append", "", $logfilestr );
  $line = `\ps -e -o'pid args' | grep 'transidserver.pl' | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'transidserver.pl'`;
if ( $cnt < 1 ) {
  exec 'batchfiles/prod/transid/transidserver.pl';
}

exit;

