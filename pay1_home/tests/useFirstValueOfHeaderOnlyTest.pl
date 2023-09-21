#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

my $test_str = (split(/,/, 'this ,is ,a ,test'))[0];
# splits string on , and returns first element.
$test_str =~ s/^\s+|\s+$//g;


print Dumper($test_str);
print $test_str . "\n";