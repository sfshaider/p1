#!/bin/env perl

use strict;
use warnings;
use Test::More tests => 8;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

use PlugNPay::Testing;
use PlugNPay::Util::Array qw(inArray);

require_ok('PlugNPay::Transaction::IpList');

my $ipl = new PlugNPay::Transaction::IpList();

SKIP: {
  my $testIp = $ARGV[0] || '127.0.0.1';

  if (!skipIntegration("skipping tests to call service because integration testing is not enabled",5)) {
    # clear info for localhost ip
    $ipl->deleteIpInfo({ ip => $testIp } );

    # get default info for an ip
    my $ipi = $ipl->getIpInfo({ ip => $testIp } );
    is($ipi->recommendation(),'allow','default recommendation is allow');

    # add 10 negative results
    for (my $i = 0; $i < 10; $i++) {
      $ipl->updateIpInfo({ 
        ip => $testIp,
        status => 'negative',
        reason => 'bad transaction'
      });
    }

    $ipi = $ipl->getIpInfo({ ip => $testIp } );
    is($ipi->recommendation(),'deny','after 10 negatives, recommendation is deny');

    # add 11 positive results
    for (my $i = 0; $i < 11; $i++) {
      $ipl->updateIpInfo({ 
        ip => $testIp,
        status => 'positive',
        reason => 'bad transaction'
      });
    }

    $ipi = $ipl->getIpInfo({ ip => $testIp } );
    is($ipi->recommendation(),'allow','after adding 11 positives, recommendation is allow, because number of positives > negatives');

    # add 2 negative results
    for (my $i = 0; $i < 2; $i++) {
      $ipl->updateIpInfo({ 
        ip => $testIp,
        status => 'negative',
        reason => 'bad transaction'
      });
    }

    $ipi = $ipl->getIpInfo({ ip => $testIp } );
    is($ipi->recommendation(),'deny','after adding two negatives, recommendation is deny again');

    $ipi = $ipl->getIpInfo({ ip => $testIp, getRequests => 1 } );
    my @recent = $ipi->recentRequests();
    isnt(@recent + 0,0,'requesting info with request returns non-empty array');

    my $bl = $ipl->getBlacklist();
    ok(inArray($testIp,$bl),'test ip is in the blacklist');

    # clear info for localhost ip
    $ipl->deleteIpInfo({ ip => $testIp } );
    $bl = $ipl->getBlacklist();
    ok(!inArray($testIp,$bl),'test ip is not in the blacklist after clearing it');

  }
}
