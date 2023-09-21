#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );
use PlugNPay::CreditCard::Encryption;
use Data::Dumper;

use lib $ENV{'PNP_PERL_LIB'};


require_ok('PlugNPay::CreditCard'); # test that we can load the module!

TestSetEncryptedAccount();
TestSetEncryptedNumber();
TestLoadEncryptedSwipe();
TestDeleteEncryptedSwipe();

sub TestSetEncryptedAccount {
  my $encrypted = '202003 aes256 56d6b97880759468a2bfae0332525cce4fd061707c33c4703c6b34d0083ca72c';
  my $expected = '4111111111111111';
  my $cc = new PlugNPay::CreditCard();
  $cc->setAccountFromEncryptedNumber($encrypted);
  is($cc->getNumber(),$expected);
}

sub TestSetEncryptedNumber {
  my $encrypted = '202003 aes256 56d6b97880759468a2bfae0332525cce4fd061707c33c4703c6b34d0083ca72c';
  my $expected = '4111111111111111';
  my $cc = new PlugNPay::CreditCard();
  $cc->setNumberFromEncryptedNumber($encrypted);
  is($cc->getNumber(),$expected);
}

sub TestLoadEncryptedSwipe {
  my $cc = new PlugNPay::CreditCard();
  my $origKSN = '12345AAABBBCCCDDD';
  my $origSwipe = '12345AAABBBCCCDDD67890EEEFFFGGG';
  my $origStatusCode = '001';
  my $origStatusMessage = 'GOOD';

  # save
  $cc->_saveEncryptedSwipe($origKSN,$origSwipe,$origStatusCode,$origStatusMessage);

  #load
  my $swipeData = $cc->_loadEncryptedSwipe($origKSN);
  my $loadedKSN = $swipeData->{'ksn'};
  my $loadedSwipe = $swipeData->{'re_encrypted_data'};
  my $loadedStatusCode = $swipeData->{'status_code'};
  my $loadedStatusMessage = $swipeData->{'status_message'};

  my $encryption = new PlugNPay::CreditCard::Encryption();
  my $loadedSwipeDecrypted = $encryption->decryptMagstripe($loadedSwipe);

  is($origKSN, $loadedKSN, 'saved and loaded ksn match');
  is($origSwipe, $loadedSwipeDecrypted, 'saved and loaded swipe match');
  is($origStatusCode, $loadedStatusCode, 'saved and loaded status code match');
  is($origStatusMessage, $loadedStatusMessage, 'saved and loaded status message match');
}

sub TestDeleteEncryptedSwipe {
  my $cc = new PlugNPay::CreditCard();
  my $origKSN = '12345AAABBBCCCDDD';
  my $origSwipe = '12345AAABBBCCCDDD67890EEEFFFGGG';
  my $origStatusCode = '001';
  my $origStatusMessage = 'GOOD';

  #save
  $cc->_saveEncryptedSwipe($origKSN,$origSwipe,$origStatusCode,$origStatusMessage);

  #delete
  $cc->_deleteEncryptedSwipe($origKSN);

  #attempt to load
  my $swipeData = $cc->_loadEncryptedSwipe($origKSN);
  my $loadedKSN = $swipeData->{'ksn'};

  is($loadedKSN, undef, 'delete successful');
}
