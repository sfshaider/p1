#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef;
  use lib '/home/pay1/perl_lib';
  require smps;
  require mckutils_strict;
  require PlugNPay::GatewayAccount::LinkedAccounts::File;
}

use strict;


my $smps = new smps();

##########################
# Direct test loadLinked #
##########################
print "Direct test loadLinked\n";
my $linkedAccountPath = '/home/pay1/tests/';
my $linkedAccountFile = 'dylaninc.txt';
my $webDataFile = new PlugNPay::WebDataFile();
$webDataFile->readFile({ fileName => 'chrisincco.txt', storageKey => 'linkedAccounts' });

#######################
# Test parse template #
#######################
print "Test parse template\n";
my %result = (
  'card-number' => '411111111111',
  'publisher-name' => 'dylaninc',
  'item1' => 'an',
  'cost1' => '1.00',
  'description1' => 'some stuff',
  'quantity1' => '1',
  'currency_symbol1' => 'usd',
  'card-amount' => '1.10',
  'tax' => '0.10'
);

&smps::parse_template('/home/pay1/web/admin/templates/iphone/', 'iphone.htm', %result) . "\n"; # this function also prints

##########################
# Test storeresults here #
##########################
print "Test storeresults here\n";
my %result = (
  'MErrMsg' => '',
  'amount' => 'usd 1.00',
  'mode'   => 'return',
  'FinalStatus' => 'success',
);
my $features = new PlugNPay::Features('dylaninc','general');
my $f = $features->getFeatures();
%smps::feature = %{$f};
my $onload = &smps::storeresults('return', %result);
my ($garbo, $fileAndGarbo) = split(/\?/,$onload);
my ($filename, $superTrash) = split("'", $fileAndGarbo);
$filename =~ s/[^a-zA-Z0-9]//g;

my $path = '/home/p/pay1/private/tranresults/';
my $file = $filename . '.txt';

my $migrator = new PlugNPay::WebDataFile();
my ($results,$contentType) = $migrator->readFile({
  'fileName' => $file,
  'localPath' => $path,
  'storageKey' => 'transactionResults'
});

my @lines = split("\n", $results);
foreach my $line (@lines) {
  print $line . "\n";
}

exit;
