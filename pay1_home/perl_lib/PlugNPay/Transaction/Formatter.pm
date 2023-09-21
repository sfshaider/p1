package PlugNPay::Transaction::Formatter;

use strict;
use PlugNPay::Token;
use PlugNPay::Contact;
use PlugNPay::Country;
use PlugNPay::Currency;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::Transaction;
use PlugNPay::Processor::ID;
use PlugNPay::GatewayAccount;
use PlugNPay::Util::UniqueID;
use PlugNPay::Transaction::Type;
use PlugNPay::Transaction::State;
use PlugNPay::Transaction::Loader;
use PlugNPay::Processor::SeqNumber;
use PlugNPay::Transaction::Vehicle;
use PlugNPay::Transaction::Updater;
use PlugNPay::Transaction::Response;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Processor::Settings::SECCodes;
use PlugNPay::Sys::Time;
use PlugNPay::Processor::Account;
use PlugNPay::Transaction::TransId;

############### Formatter ##################
# This turns the Transacion Object into a  #
# hash to allow a conversion to JSON data  #
# which is then sent to the processor.     #
#                                          #
# Only used for new transaction processing #
############################################

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $transactionObj = shift;

  if (defined $transactionObj && ref($transactionObj) =~ /^PlugNPay::Transaction/) {
    $self->setTransactionData($transactionObj);
  }

  return $self;
}

sub setTransactionData {
  my $self = shift;
  my $transaction = shift;
  $self->{'transaction'} = $transaction;
}

sub getTransactionData {
  my $self = shift;
  return $self->{'transaction'};
}

# Transaction formatting #
sub prepareTransaction {
  my $self = shift;
  my $transaction = shift;
  my $operation = shift;
  my $username = $transaction->getGatewayAccount();
  my $gatewayAccount = new PlugNPay::GatewayAccount($transaction->getGatewayAccount());
  my $stateObj = new PlugNPay::Transaction::State();
  my $typeObj = new PlugNPay::Transaction::Type();
  my $vehicleObj = new PlugNPay::Transaction::Vehicle();
  my $internalID = new PlugNPay::GatewayAccount::InternalID();
  my $procIDObj = new PlugNPay::Processor::ID();
  if (!defined $transaction || ref($transaction) !~ /^PlugNPay::Transaction/) {
    $transaction = $self->getTransactionData();
  }
  # Retrieve information from transaction #
  my $data = {};
  my $stateMachine = new PlugNPay::Transaction::State();
  my $states = $stateMachine->getStates();
  my $contact = $transaction->getBillingInformation();
  my $payType = $transaction->getTransactionPaymentType();
  my $merchantContact = $gatewayAccount->getMainContact();
  my $sensitiveData = {};
  if (!defined $payType) {
    if (ref($transaction) =~ /^PlugNPay::Transaction::Authorization::Credit/ || ref($transaction) =~ /^PlugNPay::Transaction::Credit::Credit/) {
      $payType = 'credit';
    } elsif (ref($transaction) =~ /^PlugNPay::Transaction::Authorization::OnlineCheck/ || ref($transaction) =~ /^PlugNPay::Transaction::Credit::OnlineCheck/ ) {
      $payType = 'ach';
    } elsif (ref($transaction) =~ /^PlugNPay::Transaction::Authorization::PrePaid/ || ref($transaction) =~ /^PlugNPay::Transaction::Credit::PrePaid/) {
      $payType = 'gift';
    } elsif (ref($transaction) =~ /^PlugNPay::Transaction::Authorization::EMV/ || ref($transaction) =~ /^PlugNPay::Transaction::Credit::EMV/) {
      $payType = 'emv';
    }
  }
  # Payment Information #
  my $token;
  my $merchantData = $transaction->getCustomData();
  $merchantData->{'merchant_name'} = $merchantContact->getFullName();
  $merchantData->{'merchant_company'} = $merchantContact->getCompany();
  $merchantData->{'merchant_address'} = $merchantContact->getAddress1();
  $merchantData->{'merchant_city'} = $merchantContact->getCity();
  $merchantData->{'merchant_state'} = $merchantContact->getState();
  $merchantData->{'merchant_postal_code'} = $merchantContact->getPostalCode();
  $merchantData->{'merchant_country'} = $merchantContact->getCountry();
  $merchantData->{'processor_settings'} = new PlugNPay::Processor::Account({'processorName' => $transaction->getProcessor(), 'gatewayAccount' => $transaction->getGatewayAccount()})->getSettings();
  $data->{'mid'} = $merchantData->{'processor_settings'}{'mid'};
  $data->{'tid'} = $merchantData->{'processor_settings'}{'tid'};

  my $customData = $transaction->getCustomData() || {};
  foreach my $key (keys %{$customData}) {
    $merchantData->{$key} = $customData->{$key};
  }

  $merchantData->{'merchant_type'} = $merchantData->{'processor_settings'}{'authType'};
  my $processorData = $transaction->getProcessorDataDetails();

  if ($payType eq 'credit' || $payType eq 'gift' || $payType eq 'card' || $payType eq 'emv') { #Card
    my $card = $transaction->getPayment();
    my $vehicleName = ($payType eq 'credit' ? 'card' : lc($payType));
    $data->{'transaction_vehicle_name'} = $vehicleName;
    $data->{'transaction_vehicle_id'} = $vehicleObj->getTransactionVehicleID($vehicleName);
    $data->{'processor_id'} = $procIDObj->getProcessorID($transaction->getProcessor());
    $data->{'processor'} = $transaction->getProcessor();
    $data->{'unique_id'} = new PlugNPay::Processor::SeqNumber($transaction->getProcessor())->generate($username);

    #EMV doesn't have card data.
    if($payType ne 'emv') {
      $sensitiveData->{'card_brand'} = ucfirst($card->getBrandName());
      $sensitiveData->{'card_type'} = $card->getType();
      if ($card->getMagstripe()) {
        $sensitiveData->{'magstripe'} = $card->getMagstripe();
      } else {
        $data->{'card_first_six'} = substr($card->getNumber(), 0, 6);
        $data->{'card_last_four'} = substr($card->getNumber(), -4, 4);
        $data->{'card_brand'} = uc($card->getBrandName());
        $data->{'card_category'} = $card->getCategory();
        $data->{'card_type'} = $card->getType();
        $sensitiveData->{'cvv'} = $card->getSecurityCode();
        $sensitiveData->{'card_expiration'} = $card->getExpirationMonth() . substr($card->getExpirationYear(), -2, 2);
        $sensitiveData->{'exp_month'} = $card->getExpirationMonth();
        $sensitiveData->{'exp_year'} = substr($card->getExpirationYear(), -2, 2);
        $token = $card->getToken();
        $data->{'full_name'} = $card->getName();
        $sensitiveData->{'magstripe'} = undef;
      }
    }

  } elsif ($payType  eq 'ach') {  #Check
    my $ach = $transaction->getOnlineCheck();
    $data->{'transaction_vehicle_id'} = $vehicleObj->getTransactionVehicleID('ach');
    $data->{'transaction_vehicle_name'} = 'ach';
    $data->{'processor_id'} = $procIDObj->getProcessorID($gatewayAccount->getCheckProcessor());
    $data->{'processor'} = $gatewayAccount->getCheckProcessor();
    $data->{'unique_id'} = new PlugNPay::Processor::SeqNumber($gatewayAccount->getCheckProcessor())->generate($username);
    $token = $ach->getToken();
    $sensitiveData->{'routing_number'} = $ach->getRoutingNumber();
    $sensitiveData->{'account_number'} = $ach->getAccountNumber();
    $data->{'full_name'} = $ach->getName() || $contact->getFullName();
    $sensitiveData->{'account_type'} = $ach->getAccountType();
    $sensitiveData->{'sec_code'} = $transaction->getSECCode();
    my $SECCodeObj = new PlugNPay::Processor::Settings::SECCodes();
    $SECCodeObj->setGatewayAccount($transaction->getGatewayAccount());
    my $tidOverride = $SECCodeObj->loadUnifiedTIDOverride($transaction->getSECCode());
    if ($tidOverride) {
      $data->{'merchant_tid'} = $data->{'tid'};
      $data->{'tid'} = $tidOverride;
    }
  }

  my $tokenObj = new PlugNPay::Token();
  if ($token =~ /^[a-fA-F0-9]+$/) {
    $tokenObj->fromHex($token);
  } else {
    $tokenObj->fromBinary($token);
  }
  $data->{'pnp_token'} = $tokenObj->inHex();

  # Account Information #
  $data->{'merchant_id'} = $internalID->getMerchantID($username);
  $data->{'operator_id'} = $transaction->getGatewayAccount();
  my $idFormatter = new PlugNPay::Util::UniqueID();

  my $pnpTransactionID = (defined $transaction->getPNPTransactionID() && $transaction->verifyTransactionID($transaction->getPNPTransactionID()) ? $transaction->getPNPTransactionID() : $transaction->generateTransactionID());
  $idFormatter->fromBinary($pnpTransactionID);
  $data->{'pnp_transaction_id'} = $idFormatter->inHex();

  my $pnpOrderID = $transaction->getPNPOrderID();
  if (!defined $pnpOrderID || $pnpOrderID eq '') {
    die('Transaction attempted to be processed without an order id');
  }
  $idFormatter->fromBinary($pnpOrderID);
  $data->{'pnp_order_id'} = $idFormatter->inHex(); #pnpOrderID;#=

  $data->{'merchant_order_id'} = $transaction->getMerchantTransactionID();

  my $loader = new PlugNPay::Transaction::Loader({'loadPaymentData' => 1});
  $data->{'previous_transaction_state'} = $loader->getPreviousTransactionState($transaction->getPNPTransactionReferenceID(),$data->{'transaction_vehicle_id'});

  my $startingOp;
  if (ref($transaction) =~ /^PlugNPay::Transaction::Authorization::PrePaid/) {
    $startingOp = $stateObj->getStateIDFromOperation($transaction->getGiftOp());
  } elsif ( ref($transaction) =~ /^PlugNPay::Transaction::Credit::PrePaid/ && $transaction->getGiftOp() =~ /^void/) {
    $startingOp = $stateObj->getStateIDFromOperation('void');
    $data->{'previous_transaction_state'} = $self->getGiftPreviousState($operation); #Overrides for gift
  } else {
    if(!defined $operation) {
      $operation = $self->getOperationFromPackage(ref($transaction));
    }
    $startingOp = $stateObj->getStateIDFromOperation($operation);
  }


  $data->{'transaction_state_name'} = $stateObj->getTransactionStateName($startingOp);
  $data->{'transaction_state_id'} = $startingOp;
  $data->{'transaction_amount'} = $transaction->getTransactionAmount();
  $data->{'base_transaction_amount'} = $transaction->getBaseTransactionAmount();
  $merchantData->{'merchant_classification_id'} = $transaction->getMerchantClassifierID();
  $data->{'ip_address'} = $transaction->getIPAddress();
  $data->{'transaction_type_id'} = $typeObj->getTransactionTypeID($transaction->getTransactionType());
  $data->{'username'} = $username;
  $data->{'transaction_currency'} = $transaction->getCurrency();
  my $currencyObj = new PlugNPay::Currency();
  $currencyObj->setCurrencyCode($transaction->getCurrency());
  $data->{'currency_code'} = $currencyObj->getCurrencyNumber();
  $data->{'transaction_date_time'} = $transaction->getTransactionDateTime();
  # Contact information #
  $data->{'full_name'} = $contact->getFullName() if !$data->{'full_name'};
  $data->{'address'} = $contact->getAddress1();
  $data->{'address2'} = $contact->getAddress2();
  $data->{'city'} = $contact->getCity();
  $data->{'state'} = $contact->getState();
  $data->{'postal_code'} = $contact->getPostalCode();
  $data->{'country'} = $contact->getCountry();
  $data->{'country_code'} = new PlugNPay::Country($contact->getCountry())->getNumeric();
  $data->{'phone'} = $contact->getPhone();
  $data->{'fax'} = $contact->getFax();
  $data->{'email'} = $contact->getEmailAddress();
  $data->{'company'} = $contact->getCompany();
  $data->{'transaction_tax_amount'} = $transaction->getTaxAmount();
  $data->{'base_transaction_tax_amount'} = $transaction->getBaseTaxAmount();

  # Shipping information #
  my $shipContact = $transaction->getShippingInformation();
  $data->{'shipping_full_name'} = $shipContact->getFullName();
  $data->{'shipping_address'} = $shipContact->getAddress1();
  $data->{'shipping_address2'} = $shipContact->getAddress2();
  $data->{'shipping_city'} = $shipContact->getCity();
  $data->{'shipping_state'} = $shipContact->getState();
  $data->{'shipping_postal_code'} = $shipContact->getPostalCode();
  $data->{'shipping_country'} = $shipContact->getCountry();
  $data->{'shipping_country_code'} = new PlugNPay::Country($shipContact->getCountry())->getNumeric();
  $data->{'shipping_phone'} = $shipContact->getPhone();
  $data->{'notes'} = $transaction->getShippingNotes();
  $data->{'shipping_email'} = $shipContact->getEmailAddress();
  $data->{'shipping_company'} = $shipContact->getCompany();
  $data->{'processor_token'} = $transaction->getProcessorToken();
  $data->{'authorization_code'} = $transaction->getAuthorizationCode();
  $idFormatter->fromBinary($transaction->getPNPTransactionReferenceID());
  $data->{'pnp_transaction_ref_id'} = $idFormatter->inHex();

  $data->{'extra_transaction_data'} = $transaction->getExtraTransactionData();
  foreach my $key (keys %{$transaction->getExtraTransactionData()} ) {
    $merchantData->{$key} = $transaction->getExtraTransactionData()->{$key};
  }

  $data->{'requestType'} = 'request';
  if (defined $processorData && ref($processorData) eq 'HASH') {
    $processorData->{'processor_reference_id'} = $transaction->getProcessorReferenceID();
  } else {
    if (!defined $processorData) {
      $processorData = {'processor_reference_id' => $transaction->getProcessorReferenceID()};
    } else {
      $processorData = {$data->{'transaction_state_id'} => $processorData, 'processor_reference_id' => $transaction->getProcessorReferenceID()};
    }
  }

  $data->{'processor_reference_id'} =  $transaction->getProcessorReferenceID();

  $merchantData->{'purchaseOrderNumber'} = $transaction->getPurchaseOrderNumber();
  my @transFlagArray = $transaction->getTransFlags();
  $merchantData->{'transFlags'} = \@transFlagArray;
  $merchantData->{'transFlagList'} = join(',',$transaction->getTransFlags());

  $data->{'trans_id'} = PlugNPay::Transaction::TransId::getTransIdV1({
    'username'  => $transaction->getGatewayAccount(),
    'orderId'   => $transaction->getMerchantTransactionID(),
    'processor' => $transaction->getProcessor()
  });

  return $self->stringifyElement({ 'transactionData' => $data,
           'sensitiveTransactionData' => $sensitiveData,
           'additionalProcessorData' => $processorData,
           'additionalMerchantData' => $merchantData,
           'requestID' => $data->{'pnp_transaction_id'},
           'priority' => $transaction->getProcessingPriority(),
           'type' => 'request',
           'processor' => $data->{'processor'}
         });
}

## Make Transaction Object from hash ##
sub makeTransactionObj {
  my $self = shift;
  my $data = shift;
  my $billingContact = new PlugNPay::Contact();
  my $stateObj = new PlugNPay::Transaction::State();
  my $typeObj = new PlugNPay::Transaction::Type();
  my $vehicleObj = new PlugNPay::Transaction::Vehicle();
  my $transactionObj = new PlugNPay::Transaction($stateObj->getTransactionStateName($data->{'transaction_state_id'}),$vehicleObj->getTransactionVehicleName($data->{'transaction_vehicle_id'}));

  $transactionObj->setGatewayAccount($data->{'username'} || $data->{'merchant'});
  $transactionObj->setPNPTransactionID($transactionObj->generateTransactionID());
  $transactionObj->setCurrency($data->{'transaction_currency'});
  $transactionObj->setTransactionAmount($data->{'transaction_amount'});
  $transactionObj->setBaseTransactionAmount($data->{'base_amount'});
  $transactionObj->setTaxAmount($data->{'tax_amount'});
  $transactionObj->setBaseTaxAmount($data->{'base_tax_amount'});
  $transactionObj->setMerchantClassifierID($data->{'merchant_classification_id'} || $data->{'order-id'});
  $transactionObj->setOrderID($data->{'merchant_order_id'} || $data->{'orderID'});
  $transactionObj->setPurchaseOrderNumber($data->{'purchase_order_number'});
  $transactionObj->setProcessorDataDetails($data->{'additional_processor_data'});
  foreach my $flag (split(',',$data->{'transFlags'})) {
    $transactionObj->addTransFlag($flag);
  }

  $billingContact->setFullName($data->{'full_name'} || $data->{'sensitive_data'}{'full_name'});
  $billingContact->setAddress1($data->{'address1'});
  $billingContact->setAddress2($data->{'address2'});
  $billingContact->setCity($data->{'city'});
  $billingContact->setState($data->{'state'});
  $billingContact->setCountry($data->{'country'});
  $billingContact->setCompany($data->{'company'});
  $billingContact->setPostalCode($data->{'postal_code'});
  $billingContact->setEmailAddress($data->{'email'});
  $billingContact->setPhone($data->{'phone'});
  $billingContact->setFax($data->{'fax'});
  $transactionObj->setBillingInformation($billingContact);
  if (defined $data->{'shipping'}) {
  my $shippingContact = new PlugNPay::Contact();
    $shippingContact->setFullName($data->{'shipping'}{'name'});
    $shippingContact->setAddress1($data->{'shipping'}{'address1'});
    $shippingContact->setAddress2($data->{'shipping'}{'address2'});
    $shippingContact->setCity($data->{'shipping'}{'city'});
    $shippingContact->setState($data->{'shipping'}{'state'});
    $shippingContact->setCountry($data->{'shipping'}{'country'});
    $shippingContact->setCompany($data->{'shipping'}{'company'});
    $shippingContact->setPostalCode($data->{'shipping'}{'postal_code'});
    $shippingContact->setEmailAddress($data->{'shipping'}{'email'});
    $shippingContact->setPhone($data->{'shipping'}{'phone'});
    $transactionObj->setShippingInformation($shippingContact);
  }

  my $payType = $vehicleObj->getTransactionVehicleName($data->{'transaction_vehicle_id'});
  my $tokenObj = new PlugNPay::Token();
  if ($payType eq 'card' || $payType eq 'gift' || $payType eq 'prepaid' || $payType eq 'credit' ) {
    my $card = new PlugNPay::CreditCard();
    if (defined $data->{'magstripe'}) {
      $card->setMagstripe($data->{'magstripe'});
    } else {
      my $number;
      if (defined $data->{'pnp_token'}) {
        if ($data->{'pnp_token'} !~ /^[a-fA-F0-9]+$/) {
          $tokenObj->fromBinary($data->{'pnp_token'});
          $number = $card->fromToken($tokenObj->inHex());
        } else {
          $card->fromToken($data->{'pnp_token'});
        }
      } else {
        $number = $card->{'card_number'};
      }
      my @exp = (defined $data->{'sensitive_data'}{'card_expiration'} ? split('/',$data->{'sensitive_data'}{'card_expiration'}) : ($data->{'card'}{'exp_yonth'},$data->{'card'}{'exp_year'}));

      $card->setNumber($number);
      $card->setSecurityCode($data->{'card'}{'cvv'});
      $card->setExpirationMonth($exp[0]);
      $card->setExpirationYear($exp[1]);
      $card->setName($data->{'card'}{'name'} || $billingContact->getFullName());
    }
    if ($payType eq 'gift' || $payType eq 'prepaid') {
      $transactionObj->setGiftCard($card);
    } else {
      $transactionObj->setCreditCard($card);
    }
  } elsif ($payType eq 'ach') {
    my $ach = new PlugNPay::OnlineCheck();
    my $routing;
    my $account;
    if (defined $data->{'pnp_token'}) {
      if ($data->{'pnp_token'} !~ /^[a-fA-F0-9]+$/) {
        $tokenObj->fromBinary($data->{'pnp_token'});
        ($routing,$account) = split(' ',$ach->fromToken($tokenObj->inHex()));
      } else {
        ($routing,$account) = split(' ',$ach->fromToken($data->{'pnp_token'}));
      }
    } else {
      $account = $data->{'accountnum'};
      $routing = $data->{'routingnum'};
    }
    $ach->setAccountNumber($account);
    if ($ach->verifyABARoutingNumber($routing)){
      $ach->setABARoutingNumber($routing);
    } else {
      $ach->setInternationalRoutingNumber($routing);
    }
    $ach->setName($data->{'full_name'} || $billingContact->getFullName());
    $transactionObj->setOnlineCheck($ach);
  }
  $transactionObj->setPNPToken($data->{'pnp_token'});
  $transactionObj->setAuthorizationCode($data->{'authorization_code'});
  $transactionObj->setProcessorReferenceID($data->{'processor_reference_id'});
  $transactionObj->setPNPTransactionReferenceID($data->{'pnp_transaction_ref_id'});
  $transactionObj->setProcessorToken($data->{'processor_token'});

  return $transactionObj;
}

# Level 3 data formatting #
sub prepareLevel3 {
  my $self = shift;
  my $details = shift;
  my @detailArray = ();
  foreach my $detail (@{$details}){
    my $name = $detail->getName();
    my $data = {};
    $data->{'name'} = $name;
    $data->{'description'} = $detail->getDescription();
    $data->{'quantity'} = $detail->getQuantity();
    $data->{'cost'} = $detail->getCost();
    $data->{'discount'} = $detail->getDiscount();
    $data->{'tax'} = $detail->getTax();
    $data->{'commodity_code'} = $detail->getCommodityCode();
    $data->{'custom_1'} = $detail->getCustom1();
    $data->{'custom_2'} = $detail->getCustom2();
    $data->{'unit_of_measure'} = $detail->getUnitOfMeasure();
    $data->{'is_taxable'} = $detail->isTaxable();
    push @detailArray,$data;
  }

  return $self->stringifyElement(\@detailArray);
}

sub getGiftPreviousState {
  my $self = shift;
  my $action = lc shift;
  my $states = new PlugNPay::Transaction::State()->getStates();

  if ($action eq 'voidissue') {
    return $states->{'ISSUE'};
  } elsif ($action eq 'voidreload') {
    return $states->{'RELOAD'};
  } elsif ($action eq 'voidreturn') {
    return $states->{'CREDIT'}
  } else {
    return $states->{'POSTAUTH'};
  }
}

sub formatForSettlement {
  my $self = shift;
  my $trans = shift;
  my $updater = new PlugNPay::Transaction::Updater();
  my $state = new PlugNPay::Transaction::State()->getStates()->{'POSTAUTH_PENDING'};
  $updater->prepareForTransactionAlter({'pnp_transaction_id' => $trans->{'pnp_transaction_id'},'state' => $state});
  $trans->{'transaction_state_id'} = $state;
  $trans->{'transaction_state'} = 'POSTAUTH_PENDING';

  return $self->formatLoadedTransaction($trans,$state);
}

sub formatForVoid {
  my $self = shift;
  my $trans = shift;
  my $updater = new PlugNPay::Transaction::Updater();
  my $state = new PlugNPay::Transaction::State()->getStates()->{'VOID_PENDING'};
  $updater->prepareForTransactionAlter({'pnp_transaction_id' => $trans->{'pnp_transaction_id'},'state' => $state}); #Should rename function
  my $previousState = $trans->{'transaction_state_id'};
  $trans->{'previous_transaction_state'} = $previousState;
  $trans->{'transaction_state_id'} = $state;
  $trans->{'transaction_state'} = 'VOID_PENDING';
  if (!defined $trans->{'settlement_amount'}) {
    my $settlementAmount = $updater->getAmountToSettle($trans->{'pnp_transaction_id'});
    $trans->{'settlement_amount'} = $settlementAmount;
  }

  return $self->formatLoadedTransaction($trans,$state);
}

sub formatLoadedTransaction {
  my $self = shift;
  my $trans = shift;
  my $state = shift;
  my $internalID = new PlugNPay::GatewayAccount::InternalID();
  my $username = $trans->{'username'} || $trans->{'merchant'};
  if (!defined $username) {
    $username = $internalID->getMerchantName($trans->{'merchant_id'});
  }
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $stateMachine = new PlugNPay::Transaction::State();
  my $sensitiveData = {};
  my $data = {};
  if (defined $trans->{'previous_transaction_state'}) {
    $data->{'previous_transaction_state'} = $trans->{'previous_transaction_state'};
  }
  $data->{'pnp_token'} = $trans->{'pnp_token'};
  $data->{'transaction_vehicle_name'} = ($trans->{'transaction_vehicle_id'} == 2 ? 'ach' : 'card');
  if ($data->{'transaction_vehicle_name'} ne 'ach') {
    $data->{'pnp_token'} = $trans->{'pnp_token'};
    $data->{'full_name'} = $trans->{'billing_information'}{'name'};
    $data->{'card_first_six'} = $trans->{'card_information'}{'card_first_six'};
    $data->{'card_last_four'} = $trans->{'card_information'}{'card_last_four'};
    $sensitiveData->{'card_expiration'} = $trans->{'card_information'}{'card_expiration'};
    my ($expMonth,$expYear) = split ('/',$trans->{'card_information'}{'card_expiration'});
    $sensitiveData->{'exp_month'} = $expMonth;
    $sensitiveData->{'exp_year'} = substr($expYear,-2,2);
    $data->{'avs_response'} = $trans->{'card_information'}{'avs_response'};
    $data->{'cvv_response'} = $trans->{'card_information'}{'cvv_response'};
  }
  $data->{'username'} = $username;
  my $procName = ($trans->{'processor'} ? $trans->{'processor'} : $gatewayAccount->getCardProcessor());
  my $procAccount = new PlugNPay::Processor::Account({
    'gatewayAccount' => $username,
    'processorName' => $procName
  });

  $data->{'mid'} = $procAccount->getSettingValue('mid');
  $data->{'tid'} = $procAccount->getSettingValue('tid');
  $data->{'processor_token'} = $trans->{'processor_token'};
  $data->{'transaction_vehicle_id'} = $trans->{'transaction_vehicle_id'};
  $data->{'processor_id'} = $trans->{'processor_id'};
  $data->{'processor'} = $trans->{'processor'};
  my $uniqueID = new PlugNPay::Processor::SeqNumber($procName)->generate($username);
  $data->{'unique_id'} = $uniqueID;
  $data->{'merchant_id'} = $trans->{'merchant_id'};

  my $processor = $gatewayAccount->getCardProcessor();
  my $processorAccount = new PlugNPay::Processor::Account({ gatewayAccount => "$gatewayAccount", processorName => $processor });
  my $merchantType = $processorAccount->getIndustry();
  $data->{'merchant_type'} = $merchantType;

  $data->{'operator_id'} = "PlugNPay";

  my $tokenObj = new PlugNPay::Token();
  my $token = $trans->{'pnp_token'};
  if ($token !~ /^[a-fA-F0-9]+$/) {
    $tokenObj->fromBinary($token);
  } else {
    $tokenObj->fromHex($token);
  }
  $data->{'pnp_token'} = $tokenObj->inHex();

  my $uuid = new PlugNPay::Util::UniqueID();
  $uuid->fromBinary($trans->{'pnp_transaction_id'});
  $data->{'pnp_transaction_ref_id'} = $uuid->inHex();
  $data->{'pnp_transaction_id'} = $uuid->inHex();

  $uuid->fromBinary($trans->{'pnp_order_id'});
  $data->{'pnp_order_id'} = $uuid->inHex();

  my $cardObj = new PlugNPay::CreditCard();
  $cardObj->fromToken($tokenObj->inHex());
  $data->{'authorization_code'} = $trans->{'authorization_code'};

  my $currency = $trans->{'currency'} || $trans->{'transaction_currency'};
  my $currencyObj = new PlugNPay::Currency();
  $currencyObj->setCurrencyCode($currency);

  $data->{'card_brand'} = $cardObj->getBrandName();
  $data->{'card_type'} = $cardObj->getType();
  $data->{'card_category'} = $cardObj->getCategory();
  $data->{'currency_code'} = $currencyObj->getNumeric();
  $data->{'transaction_state_id'} = $state;
  $data->{'transaction_amount'} =  sprintf("%.2f",$trans->{'transaction_amount'});
  $data->{'base_transaction_amount'} =  sprintf("%.2f",$trans->{'base_amount'});
  $data->{'transaction_currency'} = $currencyObj->getThreeLetter();
  $data->{'ip_address'} = $trans->{'ip_address'};
  $data->{'transaction_tax_amount'} = sprintf("%.2f",$trans->{'tax_amount'});
  $data->{'base_tax_amount'} = sprintf("%.2f",$trans->{'base_tax_amount'});
  $data->{'pnp_order_id'} = $trans->{'pnp_order_id'};
  $data->{'merchant_order_id'} = $trans->{'merchant_order_id'};
  $data->{'transaction_type_id'} = $trans->{'transaction_type_id'};
  for (my $i = 0; $i < 4; $i++ ) {
    $data->{'account_code' . $i} =  $trans->{'account_code' . $i};
  }

  my $loader = new PlugNPay::Transaction::Loader();
  my $additionalDetails = $loader->loadAdditionalProcessorDetails($uuid->inBinary()); #->{$trans->{'transaction_state_id'}};
  my @detailKeys = keys %{$additionalDetails};
  $data->{'processor_reference_id'} = $additionalDetails->{$trans->{'previous_transaction_state'}}{'processor_reference_id'} || $trans->{'processor_reference_id'};
  if (!defined $additionalDetails) {
    $additionalDetails = {};
  }

  $data->{'transaction_state_name'} = $trans->{'transaction_state'};
  $data->{'settlement_amount'} = sprintf("%.2f",$trans->{'settlement_amount'});
  $data->{'transaction_date_time'} = $trans->{'transaction_date_time'};

  return $self->stringifyElement( { 'transactionData' => $data,
           'sensitiveTransactionData' => $sensitiveData,
           'additionalProcessorData' => $additionalDetails->{$detailKeys[0]}, #Done to get specific transactions
           'additionalMerchantData' => {'processor_settings' => new PlugNPay::Processor::Account({'gatewayAccount' => $username, 'processorName' => $procName})->getSettings()},
           'requestID' => $data->{'pnp_transaction_id'},
           'type' => 'request',
           'processor' => $data->{'processor'},
           'priority' => '6'
         });

}

sub formatLoadedAsResponse {
  my $self = shift;
  my $transaction = shift;
  my $formatted = {};
  my $transState = $transaction->{'transaction_state_id'};
  my $time = new PlugNPay::Sys::Time();
  $formatted->{'processor_message'} = $transaction->{'processor_message'};
  $formatted->{'authorization_code'} = $transaction->{'authorization_code'};
  $formatted->{'processor_status'} = $transaction->{'status'};
  $formatted->{'transaction_status'} = ($transaction->{'transaction_state'} =~ /_PENDING$/ ? 'pending' : 'complete');
  eval {
    $formatted->{'processor_reference_id'} = $transaction->{'processor_reference_id'} || $transaction->{'additional_processor_details'}{$transState}{'processor_reference_id'};
  };
  $formatted->{'transaction_amount'} = $transaction->{'transaction_amount'};
  $formatted->{'processor_transaction_amount'} = $transaction->{'transaction_amount'};
  $formatted->{'processor_token'} = $transaction->{'processor_token'};
  $formatted->{'avs_response'} = $transaction->{'avs_response'};
  $formatted->{'cvv_response'} = $transaction->{'cvv_response'};
  $formatted->{'merchant_order_id'} = $transaction->{'merchant_order_id'};
  my $uuid = new PlugNPay::Util::UniqueID();
  if ($transaction->{'pnp_transaction_id'} !~ /^[a-fA-F0-9]+$/) {
    $uuid->fromBinary($transaction->{'pnp_transaction_id'});
    $formatted->{'pnp_transaction_id'} = $uuid->inHex();
  } else {
    $formatted->{'pnp_transaction_id'} = $transaction->{'pnp_transaction_id'};
  }

  if ($transaction->{'pnp_order_id'} !~ /^[a-fA-F0-9]+$/) {
    $uuid->fromBinary($transaction->{'pnp_order_id'});
    $formatted->{'pnp_order_id'} = $uuid->inHex();
  } else {
    $formatted->{'pnp_order_id'} = $transaction->{'pnp_order_id'};
  }

  $formatted->{'completion_time'} = $time->nowInFormat('unix');
  $formatted->{'request_time_length'} = 0;
  $formatted->{'request_time'} = 0;
  $formatted->{'transaction_state_id'} = $transState;
  $formatted->{'transaction_vehicle_id'} = $transaction->{'transaction_vehicle_id'};
  $formatted->{'transaction_date_time'} = $time->inFormatDetectType('db_gm',$transaction->{'transaction_date_time'});
  eval{
    $formatted->{'processor_code'} = $transaction->{'additional_processor_details'}{$transState}{'processor_code'} || '0000';
  };
  $formatted->{'additional_processor_details'} = $transaction->{'additional_processor_details'}{$transState} || $transaction->{'additional_processor_details'};

  return $formatted;
}

sub processResponse {
  my $self = shift;
  my $response = shift;

  # Why do this you ask? For compatability!!!!
  my $formattedResponses = $response;
  $formattedResponses->{'FinalStatus'}        = $response->{'processor_status'};
  $formattedResponses->{'MStatus'}            = $response->{'processor_status'};
  $formattedResponses->{'auth-code'}          = $response->{'authorization_code'};
  $formattedResponses->{'cvvresp'}            = $response->{'cvv_response'} if $response->{'cvv_response'};
  $formattedResponses->{'avs-code'}           = $response->{'avs_response'} if $response->{'avs_response'};
  $formattedResponses->{'MErrMsg'}            = $response->{'processor_message'};
  $formattedResponses->{'pnp_transaction_id'} = $response->{'pnp_transaction_id'} if $response->{'pnp_transaction_id'};
  $formattedResponses->{'pnp_order_id'}       = $response->{'pnp_order_id'} if $response->{'pnp_order_id'};
  $formattedResponses->{'orderID'}            = $response->{'merchant_order_id'};
  $formattedResponses->{'orderid'}            = $response->{'merchant_order_id'};

  return $formattedResponses;
}

sub makeResponseObj {
  my $self = shift;
  my $data = shift;

  my $response = new PlugNPay::Transaction::Response();
  my $stateObj = new PlugNPay::Transaction::State();
  my $status = $stateObj->getSuccessStatus($data->{'transaction_state_id'});
  $data->{'processor_status'} = $status;
  if ($status ne 'success') {
    if (!$data->{'processor_message'}) {
      $data->{'processor_message'} = 'Transaction status returned as ' . $status;
    }
    $data->{'pnp_message'} =  'Transaction status returned as ' . $status;  
  }

  my $raw = $self->processResponse($data);
  $response->setRawResponse($raw);

  return $response;
}

sub stringifyElement {
  my $self = shift;
  my $data = shift;
  if (ref($data) eq 'HASH') {
    my %newHash = ();
    foreach my $key (keys %{$data}) {
      $newHash{$key} = $self->stringifyElement($data->{$key});
    }

    return \%newHash;
  } elsif (ref($data) eq 'ARRAY') {
    my @newArray = ();
    foreach my $item (@{$data}){
      push @newArray,$self->stringifyElement($item);
    }

    return \@newArray;
  } else {
    if (defined $data ) {
      return "$data";
    } else {
      return undef;
    }
  }
}

sub getOperationFromPackage {
  my $self = shift;
  my $ref = shift;

  if ($ref =~ /^PlugNPay::Transaction::Authorization/) {
    return "auth";
  } elsif ( $ref =~ /^PlugNPay::Transaction::Credit/ ) {
    return "credit";
  } elsif ($ref =~ /^PlugNPay::Transaction::StoreData/) {
    return "storedata";
  } else {
    return "INIT";
  }
}

1;
