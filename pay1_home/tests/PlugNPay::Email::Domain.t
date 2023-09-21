#!/bin/env perl
use strict;
use warnings;
use diagnostics;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Email::Domain;
use Test::More qw( no_plan );


my $check = new PlugNPay::Email::Domain();

is($check->validate('noreply@plugnpay.com'), 1, 'Test SPF record lookup against plugnpay.com'); 
is($check->validate('noreply@amazon.com'), 0, 'Test SPF record lookup against bad domain'); 
is($check->validate('noreply@smart2pay.com'), 1, 'Test SPF record lookup against private label'); #will fail until SPF record is updated
