#!/bin/env perl
BEGIN {
    $ENV{'DEBUG'} = undef;
}

use strict;
use Test::More tests => 16;
use PlugNPay::Testing qw(skipIntegration INTEGRATION);
use Switch;

use lib $ENV{'PNP_PERL_LIB'};
require_ok('PlugNPay::Processor::MetaProcessor::GoCart');
require_ok('PlugNPay::GatewayAccount');
require_ok('PlugNPay::Processor::Account');

my $account = 'pnpdemo';

my $gatewayAccount = new PlugNPay::GatewayAccount($account);
my $originalStatus = $gatewayAccount->getStatus();
$gatewayAccount->setForceStatusChange('1');

my $processorAccount = new PlugNPay::Processor::Account({
    'processorName'  => 'gocart',
    'gatewayAccount' => $account
});

SKIP: {
    skipIntegration("skipping integration tests", 13);

    if (INTEGRATION) {
        # First make sure GoCart is enabled
        $processorAccount->setSettingValue('enabled', '1');
        $processorAccount->save();

        testAuthCodeGenerator($gatewayAccount, $processorAccount, $account);
        testValidateOrder($gatewayAccount, $processorAccount, $account);
        testGoCartIds($gatewayAccount, $processorAccount, $account);
        resetOriginalValues($gatewayAccount, $originalStatus);
    }
}

sub testAuthCodeGenerator {
    $gatewayAccount = shift;
    $processorAccount = shift;
    $account = shift;

    $gatewayAccount->setLive();
    $gatewayAccount->save();
    $processorAccount->setSettingValue('staging', '0');
    $processorAccount->save();

    my $stringLength = 434;
    my $goCartResponseData = "
    <CreditCardAuthorizationResponse xmlns='https://transaction.elementexpress.com'>
      <Response>
        <ExpressResponseCode>0</ExpressResponseCode>
        <ExpressResponseMessage>Approved</ExpressResponseMessage>
        <HostResponseCode>00</HostResponseCode>
        <ExpressTransactionDate>20210826</ExpressTransactionDate>
        <ExpressTransactionTime>135828</ExpressTransactionTime>
        <ExpressTransactionTimezone>UTC-05:00:00</ExpressTransactionTimezone>
        <Batch>
          <HostBatchID>43</HostBatchID>
        </Batch>
        <Card>
          <AVSResponseCode>Y</AVSResponseCode>
          <CVVResponseCode>P</CVVResponseCode>
          <ExpirationMonth>01</ExpirationMonth>
          <ExpirationYear>25</ExpirationYear>
          <CardLogo>Visa</CardLogo>
          <CardNumberMasked>xxxx-xxxx-xxxx-1111</CardNumberMasked>
          <BIN>411111</BIN>
          <CardLevelResults>A </CardLevelResults>
        </Card>
        <Transaction>
          <TransactionID>108713463</TransactionID>
          <ApprovalNumber>047096</ApprovalNumber>
          <ReferenceNumber>GC00000000119-00</ReferenceNumber>
          <AcquirerData>713463|123813713463|0826185828|1042000314|V|5|212000142623430|12UW||||||||A |||||||59|1000|135828|||||||429F203|0826||C||||||</AcquirerData>
          <ProcessorName>VANTIV_TEST</ProcessorName>
          <TransactionStatus>Authorized</TransactionStatus>
          <TransactionStatusCode>5</TransactionStatusCode>
          <HostTransactionID>100000</HostTransactionID>
          <ApprovedAmount>1.00</ApprovedAmount>
          <NetworkTransactionID>212000142623430</NetworkTransactionID>
          <RetrievalReferenceNumber>123813713463</RetrievalReferenceNumber>
          <SystemTraceAuditNumber>713463</SystemTraceAuditNumber>
        </Transaction>
        <Address>
          <BillingAddress1>1363-26 Vetterans Highway</BillingAddress1>
          <BillingZipcode>11788</BillingZipcode>
        </Address>
        <Terminal>
          <MotoECICode>7</MotoECICode>
        </Terminal>
        <Token>
          <TokenID>4111114335161111</TokenID>
          <TokenProvider>2</TokenProvider>
        </Token>
      </Response>
    </CreditCardAuthorizationResponse>";

    # test production
    my $goCart = new PlugNPay::Processor::MetaProcessor::GoCart($account);
    my $authCodeString = $goCart->generateWorldpayfisAuthCode($goCartResponseData);
    ok($authCodeString ne '', 'production auth code string has a value');
    is(length($authCodeString), $stringLength, 'production auth code string length is correct');

    # test staging
    $gatewayAccount->setTest();
    $gatewayAccount->save();
    $processorAccount->setSettingValue('staging', '1');
    $processorAccount->save();
    my $goCart = new PlugNPay::Processor::MetaProcessor::GoCart($account);
    my $authCodeString = $goCart->generateWorldpayfisAuthCode();
    is($authCodeString, 'TSTAUTH', 'staging auth code string is correct');
}

sub testValidateOrder {
    $gatewayAccount = shift;
    $processorAccount = shift;
    $account = shift;

    my $orderID = '890f41f5-ff50-4b2f-8721-6c06bcc248f4';

    $gatewayAccount->setTest();
    $gatewayAccount->save();
    $processorAccount->setSettingValue('staging', '1');
    $processorAccount->save();

    my $goCart = new PlugNPay::Processor::MetaProcessor::GoCart($account);
    my $isValid = $goCart->verifyGoCartOrder($orderID);

    TODO: {
        local $TODO = "not sure if this is automatable. GoCart could make changes that could cause this test to fail.";
        is($isValid, 1, 'GoCart order is valid');
    }
}

sub testGoCartIds {
    $gatewayAccount = shift;
    $processorAccount = shift;
    $account = shift;

    my $prodMerchantId = 'pnpdemo-test-merchant-id';
    my $prodApiKey = 'pnpdemo-test-api-key';
    my $stagingMerchantId = '1ec95dfc-8f8d-4ba4-8d5f-3f99f0669111';
    my $stagingApiKey = '89f8b8415a9449338797ce9ac3f39257';

    $processorAccount->setSettingValue('goCartMerchantId', $prodMerchantId);
    $processorAccount->setSettingValue('goCartApiKey', $prodApiKey);
    $processorAccount->setSettingValue('stagingMerchantId', $stagingMerchantId);
    $processorAccount->setSettingValue('stagingApiKey', $stagingApiKey);

    # test production
    $gatewayAccount->setLive();
    $gatewayAccount->save();
    $processorAccount->setSettingValue('staging', '0');
    $processorAccount->save();
    my $goCart = new PlugNPay::Processor::MetaProcessor::GoCart($account);
    is($goCart->getGoCartMerchantId, $prodMerchantId, 'production merchant id is correct');
    is($goCart->getGoCartAPIKey, $prodApiKey, 'production api key is correct');

    # test staging
    $gatewayAccount->setTest();
    $gatewayAccount->save();
    $processorAccount->setSettingValue('staging', '1');
    $processorAccount->save();
    my $goCart = new PlugNPay::Processor::MetaProcessor::GoCart($account);
    is($goCart->getGoCartMerchantId, $stagingMerchantId, 'staging merchant id is correct');
    is($goCart->getGoCartAPIKey, $stagingApiKey, 'staging api key is correct');

    # test invalid configuration 1
    $gatewayAccount->setLive();
    $gatewayAccount->save();
    $processorAccount->setSettingValue('staging', '1');
    $processorAccount->save();
    my $goCart = new PlugNPay::Processor::MetaProcessor::GoCart($account);
    is($goCart->getGoCartMerchantId, '', 'invalid test 1 merchant id is correct');
    is($goCart->getGoCartAPIKey, '', 'invalid test 1 api key is correct');

    # test invalid configuration 2
    $gatewayAccount->setTest();
    $gatewayAccount->save();
    $processorAccount->setSettingValue('staging', '0');
    $processorAccount->save();
    my $goCart = new PlugNPay::Processor::MetaProcessor::GoCart($account);
    is($goCart->getGoCartMerchantId, '', 'invalid test 2 merchant id is correct');
    is($goCart->getGoCartAPIKey, '', 'invalid test 2 api key is correct');
}

sub resetOriginalValues {
    $gatewayAccount = shift;
    $originalStatus = shift;

    switch($originalStatus) {
      case 'pending' {$gatewayAccount->setPending()}
      case 'debug' {$gatewayAccount->setDebug()}
      case 'live' {$gatewayAccount->setLive()}
      case 'cancelled' {$gatewayAccount->setCancelled()}
      case 'test' {$gatewayAccount->setTest()}
      case 'fraud' {$gatewayAccount->setFraud()}
      case 'hold' {$gatewayAccount->setOnHold()}
    }
    $gatewayAccount->save();

    is($gatewayAccount->getStatus, $originalStatus, 'account status has been set back to its original value');
}
