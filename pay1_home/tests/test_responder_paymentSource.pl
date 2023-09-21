#!/bin/env perl
# test loading of Payment source data/Card data
use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::API::REST::Responder::Merchant::Recurring::PaymentSource;
use JSON::XS;

my $ps = new PlugNPay::API::REST::Responder::Merchant::Recurring::PaymentSource();
$ps->setGatewayAccount('anhtraminc');
$ps->setResourceData({'merchant' => 'chrisinc','customer' => 'chriscust131892380183153'});
$ps->setAction('read');

print encode_json($ps->_read()) . "\n";

exit;
