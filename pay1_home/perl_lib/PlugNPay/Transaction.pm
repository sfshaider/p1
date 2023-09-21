package PlugNPay::Transaction;

use strict;

use Math::BigInt;
use PlugNPay::Sys::Time;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount;
use PlugNPay::Util::UniqueID;
use PlugNPay::Transaction::Response;
use PlugNPay::Transaction::Authorization::Credit;
use PlugNPay::Transaction::Authorization::PrePaid;
use PlugNPay::Transaction::Authorization::OnlineCheck;
use PlugNPay::Transaction::Authorization::EMV;
use PlugNPay::Transaction::StoreData::Credit;
use PlugNPay::Transaction::StoreData::PrePaid;
use PlugNPay::Transaction::StoreData::OnlineCheck;
use PlugNPay::Transaction::Credit::Credit;
use PlugNPay::Transaction::Credit::PrePaid;
use PlugNPay::Transaction::Credit::OnlineCheck;
use PlugNPay::Transaction::Credit::EMV;
use PlugNPay::Processor;
use PlugNPay::Currency;
use PlugNPay::Util::Clone;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Transaction::Legacy::AdditionalProcessorData;
use PlugNPay::Die;

use Time::HiRes qw(time);

our $__transaction_versions__ = {
  legacy => 'legacy',
  unified => 'unified'
};

sub new {
  my $class = shift;

  my $transactionObject;

  my ($mode,$type) = @_;

  $mode = lc $mode;
  $type = lc $type;
  my $giftMode = $mode;
  if ($mode eq 'issue' || $mode eq 'reload' || $mode eq 'balance') {
    $mode = 'auth';
  } elsif ($mode =~ /^void/) {
    $mode = 'void';
  }

  my ($state, $status) = split('_', $mode);
  my $transactionState = 'INIT';
  if ($mode =~ /^auth/ || inArray($state,['postauth','sale','forceauth','reauth'])) {
    $transactionState = 'AUTH_PENDING';
    if ($type =~ /^credit/ || $type =~ /^card/) {
      $transactionObject = new PlugNPay::Transaction::Authorization::Credit();
      if ($mode eq 'postauth') {
        $transactionState = 'POSTAUTH_READY';
      } elsif ($mode eq 'sale') {
        $transactionState = 'SALE_PENDING';
        $transactionObject->setSale();
      } elsif ($mode eq 'forceauth') {
        $transactionObject->setForceAuth();
      } elsif ($mode eq 'reauth') {
        $transactionState = 'AUTH_REVERSAL_PENDING'
      }
    } elsif ($type eq 'ach' || $type =~ /checking|savings/) {
      $transactionObject = new PlugNPay::Transaction::Authorization::OnlineCheck();
    } elsif ($type eq 'prepaid' || $type eq 'gift') {
      $transactionObject = new PlugNPay::Transaction::Authorization::PrePaid();
      $transactionObject->setGiftOp($giftMode);
    } elsif ($type eq 'emv') {
      $transactionObject = new PlugNPay::Transaction::Authorization::EMV();
      $transactionState = 'SALE_PENDING';
      $transactionObject->setSale();
    }
  } elsif ($mode =~ /^storedata/) {
    $transactionState = 'STOREDATA';
    if ($type =~ /^credit/ || $type =~ /^card/) {
      $transactionObject = new PlugNPay::Transaction::StoreData::Credit();
    } elsif ($type eq 'ach' || $type =~ /checking|savings/) {
      $transactionObject = new PlugNPay::Transaction::StoreData::OnlineCheck();
    } elsif ($type eq 'prepaid' || $type eq 'gift') {
      $transactionObject = new PlugNPay::Transaction::StoreData::PrePaid();
    }
  } elsif ($mode =~ /^credit/ || $mode eq 'return') {
    $transactionState = 'CREDIT_PENDING';
    if ($type =~ /^credit/ || $type =~ /^card/) {
      $transactionObject = new PlugNPay::Transaction::Credit::Credit();
    } elsif ($type eq 'ach' || $type =~ /checking|savings/) {
      $transactionObject = new PlugNPay::Transaction::Credit::OnlineCheck();
    } elsif ($type eq 'prepaid' || $type eq 'gift') {
      $transactionObject = new PlugNPay::Transaction::Credit::PrePaid();
      $transactionObject->setGiftOp($giftMode);
    } elsif ($type eq 'emv') {
      $transactionObject = new PlugNPay::Transaction::Credit::EMV();
    }
  } elsif ($mode eq 'void') {
    $transactionObject = new PlugNPay::Transaction::Credit::Credit();
    $transactionObject->setTransactionType('void');
    $transactionObject->setTransactionMode('void');
    $transactionObject->setTransactionState('VOID_PENDING');
  }

  # Required for new transaction processing #
  if (defined $transactionObject) {
    if (defined $status && 
        inArray($status,['pending', 'problem', 'ready']) &&
        inArray($state,['postauth','sale','forceauth','reauth','void','credit','storedata','auth','authorization'])
    ) {
      $transactionObject->setTransactionState(uc($mode));
    } else {
      $transactionObject->setTransactionState($transactionState);
    }
    $transactionObject->setTransactionMode($mode);
    $transactionObject->setPNPTransactionID();
  } else {
    die('Failed to create a transaction object for: ' . "mode = '$mode', type = '$type'");
  }

  return $transactionObject;
}


#################################################
# Clone: Create a shallow copy of a transaction #
#################################################
sub clone {
  my $self = shift;

  my $cloner = new PlugNPay::Util::Clone();
  my $clone = $cloner->deepClone($self);;

  return $clone;
}

sub cloneTransactionData {
  my $self = shift;
  my $transaction = shift;
  eval {
    my %transData = %{$transaction->getAllTransactionData()};
    $self->{'transactionData'} = \%transData;
  };

  return ($@ ? 0 : 1);
}

sub loadTransaction {
  my $self = shift;
  my $transactionID = shift;
  my $loader = new PlugNPay::Transaction::Loader();
  my $loadData = { 'transactionID' => $transactionID };
  if (defined $self->getGatewayAccount()) {
    $loadData->{'gatewayAccount'} = $self->getGatewayAccount();
  }

  my $transaction = $loader->load($loadData);

  $self = $transaction; #Is this what it should do?

  return $transaction;
}

#########################
## SETTERS AND GETTERS ##
#########################
# Gateway Account #
###################
sub setGatewayAccount {
  my $self = shift;
  my $account = shift;
  
  if (ref($account) ne 'PlugNPay::GatewayAccount') {
    $account = new PlugNPay::GatewayAccount($account);
  }

  $self->{'gatewayAccount'} = $account;
}

# old way to get gateway account name, to be deprecated
sub getGatewayAccount {
  my $self = shift;
  return $self->getGatewayAccountName();
}

# new way to get gateway account name
sub getGatewayAccountName {
  my $self = shift;

  my $account = $self->{'gatewayAccount'};
  if (!defined($account)) {
    die('gateway account not set');
  }

  return $account->getGatewayAccountName();
}

sub getGatewayAccountObject {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

# Processor MID for the transaction.
sub setProcessorMerchantId {
  my $self = shift;
  my $mid = shift;
  $mid =~ s/\n//g; # really don't know what else to safely filter here...
  $self->_setTransactionData('processorMerchantId',$mid);
}

sub getProcessorMerchantId {
  my $self = shift;
  return $self->_getTransactionData('processorMerchantId') || '';
}

##############
# IP Address #
##############
sub setIPAddress {
  my $self = shift;
  my $address = shift;

  $self->_setTransactionData('ipAddress',$address);
}

sub getIPAddress {
  my $self = shift;
  return $self->_getTransactionData('ipAddress');
}

###################
# TransactionType #
#########################################################################################################
# transaction type is equivilent to "operation" in the old code.                                        #
# transaction mode is a specific version of that type, such as a return being a special type of credit. #
#########################################################################################################
sub setTransactionMode {
  my $self = shift;
  $self->_setTransactionData('transactionMode',shift);
}

sub getTransactionMode {
  my $self = shift;
  return $self->_getTransactionData('transactionMode');
}


sub setTransactionType {
  my $self = shift;
  $self->_setTransactionData('transactionType',shift);
}

sub getTransactionType {
  my $self = shift;
  $self->_getTransactionData('transactionType');
}

sub setTransactionState {
  my $self = shift;
  my $state = shift;
  $self->_setTransactionData('transactionState',$state);
}

sub getTransactionState {
  my $self = shift;
  my $state = $self->_getTransactionData('transactionState');

  return $state;
}

#################
# Do Post Auth? #
#################

sub setPostAuth {
  my $self = shift;
  $self->{'postAuth'} = 1;
}

sub unsetPostAuth {
  my $self = shift;
  $self->{'postAuth'} = 0;
}

# some code somewhere calls this...
# TODO change the code calling this.
sub unsetMark {
  my $self = shift;
  $self->unsetPostAuth();
}

sub doPostAuth {
  my $self = shift;
  return $self->{'postAuth'};
}

##################
# Is Force Auth? #
##################
sub setForceAuth {
  my $self = shift;
  $self->{'forceAuth'} = 1;
}

sub unsetForceAuth {
  my $self = shift;
  $self->{'forceAuth'} = 0;
}

sub doForceAuth {
  my $self = shift;
  return $self->{'forceAuth'};
}

############
# Is Sale? #
############
sub setSale {
  my $self = shift;
  $self->{'sale'} = 1;
}

sub unsetSale {
  my $self = shift;
  $self->{'sale'} = 0;
}

sub doSale {
  my $self = shift;
  return $self->{'sale'};
}

############
# Currency #
############
sub setCurrency {
  my $self = shift;
  my $currency = lc shift;
  $currency =~ s/[^a-z]//g;
  # TODO: Add code to validate the currency using Currency.pm, which is currently in a non-merged branch
  # for now, default to merchant's default currency or USD if they do not have a default currency set
  if (!$currency && $self->getGatewayAccount()) {
    my $ga = new PlugNPay::GatewayAccount($self->getGatewayAccount());
    $currency = $ga->getDefaultCurrency() || 'USD';
  } elsif (!$currency) {
    die('Cannot set default currency unless the gateway account is defined.');
  }
  $self->_setTransactionData('currency',$currency);
}

sub getCurrency {
  my $self = shift;
  my $currency = $self->_getTransactionData('currency');

  my $ga = new PlugNPay::GatewayAccount($self->getGatewayAccount());

  return $currency || $ga->getDefaultCurrency() || 'USD';
}

######################
# Transaction Amount #
######################
sub setTransactionAmount {
  my $self = shift;
  my $amount = shift;
  $amount =~ s/[^0-9\.]//g;

  $self->_setTransactionData('amount',$amount || 0.00);
}

sub getTransactionAmount {
  my $self = shift;
  my $amount = $self->_getTransactionData('amount');
  $amount = $self->_withPreceision($amount);
  return $amount;
}

sub setBaseTransactionAmount {
  my $self = shift;
  my $amount = shift;
  $amount =~ s/[^0-9\.]//g;

  $self->_setTransactionData('baseAmount',$amount || 0.00);
}

sub getBaseTransactionAmount {
  my $self = shift;

  my $amount;
  if ($self->getTransactionMode() eq 'credit' || $self->getTransactionMode() eq 'return') {
    $amount = $self->getTransactionAmount();
  } else {
    $amount = $self->_getTransactionData('baseAmount') || ($self->getTransactionAmount() - $self->getTransactionAmountAdjustment());
    $amount = $self->_withPreceision($amount);
  }

  return $amount;
}

sub setTransactionAmountAdjustment {
  my $self = shift;
  my $amount = shift;
  $amount =~ s/[^0-9\.]//g;

  $self->_setTransactionData('adjustmentAmount',$amount || 0.00);
}

sub getTransactionAmountAdjustment {
  my $self = shift;

  my $amount = $self->_getTransactionData('adjustmentAmount');
  $amount = $self->_withPreceision($amount);

  return $amount;
}

sub adjustmentIsSurcharge {
  my $self = shift;
  $self->_setTransactionData('adjustmentIsSurcharge',1);
}

sub isAdjustmentSurcharge {
  my $self = shift;
  return $self->_getTransactionData('adjustmentIsSurcharge');
}

sub setOverrideAdjustment {
  my $self = shift;
  $self->_setTransactionData('overrideAdjustment',1);
}

sub getOverrideAdjustment {
  my $self = shift;
  return $self->_getTransactionData('overrideAdjustment');
}

sub setSettlementAmount {
  my $self = shift;
  my $amount = shift;
  $amount =~ s/[^0-9\.]//g;

  $self->_setTransactionData('settlementAmount',$amount);
}

sub getSettlementAmount {
  my $self = shift;

  return $self->_getTransactionData('settlementAmount');
}

sub setSettledAmount {
  my $self = shift;
  my $amount = shift;
  $amount =~ s/[^0-9\.]//g;

  $self->_setTransactionData('settledAmount',$amount);
}

sub getSettledAmount {
  my $self = shift;

  return $self->_getTransactionData('settledAmount');
}

sub setGratuityAmount {
  my $self = shift;
  my $amount = shift;
  $amount =~ s/[^0-9\.]//g;

  # legacy stores gratuity in raw auth code
  if ($self->getTransactionVersion() eq 'legacy') {
    my $processorId = $self->getProcessorID();
    my $additionalData = new PlugNPay::Transaction::Legacy::AdditionalProcessorData({ processorId => $processorId });

    my $rawAuthCode = $self->getRawAuthorizationCode() || ''; # default to blank in case it's not yet set for "new" processors
    $additionalData->setAdditionalDataString($rawAuthCode);

    if ($amount > 0) {
      if (!$additionalData->hasField('gratuity')) {
        die('gratuity may not be set for processor');
      }
      $additionalData->setField('gratuity',$amount);
    }
    
    $self->setRawAuthorizationCode($additionalData->getAdditionalDataString());
  }

  $self->_setTransactionData('gratuityAmount',$amount);
}

sub getGratuityAmount {
  my $self = shift;

  return $self->_getTransactionData('gratuityAmount');
}

####################
# Transaction Time #
####################
sub setTime {
  my $self = shift;
  my $time = shift;

  #this has a check to make sure it's not unix
  $time = new PlugNPay::Sys::Time()->inFormatDetectType('unix',$time);
  $self->_setTransactionData('time',$time);
  if (!defined $self->getTransactionDateTime()) {
    $self->_setTransactionData('transactionDateTime',$time);
  }
}

sub getTime {
  my $self = shift;
  return $self->_getTransactionData('time');
}

##############
# Tax Amount #
##############
sub setTaxAmount {
  my $self = shift;
  my $amount = shift;
  $amount =~ s/[^0-9\.]//g;

  $self->_setTransactionData('tax',$amount || 0.00);
}

sub getTaxAmount {
  my $self = shift;
  my $amount = $self->_getTransactionData('tax');
  $amount = $self->_withPreceision($amount);

  return $amount;
}

sub setBaseTaxAmount {
  my $self = shift;
  my $amount = shift;
  $amount =~ s/[^0-9\.]//g;

  $self->_setTransactionData('baseTaxAmount',$amount || 0.00);
}

sub getBaseTaxAmount {
  my $self = shift;
  my $amount = $self->_getTransactionData('baseTaxAmount');
  
  $amount = $self->_withPreceision($amount);

  return $amount;
}


sub getEffectiveTaxRate {
  my $self = shift;
  my $total = $self->getTransactionAmount();
  my $tax = $self->getTaxAmount();
  if (($total - $tax) > 0) {
    return ($tax / ($total - $tax));
  } else {
    return 0;
  }
}

sub setSettledTaxAmount {
  my $self = shift;
  $self->_setTransactionData('settledTaxAmount',shift);
}

sub getSettledTaxAmount {
  my $self = shift;
  return $self->_getTransactionData('settledTaxAmount');
}

#######################
# Billing Information #
#######################
# This expects a 'PlugNPay::Contact' object to be passed in;
sub setBillingInformation {
  my $self = shift;
  $self->_setTransactionData('billingContactInformation',shift);
}

sub getBillingInformation {
  my $self = shift;
  return $self->_getTransactionData('billingContactInformation');
}

########################
# Shipping Information #
########################
sub setShippingAmount {
  my $self = shift;
  $self->_setTransactionData('shippingAmount',shift)
}

sub getShippingAmount {
  my $self = shift;
  return $self->_getTransactionData('shippingAmount');
}

# This expects a 'PlugNPay::Contact' object to be passed in;
sub setShippingInformation {
  my $self = shift;
  $self->_setTransactionData('shippingContactInformation',shift);
}

sub getShippingInformation {
  my $self = shift;
  return $self->_getTransactionData('shippingContactInformation');
}

sub setShippingNotes {
  my $self = shift;
  my $shippingNotes = shift;
  return $self->_setTransactionData('shippingNotes',$shippingNotes);
}

sub getShippingNotes {
  my $self = shift;
  return $self->_getTransactionData('shippingNotes');
}

############
# Order ID #
############
# sets internally as hex.
sub setPNPOrderID {
  my $self = shift;
  my $id = shift;
  if ($id) {
    if ($self->getTransactionVersion() eq 'legacy') {
      $self->setOrderID($id);
    } else {
      my $hex = PlugNPay::Util::UniqueID::fromBinaryToHex($id);
      $self->_setTransactionData('pnpOrderID',$hex);
    }
  }
}

# returns binary
sub getPNPOrderID {
  my $self = shift;
  my $id;
  if ($self->getTransactionVersion() eq 'legacy') {
    $id = $self->getOrderID();
    if (!$id) {
      $id = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
      $self->_setTransactionData('pnpOrderID',$id);
    }
  } else {
    $id = PlugNPay::Util::UniqueID::fromHexToBinary($self->_getTransactionData('pnpOrderID'));
    if (!$id) {
      $id = $self->generateTransactionID();
      $self->_setTransactionData('pnpOrderID',$id);
    }
  }
  return $id;
}


sub verifyOrderID {
  my $self = shift;
  my $id = shift;

  if ($self !~ /^PlugNPay::Transaction/ && !defined $id) {
    $id = $self;
  }

  my $uuid = new PlugNPay::Util::UniqueID();
  if ($id =~ /^[0-9a-fA-F]+$/) {
    $uuid->fromHex($id);
  } else {
    $uuid->fromBinary($id);
  }

  return $uuid->validate();
}

sub setMerchantTransactionID {
  my $self = shift;
  my $orderID = shift || '';
  my $override = shift;

  # override by default for now
  if (!defined $override) {
    $override = 1;
  }

  my $initialOrderID = $orderID;
  $orderID =~ s/[^0-9]//g;
  if ($initialOrderID ne $orderID) {
    $orderID = '';
  }

  if ($orderID) {
    my $maxValue = new Math::BigInt('18446744073709551615');
    my $bigOrderID = new Math::BigInt("$orderID");
    if ($bigOrderID > $maxValue) {
      my $message = "Merchant Order ID exceeds max value";
      if ($override) {
        eval {
          die $message;
        };
      } else {
        die $message;
      }
    }
  }

  $self->_setTransactionData('orderID',$orderID);
}

sub getMerchantTransactionID {
  my $self = shift;
  return $self->_getTransactionData('orderID');
}

sub setOrderID {
  my $self = shift;
  $self->setMerchantTransactionID(@_);
}

sub getOrderID {
  my $self = shift;
  return $self->getMerchantTransactionID();
}

####################
# Order Classifier #
####################

sub setMerchantClassifierID {
  my $self = shift;
  $self->_setTransactionData('merchantClassifierID',shift);
}

sub getMerchantClassifierID {
  my $self = shift;
  if (defined $self->_getTransactionData('merchantClassifierID')){
    return $self->_getTransactionData('merchantClassifierID');
  } else {
    my $id = '';
    $self->setMerchantClassifierID($id);
    return $id;
  }
}

##################
# Transaction ID #
##################
# sets internally as hex, because when you need to use Data::Dumper, it's a way better experience.
sub setPNPTransactionID {
  my $self = shift;
  my $id = shift;
  if ($id) {
    if ($self->getTransactionVersion() eq 'legacy') {
      $self->setOrderID($id);
    } else {
      my $hex = PlugNPay::Util::UniqueID::fromBinaryToHex($id);
      $self->_setTransactionData('pnpTransactionID',$hex);
    }
  }
}

sub verifyTransactionID {
  my $self = shift;
  my $id = shift;

  if ($self !~ /^PlugNPay::Transaction/ && !defined $id) {
    $id = $self;
  }

  my $uuid = new PlugNPay::Util::UniqueID();
  if ($id =~ /^[0-9a-fA-F]+$/) {
    $uuid->fromHex($id);
  } else {
    $uuid->fromBinary($id);
  }

  return $uuid->validate();
}

# always returns as binary for non-legacy
sub getPNPTransactionID {
  my $self = shift;
  my $id;
  if ($self->getTransactionVersion() eq 'legacy') {
    $id = $self->getOrderID();
    if (!$id) {
      $id = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
      $self->_setTransactionData('pnpTransactionID',$id);
    }
  } else {
    $id = PlugNPay::Util::UniqueID::fromHexToBinary($self->_getTransactionData('pnpTransactionID'));
    if (!$id) {
      $id = $self->generateTransactionID();
      $self->_setTransactionData('pnpTransactionID',$id);
    }
  }
  return $id;
}

# sets internally as hex
sub setPNPTransactionReferenceID {
  my $self = shift;
  my $transID = shift;
  my $hex;
  if ($transID) {
    $hex = PlugNPay::Util::UniqueID::fromBinaryToHex($transID);
  }
  $self->_setTransactionData('pnpTransactionReferenceID',$hex);
}

# returns as binary
sub getPNPTransactionReferenceID {
  my $self = shift;
  my $binary;
  if ($self->_getTransactionData('pnpTransactionReferenceID')) {
    $binary = PlugNPay::Util::UniqueID::fromHexToBinary($self->_getTransactionData('pnpTransactionReferenceID'));
  }
  return $binary;
}

sub generateTransactionID {
  my $self = shift;
  my $uid = new PlugNPay::Util::UniqueID();
  return $uid->inHex();
}

sub generateMerchantTransactionID {
  my $self = shift;
  my $id = new PlugNPay::Transaction::TransactionProcessor()->generateOrderID();

  return $id;
}

sub setProcessor {
  my $self = shift;
  my $processor = shift;
  
  if (ref($processor) ne 'PlugNPay::Processor') {
    die('not a processor object');
  }

  $self->{'processor'} = $processor;
}

sub getProcessor {
  my $self = shift;

  if (!defined $self->{'processor'}) {
    $self->_getProcessor();
  }

  return $self->{'processor'};
}

sub _getProcessor {
  my $self = shift;
  my $input = shift;

  my $id = $input->{'id'};
  my $handle = $input->{'shortName'};

  my $processorObject;

  if (!defined $id && !defined $handle) {
    my $ga = $self->getGatewayAccountObject();
    my $processor = $ga->getProcessorByProcMethod($self->getTransactionPaymentType());
    $processorObject = new PlugNPay::Processor({ shortName => $processor });
  } elsif (defined $id) {
    $processorObject = new PlugNPay::Processor({ id => $id });
  } elsif (defined $handle) {
    $processorObject = new PlugNPay::Processor({ shortName => $handle });
  } else {
    die('unable to determine processor');
  }

  $self->{'processor'} = $processorObject
}

sub setProcessorID {
  my $self = shift;
  my $processorID = shift;

  $self->_getProcessor({ id => $processorID });
}

sub getProcessorID {
  my $self = shift;

  if (!defined $self->{'processor'}) {
    $self->_getProcessor();
  }

  return $self->{'processor'}->getID();
}

sub setProcessorShortName {
  my $self = shift;
  my $processorShortName = shift;

  $self->_getProcessor({ shortName => $processorShortName });
}

sub getProcessorShortName {
  my $self = shift;

  if (!defined $self->{'processor'}) {
    $self->_getProcessor();
  }

  return $self->{'processor'}->getShortName();
}

################
# Vendor Token #
################
sub setVendorToken {
  my $self = shift;
  my $token = shift;
  $self->_setTransactionData('vendorToken',$token);
}

sub getVendorToken {
  my $self = shift;
  return $self->_getTransactionData('vendorToken');
}

###################
# Processor Token #
###################
sub setProcessorToken {
  my $self = shift;
  my $token = shift;
  $self->_setTransactionData('processorToken',$token);
}

sub getProcessorToken {
  my $self = shift;
  return $self->_getTransactionData('processorToken');
}

##################
# Card/ACH Token #
##################
sub setPNPToken {
  my $self = shift;
  my $PNPToken = shift;

  if (ref($self->getPayment()) =~ /PlugNPay::/) {
    $self->getPayment()->fromToken($PNPToken);
  } else {
    my $payment = $self->getTransactionPaymentType() eq 'ach' ? new PlugNPay::OnlineCheck() : new PlugNPay::CreditCard();
    $payment->fromToken($PNPToken);
  }
}

sub getPNPToken {
  my $self = shift;
  return ref($self->getPayment()) =~ /^PlugNPay::/ ? $self->getPayment()->getToken() : undef;
}

######################
# Authorization Code #
######################
sub setAuthorizationCode {
  my $self = shift;
  $self->setRawAuthorizationCode(@_);
}

sub setRawAuthorizationCode {
  my $self = shift;
  my $code = shift;
  $self->_setTransactionData('authorizationCode',$code);
}

sub getAuthorizationCode {
  my $self = shift;
  return substr($self->_getTransactionData('authorizationCode'),0,6);
}

sub getRawAuthorizationCode {
  my $self = shift;
  return $self->_getTransactionData('authorizationCode');
}

##########################
# Processor Reference ID #
##########################
sub setProcessorReferenceID{
  my $self = shift;
  my $id = shift;
  $self->_setTransactionData('processorRefID',$id);
}

sub getProcessorReferenceID {
  my $self = shift;
  return $self->_getTransactionData('processorRefID');
}

###############
# origorderid #
###############
sub setInitialOrderID {
  my $self = shift;
  my $initialOrderID = shift;
  $self->_setTransactionData('initialOrderID', $initialOrderID);
}

sub getInitialOrderID {
  my $self = shift;
  return $self->_getTransactionData('initialOrderID');
}

############
# SEC Code #
############
sub setSECCode {
  my $self = shift;
  $self->_setTransactionData('secCode',shift);
}

sub getSECCode {
  my $self = shift;
  return $self->_getTransactionData('secCode');
}

#################
# Account Codes #
#################
sub setAccountCode {
  my $self = shift;
  my $accountCodeNumber = shift;
  my $value = shift;

  # if anything exists other than 1-4, change it to a 0
  $accountCodeNumber =~ s/[^1-4]/0/g;

  if ($accountCodeNumber > 0 && $accountCodeNumber <= 4) {
    $self->_setTransactionData('accountCode' . $accountCodeNumber, $value);
  }
}

sub getAccountCode {
  my $self = shift;
  my $accountCodeNumber = shift;
  return $self->_getTransactionData('accountCode' . $accountCodeNumber);
}

sub setLogin() {
  my $self = shift;
  $self->_setTransactionData('login',shift);
}

sub getLogin() {
  my $self = shift;
  return $self->_getTransactionData('login');
}

###############
# Credit Card #
###############
sub setCreditCard {
  my $self = shift;
  $self->_setTransactionData('creditCard',shift);
}

sub getCreditCard {
  my $self = shift;
  return $self->_getTransactionData('creditCard');
}

#############
# Gift Card #
#############
sub setGiftCard {
  my $self = shift;
  $self->_setTransactionData('giftCard',shift);
}

sub getGiftCard {
  my $self = shift;
  return $self->_getTransactionData('giftCard');
}

#####################
# OnlineCheck (ACH) #
#####################
sub setOnlineCheck {
  my $self = shift;
  $self->_setTransactionData('onlineCheck',shift);
}

sub getOnlineCheck {
  my $self = shift;
  return $self->_getTransactionData('onlineCheck');
}

##########################
# Processor Data Details #
##########################

sub setProcessorDataDetails {
  my $self = shift;
  my $processorDataDetails = shift;
  $self->_setTransactionData('processorDataDetails', $processorDataDetails);
}

sub getProcessorDataDetails {
  my $self = shift;
  return $self->_getTransactionData('processorDataDetails');
}

######################################
# Get the payment regardless of type #
######################################
sub getPayment {
  my $self = shift;
  if ($self->getCreditCard()) {
    return $self->getCreditCard();
  } elsif ($self->getGiftCard()) {
    return $self->getGiftCard();
  } elsif ($self->getOnlineCheck()) {
    return $self->getOnlineCheck();
  }
  return undef;
}

sub setTransactionPaymentType {
  my $self = shift;
  my $transactionPaymentType = shift;

  $self->_setTransactionData('transactionPaymentType',$transactionPaymentType);
}

sub getTransactionPaymentType {
  my $self = shift;
  return $self->_getTransactionData('transactionPaymentType');
}


###############
# Trans Flags #
###############
sub _checkTransFlags {
  my $self = shift;
  if (!defined $self->_getTransactionData('transflags')) {
    $self->_setTransactionData('transflags',[]);
  }
}

sub addTransFlag {
  my $self = shift;
  my $flag = shift;

  $self->removeTransFlag($flag);

  push (@{$self->_getTransactionData('transflags')},lc $flag);
}

sub removeTransFlag {
  my $self = shift;
  my $flag = shift;

  $self->_checkTransFlags();

  my $lastIndex = @{$self->_getTransactionData('transflags')} - 1;
  my @indexesToRemove = grep { ${$self->_getTransactionData('transflags')}[$_] eq $flag } 0..$lastIndex;

  # delete the indexes in reverse as the array changes with each delete;
  foreach my $index (reverse @indexesToRemove) {
    splice(@{$self->_getTransactionData('transflags')},$index,1);
  }
}

sub hasTransFlag {
  my $self = shift;
  my $flag = shift;

  $self->_checkTransFlags();

  my $count = grep { /^$flag$/ } @{$self->_getTransactionData('transflags')};
  return ($count > 0);
}

sub getTransFlags {
  my $self = shift;

  $self->_checkTransFlags();
  
  if (wantarray) {
    return @{$self->_getTransactionData('transflags')};
  }
  return $self->_getTransactionData('transflags');
}

#########################
# Purchase Order Number #
#########################
sub setPurchaseOrderNumber {
  my $self = shift;
  $self->_setTransactionData('purchaseOrderNumber',shift);
}

sub getPurchaseOrderNumber {
  my $self = shift;
  return $self->_getTransactionData('purchaseOrderNumber');
}

##########################################################
# Set custom fields (transient, not stored and reloaded) #
##########################################################
sub setCustomData {
  my $self = shift;
  my $customFieldsRef = shift;
  $self->_setTransactionData('customFieldsHash',$customFieldsRef);
}

sub getCustomData {
  my $self = shift;
  return $self->_getTransactionData('customFieldsHash');
}

########################
# Set itemization data #
########################
sub setItemData {
  my$self = shift;
  my $itemFieldsRef = shift;
  $self->_setTransactionData('itemFieldsHash',$itemFieldsRef);
}

sub getItemData {
  my $self = shift;
  return $self->_getTransactionData('itemFieldsHash');
}

################################################################
# CAVV (CardholderAuthenticationVerificationValue) (3D Secure) #
################################################################
sub setCAVV {
  my $self = shift;
  $self->_setTransactionData('cavv',shift);
}

sub getCAVV {
  my $self = shift;
  $self->_getTransactionData('cavv');
}

##############################
# CAVV Algorithm (3D Secure) #
##############################
sub setCAVVAlgorithm {
  my $self = shift;
  $self->_setTransactionData('cavvAlgorithm');
}

sub getCAVVAlgorithm {
  my $self = shift;
  return $self->_getTransactionData('cavvAlgorithm');
}

####################################
# pa response (3D Secure) wirecard #
####################################
sub setPaResponse {
  my $self = shift;
  $self->_setTransactionData('paresponse');
}

sub getPaResponse {
  my $self = shift;
  return $self->_getTransactionData('paresponse');
}
###################################################
# ECI (Electronic Commerce Indicator) (3D Secure) #
###################################################
sub setECI {
  my $self = shift;
  $self->_setTransactionData('eci',shift);
}

sub getECI {
  my $self = shift;
  return $self->_getTransactionData('eci');
}

############################################
# XID (Transaction Identifier) (3D Secure) #
############################################
sub setXID {
  my $self = shift;
  $self->_setTransactionData('xid',shift);
}

sub getXID {
  my $self = shift;
  return $self->_getTransactionData('xid');
}

##############################
# Convenience Charge enabled #
##############################
sub setConvenienceChargeEnabled {
  my $self = shift;
  $self->_setTransactionData('convenienceCharge',((shift) ? 1 : 0));
}

sub getConvenienceChargeEnabled {
  my $self = shift;
  return $self->_getTransactionData('convenienceCharge');
}

sub setConvenienceChargeTransaction {
  my $self = shift;
  $self->_setTransactionData('isConvenienceChargeTransaction',1);
}

sub isConvenienceChargeTransaction {
  my $self = shift;
  return $self->_getTransactionData('isConvenienceChargeTransaction');
}

sub setConvenienceChargeTransactionLink {
  my $self = shift;
  my $convenienceChargeTransaction = shift;
  $self->_setTransactionData('convenienceChargeLink',$convenienceChargeTransaction);
}

sub getConvenienceChargeTransactionLink {
  my $self = shift;
  return $self->_getTransactionData('convenienceChargeLink');
}

sub setConvenienceChargeInfoForTransaction {
  my $self = shift;
  my $info = shift;
  $self->_setTransactionData('convenienceChargeForOrderID',$info->{'orderID'});
  $self->_setTransactionData('convenienceChargeForGatewayAccount',$info->{'gatewayAccount'});
}

sub getTransactionInfoForConvenienceCharge {
  my $self = shift;

  my $orderID = $self->_getTransactionData('convenienceChargeForOrderID');
  my $gatewayAccount =  $self->_getTransactionData('convenienceChargeForGatewayAccount');

  my $infoRef;

  if ($orderID ne '' && $gatewayAccount ne '') {
    $infoRef = {orderID => $orderID, gatewayAccount => $gatewayAccount};
  }

  return $infoRef;
}

###################
# Settlement Time #
###################
sub setTransactionMarkTime {
  my $self = shift;
  my $time = shift;
  $self->_setTransacionData('mark_time');
}

sub getTransactionMarkTime {
  my $self = shift;
  return $self->_getTransactionData('mark_time');
}

sub setTransactionSettlementTime {
  my $self = shift;
  my $time = shift;
  $self->_setTransactionData('settlement_time',$time);
}

sub getTransactionSettlementTime {
  my $self = shift;
  return $self->_getTransactionData('settlement_time');
}


#############
# Date Time #
#############
sub setTransactionDateTime {
  my $self = shift;
  my $transactionDateTime = shift;
  my $timeObject = new PlugNPay::Sys::Time();
  my $enteredFormat = $timeObject->detectFormat($transactionDateTime);

  if (!defined $transactionDateTime || !$enteredFormat) {
    $self->_setTransactionData('transactionDateTime', $timeObject->nowInFormat('iso_gm'));
  } else {
    $timeObject->fromFormat($enteredFormat, $transactionDateTime);
    $self->_setTransactionData('transactionDateTime',$timeObject->inFormat('iso_gm'));
  }

  #update setTime, important for receipts
  $self->setTime($timeObject->inFormat('unix'));
}

sub getTransactionDateTime {
  my $self = shift;
  my $format = shift || 'db_gm';
  my $timeObject = new PlugNPay::Sys::Time();
  my $transTime = $self->_getTransactionData('transactionDateTime');
  my $enteredFormat = $timeObject->detectFormat($transTime);

  if (defined $transTime && $enteredFormat) {
    $timeObject->fromFormat($enteredFormat, $transTime);
    $self->_setTransactionData('transactionDateTime', $timeObject->inFormat('iso_gm'));
  } else {
    $self->_setTransactionData('transactionDateTime',$timeObject->nowInFormat('iso_gm'));
  }

  return $timeObject->inFormat($format);
}

############
# Priority #
############

sub setProcessingPriority {
  my $self = shift;
  my $ProcessingPriority = shift;
  $self->{'processingPriority'} = $ProcessingPriority;
}

sub getProcessingPriority {
  my $self = shift;
  my $priority = $self->{'processingPriority'};
  if (!defined $priority || $priority eq '') {
    $priority = '5';
  }

  return $priority;
}

##############
# Extra Data #
##############

sub setExtraTransactionData {
  my $self = shift;
  my $extra_transaction_data = shift;
  $self->{'extra_transaction_data'} = $extra_transaction_data;
}

sub getExtraTransactionData {
  my $self = shift;
  return $self->{'extra_transaction_data'} || {};
}

###################################
# Transaction Data Helper Methods #
###################################
sub _setTransactionData {
  my $self = shift;
  my $key = shift;
  my $value = shift;
  $self->{'transactionData'}{$key} = $value;
}

sub _getTransactionData {
  my $self = shift;
  return  $self->{'transactionData'}{shift || ''};
}

sub getAllTransactionData {
  my $self = shift;
  return $self->{'transactionData'};
}

####################
# Validation Error #
####################
sub setValidationError {
  my $self = shift;

  if (ref($self->{'validationError'}) ne 'ARRAY') {
    $self->{'validationError'} = [];
  }

  push @{$self->{'validationError'}},shift;
}

sub getValidationError {
  my $self = shift;
  if (ref($self->{'validationError'}) eq 'ARRAY') {
    return join('  ',@{$self->{'validationError'}});
  }
}

sub setPreAuthAmount {
  my $self = shift;
}

sub getPreAuthAmount {
  my $self = shift;
}

sub setToAsynchronous {
  my $self = shift;
  my $runAsync = 1;
  $self->{'runAsync'} = $runAsync;
}

sub setToSynchronous {
  my $self = shift;
  my $runAsync = 0;

  $self->{'runAsync'} = $runAsync;
}

sub isAsynchronous {
  my $self = shift;
  return $self->{'runAsync'};
}

#################
# Trans History #
#################

sub setHistory {
  my $self = shift;
  my $history = shift;
  $self->_setTransactionData('generatedHistory', $history);
}

sub getHistory {
  my $self = shift;
  return $self->_getTransactionData('generatedHistory') || {};
}

##############
## Response ##
##############
sub setResponse {
  my $self = shift;
  my $response = shift;
  # not stored in transactionData so it doesn't get cloned.
  $self->{'response'} = $response;
}

sub getResponse {
  my $self = shift;
  return $self->{'response'};
}

##############
# Fraud     ##
##############
sub setIgnoreCVVResponse {
  my $self = shift;
  $self->{'ignoreCVVResponse'} = 1;
}

sub getIgnoreCVVResponse {
  my $self = shift;
  return $self->{'ignoreCVVResponse'};
}

sub setIgnoreFraudCheckResponse {
  my $self = shift;
  $self->{'ignoreFraudCheckResponse'} = 1;
}

sub getIgnoreFraudCheckResponse {
  my $self = shift;
  return $self->{'ignoreFraudCheckResponse'};
}

sub setFraudConfig {
  my $self = shift;
  my $fraudConfig = shift;
  $self->{'fraud_config'} = $fraudConfig;
}

sub getFraudConfig {
  my $self = shift;
  return $self->{'fraud_config'};
}

sub setReason {
  my $self = shift;
  my $reason = shift;
  $self->{'reason'} = $reason;
}

sub getReason {
  my $self = shift;
  return $self->{'reason'};
}

sub setReceiptSendingEmailAddress {
  my $self = shift;
  my $address = shift;
  $self->_setTransactionData('receiptSendingEmailAddress',$address);
}

sub getReceiptSendingEmailAddress {
  my $self = shift;
  return $self->_getTransactionData('receiptSendingEmailAddress') || '';
}

sub getTransactionVersion {
  my $self = shift;
  if (!$self->{'transactionVersion'}) {
    my $processorId = $self->getProcessorID();
    if (!defined $processorId) {
      die('can not determine transaction version without processor id');
    }
    my $processorInfo = new PlugNPay::Processor({ id => $processorId });
    $self->{'transactionVersion'} = $processorInfo->getUsesPnpTransaction() ? 'unified' : 'legacy';
  }
  return $self->{'transactionVersion'};
}

sub setExistsInDatabase {
  my $self = shift;
  $self->{'existsInDatabase'} = 1;
}

# returns wether or the transaction is known to exist in the database.
# use only to verify existence, not non-existence.
sub existsInDatabase {
  my $self = shift;
  return $self->{'existsInDatabase'} ? 1 : 0;
}

# Set order object transaction belongs to
sub setOrder {
  my $self = shift;
  my $order = shift;
  if (ref($order) eq 'PlugNPay::Order') {
    $self->{'order'} = $order;
  }
  die('attempt to set a non-order object as value of order in transaction object');
}

# Get order object transaction belongs to, undef if it is not an order
sub getOrder {
  my $self = shift;
  if (ref($self->{'order'}) eq 'PlugNPay::Order') {
    return $self->{'order'};
  }
  return undef;
}

sub void {
  my $self = shift;
  $self->setTransactionState('VOID_PENDING');
  $self->setTransactionMode('void');
  $self->setTransactionType('void');
}

sub _withPreceision {
  my $self = shift;
  my $amount = shift;

  my $precision = new PlugNPay::Currency($self->getCurrency())->getPrecision();
  $amount = sprintf('%.' . $precision . 'f',$amount + .00001);

  return $amount;
}

#############################
## END SETTERS AND GETTERS ##
#############################



1;
