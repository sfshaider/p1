#!/bin/env perl

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::CardData;
use PlugNPay::Sys::Time;

my $cdb = new PlugNPay::CardData;
my $timeObj = new PlugNPay::Sys::Time();

my $orderIdOrCustomer = $timeObj->nowInFormat('unix');

eval {
  $cdb->insertOrderCardData({username => 'pnpdemo',orderID => $orderIdOrCustomer,cardData => 'blah3'}) . "\n";
};
print $@ . "\n" if $@;
print $cdb->getOrderCardData({username => 'pnpdemo',orderID => $orderIdOrCustomer}) . "\n";

eval {
  $cdb->insertRecurringCardData({username => 'pnpdemo',customer => $orderIdOrCustomer,cardData => 'blah3'}) . "\n";
};
print $@ . "\n" if $@;
print $cdb->getRecurringCardData({username => 'pnpdemo',customer => $orderIdOrCustomer}) . "\n";
