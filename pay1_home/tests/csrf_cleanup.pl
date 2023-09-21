#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Logging::DataLog;
use PlugNPay::Security::CSRFToken;

eval {
  my $csrf = new PlugNPay::Security::CSRFToken();
  $csrf->destroyTokens();
};

if ($@) {
  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'csrf_cleanup_job' });
  $logger->log({
    'error' => $@
  });
};

exit;
