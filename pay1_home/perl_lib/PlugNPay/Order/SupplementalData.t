#!/bin/env perl
use strict;
use warnings;
use lib '/home/pay1/perl_lib';
use Test::More tests => 15;
use Test::Exception;
use Test::MockModule;
use JSON::XS;
use Data::Dumper;
use PlugNPay::Testing qw(skipIntegration);

require_ok('PlugNPay::Order::SupplementalData');

my $sdMock = Test::MockModule->new('PlugNPay::Order::SupplementalData');
$sdMock->mock(
  _getServerParameter => sub {
    return 'PARAMETER_STORE_VALUE';
  }
);

test_input();
test_formatHash();
test_formatArray();
test_getServer_Env();
test_getSupplementalData();
test_insertSupplementalData();

sub test_getSupplementalData {
  my $requestData;
  my $requestURL;
  $sdMock->mock(
    _processRequest => sub {
      my $ms = shift;
      $requestData = $ms->getContent();
      $requestURL = $ms->getURL();
    }
  );

  lives_ok(
    sub {
      my $sd     = new PlugNPay::Order::SupplementalData();
      my $result = $sd->getSupplementalData(
        { 'dates'        => [ '2023-03-23' ],
          'merchant_ids' => [ 1234 ]
        }
      );

      like($requestURL, qr/\/supplementalData\/load$/, 'getSupplementalData url ends in /supplementalData/load');
      if ( !ok( $requestData->{'query'}{'dates'}[0] eq '2023-03-23' && $requestData->{'query'}{'merchant_ids'}[0] eq '1234', 'getSupplementalData request formatted correctly' ) ) {
        print "request data: \n" . Dumper($requestData);
      }
    },
    'getSupplementalData did not die during expected successful test'
  );

  $sdMock->unmock('_processRequest');
}

sub test_insertSupplementalData {
  my $requestData;
  my $requestURL;
  $sdMock->mock(
    _processRequest => sub {
      my $ms = shift;
      $requestData = $ms->getContent();
      $requestURL = $ms->getURL();
    }
  );

  lives_ok(
    sub {
      my $sd     = new PlugNPay::Order::SupplementalData();
      my $result = $sd->insertSupplementalData(
        { items => [
            { merchant_id       => 1,
              order_id          => '123456789098765',
              transaction_date  => '2023:03:23T16:21:53Z',
              supplemental_data => {
                customData => {
                  this => 'that',
                  and  => 'the other thing',
                  somethingUndefined => undef
                }
              }
            }
          ]
        }
      );

      like($requestURL, qr/\/supplementalData$/, 'insertSupplementalData url ends in /supplementalData');

      my $isOk =
           $requestData->{'items'}[0]{'merchant_id'} eq '1'
        && $requestData->{'items'}[0]{'order_id'} eq '123456789098765'
        && $requestData->{'items'}[0]{'supplemental_data'}{'customData'}{'this'} eq 'that';

      if ( !ok( $isOk, 'insertSupplementalData request formatted correctly' ) ) {
        print "request data: \n" . Dumper($requestData);
      }
    },
    'insertSupplementalData did not die during expected successful test'
  );

  $sdMock->unmock('_processRequest');
}

sub test_getServer_Env {
  PlugNPay::Order::SupplementalData::noCache();
  my $value = "SUPDATA_ENV_VALUE";
  local $ENV{'PNP_SUPPLEMENTAL_DATA'} = $value;
  is( PlugNPay::Order::SupplementalData::getServer(), $value, 'getServer returns environment variable value' );
  $ENV{'PNP_SUPPLEMENTAL_DATA'} = '';
  is( PlugNPay::Order::SupplementalData::getServer(), 'PARAMETER_STORE_VALUE', 'getServer returns environment variable value' );
}

sub test_input {
  my $arrayRef = [];
  my $hashRef  = {};

  lives_ok(
    sub {
      PlugNPay::Order::SupplementalData::_input( 'arrayRef', $arrayRef, 'ARRAY' );
    },
    '_input does not die on proper input type for ARRAY'
  );
  lives_ok(
    sub {
      PlugNPay::Order::SupplementalData::_input( 'hashRef', $hashRef, 'HASH' );
    },
    '_input does not die on proper input type for HASH'
  );
}

sub test_formatHash {
  my $testHash = {
    subHash => {
      aNumber => 1234,
      aString => "hello"
    },
    subArray => [ 0, 1 ]
  };

  my $formatted = PlugNPay::Order::SupplementalData::_formatHash($testHash);
  my $json      = encode_json($formatted);

  like( $json, qr/"aNumber":"1234"/,       'numeric scalar encodes as a string' );
  like( $json, qr/"subArray":\["0","1"\]/, 'numeric scalars in array ref encode as strings' );
}

sub test_formatArray {
  my $testArray = [
    { aNumber => 1234,
      aString => "hello"
    },
    [ 0, 1 ]
  ];

  my $formatted = PlugNPay::Order::SupplementalData::_formatArray($testArray);
  my $json      = encode_json($formatted);

  like( $json, qr/"aNumber":"1234"/, 'numeric scalar encodes as a string' );
  like( $json, qr/\["0","1"\]/,      'numeric scalars in array ref encode as strings' );
}
