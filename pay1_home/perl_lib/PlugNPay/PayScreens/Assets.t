#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 16;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);

require_ok('PlugNPay::Util::Status');
require_ok('PlugNPay::PayScreens::Assets');

my $assets = new PlugNPay::PayScreens::Assets();

if (!INTEGRATION) {
  diag('set TEST_INTEGRATION=1 to run integration tests');
}

SKIP: {
  skipIntegration("skipping integration test for s3 bucket definition verification",5);

  if (INTEGRATION) {
    my $objectNameInput = {
      assetType => 'logo',
      gatewayAccount => 'pnpdemo',
      localFile => '/home/pay1/web/logos/upload/logos/pnpdemo.gif'
    };

    # get info for an asset type for a username
    my $logoObjectInfo = $assets->getAssetInfo($objectNameInput);
    is($logoObjectInfo->{'object'},'merchant/pnpdemo/pay/logo','getObjectInfo: pay logo object key is correct');
    is($logoObjectInfo->{'bucket'},'static.dev.gateway-assets.com','getObjectInfo: pay logo bucket is correct');

    # upload a logo asset type for a username
    my $status;
    ($logoObjectInfo,$status) = $assets->migrate($objectNameInput);
    if (!$status) {
      diag($status->getError());
    }
    is($logoObjectInfo->{'object'},'merchant/pnpdemo/pay/logo','migrate: pay logo object key is correct');
    is($logoObjectInfo->{'bucket'},'static.dev.gateway-assets.com','migrate: pay logo bucket is correct');

    my $assetInfo = $assets->getAssetUrls($objectNameInput);
    is($assetInfo->{'sameHostUrl'}, '/assets/merchant/pnpdemo/pay/logo', 'getAssetUrls: sameHostUrl is correct');
  }
}

# _dirFromFile
my $file = '/home/p/pay1/file.txt';
my $dir = $assets->_dirFromFile($file);
is($dir,'/home/p/pay1','_dirFromFile() successfully extracts directory from file name');

# run _updateAssetsInHtml tests
test_updateAssetsInHtml();
test_replaceAssetUrl();
test_getStaticContentServerSetting();

sub test_updateAssetsInHtml {
  my $html = qq|
  <img src="https://www.example.com/logos/upload/logos/pnpdemo.jpg">
  |;

  my $username = 'pnpdemo';

  my $privateLabelDomains = ['www.example.com'];
  my %assetUrls;

  my $assetData = {
    object => 'fake-logo',
    bucket => 'fake-bucket',
    urls => [sprintf('https://fake-static.gateway-assets.com/merchant/%s/fake-logo',$username)],
    sameHostUrl => sprintf('https://www.example.com/_img/merchant/%s/logo',$username),
    contentType => 'image/jpeg',
    size => 'i forgot what this is for'
  };

  my $updateData = {
    html => $html,
    username => $username,
    privateLabelDomains => $privateLabelDomains,
    assetUrls => \%assetUrls,
    staticContentServerSetting => 'sameHost',
    existsFunction => sub {
      return 1;
    },
    migrationFunction => sub {
      return ($assetData, new PlugNPay::Util::Status(1));
    },
    assetInfoFunction => sub {
      return $assetData
    }
  };

  $html = PlugNPay::PayScreens::Assets::_updateAssetsInHtml($updateData);

  my $staticUrl = $assetData->{'sameHostUrl'};
  like($html,qr/$staticUrl/,'url replaced with proper same host url');

  $updateData->{'staticContentServerSetting'} = 'cdn'; # technically anything but sameHost will do
  %assetUrls = (); # clear asset urls so they don't get reused
  $html = PlugNPay::PayScreens::Assets::_updateAssetsInHtml($updateData);
  my $cdnUrl = $assetData->{'urls'}[0];
  like($html,qr/$cdnUrl/,'url replaced with proper cdn url');
}

sub test_replaceAssetUrl {
  my $html = qq|<input type="hidden" name="image-link" value="/logos/upload/logos/miketest.png">|;
  my $replacement = 'replacementUrl';

  $html = PlugNPay::PayScreens::Assets::_replaceAssetUrl($html,$replacement);
  like($html,qr/type="hidden"/,'_replaceAssetUrl: type is retained upon replacement');
  like($html,qr/name="image-link"/,'_replaceAssetUrl: name is retained upon replacement');
  like($html,qr/value='replacementUrl'/,'_replaceAssetUrl: value is replaced');
}

sub test_getStaticContentServerSetting {
  my $features = new PlugNPay::Features();


  # used repeatedly in test
  my ($setValue,$getValue);

  $getValue = PlugNPay::PayScreens::Assets::_getStaticContentServerSetting($features);
  is($getValue,$setValue,'undef returned for setting with neither slashpayStaticContent nor staticContentServer set');

  # for the rest of the tests
  $setValue = 'sameHost';

  $features->set('slashpayStaticContent',$setValue);
  $getValue = PlugNPay::PayScreens::Assets::_getStaticContentServerSetting($features);
  is($getValue,$setValue,'sameHost returned with slashpayStaticContent set');
  
  # remove slashpayStaticContent value
  $features->remove('slashpayStaticContent');

  $features->set('staticContentServer',$setValue);
  $getValue = PlugNPay::PayScreens::Assets::_getStaticContentServerSetting($features);
  is($getValue,$setValue,'sameHost returned with staticContentServer set');
}