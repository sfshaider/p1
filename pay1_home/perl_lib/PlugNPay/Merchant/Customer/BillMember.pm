package PlugNPay::Merchant::Customer::BillMember;

use strict;
use PlugNPay::Util;
use PlugNPay::Contact;
use PlugNPay::Merchant;
use PlugNPay::Sys::Time;
use PlugNPay::CreditCard;
use PlugNPay::Transaction;
use PlugNPay::OnlineCheck;
use PlugNPay::Util::Status;
use PlugNPay::GatewayAccount;
use PlugNPay::Logging::DataLog;
use PlugNPay::Merchant::Customer;
use PlugNPay::Membership::Plan::Type;
use PlugNPay::Merchant::Customer::Link;
use PlugNPay::Merchant::Customer::History;
use PlugNPay::Merchant::Customer::Address;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Merchant::Customer::PaymentSource;
use PlugNPay::Merchant::Customer::Address::Expose;
use PlugNPay::Merchant::Customer::PaymentSource::Type;
use PlugNPay::Merchant::Customer::PaymentSource::Expose;
use PlugNPay::Merchant::Customer::PaymentSource::ACH::Type;

#############################################
# Module: Merchant::Customer::BillMember
# -------------------------------------------
# Description:
#   Bill member module for billing customers.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

###############################################
# Subroutine: billCustomer
# ---------------------------------------------
# Description:
#   Bills a merchant customer.
sub billCustomer {
  my $self = shift;
  my $merchantCustomerLinkID = shift;
  my $customerPaymentSource = shift;
  my $billingOptions = shift;

  my $billStatus = new PlugNPay::Util::Status(1);
  my $transactionData = {};
  my @errorMsg;

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
  $merchantCustomer->loadMerchantCustomer($merchantCustomerLinkID);

  # transaction type if profile being billed
  my $transType = $billingOptions->{'transactionType'};
  if ($transType !~ /^(auth|credit)$/i) {
    push (@errorMsg, 'Invalid transaction type.');
  }

  # validate amount
  my $amount = $billingOptions->{'amount'};
  if ($amount !~ /^\d*\.?\d+$/) {
    push (@errorMsg, 'Invalid amount.');
  }

  my $tax = $billingOptions->{'tax'} || 0;
  if ($tax !~ /^\d*\.?\d+$/) {
    push (@errorMsg, 'Invalid tax amount.');
  }

  my ($gatewayAccount, $billingAccountID);  
  if ($billingOptions->{'billingAccount'}) {
    $gatewayAccount = new PlugNPay::GatewayAccount($billingOptions->{'billingAccount'});
    $billingAccountID = new PlugNPay::Merchant($billingOptions->{'billingAccount'})->getMerchantID();
  } else {
    $gatewayAccount = new PlugNPay::GatewayAccount(new PlugNPay::Merchant($merchantCustomer->getMerchantID())->getMerchantUsername());
    $billingAccountID = $merchantCustomer->getMerchantID();
  }

  my $paymentSource; 
  if (ref ($customerPaymentSource) =~ /^PlugNPay::Merchant::Customer::PaymentSource/) {
    $paymentSource = $customerPaymentSource;
  } elsif ($customerPaymentSource) {
    my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
    $exposePaymentSource->loadByLinkIdentifier($customerPaymentSource, $merchantCustomerLinkID);
    if (!$exposePaymentSource->getLinkID()) {
      push (@errorMsg, 'Invalid payment source identifier.');
    }

    $paymentSource = new PlugNPay::Merchant::Customer::PaymentSource();
    $paymentSource->loadPaymentSource($exposePaymentSource->getPaymentSourceID());
  } else {
    push (@errorMsg, 'Invalid payment source.');
  }

  if (@errorMsg == 0) {
    my $paymentSourceType = new PlugNPay::Merchant::Customer::PaymentSource::Type();
    $paymentSourceType->loadPaymentType($paymentSource->getPaymentSourceTypeID());
    my $paymentType = $paymentSourceType->getPaymentType();

    my $planType = new PlugNPay::Membership::Plan::Type();
    $planType->loadPlanTypeID($transType);
    my $transTypeID = $planType->getTypeID();

    my $transaction = new PlugNPay::Transaction($transType, $paymentType);
    $transaction->setGatewayAccount($gatewayAccount);

    # load customer address
    my $exposeAddress = new PlugNPay::Merchant::Customer::Address::Expose();
    $exposeAddress->loadExposedAddress($paymentSource->getBillingAddressID());

    my $billingInfo = new PlugNPay::Merchant::Customer::Address();
    $billingInfo->loadAddress($exposeAddress->getAddressID());

    my $contact = new PlugNPay::Contact();
    $contact->setFullName($billingInfo->getName());
    $contact->setAddress1($billingInfo->getLine1());
    $contact->setAddress2($billingInfo->getLine2());
    $contact->setCity($billingInfo->getCity());
    $contact->setState($billingInfo->getStateProvince());
    $contact->setPostalCode($billingInfo->getPostalCode());
    $contact->setCountry($billingInfo->getCountry());
    $contact->setCompany($billingInfo->getCompany());
    $transaction->setBillingInformation($contact);

    # name from address or customer
    my $customerName = $billingInfo->getName() || $merchantCustomer->getName();

    # set payment information
    if ($paymentType =~ /card/i) {
      my $card = new PlugNPay::CreditCard();
      $card->setName($customerName);
      eval {
        $card->fromToken($paymentSource->getToken());
      };
      $card->setExpirationMonth($paymentSource->getExpirationMonth());
      $card->setExpirationYear($paymentSource->getExpirationYear());
      $transaction->setCreditCard($card);
    } else {
      my $paymentSourceACHType = new PlugNPay::Merchant::Customer::PaymentSource::ACH::Type();
      $paymentSourceACHType->loadACHAccountType($paymentSource->getAccountTypeID());

      my $check = new PlugNPay::OnlineCheck();
      $check->setName($customerName);
      eval {
        $check->fromToken($paymentSource->getToken());
      };
      $check->setAccountType($paymentSourceACHType->getAccountType());

      $transaction->setOnlineCheck($check);
    }

    if (!$@) {
      # set trans flags
      if ($billingOptions->{'transflags'}) {
        if (ref($billingOptions->{'transflags'}) =~ /ARRAY/) {
          foreach my $transFlag (@{$billingOptions->{'transflags'}}) {
            $transaction->addTransFlag($transFlag);
          }
        }
      }

      # set transaction amount
      $transaction->setTransactionAmount($amount);
      $transaction->setTaxAmount($tax);

      # set transaction currency
      $transaction->setCurrency($billingOptions->{'currency'} || 'USD');

      # set transaction time
      my $transTime = new PlugNPay::Sys::Time();
      $transaction->setTime($transTime->inFormat('unix'));

      # process the transaction
      my $transactionProcessor = new PlugNPay::Transaction::TransactionProcessor();
      my $transactionResponse = $transactionProcessor->process($transaction, { 'sendEmailReceipt' => ($gatewayAccount->getFeatures()->get('sendEmailReceipt') ? 1 : 0) });

      # save in customer history
      my $history = new PlugNPay::Merchant::Customer::History();
      if ($transactionResponse->getStatus() !~ /success/i) {
        $history->saveHistoryEntry($merchantCustomerLinkID, {
          'transactionStatus' => $transactionResponse->getStatus(),
          'transactionAmount' => $transaction->getTransactionAmount(),
          'transactionTypeID' => $transTypeID,
          'transactionDate'   => $transTime->inFormat('iso'),
          'description'       => $billingOptions->{'description'} || 'Bill Member',
          'billingAccountID'  => $billingAccountID
        });

        push (@errorMsg, 'Transaction was not successful. ' . $transactionResponse->getErrorMessage());
      } else {
        $history->saveHistoryEntry($merchantCustomerLinkID, {
          'transactionStatus' => $transactionResponse->getStatus(),
          'transactionAmount' => $transaction->getTransactionAmount(),
          'orderID'           => $transactionResponse->getTransaction()->getOrderID(),
          'transactionID'     => $transactionResponse->getTransaction()->getPNPTransactionID(),
          'transactionTypeID' => $transTypeID,
          'transactionDate'   => $transTime->inFormat('iso'),
          'description'       => $billingOptions->{'description'} || 'Bill Member',
          'billingAccountID'  => $billingAccountID
        });

        $transactionData = {
          'authorizationCode' => $transactionResponse->getAuthorizationCode(),
          'orderID'           => $transactionResponse->getTransaction()->getOrderID(),
          'transactionID'     => $transactionResponse->getTransaction()->getPNPTransactionID(),
          'status'            => $transactionResponse->getStatus(),
          'message'           => $transactionResponse->getErrorMessage()
        };
      }
    }  
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_billmember' });
      $logger->log({
        'function'                => 'billCustomer',
        'error'                   => $@,
        'merchantCustomerLinkID'  => $merchantCustomerLinkID,
        'transactionData'         => $billingOptions
      });

      push (@errorMsg, 'Error while attempting to bill member.');
    }

    $billStatus->setFalse();
    $billStatus->setError(join(' ', @errorMsg));
  }

  return { 'status' => $billStatus, 'transactionDetails' => $transactionData };
}

1;
