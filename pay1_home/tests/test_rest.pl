#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use JSON::XS;
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;

my $lwp = new LWP::UserAgent('rest_test');
$lwp->ssl_opts(verify_hostname=>0);

my $httprequest = new HTTP::Request('GET' => 'https://bgiordano.nyoffice.plugnpay.com:8443/api/merchant/:bryaninc/emv/transaction/:5A6B70C02F9986FE02C511E8834CB1210E803A3F4EC');
$httprequest->header('X-Gateway-Account' => 'bryaninc');
$httprequest->header('X-Gateway-API-Key-Name' => 'emv_test');
$httprequest->header('X-Gateway-API-Key' => 'Y605VEjPiJ+UEkJ6WJmSY2rL+TgEhTaMkzM5OCgg');
$httprequest->header('ACCEPT' => 'application/json');
#my $data = {
#  'amountCharged' => '3.14',
#  'feeAmount' => '.25',
#  'taxCharged' => '.25',
#  'feeTax' => '.01',
#  'operation' => 'sale',
#  'payment' => {
#    'type' => 'card'
#  },
#  'billingInfo' => {
#    'name' => 'bryan g',
#    'address' => '1363 Vets Hwy',
#    'city' => 'Hauppauge',
#    'state' => 'NY',
#    'country' => 'US',
#    'postalCode' => '11788',
#    'email' => 'bryan@plugnpay.com'
#  }
#};
#$httprequest->content_type('application/json');
#$httprequest->content(encode_json($data));
my $response = $lwp->request($httprequest);
print $response->status_line . "\n";
print Dumper $response->content;
exit;
