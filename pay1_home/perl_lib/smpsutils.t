#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 45;
use Test::Exception;

require_ok('smpsutils');

is(&smpsutils::checkcard('6767000000000000'),'sw','Check solo card type "sw"');

is(&smpsutils::checkcard('6759000000000000'),'ma','Check Maestro card type "ma"');
is(&smpsutils::checkcard('4903030000000000'),'ma','Check Maestro card type "ma"');
is(&smpsutils::checkcard('5000010000000000'),'ma','Check Maestro card type "ma"');
is(&smpsutils::checkcard('5600030000000000'),'ma','Check Maestro card type "ma"');
is(&smpsutils::checkcard('6000030000000000'),'ma','Check Maestro card type "ma"');

is(&smpsutils::checkcard('4111111111111111'),'vi','Check Visa card type "vi"');

is(&smpsutils::checkcard('5123450000000000'),'mc','Check mastercard type "mc"');
is(&smpsutils::checkcard('2221010000000000'),'mc','Check mastercard type "mc"');

is(&smpsutils::checkcard('347000000000000'),'ax','Check american express card type "ax"');

is(&smpsutils::checkcard('30689000000000'),'dc','Check diners club card type "dc"');
is(&smpsutils::checkcard('3001234500000000'),'dc','Check diners club card type "dc"');
is(&smpsutils::checkcard('3095000000000000'),'dc','Check diners club card type "dc"');
is(&smpsutils::checkcard('3897000000000000'),'dc','Check diners club card type "dc"');

is(&smpsutils::checkcard('6011000000000000'),'ds','Check discover card type "ds"');
is(&smpsutils::checkcard('6411000000000000'),'ds','Check discover card type "ds"');
is(&smpsutils::checkcard('6511000000000000'),'ds','Check discover card type "ds"');
is(&smpsutils::checkcard('6211000000000000'),'ds','Check discover card type "ds"');

is(&smpsutils::checkcard('3088000000000000'),'jc','Check JCB card type "jc"');
is(&smpsutils::checkcard('3096000000000000'),'jc','Check JCB card type "jc"');
is(&smpsutils::checkcard('3112000000000000'),'jc','Check JCB card type "jc"');
is(&smpsutils::checkcard('3158000000000000'),'jc','Check JCB card type "jc"');
is(&smpsutils::checkcard('3337000000000000'),'jc','Check JCB card type "jc"');
is(&smpsutils::checkcard('3538000000000000'),'jc','Check JCB card type "jc"');

is(&smpsutils::checkcard('7775000000000000'),'kc','Check Keycard type "kc"');
is(&smpsutils::checkcard('7776000000000000'),'kc','Check Keycard type "kc"');
is(&smpsutils::checkcard('7777000000000000'),'kc','Check Keycard type "kc"');

is(&smpsutils::checkcard('6046260000000000'),'pl','Check private label card type "pl"');
is(&smpsutils::checkcard('6050110000000000'),'pl','Check private label card type "pl"');
is(&smpsutils::checkcard('6030280000000000'),'pl','Check private label card type "pl"');
is(&smpsutils::checkcard('6036280000000000'),'pl','Check private label card type "pl"');

is(&smpsutils::checkcard('0420000000000'),'wx','Check Wex Fleet card type "wx"');
is(&smpsutils::checkcard('0430000000000'),'wx','Check Wex Fleet card type "wx"');
is(&smpsutils::checkcard('0480000000000'),'wx','Check Wex Fleet card type "wx"');
is(&smpsutils::checkcard('0498000000000'),'wx','Check Wex Fleet card type "wx"');
is(&smpsutils::checkcard('0481000000000'),'wx','Check Wex Fleet card type "wx"');
is(&smpsutils::checkcard('0481000000000'),'wx','Check Wex Fleet card type "wx"');
is(&smpsutils::checkcard('6900460000000000000'),'wx','Check Wex Fleet card type "wx"');
is(&smpsutils::checkcard('7071380000000000000'),'wx','Check Wex Fleet card type "wx"');

is(&smpsutils::checkcard('8767000000000000'),'pp','Check pnp private label card type "pp"');

is(&smpsutils::checkcard('9767000000000000'),'sv','Check pnp stored value card type "sv"');

is(&smpsutils::checkcard('1767000000000000'),'','Check invalid card type');

# gettransid tests for microservice-transid
my $transId;
lives_ok(sub {
  $transId = smpsutils::gettransid('pnpdemo','testprocessor');
}, 'Check to ensure that request to get trans id does not die');

ok( $transId > -1, 'Check to ensure that id returned is > -1, transid = ' . $transId);

test_calculateNativeAmountFromAuthCodeColumnData();

sub test_calculateNativeAmountFromAuthCodeColumnData {
  my $processor = 'planetpay';
  my $authCodeColumnData = '095205 V00000000000000000                          300300000000                            000000000000000000092000M,65899,124,7162924,7,07/06/2023,13:09:38:0016                  0100804 840,65899';
  my $nativeCurrency = 'usd';
  my $convertedAmount = '920.00';

  my $nativeAmount = smpsutils::calculateNativeAmountFromAuthCodeColumnData({
    processor => $processor,
    authCodeColumnData => $authCodeColumnData,
    nativeCurrency => $nativeCurrency,
    convertedAmount => $convertedAmount
  });

  is($nativeAmount,658.99,'nativeAmount calculated correctly');
}