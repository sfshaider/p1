#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 4;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('PlugNPay::API');

# set up mocking for tests
my $mock = Test::MockObject->new();

my $apiMock = Test::MockModule->new('PlugNPay::Metrics');


# mock new so we don't load anything from the database
$apiMock->redefine(
'new' => sub {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}
);

my $api = new PlugNPay::API();

# fixLegacyAmount()
my $input = {
  amount => 'usd 1.01'
};

my $output = $api->fixLegacyAmount($input);
is($input->{'card_amount'},undef,'input is not modified by fixLegacyAmount');
is($output->{'card_amount'},'1.01','output card_amount contains the quantity of currency');
is($output->{'currency'},'usd','output currency contains the currency');
