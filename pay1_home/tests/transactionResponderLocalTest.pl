#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use JSON::XS;
use PlugNPay::API::REST::Responder::Merchant::Order::Transaction;

#Not the way to implement a responder, but an easy way to test
my $responder = new PlugNPay::API::REST::Responder::Merchant::Order::Transaction();
$responder->setGatewayAccount('brytest2');
$responder->setAction('read');
$responder->setResourceData({'merchant' => 'brytest2'});
$responder->setResourceOptions({'start_time' => '20180315161830', 'end_time' => '20180315161831'});
print encode_json($responder->_getOutputData());


exit;
