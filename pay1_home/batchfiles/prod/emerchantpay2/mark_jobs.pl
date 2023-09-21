#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::Updater;

my $updater  = new PlugNPay::Transaction::Updater();
my $response = $updater->updateSettlementJobs();

my $logger = new PlugNPay::Logging::DataLog( { 'collection' => 'new_settlement_jobs' } );
$logger->log( { 'job_result' => $response } );

exit;
