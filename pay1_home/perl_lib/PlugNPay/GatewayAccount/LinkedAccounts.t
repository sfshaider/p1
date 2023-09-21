#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 11;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use PlugNPay::Features;

require_ok('PlugNPay::GatewayAccount::LinkedAccounts');

my $features = new PlugNPay::Features('pnpdemo','general');
$features->set('linked_account_group','');
$features->saveContext();

my $la = new PlugNPay::GatewayAccount::LinkedAccounts();
$la->setLogin('PnPDemo');
is($la->getLogin(), 'pnpdemo', 'Login was lowercased');
$la->setLogin('pnp_demo');
is($la->getLogin(), 'pnpdemo', 'Login filtered out invalid characters');


$la->setGatewayAccount('pnpdemo');
is($la->getGatewayAccount(), 'pnpdemo', 'GatewayAccount was lowercased');
$la->setGatewayAccount('pnp_demo');
is($la->getGatewayAccount(), 'pnpdemo', 'GatewayAccount filtered out invalid characters');

eval {
  $la->setGatewayAccount('pnpdemo');
  $la->setLogin('pnpdemo');
  $la->_load();
};
my $error = $@;
ok(!$error, "Loaded successfully");
ok($la->isLinkedTo('pnpdemo2'),'Linked check works');
ok($la->isLinkedTo('PnPDEmo2'),'LC account name in isLinkedTo');
ok(!$la->isLinkedTo(undef), 'Account link check successfully handled undef account name');

my $list = $la->_loadFromLinkedListFeature($features);
my @listKeys = keys %{$list};
ok(@listKeys == 0, "No linked list data");

my $laList = $la->_loadFromLinkedAccountFeature($features);
ok($laList->{'pnpdemo2'}, "Linked Account Feature data exists");
