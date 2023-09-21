#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::Util::Encryption::LegacyKey;

############################################
# Generates an encryption key JSON file    #
# Uploads JSON file to S3 encrypted bucket #
############################################

eval {
  my $keyManager = PlugNPay::Util::Encryption::LegacyKey();
  $keyManager->generateMonthlyKey();
};

if ($@) {
  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'encryption_key_job' });
  $logger->log({
    'error' => $@
  });
};

exit;
