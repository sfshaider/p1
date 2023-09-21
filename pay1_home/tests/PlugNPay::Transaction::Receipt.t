#!/bin/env perl
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::Response;
use PlugNPay::Transaction::Receipt;

# Load a transaction and response
my $gatewayAccount = "scotttest";
my $orderID = '2019011817142900569';
my $loader = new PlugNPay::Transaction::Loader();
my $transactionData = [{gatewayAccount => $gatewayAccount, orderID => $orderID}];
my $transactionObject = $loader->load($transactionData);
my $transaction = $transactionObject->{$gatewayAccount}{$orderID};
my $response = new PlugNPay::Transaction::Response($transaction);

# Send email receipt
my $receipt = new PlugNPay::Transaction::Receipt();
$receipt->sendEmailReceipt({'transaction' => $transaction, 'response' => $response, 'bccAddress' => 'scottTEST2@plugnpay.com', 'emailSubject' => 'Scott Test Subject'});

print "DUNZO\n";

