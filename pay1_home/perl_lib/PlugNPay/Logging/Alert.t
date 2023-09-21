#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 7;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use Test::Output;

require_ok('PlugNPay::Logging::Alert');
require_ok('PlugNPay::Util::UniqueID');
require_ok('PlugNPay::DBConnection');

my $testIntegration = $ENV{'TEST_INTEGRATION'} ? 1 : 0;

# set up mocking for tests
my $mock = Test::MockObject->new();

# Mock PlugNPay::DBConnection
my $noQueries = sub {
  print STDERR new PlugNPay::Util::StackTrace()->string("\n") . "\n";
  die('unexpected query executed')
 };
my $dbsMock = Test::MockModule->new('PlugNPay::DBConnection');
$dbsMock->redefine(
'executeOrDie' => $noQueries,
'fetchallOrDie' => $noQueries
);


# test alert to stderr
$dbsMock->redefine(
'executeOrDie' => sub { return }
);

my $alerter = new PlugNPay::Logging::Alert();
stderr_like(sub {
  $alerter->alert(6,"oh no an error");
}, qr/^Processing Error: oh no an error/, "Alert of severity greater than 5 prints to stderr");


$dbsMock->redefine(
'executeOrDie' => $noQueries
);

SKIP: {
  if (!$testIntegration) {
    skip("Skipping database tests because TEST_INTEGRATION environment variable is not a true value", 3);
  }

  # allow database queries for alert testing
  $dbsMock->unmock(
  'executeOrDie','fetchallOrDie'
  );

  # create a uniquely identifiable test alert
  my $alertId = new PlugNPay::Util::UniqueID()->inHex();
  my $alertMessage = "test alert: $alertId";
  $alerter->alert(2,"$alertMessage");

  # check if alert exists in table
  my $alertRowId = $alerter->getAlertRowId();
  isnt($alertRowId,undef,'alert row id is not undefined');
  isnt($alertRowId,'','alert row id is not empty string');

  my $alertData = $alerter->getAlert($alertRowId);
  like($alertData->{'alertDetails'},qr/$alertMessage/, 'loaded alert from id matches expected alert message');

  # end of integration testing, disable queries again
  $dbsMock->redefine(
  'executeOrDie' => $noQueries,
  'fetchallOrDie' => $noQueries
  );
}
