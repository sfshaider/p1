#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::Util::Encryption::LegacyKey();
use PlugNPay::CreditCard;

&keygen();
#&loadKey();
#&decrypt();
#&decrypt_preexisting();
#&decrypt_recurring();

sub keygen {
  my $manager = new PlugNPay::Util::Encryption::LegacyKey();
  my $status =  $manager->generateMonthlyKey('202312');
  if (!$status) {
    print "Keygen error: " . $status->getError() . ', DETAILS: '.  $status->getErrorDetails() . "\n";
  } else {
    print "Generated Key\n";
  }
}

sub loadKey {
  my $manager = new PlugNPay::Util::Encryption::LegacyKey();
  my $status = $manager->loadMonthlyKey('201908');
  my $key = $manager->getActiveKey();
  if (!$status) {
    print "Keyload Fail: " . $status->getErrorDetails() . "\n";
  } elsif (!$key) {
    print "Keyload Fail: null key\n";
  } else {
    print 'Loaded key via ' .$manager->getLoadedVia() . "\n";

  }
}

sub decrypt {
  my $cc = new PlugNPay::CreditCard('4111111111111111');
  my $enc = $cc->getYearMonthEncryptedNumber();
  print 'Encrypted card: ' . $enc . "\n";
  my $cc2 = new PlugNPay::CreditCard();
  $cc2->setNumberFromEncryptedNumber($enc);
  print 'Decrypted card: ' . $cc2->getNumber() . "\n";
}

sub decrypt_preexisting {
  my $preexisting = '201908 aes256 56d6b97880759468a2bfae0332525cce4fd061707c33c4703c6b34d0083ca72c';
  my $cc2 = new PlugNPay::CreditCard();
  $cc2->setNumberFromEncryptedNumber($preexisting);
  print 'Decrypted preexisting card: ' . $cc2->getNumber() . "\n";
}

sub decrypt_recurring {
  my $recurring = 'aes256 27cbc32250685753e4587a083034d3237f6bc81386e98ecc535820eba7ec6d69';
  my $cc2 = new PlugNPay::CreditCard();
  $cc2->setNumberFromEncryptedNumber($recurring);
  print 'Decrypted recurring card: ' . $cc2->getNumber() . "\n";
}

exit;
