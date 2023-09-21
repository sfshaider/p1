use strict;
use warnings;

use Test::More tests => 8;
use Test::Exception;
use Test::MockModule;

use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::Legacy::BatchMark');
require_ok('PlugNPay::Legacy::SendMServerRequest');

my $bmMock = Test::MockModule->new('PlugNPay::Legacy::BatchMark');

if (!skipIntegration('skipping integration tests',6)) {
  testViaRoute();
}

sub testViaRoute {
  my $_loadResponse;
  my $_markResponse;

  $bmMock->mock(
    _load => sub{
      return $_loadResponse;
    },
    _mark => sub {
      return $_markResponse;
    }
  );

  my $username = 'pnpdemo';
  my $testOrderId = '1234567890';
  # test returning a transaction and mark success
  my $fakeTransaction = new PlugNPay::Transaction('auth','card');
  $fakeTransaction->setProcessorShortName('testprocessor');
  $fakeTransaction->setGatewayAccount($username);
  $fakeTransaction->setTransactionState('AUTH');
  $_loadResponse = {
    $testOrderId => $fakeTransaction
  };

  my $bm = new PlugNPay::Legacy::BatchMark();
  my $pairs = {
    'order-id-1' => $testOrderId,
  };


  my $result = $bm->viaRoute($username,$pairs);
  is($result->{'response-code-1'},'success','response-code-1 is success for viaRoute successful response');
  is($result->{'exception-message-1'},'','exception-message-1 is empty for viaRoute successful response');
  is($result->{'order-id-1'},$testOrderId,'order-id-1 is correct for viaRoute successful response');
  is($result->{'FinalStatus'},'success','FinalStatus is success for viaRoute successful response');
  is($result->{'MStatus'},'success','MStatus is success for viaRoute successful response');
  is($result->{'MErrMsg'},'Post Authorizations Attempted','MErrMsg is "Post Authorizations Attempted" for viaRoute successful response');
}
