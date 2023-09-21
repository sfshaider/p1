#!/bin/env perl

#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );

use lib $ENV{'PNP_PERL_LIB'};

require_ok('rsautils');

testRecurring();
testRecurringAgain();
testMonthly();
testMonthlyAgain();

sub testRecurring {
  my $plaintext = '4111111111111111';
  my ($ciphertextRecurring) = rsautils::rsa_encrypt_file(undef,$plaintext,undef,undef);
  my $plaintextRecurring = rsautils::rsa_decrypt_file($ciphertextRecurring);
  is($plaintextRecurring,$plaintext, 'test recurring key');
}

sub testRecurringAgain {
  my $plaintext = '4111111111111111';
  my ($ciphertextRecurring) = rsautils::rsa_encrypt_file(undef,$plaintext,undef,undef);
  my $plaintextRecurring = rsautils::rsa_decrypt_file($ciphertextRecurring);
  is($plaintextRecurring,$plaintext, 'test recurring key again');
}

sub testMonthly {
  my $plaintext = '4111111111111111';
  my ($ciphertextMonth) = rsautils::rsa_encrypt_file(undef,$plaintext,undef,'log');
  my $plaintextMonth = rsautils::rsa_decrypt_file($ciphertextMonth);
  is($plaintextMonth,$plaintext, 'test monthly key');
}

sub testMonthlyAgain {
  my $plaintext = '4111111111111111';
  my ($ciphertextMonth) = rsautils::rsa_encrypt_file(undef,$plaintext,undef,'log');
  my $plaintextMonth = rsautils::rsa_decrypt_file($ciphertextMonth);
  is($plaintextMonth,$plaintext, 'test monthly key again');
}
