#!/usr/bin/perl


use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::GatewayAccount;
use PlugNPay::Logging::ApacheLogger;
### This test will take care of T51, and T54 ###
### Need to test saving the gateway account object ###
### Need to test inheriting from a parent ga's features ###

my $parent = new PlugNPay::GatewayAccount('dylaninc');
my $ga = new PlugNPay::GatewayAccount('paddeninc');

$ga->inheritFrom($parent->getGatewayAccountName());
$ga->save();







