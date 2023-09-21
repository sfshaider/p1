#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 11;
use Test::Exception;
use Test::MockModule;
use Time::HiRes;

require_ok('PlugNPay::Transaction::Query::Request');

testSerializeDeserialize();
testProcessorSetter();

# this test also tests normal behavior of setters and getters
sub testSerializeDeserialize {
    my $q = new PlugNPay::Transaction::Query::Request();

    my $rawQuery = "a man, a plan, panama";
    $q->setRawQuery($rawQuery);

    my $rawValues = [1,2,3];
    $q->setRawValues($rawValues);

    my $processors = ['testprocessor','testprocessor2'];
    $q->setProcessors($processors);

    $q->setSkipPnpData(1);

    my $serializeStatus = $q->serialize();
    if (!$serializeStatus) {
        fail('serialization failed with error: ' . $serializeStatus->getError());
        return
    }

    my $serialized = $serializeStatus->get('serialized');

    my $dq = new PlugNPay::Transaction::Query::Request();
    my $deserializeStatus = $dq->deserialize($serialized);
    if (!$deserializeStatus) {
        fail('deserialization failed with error: ' . $deserializeStatus->getError());
        return
    }

    is($dq->getRawQuery(),$rawQuery,'get of raw query is same data passed to setter');

    is($dq->getRawValues()->[0],$rawValues->[0],'get of raw values index 0 is same data passed to setter');
    is($dq->getRawValues()->[1],$rawValues->[1],'get of raw values index 1 is same data passed to setter');
    is($dq->getRawValues()->[2],$rawValues->[2],'get of raw values index 2 is same data passed to setter');

    is($dq->getProcessors()->[0],$processors->[0],'get of processors index 0 is same data passed to setter');
    is($dq->getProcessors()->[1],$processors->[1],'get of processors index 1 is same data passed to setter');

    ok($dq->getSkipPnpData(),'skipping of pnpdata truthiness is the same as passed to setter');
}

sub testProcessorSetter {
    my $q = new PlugNPay::Transaction::Query::Request();
    
    lives_ok(sub {
        my $processor = 'testprocessor';
        $q->setProcessors($processor);
        my $got = $q->getProcessors();
        is($got->[0],$processor,'getting processors returns an array ref of one item when setting processors with a scalar');
    },'setting processors with a scalar does not return an error');

    dies_ok(sub {
        $q->setProcessors({ processor => 'testprocessor' });
    },'setting processors with an object other than a scalar or array ref triggers a die');
}