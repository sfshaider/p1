#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use lib $ENV{'PNP_PERL_PROCESSOR_LIB'};

use procutils;

$time = time();
my $logProc = 'paytechtampa2';

my $modtime = &procutils::flagread( "$username", "paytechtampa2", "/home/pay1/batchfiles/logs/paytechtampa2", "ptech.txt" );
chop $modtime;

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

system('/home/pay1/batchfiles/prod/paytechtampa2/secondary check');

if ( ( $modtime > 0 ) && ( $delta > 70 ) ) {
  $outfilestr = "";
  $outfilestr .= "aaaa killing ptechserver.pl because delta>70\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/logs/paytechtampa2", "serverlogmsg.txt", "append", "", $outfilestr );
  my $logData = { 'msg' => "$outfilestr" };
  &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

  $line = `\ps -e -o'pid args' | grep ptechserver.pl | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  my $printstr = "pid: $pid\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "serverlogmsg.txt", "append", "misc", $printstr );
  my $logData = { 'pid' => "$pid", 'msg' => "$printstr" };
  &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );
  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'ptechserver.pl'`;

if ( $cnt < 1 ) {
  exec 'batchfiles/prod/paytechtampa2/ptechserver.pl';
}

exit;

