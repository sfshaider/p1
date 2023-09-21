#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 71;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

use PlugNPay::Testing qw(skipIntegration);

require_ok('mckutils');

# test fee logging functionality
testLogFeesIfApplicable();

# test transition page
testTransitionParameters();

# test filterTransitionOrGoToCgiFields subroutine
testFilterTransitionOrGoToCgiFields();

# test isSelfPost function
testIsSelfPost();

# test goBackToPayscreens function
testGoBackToPayscreens();

# test transitionOrGoToCgi function
testTransitionOrGoToCgi();

sub testLogFeesIfApplicable {
SKIP: {
    if ( !skipIntegration( 'integration testing disabled', 10 ) ) {
      my $logged;
      my $adjMock = Test::MockModule->new('PlugNPay::Transaction::Logging::Adjustment');
      $adjMock->redefine( 'log' => sub { $logged = 1; return; } );

      my $coaMock = Test::MockModule->new('PlugNPay::COA');
      $coaMock->redefine(
        'isSurcharge' => sub { return 0; },
        'isFee'       => sub { return 0; },
        'isOptional'  => sub { return 0; }
      );

      $logged = 0;
      &mckutils::logFeesIfApplicable(
        'mckutils',
        { publisher_name => 'pnpdemo',
          orderID        => '12345',
          baseAmount     => 3.50,
          surcharge      => 2.00
        },
        { 'Duplicate' => 'no' },
        'yes',
        'dylaninc',
        '123351035'
      );
      ok( $logged, 'Logging fee' );

      $logged = 0;
      &mckutils::logFeesIfApplicable( 'mckutils', {}, { 'Duplicate' => 'yes' }, 'yes', 'dylaninc', '123351035' );
      ok( !$logged, 'Fail logging, is duplicate' );

      $logged = 0;
      &mckutils::logFeesIfApplicable( 'mckutils', {}, { 'Duplicate' => 'no' }, undef, 'dylaninc', '123351035' );
      ok( !$logged, 'Fail logging, no adj log flag set' );

      # isStoreData tests
      my $isStoreData;
      $isStoreData = &mckutils::isStoreData( { 'allowStoreData' => 1, 'storeData' => 1 } );
      is( $isStoreData, 1, 'storedata is true for passed field' );

      $isStoreData = &mckutils::isStoreData( { 'paymentMethod' => 'invoice', 'allowInvoice' => 1 } );
      is( $isStoreData, 1, 'storedata is true for invoice' );

      $isStoreData = &mckutils::isStoreData( { 'allowFreePlans' => 1, 'plan' => '1', 'cardAmount' => 0, 'transFlags' => '' } );
      is( $isStoreData, 1, 'storedata is true for free membership plan' );

      $isStoreData = &mckutils::isStoreData( { 'paymentMethod' => 'goCart' } );
      is( $isStoreData, 1, 'storedata is true for goCart transaction' );

      $isStoreData = &mckutils::isStoreData();
      is( $isStoreData, 0, 'storedata is false for normal auth' );

      $isStoreData = &mckutils::isStoreData( { 'paymentMethod' => 'onlinecheck' } );
      is( $isStoreData, 0, 'storedata is false for check transaction' );

      my $ogFlag = $mckutils::convfeeflag;
      $mckutils::convfeeflag = 1;
      my $q = { 'resphash' => 'stuffandthangs' };
      my $response = mckutils::resp_hash( { hashkey => 'blah' }, $q, {} );
      isnt( $response->{'md5Sum'}, undef, 'md5Sum returned from resp_hash' );
      isnt( $response->{'sha256Sum'}, undef, 'sha256Sum returned from resp_hash');
    }
  }
}

sub testTransitionParameters {
  my $cardExp;
  my $mckMock = new Test::MockModule('mckutils');
  $mckMock->redefine(
    transition => sub {
      my (@pairs) = @_;
      foreach my $key (@pairs) {
        if ( $key =~ /card.exp/i ) {
          $cardExp = '12/25';
        }
      }
    }
  );

  mckutils::transitionOrGoToCgi(
    { 'transition' => 1,
      'query'      => { 'card-exp' => '12/25' },
      'result'     => {}
    }
  );

  is( $cardExp, '12/25', 'transitionOrGoToCgi card-exp returned' );
}

sub testFilterTransitionOrGoToCgiFields {

  # filter code as of writing this test
  # && ( $field !~ /^card.cvv/i )
  # && ( $field !~ /merch.txn/i )
  # && ( $field !~ /cust.txn/i )
  # && ( $field !~ /month.exp/i )
  # && ( $field !~ /year.exp/i )
  # && ( $field !~ /magstripe/i )
  # && ( $field !~ /mpgiftcard/i )
  # && ( $field !~ /mpcvv/i ) ) {
  my $fieldNameInput = [ 'card-cvv', 'merch-txn', 'cust-txn', 'month-exp', 'year-exp', 'magstripe', 'mpgiftcard', 'mpcvv', 'magensacc', 'badcard-link' ];

  # first test gatewayRedirect is falsy
  my $filteredFieldNames = mckutils::filterTransitionOrGoToCgiFields(
    { fieldNames      => $fieldNameInput,
      gatewayRedirect => 0
    }
  );

  my %existingFields = map { $_ => 1 } @{$filteredFieldNames};
  isnt( $existingFields{'badcard-link'}, 1, 'badcard-link filtered out of field names for falsy gatewayRedirect' );
  isnt( $existingFields{'card-cvv'},     1, 'card-cvv filtered out of field names for falsy gatewayRedirect' );
  isnt( $existingFields{'merch-txn'},    1, 'merch-txn filtered out of field names for falsy gatewayRedirect' );
  isnt( $existingFields{'cust-txn'},     1, 'cust-txn filtered out of field names for falsy gatewayRedirect' );
  isnt( $existingFields{'month-exp'},    1, 'month-exp filtered out of field names for falsy gatewayRedirect' );
  isnt( $existingFields{'year-exp'},     1, 'year-exp filtered out of field names for falsy gatewayRedirect' );
  isnt( $existingFields{'magstripe'},    1, 'magstripe filtered out of field names for falsy gatewayRedirect' );
  isnt( $existingFields{'mpgiftcard'},   1, 'mpgiftcard filtered out of field names for falsy gatewayRedirect' );
  isnt( $existingFields{'mpcvv'},        1, 'campcvv filtered out of field names for falsy gatewayRedirect' );
  isnt( $existingFields{'magensacc'},    1, 'magensacc filtered out of field names for falsy gatewayRedirect' );

  # then test gatewayRedirect is truthy
  $filteredFieldNames = mckutils::filterTransitionOrGoToCgiFields(
    { fieldNames      => $fieldNameInput,
      gatewayRedirect => 1
    }
  );

  %existingFields = map { $_ => 1 } @{$filteredFieldNames};
  is( $existingFields{'badcard-link'}, 1, 'badcard-link not filtered out of field names for truthy gatewayRedirect' );
  isnt( $existingFields{'card-cvv'},   1, 'card-cvv filtered out of field names for truthy gatewayRedirect' );
  isnt( $existingFields{'merch-txn'},  1, 'merch-txn filtered out of field names for truthy gatewayRedirect' );
  isnt( $existingFields{'cust-txn'},   1, 'cust-txn filtered out of field names for truthy gatewayRedirect' );
  isnt( $existingFields{'month-exp'},  1, 'month-exp filtered out of field names for truthy gatewayRedirect' );
  isnt( $existingFields{'year-exp'},   1, 'year-exp filtered out of field names for truthy gatewayRedirect' );
  isnt( $existingFields{'magstripe'},  1, 'magstripe filtered out of field names for truthy gatewayRedirect' );
  isnt( $existingFields{'mpgiftcard'}, 1, 'mpgiftcard filtered out of field names for truthy gatewayRedirect' );
  isnt( $existingFields{'mpcvv'},      1, 'mpcvv filtered out of field names for truthy gatewayRedirect' );
  isnt( $existingFields{'magensacc'},  1, 'magensacc filtered out of field names for truthy gatewayRedirect' );
}

sub testIsSelfPost {
  # if link is local, it will start with /, it will return truthy 
  # if it is an external link, check that is matches this:
  # (plugnpay|icommercegateway|penzpay|pay-gate|spheralink|noblept|paywithcardx)\.(com|net)

  my @eligiableExternalLinkList = (
    'www.plugnpay.com',
    'www.icommercegateway.com',
    'www.penzpay.com',
    'www.pay-gate.com',
    'www.spheralink.com',
    'www.noblept.com',
    'www.paywithcardx.com',
    'www.plugnpay.net',
    'www.icommercegateway.net',
    'www.penzpay.net',
    'www.pay-gate.net',
    'www.spheralink.net',
    'www.noblept.net',
    'www.paywithcardx.net',
    "/local.cgi",
    '/'
  );

  my @ineligibleLinkList = (
    'www.plugnpay.asd',
    'www.icommercegateway.edu',
    'www.penzpay.org',
    'www.pay-gate.kh',
    'www.spheralink.askljljd',
    'www.noblept.assdf77d',
    'www.paywithcardx.alsjdflksd',
    'www.google.com',
    'asdasd',
    '',
  );

  foreach my $link (@eligiableExternalLinkList) {
    my $response = mckutils::isSelfPost($link);
    is ($response, 1, "$link link returns truthy");
  }

  foreach my $ineligibleLink (@ineligibleLinkList) {
    my $ineligibleResponse = mckutils::isSelfPost($ineligibleLink);
    is ($ineligibleResponse, "", "$ineligibleLink link returns falsey");
  }
}

sub testGoBackToPayscreens {
  is (mckutils::goBackToPayscreens('/test.cgi'), 1, '/test.cgi, a local link returns truthy, signal to go back to payscreens');
  is (mckutils::goBackToPayscreens('https://www.test.com'), "", 'https://www.test.com hostlink does not match server name, so do not go back to payscreens');
}

sub testTransitionOrGoToCgi {
  my $functionCalled = '';

  my $mockMckUtils = Test::MockModule->new('mckutils');
  $mockMckUtils->mock(
    transition => sub {
      my (@pairs) = @_;
      $functionCalled = 'transition';
    },
    gotocgi => sub {
      $functionCalled = 'goToCgi';
    }
  );

  my $testInputDataTemplate = {
    'transition' => 0,
    'statusToCheck' => '',
    'query' => {
      'transitiontype' => '',
      'badcard-link' => 'https://localhost.plugnpay.com:8443/pay/', # self post
      'problem-link' => 'https://localhost.plugnpay.com:8443/pay/', # self post
    },
    'selfHiddenPost' => 0,
    'successValue' => 'no',
    'result' => {}
  };

  my $statusToCheckValues = ['badcard', 'problem'];
  my $transitiontypeValues = ['hidden', 'get', 'post', undef, ''];

  foreach (@$statusToCheckValues) {
    my $copyTestData = { %$testInputDataTemplate };
    my $statusToCheck = $_;
    $copyTestData->{'statusToCheck'} = $statusToCheck;

    foreach (@$transitiontypeValues) {
      my $transitiontype = $_;
      $copyTestData->{'query'}{'transitiontype'} = $transitiontype;
      $functionCalled = '';

      mckutils::transitionOrGoToCgi($copyTestData);
      $transitiontype = "undefined or ''" if (!defined $transitiontype || $transitiontype eq ''); # need to do this because can't concat undef value to string
      # make sure transition sub is called when a badcard/problem response redirects back to /pay
      is( $functionCalled, 'transition', "transition sub is called when transitiontype is $transitiontype with $statusToCheck-link which posts back to /pay" );
    }
  }

  $mockMckUtils->unmock('transition', 'gotocgi');
}