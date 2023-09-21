#!/bin/env perl

use lib $ENV{'PNP_PERL_LIB'};
use Data::Dumper;
use PlugNPay::Client::Bluefin;

my $payload = <>;
chomp($payload);
my $bf = new PlugNPay::Client::Bluefin();
$bf->setGatewayAccount('bryaninc');
my $response = $bf->decryptSwipe($payload);
print Dumper $response;
print Dumper $bf;
exit;
