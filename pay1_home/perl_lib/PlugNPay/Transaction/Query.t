#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 1;
use Test::Exception;
use Test::MockModule;
use Time::HiRes;

require_ok('PlugNPay::Transaction::Query');