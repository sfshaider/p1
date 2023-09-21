#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Membership::Results;

###############################################
# Job: Membership Results.
# ---------------------------------------------
# Description:
#   After future payments are processed, any
#   recurring set transactions will store the
#   result in a table for this job to process.
#   The job will update the customer billing
#   profile accordingly.

my $results = new PlugNPay::Membership::Results();
$results->processMembership();
exit;
