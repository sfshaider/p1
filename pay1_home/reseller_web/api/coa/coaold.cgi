#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Environment;
use PlugNPay::InputValidator;
use PlugNPay::Partners::CardCharge;
use JSON::XS();

my $env = new PlugNPay::Environment();

my $features = $env->getFeatures();

my $results = { status => 'disabled' };

my $cardChargeFeature;

if (defined $features) {
  $cardChargeFeature = $features->get('cardcharge');
}

my %query = $env->getQuery('cardcharge');

if (defined $cardChargeFeature && $cardChargeFeature ne '') {

  my $gatewayAccount = new PlugNPay::GatewayAccount($env->get('PNP_ACCOUNT'));
  my $cardCharge = new PlugNPay::Partners::CardCharge();

  $query{'bin'} = (defined $query{'bin'} ? $query{'bin'} : $query{'pt_card_number'});
  $query{'total'} = (defined $query{'total'} ? $query{'total'} : $query{'pt_transaction_amount'});

  if (length($query{'bin'}) < 9) {
    $query{'bin'} .= '000';
  }

  $results = $cardCharge->get($query{'bin'},$query{'total'});
  $results->{'status'} = 'enabled';
  $results->{'achEnabled'} = $gatewayAccount->canProcessOnlineChecks();
  $results->{'creditEnabled'} = $gatewayAccount->canProcessCreditCards();
}

print 'Access-Control-Allow-Origin: *' . "\n";
print 'Content-type: application/json' . "\n\n";
print JSON::XS->new->utf8->encode($results);

1;
