#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::API::REST;
use PlugNPay::GatewayAccount::APIKey;
use PlugNPay::API::REST::Session;
use PlugNPay::Logging::MessageLog;
use PlugNPay::Logging::Performance;

my $performanceLogger = new PlugNPay::Logging::Performance('RESTful API start');
$ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};

my $logger = new PlugNPay::Logging::MessageLog();

my $rest = new PlugNPay::API::REST('/iapi');
$performanceLogger->addMetadata({'uri' => $rest->getResourcePath(), 'data' => $rest->getResourceData()});

print $rest->respond();

# Write and clear performance log singleton
$performanceLogger = new PlugNPay::Logging::Performance('RESTful API end');
$performanceLogger->write();

# Close DB connections
my $dbs = new PlugNPay::DBConnection();
$dbs->closeConnections();
exit;
