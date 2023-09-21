#!/bin/env perl
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;
use JSON::XS;


my $ua = new LWP::UserAgent();
$ua->ssl_opts(verify_hostname => 0);
my $merchant = $ARGV[0];
my $customer = $ARGV[1];
my $endPoint = 'https://rfox.nyoffice.plugnpay.com:8443/api/merchant/:' . $merchant . '/recurring/attendant/customer/:' . $customer . '/paymentsource';
my $request = new HTTP::Request(GET => $endPoint);
$request->header('X-Gateway-Account' => 'rfoxinc');
$request->header('X-Gateway-API-Key-Name' => 'emv');
$request->header('X-Gateway-API-Key' => 'HF0SuuOLUb6Cd5S10ntz6bpuLpS7Oupta2hZdsIv');
$request->header('ACCEPT' => 'application/json');
$request->header('content-type' => 'application/json');
$request->content(encode_json({
  'type'       => 'card',
  'cardNumber' => '4111111111111111',
  'expMonth'   => '04',
  'expYear'    => '19'
}));
my $response = $ua->request($request);
print Dumper($response);
