#!/bin/env perl
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;
use JSON::XS;

my $ua = new LWP::UserAgent();
$ua->ssl_opts(verify_hostname => 0);

my $request = new HTTP::Request('POST' => "https://localhost/api/merchant/:chrisinc/recurring/attendant/customer/:testcust/session");
$request->content_type('application/json');
$request->header('X-Gateway-Account' => 'chrisinc');
$request->header('X-Gateway-API-Key-Name' => 'testattend');
$request->header('X-Gateway-API-Key' => 'pBwY8koNzfVaIlYVK40dxi1at4mIk0Om9mBJoRrJ');
$request->header('ACCEPT' => 'application/json');

my $content = {
  additionalData => {
    restrictSections => [
      'payment',
      'payment_sources',
      'pending_payments',
      'scheduled_payments',
      'payment_history',
      'profile'

    ]
  }
};

print encode_json($content);

$request->content(encode_json($content));

my $response = $ua->request($request);
my $msg = $response->decoded_content;
print $msg;
