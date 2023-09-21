#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 1;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('PlugNPay::Token::Client');
