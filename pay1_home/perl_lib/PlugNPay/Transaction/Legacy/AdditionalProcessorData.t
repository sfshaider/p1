#!/bin/env perl
BEGIN {
    $ENV{'DEBUG'} = undef;
}

use strict;
use Test::More tests => 11;
use Test::Exception;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);
use PlugNPay::Transaction::Legacy::AdditionalProcessorData;

use lib $ENV{'PNP_PERL_LIB'};
require_ok('PlugNPay::Transaction::Legacy::AdditionalProcessorData');

SKIP: {
    skipIntegration("skipping integration tests for saving and loading", 10);

    if (INTEGRATION) {
        testSetAndGet();
    }
}

sub testSetAndGet {
    my $authCode = new PlugNPay::Transaction::Legacy::AdditionalProcessorData({ 'processorId' => '9999' });

    # set fields
    $authCode->setAdditionalDataString('');
    lives_ok ( sub {$authCode->setField('testOne', '123456')}, 'set testOne lives');
    lives_ok ( sub {$authCode->setField('testTwo', '1234567890')}, 'set testTwo lives');
    throws_ok( sub {$authCode->setField('testThree', '12345')}, '/Field value is too long/', 'set testThree dies: Field value is too long');
    lives_ok ( sub {$authCode->setField('testFour', '1234567890')}, 'set testFour lives');
    throws_ok ( sub {$authCode->setField('testTen', '1234567890')}, '/Field information is not defined/', 'set testTen dies: Field information is not defined');

    my $authCodeString = $authCode->getAdditionalDataString();

    # get fields
    $authCode->setAdditionalDataString($authCodeString);
    my $testOne = $authCode->getField('testOne');
    my $testTwo = $authCode->getField('testTwo');
    my $testFour = $authCode->getField('testFour');

    is($testOne, '123456', 'testOne has correct value');
    is($testTwo, '1234567890', 'testTwo has correct value, padding removed');
    is($testFour, '1234567890', 'testFour has correct value, padding removed');
    is(length($authCodeString), 43, 'auth code string length is correct');
    is($authCodeString, '1234561234567890RRRRR  LLLLLLLLLL1234567890', 'auth code string is correct');
}