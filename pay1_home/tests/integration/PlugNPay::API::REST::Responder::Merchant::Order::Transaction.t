#!/bin/env perl

BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

# Note: See end of this file for the base transaction template.

use strict;
use Test::More tests => 203;
use File::Basename;

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Sys::Time qw(yy mm);
use JSON::XS;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Transaction::Adjustment::Settings;


require_ok('PlugNPay::API::MockRequest');
require_ok('PlugNPay::Transaction::Updater');
require_ok('PlugNPay::API::REST');
require_ok('PlugNPay::Processor::Process::Settlement');


# set a default account
$ENV{'PNP_ACCOUNT'} ||= 'pnpdemo';
$ENV{'TEST_DISPLAY_OUTPUT'} ||= 0;
print STDERR 'Running tests for account: ' . $ENV{'PNP_ACCOUNT'} . "\n";

# disable adjustment
my $adjustmentSettings = new PlugNPay::Transaction::Adjustment::Settings($ENV{'PNP_ACCOUNT'});
$adjustmentSettings->setEnabled('0');
$adjustmentSettings->save();

my %tests;
my @testsToRun;

# read all the individual tests.
my $path = dirname(__FILE__);
my $subtestPath = $path . '/' . __FILE__ . '.d';

my @subtestFiles = getTests($subtestPath);
foreach my $subtestFile (@subtestFiles) {
  if (inArray('--skip-edge',\@ARGV) && $subtestFile =~ /_edge\.t$/) {
    print STDERR "skipping $subtestFile\n";
    next;
  }

  if (inArray('--skip-v1',\@ARGV) && $subtestFile =~ /_v1\.t$/) {
    print STDERR "skipping $subtestFile\n";
    next;
  }

  print STDERR "loading $subtestFile\n";
  my ($fh,$buffer);
  open($fh,'<',$subtestFile);
  sysread $fh, $buffer, -s $fh;
  close($fh);
  eval $buffer;
  if ($@) {
    print STDERR "Error reading subtest file: " . $subtestFile . "\n--> $@\n";
  }
}

foreach my $test (@testsToRun) {
  eval {
    &{$test}();
  };
  print $@ if $@;
}

sub getTests {
  my $base = shift;
  my $dh;

  opendir($dh,$base);
  my @allFiles = readdir($dh);

  my @subDirs = grep { -d "$base/$_" && $_ !~ /^\./ } @allFiles;
  my @subTests;

  # recursively get tests in subdirs.
  foreach my $subdir (@subDirs) {
    $subdir = "$base/$subdir";
    push @subTests, getTests($subdir);
  }

  # push tests in current dir.
  push @subTests, map { "$base/$_" } grep { -f "$base/$_" && $_ =~ /\.t$/ } @allFiles;

  return @subTests;
}





# basic auth template
sub basicAuthData {
  # exp data to use in templates
  my $yy = yy() + 1; # not a problem until year 2099, y3k
  my $mm = mm();
  return {
    "currency"=> "usd",
    "amount"=> "1.01",
    "billingInfo"=> {
      "email"=> 'usr@example.com',
      "country"=> "US",
      "city"=> "Hauppauge",
      "name"=> "Joseph Smith",
      "address"=> "123 Main St",
      "phone"=> "555-555-5555",
      "postalCode"=> "50001",
      "state"=> "NY"
    },
    "shippingInfo"=> {
      "email"=> 'usrmom@example.com',
      "country"=> "US",
      "city"=> "Port Jefferson",
      "notes"=> "send me a package",
      "name"=> "Joe's Mom",
      "address"=> "44 Left Ln",
      "phone"=> "555-555-1234",
      "postalCode"=> "50001",
      "state"=> "IA"
    },
    "security"=> {
      "ipAddress"=> "11.110.58.121"
    },
    "payment"=> {
      "card"=> {
        "expYear"=> "$yy",
        "number"=> "371746000000009",
        "cvv"=> "123",
        "expMonth"=> "$mm"
      },
      "mode"=> "auth",
      "type"=> "card"
    },
    "accountCode"=> {
      "1"=> "1234",
      "2"=> "g2g"
    },
    "customData"=> {
      "field1"=> "data_entry",
      "field2"=> "information"
    },
    "flags"=> []
  }
}

sub post {
  my $account = shift;
  my $url = shift;
  my $data = shift;
  my $mr = new PlugNPay::API::MockRequest();
  $mr->setResource($url);
  $mr->setMethod('POST');
  $mr->addHeaders({
    'content-type' => 'application/json'
  });
  $mr->setContent(encode_json($data));

  my $rest = new PlugNPay::API::REST('/api', { mockRequest => $mr });
  $rest->setRequestGatewayAccount($account);
  my $response = $rest->respond({ skipHeaders => 1 });
  my $responseData = decode_json($response);
  return $responseData;
}

sub put {
  my $account = shift;
  my $url = shift;
  my $data = shift;
  my $mr = new PlugNPay::API::MockRequest();
  $mr->setResource($url);
  $mr->setMethod('PUT');
  $mr->addHeaders({
    'content-type' => 'application/json'
  });
  $mr->setContent(encode_json($data));

  my $rest = new PlugNPay::API::REST('/api', { mockRequest => $mr });
  $rest->setRequestGatewayAccount($account);

  my $response = $rest->respond({ skipHeaders => 1 });
  my $responseData = decode_json($response);
  return $responseData;
}

sub get {
  my $account = shift;
  my $url = shift;
  my $mr = new PlugNPay::API::MockRequest();
  $mr->setResource($url);
  $mr->setMethod('GET');
  my $rest = new PlugNPay::API::REST('/api', { mockRequest => $mr });
  $rest->setRequestGatewayAccount($account);
  my $response = $rest->respond({ skipHeaders => 1 });
  my $responseData = decode_json($response);
  return $responseData;
}

sub del {
  my $account = shift;
  my $url = shift;
  my $data = shift;
  my $mr = new PlugNPay::API::MockRequest();
  $mr->setResource($url);
  $mr->setMethod('DELETE');
  if ($data) {
    $mr->addHeaders({
      'content-type' => 'application/json'
    });
    $mr->setContent(encode_json($data));
  }
  my $rest = new PlugNPay::API::REST('/api', { mockRequest => $mr });
  $rest->setRequestGatewayAccount($account);
  my $response = $rest->respond({ skipHeaders => 1 });
  my $responseData = decode_json($response);
  return $responseData;
}

sub settleLegacyTestProcessorTransaction {
  my $account = shift;
  my $transactionId = shift;
  # this is a terrible way to do this but there really isn't any other way to do it right now
  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpdata',q/
    UPDATE trans_log SET result = 'success', finalstatus = 'success' WHERE orderid = ? and username = ? AND trans_type = 'postauth'
  /,[$transactionId,$account]);
  $dbs->executeOrDie('pnpdata',q/
    UPDATE operation_log SET lastopstatus = 'success', postauthstatus = 'success' WHERE orderid = ? and username = ? AND lastop = 'postauth'
  /,[$transactionId,$account]);
}
