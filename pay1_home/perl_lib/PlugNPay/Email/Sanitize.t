#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 7;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('PlugNPay::Email::Sanitize');

my $sanitize = new PlugNPay::Email::Sanitize();

my $input = '"no\"re<p,ly"@p>l$u\`%g(np)a:;y.c|"!om,trash@plugnpay.com';
is($sanitize->sanitize($input),'"norep,ly"@plugnpay.com', 'sanitize email address properly, quoted local');

$input = 'no\"re<p,ly@p>l$u\`%g(np)a:;y.c|"!om,trash@plugnpay.com';
is($sanitize->sanitize($input),'noreply@plugnpay.com','sanitize email address properly, unquoted local');
is(PlugNPay::Email::Sanitize::sanitize($input),'noreply@plugnpay.com','sanitize email address properly, unquoted local, static call');

is($sanitize->sanitize(undef),undef,'sanitize returns undef if input is undef');

TODO: {
  local $TODO = 'fix sanitize to accomodate this';
  $input = '"no\"re<p,ly@p>l$u\`%g(np)a:;y.c|"!om,trash@plugnpay.com';
  is($sanitize->sanitize($input),'noreply@plugnpay.com','sanitize email address properly, half quoted local, start');

  $input = 'no\"re<p,ly"@p>l$u\`%g(np)a:;y.c|"!om,trash@plugnpay.com';
  is($sanitize->sanitize($input),'noreply@plugnpay.com','sanitize email address properly, half quoted local, end');
}
