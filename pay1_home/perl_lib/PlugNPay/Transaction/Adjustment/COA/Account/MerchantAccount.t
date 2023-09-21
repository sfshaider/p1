use strict;
use warnings;

use Test::More tests => 1;
use Test::Exception;
use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount');