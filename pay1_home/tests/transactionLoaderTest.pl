#!/bin/env perl

use strict;
use Data::Dumper;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::Loader::History;

my $loader = new PlugNPay::Transaction::Loader();

print Dumper( $loader->load({'username' => 'brytest2','start_time' => '20180315161830', 'end_time' => '20180315161831'}));
