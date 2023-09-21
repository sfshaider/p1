#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use lib $ENV{'PNP_PERL_PROCESSOR_LIB'};
use procutils;

my $time = time();
my $modtime = &procutils::fileread( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "accesstime2.txt" );
chop $modtime;

my $delta = $time - $modtime;

if ( $delta > 10000 ) {
  sleep(2);
  my $modtime = &procutils::fileread( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "accesstime2.txt" );
  chop $modtime;

  $delta = $time - $modtime;
}

if ( $delta > 120 ) {
  $logfilestr = "";
  $logfilestr .= "delta: $delta  killing ncbservertest2.pl\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );

  $line = `\ps -e -o'pid args' | grep 'ncbservertest2.pl' | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'ncbservertest2.pl'`;
if ( $cnt < 1 ) {
  exec 'batchfiles/prod/ncb/ncbservertest2.pl';
}

exit;

