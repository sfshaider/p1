#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 8;
use Test::Exception;
use Data::Dumper;

use PlugNPay::Util::Status;

use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::Processor::ProcessorVpnProxyClient');

my $pvpc = new PlugNPay::Processor::ProcessorVpnProxyClient();

my $testStatus = new PlugNPay::Util::Status(1);
my $testResponse = {
  name => 'port name',
  port => '707',
  remotePort => '3045',
  remoteHost => 'example.com'
};

$pvpc->mapPortInfoForIdentifierResponseToStatus($testResponse, $testStatus);

is($testStatus->get('name'),$testResponse->{'name'}, 'status name value set correctly');
is($testStatus->get('port'),$testResponse->{'port'}, 'status port value set correctly');
is($testStatus->get('remotePort'),$testResponse->{'remotePort'}, 'status remotePort value set correctly');
is($testStatus->get('remoteHost'),$testResponse->{'remoteHost'}, 'status remoteHost value set correctly');
is($testStatus->get('localDestination'),$pvpc->getHost() . ':' . $testResponse->{'port'}, 'status localDestination value set correctly');

$ENV{'PROCESSOR_VPN_PROXY_HOST'} = 'test.com';
is($pvpc->getPortInfoUrl(),'https://test.com/ports','port info url created successfully');
is($pvpc->getProxyUrl(),'https://test.com/proxy','proxy url created successfully');
delete($ENV{'PROCESSOR_VPN_PROXY_HOST'});