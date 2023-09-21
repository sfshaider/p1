use strict;
use warnings;

use Test::More tests => 3;
use Test::Exception;
use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::Transaction::Adjustment::GlobalSettings');

my $gs = new PlugNPay::Transaction::Adjustment::GlobalSettings();
is($gs->getHost(),'coa.local','host is coa.local');
is($gs->getCardLength(),12,'card length is 12');
