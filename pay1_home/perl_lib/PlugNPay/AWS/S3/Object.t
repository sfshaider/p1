#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);

require_ok('PlugNPay::AWS::S3::Object');

SKIP: {
  skipIntegration("skipping s3 upload test because integration testing is not enabled",2);

  if (INTEGRATION) {
    my $content = '•content•';
    my $bucket = 'plugnpay-dev-test-bucket';
    my $obj = new PlugNPay::AWS::S3::Object($bucket);
    $obj->setContent($content);
    $obj->setContentType('text/plain; charset=utf-8');
    $obj->setObjectName('testObject.txt');
    my $status = $obj->createObject();
    ok($status,'ensure that utf-8 encoded file can be uploaded.');
    my ($readContent,undef) = $obj->readObject();
    is($readContent,$content,'downloaded content matches uploaded content');
  }
}
