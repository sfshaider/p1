#!/bin/env perl

use strict;
use warnings FATAL => 'all';
use Test::More tests => 9;
use Test::Exception;
use Data::Dumper;

use Test::MockModule;

require_ok('PlugNPay::Transaction');
require_ok('PlugNPay::Partners::AuthVia::Pending');

testPostTransactionToAuthViaService();
testBuildAuthViaRequestJson();

sub testPostTransactionToAuthViaService {
  my $transaction = new PlugNPay::Transaction('auth','credit');
  my $conversationId = 'abcd1234efgh5678ijkl';

  # test die on missing conversation id
  dies_ok(sub {
    PlugNPay::Partners::AuthVia::Pending::postTransactionToAuthViaService({
      transaction => $transaction
    });
  }, 'postTransactionToAuthViaService dies when conversation id is not sent');

  dies_ok(sub {
    PlugNPay::Partners::AuthVia::Pending::postTransactionToAuthViaService({
      conversationId => $conversationId
    });
  }, 'postTransactionToAuthViaService dies when transaction object is not sent');

  dies_ok(sub {
    PlugNPay::Partners::AuthVia::Pending::postTransactionToAuthViaService({
      conversationId => $conversationId,
      transaction => { justA => 'hash' }
    });
  }, 'postTransactionToAuthViaService dies when transaction input is not a transaction object');
}

sub testBuildAuthViaRequestJson {
  my $transaction = new PlugNPay::Transaction('auth','credit');
  $transaction->setGatewayAccount('pnpdemo');
  my $conversationId = 'abcd1234efgh5678ijkl';

  dies_ok(sub {
    PlugNPay::Partners::AuthVia::Pending::_buildAuthViaRequestJson({
      transaction => $transaction
    });
  }, '_buildAuthViaRequestJson dies when conversation id is not sent');

  dies_ok(sub {
    PlugNPay::Partners::AuthVia::Pending::_buildAuthViaRequestJson({
      conversationId => $conversationId
    });
  }, '_buildAuthViaRequestJson dies when transaction object is not sent');

  dies_ok(sub {
    PlugNPay::Partners::AuthVia::Pending::_buildAuthViaRequestJson({
      conversationId => $conversationId,
      transaction => { justA => 'hash' }
    });
  }, '_buildAuthViaRequestJson dies when transaction input is not a transaction object');

  my $json = PlugNPay::Partners::AuthVia::Pending::_buildAuthViaRequestJson({
      conversationId => $conversationId,
      transaction => $transaction
  });
  like($json,qr/"authViaConversationId":"$conversationId"/, 'conversation id exists in json string');
}