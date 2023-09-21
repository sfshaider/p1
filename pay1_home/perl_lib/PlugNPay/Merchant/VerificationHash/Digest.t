#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 24;
use Test::Exception;
use Test::MockModule;

use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::Merchant::VerificationHash::Digest');

test_checkInput();
test_checkSettings();
test_createDigestData();
test_digest();
test_checkDigests();
test_validate();
test_vs_old();

sub test_checkInput {
  my $checkInputInput = {
    type => 'inbound',
    settings => {
      fields => ['some_field','another_field','yet_another_field'],
      timeout => 1,
      secret => 'thisIsASecretDontTellAnyone'
    },
    sortFields => 1,
    startTime => new PlugNPay::Sys::Time(),
    endTime => new PlugNPay::Sys::Time()
  };

  my $inputStatus = PlugNPay::Merchant::VerificationHash::Digest::checkInput($checkInputInput);
  ok($inputStatus,'sane input returns passing status for checkInput');

  my %checkInputInputBadTimes = (%{$checkInputInput}, startTime => '20220811112233');
  $inputStatus = PlugNPay::Merchant::VerificationHash::Digest::checkInput(\%checkInputInputBadTimes);
  ok(!$inputStatus,'bad time causes checkInput to return failure status');

  my $expStart = new PlugNPay::Sys::Time();
  my $expEnd = new PlugNPay::Sys::Time();

  $expStart->subtractHours(1);
  $expEnd->subtractHours(1);

  my %checkInputExpired = (%{$checkInputInput}, startTime => $expStart, endTime => $expEnd);
  $inputStatus = PlugNPay::Merchant::VerificationHash::Digest::checkInput(\%checkInputInputBadTimes);
  ok(!$inputStatus,'expired time causes checkInput to return failure status');


  my %checkInputInputBadSetting = (%{$checkInputInput}, settings => {});
  $inputStatus = PlugNPay::Merchant::VerificationHash::Digest::checkInput(\%checkInputInputBadSetting);
  ok(!$inputStatus,'bad settings causes checkInput to return failure status');
}

sub test_checkSettings {
  my $checkInboundSettingsInput = {
    type => 'inbound',
    settings => {
      fields => ['some_field','another_field','yet_another_field'],
      timeout => 1,
      secret => 'thisIsASecretDontTellAnyone',
      sortFields => 1
    }
  };

  my $inboundStatus = PlugNPay::Merchant::VerificationHash::Digest::checkSettings($checkInboundSettingsInput);
  if (!ok($inboundStatus,'sane input for inbound results in settings returning successful')) {
    print "==> " . $inboundStatus->getError() . "\n";
  }

  # check for invalid timeout
  $checkInboundSettingsInput->{'settings'}{'timeout'} = 0;
  $inboundStatus = PlugNPay::Merchant::VerificationHash::Digest::checkSettings($checkInboundSettingsInput);
  ok(!$inboundStatus,'invalid timeout results in error');
  isnt($inboundStatus->getError(),'','invalid timeout status contains an error message');

  $checkInboundSettingsInput->{'settings'}{'timeout'} = 1;
  $checkInboundSettingsInput->{'settings'}{'secret'} = 'bad';
  $inboundStatus = PlugNPay::Merchant::VerificationHash::Digest::checkSettings($checkInboundSettingsInput);
  ok(!$inboundStatus,'invalid secret results in error');
  isnt($inboundStatus->getError(),'','invalid secret status contains an error message');

  $checkInboundSettingsInput->{'settings'}{'secret'} = 'long enough';
  $checkInboundSettingsInput->{'settings'}{'fields'} = [];
  $inboundStatus = PlugNPay::Merchant::VerificationHash::Digest::checkSettings($checkInboundSettingsInput);
  ok(!$inboundStatus,'zero fields defined results in error');
  isnt($inboundStatus->getError(),'','zero fields defined status contains an error message');

  my $checkOutboundSettingsInput = {
    type => 'outbound',
    settings => {
      fields => ['some_field','another_field','yet_another_field'],
      secret => 'thisIsASecretDontTellAnyone'
    }
  };

  # outbound does not have a timeout
  my $outboundStatus = PlugNPay::Merchant::VerificationHash::Digest::checkSettings($checkOutboundSettingsInput);
  if (!ok($outboundStatus,'sane input for outbound results in settings returning successful')) {
    print "==> " . $outboundStatus->getError() . "\n";
  }
}

sub test_createDigestData {
  my $createDigestDataInput = {
    sortFields => 1,
    fields => ['some_field','another_field','yet_another_field'],
    sourceData => {
      some_field => 'open ',
      another_field => 'abracadabra ',
      yet_another_field => 'sesame!'
    }
  };

  my $digestData = PlugNPay::Merchant::VerificationHash::Digest::createDigestData($createDigestDataInput);
  is($digestData,'abracadabra open sesame!','createDigestData creates concatenated fields in the correct order');
}

sub test_digest {
  my $digestDataInput = {
    secret => 'this is a secret',
    digestData => 'this is some data right here'
  };

  my $digestedData = PlugNPay::Merchant::VerificationHash::Digest::digest($digestDataInput);

  isnt($digestedData->{'md5Sum'},undef,'md5 sum calculated for digestData');
  isnt($digestedData->{'sha256Sum'},undef,'sha256 sum calculated for digestData');
}

sub test_checkDigests {
  my $checkDigestsInput = {
    digestedData => {
      md5Sum => 'anMd5Sum',
      sha256Sum => 'aSha256Sum',
    }
  };

  # test md5Sum with no digest type specified
  my %md5SumAny = (%{$checkDigestsInput}, digest => 'anMd5Sum');
  my $status = PlugNPay::Merchant::VerificationHash::Digest::checkDigests(\%md5SumAny);
  ok($status,'md5Sum with no type defined passes');

  my %sha256SumAny = (%{$checkDigestsInput}, digest => 'aSha256Sum');
  $status = PlugNPay::Merchant::VerificationHash::Digest::checkDigests(\%sha256SumAny);
  ok($status,'sha256Sum with no type defined passes');

  my %md5SumSpecific = (%{$checkDigestsInput}, digest => 'anMd5Sum', digestType => 'md5Sum');
  $status = PlugNPay::Merchant::VerificationHash::Digest::checkDigests(\%md5SumSpecific);
  ok($status,'md5Sum with md5 check passes');

  my %md5SumSha256 = (%{$checkDigestsInput}, digest => 'anMd5Sum', digestType => 'sha256Sum');
  $status = PlugNPay::Merchant::VerificationHash::Digest::checkDigests(\%md5SumSha256);
  ok(!$status,'md5Sum with sha256 check fails');

  my %sha256SumSpecific = (%{$checkDigestsInput}, digest => 'aSha256Sum', digestType => 'sha256Sum');
  $status = PlugNPay::Merchant::VerificationHash::Digest::checkDigests(\%sha256SumSpecific);
  ok($status,'sha256Sum with sha256 check passes');

  my %sha256SumSha256 = (%{$checkDigestsInput}, digest => 'aSha256Sum', digestType => 'md5Sum');
  $status = PlugNPay::Merchant::VerificationHash::Digest::checkDigests(\%sha256SumSha256);
  ok(!$status,'sha256Sum with md5 check fails');
}

sub test_validate {
  my $startTime = new PlugNPay::Sys::Time();
  $startTime->subtractMinutes(2);
  my $endTime = new PlugNPay::Sys::Time();
  $endTime->addMinutes(10);

  my $now = new PlugNPay::Sys::Time();

  my $validateHashInput = { 
    settings => {
      fields => ['field1','field2'],
      timeout => 300, # 300 seconds = 5 minutes
      secret => 'excelsior!',
      sortFields => 1
    },
    sourceData => {
      field1 => 'abcd',
      field2 => 'efgh'
    },
    type => 'inbound',
    startTime => $startTime,
    endTime => $endTime,
    hashTimeString => $now->inFormat('gendatetime')
  };

  my $digestData = PlugNPay::Merchant::VerificationHash::Digest::createDigestData({
    fields => $validateHashInput->{'settings'}{'fields'},
    sourceData => $validateHashInput->{'sourceData'}
  });

  my $digests = PlugNPay::Merchant::VerificationHash::Digest::digest({
    secret => $validateHashInput->{'settings'}{'secret'},
    hashTimeString => $validateHashInput->{'hashTimeString'},
    digestData => $digestData
  });

  $validateHashInput->{'digest'} = $digests->{'sha256Sum'};

  my $result = PlugNPay::Merchant::VerificationHash::Digest::validate($validateHashInput);
  ok($result,'full test validation succeeded');
}

sub test_vs_old {
  my $now = new PlugNPay::Sys::Time();

  # transacttime is the name of the query variable for legacy pay screens auth hash timestamp input
  my $transacttime = $now->inFormat('gendatetime');

  my $query = {
  'transacttime'   => $transacttime,
  'currency'       => 'usd',
  'card-amount'    => '123.45',
  'publisher-name' => 'jamestu2'
  };

  my $secretKey = 'uCIP7KlAH7mYg74bTMyJ0XbjE';

  # matches feature format above
  my $dataToHash = $secretKey . $query->{'transacttime'} . $query->{'card-amount'} . $query->{'publisher-name'};

  my $digestor = new PlugNPay::Util::Hash();
  $digestor->add($dataToHash);
  my $oldHashedDataResult = $digestor->MD5('0x');

  # put data hashed the old way into the query so we can validate it with the new code
  $query->{'authhash'} = $oldHashedDataResult;

  my $feature = {
    authhashkey => "10|$secretKey|card-amount|publisher-name"
  };

  # the following is ripped from mckutils, it will have to do until mckutils gets refactored so this is it's own function
  # with the exception of setting up the query and features on the two lines immediately following this comment
  %mckutils::query = %{$query};
  %mckutils::feature = %{$feature};

  #-- snip --#
  # clean up transaction time for use with PlugNPay::Sys::Time
  $mckutils::query{'transacttime'} =~ s/[^0-9]//g;
  $mckutils::query{'transacttime'} =
    substr( $mckutils::query{'transacttime'}, 0, 14 );

  # feature contains timeout, secret, and then fields (in that order), pipe separated
  my (@fieldsAndStuff) = split( '\|', $mckutils::feature{'authhashkey'} );
  my $timeout          = shift @fieldsAndStuff;
  my $secret           = shift @fieldsAndStuff;
  my @fields           = @fieldsAndStuff;

  # filter timeout to digits only
  $timeout =~ s/[^0-9]//g;

  # create time objects for startTime, endTime based on input
  my $startTime = new PlugNPay::Sys::Time();
  my $endTime = new PlugNPay::Sys::Time();

  # subject 1 minute from timeout to account for clock differences
  $startTime->subtractMinutes(1);

  # add timeout from feature setting to end time
  $endTime->addMinutes($timeout);

  my %sourceData = %mckutils::query;

  my $cardAmount  = $mckutils::query{'card-amount'} + 0;
  my $currencyObj = new PlugNPay::Currency( uc( $mckutils::query{'currency'} ) );
  $cardAmount = $currencyObj->format( $cardAmount, { digitSeparator => '' } );
  $sourceData{'card-amount'} = $cardAmount;

  # this supports MD5 and SHA256 for validation
  my $validateStatus = PlugNPay::Merchant::VerificationHash::Digest::validate(
    { type     => 'inbound',
      settings => {
        fields     => \@fields,
        sortFields => 1,
        secret     => $secret,
        timeout    => $timeout
      },
      sourceData => \%sourceData,
      startTime  => $startTime,
      endTime    => $endTime,
      digest     => $mckutils::query{'authhash'},
      hashTimeString => $mckutils::query{'transacttime'}
    }
  );
  #-- snip --#

  ok($validateStatus,'new code validates old hash method');
}