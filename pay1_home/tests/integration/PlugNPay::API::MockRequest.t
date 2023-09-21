#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );

use lib $ENV{'PNP_PERL_LIB'};

require_ok('PlugNPay::API::MockRequest');

testSetMethod();
testSetResource();
testSetHeaders();
testSetContent();

sub testSetMethod {
  my $self = shift;
  my $mr = new PlugNPay::API::MockRequest();

  is($mr->method,'GET','test default method');

  $mr->setMethod('Post');
  is($mr->method,'POST','test set method, mixed case');
}

sub testSetResource {
  my $self = shift;
  my $mr = new PlugNPay::API::MockRequest();
  my $resource = '/api/test/mock';

  $mr->setResource($resource);
  is($mr->the_request,sprintf('GET %s x',$resource),'test resource with no method specified');

  $mr->setMethod('post');
  is($mr->the_request,sprintf('POST %s x',$resource),'test resource with non-default method');
}

sub testSetHeaders {
  my $self = shift;
  my $mr = new PlugNPay::API::MockRequest();
  my $mockHeaders = {
    'mockHeader1' => 'mock value 1',
    'mock-header-2' => 'mock value 2'
  };

  $mr->addHeaders($mockHeaders);
  my $headers = $mr->headers_in;
  foreach my $key (keys %{$mockHeaders}) {
    is($headers->{lc $key},$mockHeaders->{$key},'mock header check for header named ' . $key);
  }
}

sub testSetContent {
  my $self = shift;
  my $mr = new PlugNPay::API::MockRequest();
  my $content = 'this is the mock content';

  $mr->setContent($content);
  is($mr->headers_in->{'content-length'},length($content),'test content length of test content');
  is($mr->mockContent,$content,'test mock content value');
}
