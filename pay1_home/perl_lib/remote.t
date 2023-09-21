#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 23;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use PlugNPay::GatewayAccount;

require_ok('remote');

# set up mocking for tests
my $mock = Test::MockObject->new();

SKIP: {
  if (!defined $ENV{'TEST_INTEGRATION'} || $ENV{'TEST_INTEGRATION'} ne '1') {
    skip("Skipping database tests because TEST_INTEGRATION environment variable is not '1'",8);
  }

  # test checking for card number potential validity
  testCardIsPotentiallyValid();

  # test getRecurringCustomerTableLengths()

  my $lengthHashNormal = {
    'shipcity'      => 40,
    'enccardnumber' => 255,
    'startdate'     => 10,
    'purchaseid'    => 20,
    'shipaddr2'     => 40,
    'state'         => 40,
    'email'         => 50,
    'password'      => 20,
    'enddate'       => 10,
    'plan'          => 20,
    'exp'           => 10,
    'name'          => 40,
    'accttype'      => 12,
    'username'      => 100,
    'orderid'       => 24,
    'zip'           => 14,
    'balance'       => 12,
    'acct_code4'    => 60,
    'cardnumber'    => 10,
    'monthly'       => 12,
    'shipstate'     => 40,
    'result'        => 20,
    'commcardtype'  => 255,
    'status'        => 20,
    'lastattempted' => 10,
    'shacardnumber' => 50,
    'addr2'         => 40,
    'city'          => 40,
    'fax'           => 30,
    'acct_code'     => 12,
    'addr1'         => 40,
    'company'       => 40,
    'country'       => 40,
    'billusername'  => 24,
    'lastbilled'    => 10,
    'shipzip'       => 14,
    'shipcountry'   => 40,
    'phone'         => 30,
    'billcycle'     => 10,
    'length'        => 6,
    'shipname'      => 40,
    'shipaddr1'     => 40,
    'shorty'        => 2
  };
  my $lenthHashSub1 = {
    'shipcity'      => 39,
    'enccardnumber' => 254,
    'startdate'     => 9,
    'purchaseid'    => 19,
    'shipaddr2'     => 39,
    'state'         => 39,
    'email'         => 49,
    'password'      => 19,
    'enddate'       => 9,
    'plan'          => 19,
    'exp'           => 9,
    'name'          => 39,
    'accttype'      => 11,
    'username'      => 99,
    'orderid'       => 23,
    'zip'           => 13,
    'balance'       => 11,
    'acct_code4'    => 59,
    'cardnumber'    => 9,
    'monthly'       => 11,
    'shipstate'     => 39,
    'result'        => 19,
    'commcardtype'  => 254,
    'status'        => 19,
    'lastattempted' => 9,
    'shacardnumber' => 49,
    'addr2'         => 39,
    'city'          => 39,
    'fax'           => 29,
    'acct_code'     => 11,
    'addr1'         => 39,
    'company'       => 39,
    'country'       => 39,
    'billusername'  => 23,
    'lastbilled'    => 9,
    'shipzip'       => 13,
    'shipcountry'   => 39,
    'phone'         => 29,
    'billcycle'     => 9,
    'length'        => 5,
    'shipname'      => 39,
    'shipaddr1'     => 39
  };
  my $lenthHashSub1Else = {
    'shipcity'      => 39,
    'enccardnumber' => 254,
    'startdate'     => 9,
    'purchaseid'    => 19,
    'shipaddr2'     => 39,
    'state'         => 39,
    'email'         => 49,
    'password'      => 19,
    'enddate'       => 9,
    'plan'          => 19,
    'exp'           => 9,
    'name'          => 39,
    'accttype'      => 11,
    'username'      => 99,
    'orderid'       => 23,
    'zip'           => 13,
    'balance'       => 11,
    'acct_code4'    => 59,
    'cardnumber'    => 9,
    'monthly'       => 11,
    'shipstate'     => 39,
    'result'        => 19,
    'commcardtype'  => 254,
    'status'        => 19,
    'lastattempted' => 9,
    'shacardnumber' => 49,
    'addr2'         => 39,
    'city'          => 39,
    'fax'           => 29,
    'acct_code'     => 11,
    'addr1'         => 39,
    'company'       => 39,
    'country'       => 39,
    'billusername'  => 23,
    'lastbilled'    => 9,
    'shipzip'       => 13,
    'shipcountry'   => 39,
    'phone'         => 29,
    'billcycle'     => 9,
    'length'        => 5,
    'shipname'      => 39,
    'shipaddr1'     => 39,
    'shorty'        => 2
  };

  my $equal = 1;
  my $result;
  $result = remote::getRecurringCustomerTableLengths( 'jamestu2', { gt5sub1 => 1, gt5else => 1 } );
  foreach my $key ( keys %{$result} ) {
    $equal &&= $result->{$key} eq $lenthHashSub1Else->{$key};
  }
  ok( $equal, "getRecurringCustomerTableLengths(): gt5sub1,gt5else lengths match expected lengths" );

  $equal = 1;
  $result = remote::getRecurringCustomerTableLengths( 'jamestu2', { gt5sub1 => 1 } );
  foreach my $key ( keys %{$result} ) {
    $equal &&= $result->{$key} eq $lenthHashSub1->{$key};
  }
  ok( $equal, "getRecurringCustomerTableLengths(): gt5sub1 lengths match expected lengths" );

  $equal = 1;

  $result = remote::getRecurringCustomerTableLengths('jamestu2');
  foreach my $key ( keys %{$result} ) {
    $equal &&= $result->{$key} eq $lengthHashNormal->{$key};
  }
  ok( $equal, "getRecurringCustomerTableLengths(): normal lengths match expected lengths" );

  TODO: {
    local $TODO = "Need to create a transaction for this to return prev against so that one always exists.";
    ok(&test_new_returnprev(), "_new_returnprev(): No problem when attempting returnprev");
  }
}

sub test_new_returnprev {
  my $gatewayAccount = new PlugNPay::GatewayAccount('pnpdemo');
  
  my $query = {
    'publisher-name' => 'pnpdemo',
    'prevorderid' => '2023021703413235802',
    'amount' => '1.00',
    'currency' => 'usd'
  };

  my %results = &remote::_new_returnprev($gatewayAccount, $query);
  return $results{'FinalStatus'} ne 'problem';
}

sub testCardIsPotentiallyValid {
  my $wexThatPassesLuhn10 = "6900461111111111116";
  my $wexThatDoesNotPassLuhn10 = "6900461111111111111";
  my $visaTestDebit = "4111111111111111";
  my $badVisaTestDebit = "4111111111111110";

  my $cc = new PlugNPay::CreditCard($wexThatPassesLuhn10);
  ok(remote::cardIsPotentiallyValid($cc), "wex that passes luhn10 is potentially valid");
  $cc->setNumber($wexThatDoesNotPassLuhn10);
  ok(remote::cardIsPotentiallyValid($cc), "wex that does not pass luhn10 is potentially valid");
  $cc->setNumber($visaTestDebit);
  ok(remote::cardIsPotentiallyValid($cc), "visa test debit card is potentially valid");
  $cc->setNumber($badVisaTestDebit);
  ok(!remote::cardIsPotentiallyValid($cc), "bad visa test debit card is NOT potentially valid")
}

testCheckDBExists();
testHandleModeNotPermitted();

sub testCheckDBExists {
  my %testDataBaseHash = (
    'testDB' => {
      'username' => 'test username',
      'password' => 'password123',
      'host' => 'www.example.org',
      'port' => '3000',
      'database' => 'test_db'
    }
  );

  # mock
  my $miscutilsMock = Test::MockModule->new('miscutils');
  $miscutilsMock->redefine(
    'dbhconnect' => sub {
      my $database = shift;

      if ($testDataBaseHash{$database}) {
        return {'dbh' => $testDataBaseHash{$database}, 'databaseName' => $database};
      } else {
        die("Failed to load db info for $database via database directly.  Giving up.");
      }
    }
  );

  # test that $dbh is defined and $error is undef if database is found
  my ( $dbh, $error ) = remote::checkDBExists("testDB");
  isnt($dbh, undef, '$dbh is defined when db exists');
  ok(ref($dbh) eq 'HASH', '$dbh is defined');
  is($error, undef, '$error is undefined when db exists');

  # test that $dbh is undefined and $error is defined if database is not found
  my ( $dbh2, $error2 ) = remote::checkDBExists("nonexistingDB");
  is($dbh2, undef, '$dbh is undefined when db does not exist');
  ok($error2 =~ /^Failed to load db info for nonexistingDB via database directly.  Giving up./, '$error is defined when db does not exist');
};

sub testHandleModeNotPermitted {
  my $log = {};

  # mock
  my $loggerMock = Test::MockModule->new('PlugNPay::Logging::DataLog');
  $loggerMock->redefine(
    'log' => sub {
      my ( $self, $logData, $options ) = @_;
      $log = $logData;
    }
  );

  # test that a error: 'Failed to load db info for nonexistingDB via database directly.  Giving up.' returns result hash with the correct values
  my %result = remote::handleModeNotPermitted({}, "Failed to load db info for nonexistingDB via database directly.  Giving up.");
  is($log->{'message'}, 'An error occurred while attempting to load db info.', "log message was correctly logged");
  is($log->{'error'},  "Failed to load db info for nonexistingDB via database directly.  Giving up.", "error message was correctly logged");
  is($result{'FinalStatus'}, "problem", "finalStatus returns 'problem' when db fails to load");
  is($result{'resp-code'}, "P93", "resp-code returns 'P93' error status when db fails to load");
  is($result{'MErrMsg'}, "Mode not permitted for this account.", "MErrMsg returns 'Mode not permitted for this account.' error message when db fails to load");

  # test that when an error != 'Failed to load db info for nonexistingDB via database directly.  Giving up.' returns result hash with the correct values
  my %result2 = remote::handleModeNotPermitted({}, "Some other DB error.");
  is($log->{'message'}, 'An error occurred while attempting to load db info.', "log message was correctly logged");
  is($log->{'error'}, "Some other DB error.", "error message was correctly logged");
  is($result2{'FinalStatus'}, "problem", "finalStatus returns 'problem' when db there is a random db error");
  is($result2{'MErrMsg'}, "Unknown error, please contact support.", "MErrMsg returns 'Mode not permitted for this account.' error message when there is a random db error");
}
