#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 4;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use PlugNPay::Testing qw(skipIntegration);
use PlugNPay::GatewayAccount;

require_ok('PlugNPay::Transaction::MapLegacy');

SKIP: {
  if (!skipIntegration('integration testing disabled',2)) {
    my $mapLegacy = new PlugNPay::Transaction::MapLegacy();
    my $gaObject = new PlugNPay::GatewayAccount('pnpdemo');
    my $cardProc = $gaObject->getCardProcessor();
    my $transData = {
      'data'           => {
        'paymentType'   => 'credit',
        'paymentmethod' => 'swipe',
        'processor'     => $cardProc,
        'card-number'   => '4111111111111111',
        'amount'        => 'usd 1.00'
      },
      'gatewayAccount' => 'pnpdemo',
      'operation'      => 'auth',
      'responseData'   => {}
    };

    is($mapLegacy->mapToObject($transData)->getTransactionPaymentType(), 'card', 'MapLegacy::mapToObject returns correct payment type');
    is($mapLegacy->getProcessor('pnpdemo','card'), $cardProc, 'MapLegacy::getProcessor returns correct processor for pnpdemo');
  }
}

# test that map dies when invalid trans object is passed
throws_ok(sub {
  my $mapLegacy = new PlugNPay::Transaction::MapLegacy();
  $mapLegacy->map('not an object','pnpdemo');
},qr/is not a PlugNPay::Transaction/,'map dies on invalid transaction object');