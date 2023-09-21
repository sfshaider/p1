#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 34;
use Test::Exception;

require_ok('PlugNPay::ResponseLink::LocalProxy::Response');

my $testContent = qq`
{
  "requestId":"949e7c61-a55c-4f89-a1bc-df9079d71273",
  "error":false,
  "errorMessage":null,
  "headers":{
    "Content-Length":["237"],
    "Content-Type":["application/json; charset=utf-8"],
    "Date":["Mon, 11 Jul 2022 00:00:27 GMT"]
  },
  "statusCode":200,
  "status":"Ok",
  "content":"eyJ0ZXN0Ijoic3VjY2VzcyEifQ=="}
`;

my $response = new PlugNPay::ResponseLink::LocalProxy::Response();
$response->_parseJsonBody($testContent);
my $content = $response->getContent();
is($content,'{"test":"success!"}','content decodes successfully');
is($response->getHeader('content-length'),'237','header retrieved successfully');
ok($response->isSuccess(),'response reported successful');
is($response->getStatus(),'200 Ok','status returned successfully');

# test getStatusCode function
testGetStatusCode();

# test getStatusCode function
testIsSuccess();

sub testGetStatusCode {
  my $response = new PlugNPay::ResponseLink::LocalProxy::Response();
  my %falseyValues = (
    'empty string' => '',
    'zero string' => '0',
    'zero float' => 0.0,
    'undef' => undef,
    'zero' => 0
  );

  # test that falsey values default to statusCode = 500
  foreach my $key (keys %falseyValues) {
    $response->{'statusCode'} = $falseyValues{$key};
    is($response->getStatusCode(), 500, "statusCode defaults to 500 if it is $key");
  }

  $response->{'statusCode'} = 200;
  is($response->getStatusCode(), '200', 'statusCode returns correct value if it is a defined value');
};

sub testIsSuccess {
  my $response = new PlugNPay::ResponseLink::LocalProxy::Response();
  my %nonSuccessCodes = (
    'empty string' => '',
    'zero string' => '0',
    'zero float' => 0.0,
    'undef' => undef,
    '500' => 500,
    '501' => 501,
    '502' => 502,
    '503' => 503,
    '400' => 400,
    '401' => 401,
    '402' => 402,
    '403' => 403,
    '404' => 404,
    '301' => 301,
    '302' => 302,
    '303' => 303,
    '304' => 304,
    'zero' => 0
  );

  my %successCodes = (
    '200' => 200,
    '201' => 201,
    '202' => 202,
    '203' => 203,
    '204' => 204,
  );

  # test that isSuccess returns falsey if statusCode != 2XX
  foreach my $key (keys %nonSuccessCodes) {
    $response->{'statusCode'} = $nonSuccessCodes{$key};
    is($response->isSuccess(), '', "isSuccess returns falsey if it is $key");
  }

   # test that isSuccess returns truthy if statusCode =~ 2XX
  foreach my $key (keys %successCodes) {
    $response->{'statusCode'} = $successCodes{$key};
    is($response->isSuccess(), 1, "isSuccess returns truthy if status code == $key");
  }
};