package PlugNPay::AWS::S3::Object;

use strict;

use JSON::XS;
use XML::Simple;
use PlugNPay::Die;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use Encode qw(encode decode);
use PlugNPay::AWS::ParameterStore qw(getParameter);
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::AWS::S3::Object::ObjectProxy;

our $__serviceURL;

sub new {
  my $class = shift;
  my $self;
  my $bucketName = shift;

  $self = new PlugNPay::AWS::S3::Object::ObjectProxy($bucketName);

  return $self;
}

1;
