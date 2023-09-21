#!/usr/local/bin/perl

use lib '/home/p/pay1/perl_lib';

$time = time();

open( infile, "/home/p/pay1/batchfiles/fdmsemv/accesstime.txt" );
$modtime = <infile>;
close(infile);
chop $modtime;

if ( $modtime eq "" ) {
  open( infile, "/home/p/pay1/batchfiles/fdmsemv/accesstime.txt" );
  $modtime = <infile>;
  close(infile);
  chop $modtime;
}

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

system('/home/p/pay1/batchfiles/fdmsemv/secondary check');

if ( $delta > 120 ) {
  open( logfile, ">>/home/p/pay1/batchfiles/fdmsemv/serverlogmsg.txt" );
  print logfile "delta: $delta  killing fdmsemvserver.pl\n";
  close(logfile);
  $line = `\ps -e -o'pid args' | grep 'fdmsemvserver.pl' | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'fdmsemvserver.pl'`;
if ( $cnt < 1 ) {
  exec 'batchfiles/fdmsemv/fdmsemvserver.pl';
}

exit;

