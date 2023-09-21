#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::COA;
use PlugNPay::API;
use PlugNPay::GatewayAccount;
use PlugNPay::Security;
use PlugNPay::UserDevices;
use JSON::XS();

PlugNPay::Security::postOnly();

my $api = new PlugNPay::API('coa');

my $gatewayAccountName = $api->parameter('pt_gateway_account');;
my $gatewayAccount = new PlugNPay::GatewayAccount($gatewayAccountName);
my $deviceID = $api->parameter('pt_mobile_device_id');

# Password is only required if doing a direct call to coa.cgi without setting up a session first.
# Not to be used when called from web pages.
# sessionID should be used on subsequent requests for that payment session.
my $password = $api->parameter('pt_gateway_password');

my $sessionID = $api->parameter('pt_coa_session_id');

my $coa = new PlugNPay::COA($gatewayAccountName);

my $results = { status => 'disabled' };

# If password is sent and sessionID is not, then create a new session.
# same for deviceID
if ($password ne '' && !$sessionID) {
  my $remoteUsername = 'rc_' . $gatewayAccountName;
  my $username = new PlugNPay::Username($remoteUsername);
  if ($username->verifyPassword($password)) {
    $sessionID = $coa->startSession();
  }
} elsif ($deviceID ne '' && !$sessionID) {
  my $device = new PlugNPay::UserDevices({gatewayAccount => $gatewayAccountName, deviceID => $deviceID});
  if ($device->isApproved()) {
    $sessionID = $coa->startSession();
  }
}

my $magensaData = $api->parameter('pt_magensa');
my $magensaError;
my $decryptedCard;
if ($magensaData) { # encrypted swipe
  my $decryptedData = new PlugNPay::CreditCard->decryptMagensa($magensaData);
  $magensaError = $decryptedData->{'errorMessage'};
  $decryptedCard = $decryptedData->{'card-number'};
}
if ($magensaError ne '') {
  $results->{'error'} = 'magensa failed to decrypt, ' . $magensaError;
  $results->{'status'} = 'error';
}

if ($coa->getEnabled() && $results->{'status'} ne 'error') {
  if (1 || $coa->verifySession($sessionID)) {
    my $bin = $decryptedCard || $api->parameter('pt_card_number') || $api->parameter('bin');
    my $total = $api->parameter('pt_transaction_amount') || $api->parameter('total');
    my $magensaData = $api->parameter('pt_magensa');
    my $magensaError;

    if (length($bin) < 9) {
      $bin .= '000';
      $bin = substr($bin,0,9);
    }

    $results = $coa->get($bin,$total);
    $results->{'status'} = 'enabled';
    $results->{'model'} = $coa->getModel();
    $results->{'achEnabled'} = $gatewayAccount->canProcessOnlineChecks();
    $results->{'creditEnabled'} = $gatewayAccount->canProcessCreditCards();
    $results->{'sessionID'} = $sessionID;
    $results->{'pt_transaction_amount'} = $total;
    $results->{'creditTotalRate'} = sprintf('%.02f',$coa->getCreditTotalRate() * 100.00);
    $results->{'debiTotalRate'}   = sprintf('%.02f',$coa->getDebitTotalRate() * 100.00);
    $results->{'achTotalRate'}    = sprintf('%.02f',$coa->getACHTotalRate() * 100.00);
    $results->{'creditFixedFee'}  = sprintf('%.02f',$coa->getCreditFixedFee());
    $results->{'debitFixedFee'}   = sprintf('%.02f',$coa->getDebitFixedFee());
    $results->{'achFixedFee'}     = sprintf('%.02f',$coa->getACHFixedFee());
  } else {
    $results->{'status'} = 'error';
    $results->{'error'} = 'Invalid Session ID, password, or device ID.';
  }
}

print 'Access-Control-Allow-Origin: *' . "\n";
print 'Content-type: application/json' . "\n\n";
print JSON::XS->new->utf8->encode($results);

1;
