#!/bin/env perl
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use isotables;

use Data::Dumper;
print Dumper \%isotables::currencyUSD840;
exit;
