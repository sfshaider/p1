#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::Sys::Time;
use PlugNPay::Transaction::Updater;
use PlugNPay::Processor::Process::Settlement;

my $updater = new PlugNPay::Transaction::Updater();
my $response = $updater->updateSettlementJobs();

my $logger = new  PlugNPay::Logging::DataLog({'collection' => 'new_settlement_jobs'});

my $settlement = new PlugNPay::Processor::Process::Settlement();
my $time = new PlugNPay::Sys::Time();

my $resp = $settlement->settle($time->inFormat('db_gm'));

exit;
