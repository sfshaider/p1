#!/usr/bin/perl

use strict;
use lib '/home/pay1/perl_lib';

use PlugNPay::Transaction::Updater::Status;
my $updater = new PlugNPay::Transaction::Updater::Status();

my $res = $updater->update();

use Data::Dumper;
print Dumper $res;
