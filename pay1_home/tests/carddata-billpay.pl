#!/usr/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::CardData;

my $cd = new PlugNPay::CardData();
$cd->insertBillpayCardData({customer => 'chris@test.plugnpay.com', profileID => '20180427101010', cardData => 'blahblahblahbillpay'});
print $cd->getBillpayCardData({customer => 'chris@test.plugnpay.com', profileID => '20180427101010'});
