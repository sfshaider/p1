#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 72;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);

require_ok('PlugNPay::Legacy::MckUtils::Transition');

my $transitionMock = Test::MockModule->new('PlugNPay::Legacy::MckUtils::Transition');

# test forceLegacyFeatureIsSet function
testForceLegacyFeatureIsSet();

# test isPayscreensVersion2 function
testIsPayscreensVersion2();

# test transitionPage function
testTransitionPage();

SKIP: {
  skipIntegration("skipping integration tests for template loading",12);
  # getTransitionPage()

  if (INTEGRATION) {
    # clear feature value for template loadeding.
    my $features = new PlugNPay::Features('pnpdemo','general');
    $features->set('authcgiTransitionTemplate','');
    $features->set('transitiontype','post');
    $features->saveContext();

    # create default template
    my $wdf = new PlugNPay::WebDataFile();

    my %baseWDFRequest = (
      storageKey => 'merchantAdminTemplates'
    );

    my $deftran = {
      %baseWDFRequest,
      fileName => 'pnpdemo_deftran.html',
      subPrefix => 'transition/',
      content => 'pnpdemo deftran'
    };

    my $requested = {
      %baseWDFRequest,
      fileName => 'pnpdemo_requested.html',
      subPrefix => 'transition/',
      content => 'pnpdemo requested'
    };

    my $cobrand = {
      %baseWDFRequest,
      fileName => 'demopnp.html',
      content => 'demopnp cobrand',
      subPrefix => 'transition/cobrand/'
    };

    my $reseller = {
      %baseWDFRequest,
      fileName => 'devresell.html',
      content => 'devresell reseller',
      subPrefix => 'transition/reseller/'
    };

    # check defalt template
    $wdf->deleteFile($deftran);
    $wdf->writeFile($deftran);
    my $content = PlugNPay::Legacy::MckUtils::Transition::getTransitionPage('pnpdemo');
    is($content,'pnpdemo deftran','pnpdemo deftran template loaded');
    $content = PlugNPay::Legacy::MckUtils::Transition::getTransitionPage('pnpdemo');
    is($content,'pnpdemo deftran','pnpdemo deftran template loaded again (now in s3)');
    $wdf->deleteFile($deftran);

    # check requested template
    $wdf->deleteFile($requested);
    $wdf->writeFile($requested);
    $content = PlugNPay::Legacy::MckUtils::Transition::getTransitionPage('pnpdemo','requested');
    is($content,'pnpdemo requested','pnpdemo requested template loaded');
    $content = PlugNPay::Legacy::MckUtils::Transition::getTransitionPage('pnpdemo','requested');
    is($content,'pnpdemo requested','pnpdemo requested template loaded again (now in s3)');
    $wdf->deleteFile($requested);

    # clear stored template name, set cobrand feature, check cobrand template
    $wdf->deleteFile($cobrand);
    $wdf->writeFile($cobrand);
    $features->set('authcgiTransitionTemplate','');
    $features->set('cobrand','demopnp');
    $features->saveContext();
    $content = PlugNPay::Legacy::MckUtils::Transition::getTransitionPage('pnpdemo');
    is($content,'demopnp cobrand','demopnp cobrand template loaded');
    $content = PlugNPay::Legacy::MckUtils::Transition::getTransitionPage('pnpdemo');
    is($content,'demopnp cobrand','demopnp cobrand template loaded again (now in s3)');
    $wdf->deleteFile($cobrand);

    # clear stored template name, clear cobrand feature, check reseller template
    $wdf->deleteFile($reseller);
    $wdf->writeFile($reseller);
    $features->set('authcgiTransitionTemplate','');
    $features->set('cobrand','');
    $features->saveContext();
    $content = PlugNPay::Legacy::MckUtils::Transition::getTransitionPage('pnpdemo');
    is($content,'devresell reseller','devresell reseller template loaded');
    $content = PlugNPay::Legacy::MckUtils::Transition::getTransitionPage('pnpdemo');
    is($content,'devresell reseller','devresell reseller template loaded again (now in s3)');
    $wdf->deleteFile($reseller);

    # clear stored template name, check feature transitiontype=post
    $content = PlugNPay::Legacy::MckUtils::Transition::transitionPage({
      merchant => 'pnpdemo', 
      FinalStatus => 'success', 
      'success-link' => 'http://www.example.com'
    },{
      merchant => 'pnpdemo', 
      FinalStatus => 'success', 
      'success-link' => 'http://www.example.com'
    });
    like($content,qr/default post template/,'default post template loaded from feature');
    $features->removeFeature('transitiontype');
    $features->saveContext();
    $content = PlugNPay::Legacy::MckUtils::Transition::transitionPage({
      merchant => 'pnpdemo', 
      FinalStatus => 'success', 
      'success-link' => 'http://www.example.com'
    },{
      merchant => 'pnpdemo', 
      FinalStatus => 'success', 
      'success-link' => 'http://www.example.com'
    });
    like($content,qr/default redirect template/,'default redirect template loaded when transitiontype=post feature removed');
    $content = PlugNPay::Legacy::MckUtils::Transition::transitionPage({
      merchant => 'pnpdemo', 
      FinalStatus => 'success', 
      'success-link' => 'http://www.example.com'
    },{
      merchant => 'pnpdemo',
      FinalStatus => 'success', 
      'success-link' => 'http://www.example.com',
      transitiontype => 'post'
    });
    like($content,qr/default post template/,'default post template loaded from submitted data');

  
    # check that /pay paramters get converted back and that a requested template is still picked up when converted
    # mocked subroutine runs the test
    $transitionMock->mock(
      getTransitionPage => sub {
        my (undef,$transitionPage) = @_;
        is($transitionPage,'itworked','transition template successfully passed into getTransitionPage after /pay key name conversion');
      }
    );

    # we are not actually testing the response here because we mocked getTransitionPage
    PlugNPay::Legacy::MckUtils::Transition::transitionPage({
      merchant => 'pnpdemo',
      FinalStatus => 'success', 
      'success-link' => 'http://www.example.com',
      customname99999999 => 'payscreensVersion',
      customvalue99999999 => '2',
      transitionpage => 'itworked'
    },{
      merchant => 'pnpdemo',
      FinalStatus => 'success', 
      'success-link' => 'http://www.example.com',
      transitiontype => 'post'
    });

    $transitionMock->unmock('getTransitionPage');
  }
}

# generateRedirectQueryString()
my $data = {
  cow => "moo",
  chicken => "cluck",
  duck => "quack",
  sheep => "bahhh"
};
is(PlugNPay::Legacy::MckUtils::Transition::generateRedirectQueryString($data),"chicken=cluck&cow=moo&sheep=bahhh&duck=quack","query string generates correctly");


# generateRedirectHiddenFields()
$data = {
  escapism => '"><script>alert("oh noes")</script>',
  plainolddata => "yay"
};
like(PlugNPay::Legacy::MckUtils::Transition::generateRedirectHiddenFields($data),qr|<input type="hidden" name="plainolddata" value="yay">|,"generateRedirectHiddenFields() generates correctly");
unlike(PlugNPay::Legacy::MckUtils::Transition::generateRedirectHiddenFields($data),qr|<script>alert\("oh noes"\)</script>|,"generateRedirectHiddenFields() encodes entities correctly");


# filterRedirectFields()
$data = {
  card_number => '4111111111111111',
  'card-cvv' => '123',
  success_link => 'http://microservices.io',
  merch_txn => 'and then...',
  cust_txn => 'no and then',
  magstripe => 'yawn',
  month_exp => '09',
  year_exp => '2021',
  mpgiftcard => 'bankagenzia',
  mpcvv => 'that last one was suggested by atom...its somewhere in the source code...',
  magensacc => 'super secret data',
  goodfield => 'i will survive!',
  'badcard-link' => 'so will i!'
};
my $filteredData = PlugNPay::Legacy::MckUtils::Transition::filterRedirectFields($data);
is($filteredData->{'card_number'},undef,'filterRedirectFields() - card[-_]number is filtered out, example of underscore');
is($filteredData->{'card-cvv'},undef,'filterRedirectFields() - card[-_]cvv is filtered out, example of hyphen');
isnt($filteredData->{'success_link'},undef,'filterRedirectFields() - links are *not* filtered out');
is($filteredData->{'merch_txn'},undef,'filterRedirectFields() - merch[-_]txn is filtered out');
is($filteredData->{'cust_txn'},undef,'filterRedirectFields() - cust[-_]txn is filtered out');
is($filteredData->{'magstripe'},undef,'filterRedirectFields() - magstripe is filtred out');
is($filteredData->{'month_exp'},undef,'filterRedirectFields() - month_exp is filtered out');
is($filteredData->{'year_exp'},undef,'filterRedirectFields() - year_exp is filtered out');
is($filteredData->{'mpgiftcard'},undef,'filterRedirectFields() - mpgiftcard is filtered out');
is($filteredData->{'mpcvv'},undef,'filterRedirectFields() - mpcvv is filtered out');
is($filteredData->{'magensacc'},undef,'filterRedirectFields() - magensacc is filtered out');
isnt($filteredData->{'goodfield'},undef,'filterRedirectFields() - goodfield is *not* filtered out');


# postRedirect()
my $input = {
  bananas => "this is",
  FinalStatus => 'success'
};

my $url = 'http://www.example.com';
my $html = PlugNPay::Legacy::MckUtils::Transition::postRedirect($url,$input);
like($html,qr/<input type="hidden" name="bananas" value="this is">/,'postRedirect() - hidden field generated correctly');
like($html,qr/<form name="redirect" action="http:\/\/www.example.com" method="POST">/,'postRedirect() - form posts to url');

# defaultRedirect()
$html = PlugNPay::Legacy::MckUtils::Transition::defaultRedirect($url,$input);
like($html,qr/www.example.com\?FinalStatus=success&bananas=this\+is/,'postRedirect() - query string generated correctly');
like($html,qr/<META http-equiv="refresh" content="5; URL=http:\/\/www.example.com/,'postRedirect() - form posts to url');

# customRedirect()
my $template = <<EOF;
url: <a href="[pnp_STRTURL]">link[pnp_ENDURL]
title: [pnp_title]
quantity: [pnp_quantity], description: [pnp_description]
cost: [pnp_cost], weight: [pnp_weight]
querystring: [pnp_QUERYSTR]
EOF

$input = {
  title => "shopping list",
  quantity => "2",
  description => "zucchini",
  weight => ".4"
};

$html = PlugNPay::Legacy::MckUtils::Transition::customRedirect($url,$template,$input);
like($html,qr/url: <a href="http:\/\/www.example.com">link<\/a>/,'customRedirect() - url replacement successful');
like($html,qr/title: shopping list/,'customRedirect() - variable replacement successful');
like($html,qr/quantity: 2, description: zucchini/,'customRedirect() - multiple variable replacement successful');
like($html,qr/cost: , weight: .4/,'customRedirect() - multiple variable, first missing, replacement successful');
like($html,qr/querystring: \?weight=\.4\&quantity=2\&title=shopping\+list\&description=zucchini/, 'customRedirect() - query string replacement successful');



sub testForceLegacyFeatureIsSet {
  my $features = new PlugNPay::Features();

  my $notSet = PlugNPay::Legacy::MckUtils::Transition::forceLegacyFeatureIsSet($features);
  ok(!$notSet, 'forceLegacyFeatureIsSet returns false when feature is not set');

  $features->set('forceLegacy',1);
  my $set = PlugNPay::Legacy::MckUtils::Transition::forceLegacyFeatureIsSet($features);
  ok($set, 'forceLegacyFeatureIsSet returns true when feature is set set');
}

sub testIsPayscreensVersion2 {
  my %fields;

  my $isNotV2 = PlugNPay::Legacy::MckUtils::Transition::isPayscreensVersion2(\%fields);
  ok(!$isNotV2, 'isPayscreensVersion2 returns false when payscreensVersion custom name/value is not set to');

  $fields{'customname99999999'} = 'payscreensVersion';
  $fields{'customvalue99999999'} = '1';

  $isNotV2 = PlugNPay::Legacy::MckUtils::Transition::isPayscreensVersion2(\%fields);
  ok(!$isNotV2, 'isPayscreensVersion2 returns false when payscreensVersion custom name/value is set to a value other than 2');

  $fields{'customvalue99999999'} = '2';
  my $isV2 = PlugNPay::Legacy::MckUtils::Transition::isPayscreensVersion2(\%fields);
  ok($isV2, 'isPayscreensVersion2 returns true when payscreensVersion custom name/value is set to 2');
}

# make sure postRedirect is called when it hidden and that type = post
sub testTransitionPage {
  my $functionCalled = '';
  my $transitionType = '';

  my $transitionMock2 = Test::MockModule->new('PlugNPay::Legacy::MckUtils::Transition');
  $transitionMock2->mock(
    postRedirect => sub {
      my $url = shift;
      my $transitionFields = shift;

      $functionCalled = 'postRedirect';
      $transitionType = $transitionFields->{'transitiontype'};
    }
  );

  my $testFieldDataHidden = {
    'merchant' => 'test',
    'transitiontype' => 'hidden', 
  }; 

  my $testFieldDataPost = {
    'merchant' => 'test',
    'transitiontype' => 'post',
  };

  my $testFieldDataGet = {
    'merchant' => 'test',
    'transitiontype' => 'get',
  };

  my $testHiddenInputData = {
    'transitiontype' => 'hidden',
    'FinalStatus' => 'problem',
    'badcard-link' => 'https://localhost.plugnpay.com:8443/pay/',
    'problem-link' => 'https://localhost.plugnpay.com:8443/pay/',
    'success-link' => 'https://localhost.plugnpay.com:8443/pay/',
  };

  my $testPostInputData = {
    'transitiontype' => 'post',
    'FinalStatus' => 'problem',
    'badcard-link' => 'https://localhost.plugnpay.com:8443/pay/',
    'problem-link' => 'https://localhost.plugnpay.com:8443/pay/',
    'success-link' => 'https://localhost.plugnpay.com:8443/pay/',
  };

  my $testGetInputData = {
    'transitiontype' => 'get',
    'FinalStatus' => 'problem',
    'badcard-link' => 'https://localhost.plugnpay.com:8443/pay/',
    'problem-link' => 'https://localhost.plugnpay.com:8443/pay/',
    'success-link' => 'https://localhost.plugnpay.com:8443/pay/',
  };

  my $fieldDataMap = {
    'post' => $testFieldDataPost,
    'get' => $testFieldDataGet,
    'hidden' => $testFieldDataHidden
  };

  my $inputDataMap = {
    'post' => $testPostInputData,
    'get' => $testGetInputData,
    'hidden' => $testHiddenInputData
  };

  my @finalStatusList = ('problem', 'success', 'badcard');
  my $alwaysUsePost = 1;

  foreach(@finalStatusList) {
    foreach my $key (keys %$fieldDataMap) {
      my $fieldDataMapCopy = { %$fieldDataMap };
      my $inputDataMapCopy = { %$inputDataMap };

      # reset 
      $functionCalled = '';
      $transitionType = '';
      # set finalStatus to current value in the finalStatusList
      $fieldDataMapCopy->{'FinalStatus'} = $_;
      $inputDataMapCopy->{'FinalStatus'} = $_;

      PlugNPay::Legacy::MckUtils::Transition::transitionPage($fieldDataMapCopy->{$key}, $inputDataMapCopy->{$key}, $alwaysUsePost);
      # make sure postRedirect is called when alwaysUsePost = 1
      is( $functionCalled, 'postRedirect', "postDirect sub was called when transitionType is $key for $_ response");
      #make sure that original transitionType value is preserved when redirecting back to /pay
      is( $transitionType, $key, "pb_transition_type/transitiontype is $key for $_ response");

      $functionCalled = '';
      $transitionType = '';

      if ($key eq 'post') {
        PlugNPay::Legacy::MckUtils::Transition::transitionPage($fieldDataMapCopy->{$key}, $inputDataMapCopy->{$key}, 0);
        # make sure postRedirect is called when transitiontype = 'post'
        is( $functionCalled, 'postRedirect', "postDirect sub was called when transitionType is $key for $_ response");
        is( $transitionType, $key, "pb_transition_type/transitiontype is $key for $_ response, , and alwaysUsePost is off");
      } else {
        PlugNPay::Legacy::MckUtils::Transition::transitionPage($fieldDataMapCopy->{$key}, $inputDataMapCopy->{$key}, 0);
        # make sure postRedirect is not called when transitiontype != 'post'
        is( $functionCalled, '', "postDirect sub is not called when transitionType is $key for $_ response, and alwaysUsePost is off");
      }
    }
  }

  $transitionMock2->unmock('postRedirect');
}