package PlugNPay::Transaction::MapLegacy;

use strict;
use PlugNPay::GatewayAccount;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::SECCode;
use PlugNPay::Transaction::Loader;
use PlugNPay::Sys::Time;
use PlugNPay::Transaction::DefaultValues;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Transaction::State;
use PlugNPay::Transaction;
use PlugNPay::Transaction::Response;
use PlugNPay::Processor::ID;
use PlugNPay::Processor;

# This was buildSendMServerPairs function in TransactionProcessor #

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub map {
  my $self = shift;
  my $transactionObject = shift;
  my $gatewayAccount = shift || $transactionObject->getGatewayAccount();

  my $transactionObjectIsOk = 0;
  eval {
    if ($transactionObject->isa('PlugNPay::Transaction')) {
      $transactionObjectIsOk = 1;
    }
  };

  if (!$transactionObjectIsOk) {
    die('transactionObject is not a PlugNPay::Transaction');
  }

  my $responseObject = $transactionObject->getResponse();

  # create a hash that we will push onto the @sendmserverData array
  my %pairs = ();

  # do customData first so that if there's any reserved parameters, they are overwritten
  my $customData = $transactionObject->getCustomData();
  my $customCount = 1;
  foreach my $key (keys %{$customData}) {
    $pairs{'customname' . $customCount} = $key;
    $pairs{'customvalue' . $customCount} = $customData->{$key};
    $pairs{$key} = $customData->{$key};
    $customCount++;
  }

  # put the transaction amount into the pairs
  my $currency = lc $transactionObject->getCurrency() || lc new PlugNPay::GatewayAccount($gatewayAccount)->getDefaultCurrency();
  my $amount = $transactionObject->getTransactionAmount();
  $pairs{'amount'} = $currency . ' ' . $amount;
  $pairs{'base_amount'} = $currency . ' ' . $transactionObject->getBaseTransactionAmount();
  if ($transactionObject->getTransactionDateTime()) {
     $pairs{'trans_time'} = $transactionObject->getTransactionDateTime();
  }

  #IP Address
  $pairs{'ipaddress'} = $transactionObject->getIPAddress();

  if ($transactionObject->doPostAuth() && $transactionObject->getTransactionType() =~ /^auth/i) {
    $pairs{'authtype'} = 'authpostauth';
  }

  if ($transactionObject->doForceAuth()) {
    $pairs{'operation'} = 'forceauth';
  } else {
    my ($transState,$statusCode) = split('_',lc $transactionObject->getTransactionState());
    $pairs{'operation'} = $pairs{'operation'} || $transState;
  }

  # put the tax amount into the pairs
  $pairs{'tax'} = $transactionObject->getTaxAmount();
  $pairs{'base_tax'} = $transactionObject->getBaseTaxAmount();

  # TODO: put the pay method into the pairs

  # put the order id into the pairs
  $pairs{'orderID'} = $transactionObject->getOrderID();
  $pairs{'order-id'} = $transactionObject->getMerchantClassifierID();
  $pairs{'pnp_order_id'} = _binIdToHexId($transactionObject->getPNPOrderID());
  $pairs{'pnp_transaction_id'} = _binIdToHexId($transactionObject->getPNPTransactionID());
  $pairs{'transaction_state'} = $transactionObject->getTransactionState();

  $pairs{'processMode'} = ($transactionObject->isAsynchronous() ? 'async' : 'sync');

  # put transflags into the pairs
  $pairs{'transflags'} = join(',', $transactionObject->getTransFlags());

  # put the account codes into the pairs
  $pairs{'acct_code'}  = $transactionObject->getAccountCode(1);
  $pairs{'acct_code2'} = $transactionObject->getAccountCode(2);
  $pairs{'acct_code3'} = $transactionObject->getAccountCode(3);
  $pairs{'acct_code4'} = $transactionObject->getAccountCode(4);

  if (!defined $pairs{'acct_code3'} || $pairs{'acct_code3'} eq "") {
    $pairs{'acct_code3'} = $transactionObject->getLogin();
  }

  if ($transactionObject->getReason()) {
    $pairs{'acct_code4'} = $transactionObject->getReason();
  }

  $pairs{'extra_data'} = $transactionObject->getExtraTransactionData();


  if ($transactionObject->isAdjustmentSurcharge()) {
    $pairs{'surcharge'} = $transactionObject->getTransactionAmountAdjustment();
  }

  # put the card info into pairs
  if ($transactionObject->getTransactionPaymentType() eq 'credit' && defined $transactionObject->getCreditCard()) {
    $pairs{'card-number'} =  $transactionObject->getCreditCard()->getNumber();
    $pairs{'card-cvv'} =     $transactionObject->getCreditCard()->getSecurityCode();
    $pairs{'card-exp'} =     sprintf('%02d/%02d',$transactionObject->getCreditCard()->getExpirationMonth(),$transactionObject->getCreditCard()->getExpirationYear());
    $pairs{'card-name'} =    $transactionObject->getCreditCard()->getName();
    $pairs{'magstripe'} =    $transactionObject->getCreditCard()->getMagstripe();
    $pairs{'commcardtype'} = $transactionObject->getCreditCard()->getCommCardType();
    $pairs{'accttype'} = 'credit';
  }

  # put the online check info into pairs
  if ($transactionObject->getTransactionPaymentType() eq 'ach' && defined $transactionObject->getOnlineCheck()) {
    $pairs{'card-name'} =  $transactionObject->getOnlineCheck()->getName();
    $pairs{'routingnum'} = $transactionObject->getOnlineCheck()->getRoutingNumber();
    $pairs{'accountnum'} = $transactionObject->getOnlineCheck()->getAccountNumber();
    $pairs{'card-number'} = $pairs{'routingnum'} . ' ' . $pairs{'accountnum'};
    $pairs{'accttype'} = 'checking';
    $pairs{'checktype'} = $transactionObject->getSECCode();
    my $secCodeChecker = new PlugNPay::SECCode();
    if ($secCodeChecker->isCommercial($transactionObject->getSECCode())) {
      $pairs{'commcardtype'} = 'purchase'; # why an ach transaction uses "commcardtype" i will never understand.
    }
  }

  if($transactionObject->getTransactionPaymentType() eq 'emv') {
    $pairs{'paymethod'} = 'emv';
  }

  $pairs{'pnp_token'} = $transactionObject->getPNPToken() || new PlugNPay::Token()->getToken($pairs{'card-number'});

  if (defined $transactionObject->getBillingInformation()) {
    my $addr1 = $transactionObject->getBillingInformation()->getAddress1();
    my $addr2 = $transactionObject->getBillingInformation()->getAddress2();

    if ($addr2) {
      $pairs{'card-address'} = $addr1 . ' ' . $addr2;
    } else {
      $pairs{'card-address'} = $addr1;
    }

    $pairs{'card-address1'} = $addr1;
    $pairs{'card-address2'} = $addr2;

    $pairs{'card-city'} =     $transactionObject->getBillingInformation()->getCity();
    $pairs{'card-state'} =    $transactionObject->getBillingInformation()->getState();
    $pairs{'card-zip'} =      $transactionObject->getBillingInformation()->getPostalCode();
    $pairs{'card-country'} =  $transactionObject->getBillingInformation()->getCountry();
    $pairs{'phone'} =         $transactionObject->getBillingInformation()->getDayPhone();
    $pairs{'email'} =         $transactionObject->getBillingInformation()->getEmailAddress();
    $pairs{'fax'} =           $transactionObject->getBillingInformation()->getFax();
  }

  if (defined $transactionObject->getShippingInformation()) {
    $pairs{'address'} =      $transactionObject->getShippingInformation()->getAddress1() . ' ' . $transactionObject->getShippingInformation()->getAddress2();
    $pairs{'address1'} =     $transactionObject->getShippingInformation()->getAddress1();
    $pairs{'address2'} =     $transactionObject->getShippingInformation()->getAddress2();
    $pairs{'city'} =         $transactionObject->getShippingInformation()->getCity();
    $pairs{'state'} =        $transactionObject->getShippingInformation()->getState();
    $pairs{'zip'} =          $transactionObject->getShippingInformation()->getPostalCode();
    $pairs{'country'} =      $transactionObject->getShippingInformation()->getCountry();
    $pairs{'shipphone'} =    $transactionObject->getShippingInformation()->getDayPhone();
    $pairs{'shipemail'} =    $transactionObject->getShippingInformation()->getEmailAddress();
    $pairs{'shipfax'} =      $transactionObject->getShippingInformation()->getFax();
  }

  # put 3d Secure info into pairs
  $pairs{'cavv'} = $transactionObject->getCAVV();
  $pairs{'cavvalgorithm'} = $transactionObject->getCAVVAlgorithm();
  $pairs{'eci'} = $transactionObject->getECI();
  $pairs{'xid'} = $transactionObject->getXID();

  # put the purchase order number into the pairs
  $pairs{'ponumber'} = $transactionObject->getPurchaseOrderNumber();
  if (defined $transactionObject->getItemData() && ref($transactionObject->getItemData()) eq 'HASH') {
    foreach my $itemKey ( keys %{$transactionObject->getItemData()}) {
      $pairs{$itemKey} = $transactionObject->getItemData()->{$itemKey};
    }
  }

  #return data
  $pairs{'pnp_transaction_ref_id'} = _binIdToHexId($transactionObject->getPNPTransactionReferenceID()) if $transactionObject->getPNPTransactionReferenceID();
  $pairs{'origorderid'} = _binIdToHexId($transactionObject->getInitialOrderID()) if $transactionObject->getInitialOrderID();
  $pairs{'processor_token'} = $transactionObject->getProcessorToken() if $transactionObject->getProcessorToken();
  $pairs{'processor_reference_id'} = _binIdToHexId($transactionObject->getProcessorReferenceID()) if $transactionObject->getProcessorReferenceID();
  $pairs{'refnumber'} = $transactionObject->getProcessorReferenceID() if $transactionObject->getProcessorReferenceID();
  $pairs{'processor_data_details'} = $transactionObject->getProcessorDataDetails();
  if ($transactionObject->getAuthorizationCode()) {
    $pairs{'auth-code'} = $transactionObject->getAuthorizationCode();
  }

  if (defined $responseObject && ref($responseObject) eq 'PlugNPay::Transaction::Response') {
    $pairs{'avs-code'} = $responseObject->getAVSResponse();
    $pairs{'cvvresp'} = $responseObject->getSecurityCodeResponse();
    $pairs{'MErrMsg'} = $responseObject->getErrorMessage();
    $pairs{'FinalStatus'} = $responseObject->getStatus();
    $pairs{'result'} = $responseObject->getStatus();
    $pairs{'auth-code'} = $responseObject->getAuthorizationCode();
  } elsif (defined $responseObject && ref($responseObject) eq 'HASH') {
    $pairs{'avs-code'} = $responseObject->{'avs_response'};
    $pairs{'cvvresp'} = $responseObject->{'cvv_response'};
    $pairs{'MErrMsg'} = $responseObject->{'error_message'};
    $pairs{'FinalStatus'} = $responseObject->{'status'};
    $pairs{'result'} = $responseObject->{'result'} || $responseObject->{'status'};
    $pairs{'auth-code'} = $responseObject->{'authorization_code'};
  } elsif ($transactionObject->getAuthorizationCode()) {
    $pairs{'auth-code'} = $transactionObject->getAuthorizationCode();
  }

  $pairs{'publisher-email'} = $transactionObject->getReceiptSendingEmailAddress();

  # get and use 'defaultValues'
  my $defaultValues = new PlugNPay::Transaction::DefaultValues();
  my $pairs = $defaultValues->setLegacyDefaultValues($gatewayAccount, \%pairs);

  # create a copy of pairs for logging, must be a copy to prevent an infinite refernce loop
  my %fullTransactionData = %{$pairs};
  $pairs->{'__full_transaction_data__'} = \%fullTransactionData;

  # needed for conditional logic based on transaction origination, such as checking returns vs credits
  $pairs->{'__from_transaction_object__'} = 1;
  return $pairs;
}

sub _binIdToHexId {
  my $possiblyBin = shift;
  return PlugNPay::Util::UniqueID::fromBinaryToHex($possiblyBin);
}

sub mapOutput {
  my $self = shift;
  my $transactionObject = shift;
  my $gatewayAccount = shift;

  my $mapped = $self->map($transactionObject,$gatewayAccount);

  # masked payment value does not map using MapLegacy
  my $paymentObj = $transactionObject->getPayment();
  my $maskedNumber = $paymentObj->getMaskedNumber();
  $mapped->{'card-number'} = $maskedNumber;

  #delete internal keys (keys starting with underscore)
  foreach my $key (keys %{$mapped}) {
    if ($key =~ /^_/) {
      delete $mapped->{$key};
    }
  }

  # ich bin ein outlier, this does not belong here.
  delete $mapped->{'processor_data_details'};

  return $mapped;
}

sub mapRemote {
  my $self = shift;
  my $transactionObject = shift;
  my $responseObject = shift;
  my $currency = lc $transactionObject->getCurrency() || lc new PlugNPay::GatewayAccount($transactionObject->getGatewayAccount())->getDefaultCurrency();
  my $amount = $transactionObject->getTransactionAmount();

  my $timeObject = new PlugNPay::Sys::Time();

  my %pairs = ();

  # do customData first so that if there's any reserved parameters, they are overwritten
  my $customData = $transactionObject->getCustomData();
  my $customCount = 1;
  foreach my $key (keys %{$customData}) {
    $pairs{'customname' . $customCount} = $key;
    $pairs{'customvalue' . $customCount} = $customData->{$key};
    $pairs{$key} = $customData->{$key};
    $customCount++;
  }

  $pairs{'amountcharged'} = $amount;
  $pairs{'card-amount'} = $amount;
  $pairs{'adjustment'} = $transactionObject->getTransactionAmountAdjustment();
  $pairs{'baseAmount'} = $transactionObject->getBaseTransactionAmount();
  $pairs{'currency'} = $currency;
  my ($transState,$statusCode) = split('_',lc $transactionObject->getTransactionState());
  if ($transactionObject->doForceAuth() && $transState eq 'auth') {
    $pairs{'operation'} = 'forceauth';
  } else {
    $pairs{'operation'} = $transState;
  }

  if ($transactionObject->doPostAuth() && $transactionObject->getTransactionType() =~ /^auth/i) {
    $pairs{'authtype'} = 'authpostauth';
  }


  $pairs{'orderID'} = $transactionObject->getOrderID();
  $pairs{'refnumber'} = $transactionObject->getProcessorReferenceID();

  my $contact = $transactionObject->getBillingInformation();
  $pairs{'full-name'} = $contact->getFullName();
  $pairs{'card-address1'} = $contact->getAddress1();
  $pairs{'card-address2'} = $contact->getAddress2();
  $pairs{'card-city'} = $contact->getCity();
  $pairs{'card-state'} = $contact->getState();
  $pairs{'card-country'} = $contact->getCountry();
  $pairs{'card-zip'} = $contact->getPostalCode();
  $pairs{'email'} = $contact->getEmailAddress();
  $pairs{'origorderid'} = $transactionObject->getInitialOrderID() if $transactionObject->getInitialOrderID();
  $pairs{'ponumber'} = $transactionObject->getPurchaseOrderNumber() if $transactionObject->getPurchaseOrderNumber();
  $pairs{'trans_time'} = $timeObject->inFormatDetectType('gendatetime',$transactionObject->getTransactionDateTime());
  $pairs{'trans_date'} = $timeObject->inFormatDetectType('yyyymmdd',$transactionObject->getTransactionDateTime());

  # put the card info into pairs
  if ($transactionObject->getTransactionPaymentType() eq 'credit' && defined $transactionObject->getCreditCard()) {
    $pairs{'card-number'} =  $transactionObject->getCreditCard()->getMaskedNumber();
    $pairs{'card-exp'} =     sprintf('%02d/%02d',$transactionObject->getCreditCard()->getExpirationMonth(),$transactionObject->getCreditCard()->getExpirationYear());
    $pairs{'card-name'} =    $transactionObject->getCreditCard()->getName();
    $pairs{'card_type'} =    $transactionObject->getCreditCard()->getType();
    $pairs{'accttype'} = 'credit';
  } elsif ($transactionObject->getTransactionPaymentType() eq 'ach' && defined $transactionObject->getOnlineCheck()) {
    $pairs{'card-name'} =  $transactionObject->getOnlineCheck()->getName();
    $pairs{'routingnum'} = $transactionObject->getOnlineCheck()->getRoutingNumber();
    $pairs{'accountnum'} = $transactionObject->getOnlineCheck()->getAccountNumber();
    $pairs{'card-number'} = $transactionObject->getOnlineCheck()->getMaskedNumber();
    $pairs{'accttype'} = 'checking';
    $pairs{'checktype'} = $transactionObject->getSECCode();
    my $secCodeChecker = new PlugNPay::SECCode();
    if ($secCodeChecker->isCommercial($transactionObject->getSECCode())) {
      $pairs{'commcardtype'} = 'purchase'; # why an ach transaction uses "commcardtype" i will never understand.
    }
  }

  # put the account codes into the pairs
  $pairs{'acct_code'}  = $transactionObject->getAccountCode(1);
  $pairs{'acct_code2'} = $transactionObject->getAccountCode(2);
  $pairs{'acct_code3'} = $transactionObject->getAccountCode(3);
  $pairs{'acct_code4'} = $transactionObject->getAccountCode(4);

  my $extraData = $transactionObject->getExtraTransactionData();
  if (ref($extraData) eq 'HASH' && (keys %{$extraData}) > 0 ) {
    $pairs{'batch_time'} = $extraData->{'batch_time'};
    $pairs{'batch_number'} = $extraData->{'batch_number'};
    $pairs{'extra_data'} = map{ $_ . '=' . $extraData->{$_} } keys %{$extraData};
  }

  my $processorDetails = $transactionObject->getProcessorDataDetails();
  if (ref($processorDetails) eq 'HASH' && (keys %{$processorDetails}) > 0) {
    my $dataArray = [];
    foreach my $state (keys %{$processorDetails}) {
      my $details = map{ $_ . '=' . $processorDetails->{$state}{$_} } keys %{$processorDetails->{$state}};
      push @{$dataArray},$state . '=' . $details;
    }
    $pairs{'processor_data_details'} = join('&',@{$dataArray});
    if (!defined $pairs{'refnumber'}) {
      my $stateMachine = new PlugNPay::Transaction::State();
      $processorDetails->{$stateMachine->getTransactionStateID($transactionObject->getTransactionState())}{'processor_reference_id'};
    }
  }

  if (defined $responseObject && ref($responseObject) eq 'PlugNPay::Transaction::Response') {
    $pairs{'avs-code'} = $responseObject->getAVSResponse();
    $pairs{'cvvresp'} = $responseObject->getSecurityCodeResponse();
    $pairs{'MErrMsg'} = $responseObject->getErrorMessage();
    $pairs{'FinalStatus'} = $responseObject->getStatus();
    $pairs{'result'} = $responseObject->getStatus();
    $pairs{'auth-code'} = $responseObject->getAuthorizationCode();
  } elsif (defined $responseObject && ref($responseObject) eq 'HASH') {
    $pairs{'avs-code'} = $responseObject->{'avs_response'};
    $pairs{'cvvresp'} = $responseObject->{'cvv_response'};
    $pairs{'MErrMsg'} = $responseObject->{'error_message'};
    $pairs{'FinalStatus'} = $responseObject->{'status'};
    $pairs{'result'} = $responseObject->{'result'} || $responseObject->{'status'};
    $pairs{'auth-code'} = $responseObject->{'authorization_code'};
  } elsif ($transactionObject->getAuthorizationCode()) {
    $pairs{'auth-code'} = $transactionObject->getAuthorizationCode();
  }

  $pairs{'processMode'} = ($transactionObject->isAsynchronous() ? 'async' : 'sync');
  # put transflags into the pairs
  $pairs{'transflags'} = join(',', $transactionObject->getTransFlags());

  $pairs{'status'} = $statusCode || 'success';

  # create a copy of pairs for logging, must be a copy to prevent an infinite refernce loop
  my %fullTransactionData = %pairs;
  $pairs{'__full_transaction_data__'} = \%fullTransactionData;

  return \%pairs;
}

sub mapToObject {
  my $self = shift;
  my $input = shift;
  if (ref($input) ne 'HASH') {
    die ('no data sent to map');
  }

  # parse input
  my $transData = $input->{'data'};
  my $gatewayAccount = $input->{'gatewayAccount'} || $transData->{'username'} || $transData->{'publisher-name'};
  my $operation = $input->{'operation'} || $transData->{'operation'};
  my $responseData = $input->{'responseData'} || {};

  # set payment type
  my $paymentType = $transData->{'paymethod'} || $transData->{'paymenttype'} || $input->{'paymentType'};
  my $isACH = inArray($transData->{'accttype'}, ['checking','savings']) || inArray($paymentType, ['checking','savings','ach']);
  if ($isACH) {
    $paymentType = 'ach';
  } elsif ($paymentType eq 'emv') {
    $paymentType = 'emv';
  } elsif ($paymentType eq 'gift' || $paymentType eq 'prepaid') {
    $paymentType = 'gift';
  } else {
    $paymentType = 'card';
  }
  
  # create trans
  my $transactionObj = new PlugNPay::Transaction($operation, $paymentType);
  $transactionObj->setTransactionPaymentType($paymentType);
  $transactionObj->setGatewayAccount($gatewayAccount);
  
  # set proc info
  my $processor = $input->{'processor'};
  if (!$processor) {
    $processor = $self->getProcessor($gatewayAccount, $paymentType);
  }
  my $processorId = new PlugNPay::Processor::ID()->getProcessorID($processor);
  $transactionObj->setProcessorID($processorId);
  $transactionObj->setProcessor($processor);

  my %completeData = (%{$transData},%{$responseData});
  my $responseObj = new PlugNPay::Transaction::Response(\%completeData);

  # Payment
  my $token;
  if (inArray($transData->{'accttype'},['savings','checking'])) {
    my $ach = new PlugNPay::OnlineCheck();
    if ($transData->{'card-number'} || ($transData->{'routingnum'} && $transData->{'accountnum'})) {
      my ($routing, $account) = split(' ', $transData->{'card-number'});
      if (!$routing && $transData->{'routingnum'}) {
        $routing = $transData->{'routingnum'};
      }

      if (!$account && $transData->{'accountnum'}) {
        $account = $transData->{'accountnum'};
      }

      $ach->setRoutingNumber($routing);
      $ach->setAccountNumber($account);
      $ach->setAccountType($transData->{'accttype'});
    } elsif ($transData->{'enccardnumber'}) {
      $ach->setAccountFromEncryptedNumber($transData->{'enccardnumber'});
    } elsif ($transData->{'token'}) {
      $ach->fromToken($transData->{'token'});
    }
    $ach->setName($transData->{'card-name'});
    $ach->setSECCode($transData->{'checktype'});
    $token = $ach->getToken();
    $transactionObj->setOnlineCheck($ach);
  } else {
    my $card = new PlugNPay::CreditCard();
    if ($transData->{'magstripe'}) {
      $card->setMagstripe($transData->{'magstripe'});
    } elsif ($transData->{'card-number'}) {
      $card->setNumber($transData->{'card-number'});
    } elsif ($transData->{'enccardnumber'}) {
      $card->setNumberFromEncryptedNumber($transData->{'enccardnumber'});
    } elsif ($transData->{'token'}) {
      $card->fromToken($transData->{'token'});
    }

    my ($month,$year) = split('/',$transData->{'card-exp'});
    $card->setExpirationMonth($month);
    $card->setExpirationYear($year);
    $card->setSecurityCode($transData->{'card-cvv'});
    $card->setName($transData->{'card-name'});
    $token = $card->getToken();
    $transactionObj->setCreditCard($card);
  }
  $transactionObj->setPNPToken($token);

  # Identifiers
  my $transactionId = $transData->{'pnp_transaction_id'} || $transData->{'orderID'} || $transData->{'orderid'};
  $transactionObj->setMerchantTransactionID($transData->{'orderID'} || $transData->{'orderid'});
  $transactionObj->setMerchantClassifierID($transData->{'order-id'});
  $transactionObj->setTransactionDateTime($transData->{'trans_time'});
  $transactionObj->setIPAddress($transData->{'ipaddress'});
  $transactionObj->setPNPTransactionID($transactionId);

  #State and Status
  my $status = $transData->{'status'} || $transData->{'FinalStatus'} || $responseData->{'FinalStatus'} || 'pending';
  my $transactionState = new PlugNPay::Transaction::State()->translateLegacyOperation($operation,$status);
  $transactionObj->setTransactionState($transactionState);

  my $authCode = $transData->{'auth-code'} || $responseData->{'auth-code'};
  $transactionObj->setAuthorizationCode($authCode); 

  # Amounts
  if ($transData->{'amount'} =~ /[a-zA-Z]{3} \d+\.?\d*/) {
    my ($currency, $amount) = split(' ',$transData->{'amount'});
    $transactionObj->setTransactionAmount($amount);
    $transactionObj->setCurrency($currency);
  } else {
    $transactionObj->setTransactionAmount($transData->{'amount'});
  }
  $transactionObj->setBaseTransactionAmount($transData->{'baseAmount'});
  $transactionObj->setTaxAmount($transData->{'tax'});

  my $adjustmentAmount = $transData->{'adjustment'} ||  $transData->{'surcharge'};
  $transactionObj->setTransactionAmountAdjustment($adjustmentAmount) if $adjustmentAmount;

  # Contact Information
  my $bill = new PlugNPay::Contact();
  $bill->setFullName($transData->{'card-name'});
  $bill->setAddress1($transData->{'card-address'});
  $bill->setAddress2($transData->{'card-address2'});
  $bill->setCity($transData->{'card-city'});
  $bill->setState($transData->{'card-state'});
  $bill->setCountry($transData->{'card-country'});
  $bill->setPostalCode($transData->{'card-zip'});
  $bill->setEmailAddress($transData->{'email'});
  $bill->setPhone($transData->{'phone'});
  $transactionObj->setBillingInformation($bill);

  my $ship = new PlugNPay::Contact();
  $ship->setFullName($transData->{'name'});
  $ship->setAddress1($transData->{'address'});
  $ship->setAddress2($transData->{'address2'});
  $ship->setCity($transData->{'city'});
  $ship->setState($transData->{'state'});
  $ship->setCountry($transData->{'country'});
  $ship->setPostalCode($transData->{'zip'});
  $ship->setEmailAddress($transData->{'shipemail'});
  $ship->setPhone($transData->{'shipphone'});
  $transactionObj->setShippingInformation($ship);
  $transactionObj->setShippingNotes($transData->{'notes'});
  $transactionObj->setShippingAmount($transData->{'shipamount'}) if defined $transData->{'shipamount'};

  #Account Code Fun
  $transactionObj->setAccountCode(1,$transData->{'acct_code'});
  $transactionObj->setAccountCode(2,$transData->{'acct_code2'});
  $transactionObj->setAccountCode(3,$transData->{'acct_code3'});
  $transactionObj->setAccountCode(4,$transData->{'acct_code4'});
 
  #extraData
  my $extraData = {}; #$transactionObject->getExtraTransactionData();
  $extraData->{'batch_time'} =  $transData->{'batch_time'};
  $extraData = $transData->{'batch_number'};
  $transactionObj->setExtraTransactionData($extraData);

  #ref nums
  $transactionObj->setProcessorReferenceID($transData->{'refnumber'});
  $transactionObj->setInitialOrderID($transData->{'origorderid'});
  $transactionObj->setPNPTransactionReferenceID($transData->{'pnp_transaction_ref_id'}) if $transData->{'pnp_transaction_ref_id'};
  $transactionObj->setProcessorToken($transData->{'processor_token'}) if $transData->{'processor_token'};
  if ($transData->{'processor_data_details'}) {
    $transactionObj->setProcessorDataDetails($transData->{'processor_data_details'});
  } elsif ($transData->{'refnumber'}) {
    $transactionObj->setProcessorDataDetails({'processor_reference_id' => $transData->{'refnumber'}});
  }

  #Custom and Items
  my $customData = {};
  my $itemizationData = {};
  $transactionObj->setPurchaseOrderNumber($transData->{'ponumber'});
  foreach my $key (keys %{$transData}) {
    if ($key =~ /^(customname|customvalue)/i) {
      $customData->{$key} = $transData->{$key};
    } elsif ($key =~ /^item/i) {
      $itemizationData->{$key} = $transData->{$key};
    }
  }
  $transactionObj->setItemData($itemizationData);
  $transactionObj->setCustomData($customData);

  # 3DSecure
  $transactionObj->setCAVV($transData->{'cavv'});
  $transactionObj->setXID($transData->{'xid'});
  $transactionObj->setECI($transData->{'eci'});
  $transactionObj->setPaResponse($transData->{'paresponse'});
  $transactionObj->setCAVVAlgorithm($transData->{'cavvalgorithm'});
  $transactionObj->setResponse($responseObj);

  #publisheremail
  $transactionObj->setReceiptSendingEmailAddress($transData->{'publisheremail'});

  # Trans Flags
  foreach my $flag (split(',',$transData->{'transflags'})) {
    $transactionObj->addTransFlag($flag);
  }

  return $transactionObj;
}

sub getProcessor {
  my $self = shift;
  my $gatewayAccountName = shift;
  my $paymentType = shift || 'card';

  my $gatewayAccount = new PlugNPay::GatewayAccount($gatewayAccountName);
  my $processor = $gatewayAccount->getCardProcessor();
  if ($paymentType eq 'ach') {
    $processor = $gatewayAccount->getCheckProcessor();
  } elsif ($paymentType eq 'tds') {
    $processor = $gatewayAccount->getTDSProcessor();
  } elsif ($paymentType eq 'wallet') {
    $processor = $gatewayAccount->getWalletProcessor();
  } elsif ($paymentType eq 'emv') {
    $processor = $gatewayAccount->getEMVProcessor();
  }

  return $processor;
}
    
1;
