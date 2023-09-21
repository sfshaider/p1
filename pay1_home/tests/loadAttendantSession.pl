#!/bin/env perl
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use Data::Dumper;
use PlugNPay::Recurring::Attendant;

my $attendant = new PlugNPay::Recurring::Attendant();
my $sessionID = '';
$attendant->loadAttendantSession($sessionID);

print Dumper($attendant);
