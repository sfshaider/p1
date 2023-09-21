#!/bin/env perl

use lib '/home/pay1/batchfiles/perl_lib';
use lib '/home/pay1/batchfiles/perlpr_lib';

use procutils;

$time = time();
my $logProc = "paytechsalem2";

my $modtime = &procutils::fileread( "$username", "paytechsalem2", "/home/pay1/batchfiles/logs/paytechsalem2", "accesstime.txt" );
chop $modtime;

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

system('/home/pay1/batchfiles/prod/paytechsalem2/secondary check');

if ( $delta > 70 ) {
  $outfilestr = "";
  $outfilestr .= "aaaa $time  $modtime  $delta  killing paytechsalem2server.pl because delta>70\n";

  $line = `\ps -e -o'pid args' | grep paytechsalem2server.pl | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  $outfilestr .= "$pid\n";
  my $logData = { 'time' => "$time", 'modtime' => "$modtime", 'delta' => "$delta", 'pid' => "$pid", 'msg' => "$outfilestr" };
  &procutils::writeDataLog( $username, $logProc, "serverlogmsg", $logData );
  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'paytechsalem2server.pl'`;
my $printstr = "$cnt\n";
my $logData = { 'cnt' => "$cnt", 'msg' => "$printstr" };
&procutils::writeDataLog( $username, $logProc, "miscdebug", $logData );

if ( $cnt < 1 ) {
  exec 'batchfiles/processors/paytechsalem2/paytechsalem2server.pl';
}

exit;

