#!/bin/env perl

use strict;
use Data::Dumper;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::Fraud;
use PlugNPay::DBConnection;
use PlugNPay::Transaction;
use PlugNPay::Transaction::TransactionProcessor();
use PlugNPay::GatewayAccount;
my $ga = new PlugNPay::GatewayAccount('dylaninc');
my $contact = $ga->getMainContact();
my $cc = new PlugNPay::CreditCard('4111111111111111');
$cc->setExpirationMonth('12');
$cc->setExpirationYear('2020');
$cc->setSecurityCode('222');
$cc->setName('Dylan Manitta');


my $t = new PlugNPay::Transaction('auth','card');
my $fraud = new PlugNPay::Fraud({'gatewayAccount' => 'dylaninc'});

$t->setOrderID(new PlugNPay::Transaction::TransactionProcessor()->generateOrderID());
$t->setGatewayAccount('dylaninc');
$t->setCreditCard($cc);
$t->setBillingInformation($contact);
$t->setShippingInformation($contact);
$t->setTransactionDateTime('2019-01-01 11:11:11');

print Dumper $fraud->preAuthScreen($t);

exit;
