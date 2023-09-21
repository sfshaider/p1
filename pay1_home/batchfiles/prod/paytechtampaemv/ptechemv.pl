#!/usr/local/bin/perl

use lib '/home/p/pay1/perl_lib';

$time = time();

open( infile, "/home/p/pay1/batchfiles/paytechtampa/ptechemv.txt" );
$modtime = <infile>;
close(infile);
chop $modtime;

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

system('/home/p/pay1/batchfiles/paytechtampa/secondary check');

if ( ( $modtime > 0 ) && ( $delta > 70 ) ) {
  open( outfile, ">>/home/p/pay1/batchfiles/paytechtampa/temp.txt" );
  print outfile "aaaa killing ptechemvserver.pl because delta>70\n";
  close(outfile);
  $line = `\ps -e -o'pid args' | grep ptechemvserver.pl | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  print "$pid\n";
  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'ptechemvserver.pl'`;
print "$cnt\n";
if ( $cnt < 1 ) {
  print 'in loop\n';
  exec 'batchfiles/paytechtampa/ptechemvserver.pl';
}

exit;

