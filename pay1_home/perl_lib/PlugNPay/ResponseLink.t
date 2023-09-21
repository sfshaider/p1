#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 10;
use Test::Exception;
use Test::MockModule;

use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::ResponseLink');

TODO: { # only works on office vpn until callback in dev is replaced
  testCallbackRequest();
}
testDirectRequest();
testGetRequestTimeout();
test_doRequest();

sub testCallbackRequest {
  my $username = 'pnpdemo';
  my $url = 'http://www.example.org';
  my $contentType = 'text/html';
  my $headerName = 'test-header';
  my $headerValue = 'test-value';

  lives_ok(sub {
    my $rl = new PlugNPay::ResponseLink();

    $rl->setUsername($username);
    $rl->setRequestURL($url);
    $rl->setRequestMethod('GET');
    $rl->setRequestContentType($contentType);
    $rl->setRequestMode('DIRECT');
    $rl->addRequestHeader($headerName,$headerValue);
    $rl->doRequest();

    my $responseContent = $rl->getResponseContent();
    my %responseAPIData = $rl->getResponseAPIData();
  }, 'doRequest does not die for GET via callback server to www.example.org');
}

sub testDirectRequest {
  my $username = 'pnpdemo';
  my $url = 'http://www.example.org';
  my $contentType = 'text/html';
  my $headerName = 'test-header';
  my $headerValue = 'test-value';

  lives_ok(sub {
    my $rl = new PlugNPay::ResponseLink();

    $rl->setUsername($username);
    $rl->setRequestURL($url);
    $rl->setRequestMethod('GET');
    $rl->setRequestMode('DIRECT');
    $rl->setRequestContentType($contentType);
    $rl->addRequestHeader($headerName,$headerValue);
    $rl->doRequest();

    my $responseContent = $rl->getResponseContent();
    my %responseAPIData = $rl->getResponseAPIData();
  }, 'doRequest does not die for direct GET to www.example.org');
}

sub testGetRequestTimeout {
  my $rl = new PlugNPay::ResponseLink();
  my %falseyValues = (
    'empty string' => '',
    'zero string' => '0',
    'zero float' => 0.0,
    'undef' => undef,
    'zero' => 0
  );

  # test that falsey values default to 30
  foreach my $key (keys %falseyValues) {
    $rl->setRequestTimeout($falseyValues{$key});
    cmp_ok($rl->getRequestTimeout(), '==', 30, "timeout defaults to 30 if it is $key");
  }

  # test that the set value was returned
  $rl->setRequestTimeout(100);
  cmp_ok($rl->getRequestTimeout(), '==', 100, "timeout returns correct value that was set");

}

sub test_doRequest {
  my $timeout = 0; 

  # mock 
  my $localProxyMock = Test::MockModule->new('PlugNPay::ResponseLink::LocalProxy::Request');
  $localProxyMock->redefine(
    'setTimeoutSeconds' => sub {
      my $self = shift;
      my $secs = shift;
      $timeout = $secs;
    }
  );

  my $method = 'GET';
  my $url = 'http://www.example.org';
  my $data = {};

  my $rl = new PlugNPay::ResponseLink();

  $rl->_doRequest({
    method => $method,
    url => $url,
    data => $data
  });
  
  cmp_ok($timeout, "==", 30, "time out is set with $timeout seconds");
}