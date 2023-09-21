#!/bin/env perl

#################################################################################################################
# NOTE: most of the functions in PlugNPay::Transaction::Adjustment::Bucket are tested in the Adjustment tests.  #
# This script is for the functions that aren't                                                                  #
#################################################################################################################

use strict;
use Test::More tests => 23;
use Data::Dumper;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);

use lib $ENV{'PNP_PERL_LIB'};
require_ok('PlugNPay::Transaction::Adjustment::Bucket');

my $username = 'pnpdemo';

SKIP: {
  if (!skipIntegration("skipping integration tests because TEST_INTEGRATION environment variable is not '1'", 22)) {
    setBuckets($username);
    testGetBuckets($username);
    testBucketExistsForSubtypeID($username);
  }
}

sub setBuckets {
  my $username = shift;

  my $bucketData = [
    { 'subtypeID'       => '1',
      'base'            => '0',
      'coaRate'         => '0',
      'totalRate'       => '2',
      'fixedAdjustment' => '0'
    },
    { 'subtypeID'       => '1',
      'base'            => '1500',
      'coaRate'         => '0',
      'totalRate'       => '0',
      'fixedAdjustment' => '10'
    },
  ];

  my @bucketArray;
  foreach my $bucketInfo (@{$bucketData}) {
    my $bucket = new PlugNPay::Transaction::Adjustment::Bucket();
    $bucket->setPaymentVehicleSubtypeID($bucketInfo->{'subtypeID'});
    $bucket->setBase($bucketInfo->{'base'});
    $bucket->setCOARate($bucketInfo->{'coaRate'});
    $bucket->setTotalRate($bucketInfo->{'totalRate'});
    $bucket->setFixedAdjustment($bucketInfo->{'fixedAdjustment'});
    push @bucketArray,$bucket;
  }
  my $bucketCreator = new PlugNPay::Transaction::Adjustment::Bucket($username);
  $bucketCreator->setBuckets(\@bucketArray);

}

sub testGetBuckets {
  my $username = shift;

  # Get the higher base bucket
  my $bucketGetter = new PlugNPay::Transaction::Adjustment::Bucket($username);
  $bucketGetter->setMode('single');
  $bucketGetter->setPaymentVehicleSubtypeID('1');
  $bucketGetter->setTransactionAmount('2000');
  my $buckets = $bucketGetter->getBuckets();
  foreach my $bucketInfo (@{$buckets}) {
    is($bucketInfo->{'paymentVehicleSubtypeID'}, '1', 'payment vehicle subtype id is correct for higher base bucket');
    is($bucketInfo->{'base'}, '1500.000', 'base is correct for higher base bucket');
    is($bucketInfo->{'coaRate'}, '0.00', 'coa rate is correct for higher base bucket');
    is($bucketInfo->{'totalRate'}, '0.000', 'total rate is correct for higher base bucket');
    is($bucketInfo->{'fixedAdjustment'}, '10.000', 'fixed adjustment is correct for higher base bucket');
  }

  # Get the lower base bucket
  my $bucketGetter = new PlugNPay::Transaction::Adjustment::Bucket($username);
  $bucketGetter->setMode('single');
  $bucketGetter->setPaymentVehicleSubtypeID('1');
  $bucketGetter->setTransactionAmount('100');
  my $buckets = $bucketGetter->getBuckets();
  foreach my $bucketInfo (@{$buckets}) {
    is($bucketInfo->{'paymentVehicleSubtypeID'}, '1', 'payment vehicle subtype id is correct for lower base bucket');
    is($bucketInfo->{'base'}, '0.000', 'base is correct for lower base bucket');
    is($bucketInfo->{'coaRate'}, '0.00', 'coa rate is correct for lower base bucket');
    is($bucketInfo->{'totalRate'}, '2.000', 'total rate is correct for lower base bucket');
    is($bucketInfo->{'fixedAdjustment'}, '0.000', 'fixed adjustment is correct for lower base bucket');
  }


  # Get both buckets
  my $bucketGetter = new PlugNPay::Transaction::Adjustment::Bucket($username);
  $bucketGetter->setMode('cumulative');
  $bucketGetter->setPaymentVehicleSubtypeID('1');
  $bucketGetter->setTransactionAmount('2000');
  my $buckets = $bucketGetter->getBuckets();
  foreach my $bucketInfo (@{$buckets}) {
    if ($bucketInfo->{'base'} eq '1500.000') {
      is($bucketInfo->{'paymentVehicleSubtypeID'}, '1', 'payment vehicle subtype id is correct for higher base bucket when getting both buckets');
      is($bucketInfo->{'base'}, '1500.000', 'base is correct for higher base bucket when getting both buckets');
      is($bucketInfo->{'coaRate'}, '0.00', 'coa rate is correct for higher base bucket when getting both buckets');
      is($bucketInfo->{'totalRate'}, '0.000', 'total rate is correct for higher base bucket when getting both buckets');
      is($bucketInfo->{'fixedAdjustment'}, '10.000', 'fixed adjustment is correct for higher base bucket when getting both buckets');
    }
    if ($bucketInfo->{'base'} eq '0.000') {
      is($bucketInfo->{'paymentVehicleSubtypeID'}, '1', 'payment vehicle subtype id is correct for lower base bucket when getting both buckets');
      is($bucketInfo->{'base'}, '0.000', 'base is correct for lower base bucket when getting both buckets');
      is($bucketInfo->{'coaRate'}, '0.00', 'coa rate is correct for lower base bucket when getting both buckets');
      is($bucketInfo->{'totalRate'}, '2.000', 'total rate is correct for lower base bucket when getting both buckets');
      is($bucketInfo->{'fixedAdjustment'}, '0.000', 'fixed adjustment is correct for lower base bucket when getting both buckets');
    }
  }
}

sub testBucketExistsForSubtypeID {
  my $username = shift;

  my $bucket = new PlugNPay::Transaction::Adjustment::Bucket($username);

  my $idA = '1';
  my $idB = '2';

  is ($bucket->bucketExistsForSubtypeID($idA), 1, "bucket exists for subTypeId $idA");
  is ($bucket->bucketExistsForSubtypeID($idB), 0, "bucket does not exist for subTypeId $idB");

}