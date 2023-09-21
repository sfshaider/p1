#!/bin/env perl

use lib $ENV{'PNP_PERL_LIB'};
use strict;
use warnings;
use PlugNPay::AWS::S3::Bucket;

my $bucket = new PlugNPay::AWS::S3::Bucket();
$bucket->setBucketName('plugnpay-an1testbucket');
$bucket->setAccessKeyID('AKIAUMILVUK4EFRQNKHH');
$bucket->setSecretAccessKey('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');
$bucket->setGatewayAccount('paddeninc');

# Test to see if the bucket exists.
my $response = $bucket->bucketExists();
print Dumper $response;

$bucket->createBucket();
