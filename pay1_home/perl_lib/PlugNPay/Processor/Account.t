#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 10;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('PlugNPay::Processor::Account');

# set up mocking for tests
my $mock = Test::MockObject->new();

# Mock PlugNPay::DBConnection
my $noQueries = sub {
  print STDERR new PlugNPay::Util::StackTrace()->string("\n") . "\n";
  die('unexpected query executed')
 };
my $dbsMock = Test::MockModule->new('PlugNPay::DBConnection');
$dbsMock->redefine(
'executeOrDie' => $noQueries,
'fetchallOrDie' => $noQueries
);

my $paMock = Test::MockModule->new('PlugNPay::Processor::Account');
my $psMock = Test::MockModule->new('PlugNPay::Processor::Settings');


# getUnifiedInsert()
# redefine DBConnection functions for testing getUnifiedInsert
$dbsMock->redefine(
'executeOrDie' => sub {
  return;
},
'fetchallOrDie' => sub {
  return {
    rows => [
      { id => 49, key => 'industryCode' }, # 49 for industryCode, doesn't really matter as long as we are consistent in or test and mocking
      { id => 51, key => 'empty_string_from_undef'}, # to test converting undef to empty string
    ]
  };
}
);

$paMock->redefine(
'getGatewayAccount' => sub {
  return 'pnpdemo';
},
'getCustomerID' => sub {
  return 99;
},
'getProcessorID' => sub {
  return 79; #
}
);

# test in eval to ensure dbsMock gets reset.
eval {
  my $pa = new PlugNPay::Processor::Account();
  my $result = $pa->getUnifiedInsert({ industryCode => 'retail', empty_string_from_undef => undef });
  # use Data::Dumper; print STDERR Dumper($result);
  is($result->{'params'},'(?,?,?,?),(?,?,?,?)','getUnifiedInsert params returns the correct string of placeholders');
  is($result->{'data'}[0],99,'getUnifiedInsert() data returns the correct value for position 0 (customer_id, mocked test value)');
  is($result->{'data'}[1],79,'getUnifiedInsert() data returns the correct value for position 1 (processor_id, mocked test value)');
  is($result->{'data'}[2],49,'getUnifiedInsert() data returns the correct value for position 2 (key_id, mocked industryCode test value');
  is($result->{'data'}[3],'retail','getUnifiedInsert() data returns the correct value for position 3 (value)');
  is($result->{'data'}[4],99,'getUnifiedInsert() data returns the correct value for position 4 (customer_id, mocked test value)');
  is($result->{'data'}[5],79,'getUnifiedInsert() data returns the correct value for position 5 (processor_id, mocked test value)');
  is($result->{'data'}[6],51,'getUnifiedInsert() data returns the correct value for position 6 (key_id, mocked empty_string_form_undef test vale)');
  is($result->{'data'}[7],'','getUnifiedInsert() data returns the correct value for position 7 (value, empty string converted from undef)');
};

$dbsMock->redefine(
'executeOrDie' => $noQueries,
'fetchallOrDie' => $noQueries
);
