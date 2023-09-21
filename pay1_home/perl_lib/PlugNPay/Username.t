#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 8;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('PlugNPay::Username');

my $un = new PlugNPay::Username();
$un->setUsername('pnpdemosub');

is($un->isMainLogin(),0,'is not main login for login different than gateway account');
$un->setUsername('pnpdemo');
is($un->isMainLogin(),1,'is main login for login equivilent to gateway account');

# set back to sub for further tests
$un->setUsername('pnpdemosub');




# Integrtion tests, tested when $ENV{'TEST_INTEGRATION'} == "1"
SKIP: {
  # setEmailAddress sanitizes input
  my $emailAddress = '"no\"re<p,ly2"@p>l$u\`%g(np)a:;y.c|"!om,trash@plugnpay.com';
  $un->setSubEmail($emailAddress);
  is($un->getSubEmail(),'"norep,ly2"@plugnpay.com', 'setSubEmail sanitizes input');
  TODO: { # subEmail private variable no longer used, need to figure out a better way to test this
    $un->{'subEmail'} = $emailAddress;
    is($un->getSubEmail(),'"norep,ly2"@plugnpay.com', 'getSubEmail sanitizes output');
  }

  if (!defined $ENV{'TEST_INTEGRATION'} || $ENV{'TEST_INTEGRATION'} ne '1') {
    skip("Skipping database tests because TEST_INTEGRATION environment variable is not '1'", 3);
  }

  # clear subEmail key from object
  my $unDatabase = new PlugNPay::Username();
  is($unDatabase->getSubEmail('pnpdemosub'),'"norep,ly2"@plugnpay.com', 'getSubEmail loads email from database with username input');
  $unDatabase->setUsername('pnpdemosub');
  is($unDatabase->getSubEmail(),'"norep,ly2"@plugnpay.com', 'getSubEmail loads email from database with username set in object');
  ok($unDatabase->exists(),'exists returns truthy value for existant username');

  my $mobiUn = new PlugNPay::Username();
  $un->setUsername('rc_pnpdemo');
  $un->setPassword("abcd1234ABCD5678");
}
