#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

# Note: See end of this file for the base transaction template.

use strict;
use Test::More qw( no_plan );

use lib $ENV{'PNP_PERL_LIB'};

require_ok('PlugNPay::Util::UniqueID');

testConversionFromHexToBinary();
testFromBinaryToHex();
testValidate();
testValidateLegacyOID();

sub testConversionFromHexToBinary {
  my $uid = new PlugNPay::Util::UniqueID();
  my $hex = $uid->inHex();
  my $uid2 = new PlugNPay::Util::UniqueID();
  is($uid->inBinary(),$uid2->fromHexToBinary($hex),'conversion from hex to binary');
}

sub testFromBinaryToHex {
  my $uid = new PlugNPay::Util::UniqueID();
  my $bin = $uid->inBinary();
  my $uid2 = new PlugNPay::Util::UniqueID();
  is($uid->inHex(), $uid2->fromBinaryToHex($bin),'conversion from binary to hex');
}

sub testValidate {
  my $uid = new PlugNPay::Util::UniqueID();
  my $hex = $uid->inHex();
  my $uid2 = new PlugNPay::Util::UniqueID();
  $uid2->fromHex($hex);
  is($uid2->validate(),1,'test validation');
}

sub testValidateLegacyOID {
  my $uid = new PlugNPay::Util::UniqueID();
  my $hex = '2021062315004815451'; # finger quotes
  $uid->fromHex($hex);
  isn't($uid->validate(),1,'test validation of legacy oid');
}
