#!/usr/bin/perl

use strict;
use warnings;
use lib $ENV{'PNP_PERL_LIB'};
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;

# URL: /api/reseller/merchant/status
# PUT Request

my $lwp = new LWP::UserAgent('status_test');
$lwp->ssl_opts(verify_hostname=>0);

my $httprequest = new HTTP::Request('PUT' => "https://lpadden.nyoffice.plugnpay.com:8443/api/reseller/merchant/status");
$httprequest->header('X-Gateway-Account' => 'paddeninc');
$httprequest->header('X-Gateway-API-Key-Name' => 'resellermerchantresp');
$httprequest->header('X-Gateway-API-Key' => 'Pfc+87tvlTYg83KNb/XMJdlGKcN13KtYARgyh2ak');
$httprequest->header('ACCEPT' => 'application/json');

# testing debug first;
my $data = '
  {
		  "status": "debug",
		  "gatewayAccount": "paddeninc"
  }
';

$httprequest->content_type('application/json');
$httprequest->content($data);
my $response = $lwp->request($httprequest);
print Dumper $response->content;

exit;

