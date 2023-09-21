#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 13;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);

require_ok('PlugNPay::AWS::S3::Object::ObjectProxy');

SKIP: {
  skipIntegration("skipping s3 upload test because integration testing is not enabled",12);

  if (INTEGRATION) {
    my $content = '•content•'; # those dots are unicode characters
    my $bucket = 'plugnpay-dev-test-bucket';
    my $objectName = 'testObject.txt';
    my $toObjectName = 'testObject2.txt';
    my $toBucket = 'plugnpay-dev-test-bucket2';
    my $contentType = 'text/plain; charset=utf-8';
    my $obj = new PlugNPay::AWS::S3::Object::ObjectProxy($bucket);
    $obj->setContent($content);
    $obj->setContentType($contentType);
    $obj->setObjectName($objectName);
    $obj->setAcl('public-read');

    # test create
    my $status = $obj->createObject();
    ok($status,'ensure that utf-8 encoded file can be uploaded.');

    # test read
    my ($readContent,$readContentType) = $obj->readObject();
    is($readContent,$content,'downloaded content matches uploaded content');
    is($readContentType,$contentType,'downloaded content type matches uploaded content type');

    # test presigned url
    my $url = $obj->getPresignedURL({
      bucket => $bucket,
      object => $objectName
    });
    like($url,qr/^https:\/\//, 'presigned url looks like a url');

    # test copy
    $status = $obj->copyObject({
      toBucket => $toBucket,
      toObject => $toObjectName
    });

    ok($status,'ensure that file was copied');
    # try to read copy
    my $obj2 = new PlugNPay::AWS::S3::Object::ObjectProxy($toBucket);
    $obj2->setObjectName($toObjectName);
    lives_ok(sub {
      ($readContent,$readContentType) = $obj2->readObject();
    }, 'read of copied file should not die');
    is($readContent,$content,'downloaded content matches source content');
    is($readContentType,$contentType,'downloaded content type matches source content type');
    eval { # delete the object, don't worry about result, we're gonna test that in a moment...
      $obj2->deleteObject();
    };

    # test delete
    $status = $obj->deleteObject();
    ok($status,'ensure that file was deleted.');
    # read should die when object doesn't exist
    dies_ok(sub {
      $obj->readObject();
    }, "ensure that file can no longer be read.");
    is($obj->getContent(),undef,'ensure that on read and object does not exist, object content is undef');
    is($obj->getContentType(),undef,'ensure that on read and object does not exist, object contentType is undef');
  }
}
