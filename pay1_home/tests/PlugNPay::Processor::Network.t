#!/usr/bin/perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use Test::More qw( no_plan );
use PlugNPay::Processor::Network;

my $network = new PlugNPay::Processor::Network({'processor' => 'fdmslcr'});

is($network->getNetworkName('06'), 'PULSE');
is($network->getNetworkName('00'), 'Other');
is($network->getNetworkName('ZZ'), 'Star');
