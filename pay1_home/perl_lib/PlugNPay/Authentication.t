#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 10;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);

require_ok('PlugNPay::Authentication');
require_ok('PlugNPay::Authentication::Login');
require_ok('PlugNPay::Util::RandomString');

my $userData = {
  'username' => 'pnpdemo',
  'override' => 'pnpdemo2',
  'realm'    => 'PNPADMINID'
};

SKIP: {
  if (!skipIntegration("skipping integration tests", 7)) {
    my $password = setPassword($userData);
    $userData->{'password'} = $password;
    test_overrideType($userData)
  }
}

sub setPassword {
  my $userData = shift;

  # Create and set new password
  my $random = new PlugNPay::Util::RandomString();
  my $randomPassword = $random->randomAlphaNumeric(16);

  my $loginClient = new PlugNPay::Authentication::Login({
    login => $userData->{'username'}
  });
  $loginClient->setRealm($userData->{'realm'});

  my $result = $loginClient->clearPasswordHistory();
  ok($result, 'password history cleared successfully');
  $result = $loginClient->setPassword({
    password => $randomPassword
  });
  ok($result, 'random password set');

  return $randomPassword;
}

sub authenticate {
  my $userData = shift;

  my $authentication = new PlugNPay::Authentication();
  $authentication->validateLogin({
    generateCookie => 0,
    login          => $userData->{'username'},
    password       => $userData->{'password'},
    realm          => $userData->{'realm'},
    override       => $userData->{'override'},
    version        => 2
  });

  return $authentication;
}

sub test_overrideType {
  my $userData = shift;

  my $loginClient = new PlugNPay::Authentication::Login({
    login => $userData->{'username'}
  });
  $loginClient->setRealm($userData->{'realm'});

  # add directories
  $loginClient->addDirectories({
    directories => ['reseller','all']
  });

  # authenticate to get overrideType
  my $authResult = authenticate($userData);

  my $canOverride = $authResult->canOverride();
  ok($canOverride, 'user can override');

  my $overrideType = $authResult->getOverrideType();
  is($overrideType, 'reseller', 'overrideType is "reseller" when "all" and "reseller" exist');

  # remove "reseller" dir
  $loginClient->removeDirectories({
    directories => ['reseller']
  });

  # authenticate to get new overrideType
  $authResult = authenticate($userData);

  $overrideType = $authResult->getOverrideType();
  is($overrideType, 'all', 'overrideType is "all" when it is the only type that exists');

  # remove "all" dir
  $loginClient->removeDirectories({
    directories => ['all']
  });

  # authenticate to get new overrideType
  $authResult = authenticate($userData);

  $canOverride = $authResult->canOverride();
  ok(!$canOverride, 'user cannot override when no override directories exist');

  $overrideType = $authResult->getOverrideType();
  is($overrideType, '', 'overrideType is empty when no override directories exist');
}

