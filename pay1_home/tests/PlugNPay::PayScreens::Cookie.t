use diagnostics;
use warnings;
use strict;
use Test::More qw( no_plan );

require_ok('PlugNPay::PayScreens::Cookie');
my $c = new PlugNPay::PayScreens::Cookie();

# Cookie creation
my $testCookieData = {'username' => 'scotttest', 'payscreensVersion' => '2'};
like($c->createEncryptedCookie({'name' => 'payscreens', 'value' => $testCookieData}), qr/payscreens=\S\S/, 'Cookie was created');

# Cookie validation - modify to test different errors
my $testValidationData = {'cookie' => 'test',
            'decryptedCookie' => 'test2',
            'cookieTime' => 10,
            'validationTime' => 30,
            'cookieIP' => '127.0.0.1',
            'remoteIP' => '127.0.0.1'
};
is($c->validateCookie($testValidationData), '', 'Cookie is valid');
