#!/usr/local/bin/perl

use lib '/home/p/pay1/perl_lib';

#use miscutils;
use visanetemv;

my $username = "testptech";

my $result = &visanetemv::getreport( "$username", "emvparams" );
open( OUTFILE, ">/home/p/pay1/batchfiles/visanetemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

$result = &visanetemv::getreport( "$username", "publickeys" );
open( OUTFILE, ">>/home/p/pay1/batchfiles/visanetemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

$result = &visanetemv::getreport( "$username", "statistics" );
open( OUTFILE, ">>/home/p/pay1/batchfiles/visanetemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

$result = &visanetemv::getreport( "$username", "offlinedecline" );
open( OUTFILE, ">>/home/p/pay1/batchfiles/visanetemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

exit;

