package PlugNPay::AWS::S3::Object::Simple;

use strict;
use PlugNPay::Die;
use PlugNPay::Logging::DataLog;
use PlugNPay::AWS::S3::Object;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub put {
  my $self = $_[0];
  my $args = $_[1] || $_[0]; #optional args: encType, encKey

  my @required = ('object','bucket','contentType','data');
  my @missingValues = grep { !defined $args->{$_} } @required;

  if (@missingValues > 0) {
    die('Missing value(s) for put: ' . join(',',@missingValues));
  }

  # ensure proper formatting of object key
  $args->{'object'} = cleanObjectKey($args->{'object'});

  my $s3Obj = new PlugNPay::AWS::S3::Object($args->{'bucket'});
  $s3Obj->setObjectName($args->{'object'});
  $s3Obj->setContentType($args->{'contentType'});
  $s3Obj->setContent($args->{'data'});
  $s3Obj->setEncType($args->{'encType'});  # optional, 'AES256' or 'aws:kms'
  $s3Obj->setEncKey($args->{'encKey'});  # optional, include encryption key when using aws:kms as encryption type

  return $s3Obj->createObject();
}

########################################################################################
# optional args: toBucket, toObject                                                    #
# you probably want to send at least one of those, it won't error if you don't though. #
########################################################################################
sub cp {
  my $self = $_[0];
  my $args = $_[1] || $_[0];

  my @required = ('object', 'bucket');
  my @missingValues = grep { $args->{$_} eq '' } @required;

  if (@missingValues > 0) {
    die('Missing value(s) for cp: ' . join(',',@missingValues));
  }

  # ensure proper formatting of object key
  $args->{'object'} = cleanObjectKey($args->{'object'});
  if ($args->{'toObject'}) {
    $args->{'toObject'} = cleanObjectKey($args->{'toObject'});
  }

  my $s3Obj = new PlugNPay::AWS::S3::Object($args->{'bucket'});
  $s3Obj->setObjectName($args->{'object'});

  return $s3Obj->copyObject({ toBucket => $args->{'toBucket'}, toObject => $args->{'toObject'} });
}

sub get {
  return _getOrDelete(@_,'get');
}


sub delete {
  return _getOrDelete(@_,'delete');
}

# same code except for last line and mode must be passed to determine which to call.
sub _getOrDelete {
  my $args = $_[-2];
  my $mode = $_[-1];

  die('mode is not a scalar') if (ref($mode));

  my @required = ('object','bucket');
  my @missingValues = grep { $args->{$_} eq '' } @required;

  if (@missingValues > 0) {
    die('Missing value(s) for ' . $mode . ': ' . join(',',@missingValues));
  }

  # ensure proper formatting of object key
  $args->{'object'} = cleanObjectKey($args->{'object'});

  my $s3Obj = new PlugNPay::AWS::S3::Object($args->{'bucket'});
  $s3Obj->setObjectName($args->{'object'});

  my $return = undef;
  my $contentType = undef;

  if ($mode eq 'get') {
    ($return,$contentType) = $s3Obj->readObject();
  } elsif ($mode eq 'delete') {
    $return = $s3Obj->deleteObject();
  }

  if (wantarray) { # perl magic 🧙‍
    return $return,$contentType;
  }

  return $return; # return!
}

sub cleanObjectKey {
  my $key = shift;

  # do not allow obects to start with a slash
  $key =~ s/^\///;

  if ($key eq '') {
    die('Empty name for Object not allowed.');
  }

  return $key;
}

1;
