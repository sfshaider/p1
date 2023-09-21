#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef;
}

use strict;
use Test::More tests => 2;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);

use lib $ENV{'PNP_PERL_LIB'};
require_ok('PlugNPay::Partners::Cardinal::Session');

SKIP: {
  if (!skipIntegration("skipping integration tests", 1)) {
    my $account = 'pnpdemo';
    generateSession($account);
  }
}

sub generateSession {
  my $account = shift;
  my $session = new PlugNPay::Partners::Cardinal::Session();
  my $sessionId = $session->generate($account);
  ok($sessionId ne '', 'session id was created');
}
