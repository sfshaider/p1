#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::API;
use PlugNPay::Partners::CardCharge;
use PlugNPay::CreditCard;
use PlugNPay::ConvenienceFee;
use PlugNPay::DBConnection;
use PlugNPay::Security;
use JSON::XS();

# only allow posts;
PlugNPay::Security::postOnly();

my $response = '';

my $api = new PlugNPay::API('conv_fee');

if ($api->parameter('pt_gateway_account') ne '') {
  my $account = $api->parameter('pt_gateway_account');
  my $cf = new PlugNPay::ConvenienceFee($account);
  if ($cf->getEnabled()) {

    # get the buckets
    my $transactionAmount = $api->parameter('pt_transaction_amount');
    if (!defined $transactionAmount || $transactionAmount eq '') {
      $transactionAmount = $api->parameter('total');
    }
    my %result = $cf->getConvenienceFees($transactionAmount);

    # get the card type
    my $bin = $api->parameter('bin');
    if (!defined $bin || $bin eq '') {
      $bin = $api->parameter('pt_card_number');
    }

    my $cc = new PlugNPay::CreditCard($bin);
    $result{'cardCategory'} = $cc->getCardCategory();

    my $adjustmentCategory = $result{'cardCategory'} || $result{'defaultCategory'};

    if (defined $result{'cardCategory'} && defined $result{'fees'}{'credit'}{$result{'cardCategory'}}) {
      $result{'creditAdjustment'} = $result{'fees'}{'credit'}{$result{'cardCategory'}};
    } else {
      $result{'creditAdjustment'} = $result{'fees'}{'credit'}{$result{'defaultCategory'}};
    }

    if (defined $result{'fees'}{'ach'} && defined $result{'fees'}{'ach'}{'standard'}) {
      $result{'achAdjustment'} = $result{'fees'}{'ach'}{'standard'};
    } else {
      $result{'achAdjustment'} = 0.00;
    }

    $result{'pt_transaction_amount'} = $transactionAmount;

    $response = JSON::XS::encode_json(\%result);
  } else {
    $response = JSON::XS::encode_json({ error => 1, errorMessage => 'This account is not configured for convenience fee calculations.'});
  }
} else {
  $response = JSON::XS::encode_json({ error => 1, errorMessage => 'No account supplied.' });
}

print 'Content-type: application/json' . "\n";
print 'Pragma: No-cache' . "\n";
print 'Cache-control: no-cache,no-store' . "\n";
print "\n";
print $response;

PlugNPay::DBConnection::cleanup();



1;
