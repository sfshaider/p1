#!/bin/env perl

use strict;
use Test::More qw( no_plan );
use PlugNPay::Util::Temp;

sub testStore {
  my $temp = new PlugNPay::Util::Temp();
  $temp->setKey('testStore');
  $temp->setValue({ 'data' => 'this is a test' });
  $temp->setPassword('testing123');
  my $status = $temp->store();
  ok($status); 
}

sub testStoreAndRetrieve {
  my $temp = new PlugNPay::Util::Temp();
  my $data = 'this is a test';
  $temp->setKey('testStoreAndRetrieve');
  $temp->setValue({ 'data' => $data });
  $temp->setPassword('testing123');
  my $storeStatus = $temp->store();

  my $retrieveStatus = $temp->fetch('testStoreAndRetrieve','testing123');
  ok($storeStatus && $retrieveStatus && $temp->getValue()->{'data'} eq $data);
}

sub testFailureToStore {
  # how do test?
}

sub testFailureToRetreive {
  my $temp = new PlugNPay::Util::Temp();
  my $retrieveStatus = $temp->fetch('testRetrieveFailure','testing123');
  ok(!$retrieveStatus);
}

my $tests = [
  'testStore',
  'testStoreAndRetrieve',
  'testFailureToRetreive'
];

sub runTests {
  my $status = 1;

  foreach my $test (@{$tests}) {
    print 'running test: ' . $test . "\n";
    eval "$test()";
    if ($@) {
      print "Test $test failed. $@\n";
    }
  }
}

runTests();
