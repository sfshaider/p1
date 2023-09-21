#!/bin/env perl
BEGIN {
    $ENV{'DEBUG'} = undef;
}

use strict;
use Test::More tests => 4;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Util::Temp;

require_ok('PlugNPay::PayScreens::Cookie');

# TODO: Add more tests. For now just testing one-time-use id functions

my $oneTimeUseId = 'testOneTimeUseId';

my $data = {
    'cookie'          => '123',
    'decryptedCookie' => '456',
    'cookieIP'        => '127.0.0.1',
    'remoteIP'        => '127.0.0.1',
    'cookieTime'      => '60',
    'validationTime'  => '120',
    'oneTimeUseId'    => $oneTimeUseId
};

testOneTimeUseIdError($data);
testStoreOneTimeUseId($oneTimeUseId);
testFetchOneTimeUseId($oneTimeUseId);

sub testOneTimeUseIdError {
    my $data = shift;

    # Modify the one-time-use id to make it invalid
    $data->{'oneTimeUseId'} = 'invalidId';

    my $cookie = new PlugNPay::PayScreens::Cookie();
    my $errorMessage = $cookie->validateCookie($data);

    is($errorMessage, 'one-time-use id invalid', 'one-time-use id failure was successful');
}

sub testStoreOneTimeUseId {
    my $id = shift;
    my $cookie = new PlugNPay::PayScreens::Cookie();
    my $status = $cookie->storeOneTimeUseId($id);

    is($status->{_status_}, 1, 'Store one-time-use-id was successful');
}

sub testFetchOneTimeUseId {
    my $id = shift;

    my $cookie = new PlugNPay::PayScreens::Cookie();
    my $status = $cookie->fetchOneTimeUseId($id);

    is($status->{_status_}, 1, 'Fetch one-time-use-id was successful');
}
