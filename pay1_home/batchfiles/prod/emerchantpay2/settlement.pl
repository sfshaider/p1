#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::Sys::Time;
use PlugNPay::Logging::DataLog;
use PlugNPay::Processor::Process::Settlement;

my $settlement = new PlugNPay::Processor::Process::Settlement();
my $time       = new PlugNPay::Sys::Time();

my $resp = $settlement->settle( $time->inFormat('iso_gm') );

# returns a hash in this format: { $processorID => { $pnpTransID => $responseData}  };

my $logger = new PlugNPay::Logging::DataLog( { 'collection' => 'new_settlement' } );

$logger->log($resp);

exit;
