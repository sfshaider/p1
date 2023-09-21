#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::Transaction;
use Data::Dumper;
my $trans;

#NOW TO SHOW YOU MY FINAL FORM
$trans = new PlugNPay::Transaction('credit','credit'); #We made a credit card return
##$trans->clone();
##$trans->cloneTransactionData();
##$trans->loadTransaction();
#$trans->setGatewayAccount();
#$trans->getGatewayAccount();
#$trans->setIPAddress();
#$trans->getIPAddress();
#$trans->setTransactionType();
#$trans->getTransactionType();
#$trans->setTransactionState();
#$trans->getTransactionState();
#$trans->setPostAuth();
#$trans->unsetPostAuth();
#$trans->doPostAuth();
#$trans->setSale();
#$trans->unsetSale();
#$trans->doSale();
#$trans->setCurrency();
#$trans->getCurrency();
#$trans->setTransactionAmount();
#$trans->getTransactionAmount();
#$trans->setBaseTransactionAmount();
#$trans->getBaseTransactionAmount();
#$trans->setTransactionAmountAdjustment();
#$trans->getTransactionAmountAdjustment();
#$trans->adjustmentIsSurcharge();
#$trans->isAdjustmentSurcharge();
#$trans->setOverrideAdjustment();
#$trans->getOverrideAdjustment();
#$trans->setSettlementAmount();
#$trans->getSettlementAmount();
#$trans->setSettledAmount();
#$trans->getSettledAmount();
#$trans->setTime();
#$trans->getTime();
#$trans->setTaxAmount();
#$trans->getTaxAmount();
#$trans->setBaseTaxAmount();
#$trans->getBaseTaxAmount();
#$trans->getEffectiveTaxRate();
#$trans->setSettledTaxAmount();
#$trans->getSettledTaxAmount();
#$trans->setBillingInformation();
#$trans->getBillingInformation();
#$trans->setShippingInformation();
#$trans->getShippingInformation();
#$trans->setShippingNotes();
#$trans->getShippingNotes();
#$trans->setPNPOrderID();
#$trans->getPNPOrderID();
#$trans->setMerchantTransactionID();
#$trans->getMerchantTransactionID();
#$trans->setOrderID();
#$trans->getOrderID();
#$trans->setMerchantClassifierID();
#$trans->getMerchantClassifierID();
#$trans->setPNPTransactionID();
#$trans->verifyTransactionID();
#$trans->getPNPTransactionID();
#$trans->setPNPTransactionReferenceID();
#$trans->getPNPTransactionReferenceID();
#$trans->generateTransactionID();
#$trans->generateMerchantTransactionID();
#$trans->setVendorToken();
#$trans->getVendorToken();
#$trans->setProcessorToken();
#$trans->getProcessorToken();
#$trans->setPNPToken();
#$trans->getPNPToken();
$trans->setAuthorizationCode('1234567890----0-');
print $trans->getAuthorizationCode();
#$trans->setProcessorReferenceID
#$trans->getProcessorReferenceID();
#$trans->setSECCode();
#$trans->getSECCode();
#$trans->setAccountCode();
#$trans->getAccountCode();
#$trans->setCreditCard();
#$trans->getCreditCard();
#$trans->setGiftCard();
#$trans->getGiftCard();
#$trans->setOnlineCheck();
#$trans->getOnlineCheck();
#$trans->setProcessorDataDetails();
#$trans->getProcessorDataDetails();
#$trans->getPayment();
#$trans->getTransactionPaymentType();
#$trans->_checkTransFlags();
#$trans->addTransFlag();
#$trans->removeTransFlag();
#$trans->hasTransFlag();
#$trans->getTransFlags();
#$trans->setPurchaseOrderNumber();
#$trans->getPurchaseOrderNumber();
#$trans->setCustomData();
#$trans->getCustomData();
#$trans->setItemData();
#$trans->getItemData();
#$trans->setCAVV();
#$trans->getCAVV();
#$trans->setCAVVAlgorithm();
#$trans->getCAVVAlgorithm();
#$trans->setECI();
#$trans->getECI();
#$trans->setXID();
#$trans->getXID();
#$trans->setConvenienceChargeEnabled();
#$trans->getConvenienceChargeEnabled();
#$trans->setConvenienceChargeTransaction();
#$trans->isConvenienceChargeTransaction();
#$trans->setConvenienceChargeTransactionLink();
#$trans->getConvenienceChargeTransactionLink();
#$trans->setConvenienceChargeInfoForTransaction();
#$trans->getTransactionInfoForConvenienceCharge();
#$trans->setTransactionSettlementTime();
#$trans->getTransactionSettlementTime();
#$trans->setTransactionDateTime();
#$trans->getTransactionDateTime();
#$trans->setProcessingPriority();
#$trans->getProcessingPriority();
#$trans->setExtraTransactionData();
#$trans->getExtraTransactionData();
#$trans->_setTransactionData();
#$trans->_getTransactionData();
#$trans->getAllTransactionData();
#$trans->setValidationError();
#$trans->getValidationError();
#$trans->setPreAuthAmount();
#$trans->getPreAuthAmount();
#$trans->authPrev();

print "\n";
exit;
