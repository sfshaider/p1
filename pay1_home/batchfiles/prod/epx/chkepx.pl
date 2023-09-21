#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};

#use miscutils;

#for ($i=0; $i<=6; $i++) {
$cnt = `ps -ef | grep -v grep | grep -v vim | grep -c 'epx/genfiles.pl'`;
chop $cnt;

open( infile, "/home/pay1/batchfiles/logs/epx/genfiles.txt" );
$username = <infile>;
close(infile);
chop $username;

print "cnt: $cnt  username: $username\n";

# if genfiles is not running and genfiles.txt has a username in it, run genfiles on that group
if ( ( $cnt == 0 ) && ( $username ne "" ) ) {
  print "$username  epx genfiles.pl is not running, restarting...\n";

  print "/home/pay1/batchfiles/prod/epx/genfiles.pl\n";

  #exec "/home/pay1/batchfiles/prod/epx/genfiles.pl";
}

#}

exit;

