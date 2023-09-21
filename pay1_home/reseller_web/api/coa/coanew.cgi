#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::COA;
use PlugNPay::API;
use PlugNPay::GatewayAccount;
use PlugNPay::Security;
use JSON::XS();

PlugNPay::Security::postOnly();

my $api = new PlugNPay::API('coa');

my $gatewayAccountName = $api->parameter('pt_gateway_account');;
my $gatewayAccount = new PlugNPay::GatewayAccount($gatewayAccountName);

# Password is only required if doing a direct call to coa.cgi without setting up a session first.
# Not to be used when called from web pages.
# sessionID should be used on subsequent requests for that payment session.
my $password = $api->parameter('pt_gateway_password');

my $sessionID = $api->parameter('pt_coa_session_id');

my $coa = new PlugNPay::COA($gatewayAccountName);

my $results = { status => 'disabled' };

# If password is sent and sessionID is not, then create a new session.
if ($password && !$sessionID) {
  my $remoteUsername = 'rc_' . $gatewayAccountName;
  my $username = new PlugNPay::Username($remoteUsername);
  if ($username->verifyPassword($password)) {
    $sessionID = $coa->startSession();
  }
}

my $bypassSessionCheck = 0;

## Temporary fix until demos are updated to use sessions.  This auto expires on November 1 2014.
my $time = time();
if ($time < 1414800000 && $gatewayAccountName =~ /^(vffdemo|convfeedem|surchrgdem|instchoice|instdiscnt|nobledemo)$/) {
  $bypassSessionCheck = 1;
}
## end of temporary fix.

my $features = $gatewayAccount->getFeatures();
my $cardChargeFeature;
if (defined $features) {
  $cardChargeFeature = $features->get('cardcharge');
}

if ($coa->getEnabled() || $cardChargeFeature) {
  if ($coa->verifySession($sessionID) || $bypassSessionCheck) {
    my $bin =   $api->parameter('pt_card_number');
    if (!defined $bin || $bin eq '') {
      $bin = $api->parameter('bin');
    }
    my $total = $api->parameter('pt_transaction_amount');
    if (!defined $total || $total eq '') {
      $total = $api->parameter('total');
    }

    if (length($bin) < 9) {
      $bin .= '000';
    }

    $results = $coa->get($bin,$total);
    $results->{'status'} = 'enabled';
    $results->{'achEnabled'} = $gatewayAccount->canProcessOnlineChecks();
    $results->{'creditEnabled'} = $gatewayAccount->canProcessCreditCards();
    $results->{'sessionID'} = $sessionID;
  } else {
    $results->{'status'} = 'error';
    $results->{'error'} = 'Invalid Session ID or password.';
  }
}

print 'Access-Control-Allow-Origin: *' . "\n";
print 'Content-type: application/json' . "\n\n";
print JSON::XS->new->utf8->encode($results);

1;
