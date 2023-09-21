#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;

$time = time();
( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $d8, $d9, $modtime ) = stat "/home/pay1/batchfiles/logs/telecheck/accesstime.txt";

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

my $printstr = "delta: $delta\n";
&procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

if ( $delta > 120 ) {
  $line = `\ps -e -o'pid args' | grep 'telecheckserver.pl' | grep -v grep | grep -v vim`;
  my $printstr = "line: $line\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'telecheckserver.pl'`;
my $printstr = "cnt: $cnt\n";
&procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
if ( $cnt < 1 ) {
  exec 'batchfiles/prod/telecheck/telecheckserver.pl';
}

exit;

