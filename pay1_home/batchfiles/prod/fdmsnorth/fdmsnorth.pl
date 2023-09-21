#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};

$time = time();

open( infile, "/home/p/pay1/batchfiles/logs/fdmsnorth/accesstime.txt" );
$modtime = <infile>;
close(infile);
chop $modtime;

if ( $modtime eq "" ) {
  open( infile, "/home/p/pay1/batchfiles/logs/fdmsnorth/accesstime.txt" );
  $modtime = <infile>;
  close(infile);
  chop $modtime;
}

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

system('/home/p/pay1/batchfiles/logs/fdmsnorth/secondary check');

if ( $delta > 120 ) {
  open( logfile, ">>/home/p/pay1/batchfiles/logs/fdmsnorth/serverlogmsg.txt" );
  print logfile "delta: $delta  killing fdmsnorthserver.pl\n";
  close(logfile);
  $line = `\ps -e -o'pid args' | grep 'fdmsnorthserver.pl' | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'fdmsnorthserver.pl'`;
if ( $cnt < 1 ) {
  exec 'batchfiles/prod/fdmsnorth/fdmsnorthserver.pl';
}

exit;

