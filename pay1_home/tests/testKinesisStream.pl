#!/bin/env perl
use lib $ENV{"PNP_PERL_LIB"};
use strict;
use warnings;
use PlugNPay::AWS::Kinesis;
use Data::Dumper;

my $stream = new PlugNPay::AWS::Kinesis();
my $streamName = "TransactionStream";
my $url = "http://172.17.0.3:8080/stream/" . $streamName;
my $data = {"test" => "hello"};
my $status = $stream->insertData($streamName, $data, $url);
print Dumper $status->getStatus();
