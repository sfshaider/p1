package PlugNPay::Transaction::JSON;

use strict;
use PlugNPay::Token;
use PlugNPay::Contact;
use PlugNPay::Sys::Time;
use PlugNPay::GatewayAccount;
use PlugNPay::Util::UniqueID;
use PlugNPay::Processor::Route;
use PlugNPay::Transaction::State;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::Response::JSON;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub transactionToJSON {
  my $self = shift;
  my $transactionObj = shift;
  my $options = shift || {};

  # gaMaybe might be string or object, object overloads to string
  my $gaMaybe = $transactionObj->getGatewayAccount();
  my $ga = new PlugNPay::GatewayAccount("$gaMaybe");

  my $processor = $transactionObj->getProcessor();

  my $billingInfo = $self->contactInformation($transactionObj->getBillingInformation());
  my $shippingInfo = $self->contactInformation($transactionObj->getShippingInformation());
  my $feeTax = $transactionObj->getTaxAmount() - $transactionObj->getBaseTaxAmount();
  $feeTax = 0 if $feeTax < 0;
  my $paymentType = $transactionObj->getTransactionPaymentType();

  my $hash = {
    'gatewayAccount'       => $ga->getGatewayAccountName(),
    'currency'             => uc($transactionObj->getCurrency()),
    'amount'               => sprintf("%.2f",$transactionObj->getTransactionAmount()),
    'baseAmount'           => sprintf("%.2f",$transactionObj->getBaseTransactionAmount()),
    'feeAmount'            => sprintf("%.2f",$transactionObj->getTransactionAmountAdjustment()),
    'tax'                  => sprintf("%.2f", $transactionObj->getTaxAmount()),
    'baseTax'              => sprintf("%.2f",$transactionObj->getBaseTaxAmount()),
    'feeTax'               => sprintf("%.2f",$feeTax),
    'billingInfo'          => $billingInfo,
    'shippingInfo'         => $shippingInfo,
    'orderID'              => $transactionObj->getMerchantTransactionID(),
    'secCode'              => $transactionObj->getSECCode(),
    'payment'              => {'type' => $paymentType,'mode' => $transactionObj->getTransactionMode()},
    'authorizationCode'    => $transactionObj->getAuthorizationCode(),
    'purchaseOrderNumber'  => $transactionObj->getPurchaseOrderNumber(),
    'transactionState'     => determineState($transactionObj->getTransactionState(),$transactionObj->getExtraTransactionData()),
    'loadedState'          => $transactionObj->getTransactionState(),
    'processor'            => $processor
  };

  $hash->{'transactionDateTime'} = $self->convertTimeFormat($transactionObj->getTransactionDateTime());

  $hash->{'processorReferenceID'} = $transactionObj->getProcessorReferenceID() || '';

  my $router = new PlugNPay::Processor::Route();
  if ($router->getProcessorPackageData()->{$processor}{$paymentType}{'package'} =~ /^PlugNPay::Processor::Route/) {
    my $uuid = new PlugNPay::Util::UniqueID();
    if ($transactionObj->getPNPTransactionID() !~ /^[a-fA-F0-9]+$/) {
      $uuid->fromBinary($transactionObj->getPNPTransactionID());
      $hash->{'pnpTransactionID'} = $uuid->inHex();
    } else {
      $hash->{'pnpTransactionID'} = $transactionObj->getPNPTransactionID();
    }

    #Unique Identifier in an order Object, but has a reference in Transaction objects too.
    if (defined $transactionObj->getPNPOrderID()) {
      if ($transactionObj->getPNPOrderID() !~ /^[a-fA-F0-9]+$/) {
        $uuid->fromBinary($transactionObj->getPNPOrderID());
        $hash->{'pnpOrderID'} = $uuid->inHex();
      } else {
        $hash->{'pnpOrderID'} = $transactionObj->getPNPOrderID();
      }
    } else {
      $hash->{'pnpOrderID'} = '';
    }

    #New processing splits these this way
    if (defined $transactionObj->getPNPTransactionReferenceID()) {
      if ($transactionObj->getPNPTransactionReferenceID() !~ /^[a-fA-F0-9]+$/) {
        $uuid->fromBinary($transactionObj->getPNPTransactionReferenceID());
        $hash->{'pnpTransactionReferenceID'} = $uuid->inHex();
      } else {
        $hash->{'pnpTransactionReferenceID'} = $transactionObj->getPNPTransactionReferenceID();
      }
    } else {
      $hash->{'pnpTransactionReferenceID'} = '';
    }
  } else {
    $hash->{'pnpTransactionID'} = $transactionObj->getMerchantTransactionID();
  }

  $hash->{'merchantClassifierID'} = $transactionObj->getMerchantClassifierID();
  $hash->{'merchantOrderID'} = $transactionObj->getMerchantTransactionID();

  if (defined $transactionObj->getProcessorToken()) {
    $hash->{'processorToken'} = $transactionObj->getProcessorToken();
  }

  if (defined $transactionObj->getProcessorDataDetails()) {
    my $stateID = new PlugNPay::Transaction::State()->getTransactionStateID($transactionObj->getTransactionState());
    my $specificData = $transactionObj->getProcessorDataDetails()->{$stateID} || {};
    $hash->{'processorDetails'} = $self->convertKeyNames($specificData);
  } else {
    $hash->{'processorDetails'} = {};
  }
  my $payment = $transactionObj->getPayment();
  my $paymentName;
  if (ref($payment) =~ /^PlugNPay::CreditCard/) {
    if ($transactionObj->getPNPToken()) {
      if ($transactionObj->getPNPToken() =~ /^[a-fA-F0-9]+$/) {
        $hash->{'payment'}{'card'}{'token'} = $transactionObj->getPNPToken();
      } else {
        my $token = new PlugNPay::Token();
        $token->fromBinary($transactionObj->getPNPToken());
        $hash->{'payment'}{'card'}{'token'} = $token->inHex();
      }
    }

    $paymentName = $payment->getName();
    $hash->{'payment'}{'card'}{'name'} = $paymentName || '';
    $hash->{'payment'}{'card'}{'maskedNumber'} = $payment->getMaskedNumber();
    $hash->{'payment'}{'card'}{'expMonth'} = $payment->getExpirationMonth();
    $hash->{'payment'}{'card'}{'expYear'} = $payment->getExpirationYear();
    $hash->{'payment'}{'card'}{'type'} = $payment->getType();
    $hash->{'payment'}{'card'}{'brand'} = $payment->getBrand();
    $hash->{'payment'}{'card'}{'isDebit'} = $payment->isDebit();

    if ($options->{'fullPaymentInfo'}) {
      $hash->{'payment'}{'card'}{'number'} = $payment->getNumber();
      $hash->{'payment'}{'card'}{'securityCode'} = $payment->getSecurityCode();
    }
  } elsif (ref($payment) =~ /^PlugNPay::OnlineCheck/){
    if ($transactionObj->getPNPToken()){
      if ($transactionObj->getPNPToken() =~ /^[a-fA-F0-9]+$/) {
        $hash->{'payment'}{'ach'}{'token'} = $transactionObj->getPNPToken();
      } else {
        my $token = new PlugNPay::Token();
        $token->fromBinary($transactionObj->getPNPToken());
        $hash->{'payment'}{'ach'}{'token'} = $token->inHex();
      }
      $payment->fromToken($hash->{'payment'}{'ach'}{'token'});
    }

    $paymentName = $payment->getName();
    $hash->{'payment'}{'ach'}{'name'} = $paymentName || '';
    $hash->{'payment'}{'ach'}{'maskedAccountNumber'} = $payment->getMaskedAccount();
    $hash->{'payment'}{'ach'}{'routingNumber'} = $payment->getRoutingNumber();
    $hash->{'payment'}{'ach'}{'accountType'} = $payment->getAccountType();
    if ($options->{'fullPaymentInfo'}) {
      $hash->{'payment'}{'ach'}{'accountNumber'} = $payment->getAccountNumber();
    } else {
      $hash->{'payment'}{'ach'}{'accountNumber'} = $payment->getMaskedAccount();
    }
  }

  if ($paymentName && (!$hash->{'billingInfo'}{'name'} || $hash->{'billingInfo'}{'name'} =~ /^\s+$/)) {
    $hash->{'billingInfo'}{'name'} = $paymentName;
  }

  $hash->{'accountCode'} = {
    1 => $transactionObj->getAccountCode(1),
    2 => $transactionObj->getAccountCode(2),
    3 => $transactionObj->getAccountCode(3),
    4 => $transactionObj->getAccountCode(4)
  };

  $hash->{'login'} = $transactionObj->getLogin();

  $hash->{'reason'} = $transactionObj->getReason();

  $hash->{'customData'} = $transactionObj->getCustomData();

  $hash->{'settledAmount'} = sprintf("%.2f",$transactionObj->getSettledAmount()) || 0.00;
  $hash->{'markedSettlementAmount'} = sprintf("%.2f",$transactionObj->getSettlementAmount()) || 0.00;

  my $extra = $transactionObj->getExtraTransactionData();
  $hash->{'additionalMerchantData'} = $self->convertKeyNames($extra);
  delete($hash->{'additionalMerchantData'}{'responseData'});

  if ($extra->{'batchID'}) {
    $hash->{'batchID'} = $extra->{'batchID'};
  }

  $hash->{'additionalProcessorData'} = $self->mapIDToState($transactionObj->getProcessorDataDetails());
  #Response Data
  if (ref($transactionObj->getResponse()) eq 'PlugNPay::Transaction::Response') {
    $hash->{'cvvResponse'} = $transactionObj->getResponse()->getSecurityCodeResponse();
    $hash->{'avsResponse'} = $transactionObj->getResponse()->getAVSResponse();
    $hash->{'processorMessage'} = $transactionObj->getResponse()->getMessage();
  } else {
    $hash->{'cvvResponse'} = $extra->{'response_data'}{'cvv_response'};
    $hash->{'avsResponse'} = $extra->{'response_data'}{'avs_response'};
    $hash->{'processorMessage'} = $extra->{'response_data'}{'processor_message'};
  }

  if (!$hash->{'authorizationCode'} && $extra->{'response_data'}{'authorization_code'}) {
    $hash->{'authorizationCode'} = substr($extra->{'response_data'}{'authorization_code'},0,6);
  }

  $hash->{'additionalProcessorData'} = $transactionObj->getProcessorDataDetails();
  $hash->{'transactionHistory'} = $self->convertKeyNames($transactionObj->getHistory());

  my $transStateOptions = {
    'status' => $hash->{'finalStatus'},
    'reference_number' => $transactionObj->getPNPTransactionReferenceID(),
    'pnp_job_id' => $extra->{'pnp_job_id'}
  };

  my $adjInfo = $transactionObj->getTransactionInfoForConvenienceCharge();
  if ($adjInfo->{'orderID'} && $adjInfo->{'gatewayAccount'}) {
    $hash->{'adjustmentInformation'}{'adjustmentOrderID'} = $adjInfo->{'orderID'};
    $hash->{'adjustmentInformation'}{'adjustmentAccount'} = $adjInfo->{'gatewayAccount'};
  }

  $hash->{'transactionStatus'} = getStatusFromState($hash->{'transactionState'},$hash->{'finalStatus'}, $transStateOptions);

  if ($transactionObj->getResponse()) {
    my $responseJSONitizerator = new PlugNPay::Transaction::Response::JSON();
    my $responseJSON = $responseJSONitizerator->responseToJSON($transactionObj->getResponse());
    $hash->{'response'} = $responseJSON;
  }

  return $hash;
}

#Sub Function to build contact info
sub contactInformation {
  my $self = shift;
  my $contact = shift;

  if (ref($contact) eq 'PlugNPay::Contact') {
    my $contactHash = {
      'name'        => $contact->getFullName(),
      'company'     => $contact->getCompany(),
      'address'     => $contact->getAddress1(),
      'address2'    => $contact->getAddress2(),
      'city'        => $contact->getCity(),
      'state'       => $contact->getState(),
      'postalCode'  => $contact->getPostalCode(),
      'country'     => $contact->getCountry(),
      'phone'       => $contact->getPhone(),
      'fax'         => $contact->getFax(),
      'email'       => $contact->getEmailAddress()
    };

    return $contactHash;
  } else {
    my $contactUpdate = {};
    my $postalCode = $contact->{'postal_code'} || $contact->{'postalCode'};
    my $phone = $contact->{'dayPhone'} || $contact->{'phone'};
    $contactUpdate->{'name'} = $contact->{'name'} || '';
    $contactUpdate->{'company'} = $contact->{'company'} || '';
    $contactUpdate->{'address'} = $contact->{'address'} || '';
    $contactUpdate->{'address2'} = $contact->{'address2'} || '';
    $contactUpdate->{'city'} = $contact->{'city'} || '';
    $contactUpdate->{'state'} = $contact->{'state'} || '';
    $contactUpdate->{'country'} = $contact->{'country'} || '';
    $contactUpdate->{'email'} = $contact->{'email'} || '';
    $contactUpdate->{'postalCode'} = $postalCode || '';
    $contactUpdate->{'fax'} = $contact->{'fax'} || '';
    $contactUpdate->{'phone'} = $phone || '';

    return $contactUpdate;
  }
}

sub mapIDToState {
  my $self = shift;
  my $additionalDetails = shift;
  if (ref($additionalDetails) ne 'HASH') {
    return {};
  }

  my $responseHash = {};
  my $stateMachine = new PlugNPay::Transaction::State();
  foreach my $key (keys %{$additionalDetails}) {
    if ($key =~ /^\d+$/) {
      $responseHash->{$stateMachine->getTransactionStateName($key)} = $self->convertKeyNames($additionalDetails->{$key});
    } else {
      $responseHash->{$key} = $self->convertKeyNames($additionalDetails->{$key});
    }
  }

  return $responseHash;
}

sub convertKeyNames {
  my $self = shift;
  my $oldData = shift;
  my $newData = {};

  foreach my $key (keys %{$oldData}) {
    my $convertedKey = lcfirst(join('', map {ucfirst($_)} split('_',$key)));
    my $entry = $oldData->{$key};
    if ($key =~ /time/i) {
      $entry = $self->convertTimeFormat($entry);
    }

    if ($key =~ /amount/i) {
      $entry = sprintf("%.2f",$entry);
    }

    if (ref($entry) =~ /^PlugNPay::Transaction/) {
      $entry = $self->transactionToJSON($entry);
    }

    $newData->{$convertedKey} = $entry;
  }

  return $newData;
}

sub getStatusFromState {
  my $state = uc shift;
  my $processorStatus = uc shift;
  my $options = shift || {};
  my $displayState = {};
  my ($transState, $subState) = split('_',$state);

  if ($transState eq 'AUTH' || $transState eq 'AUTHORIZATION') {
    if ($options->{'pnp_job_id'}) {
      $displayState->{'state'} = 'Marked';
    } else {
      $displayState->{'state'} = 'Authorization';
    }
  } elsif ($transState eq 'POSTAUTH'){
    if ($subState eq 'READY') {
      $displayState->{'state'} = 'Marked';
    } else {
      $displayState->{'state'} = 'Settlement';
    }
  } elsif ($transState eq 'CREDIT' || $transState eq 'RETURN') {
    $displayState->{'state'} = ($transState eq 'CREDIT' && !$options->{'reference_number'} ? 'Credit' : 'Return');
  } elsif ($transState eq 'VOID' && $processorStatus eq 'SUCCESS') {
    $displayState->{'state'} = 'Voided';
  } elsif ($transState eq 'SALE') {
    $displayState->{'state'} = 'Sale';
  } else {
    $displayState->{'state'} = ucfirst($transState);
  }

  if ($displayState->{'state'} ne 'Marked' && $displayState->{'state'} ne 'Voided') {
    if ($subState eq 'PROBLEM' || $processorStatus =~ /PROBLEM|BADCARD/i) {
      my $canDecline = ($transState eq 'AUTH' || $transState eq 'CREDIT' || $transState eq 'RETURN' || $transState eq 'SALE');
      $displayState->{'status'} = ($canDecline && $options->{'status'} =~ /decline|badcard/i ? 'Declined' : 'Failure');
    } elsif ($subState eq 'PENDING' || $processorStatus eq 'PENDING') {
      $displayState->{'status'} = 'Pending';
    } else {
      $displayState->{'status'} = 'Successful';
    }
  } else {
    delete $displayState->{'status'};
  }

  return $displayState;
}

sub determineState {
  my $transactionState = shift;
  my $additionalMerchantData = shift || {};

  if ($additionalMerchantData->{'pnp_job_id'} && $additionalMerchantData->{'has_settlement_job'} && $transactionState eq 'AUTH') {
    return 'POSTAUTH_READY';
  } else {
    return $transactionState;
  }
}

sub convertTimeFormat {
  my $self = shift;
  my $timeString = shift;
  my $newTime = '';
  my $timeObj = new PlugNPay::Sys::Time();

  #Doing some funky stuff
  if ($timeString !~ /^\d{4}:\d{2}:\d{2} \d{2}\d{2}\d{2}$/) {
    $newTime = $timeObj->inFormatDetectType('db_gm', $timeString);
  } else {
    $newTime = $timeString;
  }

  $newTime =~ s/ /T/;

  return $newTime . 'Z';
}

1;
