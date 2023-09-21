#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use Data::UUID;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);

require_ok('PlugNPay::WebDataFile');

my $wdf = new PlugNPay::WebDataFile();

SKIP: {
  skipIntegration("skipping billpayLite S3 write tests for WebDataFile",1);

  my $fileToUpload;
  if (INTEGRATION) {
    my $filename = 'pnpdemo_template.txt';
    my $uuid = new Data::UUID()->create_str();

    # create local file to upload...
    my $storageInfo = $wdf->getStorageInfo('billpayLite');
    my ($fh, $buffer);
    my $uploadContent = '• Some utf-8 stuff here • :' . $uuid;
    open($fh,'>',$storageInfo->{'localPath'} . '/' . $filename);
    print $fh $uploadContent;
    close($fh);

    # ensure file does not exist in S3, then sleep 2 seconds for eventual consistency
    my $simpleS3 = new PlugNPay::AWS::S3::Object::Simple();
    my $o = $storageInfo->{'prefix'} . $filename;
    $simpleS3->delete({
      bucket => $storageInfo->{'bucket'},
      object => $o
    });
    select undef, undef, undef, 2.0; # accurate sleeping

    # lazily upload file by reading the local file (this is why we needed to delete above)
    $wdf->readFile({ storageKey => 'billpayLite', fileName => $filename });

    # no sleeping needed on object creation :D

    # read file from s3 via Object::Simple
    my $content = $simpleS3->get({
      bucket => $storageInfo->{'bucket'},
      object => $o
    });

    # check to make sure content matches uuid generated for this test
    is($content,$uploadContent,'ensure uploaded content matches the expected content');
  }
}
