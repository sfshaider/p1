#!/bin/env perl 

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use JSON::XS;
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;

my $server_ip = `hostname -i`;
chomp $server_ip;

my $lwp = new LWP::UserAgent('remote_client');
$lwp->ssl_opts(verify_hostname=>0);

my $httprequest = new HTTP::Request('POST' => 'https://' . $server_ip . '/iapi/merchant/:chrisinc/order/transaction/storedata');

my $data = {
    "transactions" => {
        "transaction1" => {
            "amount" => "1.00",
            "calculateAdjustment" => "yes", #/* This is optional, defaults to "no". Calculates and stores Adjustment fee */
            "orderID" => "1234657890234", #/* This is optional */
            "billingInfo" => {
                "email" => 'user@test.com',
                "country" => "US",
                "city" => "Albany",
                "name" => "John Doe",
                "address" => "123 Main Street",
                "phone" => "555-555-5555",
                "postalCode" => "12201",
                "state" => "NY"
            },
            "payment" => {
                "card" => {
                    "expYear" => "19",
                    "number" => "4111111111111111",
                    "expMonth" => "12"
                },
                "type" => "credit"
            },
            "accountCode" => "EX1"
        },
        "transaction2" => {
            "amount" => "10.29",
            "operation" => "ext_sale", #/* This is optional, defaults to "storedata" */
            "billingInfo" => {
                "email" => 'user@test.com',
                "country" => "US",
                "city" => "Albany",
                "name" => "Barry Tester",
                "address" => "555 Main Street",
                "phone" => "555-555-5559",
                "postalCode" => "12201",
                "state" => "NY"
            },
            "payment" => {
                "ach" => {
                    "routingNumber" => "99999992",
                    "accountNumber" => "1234567890",
                    "accountType" => "Checking"
                },
                "type" => "ach"
            },
            "accountCode" => " EX2"
        }
    }
};

$httprequest->content_type('application/json');
$httprequest->content(encode_json($data));
my $response = $lwp->request($httprequest);
print $response->status_line . "\n";
print Dumper $response->content;

exit;
