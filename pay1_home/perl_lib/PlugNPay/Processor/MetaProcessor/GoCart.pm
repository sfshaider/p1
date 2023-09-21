package PlugNPay::Processor::MetaProcessor::GoCart;

use strict;
use PlugNPay::Processor::Account;
use XML::Simple;
use PlugNPay::Sys::Time;
use PlugNPay::Util::Hash;
use PlugNPay::ResponseLink;
use JSON::XS;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::Legacy::AdditionalProcessorData;
use PlugNPay::GatewayAccount;
use MIME::Base64 qw(encode_base64 decode_base64);

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;

    my $account = shift;
    if ($account) {
        $self->setAccount($account);
    }

    $self->setProcessor('worldpayfis');

    # load gatewayAccount settings
    my $ga = new PlugNPay::GatewayAccount($self->getAccount());
    my $isTest = $ga->isTest();
    my $isLive = $ga->isLive();

    # load processor settings
    my $processorAccount = new PlugNPay::Processor::Account({
        'processorName'  => 'gocart',
        'gatewayAccount' => $self->getAccount()
    });
    my $isEnabled = $processorAccount->getSettingValue('enabled') ? 1 : 0;

    if ($isEnabled) {
        $self->setEnabled($isEnabled);
        my $isStaging = $processorAccount->getSettingValue('staging') ? 1 : 0;

        if ($isTest && $isStaging eq '1') {
            $self->setStaging($isStaging);
            $self->setGoCartMerchantId($processorAccount->getSettingValue('stagingMerchantId'));
            $self->setGoCartAPIKey($processorAccount->getSettingValue('stagingApiKey'));
        }
        elsif ($isLive && $isStaging eq '0') {
            $self->setGoCartMerchantId($processorAccount->getSettingValue('goCartMerchantId'));
            $self->setGoCartAPIKey($processorAccount->getSettingValue('goCartApiKey'));
        }
        else {
            # disable GoCart
            $self->setEnabled('0');
            my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'partner_gocart' });
            $logger->log({
                'account' => $self->getAccount(),
                'message' => 'GoCart is not configured correctly'
            });
        }

        $self->setExpeditedCheckoutEnabled($processorAccount->getSettingValue('expeditedCheckout'));
        $self->setEnrollmentCheckboxEnabled($processorAccount->getSettingValue('enrollmentEnabled'));
        $self->setEnrollmentCheckboxChecked($processorAccount->getSettingValue('enrollmentChecked'));
    }

    return $self;
}

sub setAccount {
    my $self = shift;
    my $account = shift;
    $self->{'account'} = $account;
}

sub getAccount {
    my $self = shift;
    return $self->{'account'};
}

sub setProcessor {
    my $self = shift;
    my $processor = shift;
    $self->{'processor'} = $processor;
}

sub getProcessor {
    my $self = shift;
    return $self->{'processor'};
}

sub getMid {
    my $self = shift;

    my $processorAccount = new PlugNPay::Processor::Account({
        'processorName'  => $self->getProcessor(),
        'gatewayAccount' => $self->getAccount()
    });

    $self->{'mid'} = $processorAccount->getSettingValue('mid');
    return $self->{'mid'};
}

sub setGoCartMerchantId {
    my $self = shift;
    my $goCartMerchantId = shift;
    $self->{'goCartMerchantId'} = $goCartMerchantId;
}

sub getGoCartMerchantId {
    my $self = shift;
    return $self->{'goCartMerchantId'} || '';
}

sub setGoCartAPIKey {
    my $self = shift;
    my $goCartAPIKey = shift;
    $self->{'goCartAPIKey'} = $goCartAPIKey;
}

sub getGoCartAPIKey {
    my $self = shift;
    return $self->{'goCartAPIKey'} || '';
}

sub setStaging {
    my $self = shift;
    my $staging = shift;
    $self->{'staging'} = $staging;
}

sub getStaging {
    my $self = shift;
    return ($self->{'staging'} ? 1 : 0);
}

sub setEnabled {
    my $self = shift;
    my $enabled = shift;
    $self->{'enabled'} = $enabled;
}

sub getEnabled {
    my $self = shift;
    return ($self->{'enabled'} ? 1 : 0);
}

sub setExpeditedCheckoutEnabled {
    my $self = shift;
    my $enabled = shift;
    $self->{'expeditedCheckoutEnabled'} = $enabled;
}

sub getExpeditedCheckoutEnabled {
    my $self = shift;
    return $self->{'expeditedCheckoutEnabled'};
}

sub setEnrollmentCheckboxEnabled {
    my $self = shift;
    my $enabled = shift;
    $self->{'enrollmentEnabled'} = $enabled;
}

sub getEnrollmentCheckboxEnabled {
    my $self = shift;
    return ($self->{'enrollmentEnabled'} ? 1 : 0);
}

sub setEnrollmentCheckboxChecked {
    my $self = shift;
    my $checked = shift;
    $self->{'enrollmentChecked'} = $checked;
}

sub getEnrollmentCheckboxChecked {
    my $self = shift;
    return ($self->{'enrollmentChecked'} ? 1 : 0);
}


sub getSdkUrl {
    my $self = shift;

    my $enabled = $self->getEnabled();
    my $id = $self->getGoCartMerchantId();
    my $staging = $self->getStaging() ? '-staging' : '';
    my $url = '';

    if ($id eq '') {
        my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'partner_gocart' });
        $logger->log({
            'account'       => $self->getAccount(),
            'message'       => 'GoCart is enabled but missing GoCart merchant ID'
        });
    }

    if ($enabled && $id ne '') {
        $url = 'https://api' . $staging . '.gocartpay.com/merchants/' . $id . '/sdk';
    }

    return $url;
}

sub generateWorldpayfisAuthCode {
    my $self = shift;
    my $goCartResponseData = shift;
    my $orderID = shift;

    my $authCodeString = '';

    if ($self->getStaging()) {
        $authCodeString = 'TSTAUTH';
    } else {
        eval {
            my $goCartData = XMLin($goCartResponseData);
            my $approvalNumber = $goCartData->{'Response'}{'Transaction'}{'ApprovalNumber'};
            my $networkTransactionId = $goCartData->{'Response'}{'Transaction'}{'NetworkTransactionID'};
            my $transactionId = $goCartData->{'Response'}{'Transaction'}{'TransactionID'};
            my $hostBatchId = $goCartData->{'Response'}{'Batch'}{'HostBatchID'};
            my $expressResponseCode = $goCartData->{'Response'}{'ExpressResponseCode'};

            # Generate auth code
            my $processor = new PlugNPay::Processor({ shortName => $self->getProcessor() });
            my $authCode = new PlugNPay::Transaction::Legacy::AdditionalProcessorData({ 'processorId' => $processor->getID() });

            # right now *** THIS IS WORLDPAY SPECIFIC ***
            if ($self->getProcessor() eq 'worldpayfis') {
                $authCode->setField('appcode', $approvalNumber);
                $authCode->setField('nettransid', $networkTransactionId);
                $authCode->setField('ponumber', '');
                $authCode->setField('country', '');
                $authCode->setField('tax', '');
                $authCode->setField('shipzip', '');
                $authCode->setField('magstripetrack', '');
                $authCode->setField('cashback', '');
                $authCode->setField('transid', $transactionId);
                $authCode->setField('hostbatchid', $hostBatchId);
                $authCode->setField('hostitemid', '');
                $authCode->setField('marketdata', '');
                $authCode->setField('commflag', '');
                $authCode->setField('gratuity', '');
                $authCode->setField('authrespcode', $expressResponseCode);
                $authCode->setField('dccinfo', '');
                $authCode->setField('deviceid', '');
                $authCode->setField('surcharge', '');
                $authCode->setField('convfee', '');
                $authCodeString = $authCode->getAdditionalDataString();
            }
        };

        if ($@) {
            my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'partner_gocart' });
            $logger->log({
                'account'       => $self->getAccount(),
                'goCartOrderID' => $orderID,
                'message'       => 'auth_code could not be generated',
                'errorMessage'  => $@
            });
        }
    }

    return $authCodeString;
}

sub generateGoCartRequestSignature {
    my $self = shift;
    my $data = shift;

    my $xMerchantId = $data->{'xMerchantId'};
    my $xApiKey = $data->{'$xApiKey'};
    my $orderID = $data->{'orderID'};

    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'partner_gocart'});
    if (!defined $xMerchantId) {
        $logger->log({
            'account'        => $self->getAccount(),
            'goCartOrderID'  => $orderID,
            'message'        => 'GoCart merchant ID not defined.',
        });
    }
    if (!defined $xApiKey) {
        $logger->log({
            'account'        => $self->getAccount(),
            'goCartOrderID'  => $orderID,
            'message'        => 'GoCart API Key is not defined.',
        });
    }

    my $timeStamp = $data->{'timeStamp'};
    my $nonce = $data->{'nonce'};
    my $requestURI = 'orders/' . $orderID;
    my $requestMethod = 'GET';
    my $requestBody = '';

    my $signatureString = uc($xMerchantId . '|' . $xApiKey . '|' . $timeStamp . '|' . $nonce . '|' . $requestURI . '|' . $requestMethod . '|' . $requestBody);
    # remove whitespace
    $signatureString =~ s/\s//g;
    # base64 encode
    my $encodedString = encode_base64($signatureString);
    # remove white space again
    $encodedString =~ s/\s//g;
    # generate sha256 hash
    my $hash = new PlugNPay::Util::Hash();
    $hash->add($encodedString);
    my $signature = $hash->sha256();

    return $signature;
}

sub generateGoCartRequestHeader {
    my $self = shift;
    my $orderID = shift;

    my $xMerchantId = $self->getGoCartMerchantId();
    my $xApiKey = $self->getGoCartAPIKey();
    my $timeStamp = new PlugNPay::Sys::Time('unix');
    my $nonce = new PlugNPay::Util::RandomString()->randomAlphaNumeric('32');

    my $signatureData = {
        'xMerchantId' => $xMerchantId,
        '$xApiKey'    => $xApiKey,
        'timeStamp'   => $timeStamp,
        'nonce'       => $nonce,
        'orderID'     => $orderID
    };

    my $signature = $self->generateGoCartRequestSignature($signatureData);

    my $header = {'X-Merchant-Id' => $xMerchantId, 'Timestamp' => $timeStamp, 'Nonce' => $nonce, 'Signature' => $signature};

    return $header;
}

sub doGoCartRequest {
    my $self = shift;
    my $orderID = shift;

    my $username = $self->getAccount();
    my $header = $self->generateGoCartRequestHeader($orderID);

    # type ProxyRequest struct {
    # 	Uri           string            `json:"uri"` // path part of url, without leading slash
    # 	Method        string            `json:"method"`
    # 	Content       string            `json:"content"` // base64 encoded content.
    # 	ContentType   string            `json:"contentType"`
    # 	HostId        *string           `json:"hostId"`
    # 	Headers       map[string]string `json:"headers"`
    # 	LogIdentifier string            `json:"logIdentifier"`
    # }

    my $proxyRequest = {
        uri => 'orders/' . $orderID,
        method => 'GET',
        hostId => ($self->getStaging() ? 'staging' : 'production'),
        headers => $header,
        logIdentifier => sprintf('%s:%s',$username,$orderID)
    };

    my $proxyRequestJson = encode_json($proxyRequest);

    my $rl = new PlugNPay::ResponseLink();
    $rl->setUsername($username);
    $rl->setRequestMethod('POST');
    $rl->setRequestMode('DIRECT');
    $rl->setRequestData($proxyRequestJson);
    $rl->setRequestContentType('application/json');
    $rl->setRequestURL('http://proc-gocart.local/proxy');
    $rl->doRequest();
    my $proxyContent = $rl->getResponseContent();
    my $responseData = decode_json($proxyContent);

    my $responseContent;
    my $responseContentJson;

    eval {
      $responseContentJson = decode_base64($responseData->{'responseContent'});
      $responseContent = decode_json($responseContentJson);
    };

    my $status = $responseData->{'responseStatusCode'};

    if ($status ne '200') {
        my $logger = new PlugNPay::Logging::DataLog({'collection' => 'partner_gocart'});
        $logger->log({
            account       => $self->getAccount(),
            goCartOrderID => $orderID,
            message       => 'Request to GoCart failed',
            status        => $status,
            responseJson  => $responseContentJson,
            response      => $responseContent
        });
    }

    return $responseContentJson;
}

sub verifyGoCartOrder {
    my $self = shift;
    my $orderID = shift;

    my $responseJSON = $self->doGoCartRequest($orderID);
    my $response;
    eval {
        $response = decode_json($responseJSON);
    };
    if ($@) {
        my $logger = new PlugNPay::Logging::DataLog({'collection' => 'partner_gocart'});
        $logger->log({
            'account'        => $self->getAccount(),
            'goCartOrderID'  => $orderID,
            'message'        => 'Invalid JSON',
            'response' => $response
        });
    }

    my $status = $response->{'status'};
    my $transactions = $response->{'transactions'};
    my $transactionStatus;
    foreach my $transaction (@{$transactions}) {
        $transactionStatus = $transaction->{'status'};
    }

    my $isValid = 0;
    if ($status eq 'PROCESSED' && $transactionStatus eq 'SUCCESS') {
        $isValid = 1;
    } else {
        my $logger = new PlugNPay::Logging::DataLog({'collection' => 'partner_gocart'});
        $logger->log({
            'account'        => $self->getAccount(),
            'goCartOrderID'  => $orderID,
            'message'        => 'Could not verify order with GoCart',
            'goCartResponse' => $response
        });
    }

    return $isValid;
}

sub postProcess {
    my $self = shift;
    my $data = shift;

    my $clientResponse = $data->{'clientResponse'};
    my $orderID = $data->{'goCartOrderID'};
    my $responseData = {};

    $responseData->{'processor'} = $self->getProcessor();
    $responseData->{'mid'} = $self->getMid();

    # Validate order with GoCart
    my $orderIsValid = $self->verifyGoCartOrder($orderID);

    # Generate auth code
    my $authCode;
    $authCode = $self->generateWorldpayfisAuthCode($clientResponse, $orderID);
    $responseData->{'authCode'} = $authCode;

    if ($orderIsValid && $authCode ne '') {
        $responseData->{'FinalStatus'} = 'success';
    } else {
        my $errorMessage = "Could not validate GoCart order $orderID";
        $responseData->{'FinalStatus'} = 'problem';
        $responseData->{'MStatus'} = 'problem';
        $responseData->{'MErrMsg'} = $errorMessage;
    }

    return $responseData;
}




1;
