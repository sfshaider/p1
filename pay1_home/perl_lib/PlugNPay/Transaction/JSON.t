#!/bin/env perl

use strict;
use warnings;
use Test::More tests => 2;
use Test::Exception;
use Test::MockModule;

use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::Transaction::JSON');

# test json gateway account is the name, not the object
SKIP: {
  if (!skipIntegration('skipping integration tests because TEST_INTEGRATION is not 1',1)) {
    my $transaction = new PlugNPay::Transaction('authorization','credit');
    my $ga = new PlugNPay::GatewayAccount();
    $ga->setGatewayAccountName('pnpdemo');
    $transaction->setGatewayAccount($ga);
    my $jsonMapper = new PlugNPay::Transaction::JSON();
    my $json = $jsonMapper->transactionToJSON($transaction);
    if (!is($json->{'gatewayAccount'},'pnpdemo','gatewayAccount in transaction json object is string, not object')) {
      use Data::Dumper; print STDERR Dumper($json);
    }
  }
}
