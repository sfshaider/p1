use strict;
use warnings;

use Test::More tests => 7;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('security');

testCreateVerifcationHash();
testGenerateSharedSecret();

sub testCreateVerifcationHash {
  # inputs: 
  # my $standardFields = $input->{'standardFields'}; # array ref
  # my $customFields = $input->{'customFields'}; # array ref
  # my $action = $input->{'action'}; # string
  # my $inputSecret = $input->{'secret'}; # string
  # my $window = $input->{'window'}; # integer (minutes, optional)

  # "hashkey" input (no window)
  my @standard = ('a','c','e');
  my @custom = ('b','d','e');
  my $input = {
    standardFields => \@standard,
    customFields => \@custom,
    action => 'create',
    secret => 'thisWillBeRemovedForCreate'
  };
  my $value = security::createVerificationHash($input);
  like($value,qr/\|a\|b\|c\|d\|e/,'createVerificationHash merged, deduped, and sorted fields');
  isnt(substr($value,0,length($input->{'secret'})),$input->{'secret'},'createVerificationHash did not include input secret');

  $input = {
    standardFields => \@standard,
    customFields => \@custom,
    action => '',
    secret => 'thisWillBeRemovedForCreate'
  };
  $value = security::createVerificationHash($input);
  is($value,'thisWillBeRemovedForCreate|a|b|c|d|e','createVerification hash created successfully for blank action');

  # "authhashkey" input (with window)
  $input = {
    standardFields => \@standard,
    customFields => \@custom,
    action => 'create',
    secret => 'thisWillBeRemovedForCreate',
    window => 10
  };
  $value = security::createVerificationHash($input);
  like($value,qr/^10\|.*/,'createVerificationHash inserts window at the front of the value');
}

sub testGenerateSharedSecret {
  my $secret = security::generateSharedSecret();
  is(length($secret),25,'generateSharedSecret default secret length is 25');
  $secret = security::generateSharedSecret(10);
  is(length($secret),10,'generateSharedSecret creates proper length secret with input');
}