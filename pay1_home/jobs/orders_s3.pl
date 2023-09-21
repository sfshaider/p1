#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Order::Report;
use PlugNPay::Logging::DataLog;

my $report = new PlugNPay::Order::Report();
eval {
  $report->processBatches();
};

if ($@) {
  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'orders_s3_cron' });
  $logger->log({
    'error' => $@
  });
}

exit;
