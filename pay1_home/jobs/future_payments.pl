#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Merchant::Customer::FuturePayment;

###############################################
# Job: Future Payments
# ---------------------------------------------
# Description:
#   Future payments are upcoming transactions
#   for a customer. The job will load all
#   pending transactions for the day and 
#   process.

my $futurePayments = new PlugNPay::Merchant::Customer::FuturePayment();
$futurePayments->process();
exit;
