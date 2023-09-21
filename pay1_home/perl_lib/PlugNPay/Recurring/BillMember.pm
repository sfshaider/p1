package PlugNPay::Recurring::BillMember;

use strict;
use PlugNPay::Util;
use PlugNPay::Contact;
use PlugNPay::Processor;
use PlugNPay::Sys::Time;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::Transaction;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::JSON;
use PlugNPay::Recurring::Profile;
use PlugNPay::Recurring::Attendant;
use PlugNPay::CreditCard::Encryption;
use PlugNPay::OnlineCheck::Encryption;
use PlugNPay::Recurring::PaymentSource;
use PlugNPay::Transaction::Response::JSON;
use PlugNPay::Transaction::TransactionProcessor;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub getTransactionResult {
  my $self = shift;
  return $self->{'transactionResult'};
}

sub setTransactionObject {
  my $self = shift;
  my $transObj = shift;
  $self->{'transaction'} = $transObj;
}

sub getTransactionObject {
  my $self = shift;
  return $self->{'transaction'};
}

sub billMember {
  my $self = shift;
  my $merchant = shift;
  my $customer = shift;
  my $billingOptions = shift;

  my $databaseName = $billingOptions->{'databaseName'} || $merchant;
  my $sendEmailReceipt = $billingOptions->{'sendEmailReceipt'} || 1;

  my $dbs = new PlugNPay::DBConnection();

  my ($transID, $orderID);
  my ($status, $errorMsg, $responseMessage);
  my $transactionStatus = 'problem'; # default status, get's overridden by transaction result
  eval {
    if (!PlugNPay::Recurring::Username::exists({ merchant => $merchant, username => $customer })) {
      $errorMsg = 'Failed to bill member. Customer does not exist.';
      die($errorMsg);
    }

    my $contact;
    my $shippingContact;
    my $accountCode = '';

    my $ga = new PlugNPay::GatewayAccount($customer);
    if ($merchant eq 'pnpbilling') {
      $contact = $ga->getBillingContact();
      $shippingContact = $ga->getBillingContact();
    } else {
      my $profile = new PlugNPay::Recurring::Profile();
      if (!$profile->load($databaseName, $customer)) {
        $errorMsg = 'Failed to bill member. Unable to load existing profile.';
        die($errorMsg);
      }

      $contact = new PlugNPay::Contact();
      $contact->setFullName($profile->getName());
      $contact->setAddress1($profile->getAddress1());
      $contact->setAddress2($profile->getAddress2());
      $contact->setCity($profile->getCity());
      $contact->setState($profile->getState());
      $contact->setPostalCode($profile->getPostalCode());
      $contact->setCountry($profile->getCountry());
      $contact->setCompany($profile->getCompany());
      $contact->setEmailAddress($profile->getEmail());
      $contact->setPhone($profile->getPhone()) ;

      $shippingContact = new PlugNPay::Contact();
      $shippingContact->setFullName($profile->getShippingName());
      $shippingContact->setAddress1($profile->getShippingAddress1());
      $shippingContact->setAddress2($profile->getShippingAddress2());
      $shippingContact->setCity($profile->getShippingCity());
      $shippingContact->setState($profile->getShippingState());
      $shippingContact->setPostalCode($profile->getShippingPostalCode());
      $shippingContact->setCountry($profile->getShippingCountry());
      $shippingContact->setPhone($profile->getPhone());

      $accountCode = $profile->getAccountCode();
    }

    my $paymentSource = new PlugNPay::Recurring::PaymentSource();
    if (!$paymentSource->loadPaymentSource($merchant, $customer)) {
      $errorMsg = 'Failed to bill member. Unable to load payment source information.';
      die $errorMsg;
    }

    my $transaction = new PlugNPay::Transaction('auth', $paymentSource->getPaymentSourceType());
    $self->setTransactionObject($transaction);
    $transaction->setGatewayAccount($merchant);
    $transaction->setBillingInformation($contact);
    $transaction->setShippingInformation($shippingContact);

    if ((grep { $_ eq $paymentSource->getPaymentSourceType() } ('card','credit')) > 0) {
      my $cardNumber = $paymentSource->getCardNumber();
      my $cc = new PlugNPay::CreditCard($cardNumber);
      $cc->setName($contact->getName());
      $cc->setExpirationMonth($paymentSource->getExpMonth());
      $cc->setExpirationYear($paymentSource->getExpYear());
      $cc->setSecurityCode($billingOptions->{'cvv'});
      $transaction->setPNPToken($cc->getToken());
      $transaction->setCreditCard($cc);

      # set the processor id on the transaction object.
      my $procName = $ga->getCardProcessor();
      my $processor = new PlugNPay::Processor({ shortName => $procName });
      my $procId = $processor->getID();
      $transaction->setProcessorID($procId);
    } elsif ((grep { $_ eq $paymentSource->getPaymentSourceType() } ('ach','checking','savings')) > 0) {
      my $accountInfo = new PlugNPay::OnlineCheck::Encryption()->decrypt($paymentSource->getEncCardNumber());

      my $ach = new PlugNPay::OnlineCheck();
      $ach->setABARoutingNumber($accountInfo->{'routing'});
      $ach->setAccountNumber($accountInfo->{'account'});
      $transaction->setPNPToken($ach->getToken());
      $transaction->setOnlineCheck($ach);

      # set the processor id on the transaction object.
      my $procName = $ga->getACHProcessor();
      my $processor = new PlugNPay::Processor({ shortName => $procName });
      my $procId = $processor->getID();
      $transaction->setProcessorID($procId);
    } else {
      $errorMsg = 'Failed to bill member. Unsupported payment type.';
      die $errorMsg;
    }

    my $amount = $billingOptions->{'amount'};
    $amount =~ s/[^0-9\.]//g;
    if ($amount !~ /^\d*\.?\d+$/) {
      $errorMsg = 'Failed to bill member. Invalid amount.';
      die($errorMsg);
    }

    my $taxAmount = $billingOptions->{'tax'} || 0;
    if ($taxAmount) {
      if ($taxAmount !~ /^\d*\.?\d+$/) {
        $errorMsg = 'Failed to bill member. Invalid tax amount.';
        die $errorMsg;
      }
    }

    $transaction->setTransactionAmount($amount);
    $transaction->setTaxAmount($taxAmount);

    if ($billingOptions->{'recInit'}) {
      $transaction->addTransFlag('recinit');
    } elsif ($billingOptions->{'recurring'}) {
      $transaction->addTransFlag('recurring');
    } else {
      my $initialOrderID = $paymentSource->getOrderID();
      $transaction->setInitialOrderID($initialOrderID);
    }

    $transaction->setAccountCode(1, $billingOptions->{'acctCode1'} || $accountCode);
    $transaction->setAccountCode(2, $billingOptions->{'acctCode2'} || '');
    $transaction->setAccountCode(3, $billingOptions->{'acctCode3'} || '');

    if ($billingOptions->{'merchantClassifierID'}) {
      $transaction->setMerchantClassifierID($billingOptions->{'merchantClassifierID'});
    }

    $transaction->setAccountCode(4,$databaseName . ':' . $customer);

    my $transactionProcessor = new PlugNPay::Transaction::TransactionProcessor();
    my $result = $transactionProcessor->process($transaction,{sendEmailReceipt => $sendEmailReceipt});
    $self->{'transactionResult'} = $result;

    my $transactionJSON = new PlugNPay::Transaction::JSON();
    my $transactionResponseJSON = new PlugNPay::Transaction::Response::JSON();

    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_attendant' });
    $logger->log({
      'billmember' => {
         'request'  => $transactionJSON->transactionToJSON($transaction),
         'response' => $transactionResponseJSON->responseToJSON($result)
       },
       'merchant'     => $merchant,
       'customer'     => $customer,
       'description'  => $billingOptions->{'description'},
       'databaseName' => $billingOptions->{'databaseName'}
    });

    my $trans = $result->getTransaction();
    if ($merchant eq 'pnpbilling') {

      # do we do anything when billing merchants?
    } else {
      $self->insertBillingEntry($merchant, $customer, {
        'result'          => $result->getStatus(),
        'orderID'         => $trans->getOrderID(),
        'amount'          => $transaction->getTransactionAmount(),
        'description'     => $billingOptions->{'description'} || 'Remote Member Billing',
        'databaseName'    => $billingOptions->{'databaseName'},
        'transactionDate' => new PlugNPay::Sys::Time('db', $transaction->getTransactionDateTime())->inFormat('yyyymmdd')
      });
    }

    $orderID = $trans->getOrderID();
    $transID = $trans->getPNPTransactionID();

    $transactionStatus = $result->getStatus();

    if (&PlugNPay::Processor::usesUnifiedProcessing($trans->getProcessor(), $trans->getTransactionPaymentType())) {
      if ($transID !~ /^[a-fA-F0-9]+$/) {
        $transID = PlugNPay::Util::UniqueID::fromBinaryToHex($transID);
      }
    } else {
      $transID = $trans->getOrderID();
    }

    if ($result->getStatus() =~ /success/) {
      $status = 1;
    } else {
      $status = 0;
      $responseMessage = $result->getErrorMessage();
    }
  };

  if ($@) {
    if (!$errorMsg) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_attendant' });
      my (undef,$logID) = $logger->log({
        'customer' => $customer,
        'merchant' => $merchant,
        'subroutine' => 'billMember',
        'error' => $@
      });

      $errorMsg = 'Failed to bill member.  System error.  Contact support logID: ' . $logID;
    }

    return {
      status => 0,
      transactionStatus => $transactionStatus,
      transactionDetails => $self->getTransactionObject(),
      message => $errorMsg
    };
  }

  # get masked card number from transaction object
  my $maskedCardNumber;
  if ($self->getTransactionObject()) {
    $maskedCardNumber = $self->getTransactionObject()->getPayment()->getMaskedNumber();
  }

  return {
    'status' => 1,
    'transactionStatus' => $transactionStatus,
    'billed' => $status,
    'message' => $responseMessage,
    'maskedCardNumber' => $maskedCardNumber,
    'transactionDetails' => {
      'orderID' => $orderID,
      'pnpTransactionID' => $transID
    }
  };
}

sub insertBillingEntry {
  my $self = shift;
  my $merchant = shift;
  my $customer = shift;
  my $billingInfo = shift;

  my $databaseName = $billingInfo->{'databaseName'} || $merchant;

  my $errorMsg;
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare($databaseName, q/INSERT INTO billingstatus
                                         ( username,
                                           orderid,
                                           trans_date,
                                           amount,
                                           descr,
                                           result,
                                           billusername )
                                         VALUES (?,?,?,?,?,?,?)/) or die $DBI::errstr;
    $sth->execute($customer,
                  $billingInfo->{'orderID'},
                  $billingInfo->{'transactionDate'},
                  $billingInfo->{'amount'},
                  $billingInfo->{'description'} || 'Remote bill member.',
                  $billingInfo->{'result'},
                  $billingInfo->{'databaseName'}) or die $DBI::errstr;
  };

  if ($@) {
    if (!$errorMsg) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_attendant' });
      $logger->log({
        'customer' => $customer,
        'merchant' => $merchant,
        'database' => $databaseName,
        'subroutine' => 'insertBillingEntry',
        'error' => $@
      });
      $errorMsg = 'Failed to save billing status entry.';
    }

    return { 'status' => 0, 'errorMessage' => $errorMsg };
  }

  return { 'status' => 1 };
}

1;
