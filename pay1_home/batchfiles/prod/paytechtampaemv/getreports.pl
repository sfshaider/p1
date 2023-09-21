#!/usr/local/bin/perl

use lib '/home/p/pay1/perl_lib';

use paytechtampaemv;

my $username = "testptechus";

my $result = &paytechtampaemv::getreport( "$username", "emvparams" );
open( OUTFILE, ">/home/p/pay1/batchfiles/paytechtampaemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

$result = &paytechtampaemv::getreport( "$username", "publickeys" );
open( OUTFILE, ">>/home/p/pay1/batchfiles/paytechtampaemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

$result = &paytechtampaemv::getreport( "$username", "statistics" );
open( OUTFILE, ">>/home/p/pay1/batchfiles/paytechtampaemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

$result = &paytechtampaemv::getreport( "$username", "offlinedecline" );
open( OUTFILE, ">>/home/p/pay1/batchfiles/paytechtampaemv/reports.txt" );
print OUTFILE "$result\n";
close(OUTFILE);

exit;

