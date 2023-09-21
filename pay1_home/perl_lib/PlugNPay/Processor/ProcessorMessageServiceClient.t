#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 1;
use Test::Exception;
use Data::Dumper;

use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::Processor::ProcessorMessageServiceClient');