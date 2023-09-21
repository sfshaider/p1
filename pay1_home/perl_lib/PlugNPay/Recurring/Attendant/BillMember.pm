package PlugNPay::Recurring::Attendant::BillMember;

use strict;
use PlugNPay::Contact;
use PlugNPay::Sys::Time;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::Transaction;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Recurring::Attendant;
use PlugNPay::CreditCard::Encryption;
use PlugNPay::OnlineCheck::Encryption;
use PlugNPay::Recurring::Attendant::Profile;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Recurring::Attendant::PaymentSource;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub billMember {
  my $self = shift;
  my $customer = lc shift;
  my $merchant = shift;
  my $billOptions = shift;
  my $saveProfile = shift;
  my $savePaymentSource = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $errorMsg;
  eval {
    $dbs->begin($merchant);

    my $billingInformation  = {};
    my $shippingInformation = {};
    my $paymentInformation  = {};

    #####################################################
    # If customer exist, update member, else add member #
    #####################################################
    my $attendant = new PlugNPay::Recurring::Attendant();
    if ($attendant->doesCustomerExist($merchant, $customer)) {
      my $profile = new PlugNPay::Recurring::Attendant::Profile();
      $profile->loadProfile($customer, $merchant);

      my $paymentSource = new PlugNPay::Recurring::Attendant::PaymentSource();

      if ($saveProfile) {
        my $updateProfileStatus = $profile->updateProfile($billOptions->{'profile'}, $customer, $merchant);
        if (!$updateProfileStatus->{'status'}) {
          $errorMsg = 'Failed to bill member. ' . $updateProfileStatus->{'errorMessage'};
          die;
        }

        if ($savePaymentSource) {
          if (!$paymentSource->updatePaymentSource($merchant, $customer, $billOptions->{'payment'})) {
            $errorMsg = 'Unable to bill member. Failed to update payment source.';
            die;
          }
        }
      }

      $billingInformation->{'name'}    = $billOptions->{'profile'}{'name'}    || $profile->getName();
      $billingInformation->{'addr1'}   = $billOptions->{'profile'}{'addr1'}   || $profile->getAddr1();
      $billingInformation->{'addr2'}   = $billOptions->{'profile'}{'addr2'}   || $profile->getAddr2();
      $billingInformation->{'city'}    = $billOptions->{'profile'}{'city'}    || $profile->getCity();
      $billingInformation->{'state'}   = $billOptions->{'profile'}{'state'}   || $profile->getState();
      $billingInformation->{'zip'}     = $billOptions->{'profile'}{'zip'}     || $profile->getZip();
      $billingInformation->{'country'} = $billOptions->{'profile'}{'country'} || $profile->getCountry();
      $billingInformation->{'company'} = $billOptions->{'profile'}{'company'} || $profile->getCompany();

      $shippingInformation->{'name'}    = $billOptions->{'profile'}{'shippingName'}    || $profile->getShippingName();
      $shippingInformation->{'addr1'}   = $billOptions->{'profile'}{'shippingAddr1'}   || $profile->getShippingAddr1();
      $shippingInformation->{'addr2'}   = $billOptions->{'profile'}{'shippingAddr2'}   || $profile->getShippingAddr2();
      $shippingInformation->{'city'}    = $billOptions->{'profile'}{'shippingCity'}    || $profile->getShippingCity();
      $shippingInformation->{'state'}   = $billOptions->{'profile'}{'shippingState'}   || $profile->getShippingState();
      $shippingInformation->{'zip'}     = $billOptions->{'profile'}{'shippingZip'}     || $profile->getShippingZip();
      $shippingInformation->{'country'} = $billOptions->{'profile'}{'shippingCountry'} || $profile->getShippingCountry();

      $paymentSource->loadPaymentSource($merchant, $customer);
      my $type = $billOptions->{'payment'}{'type'} || $paymentSource->getPaymentSourceType();
      if ($type =~ /card/i) {
        my $cardNumber;
        if ($paymentSource->getEncCardNumber()) {
          $cardNumber = new PlugNPay::CreditCard::Encryption()->decrypt($paymentSource->getEncCardNumber());
        }

        $paymentInformation->{'cardNumber'}      = $billOptions->{'payment'}{'cardNumber'} || $cardNumber;
        $paymentInformation->{'expirationMonth'} = $billOptions->{'payment'}{'expMonth'}   || $paymentSource->getExpMonth();
        $paymentInformation->{'expirationYear'}  = $billOptions->{'payment'}{'expYear'}    || $paymentSource->getExpYear();
      } else {
        my $accountInfo = {}; 
        if ($paymentSource->getEncCardNumber()) {
          $accountInfo = new PlugNPay::OnlineCheck::Encryption()->decrypt($paymentSource->getEncCardNumber());
        }

        $paymentInformation->{'routingNumber'}   = $billOptions->{'payment'}{'routingNumber'} || $accountInfo->{'routing'};
        $paymentInformation->{'accountNumber'}   = $billOptions->{'payment'}{'accountNumber'} || $accountInfo->{'account'};
      }
    } else {
      if ($saveProfile) {
        my $profile = new PlugNPay::Recurring::Attendant::Profile();
        my $saveProfileStatus = $profile->saveProfile($billOptions->{'profile'}, $customer, $merchant);
        if (!$saveProfileStatus->{'status'}) {
          $errorMsg = 'Failed to bill member. ' . $saveProfileStatus->{'errorMessage'};
          die;
        }

        if ($savePaymentSource) {
          my $paymentSource = new PlugNPay::Recurring::Attendant::PaymentSource();
          if (!$paymentSource->updatePaymentSource($merchant, $customer, $billOptions->{'payment'})) {
            $errorMsg = 'Unable to bill member. Failed to save payment source.';
            die;
          }
        }
      }

      $billingInformation->{'name'}    = $billOptions->{'profile'}{'name'};
      $billingInformation->{'addr1'}   = $billOptions->{'profile'}{'addr1'};
      $billingInformation->{'addr2'}   = $billOptions->{'profile'}{'addr2'};
      $billingInformation->{'city'}    = $billOptions->{'profile'}{'city'};
      $billingInformation->{'state'}   = $billOptions->{'profile'}{'state'};
      $billingInformation->{'zip'}     = $billOptions->{'profile'}{'zip'};
      $billingInformation->{'country'} = $billOptions->{'profile'}{'country'};
      $billingInformation->{'company'} = $billOptions->{'profile'}{'company'};

      $shippingInformation->{'name'}    = $billOptions->{'profile'}{'shippingName'};
      $shippingInformation->{'addr1'}   = $billOptions->{'profile'}{'shippingAddr1'};
      $shippingInformation->{'addr2'}   = $billOptions->{'profile'}{'shippingAddr2'};
      $shippingInformation->{'city'}    = $billOptions->{'profile'}{'shippingCity'};
      $shippingInformation->{'state'}   = $billOptions->{'profile'}{'shippingState'};
      $shippingInformation->{'zip'}     = $billOptions->{'profile'}{'shippingZip'};
      $shippingInformation->{'country'} = $billOptions->{'profile'}{'shippingCountry'};

      my $type = $billOptions->{'payment'}{'type'};
      if ($type =~ /card/i) {
        $paymentInformation->{'cardNumber'}      = $billOptions->{'payment'}{'cardNumber'};
        $paymentInformation->{'expirationMonth'} = $billOptions->{'payment'}{'expMonth'};
        $paymentInformation->{'expirationYear'}  = $billOptions->{'payment'}{'expYear'};
     } else {
        $paymentInformation->{'routingNumber'}   = $billOptions->{'payment'}{'routingNumber'};
        $paymentInformation->{'accountNumber'}   = $billOptions->{'payment'}{'accountNumber'};
      }
    }

    my $contact = new PlugNPay::Contact();
    $contact->setFullName($billingInformation->{'name'});
    $contact->setAddress1($billingInformation->{'addr1'});
    $contact->setAddress2($billingInformation->{'addr2'});
    $contact->setCity($billingInformation->{'city'});
    $contact->setState($billingInformation->{'state'});
    $contact->setPostalCode($billingInformation->{'zip'});
    $contact->setCountry($billingInformation->{'country'});
    $contact->setCompany($billingInformation->{'company'});

    my $shippingContact = new PlugNPay::Contact();
    $shippingContact->setFullName($shippingInformation->{'name'});
    $shippingContact->setAddress1($shippingInformation->{'addr1'});
    $shippingContact->setAddress2($shippingInformation->{'addr2'});
    $shippingContact->setCity($shippingInformation->{'city'});
    $shippingContact->setState($shippingInformation->{'state'});
    $shippingContact->setPostalCode($shippingInformation->{'zip'});
    $shippingContact->setCountry($shippingInformation->{'country'});

    my $type = lc $paymentInformation->{'type'};
    if ($type !~ /^card$|^ach$/i) {
      $errorMsg = 'Failed to bill member. Invalid payment type.';
      die;
    }

    my $transaction = new PlugNPay::Transaction('auth', $type);
    $transaction->setGatewayAccount($merchant);
    $transaction->setBillingInformation($contact);
    $transaction->setShippingInformation($shippingContact);

    if ($type =~ /card/i) {
      my $cc = new PlugNPay::CreditCard($paymentInformation->{'cardNumber'});
      $cc->setExpirationMonth($paymentInformation->{'expMonth'});
      $cc->setExpirationYear($paymentInformation->{'expYear'});
      $transaction->setCreditCard($cc);
    } else {
      my $ach = new PlugNPay::OnlineCheck();
      $ach->setABARoutingNumber($paymentInformation->{'routingNumber'});
      $ach->setAccountNumber($paymentInformation->{'accountNumber'});
      $transaction->setOnlineCheck($ach);
    }

    my $amount = $billOptions->{'amount'};
    if (!$amount || $amount !~ /^\d*\.?\d+$/) {
      $errorMsg = 'Failed to bill member. Invalid amount.';
      die;
    }

    $transaction->setTransactionAmount($amount);

    my $transactionProcessor = new PlugNPay::Transaction::TransactionProcessor();
    my $result = $transactionProcessor->process($transaction);

    $self->insertBillingEntry($customer, $merchant, {
      'result'              => $result->getStatus(),
      'orderID'             => $transaction->getOrderID(),
      'amount'              => $transaction->getTransactionAmount(),
      'description'         => $billOptions->{'description'} || 'Remote Member Billing',
      'billingUsername'     => $billOptions->{'billingUsername'},
      'transactionDate'     => new PlugNPay::Sys::Time('db', $transaction->getTransactionDateTime())->inFormat('yyyymmdd')
    });
  };

  if ($@) {
    $dbs->rollback($merchant);
    if (!$errorMsg) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_attendant' });
      $logger->log({
        'customer' => $customer,
        'merchant' => $merchant,
        'subroutine' => 'billMember',
        'error' => $@
      });

      $errorMsg = 'Failed to bill member.';
    }

    return { 'status' => 0, 'errorMessage' => $errorMsg };
  }

  $dbs->commit($merchant);
  return { 'status' => 1 };
}

sub insertBillingEntry {
  my $self = shift;
  my $customer = shift;
  my $merchant = shift;
  my $billingInfo = shift;

  my $errorMsg;
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare($merchant, q/INSERT INTO billingstatus
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
                  $billingInfo->{'billingUsername'}) or die $DBI::errstr;
  };

  if ($@) {
    if (!$errorMsg) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_attendant' });
      $logger->log({
        'customer' => $customer,
        'merchant' => $merchant,
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
