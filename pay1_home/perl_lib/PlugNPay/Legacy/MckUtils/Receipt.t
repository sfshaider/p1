#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 20;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);

require_ok('PlugNPay::Legacy::MckUtils::Receipt');

my $result; # used for results of sub calls to test for values

# Mock PlugNPay::DBConnection
my $noQueries = sub {
  print STDERR new PlugNPay::Util::StackTrace()->string("\n") . "\n";
  die('unexpected query executed')
 };
my $dbsMock = Test::MockModule->new('PlugNPay::DBConnection');
$dbsMock->redefine(
'executeOrDie' => $noQueries,
'fetchallOrDie' => $noQueries
);

my $featuresMock = Test::MockModule->new('PlugNPay::Features');
my $featureHash = {};
$featuresMock->redefine(
'new' => sub {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
},
'set' => sub {
  shift;
  my $featureName = shift;
  my $featureValue = shift;
  $featureHash->{$featureName} = $featureValue;
},
'get' => sub {
  shift;
  my $featureName = shift;
  return $featureHash->{$featureName};
}
);

my $wdfMock = Test::MockModule->new('PlugNPay::WebDataFile');
my $wdfReadCount = 0;
my $wdfContent = '';
sub wdfReadFileMock {
  $wdfReadCount++;
  return $wdfContent;
}
$wdfMock->redefine(
'readFile' => \&wdfReadFileMock
);

# generateReceiptRules()
my $generateReceiptLoadRulesInput = {
  templateType => 'thankyou',
  client => 'blah',
  mode => 'auth',
  username => 'pnpdemo',
  reseller => 'devresell',
  cobrand => 'pnpcobrand',
  receiptType => 'pos_',
  payMethod => 'credit',
  isAch => 0,
  templateName => 'custom'
};

my $creditRules = PlugNPay::Legacy::MckUtils::Receipt::_generateReceiptLoadRules($generateReceiptLoadRulesInput);
my %files = map { sprintf('%s%s', $_->{'subPrefix'},$_->{'fileName'}) => 1 } @{$creditRules};
is($files{'thankyou/pnpdemo_credit.htm'},1,'paymethod template exists in rules');
is($files{'thankyou/pnpdemo_pos.htm'},1,'receiptType template exists in rules');
is($files{'virtualterm/cobrand/thankyou/pnpcobrand_auth.htm'},1,'cobrand mode template exists in rules');
is($files{'virtualterm/thankyou/pnpdemo_auth.htm'},1,'mode template exists in rules');
is($files{'virtualterm/thankyou/cobrand/pnpcobrand_auth.htm'},1,'alternate cobrand template exists in rules');
is($files{'thankyou/pnpdemo.htm'},1,'default merchant template exists in rules');
is($files{'thankyou/devresell_std.htm'},1,'default reseller template exists in rules');
is($files{'thankyou/pnpdemo_pos_custom.htm'},1,'custom pos template exists in rules');
is($files{'thankyou/cobrand/pnpcobrand.htm'},1,'cobrand template exists in rules');
is($files{'thankyou/pnpdemo_custom.htm'},1,'custom merchant template exists in rules');
is($files{'thankyou/pnpdemo_std_custom.htm'},1,'merchant standard custom(?) receipt exists in rules');
is($files{'thankyou/pnpdemo_std.htm'},1,'merchant standard receipt exists in rules');

# generateReceipt()
my @generateReceiptInput = ({
  templateType => 'thankyou',
  client => 'blah',
  mode => 'auth',
  username => 'pnpdemo',
  reseller => 'devresell',
  cobrand => 'pnpcobrand',
  receiptType => 'pos_',
  payMethod => 'credit',
  isAch => 0,
  templateName => 'custom'
},{
  query => {
    'someVariable1' => 'value1',
    'someVariable2' => 'value2'
  },
  tableContent => 'table goes here'
});

my $rendered = PlugNPay::Legacy::MckUtils::Receipt::_generateReceipt(@generateReceiptInput);
is($wdfReadCount,13,'WebDataFile attempted to read the expected number of files');
$wdfContent = <<"EOF";
content goes here
someVariable1: '[pnp_someVariable1]'
someVariable2: '[pnp_someVariable2]'
table: '[TABLE]'
EOF
$rendered = PlugNPay::Legacy::MckUtils::Receipt::_generateReceipt(@generateReceiptInput);
like($rendered,qr/someVariable1: 'value1'/,'someVariable1 substituted');
like($rendered,qr/someVariable2: 'value2'/,'someVariable2 substituted');
like($rendered,qr/table: 'table goes here'/,'table substituted');

# getReceipt()
my $getReceiptInput = {
    mckutils_merged => {
    FinalStatus => 'success',
    client => 'blah',
    mode => 'auth',
    publisher_name => 'pnpdemo',
    cobrand => 'pnpcobrand',
    receipt_type => 'pos_',
    routingnum => '999999992',
    paytemplate => 'custom',
    someVariable1 => 'value1',
    someVariable2 => 'value2'
  },
  reseller => 'devresell',
  tableContent => 'table goes here'
};

$rendered = PlugNPay::Legacy::MckUtils::Receipt::getReceipt($getReceiptInput);
like($rendered,qr/someVariable1: 'value1'/,'someVariable1 substituted');
like($rendered,qr/someVariable2: 'value2'/,'someVariable2 substituted');
like($rendered,qr/table: 'table goes here'/,'table substituted');
