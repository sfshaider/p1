#!/usr/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use smpsutils;
use Data::Dumper;

# get  record from pnpdata

my $result1 = smpsutils::details('chrisinc',{ order-id => 2016033020482405227, suppressAlert => 1 });
print STDERR "result1=" . Dumper($result1);

my $result2 = smpsutils::unmark('chrisinc',{ order-id => 2016033020482405227, suppressAlert => 1 });
print STDERR "result2=" . Dumper($result2);
