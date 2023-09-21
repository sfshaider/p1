#!/bin/env perl
use lib $ENV{'PNP_PERL_LIB'};
use strict;
use warnings;
use PlugNPay::Util::Status;

my $status = new PlugNPay::Util::Status();
$status->setError("testerr");
print $status->getStackTrace();


1;
