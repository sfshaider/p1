#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Logging::Transaction;
use PlugNPay::Transaction;
use PlugNPay::Contact;
use PlugNPay::Recurring::Profile;
use Time::HiRes qw(time);

my $transaction = new PlugNPay::Transaction('auth', 'card');
$transaction->setOrderID(PlugNPay::Transaction::TransactionProcessor::generateOrderID());

my $profile = new PlugNPay::Recurring::Profile('paddeninc', 'padden42');

my $contact = new PlugNPay::Contact();
$contact->setFullName($profile->getName());
$contact->setAddress1($profile->getAddress1());
$contact->setAddress2($profile->getAddress2());
$contact->setCity($profile->getCity());
$contact->setState($profile->getState());
$contact->setPostalCode($profile->getPostalCode());
$contact->setCountry($profile->getCountry());
$contact->setCompany($profile->getCompany());
$contact->setEmailAddress($profile->getEmail());
$contact->setPhone($profile->getPhone());

my $shippingContact = new PlugNPay::Contact();
$shippingContact->setFullName($profile->getShippingName());
$shippingContact->setAddress1($profile->getShippingAddress1());
$shippingContact->setAddress2($profile->getShippingAddress2());
$shippingContact->setCity($profile->getShippingCity());
$shippingContact->setState($profile->getShippingState());
$shippingContact->setPostalCode($profile->getShippingPostalCode());
$shippingContact->setCountry($profile->getShippingCountry());
$shippingContact->setPhone($profile->getPhone());

$transaction->setGatewayAccount('paddeninc');
$transaction->setBillingInformation($contact);
$transaction->setShippingInformation($shippingContact);

$transaction->setTransactionAmount(100);
$transaction->setCreditCard(new PlugNPay::CreditCard('4111111111111111'));

my $resp = new PlugNPay::Transaction::Response();
$resp->setStatus('success');
$transaction->setResponse($resp);

my $transLogger = new PlugNPay::Logging::Transaction();
my $data = {
  'transaction' => $transaction,
  'duration' => 100,
  'remoteIpAddress' => '10.100.2.15',
  'ipAddress' => '10.100.2.15',
  'templateName' => 'pay'
};
$transLogger->log($data);
