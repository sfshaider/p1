#!/bin/env perl 

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use JSON::XS;
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;

my $lwp = new LWP::UserAgent('remote_client');
$lwp->ssl_opts(verify_hostname=>0);

my $httprequest = new HTTP::Request('POST' => 'https://bgiordano.nyoffice.plugnpay.com:8443/api/merchant/:bryaninc/remote_client/');
$httprequest->header('X-Gateway-Account' => 'bryaninc');
$httprequest->header('X-Gateway-API-Key-Name' => 'emv_test');
$httprequest->header('ACCEPT' => 'application/json');
$httprequest->header('X-Gateway-API-Key' => 'Y605VEjPiJ+UEkJ6WJmSY2rL+TgEhTaMkzM5OCgg');

my $data = {
  'password' => 'P@sswrd103',
  'generate_random_password' => '0'
};

$httprequest->content_type('application/json');
$httprequest->content(encode_json($data));
my $response = $lwp->request($httprequest);
print $response->status_line . "\n";
print Dumper $response->content;

exit;
