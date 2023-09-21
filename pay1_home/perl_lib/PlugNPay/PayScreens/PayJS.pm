package PlugNPay::PayScreens::PayJS;

use strict;
use PlugNPay::Util::Hash;
use PlugNPay::AWS::S3::Object::Simple;
use PlugNPay::Logging::DataLog;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub getPayJSHashFileName {
  my $self = shift;

  # If file exists on S3, return hash file name, otherwise return ''
  my $hash = $self->generateHash();
  my $fileName = "pay.$hash.js";

  my $hashFileName = $self->verifyPayJS($fileName) ? $fileName : '';

  return $hashFileName;
}

sub verifyPayJS {
  my $self = shift;
  my $fileName = shift;
  my $verified;

  my $filePath = '/tmp/';
  my $existsSuffix = '.exists';
  my $missingSuffix = '.missing';

  my $exists = $filePath . $fileName . $existsSuffix;
  my $missing = $filePath . $fileName . $missingSuffix;

  if (-e $exists || -e $missing) {
    if (-e $missing) {
      $verified = 0;
    } elsif (-e $exists) {
      $verified = 1;
    }
  } else {
    # no local file exists so check S3 and create local file
    if ($self->existsOnS3($fileName)) {
      $self->createFile($exists);
      $verified = 1;
    } else {
      $self->createFile($missing);
      $verified = 0;
    }
  }

  return $verified;
}

sub existsOnS3 {
  my $self = shift;
  my $fileName = shift;
  my $exists = 0;
  my $js = '';

  my $dev;
  if ($ENV{'DEVELOPMENT'} eq 'TRUE') {
    $dev = '.dev';
  }

  my $bucket = 'static' . $dev . '.gateway-assets.com';
  my $object = '_js/bundle/' . $fileName;

  my $args = {'bucket' => $bucket, 'object' => $object};

  my $s3 = new PlugNPay::AWS::S3::Object::Simple();
  eval {
    ($js) = $s3->get($args);
  };
  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'payjs_bundle' });
    $logger->log({
        'message'      => $fileName . ' cannot be found on S3',
        'errorMessage' => $@
    });
  }

  if ($js ne '') {
    $exists = 1;
  }

  return $exists;
}

sub createFile {
  my $self = shift;
  my $file = shift;
  my $fh;

  open($fh,'>>',$file);
  close($fh);
}

sub generateHash {
  my $self = shift;
  my $hash = new PlugNPay::Util::Hash();
  my $payJSHash;

  my ($fh,$content);
  open($fh,'<','/home/pay1/web/_js/bundle/pay.js');
  sysread $fh, $content, -s $fh;
  close($fh);

  $hash->add($content);
  $payJSHash = $hash->sha256();

  return $payJSHash;
}

1;