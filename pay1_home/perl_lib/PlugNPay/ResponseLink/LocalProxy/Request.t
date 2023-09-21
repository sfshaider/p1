use strict;
use warnings;

use Test::More tests => 4;
use Test::Exception;

require_ok('PlugNPay::ResponseLink::LocalProxy::Request');

my $requestsObj = new PlugNPay::ResponseLink::LocalProxy::Request();

my $method = 'post';
$requestsObj->setMethod($method);
is($requestsObj->getMethod(),$method,'set/get method');

my $url = 'http://example.com';
$requestsObj->setUrl($url);
is($requestsObj->getUrl(),$url,'set/get url');

my $header1Name = 'X-Test-Header';
my $header1Value = 'X-Test-Header-Value';

lives_ok(sub {
  $requestsObj->addHeader($header1Name,$header1Value);
},'addHeader');
