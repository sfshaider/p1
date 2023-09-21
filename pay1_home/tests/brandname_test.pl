#!/bin/env perl
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::CreditCard;

my $cc = new PlugNPay::CreditCard('4111111111111111');

print $cc->getBrandName()  . "\n";

exit;
