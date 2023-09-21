#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use PlugNPay::GatewayAccount;

require_ok('PlugNPay::Processor::Route::LegacyChecks');
my $gaMock = Test::MockModule->new('PlugNPay::GatewayAccount');
$gaMock->redefine(
  'load' => {},
  'getProcessorPackages' => {},
  'getCheckProcessor' => sub { return 'testprocessorach' },
  'getCardProcessor' => sub { return 'testprocessor'}
);

ok(defined PlugNPay::Processor::Route::LegacyChecks::_getProcessorName('pnpdemo', 'credit'),'Testing processor load returns defined value');
