#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );

use lib $ENV{'PNP_PERL_LIB'};

require_ok('PlugNPay::Transaction'); # test that we can load the module!


TestInvalidOrderIdEnforced();
TestInvalidOrderIdNotEnforced();
TestInvalidMerchantTransactionIdEnforced();
TestInvalidMerchantTransactionIdNotEnforced();
TestTransactionBaseAmount();

# max valid order id is 18446744073709551615, appending 1 to test
sub TestInvalidOrderIdEnforced {
  my $t = new PlugNPay::Transaction('auth','credit');
  eval {
    $t->setOrderID('184467440737095516151', 0);
  };
  isnt($@,'','test enforcement of large order ids explicitly enabled');
}

sub TestInvalidOrderIdNotEnforced {
  my $t = new PlugNPay::Transaction('auth','credit');
  eval {
    $t->setOrderID('184467440737095516151', 1);
  };
  is($@,'','test enforcement of large order ids explicitly disabled');

  # currently default is to not enforce
  eval {
    $t->setOrderID('184467440737095516151');
  };
  is($@,'','test default non-enforcement of large order ids');
}

# max valid order id is 18446744073709551615, appending 1 to test
sub TestInvalidMerchantTransactionIdEnforced {
  my $t = new PlugNPay::Transaction('auth','credit');
  eval {
    $t->setOrderID('184467440737095516151', 0);
  };
  isnt($@,'','test enforcement of large transaction ids explicitly enabled');
}

sub TestInvalidMerchantTransactionIdNotEnforced {
  my $t = new PlugNPay::Transaction('auth','credit');
  eval {
    $t->setMerchantTransactionID('184467440737095516151', 1);
  };
  is($@,'','test enforcement of large transaction ids explicitly disabled');

  # currently default is to not enforce
  eval {
    $t->setMerchantTransactionID('184467440737095516151');
  };
  is($@,'','test default non-enforcement of large transaction ids');
}

sub TestTransactionBaseAmount {
  my $t = new PlugNPay::Transaction('auth','credit');
  $t->setTransactionAmount(10.00);
  $t->setTransactionAmountAdjustment(2.00);
  is($t->getBaseTransactionAmount(),8.00,'test base transaction amount generated from transaction amount and adjustment amount');
}
