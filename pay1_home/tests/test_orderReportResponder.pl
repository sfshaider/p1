#!/bin/env perl
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use LWP::UserAgent;
use HTTP::Request;
use Data::Dumper;
use JSON::XS;

my $ua = new LWP::UserAgent();
$ua->ssl_opts(verify_hostname => 0);

#check args
my $count_args = $#ARGV + 1; 
my $TYPE;
my $BATCHID;
my $PARMOK;

print "count args=" . $count_args . " \n";
if ($count_args < 1) {
	print "usage: /usr/bin/perl $0 POST/GET <patchid> /DELETE <batchid>\n";
} elsif ($count_args < 2) {
	$TYPE = $ARGV[0];
	if ($TYPE eq 'POST') {
		$PARMOK = 1;
	}
	elsif ($TYPE eq 'GET' || $TYPE eq 'DELETE'){
		print "usage: /usr/bin/perl $0 $TYPE <batchid>\n";
	}
	else {
		print "usage: /usr/bin/perl $0 POST/GET <patchid> /DELETE <batchid>\n";
	}
	
} else {
	$BATCHID = $ARGV[1];
	$PARMOK = 1;
}

print "batchid=" . $BATCHID . "\n";
if ($PARMOK) {
	#set request type and url
	my $TYPE = $ARGV[0]; #POST, GET, DELETE
	my $content = {}; #TYPE eq GET/DELETE
	if ($TYPE eq 'POST') {
		$content = {'start_date' =>'20180901', 'end_date' =>'20180902'};
	}
	my $URL = "https://anguyen.nyoffice.plugnpay.com:8443/api/merchant/:anhtraminc/order/transaction/report";
	if ($BATCHID) {
		$URL = $URL . "/:" . $BATCHID;
	}

	my $request = new HTTP::Request($TYPE => $URL);
	#my $request = new HTTP::Request($TYPE => "https://anguyen.nyoffice.plugnpay.com:8443/api/merchant/:anhtraminc/order/transaction/report");

	$request->content_type('application/json');
	$request->header('X-Gateway-Account' => 'anhtraminc');
	$request->header('X-Gateway-API-Key-Name' => 'ordertest');
	$request->header('X-Gateway-API-Key' => 'ZQc/3kRoEeaOI/HybSKR5/RKSmRboTvi7HNDt/yz');
	$request->header('ACCEPT' => 'application/json');

	my $content = {'cardNumber' => '4111', 'amount' =>'3.00', 'batchid' =>'123456789','start_date' =>'20180901', 'end_date' =>'20180902'};

	print encode_json($content);

	$request->content(encode_json($content));

	my $response = $ua->request($request);
	print "\n After call to request response= " . Dumper($response) . "\n";
	my $msg = $response->decoded_content;

	print $msg;

}




