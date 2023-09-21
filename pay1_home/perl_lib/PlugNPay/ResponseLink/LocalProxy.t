use strict;
use warnings;

use Test::More tests => 3;
use Test::Exception;
use Data::Dumper;

use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::ResponseLink::LocalProxy');
require_ok('PlugNPay::ResponseLink::LocalProxy::Request');

SKIP: {
  if (!skipIntegration('skipping integration tests for testing LocalProxy',1)) {
    my $lp = new PlugNPay::ResponseLink::LocalProxy();
    my $req = new PlugNPay::ResponseLink::LocalProxy::Request();
    $req->setUrl('https://www.plugnpay.com');
    $req->setMethod('get');
    my $resp = $lp->do($req);
    if (!is($resp->getStatusCode(),'200','request was successful')) {
      print Dumper({
        req => $req,
        resp => $resp
      });
    }
  }
}

