#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('PlugNPay::Security::JWT');

my $token = &generateToken();


ok(defined $token,'Generated token successfully');
ok(&PlugNPay::Security::JWT::isValidToken($token), 'Validated Token');

sub generateToken {
  my $tokenData = {
    'secretType' => 'RS256',
    'claims' => {'merchant' => 'dylaninc'}
  };

  my $generated;
  eval {
    $generated = &PlugNPay::Security::JWT::generate($tokenData);
  };

  if ($@) {
    print STDERR "JWT generation failed: $@\n";
  }

  return $generated;
}
