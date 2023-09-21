#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::ResponseLink;
my $domain = 'https://dmanitta.nyoffice.plugnpay.com:8443/payment/pnpremote.cgi';
&doit($domain);
exit;
sub doit {
my $url = shift;
my $rl = new PlugNPay::ResponseLink();
$rl->setUsername('dylaninc');
$rl->setRequestMode('PROXY');
$rl->setRequestURL($url);
$rl->setRequestData({'publisher-password' => 'P@ssword1',
'mode' => 'query_trans',
'merchant' => 'dylaninc',
'startdate'  => '20171111',
'enddate' => '20171222',
'publisher-name' => 'dylaninc'});

$rl->setRequestContentType('application/x-www-form-urlencoded');
$rl->setResponseAPIType('querystring');

$rl->doRequest();

use Data::Dumper;
my $responseContent = $rl->getResponseContent();
my %api = $rl->getResponseAPIData();
print Dumper(\%api);
}
