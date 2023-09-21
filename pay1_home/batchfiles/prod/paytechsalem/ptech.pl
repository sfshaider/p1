#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use lib $ENV{'PNP_PERL_PROCESSOR_LIB'};

use procutils;

$time = time();

my $modtime = &procutils::fileread( "$username", "paytechsalem", "/home/pay1/batchfiles/logs/paytechsalem", "accesstime.txt" );
chop $modtime;

$delta = $time - $modtime;
$temp1 = gmtime($time);
$temp2 = gmtime($modtime);

system('/home/pay1/batchfiles/prod/paytechsalem/secondary check');

if ( $delta > 70 ) {
  $outfilestr = "";
  $outfilestr .= "aaaa $time  $modtime  $delta  killing ptechsalemserver.pl because delta>70\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/logs/paytechsalem", "serverlogmsg.txt", "append", "", $outfilestr );

  $line = `\ps -e -o'pid args' | grep ptechsalemserver.pl | grep -v grep | grep -v vim`;
  chop $line;
  $_ = $line;
  s/\s*(\d+)\s//;
  $pid = $1;

  my $printstr = "$pid\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "serverlogmsg.txt", "append", "misc", $printstr );
  if ( $pid >= 1 ) {
    kill 9, $pid;
  }
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'ptechsalemserver.pl'`;
my $printstr = "$cnt\n";
&procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

if ( $cnt < 1 ) {
  exec 'batchfiles/prod/paytechsalem/ptechsalemserver.pl';
}

exit;

