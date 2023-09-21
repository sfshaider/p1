#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::API::REST::Responder::Merchant::Order::Transaction::CustomData;
use JSON::XS;

my $cd = new PlugNPay::API::REST::Responder::Merchant::Order::Transaction::CustomData();
$cd->setGatewayAccount('dylaninc');
$cd->setResourceData({'merchant' => 'dylaninc'});
$cd->setResourceDataArray({'order' => ['2018040313094522093','2018040317100709342']});
$cd->setResourceOptions({'start_time' => '20180403','end_time' => '20180403'});
$cd->setAction('read');

print encode_json($cd->_read()) . "\n";

exit;
