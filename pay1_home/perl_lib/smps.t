#!/bin/env perl

# The Road goes ever on and on
# Down from the door where it began.
# Now far ahead the Road has gone,
# And I must follow, if I can,
# Pursuing it with eager feet,
# Until it joins some larger way
# Where many paths and errands meet.
# And whither then? I cannot say
#
# - J.R.R. Tolkien, The Fellowship of the Ring

use strict;
use warnings;

use Test::More tests => 53;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

# set up mocking for tests
my $mock = Test::MockObject->new();

# Mock PlugNPay::Processor::Account subs
my $procAccountMock = Test::MockModule->new('PlugNPay::Processor::Account');


require_ok('smps');

# amountFromDatabaseAmountString()
is(smps::amountFromDatabaseAmountString("usd 1.50"), '1.50', 'amountFromDatabaseAmountString expected input format');
is(smps::amountFromDatabaseAmountString("1.50"), '1.50', 'amountFromDatabaseAmountString only amount passed, no currency');
is(smps::amountFromDatabaseAmountString("usd     1.50"), '1.50', 'amountFromDatabaseAmountString expected input format but with extra spaces');
throws_ok( sub {smps::amountFromDatabaseAmountString('usd 1.5.25')}, qr/^Invalid amount,/, 'amountFromDatabaseAmountString extra periods in input format');
throws_ok( sub {smps::amountFromDatabaseAmountString('usd')}, qr/^Invalid amount string/, 'amountFromDatabaseAmountString only currency passed, no amount');



# currencyFromDatabaseAmountString()
is(smps::currencyFromDatabaseAmountString('usd 1.50'), 'usd', 'currencyFromDatabaseAmountString expected input format');
is(smps::currencyFromDatabaseAmountString('usd 1.50'), 'usd', 'currencyFromDatabaseAmountString extra spaces in input format');
is(smps::currencyFromDatabaseAmountString('usd'), 'usd', 'currencyFromDatabaseAmountString only currency passed, no amount');
throws_ok( sub {smps::currencyFromDatabaseAmountString('1.50')}, qr/^Invalid currency string/, 'currencyFromDatabaseAmountString only amount passed, no currency');



# calculateRetrunAdjustmentAmount()
# contrived example:
is(smps::calculateReturnAdjustmentAmount({
  returnTotalAmount => 103.50,
  authorizationBaseAmount => 100.00,
  authorizationAdjustmentAmount => 3.50
}), '3.5', 'calculateReturnAdjustmentAmount expected base amount result (contrived full return)');

# real world example:
is(smps::calculateReturnAdjustmentAmount({
  returnTotalAmount => 2624.97,
  authorizationBaseAmount => 2536.25,
  authorizationAdjustmentAmount => 88.72
}), '88.72', 'calculateReturnAdjustmentAmount expected base amount result (real world full return)');

# TODO add partial return examples

throws_ok( sub {smps::calculateReturnAdjustmentAmount({
  authorizationBaseAmount => 100.00,
  authorizationAdjustmentAmount => 3.50
})}, qr/^returnTotalAmount not defined/, 'calculateReturnAdjustmentAmount without returnBaseAmount');

throws_ok( sub {smps::calculateReturnAdjustmentAmount({
  returnTotalAmount => 100.00,
  authorizationAdjustmentAmount => 3.50
})}, qr/^authorizationBaseAmount not defined/, 'calculateReturnAdjustmentAmount without authorizationTotalAmount');

throws_ok( sub {smps::calculateReturnAdjustmentAmount({
  returnTotalAmount => 100.00,
  authorizationBaseAmount => 100.00
})}, qr/^authorizationAdjustmentAmount not defined/, 'calculateReturnAdjustmentAmount without originalAdjustment');



# calculateDisplayedBaseAmountAndAdjustment()
# TODO add tests for partial returns
# make sure PlugNPay::Transaction::Logging::Adjustment is loaded.
require_ok('PlugNPay::Transaction::Logging::Adjustment');

my ($baseAmount, $adjustmentAmount);

# call calculateDisplayedBaseAmountAndAdjustment for an auth
eval {
  my $adjustmentInfo = new PlugNPay::Transaction::Logging::Adjustment();
  $adjustmentInfo->setBaseAmount(100.00);
  $adjustmentInfo->setAdjustmentAmount(3.50);
  ($baseAmount, $adjustmentAmount) = smps::calculateDisplayedBaseAmountAndAdjustment({
    amount => 100.00,
    adjustmentInfo => $adjustmentInfo,
    transactionType => 'auth'
  });
};
is($@, '', 'calculateDisplayedBaseAmountAndAdjustment() returns without error on expected input for an auth calculation');
is($baseAmount,'100.00', 'calculateDisplayedBaseAmountAndAdjustment() base amount result for an auth calculation');
is($adjustmentAmount,'3.50','calculateDisplayedBaseAmountAndAdjustment() adjustment amount result for an auth calculation');

# call calculateDisplayedBaseAmountAndAdjustment for an auth with no adjustment log
eval {
  my $adjustmentInfo = undef;
  ($baseAmount, $adjustmentAmount) = smps::calculateDisplayedBaseAmountAndAdjustment({
    amount => 100.00,
    adjustmentInfo => $adjustmentInfo,
    transactionType => 'auth'
  });
};
is($@, '', 'calculateDisplayedBaseAmountAndAdjustment() returns without error on expected input for an auth calculation with no adjustment log data');
is($baseAmount,'100.00', 'calculateDisplayedBaseAmountAndAdjustment() base amount result for an auth calculation with no adjustment log data');
is($adjustmentAmount,'0.00','calculateDisplayedBaseAmountAndAdjustment() adjustment amount result for an auth calculation with no adjustment log data');

# call calculateDisplayedBaseAmountAndAdjustment for a return and get results;
eval {
  my $adjustmentInfo = new PlugNPay::Transaction::Logging::Adjustment();
  $adjustmentInfo->setBaseAmount(100.00);
  $adjustmentInfo->setAdjustmentAmount(3.50);
  ($baseAmount, $adjustmentAmount) = smps::calculateDisplayedBaseAmountAndAdjustment({
    amount => 103.50,
    adjustmentInfo => $adjustmentInfo,
    transactionType => 'return'
  });
};
is($@, '', 'calculateDisplayedBaseAmountAndAdjustment() returns without error on expected input for a return calculation');
is($baseAmount,'100.00', 'calculateDisplayedBaseAmountAndAdjustment() base amount result for a return calculation');
is($adjustmentAmount,'3.50','calculateDisplayedBaseAmountAndAdjustment() adjustment amount result for a return calculation');

# call calculateDisplayedBaseAmountAndAdjustmentForOperation
my $calculatedData = {};
eval {
  my $adjustmentInfo = new PlugNPay::Transaction::Logging::Adjustment();
  $adjustmentInfo->setBaseAmount(100.00);
  $adjustmentInfo->setAdjustmentAmount(3.50);
  $calculatedData = smps::calculateDisplayedBaseAmountAndAdjustmentForOperation({
    operation => 'auth',
    amount => 103.50,
    adjustmentInfo => $adjustmentInfo,
    transactionType => 'return'
  });
};

is($@, '', 'calculateDisplayedBaseAmountAndAdjustmentForOperation() returns without error on expected input for a auth calculation');
isnt($calculatedData->{'baseAmount'},'0.00', 'calculateDisplayedBaseAmountAndAdjustmentForOperation() base amount result for an auth calculation');
isnt($calculatedData->{'adjustment'},'0.00','calculateDisplayedBaseAmountAndAdjustmentForOperation() adjustment amount result for an auth calculation');

eval {
  my $adjustmentInfo = new PlugNPay::Transaction::Logging::Adjustment();
  $adjustmentInfo->setBaseAmount(100.00);
  $adjustmentInfo->setAdjustmentAmount(3.50);
  $calculatedData = smps::calculateDisplayedBaseAmountAndAdjustmentForOperation({
    operation => 'void',
    amount => 103.50,
    adjustmentInfo => $adjustmentInfo,
    transactionType => 'return'
  });
};

is($@, '', 'calculateDisplayedBaseAmountAndAdjustmentForOperation() returns without error on expected input for a void calculation');
is($calculatedData->{'baseAmount'},'0.00', 'calculateDisplayedBaseAmountAndAdjustmentForOperation() base amount result for an void calculation');
is($calculatedData->{'adjustment'},'0.00','calculateDisplayedBaseAmountAndAdjustmentForOperation() adjustment amount result for an void calculation');

eval {
  my $adjustmentInfo = new PlugNPay::Transaction::Logging::Adjustment();
  $adjustmentInfo->setBaseAmount(100.00);
  $adjustmentInfo->setAdjustmentAmount(3.50);
  $calculatedData = smps::calculateDisplayedBaseAmountAndAdjustmentForOperation({
    operation => 'inquiry',
    amount => 103.50,
    adjustmentInfo => $adjustmentInfo,
    transactionType => 'return'
  });
};

is($@, '', 'calculateDisplayedBaseAmountAndAdjustmentForOperation() returns without error on expected input for a inquiry calculation');
is($calculatedData->{'baseAmount'},'0.00', 'calculateDisplayedBaseAmountAndAdjustmentForOperation() base amount result for an inquiry calculation');
is($calculatedData->{'adjustment'},'0.00','calculateDisplayedBaseAmountAndAdjustmentForOperation() adjustment amount result for an inquiry calculation');

eval {
  my $adjustmentInfo = new PlugNPay::Transaction::Logging::Adjustment();
  $adjustmentInfo->setBaseAmount(100.00);
  $adjustmentInfo->setAdjustmentAmount(3.50);
  $calculatedData = smps::calculateDisplayedBaseAmountAndAdjustmentForOperation({
    operation => 'settle',
    amount => 103.50,
    adjustmentInfo => $adjustmentInfo,
    transactionType => 'return'
  });
};

is($@, '', 'calculateDisplayedBaseAmountAndAdjustmentForOperation() returns without error on expected input for a settle calculation');
is($calculatedData->{'baseAmount'},'0.00', 'calculateDisplayedBaseAmountAndAdjustmentForOperation() base amount result for a settle calculation');
is($calculatedData->{'adjustment'},'0.00','calculateDisplayedBaseAmountAndAdjustmentForOperation() adjustment amount result for a settle calculation');



# call checkTransCountsAsSettled
my $isACHSettled = 1;
my $isCardSettled = 1;

eval {
  my $checkArguments = {
    'transType' => 'auth',
    'status' => 'success',
    'industryCode' => '',
    'accountType' => 'checking',
    'transFlags' => 'authpostauth',
    'authType' => 'authpostauth',
    'achProcessor' => '',
    'cardProcessor' => ''
  };

  my @checkProcessors = ('alliance','alliancesp','globaletel','securenetach','tpayments');
  foreach my $chkprocessor (@checkProcessors) {
    $checkArguments->{'achProcessor'} = $chkprocessor;
    $isACHSettled &&= &smps::checkTransCountsAsSettled($checkArguments);
  }

  $checkArguments->{'transFlags'} = 'capture';
  $checkArguments->{'accountType'} = 'credit';
  $checkArguments->{'authType'} = 'authpostauth';
  $checkArguments->{'achProcessor'} = '';
  my @cardProcessors = ('globalc','pago','newtek','wirecard','payvision');
  foreach my $processor (@cardProcessors) {
    $checkArguments->{'cardProcessor'} = $processor;
    $isCardSettled &&= &smps::checkTransCountsAsSettled($checkArguments);
  }
};
isnt($@, undef, 'checkTransCountsAsSettled() returns without error on expected transaction detail input');
is($isACHSettled, 1, 'checkTransCountsAsSettled() returns true if transaction counts as a settled ACH transaction');
is($isCardSettled, 1, 'checkTransCountsAsSettled() returns true if transaction counts as a settled card transaction');
is(&smps::checkTransCountsAsSettled({
    'transType' => 'auth',
    'status' => 'success',
    'industryCode' => '',
    'accountType' => 'credit',
    'transFlags' => 'authcapture',
    'authType' => 'authcapture',
    'achProcessor' => '',
    'cardProcessor' => ''
  }),1, 'checkTransCountsAsSettled() returns true if authType is set to "authcapture" and account type is not "checking"');

isnt(&smps::checkTransCountsAsSettled({
    'transType' => 'auth',
    'status' => 'success',
    'industryCode' => '',
    'accountType' => 'savings',
    'transFlags' => 'authonly',
    'authType' => 'authpostauth',
    'achProcessor' => '',
    'cardProcessor' => ''
  }), 1, 'checkTransCountsAsSettled() returns false if transaction does not meet "settled" criteria');

isnt(&smps::checkTransCountsAsSettled({
    'transType' => 'auth',
    'status' => 'success',
    'industryCode' => '',
    'accountType' => 'savings',
    'transFlags' => 'authonly',
    'authType' => 'authpostauth',
    'achProcessor' => 'tpayments',
    'cardProcessor' => ''
  }), 1, 'checkTransCountsAsSettled() returns false if ACH transaction is authonly or account code is not checking or incorrect processor');

isnt(&smps::checkTransCountsAsSettled({
    'transType' => 'auth',
    'status' => 'success',
    'industryCode' => '',
    'accountType' => 'credit',
    'transFlags' => 'authpostauth',
    'authType' => 'authpostauth',
    'achProcessor' => '',
    'cardProcessor' => 'wirecard'
  }), 1, 'checkTransCountsAsSettled() returns false if card transaction does not have capture flag or is incorrect processor');

isnt(&smps::checkTransCountsAsSettled({
    'transType' => 'auth',
    'status' => 'success',
    'industryCode' => 'petroleum',
    'accountType' => 'checking',
    'transFlags' => 'authpostauth',
    'authType' => 'authpostauth',
    'achProcessor' => '',
    'cardProcessor' => ''
  }), 1, 'checkTransCountsAsSettled() returns false if industry code is set to "petroleum"');

isnt(&smps::checkTransCountsAsSettled({
    'transType' => 'auth',
    'status' => 'problem',
    'industryCode' => '',
    'accountType' => 'checking',
    'transFlags' => 'authpostauth',
    'authType' => 'authpostauth',
    'achProcessor' => '',
    'cardProcessor' => ''
  }), 1, 'checkTransCountsAsSettled() returns false if transaction was not an auth');

isnt(&smps::checkTransCountsAsSettled({
    'transType' => 'return',
    'status' => 'success',
    'industryCode' => '',
    'accountType' => 'checking',
    'transFlags' => 'authpostauth',
    'authType' => 'authpostauth',
    'achProcessor' => '',
    'cardProcessor' => ''
  }), 1, 'checkTransCountsAsSettled() returns false if transaction is not an authorization');


# getAchStatus()

# mocking PlugNPay::Processor::Account;
# settings object to return values from for PlugNPay::Processor::Account mock
my $procAccountSettings = {};

$procAccountMock->redefine(
'new' => sub { # to prevent loading from database on new
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
},
'getSettingValue' => sub {
  my $self = shift;
  my $setting = shift;
  return $procAccountSettings->{$setting};
},
'hasSetting' => sub {
  my $self = shift;
  my $setting = shift;
  return defined $procAccountSettings->{$setting};
}
);

throws_ok( sub {
  my $achstatus = smps::getAchStatus({});
}, qr/gatewayAccount is required/, 'error thrown on call to getAchStatus when gatewayAccount is not passed');

my $achStatus;
eval {
  $achStatus = smps::getAchStatus({
    gatewayAccount => 'pnpdemo',
    achProcessor => undef
  });
};
is($achStatus,'disabled', 'disabled returned when ach processor is not defined');

eval {
  $achStatus = smps::getAchStatus({
    gatewayAccount => 'pnpdemo',
    achProcessor => ''
  });
};
is($achStatus,'disabled', 'disabled returned when ach processor is not empty string');

eval {
  $achStatus = smps::getAchStatus({
    gatewayAccount => 'pnpdemo',
    achProcessor => 'testprocessor'
  });
};
is($achStatus,'enabled', 'enabled returned when ach processor is testprocessor');

$procAccountSettings->{'status'} = 'enabled';
eval {
  $achStatus = smps::getAchStatus({
    gatewayAccount => 'pnpdemo',
    achProcessor => 'fakeprocessor'
  });
};
is($achStatus,'enabled', 'enabled returned when ach processor is defined and status is enabled');

$procAccountSettings->{'status'} = 'disabled';
eval {
  $achStatus = smps::getAchStatus({
    gatewayAccount => 'pnpdemo',
    achProcessor => 'fakeprocessor'
  });
};
is($achStatus,'disabled', 'enabled returned when ach processor is defined and status is disabled');
