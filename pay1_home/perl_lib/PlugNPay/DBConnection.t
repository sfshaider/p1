#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('PlugNPay::DBConnection');

test_connectTo();

sub test_connectTo {
    # fake creds that will simulate DB connection error
    my $testCredentials = {
        'database' => 'testdb',
        'password' => 'testing',
        'port' => '8443',
        'host' => '127.0.0.1',
        'username' => 'testdb'
    };

    my $error;

    # mock
    my $mockLogger = Test::MockModule->new('PlugNPay::Logging::DataLog');
    $mockLogger->redefine(
        'log' => sub {
            my $logData = shift;
            my $options = shift;

            $error = $logData;
        }
    );

    my $dbs = new PlugNPay::DBConnection();

    # test that dbs connection dies.
    dies_ok( sub { $dbs->_connectTo($testCredentials) });
    # test that logger is logging error when there is a DB connection error. 
    is(defined $error, 1, "error is logged in datalog/database");
}