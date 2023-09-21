#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};

$time = time();

open( infile, "/home/p/pay1/batchfiles/logs/fdms/baccesstime.txt" );
$modtime = <infile>;
close(infile);
chop $modtime;

if ( $modtime eq "" ) {
  open( infile, "/home/p/pay1/batchfiles/logs/fdms/baccesstime.txt" );
  $modtime = <infile>;
  close(infile);
  chop $modtime;
}

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

if ( $delta > 120 ) {
  open( logfile, ">>/home/p/pay1/batchfiles/logs/fdms/batchlog.txt" );
  print logfile "delta: $delta\n";
  close(logfile);

  $line = `\ps -e -o'pid args' | grep 'fdmsbserver.pl' | grep -v grep | grep -v vim`;

  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'fdmsbserver.pl'`;

if ( $cnt < 1 ) {
  exec 'batchfiles/prod/fdms/fdmsbserver.pl';
}

exit;

