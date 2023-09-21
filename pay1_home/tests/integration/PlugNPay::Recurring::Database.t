#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );
use Data::Dumper;

use lib $ENV{'PNP_PERL_LIB'};


require_ok('PlugNPay::Recurring::Database'); # test that we can load the module!

TestJamesTU2DatabaseProfileColumns();
TestJamesTU2DatabasePaymentSourceColumns();


sub TestJamesTU2DatabaseProfileColumns {
  my $db = new PlugNPay::Recurring::Database({ database => 'jamestu2' });
  my $profileColumns = $db->profileColumns();
  my $columnCount = @{$profileColumns};
  diag(Dumper($profileColumns));
}

sub TestJamesTU2DatabasePaymentSourceColumns {
  my $db = new PlugNPay::Recurring::Database({ database => 'jamestu2' });
  my $paymentSourceColumns = $db->paymentSourceColumns();
  my $columnCount = @{$paymentSourceColumns};
  diag(Dumper($paymentSourceColumns));
}
