use strict;
use warnings;

use Test::More tests => 11;
use Test::Exception;

require_ok('PlugNPay::Legacy::SendMServerRequest');

my $smsr = new PlugNPay::Legacy::SendMServerRequest();

my $account = 'pnpdemo';
$smsr->setGatewayAccount($account);
is($smsr->getGatewayAccount(),$account,'set and get for gateway account match');

my $operation = 'auth';
$smsr->setOperation($operation);
is($smsr->getOperation(),$operation,'set and get for operation match');

my $pairs = {'foo' => 'bar','baz' => 'qux'};
$smsr->setPairs($pairs);
is($smsr->getPairs()->{'foo'},'bar','get pairs retains key/value pairs (test 1)');
is($smsr->getPairs()->{'baz'},'qux','get pairs retains key/value pairs (test 2)');

ok(!$smsr->isTestRequest(),'object is not test request by defaut');
$smsr->setTestRequest();
ok($smsr->isTestRequest(),'setTestRequest turns on test request flag');
$smsr->unsetTestRequest();
ok(!$smsr->isTestRequest(),'unsetTestRequest turns off test request flag');

ok(!$smsr->isCertificationRequest(),'object is not certification request by defaut');
$smsr->setCertificationRequest();
ok($smsr->isCertificationRequest(),'setCertificationRequest turns on certification request flag');
$smsr->unsetCertificationRequest();
ok(!$smsr->isCertificationRequest(),'unsetCertificationRequest turns off certification request flag');

