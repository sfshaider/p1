#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};

$time = time();

open( infile, "/home/p/pay1/batchfiles/logs/fdmsrc/accesstime.txt" );
$modtime = <infile>;
close(infile);
chop $modtime;

if ( $modtime eq "" ) {
  open( infile, "/home/p/pay1/batchfiles/logs/fdmsrc/accesstime.txt" );
  $modtime = <infile>;
  close(infile);
  chop $modtime;
}

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

system('/home/p/pay1/batchfiles/prod/fdmsrc/secondary check');

if ( $delta > 120 ) {
  open( logfile, ">>/home/p/pay1/batchfiles/logs/fdmsrc/serverlogmsg.txt" );
  print logfile "delta: $delta  killing fdmsrcserver.pl\n";
  close(logfile);
  $line = `\ps -e -o'pid args' | grep 'fdmsrcserver.pl' | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'fdmsrcserver.pl'`;
if ( $cnt < 1 ) {
  exec 'batchfiles/prod/fdmsrc/fdmsrcserver.pl';
}

exit;

