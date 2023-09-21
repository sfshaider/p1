#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::CreditCard;

#test1: test card with defined expirationMonth
my $cc = new PlugNPay::CreditCard('4111111111111111');
$cc->setExpirationMonth('12');
$cc->setExpirationYear('2020');

print  "\n test1: test credit card with defined expirationMonth";
print  "\n test1: expirationMonth is " . $cc->getExpirationMonth();
print  "\n test1: isExpired? " . $cc->isExpired();
print "\n";

#test2: test card with undefined expirationMonth
my $cc2 = new PlugNPay::CreditCard('4111111111111111');
$cc2->setExpirationYear('2020');

print "\n test2: test credit card with undefined expirationMonth";
print "\n test2: expirationMonth is " . $cc2->getExpirationMonth();
print "\n test2: isExpired? " . $cc2->isExpired();
print "\n";

#test3: test card with past expirationYear
my $cc3 = new PlugNPay::CreditCard('4111111111111111');
$cc3->setExpirationMonth('12');
$cc3->setExpirationYear('2019');

print "\n test3: test credit card with past expirationYear";
print "\n test3: expirationYear is " . $cc3->getExpirationYear();
print "\n test3: isExpired? " . $cc3->isExpired();
print "\n";

exit;
