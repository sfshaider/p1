#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 8;
use Test::Exception;
use Test::MockModule;
use Time::HiRes;

require_ok('PlugNPay::Transaction::Query::Response');

testSerializeDeserialize();

# this test also tests normal behavior of setters and getters
sub testSerializeDeserialize {
    my $r = new PlugNPay::Transaction::Query::Response();

    my $message = 'a message';
    my $rows = [
      { field1 => 'row1value1', field2 => 'row1value2' },
      { field1 => 'row2value1', field2 => 'row2value2' }
    ];
    my $queryId = 'a query id';

    $r->setError(1);
    $r->setMessage($message);
    $r->setRows($rows);
    $r->setQueryId($queryId);

    my $serializeStatus = $r->serialize();
    if (!$serializeStatus) {
        fail('serialization failed with error: ' . $serializeStatus->getError());
        return
    }

    my $serialized = $serializeStatus->get('serialized');

    my $dr = new PlugNPay::Transaction::Query::Response();
    my $deserializeStatus = $dr->deserialize($serialized);
    if (!$deserializeStatus) {
        fail('deserialization failed with error: ' . $deserializeStatus->getError());
        return
    }

    my $firstRow = $dr->nextRow();
    my $secondRow = $dr->nextRow();

    ok($dr->getError(),'getError returns truthy value after deseriaization');
    is($dr->getMessage(),$message,'getMessage returns set message after deserialization');
    is($firstRow->{'field1'}, $rows->[0]{'field1'},'row 1 after deserializations matches row 1 prior to serialization');
    is($firstRow->{'field2'}, $rows->[0]{'field2'},'row 2 after deserializations matches row 2 prior to serialization');
    is($secondRow->{'field1'}, $rows->[1]{'field1'},'row 1 after deserializations matches row 1 prior to serialization');
    is($secondRow->{'field2'}, $rows->[1]{'field2'},'row 2 after deserializations matches row 2 prior to serialization');
    is($dr->getQueryId(),$queryId,'getQueryId returns set query id after deserialization');
}