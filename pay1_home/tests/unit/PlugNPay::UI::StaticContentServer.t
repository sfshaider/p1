#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );
use Data::Dumper;

use lib $ENV{'PNP_PERL_LIB'};


require_ok('PlugNPay::UI::StaticContent'); # test that we can load the module!

TestRandomStaticServer();
TestRandomNumberGeneration10000();
TestDevString();
TestDevStringForProduction();

sub TestRandomStaticServer {
  local %ENV;
  for (my $i = 0; $i < 10000; $i++) {
    my $server = PlugNPay::UI::StaticContent::randomStaticServer();
    diag($server);
    if ($server !~ /^www\d\.static\.gateway-assets\.com$/) {
      ok($server =~ /^www\d\.static\.gateway-assets\.com$/);
      diag("Bad server name: " . $server);
      last;
    }
  }
}

sub TestRandomNumberGeneration10000 {
  for (my $i = 0; $i < 10000; $i++) {
    my $x = PlugNPay::UI::StaticContent::_randomInt();
    if ($x % 1 != 0) {
      ok($x % 1 == 0);
      diag("Value is not an integer: " . $x);
    }
    if ($x >= 10) { # this is to prevent 10k test output lines, we want to is "ok" but only when we know it's going to fail.
      ok($x < 10);
      diag("Unexpected value: " . $x);
      last;
    }
  }
}

sub TestDevString {
  local %ENV;
  $ENV{'DEVELOPMENT'} = 'TRUE';
  my $devString = PlugNPay::UI::StaticContent::_devString();
  is($devString,'.dev');
}

sub TestDevStringForProduction {
  local %ENV;
  my $devString = PlugNPay::UI::StaticContent::_devString();
  is($devString,'');
}
