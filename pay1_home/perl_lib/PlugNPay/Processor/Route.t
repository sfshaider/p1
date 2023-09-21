#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 16;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use File::Touch;

require_ok('PlugNPay::Processor::Route');

test_getCustomData();

# Test the isQueryOperation function
# these should be query types
ok(PlugNPay::Processor::Route::isQueryOperation('query'),'query is a query operation');
ok(PlugNPay::Processor::Route::isQueryOperation('batchquery'),'batchquery is a query operation');
ok(PlugNPay::Processor::Route::isQueryOperation('batch-prep'),'batch-prep is a query operation');
ok(PlugNPay::Processor::Route::isQueryOperation('details'),'query is a query operation');
ok(PlugNPay::Processor::Route::isQueryOperation('card-query'),'card-query is a query operation');

# note the ! in front of the function call!!!!  these are *not* query types
ok(!PlugNPay::Processor::Route::isQueryOperation('auth'),'auth is not a query operation');
ok(!PlugNPay::Processor::Route::isQueryOperation('void'),'void is not a query operation');
ok(!PlugNPay::Processor::Route::isQueryOperation('return'),'return is not a query operation');
ok(!PlugNPay::Processor::Route::isQueryOperation('postauth'),'postauth is not a query operation');
ok(!PlugNPay::Processor::Route::isQueryOperation('reauth'),'reauth is not a query operation');


# Test the bypassSendMServerForQueries function
# create the config dir if it does not exist
my $configDir = '/home/pay1/etc/route-query/';
if ( !-d $configDir ) {
  mkdir $configDir;
}

# delete the legacy-default file if it exists
my $legacyDefaultFile = '/home/pay1/etc/route-query/legacy-default';
if ( -e $legacyDefaultFile ) {
  unlink($legacyDefaultFile);
}

# delete the testprocessor file if it exists
my $testprocessorFile = '/home/pay1/etc/route-query/testprocessor';
if ( -e $testprocessorFile ) {
  unlink($testprocessorFile);
}

ok(PlugNPay::Processor::Route::bypassSendMServerForQueries('testprocessor'),'testprocessor bypasses processor module for queries by default');
touch($testprocessorFile);
ok(!PlugNPay::Processor::Route::bypassSendMServerForQueries('testprocessor'),'testprocessor queries through processor module for queries when testprocessor file is present and legacy-default is not present');
touch($legacyDefaultFile);
ok(PlugNPay::Processor::Route::bypassSendMServerForQueries('testprocessor'),'testprocessor bypasses processor module for queries when testprocessor file is present and legacy-default is present');
unlink($testprocessorFile);
ok(!PlugNPay::Processor::Route::bypassSendMServerForQueries('testprocessor'),'testprocessor queries through processor module for queries when testprocessor file is not present and legacy-default is present');
# cleanup
unlink($legacyDefaultFile);


sub test_getCustomData {
  my $username = 'pnpdemo';
  my $query = {
    notCustom => "not a custom data key/value pair",
    customname45 => 'aaaa',
    customvalue45 => 'bbbb'
  };

  my $customData = PlugNPay::Processor::Route::getCustomData($username, $query);
  is($customData->{'aaaa'},'bbbb','custom data extracted from query');
}