#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use lib $ENV{'PNP_PERL_PROCESSOR_LIB'};
use procutils;

$time = time();
my @infilestrarray = &procutils::flagread( "buypass", "buypass", "/home/pay1/batchfiles/logs/buypass", "accesstime.txt" );
$modtime = $infilestrarray[0];
chop $modtime;

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

if ( $delta > 70 ) {
  $outfilestr = "";
  $outfilestr .= "aaaa killing buypassserver.pl because delta>70\n";
  &procutils::filewrite( "buypass", "buypass", "/home/pay1/batchfiles/logs/buypass", "serverlogmsg.txt", "append", "", $outfilestr );

  $line = `\ps -e -o'pid args' | grep buypassserver.pl | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  my $printstr = "$pid\n";
  &procutils::filewrite( "buypass", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );
  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'buypassserver.pl'`;
my $printstr = "$cnt\n";
&procutils::filewrite( "buypass", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );
if ( $cnt < 1 ) {
  my $printstr = 'in loop\n';
  &procutils::filewrite( "buypass", "buypass", "/home/pay1/batchfiles/devlogs/buypass", "miscdebug.txt", "append", "misc", $printstr );
  exec 'batchfiles/prod/buypass/buypassserver.pl';
}

exit;

