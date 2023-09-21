#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use lib $ENV{'PNP_PERL_PROCESSOR_LIB'};

use procutils;

$time = time();

my $modtime = &procutils::flagread( "$username", "fdmsomaha", "/home/pay1/batchfiles/logs/fdmsomaha", "accesstime.txt" );
chop $modtime;

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

system('/home/pay1/batchfiles/prod/fdmsomaha/secondary check');

if ( $delta > 120 ) {
  $logfilestr = "";
  $logfilestr .= "delta: $delta  killing fdmsoserver.pl\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/logs/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
  $line = `\ps -e -o'pid args' | grep 'fdmsoserver.pl' | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'fdmsoserver.pl'`;
if ( $cnt < 1 ) {
  exec 'batchfiles/prod/fdmsomaha/fdmsoserver.pl';
}

exit;

