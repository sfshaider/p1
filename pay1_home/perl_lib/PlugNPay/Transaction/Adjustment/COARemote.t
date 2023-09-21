use strict;
use warnings;

use Test::More tests => 5;
use Test::Exception;
use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::Transaction::Adjustment::COARemote');
require_ok('PlugNPay::Transaction::Adjustment::Settings');

SKIP: {
  if (not skipIntegration("skipping integration tests",1)) {
    my $s = new PlugNPay::Transaction::Adjustment::Settings('pnpdemo');
    
    my $coaAccountNumber = $s->getCOAAccountNumber();
    my $coaAccountIdentifier = $s->getCOAAccountIdentifier();
    my $amount = '1.00';
    my $transactionIdentifier = '1234567890987654321';
    my $bin = '4111111111111111';

    my $cr = new PlugNPay::Transaction::Adjustment::COARemote();
    $cr->setTransactionAmount($amount);
    $cr->setTransactionIdentifier($transactionIdentifier);
    $cr->setAccountIdentifier($coaAccountIdentifier);
    $cr->setAccountNumber($coaAccountNumber);
    $cr->setCardNumber($bin);

    my $resp = $cr->getResponse();
    is($resp->{'isDebit'},1,'isDebit is 1');
    is($resp->{'cardType'},'debit','cardType is debit');
    is($resp->{'cardBrand'},'Visa','cardBrand is Visa');
  }
}