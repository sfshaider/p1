#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 8;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

use PlugNPay::Testing qw(skipIntegration);
require_ok('PlugNPay::Legacy::MckUtils::Links');
testGenerateLinks();

sub testGenerateLinks {
  my $query = {'convert' => 'underscores', 'problem_link' => 'https://localhost:8443/should-convert-this/'};
  my $data = {
    'serverName'                => 'localhost',
    'serverPort'                => 443,
    'transactionParameterInput' => $query
  };

  # check generateLinksForSlashPay function
  my $responseQuery = PlugNPay::Legacy::MckUtils::Links::generateLinksForSlashPay($data);
  is($responseQuery->{'badcard_link'}, 'https://localhost/pay/', 'badcard link properly set');
  is($responseQuery->{'problem_link'}, 'https://localhost:8443/should-convert-this/', 'successfully loaded existing problem link');

  # check shouldGenerateLinkForField function
  my $transactionInputToCheck = {
    'transactionParameterInput' => '',
    'shouldForceReceipt' => 'no'
  };

  my $shouldCheck = PlugNPay::Legacy::MckUtils::Links::shouldGenerateLinkForField($transactionInputToCheck);
  ok($shouldCheck,'Valid link generation boolean logic worked correctly'); 

  $transactionInputToCheck->{'transactionParameterInput'} = 'this is some data that should not be';
  my $shouldFail = PlugNPay::Legacy::MckUtils::Links::shouldGenerateLinkForField($transactionInputToCheck);
  ok(!$shouldFail, 'Invalid link generation boolean logic worked correctly');

  $transactionInputToCheck->{'transactionParameterInput'} = '';
  $transactionInputToCheck->{'shouldForceReceipt'} = 'yes';
  my $shouldAlsoFail = PlugNPay::Legacy::MckUtils::Links::shouldGenerateLinkForField($transactionInputToCheck);
  ok(!$shouldAlsoFail, 'Force receipt boolean logic worked correctly');

  # check getDefaultLinkForSlashPay function
  my $default = PlugNPay::Legacy::MckUtils::Links::getDefaultLinkForSlashPay({'serverName' => 'testhost.com', 'serverPort' => 55555});
  is ($default, 'https://testhost.com:55555/pay/', 'default link creation works');

  # check convertFieldNamesFromHypthensToUnderscores function
  my $converted = PlugNPay::Legacy::MckUtils::Links::convertLinkFieldNamesFromHyphensToUnderscores(['badcard-link']);
  is($converted->[0], 'badcard_link', 'hypen conversion works correctly');
}
