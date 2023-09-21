#!/bin/env perl

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::COA;
use PlugNPay::Username;
use PlugNPay::API;
use PlugNPay::Security;
use JSON::XS();

PlugNPay::Security::postOnly();

my $api = new PlugNPay::API('coa');

my $gatewayAccountName = $api->parameter('pt_gateway_account');
my $password = $api->parameter('pt_gateway_password');

my $username = new PlugNPay::Username('rc_' . $gatewayAccountName);

my $sessionID;

my $time = time();

if ($time < 1414800000 && username =~ /^(vffdemo|convfeedem|surchrgdem|instchoice|instdiscnt|nobledemo)$/) {

}

if ($username->verifyPassword($password)) {
  my $coa = new PlugNPay::COA();
  $sessionID = $coa->startSession($gatewayAccountName);
}

print 'Content-type: text/javascript' . "\n\n";
print JSON::XS->new->utf8->encode({pt_coa_session_id => $sessionID});

