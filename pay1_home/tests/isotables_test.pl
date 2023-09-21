#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use isotables;

print 'Going thru currency hashes',"\n";
print 'Numeric for USD: ' . $isotables::currencyUSD840{'USD'} . "\n";
print 'Code for 840: ' . $isotables::currency840USD{'840'} . "\n";
print 'USD precision: ' . $isotables::currencyUSD2{'USD'} . "\n";
print '840 precision: ' . $isotables::currency8402{'840'} . "\n\n";


print 'Going thru country hashes',"\n";
print 'Three letter code for US: ' . $isotables::countryUSUSA{'US'} . "\n";
print 'Numeric for US: ' . $isotables::countryUS840{'US'} . "\n";
print 'Two letter code for 840: ' . $isotables::country840US{'840'} . "\n";
print 'End isotable tests',"\n";

exit;
