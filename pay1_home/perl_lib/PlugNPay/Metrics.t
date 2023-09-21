#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 19;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('PlugNPay::Metrics');

# set up mocking for tests
my $mock = Test::MockObject->new();

my $metricsMock = Test::MockModule->new('PlugNPay::Metrics');

# mock function to load from parameter store
$metricsMock->redefine(
'getParameterStoreHostAndPort' => sub {
  return {
    host => 'statsd-paramstore.local',
    port => '1234'
  };
}
);

my $metrics = new PlugNPay::Metrics();
is($PlugNPay::Metrics::_host_,'statsd-paramstore.local','host is mocked host from ParameterStore');
is($PlugNPay::Metrics::_port_,'1234','port is mocked port from ParameterStore');

# reset _host_ and _port_ so we can check defaults
PlugNPay::Metrics::clearCachedHostAndPort();
# mock function to load from parameter store returning nothing
$metricsMock->redefine(
'getParameterStoreHostAndPort' => sub {
  return {
    host => undef,
    port => undef
  };
}
);

$metrics = new PlugNPay::Metrics();
is($PlugNPay::Metrics::_host_,'statsd.local','host is default host');
is($PlugNPay::Metrics::_port_,'8125','port is default port');

# set ENV vars to load host and port from environment
$ENV{'STATSD_HOST'} = 'statsd-env.local';
$ENV{'STATSD_PORT'} = 9876;
# reset _host_ and _port_ so we can check env
PlugNPay::Metrics::clearCachedHostAndPort();

$metrics = new PlugNPay::Metrics();
is($PlugNPay::Metrics::_host_,'statsd-env.local','host is host from environment');
is($PlugNPay::Metrics::_port_,'9876','port is port from environment');

my $doNothing = sub {};
$metricsMock->redefine(
'_increment' => $doNothing,
'_decrement' => $doNothing,
'_gauge' => $doNothing,
'_timing' => $doNothing
);


# check that bad metric name throws error for increment, decrement, gauge, and timing
throws_ok(sub {
  my $m = new PlugNPay::Metrics();
  $m->increment({
    metric => 'this is a bad metric name',
    value => 5
  })
},qr/^bad metric name/,'bad metric name throws error on increment');

throws_ok(sub {
  my $m = new PlugNPay::Metrics();
  $m->decrement({
    metric => 'this is a bad metric name',
    value => 5
  })
},qr/^bad metric name/,'bad metric name throws error on decrement');

throws_ok(sub {
  my $m = new PlugNPay::Metrics();
  $m->gauge({
    metric => 'this is a bad metric name',
    value => 5
  })
},qr/^bad metric name/,'bad metric name throws error on gauge');

throws_ok(sub {
  my $m = new PlugNPay::Metrics();
  $m->timing({
    metric => 'this is a bad metric name',
    value => 5
  })
},qr/^bad metric name/,'bad metric name throws error on timing');


# check that bad value throws error for increment, decrement, gauge, and timing
throws_ok(sub {
  my $m = new PlugNPay::Metrics();
  $m->increment({
    metric => 'this.is.a.good.metric.name',
    value => -1
  })
},qr/^value must be unsigned integer/,'bad value throws error on increment');

throws_ok(sub {
  my $m = new PlugNPay::Metrics();
  $m->decrement({
    metric => 'this.is.a.good.metric.name',
    value => -1
  })
},qr/^value must be unsigned integer/,'bad value throws error on decrement');

throws_ok(sub {
  my $m = new PlugNPay::Metrics();
  $m->gauge({
    metric => 'this.is.a.good.metric.name',
    value => '-10.b'
  })
},qr/^value must be numeric/,'bad value throws error on gauge');

throws_ok(sub {
  my $m = new PlugNPay::Metrics();
  $m->timing({
    metric => 'this.is.a.good.metric.name',
    value => -1
  })
},qr/^value must be unsigned integer/,'bad value throws error on timing');

# check various metric names
throws_ok(sub {
  PlugNPay::Metrics::checkMetric('.');
},qr/^bad metric name/,'metric name may not be a period');

throws_ok(sub {
  PlugNPay::Metrics::checkMetric('.bad');
},qr/^bad metric name/,'metric name may not start with a period');

throws_ok(sub {
  PlugNPay::Metrics::checkMetric('bad.');
},qr/^bad metric name/,'metric name may not end with a period');

lives_ok(sub {
  PlugNPay::Metrics::checkMetric('this.is.ok');
},'metric may begin and end with alphanumeric and contain periods');
