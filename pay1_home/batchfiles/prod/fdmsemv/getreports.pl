#!/usr/local/bin/perl

use lib '/home/p/pay1/perl_lib';

use fdmsemv;

my $username    = "testfdmsemv";
my $terminalnum = "00001";

my $result = &fdmsemv::getreport( "$username", "$terminalnum", "emvparams" );
open( OUTFILE, ">/home/p/pay1/batchfiles/fdmsemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

$result = &fdmsemv::getreport( "$username", "$terminalnum", "publickeys" );
open( OUTFILE, ">>/home/p/pay1/batchfiles/fdmsemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

$result = &fdmsemv::getreport( "$username", "$terminalnum", "statistics" );
open( OUTFILE, ">>/home/p/pay1/batchfiles/fdmsemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

$result = &fdmsemv::getreport( "$username", "$terminalnum", "offlinedecline" );
open( OUTFILE, ">>/home/p/pay1/batchfiles/fdmsemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

$result = &fdmsemv::getreport( "$username", "$terminalnum", "transaction" );
open( OUTFILE, ">>/home/p/pay1/batchfiles/fdmsemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

exit;

