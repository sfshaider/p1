#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use lib $ENV{'PNP_PERL_PROCESSOR_LIB'};

use procutils;

my $time = time();

my @infilestrarray = &procutils::fileread( "$username", "fdmsrctok", "/home/pay1/batchfiles/logs/fdmsrctok", "accesstime.txt" );
$modtime = $infilestrarray[0];
chop $modtime;

if ( $modtime eq "" ) {
  my @infilestrarray = &procutils::fileread( "$username", "fdmsrctok", "/home/pay1/batchfiles/logs/fdmsrctok", "accesstime.txt" );
  $modtime = $infilestrarray[0];
  chop $modtime;
}

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

if ( $delta > 120 ) {

  $logfilestr = "";
  $logfilestr .= "delta: $delta  killing fdmsrctok.pl\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/logs/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

  $line = `\ps -e -o'pid args' | grep 'fdmsrctokserver.pl' | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'fdmsrctokserver.pl'`;
if ( $cnt < 1 ) {
  exec 'batchfiles/prod/fdmsrctok/fdmsrctokserver.pl';
}

exit;

