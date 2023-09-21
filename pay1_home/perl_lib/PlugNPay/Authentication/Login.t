#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 17;
use Test::Exception;
use Test::MockObject;
use Test::Output;
use PlugNPay::Util::Array qw(inArray);

require_ok('PlugNPay::Authentication');
require_ok('PlugNPay::Authentication::Login');
require_ok('PlugNPay::Util::RandomString');

testSetAndGet();
testSettingPassword();
testFeaturesMapToString();

sub testFeaturesMapToString {
  my $featuresHash = {
    this => "that",
    something => "else"
  };

  my $loginClient = new PlugNPay::Authentication::Login();
  my $featureString = $loginClient->featuresMapToString($featuresHash);
  is($featureString,'something=else,this=that','feature string generated correctly from hash');
}

sub testSetAndGet {
  my $loginClient = new PlugNPay::Authentication::Login({
    login => 'pnpdemo'
  });
  $loginClient->setRealm('PNPADMINID');

  $loginClient->setDirectories({
    directories => []
  });
  my $got = getLoginInfo($loginClient);
  ok(@{$got->{'directories'}} == 0,'login has no access at start of test');
  
  my $acl = ['/admin'];
  $loginClient->setDirectories({
    directories => $acl
  });
  $got = getLoginInfo($loginClient);
  ok(inArray('/admin',$got->{'directories'}),'/admin directory set for login');

  $loginClient->addDirectories({
    directories => ['/admin/fraudtrack']
  });
  $got = getLoginInfo($loginClient);
  ok(inArray('/admin/fraudtrack',$got->{'directories'}),'directory added successfully');

  $loginClient->removeDirectories({
    directories => ['/admin/fraudtrack']
  });
  $got = getLoginInfo($loginClient);
  ok(!inArray('/admin/fraudtrack',$got->{'directories'}),'directory removed successfully');

  $loginClient->setTemporaryPasswordMarker();
  $got = getLoginInfo($loginClient);
  ok($got->{'passwordIsTemporary'}, 'temporary password marker set');

  $loginClient->clearTemporaryPasswordMarker();
  $got = getLoginInfo($loginClient);
  ok(!$got->{'passwordIsTemporary'}, 'temporary password marker cleared');
}

sub testSettingPassword {
  my $loginClient = new PlugNPay::Authentication::Login({
    login => 'pnpdemo'
  });
  $loginClient->setRealm('PNPADMINID');

  my $random = new PlugNPay::Util::RandomString();
  my $randomPassword = $random->randomAlphaNumeric(16);

  # set a random password then clear history for tests to work
  my $result = $loginClient->setPassword({
    password => $randomPassword
  });
  ok($result,'random password set for pre-test setup');

  $result = $loginClient->clearPasswordHistory();
  ok($result,'password history cleared successfully');

  my $firstPassword = 'thisIsAGoodPassword123';
  $result = $loginClient->setPassword({
    password => $firstPassword
  });
  ok($result,'password api call successful');

  $result = $loginClient->setPassword({
    password => $firstPassword
  });
  ok(!$result,'api call to set password the same as the current password failed (expected)');

  my $wrongPassword = 'not the correct password';
  my $badPassword = 'thisIsABadPassword123'; # bad because it contains 3+ letters/numbers in a row that are the same
  my $secondPassword = 'aSecondValue4Testing'; # satisfies all rules for new password vs old password

  $result = $loginClient->setPassword({
    password => $firstPassword,
    currentPassword => $wrongPassword
  });
  ok(!$result,'api call to update password with incorrect current password failed (expected)');

  $result = $loginClient->setPassword({
    password => $firstPassword,
    currentPassword => $firstPassword
  });
  ok(!$result,'api call to update password with same password as current password failed (expected)');

  $result = $loginClient->setPassword({
    password => $secondPassword,
    currentPassword => $firstPassword
  });
  ok($result,'api call to update password with a new allowable password successful');
}

sub getLoginInfo {
  my $client = shift;
  my $result = $client->getLoginInfo();
  return $result->get('loginInfo');
}