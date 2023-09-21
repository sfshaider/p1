#!/bin/env perl

use strict;
use Data::Dumper;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::Loader::History;

my $loader = new PlugNPay::Transaction::Loader();
my $historyBuilder = new PlugNPay::Transaction::Loader::History();

my $loaded = $loader->load({'username' => 'scotttestp', 'orderID' =>  '2017121816462425561'})->{'scotttestp'};
my @keys = keys %{$loaded};

my $history = $historyBuilder->buildTransactionHistory($loaded->{$keys[0]});

print Dumper $history;
