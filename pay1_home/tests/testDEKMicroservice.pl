#!/bin/env perl

use strict;
use warnings;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::DEK;
use Data::Dumper;

my $ms = new PlugNPay::DEK();
my $newKey = 'testdekkey7';
my $oldKey = 'dektest5key';
my $dekStr = 'fajsjfaiwoetowjeoiwjeorqij';
my $url = 'http://10.100.2.15:5002/dek/';

$ms->setKey($newKey);
$ms->setUrl($url);
$ms->setDEKString($dekStr);

my $createKeyResp = $ms->createKeyAndString();
print Dumper $createKeyResp;

my $response = $ms->requestKey($oldKey);
print Dumper $response;

