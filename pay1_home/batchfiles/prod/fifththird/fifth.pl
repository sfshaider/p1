#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};

#use miscutils;

$time = time();

#($d1,$d2,$d3,$d4,$d5,$d6,$d7,$d8,$d9,$modtime) = stat "/home/p/pay1/batchfiles/logs/fifththird/accesstime.txt";
open( infile, "/home/p/pay1/batchfiles/logs/fifththird/accesstime.txt" );
$modtime = <infile>;
close(infile);
chop $modtime;

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

system('/home/p/pay1/batchfiles/prod/fifththird/secondary check');

if ( ( $delta > 120 ) && ( $delta < 36000 ) ) {
  open( logfile, ">>/home/p/pay1/batchfiles/logs/fifththird/serverlogmsg.txt" );
  print logfile "delta: $delta  killing fifthserver.pl\n";
  close(logfile);
  $line = `\ps -e -o'pid args' | grep 'fifthserver.pl' | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'fifthserver.pl'`;
if ( $cnt < 1 ) {
  exec 'batchfiles/prod/fifththird/fifthserver.pl';
}

exit;

