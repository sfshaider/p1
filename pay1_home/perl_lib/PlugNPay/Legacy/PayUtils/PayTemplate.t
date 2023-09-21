#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 10;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);

require_ok('PlugNPay::Legacy::PayUtils::PayTemplate');

SKIP: {
  skipIntegration( "skipping integration tests for template loading", 5);

  # getTransitionPage()

  if (INTEGRATION) {
    # NOTE:
    #   The order of these tests is very important.

    # clear feature value for template loadeding.
    my $features = new PlugNPay::Features( 'pnpdemo', 'general' );
    $features->set( 'paycgiTemplate', '' );
    $features->saveContext();

    my $wdf = new PlugNPay::WebDataFile();

    my %baseWDFRequest = ( storageKey => 'merchantAdminTemplates' );

    #############################
    # default merchant template #
    #############################
    my $defaultContent = 'default template content';

    my $defaultTemplate = {
      %baseWDFRequest,
      subPrefix => 'payscreen/',
      fileName  => 'pnpdemo_paytemplate.txt',
      content   => $defaultContent
    };

    # write the test template
    $wdf->writeFile($defaultTemplate);

    my $loadTemplateInput = {
      gatewayAccount    => 'pnpdemo',
      reseller          => 'devresell',
      cobrand           => '',
      language          => '',
      client            => '',
      requestedTemplate => ''
    };

    my $loadedContent = PlugNPay::Legacy::PayUtils::PayTemplate::loadTemplate($loadTemplateInput);
    is( $loadedContent, $defaultContent, 'loadedContent matches stored content for default template' );

    #############################
    # default language template #
    #############################
    # this should load with the default template set in the feature, and not overwrite the feature
    # the latter is tested by ensuring the default template is loaded again when language is removed from the input
    my $defaultLanguageContent = 'default language template content';

    my $defaultLanguageTemplate = {
      %baseWDFRequest,
      subPrefix => 'payscreen/',
      fileName  => 'pnpdemo_en_paytemplate.txt',
      content   => $defaultLanguageContent
    };

    # write the test template
    $wdf->writeFile($defaultLanguageTemplate);

    $loadTemplateInput = {
      gatewayAccount    => 'pnpdemo',
      reseller          => 'devresell',
      cobrand           => '',
      language          => 'en',
      client            => '',
      requestedTemplate => ''
    };

    $loadedContent = PlugNPay::Legacy::PayUtils::PayTemplate::loadTemplate($loadTemplateInput);
    is( $loadedContent, $defaultLanguageContent, 'loadedContent matches stored content for default language template' );

    # try to load default tempalte again after language template loaded to ensure feature is not set.
    $loadTemplateInput->{'language'} = '';
    $loadedContent = PlugNPay::Legacy::PayUtils::PayTemplate::loadTemplate($loadTemplateInput);
    is( $loadedContent, $defaultContent, 'loadedContent matches stored content for default template' );

    
    #############
    # requested #
    #############
    my $requestedContent = 'requested template content';

    my $requestedTemplate = {
      %baseWDFRequest,
      subPrefix => 'payscreen/',
      fileName  => 'pnpdemo_requested.txt',
      content   => $requestedContent
    };

    # write the test template
    $wdf->writeFile($requestedTemplate);

    $loadTemplateInput = {
      gatewayAccount    => 'pnpdemo',
      reseller          => 'devresell',
      cobrand           => '',
      language          => '',
      client            => '',
      requestedTemplate => 'requested'
    };

    $loadedContent = PlugNPay::Legacy::PayUtils::PayTemplate::loadTemplate($loadTemplateInput);
    is( $loadedContent, $requestedContent, 'loadedContent matches stored content for requested template' );

    #########################
    # requested w/ language #
    #########################
    my $requestedLanguageContent = 'requested language template content';

    my $requestedLanguageTemplate = {
      %baseWDFRequest,
      subPrefix => 'payscreen/',
      fileName  => 'pnpdemo_en_requested.txt',
      content   => $requestedLanguageContent
    };

    # write the test template
    $wdf->writeFile($requestedLanguageTemplate);

    $loadTemplateInput = {
      gatewayAccount    => 'pnpdemo',
      reseller          => 'devresell',
      cobrand           => '',
      language          => 'en',
      client            => '',
      requestedTemplate => 'requested'
    };

    $loadedContent = PlugNPay::Legacy::PayUtils::PayTemplate::loadTemplate($loadTemplateInput);
    is( $loadedContent, $requestedLanguageContent, 'loadedContent matches stored content for requested language template' );

    ###########
    # cobrand #
    ###########
    # clear feature value for template loadeding.
    $features->set( 'paycgiTemplate', '' );
    $features->saveContext();

    my $cobrandContent = 'cobrand template content';

    my $cobrandTemplate = {
      %baseWDFRequest,
      subPrefix => 'payscreen/cobrand/',
      fileName  => 'acobrand_paytemplate.txt',
      content   => $cobrandContent
    };

    # clear default template, as cobrand is lower priority
    $wdf->deleteFile($defaultTemplate);

    # write the test template
    $wdf->writeFile($cobrandTemplate);

    $loadTemplateInput = {
      gatewayAccount    => 'pnpdemo',
      reseller          => 'devresell',
      cobrand           => 'acobrand',
      language          => '',
      client            => '',
      requestedTemplate => ''
    };

    $loadedContent = PlugNPay::Legacy::PayUtils::PayTemplate::loadTemplate($loadTemplateInput);
    is( $loadedContent, $cobrandContent, 'loadedContent matches stored content for cobrand template' );

    ############
    # reseller #
    ############
    # clear feature value for template loadeding.
    $features->set( 'paycgiTemplate', '' );
    $features->saveContext();

    my $resellerContent = 'reseller template content';

    my $resellerTemplate = {
      %baseWDFRequest,
      subPrefix => 'payscreen/',
      fileName  => 'devresell_paytemplate.txt',
      content   => $resellerContent
    };

    # clear cobrand template, as reseller is lower priority than cobrand
    $wdf->deleteFile($cobrandTemplate);

    # write the test template
    $wdf->writeFile($resellerTemplate);

    $loadTemplateInput = {
      gatewayAccount    => 'pnpdemo',
      reseller          => 'devresell',
      cobrand           => 'acobrand',
      language          => '',
      client            => '',
      requestedTemplate => ''
    };

    $loadedContent = PlugNPay::Legacy::PayUtils::PayTemplate::loadTemplate($loadTemplateInput);
    is( $loadedContent, undef, 'loadedContent is empty for devresell template (not a matching client)' );

    # now a reseller test for a 'matching' reseller (aaronsinc) with a specific client string (aaronsinc)
    # clear feature value for template loadeding.
    $features->set( 'paycgiTemplate', '' );
    $features->saveContext();

    # :neutral_face:
    # $loadTemplateInput->{'reseller'} = 'aaronsinc';
    # $loadTemplateInput->{'client'}   = 'affiniscape';
    $resellerTemplate                = {
      %baseWDFRequest,
      subPrefix => 'payscreen/',
      fileName  => 'aaronsinc_paytemplate.txt',
      content   => $resellerContent
    };

    # write the test template for matching reseller (aaronsinc)
    $wdf->writeFile($resellerTemplate);

    $loadTemplateInput = {
      gatewayAccount    => 'pnpdemo',
      reseller          => 'devresell',
      cobrand           => 'acobrand',
      language          => '',
      client            => 'affiniscape',
      requestedTemplate => ''
    };

    $loadedContent = PlugNPay::Legacy::PayUtils::PayTemplate::loadTemplate($loadTemplateInput);
    is( $loadedContent, $resellerContent, 'loadedContent matches stored content for aaronsinc template (matching reseller with client)' );

    delete $loadTemplateInput->{'client'};
    $wdf->writeFile($defaultTemplate);

    # now test load for aaronsinc without client set to ensure the client version is not saved as default
    $loadedContent = PlugNPay::Legacy::PayUtils::PayTemplate::loadTemplate($loadTemplateInput);
    is( $loadedContent, $defaultContent, 'loadedContent matches stored content for default template (not matching reseller)' );
  }
}
