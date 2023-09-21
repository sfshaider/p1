#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Batch;
use PlugNPay::Logging::DataLog;

eval {
  my $batches = new PlugNPay::Batch();
  $batches->process();
};

if ($@) {
  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
  $logger->log({
    'job' => 'batch processing',
    'error' => $@
  }); 
}

exit;
