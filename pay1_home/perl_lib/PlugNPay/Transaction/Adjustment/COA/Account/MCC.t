use strict;
use warnings;

use Test::More tests => 4;
use Test::Exception;
use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::Transaction::Adjustment::COA::Account::MCC');

my $mcc = new PlugNPay::Transaction::Adjustment::COA::Account::MCC();

my $testMcc = '9399';
$mcc->setMCC($testMcc);
is($mcc->getMCC,$testMcc,'getMCC returns the same mcc that was set');

SKIP: {
  if (not skipIntegration('skipping integration tests')) {
    my $valid = $mcc->isValid();

    # as of writing this test, 9399 is a valid mcc
    ok($valid,'isValid returns true for a valid mcc');
    $mcc->setMCC('0');
    $valid = $mcc->isValid();
    ok(!$valid,'isValid returns false for an invalid mcc');
  }
}
