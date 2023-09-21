#!/bin/env perl
BEGIN {
    $ENV{'DEBUG'} = undef;
}

use strict;
use Test::More tests => 8;
use PlugNPay::PayScreens::PayJS;
use lib $ENV{'PNP_PERL_LIB'};

require_ok('PlugNPay::PayScreens::PayJS');

testVerifyPayJS();
testExistsOnS3();
testCreateFile();
testGenerateHash();

sub testVerifyPayJS {
    my $payJS = new PlugNPay::PayScreens::PayJS;

    # test local .exists file exists
    $payJS->createFile('/tmp/e.exists');
    is($payJS->verifyPayJS('e'), 1, '.exists file exists');

    # test local .missing file exists
    $payJS->createFile('/tmp/m.missing');
    is($payJS->verifyPayJS('m'), 0, '.missing file exists');

    # test s3 file exists
    is($payJS->verifyPayJS('pay.js'), 1, 'file exists on S3');

    # test s3 file missing
    is($payJS->verifyPayJS('nope'), 0, 'file missing on S3');
}

sub testExistsOnS3 {
    my $objectName = 'pay.js';
    my $payJS = new PlugNPay::PayScreens::PayJS;

    is($payJS->existsOnS3($objectName), 1, 'object exists on S3');
}

sub testCreateFile {
    my $file = '/tmp/testing123';

    my $payJS = new PlugNPay::PayScreens::PayJS;
    $payJS->createFile($file);

    ok(-e $file, 'file was created');
}

sub testGenerateHash {
    my $payJS = new PlugNPay::PayScreens::PayJS;
    my $length = 64;
    my $hash = $payJS->generateHash();

    is(length($hash), $length, 'hash length is correct');
}