#!/bin/env perl
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;
use JSON::XS;

my $ua = new LWP::UserAgent();
$ua->ssl_opts(verify_hostname => 0);

my $TYPE = $ARGV[0];
my $hashtype = $ARGV[1] || 'outbound';
my $URL = "https://bgiordano.nyoffice.plugnpay.com:8443/api/merchant/:brytest2/verificationhash/$hashtype/";
my $request = new HTTP::Request($TYPE => $URL);

if ($TYPE eq 'POST') {
  my $content;
  if ($hashtype eq 'outbound') {
    $content = {'fields' => ['publisher-name', 'orderID', 'bigbrybry' ] };
  } elsif ($hashtype eq 'inbound') {
    $content = {'fields' => ['publisher-name', 'orderID', 'testing123' ], 'timeWindow' => 30 };
  } else {
    die "bad hash type";
  } 

  $request->content(encode_json($content));
  $request->content_type('application/json');
}

$request->header('X-Gateway-Account' => 'brytest2');
$request->header('X-Gateway-API-Key-Name' => 'verification');
$request->header('X-Gateway-API-Key' => 'GXS5AR4hHva5XIDdLN1cTawHeup4va36xKXSjn6h');
$request->header('ACCEPT' => 'application/json');

my $response = $ua->request($request);
print "\n After call to request response= " . Dumper($response) . "\n";
my $msg = $response->decoded_content;
print $msg . "\n\n";
exit;
