#!/usr/bin/perl

use strict;
use warnings;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::GatewayAccount;
use JSON::XS;
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;


# URL: /api/reseller/merchant
# POST Request

my $lwp = new LWP::UserAgent('gateway_test');
$lwp->ssl_opts(verify_hostname=>0);

my $httprequest = new HTTP::Request('POST' => 'https://lpadden.nyoffice.plugnpay.com:8443/api/reseller/:paddeninc/merchant');
$httprequest->header('X-Gateway-Account' => 'paddeninc');
$httprequest->header('X-Gateway-API-Key-Name' => 'resellermerchantresp');
$httprequest->header('X-Gateway-API-Key' => 'Pfc+87tvlTYg83KNb/XMJdlGKcN13KtYARgyh2ak');
$httprequest->header('ACCEPT' => 'application/json');

my $data = '
      {
	"account": {
		"processors": {
			"cardProcessor": "testprocessor",
			"achProcessor": "testprocessor",
			"processor": [{
					"type": "cardProcessor",
					"setting": [{
							"value": "12345",
							"name": "mid"
						},
						{
							"value": "1",
							"name": "isRetail"
						},
						{
							"value": "23436",
							"name": "tid"
						},
						{
							"value": "authonly",
							"name": "authType"
						},
						{
							"value": "123456",
							"name": "terminalNumber"
						}
					],
					"shortName": "testprocessor"
				},
				{
					"type": "achProcessor",
					"setting": [{
							"value": "12345",
							"name": "mid"
						},
						{
							"value": "1",
							"name": "isRetail"
						},
						{
							"value": "11122",
							"name": "tid"
						},
						{
							"value": "authonly",
							"name": "authType"
						},
						{
							"value": "123234",
							"name": "terminalNumber"
						}
					],
					"shortName": "testprocessor"
				}
			]
		},
		"billing": {
			"contact": {
				"emailList": [{
					"primary": "true",
					"type": "primary",
					"address": "test@subr.com"
				}]
			}
		},
		"primaryContact": {
			"emailList": [{
				"primary": "true",
				"type": "primary",
				"address": "test@subr.com"
			}],
			"addressList": [{
				"primary": "true",
				"type": "main",
				"streetLine1": "6 Test Ave",
				"streetLine2": "APT 2b",
				"city": "Upton",
				"stateProvince": "New York",
				"postalCode": "11793",
				"country": "US"
			}],
			"phoneList": [{
				"primary": "true",
				"type": "phone",
				"number": "6315558989"
			}],
			"name": "Manuel Testerson"
		},
		"technicalContact": {
		  "emailList": [{
		    "primary": "true",
				"type": "primary",
				"address": "test@subr.com"
		  }],
		  "phoneList": [{
				"primary": "true",
				"type": "phone",
				"number": "6315558989"
			}],
			"name": "Manuel Testerson"
		},
		"gatewayAccountName": "paddentest7",
		"companyName": "Test Reseller 2"
	}
}
';

$httprequest->content_type('application/json');
$httprequest->content($data);
my $response = $lwp->request($httprequest);
print Dumper $response->content;

exit;



