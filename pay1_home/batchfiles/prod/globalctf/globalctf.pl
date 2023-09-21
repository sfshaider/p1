#!/usr/local/bin/perl

use lib '/home/p/pay1/perl_lib';

#use miscutils;

$time = time();

#($d1,$d2,$d3,$d4,$d5,$d6,$d7,$d8,$d9,$modtime) = stat "/home/p/pay1/batchfiles/globalctf/accesstime.txt";
open( infile, "/home/p/pay1/batchfiles/globalctf/accesstime.txt" );
$modtime = <infile>;
close(infile);
chop $modtime;

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

#system('/home/p/pay1/batchfiles/globalctf/secondary check');

if ( $delta > 120 ) {
  open( logfile, ">>/home/p/pay1/batchfiles/globalctf/serverlogmsg.txt" );
  print logfile "delta: $delta  killing globalctfserver.pl\n";
  close(logfile);
  $line = `\ps -e -o'pid args' | grep 'globalctfserver.pl' | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'globalctfserver.pl'`;
if ( $cnt < 1 ) {
  exec 'batchfiles/globalctf/globalctfserver.pl';
}

exit;

