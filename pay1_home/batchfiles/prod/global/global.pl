#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};

#use miscutils;

$time = time();

#($d1,$d2,$d3,$d4,$d5,$d6,$d7,$d8,$d9,$modtime) = stat "/home/p/pay1/batchfiles/logs/global/accesstime.txt";
open( infile, "/home/p/pay1/batchfiles/logs/global/accesstime.txt" );
$modtime = <infile>;
close(infile);
chop $modtime;

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

system('/home/p/pay1/batchfiles/prod/global/secondary check');

if ( ( $delta > 120 ) && ( $modtime > 0 ) ) {
  open( outfile, ">>/home/p/pay1/batchfiles/logs/global/serverlogmsg.txt" );
  print outfile "aaaa killing globalserver.pl because delta>120 $temp1 $temp2\n";
  close(outfile);
  $line = `\ps -e -o'pid args' | grep globalserver.pl | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  print "$pid\n";
  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'globalserver.pl'`;
print "$cnt\n";
if ( $cnt < 1 ) {
  print 'in loop\n';
  exec 'batchfiles/prod/global/globalserver.pl';
}

exit;

