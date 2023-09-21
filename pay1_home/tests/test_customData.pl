#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::Transaction::Logging::CustomData;
use JSON::XS;

my $cd = new PlugNPay::Transaction::Logging::CustomData('dylaninc');
my $data = $cd->loadCustomData(['2018040313094522093','2018040317100709342'],'20180403','20180403');
print encode_json($data) . "\n";


exit;
