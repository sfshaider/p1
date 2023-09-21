#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use lib $ENV{'PNP_PERL_PROCESSOR_LIB'};

use procutils;

$time = time();

my $modtime = &procutils::flagread( "$username", "paytechtampa", "/home/pay1/batchfiles/logs/paytechtampa", "ptech.txt" );
chop $modtime;

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

system('/home/pay1/batchfiles/prod/paytechtampa/secondary check');

if ( ( $modtime > 0 ) && ( $delta > 70 ) ) {
  $outfilestr = "";
  $outfilestr .= "aaaa killing ptechserver.pl because delta>70\n";
  &procutils::filewrite( "$username", "paytechtampa", "/home/pay1/batchfiles/logs/paytechtampa", "serverlogmsg.txt", "append", "", $outfilestr );

  $line = `\ps -e -o'pid args' | grep ptechserver.pl | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  my $printstr = "pid: $pid\n";
  &procutils::filewrite( "$username", "paytechtampa", "/home/pay1/batchfiles/devlogs/paytechtampa", "serverlogmsg.txt", "append", "misc", $printstr );
  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'ptechserver.pl'`;

if ( $cnt < 1 ) {
  exec 'batchfiles/prod/paytechtampa/ptechserver.pl';
}

exit;

