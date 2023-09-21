#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 7;
use Test::Exception;
use Test::MockModule;
use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::GatewayAccount::InternalID');

my $iid = new PlugNPay::GatewayAccount::InternalID();

SKIP: {
  if ( !skipIntegration( 'skipping integration tests', 8 ) ) {
    my $username = 'testxyzabcd';
    $iid->_deleteTestData($username);

    my $pnpMiscCustomerId  = $iid->getPNPMiscCustomerId($username);
    my $pnpTransMerchantId = $iid->getPNPTransactionMerchantId($username);
    is( $pnpMiscCustomerId, $pnpTransMerchantId, 'pnpMiscCustomerId and pnpTransactionMerchantId are equivilent' );

    $iid->_deleteTestCacheData( $username, $pnpMiscCustomerId );

    my $pnpMiscCustomerUsername  = $iid->getPNPMiscCustomerFromId($pnpMiscCustomerId);
    my $pnpTransCustomerUsername = $iid->getPNPTransactionMerchantFromId($pnpTransMerchantId);

    is( $pnpMiscCustomerUsername, $pnpTransCustomerUsername, 'pnpMiscCustomerUsername and pnpTransactionCustomerUsername are equivilent' );

    # test old function names
    my $oldIdFromUsername = $iid->getIdFromUsername($username);
    is( $pnpMiscCustomerId, $oldIdFromUsername, 'getIdFromUsername returns the same value as getPNPMiscCustomerId' );

    my $oldUsernameFromId = $iid->getUsernameFromId($pnpMiscCustomerId);
    is( $pnpMiscCustomerUsername, $oldUsernameFromId, 'getUsernameFromId returns the same value as getPNPMiscCustomerFromId' );

    my $oldMerchantId = $iid->getMerchantID($username);
    is( $pnpMiscCustomerId, $oldMerchantId, 'getMerchantID returns the same value as getPNPTransactionMerchantId' );

    my $oldMerchantName = $iid->getMerchantName($pnpMiscCustomerId);
    is( $pnpMiscCustomerUsername, $oldMerchantName, 'getMerchantName returns the same value as getPNPTransactionMerchantFromId' );

  }
}
