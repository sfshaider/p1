#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use Data::Dumper;
use PlugNPay::API::REST::Responder::Reseller::Merchant::Status;
my $responder = new PlugNPay::API::REST::Responder::Reseller::Merchant::Status();
$responder->setGatewayAccount('dylaninc');
$responder->setResourceData({'reseller' => 'dylaninc', 'merchant' => 'dylaninc2', 'status' => 'live'});
$responder->setInputData({'reseller' => 'dylaninc', 'gatewayAccount' => 'dylaninc2', 'status' => 'live'});
$responder->setAction('read');

print Dumper $responder->_getOutputData();

$responder->setAction('update');
print Dumper $responder->_getOutputData();


exit;
