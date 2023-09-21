#!/usr/bin/perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use Test::More qw( no_plan );
use PlugNPay::Transaction::Legacy::AdditionalProcessorData;

my $ad = new PlugNPay::Transaction::Legacy::AdditionalProcessorData({processorId => 78}); # 78 = testprocessor2 on dev

$ad->setAdditionalDataString('            elephanthawk           000003.50    reserved00');
#                             0123456789012345678901234567890123456789012345678901234567890
is($ad->getField('mammal'),'elephant','Check mammal value.');
is($ad->getField('bird'),'hawk','Check bird value.');
is($ad->getField('bout'),'3.50','Check bout value.'); 
is($ad->getField('reserved'),'    reserved','Check reserved value.');
is($ad->getField('processed_network_id'), 'development', 'Checking Network Name);
