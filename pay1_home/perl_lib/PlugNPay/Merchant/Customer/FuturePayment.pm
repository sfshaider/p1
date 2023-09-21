package PlugNPay::Merchant::Customer::FuturePayment;

use strict;
use PlugNPay::Email;
use PlugNPay::Contact;
use PlugNPay::Merchant;
use PlugNPay::Sys::Time;
use PlugNPay::Transaction;
use PlugNPay::Util::Status;
use PlugNPay::DBConnection;
use PlugNPay::Logging::Alert;
use PlugNPay::GatewayAccount;
use PlugNPay::Logging::DataLog;
use PlugNPay::Membership::Plan;
use PlugNPay::Util::RandomString;
use PlugNPay::Membership::Profile;
use PlugNPay::Membership::Results;
use PlugNPay::Membership::Plan::Type;
use PlugNPay::Merchant::Customer::Link;
use PlugNPay::GatewayAccount::Services;
use PlugNPay::Merchant::Customer::Phone;
use PlugNPay::Membership::Plan::Currency;
use PlugNPay::Membership::Plan::Settings;
use PlugNPay::Merchant::Customer::History;
use PlugNPay::Membership::Plan::BillCycle;
use PlugNPay::Merchant::Customer::Address;
use PlugNPay::Membership::Profile::Status;
use PlugNPay::Merchant::Customer::Job::Status;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Merchant::Customer::PaymentSource;
use PlugNPay::Merchant::Customer::Phone::Expose;
use PlugNPay::Merchant::Customer::Address::Expose;
use PlugNPay::Merchant::Customer::PaymentSource::Type;
use PlugNPay::Merchant::Customer::PaymentSource::Expose;
use PlugNPay::Merchant::Customer::FuturePayment::Service;
use PlugNPay::Merchant::Customer::PaymentSource::ACH::Type;

###########################################
# Module: FuturePayment
# -----------------------------------------
# Description:
#   Customer's future payments are stored
#   and will be processed as a background
#   job. Future payments can be set by a
#   variety of services, or the 
#   merchant (USER).

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub setFuturePaymentID {
  my $self = shift;
  my $futurePaymentID = shift;
  $self->{'futurePaymentID'} = $futurePaymentID;
}

sub getFuturePaymentID {
  my $self = shift;
  return $self->{'futurePaymentID'};
}

sub setIdentifier {
  my $self = shift;
  my $identifier = shift;
  $self->{'identifier'} = $identifier;
}

sub getIdentifier {
  my $self = shift;
  return $self->{'identifier'};
}

sub setMerchantCustomerLinkID {
  my $self = shift;
  my $merchantCustomerLinkID = shift;
  $self->{'merchantCustomerLinkID'} = $merchantCustomerLinkID;
}

sub getMerchantCustomerLinkID {
  my $self = shift;
  return $self->{'merchantCustomerLinkID'};
}

sub setBillingAccountID {
  my $self = shift;
  my $billingAccountID = shift;
  $self->{'billingAccountID'} = $billingAccountID;
}

sub getBillingAccountID {
  my $self = shift;
  return $self->{'billingAccountID'};
}

sub setTransactionTypeID {
  my $self = shift;
  my $transactionTypeID = shift;
  $self->{'transactionTypeID'} = $transactionTypeID;
}

sub getTransactionTypeID {
  my $self = shift;
  return $self->{'transactionTypeID'};
}

sub setAmount {
  my $self = shift;
  my $amount = shift;
  $self->{'amount'} = $amount; 
}

sub getAmount {
  my $self = shift;
  return $self->{'amount'};
}

sub setDescription {
  my $self = shift;
  my $description = shift;
  $self->{'description'} = $description;
}

sub getDescription {
  my $self = shift;
  return $self->{'description'};
}

sub setPaymentSourceID {
  my $self = shift;
  my $paymentSourceID = shift;
  $self->{'paymentSourceID'} = $paymentSourceID;
}

sub getPaymentSourceID {
  my $self = shift;
  return $self->{'paymentSourceID'};
}

sub setCreationDate {
  my $self = shift;
  my $creationDate = shift;
  $self->{'creationDate'} = $creationDate;
}

sub getCreationDate {
  my $self = shift;
  return $self->{'creationDate'};
}

sub setPaymentDate {
  my $self = shift;
  my $paymentDate = shift;
  $self->{'paymentDate'} = $paymentDate;
}

sub getPaymentDate {
  my $self = shift;
  return $self->{'paymentDate'};
}

sub setStatusID {
  my $self = shift;
  my $statusID = shift;
  $self->{'statusID'} = $statusID;
}

sub getStatusID {
  my $self = shift;
  return $self->{'statusID'};
}

sub setBatchID {
  my $self = shift;
  my $batchID = shift;
  $self->{'batchID'} = $batchID;
}

sub getBatchID {
  my $self = shift;
  return $self->{'batchID'};
}

sub setProfileID {
  my $self = shift;
  my $profileID = shift;
  $self->{'profileID'} = $profileID;
}

sub getProfileID {
  my $self = shift;
  return $self->{'profileID'};
}

sub setServiceID {
  my $self = shift;
  my $serviceID = shift;
  $self->{'serviceID'} = $serviceID;
}

sub getServiceID {
  my $self = shift;
  return $self->{'serviceID'};
}

sub isProfilePayment {
  my $self = shift;
  return (defined $self->{'profileID'} ? 1 : 0);
}

#################################
# Subroutine: isModifiable
# -------------------------------
# Description:
#   If the service is set by the
#   user, it is modifiable.
sub isModifiable {
  my $self = shift;
  my $service = new PlugNPay::Merchant::Customer::FuturePayment::Service();
  return ($service->loadService($self->{'serviceID'}) =~ /USER/i ? 1 : 0);
}

###########################################
# Subroutine: loadCustomerFuturePayments
# -----------------------------------------
# Description:
#   Loads future payments for a given
#   customer id.
sub loadCustomerFuturePayments {
  my $self = shift;
  my $merchantCustomerLinkID = shift;

  my $futurePayments = [];

  my @values = ();
  my $sql = q/SELECT id,
                     identifier,
                     merchant_customer_link_id,
                     billing_merchant_id,
                     transaction_type_id,
                     amount,
                     description,
                     creation_date,
                     payment_date,
                     payment_source_id,
                     status_id,
                     batch_id,
                     profile_id,
                     service_id
              FROM customer_future_payments
              WHERE merchant_customer_link_id = ?
              AND status_id = ?
              ORDER BY id ASC/;

  my $futurePaymentStatus = new PlugNPay::Merchant::Customer::Job::Status();
  my $pendingStatusID = $futurePaymentStatus->loadStatusID('pending');

  push (@values, $merchantCustomerLinkID);
  push (@values, $pendingStatusID);

  my $limit = '';
  if ( (defined $self->{'limitData'}{'limit'}) && (defined $self->{'limitData'}{'offset'}) ) {
    $limit = ' LIMIT ?,? ';
    push (@values, $self->{'limitData'}{'offset'});
    push (@values, $self->{'limitData'}{'limit'});
  }

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust', $sql . $limit, \@values, {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        my $futurePayment = new PlugNPay::Merchant::Customer::FuturePayment();
        $futurePayment->_setFuturePaymentDataFromRow($row);
        push (@{$futurePayments}, $futurePayment);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadCustomerFuturePayments'
    });
  }

  return $futurePayments;
}

##################################
# Subroutine: loadFuturePayment
# --------------------------------
# Description:
#   Loads a future payment based
#   on the id of the table.
sub loadFuturePayment {
  my $self = shift;
  my $futurePaymentID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               merchant_customer_link_id,
               billing_merchant_id,
               transaction_type_id,
               amount,
               description,
               creation_date,
               payment_date,
               payment_source_id,
               status_id,
               batch_id,
               profile_id,
               service_id
        FROM customer_future_payments
        WHERE id = ?/, [$futurePaymentID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setFuturePaymentDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadFuturePayment'
    });
  }
}

sub _setFuturePaymentDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'futurePaymentID'}        = $row->{'id'};
  $self->{'identifier'}             = $row->{'identifier'};
  $self->{'description'}            = $row->{'description'};
  $self->{'merchantCustomerLinkID'} = $row->{'merchant_customer_link_id'};
  $self->{'billingAccountID'}       = $row->{'billing_merchant_id'};
  $self->{'transactionTypeID'}      = $row->{'transaction_type_id'};
  $self->{'paymentSourceID'}        = $row->{'payment_source_id'};
  $self->{'amount'}                 = $row->{'amount'};
  $self->{'creationDate'}           = $row->{'creation_date'};
  $self->{'paymentDate'}            = $row->{'payment_date'};
  $self->{'statusID'}               = $row->{'status_id'};
  $self->{'batchID'}                = $row->{'batch_id'};
  $self->{'profileID'}              = $row->{'profile_id'};
  $self->{'serviceID'}              = $row->{'service_id'};
}

##############################################################
# Subroutine: scheduleRecurringPayment
# ------------------------------------------------------------
# Description:
#   Looks at the profile to see whether a recurring payment
#   can be scheduled. If the profile is not active, if the
#   bill cycle is 0, or if the profile does not owe an amount
#   then don't schedule a payment.
sub scheduleRecurringPayment {
  my $self = shift;
  my $profileID = shift;

  # load the profile
  my $profile = new PlugNPay::Membership::Profile();
  $profile->loadBillingProfile($profileID);

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
  $merchantCustomer->loadMerchantCustomer($profile->getMerchantCustomerLinkID());

  my $planSettings = new PlugNPay::Membership::Plan::Settings();
  $planSettings->loadPlanSettings($profile->getPlanSettingsID());

  my $plan = new PlugNPay::Membership::Plan();
  $plan->loadPaymentPlan($planSettings->getPlanID());

  my $transType = new PlugNPay::Membership::Plan::Type();
  $transType->loadPlanType($plan->getPlanTransactionTypeID());
  my $transactionType = $transType->getType();

  my $billCycle = new PlugNPay::Membership::Plan::BillCycle();
  $billCycle->loadBillCycle($planSettings->getBillCycleID());
  if ($billCycle->getCycleDuration() == 0) {
    return new PlugNPay::Util::Status(1);
  }

  my $profileStatus = new PlugNPay::Membership::Profile::Status();
  $profileStatus->loadStatus($profile->getStatusID());
  if ($profileStatus->getStatus() !~ /active/i) {
    return new PlugNPay::Util::Status(1);
  }

  # the end date for the next cycle needs to be already set for the user
  # prior to calling this subroutine
  my $services = new PlugNPay::GatewayAccount::Services(new PlugNPay::Merchant($merchantCustomer->getMerchantID())->getMerchantUsername());
  my $lookAhead = $services->getLookAhead() || 3;
  if ($lookAhead > 0) {
    $lookAhead -= 1; # this accounts for the end date being a valid payment date
  }

  my $nextEndDate = new PlugNPay::Sys::Time('iso', $profile->getCurrentCycleEndDate());
  $nextEndDate->subtractDays($lookAhead);
  my $paymentDate = $nextEndDate->inFormat('yyyymmdd');

  # if subtracting the lookahead ends up being before today, set it for today
  my $today = new PlugNPay::Sys::Time();
  if ($today->inFormat('yyyymmdd') >= $paymentDate) {
    $paymentDate = $today->inFormat('yyyymmdd');
  }
 
  my $initiateLoyaltyCount = $planSettings->getLoyaltyCount(); # if profile loyalty is greater than plan loyalty
  my $currentLoyaltyCount  = $profile->getLoyaltyCount();      # this will need to be updated as well
 
  my $amountDue;
  if ($currentLoyaltyCount < $initiateLoyaltyCount) {
    $amountDue = $planSettings->getRecurringFee();    # get recurring fee from profile
  } else {
    if (($planSettings->getLoyaltyFee() == 0) || (!$planSettings->getLoyaltyFee())) {
      $amountDue = $planSettings->getRecurringFee();
    } else {
      $amountDue = $planSettings->getLoyaltyFee();  
    }
  }

  # add sign up fee if need be
  if ($profile->getChargeSignUpFee()) {
    $amountDue += $planSettings->getSignUpFee();
  }

  # if install billing is true, check the balance before scheduling the payment
  # if the balance is 0, then the customer has fulfilled their obligation
  if ($planSettings->getInstallBilling()) {
    if ($profile->getBalance() > 0) {
      if ($amountDue > $profile->getBalance()) {
        $amountDue = $profile->getBalance();
      }
    } else {
      # fulfillment complete, change bill cycle to 0
      $profile->updateBillingProfile({
        'billCycle' => 'None'
      });
      return new PlugNPay::Util::Status(1);
    }
  }

  if ($amountDue == 0) {
    return new PlugNPay::Util::Status(1);
  }

  # load the payment source associated with the billing profile.
  my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
  $exposePaymentSource->loadExposedPaymentSource($profile->getPaymentSourceID());

  my $paymentInfo = {
    'amount'                   => $amountDue,
    'description'              => 'Recurring payment: ' . $profile->getIdentifier(),
    'service'                  => 'RECURRING',
    'paymentDate'              => $paymentDate,
    'paymentSourceIdentifier'  => $exposePaymentSource->getIdentifier(),
    'transactionType'          => $transactionType,
    'billingProfileIdentifier' => $profile->getIdentifier(),
    'recurringSet'             => 1
  };

  return $self->scheduleFuturePayment($profile->getMerchantCustomerLinkID(), $paymentInfo);
}

#####################################################
# Subroutine: scheduleFuturePayment
# ---------------------------------------------------
# Description:
#   Schedules a future payment for a customer.
#   Accepts amount, paymentDate (yyyymmdd), profile
#   and payment source identifiers.
sub scheduleFuturePayment {
  my $self = shift;
  my $merchantCustomerLinkID = shift;
  my $paymentInfo = shift;

  my @errorMsg;
  my $status = new PlugNPay::Util::Status(1);

  my $amount = $paymentInfo->{'amount'};
  $amount =~ s/[^0-9\.]//g;
  if ($amount !~ /^\d*\.?\d+$/ || $amount <= 0) {
    push (@errorMsg, 'Invalid amount.');
  }

  my $description = $paymentInfo->{'description'};
  if ($description) {
    $description =~ s/[^a-zA-Z0-9\_\-\@\$\. ]//g;
  }

  my $paymentDate = $paymentInfo->{'paymentDate'};
  if ($paymentDate !~ /^\d{8}$/) {
    push (@errorMsg, 'Invalid payment date format. (YYYY/MM/DD).');
  } else {
    my $year  = substr($paymentDate, 1, 4);
    my $month = substr($paymentDate, 4, 2);
    my $day   = substr($paymentDate, 6, 2);
   
    my $timeObj = new PlugNPay::Sys::Time();
    if (!$timeObj->validDate($day, $month, $year)) {
      push (@errorMsg, 'Invalid date.');
    }

    if ($timeObj->nowInFormat('yyyymmdd') > $paymentDate) {
      push (@errorMsg, 'Payment date cannot be scheduled before today.');
    }
  }

  my $paymentSourceIdentifier = $paymentInfo->{'paymentSourceIdentifier'};
  my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
  $exposePaymentSource->loadByLinkIdentifier($paymentSourceIdentifier, $merchantCustomerLinkID);
  my $paymentSourceID = $exposePaymentSource->getLinkID();
  if (!$paymentSourceID) {
    push (@errorMsg, 'Invalid payment source identifier.');
  }

  my $transType = $paymentInfo->{'transactionType'} || 'auth';
  if ($transType !~ /^(auth|credit)$/i) {
    push (@errorMsg, 'Invalid transaction type.');
  }

  if (@errorMsg == 0) {
    my $transactionType = new PlugNPay::Membership::Plan::Type();
    $transactionType->loadPlanTypeID($transType);

    # profile identifier
    my $profileID;
    if ($paymentInfo->{'billingProfileIdentifier'}) {
      my $profile = new PlugNPay::Membership::Profile();
      $profile->loadByBillingProfileIdentifier($paymentInfo->{'billingProfileIdentifier'}, $merchantCustomerLinkID);
      $profileID = $profile->getBillingProfileID();
      if (!$profileID) {
        push (@errorMsg, 'Invalid profile identifier.');
      } else {
        # has the sign up fee been paid for the profile
        if ($profile->getChargeSignUpFee() && !$paymentInfo->{'recurringSet'}) {
          push (@errorMsg, 'Sign up fee must be paid before scheduling payments for a profile.');
        } else {
          # if it is a profile payment. check if it is a install billing profile.
          # this allows customers to add additional payments on top of their recurring payments
          # to pay off a balance quicker

          my $planSettings = new PlugNPay::Membership::Plan::Settings();
          $planSettings->loadPlanSettings($profile->getPlanSettingsID());
          if ($planSettings->getInstallBilling()) {
            # if install billing is true, don't charge over the amount they are due for.
            if ($amount > $profile->getBalance()) {
              $amount = $profile->getBalance();
            }
          } else {
            if (!$paymentInfo->{'recurringSet'}) {
              push (@errorMsg, 'Unable to save future payment on non installment billing profile.');
            }
          }
        }
      }
    }

    if (@errorMsg == 0) {
      my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
      $merchantCustomer->loadMerchantCustomer($merchantCustomerLinkID);

      my $billingAccountID = $merchantCustomer->getMerchantID();
      if ($paymentInfo->{'billingAccount'}) {
        $billingAccountID = new PlugNPay::Merchant($paymentInfo->{'billingAccount'})->getMerchantID();
      }

      # pending status first
      my $futurePaymentStatus = new PlugNPay::Merchant::Customer::Job::Status();
      my $statusID = $futurePaymentStatus->loadStatusID('pending');

      # service that is setting this payment
      my $serviceName = $paymentInfo->{'service'} || 'USER';
      my $service = new PlugNPay::Merchant::Customer::FuturePayment::Service();
      my $serviceID = $service->loadServiceID($serviceName);

      # generate future payment identifier
      my $identifier = $self->_generateUniqueFuturePaymentID();

      my $params = [
        $merchantCustomerLinkID,
        $billingAccountID,
        $identifier,
        $amount,
        $transactionType->getTypeID(),
        $description,
        new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd'),
        $paymentDate,
        $paymentSourceID,
        $statusID,
        $profileID,
        $serviceID
      ];

      eval {
        my $dbs = new PlugNPay::DBConnection();
        $dbs->executeOrDie('merchant_cust',
          q/INSERT INTO customer_future_payments
            ( merchant_customer_link_id,
              billing_merchant_id,
              identifier,
              amount,
              transaction_type_id,
              description,
              creation_date,
              payment_date,
              payment_source_id,
              status_id,
              profile_id,
              service_id )
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)/, $params);
      };
    }
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'                  => $@,
        'data'                   => $paymentInfo,
        'merchantCustomerLinkID' => $merchantCustomerLinkID,
        'function'               => 'scheduleFuturePayment'
      });

      push (@errorMsg, 'Error while attempting to schedule payment.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status; 
}

##################################################
# Subroutine: updatePendingFuturePayment
# ------------------------------------------------
# Description:
#   Allows updating a PENDING status future 
#   payment. Expects payment to be loaded into 
#   current object.
sub updatePendingFuturePayment {
  my $self = shift;
  my $updateData = shift;

  my @errorMsg;
  my $status = new PlugNPay::Util::Status(1);

  if (!$self->isModifiable()) {
    $status->setFalse();
    $status->setError('Payment is unable to be modified.');
    return $status;
  }

  my $futurePaymentStatus = new PlugNPay::Merchant::Customer::Job::Status();
  my $statusID = $futurePaymentStatus->loadStatusID('pending');
  if ($self->{'statusID'} != $statusID) {
    $status->setFalse();
    $status->setError('Unable to update a non-pending payment.');
    return $status;
  }

  my $amount = $self->{'amount'};
  if (exists $updateData->{'amount'}) {
    $amount = $updateData->{'amount'};
    $amount =~ s/[^0-9\.]//g;
    if ($amount !~ /^\d*\.?\d+$/ || $amount <= 0) {
      push (@errorMsg, 'Invalid amount.');
    }
  }

  my $description = $self->{'description'};
  if (exists $updateData->{'description'}) {
    $description = $updateData->{'description'};
    if ($description) {
      $description =~ s/[^a-zA-Z0-9\_\-\@\$\. ]//g;
    }
  }

  my $paymentDate = $self->{'paymentDate'};
  if (exists $updateData->{'paymentDate'}) {
    $paymentDate = $updateData->{'paymentDate'};

    if ($paymentDate !~ /^\d{8}$/) {
      push (@errorMsg, 'Invalid payment date format. (YYYY/MM/DD).');
    } else {
      my $year  = substr($paymentDate, 1, 4);
      my $month = substr($paymentDate, 4, 2);
      my $day   = substr($paymentDate, 6, 2);
  
      my $timeObj = new PlugNPay::Sys::Time();
      if (!$timeObj->validDate($day, $month, $year)) {
        push (@errorMsg, 'Invalid date.');
      } else {
        if ($timeObj->nowInFormat('yyyymmdd') > $paymentDate) {
          push (@errorMsg, 'Payment date cannot be scheduled before today.');
        }
      }
    }
  }

  my $transTypeID;
  if (exists $updateData->{'transactionType'}) {
    my $transType = $updateData->{'transactionType'};
    if ($transType !~ /^(auth|credit)$/i) {
      push (@errorMsg, 'Invalid transaction type.');
    } else {
      my $transactionType = new PlugNPay::Membership::Plan::Type();
      $transactionType->loadPlanTypeID($transType);
      $transTypeID = $transactionType->getTypeID();
    }
  } else {
    $transTypeID = $self->{'transactionTypeID'}
  }

  my $paymentSourceID = $self->{'paymentSourceID'};
  if (exists $updateData->{'paymentSourceIdentifier'}) {
    my $paymentSourceIdentifier = $updateData->{'paymentSourceIdentifier'};
    my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
    $exposePaymentSource->loadByLinkIdentifier($paymentSourceIdentifier, $self->{'merchantCustomerLinkID'});
    $paymentSourceID = $exposePaymentSource->getLinkID();
    if (!$paymentSourceID) {
      push (@errorMsg, 'Invalid payment source identifier.');
    }
  }
 
  my $profileID = $self->{'profileID'};
  if (@errorMsg == 0) {
    if (exists $updateData->{'billingProfileIdentifier'}) {
      if ($updateData->{'billingProfileIdentifier'}) {
        my $profile = new PlugNPay::Membership::Profile();
        $profile->loadByBillingProfileIdentifier($updateData->{'billingProfileIdentifier'}, $self->{'merchantCustomerLinkID'});
        if (!$profile->getBillingProfileID()) {
          push (@errorMsg, 'Invalid profile identifier.');
        } else {
          # has the sign up fee been paid for the profile
          if ($profile->getChargeSignUpFee()) {
            push (@errorMsg, 'Sign up fee must be paid before scheduling payments for a profile.');
          } else {
            my $planSettings = new PlugNPay::Membership::Plan::Settings();
            $planSettings->loadPlanSettings($profile->getPlanSettingsID());
            if ($planSettings->getInstallBilling()) {
              # if install billing is true, don't charge over the amount they are due for.
              if ($amount > $profile->getBalance()) {
                $amount = $profile->getBalance();
              }
            } else {
              push (@errorMsg, 'Unable to update future payment on non installment billing profile.');
            }
          }
        }
      } else {
        $profileID = undef;
      }
    }
  }

  if (@errorMsg == 0) {
    my $billingAccountID = $self->{'billingAccountID'};
    if (exists $updateData->{'billingAccount'} && $updateData->{'billingAccount'}) {
      $billingAccountID = new PlugNPay::Merchant($updateData->{'billingAccount'})->getMerchantID();
    }

    eval {
      my $params = [
        $billingAccountID,
        $amount,
        $transTypeID,
        $description,
        $paymentDate,
        $paymentSourceID,
        $profileID,
        $self->{'futurePaymentID'}
      ];

      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/UPDATE customer_future_payments
          SET billing_merchant_id = ?,
              amount = ?,
              transaction_type_id = ?,
              description = ?,
              payment_date = ?,
              payment_source_id = ?,
              profile_id = ?
          WHERE id = ?/, $params);
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error' => $@,
        'data' => $updateData,
        'merchantCustomerLinkID' => $self->{'merchantCustomerLinkID'},
        'function' => 'updateFuturePayment'
      });

      push (@errorMsg, 'Error while attempting to update payment.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

###########################################
# Subroutine: removeFuturePayment
# -----------------------------------------
# Description:
#   Removing future payments from the 
#   customers records. This subroutine is
#   unable to remove a non-user service
#   payment.
sub removeFuturePayment {
  my $self = shift;
  my $futurePaymentID = shift || $self->{'futurePaymentID'};

  my @errorMsg;
  my $status = new PlugNPay::Util::Status(1);

  $self->loadFuturePayment($futurePaymentID);
  if (!$self->isModifiable()) {
    $status->setFalse();
    $status->setError('Unable to modify payment.');
    return $status;
  }

  my $futurePaymentStatus = new PlugNPay::Merchant::Customer::Job::Status();
  my $paymentStatus = $futurePaymentStatus->loadStatus($self->{'statusID'});
  if ($paymentStatus !~ /PENDING/) {
    push (@errorMsg, 'Unable to delete non pending payment.');
  }

  if (@errorMsg == 0) {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/DELETE FROM customer_future_payments
          WHERE id = ?/, [$futurePaymentID]);
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error' => $@,
        'futurePaymentID' => $futurePaymentID,
        'function' => 'removeFuturePayment'
      });

      push (@errorMsg, 'Error while attempting to delete future payment.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

######################################
# Subroutine: removePendingRecurring
# ------------------------------------
# Description:
#   Removes a pending recurring 
#   future payment. Internally used
#   so that updates to the profile
#   can be rescheduled payments.
sub removePendingRecurring {
  my $self = shift;
  my $profileID = shift;

  my $status = new PlugNPay::Util::Status(1);
  eval {
    my $futurePaymentStatus = new PlugNPay::Merchant::Customer::Job::Status();
    my $pendingStatusID = $futurePaymentStatus->loadStatusID('pending');

    my $service = new PlugNPay::Merchant::Customer::FuturePayment::Service();
    my $recurringServiceID = $service->loadServiceID('RECURRING');

    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM customer_future_payments
        WHERE status_id = ?
        AND profile_id = ?
        AND service_id = ?/, [$pendingStatusID, $profileID, $recurringServiceID]);
  };

  if ($@) {
    $self->_log({
      'error'     => $@,
      'function'  => 'removePendingRecurring',
      'profileID' => $profileID
    });

    $status->setFalse();
    $status->setError('Failed to remove pending recurring future payment.');
  }

  return $status;
}

sub customerFuturePaymentExists {
  my $self = shift;
  my $merchantCustomerLinkID = shift;
  my $futurePaymentIdentifier = shift;

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM customer_future_payments
        WHERE identifier = ?
        AND merchant_customer_link_id = ?/, [$futurePaymentIdentifier, $merchantCustomerLinkID], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'customerFuturePaymentExists'
    });
  }

  return $exists;
}

sub isPaymentSourceUsed {
  my $self = shift;
  my $paymentSourceID = shift;

  my $inUse = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `inUse`
        FROM customer_future_payments
        WHERE payment_source_id = ?/, [$paymentSourceID], {})->{'result'};
    $inUse = $rows->[0]{'inUse'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'isPaymentSourceUsed'
    });
  }

  return $inUse;
}

sub _generateUniqueFuturePaymentID {
  my $self = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};

  my $uniqueID = new PlugNPay::Util::RandomString()->randomAlphaNumeric(24);
  if ($self->doesUniqueFuturePaymentIDExist($uniqueID, $merchantCustomerLinkID)) {
    return $self->_generateUniqueFuturePaymentID($merchantCustomerLinkID);
  }

  return $uniqueID;
}

sub doesUniqueFuturePaymentIDExist {
  my $self = shift;
  my $uniqueID = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM customer_future_payments
        WHERE identifier = ?
        AND merchant_customer_link_id = ?/, [$uniqueID, $merchantCustomerLinkID], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'doesUniqueFuturePaymentIDExist'
    });
  }

  return $exists;
}

sub loadByFuturePaymentIdentifier {
  my $self = shift;
  my $futurePaymentIdentifier = shift;
  my $merchantCustomerLinkID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               merchant_customer_link_id,
               billing_merchant_id,
               transaction_type_id,
               amount,
               description,
               creation_date,
               payment_date,
               payment_source_id,
               status_id,
               batch_id,
               profile_id,
               service_id
        FROM customer_future_payments
        WHERE identifier = ?
        AND merchant_customer_link_id = ?/, [$futurePaymentIdentifier, $merchantCustomerLinkID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setFuturePaymentDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadByFuturePaymentIdentifier'
    });
  }
}

sub updatePaymentsPlanChange {
  my $self = shift;
  my $profiles = shift;
  my $typeID = shift;

  my $status = new PlugNPay::Util::Status(1);

  eval {
    if (@{$profiles} > 0) {
      my $dbs = new PlugNPay::DBConnection();
      my $sql = q/UPDATE customer_future_payments
                  SET transaction_type_id = ?
                  WHERE profile_id IN (/;

      my @params = map { '?' } @{$profiles};
      $dbs->executeOrDie('merchant_cust', $sql . join(',', @params) . ')', [$typeID, @{$profiles}]);
    }
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'future_payment' });
    $logger->log({
      'error' => $@,
      'function' => 'updatePaymentsPlanChange'
    });

    $status->setFalse();
    $status->setError('Failed to update existing payments to new transaction type.');
  }

  return $status;
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getFuturePaymentListSize {
  my $self = shift;
  my $merchantCustomerLinkID = shift;

  my $count = 0;

  eval {
    my $futurePaymentStatus = new PlugNPay::Merchant::Customer::Job::Status();
    my $pendingStatusID = $futurePaymentStatus->loadStatusID('pending');

    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM customer_future_payments
        WHERE merchant_customer_link_id = ?
        AND status_id = ?/, [$merchantCustomerLinkID, $pendingStatusID], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'getFuturePaymentListSize'
    });
  }

  return $count;
}

###############################################
# Subroutine: process
# ---------------------------------------------
# Description:
#   --DO NOT CALL THIS SUBROUTINE--
#   Entrypoint for future payment job.
sub process {
  my $self = shift;
  eval {
    $self->_loadPayments();
  };
}

########################################################################
# Subroutine: _loadPayments
# ----------------------------------------------------------------------
# Description:
#   This loads future payments for today's date and payment's marked
#   as RETRY that last_attempted is not today for recurring payments.
sub _loadPayments {
  my $self = shift;
  my $batchID;
  my $futurePayments = [];

  my $status = new PlugNPay::Util::Status();
  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');

    my $futurePaymentStatus = new PlugNPay::Merchant::Customer::Job::Status();
    my $pendingStatusID = $futurePaymentStatus->loadStatusID('pending');

    my $today = new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd');

    # get all of the payments into an array to be processed
    $futurePayments = [];

    # GET THE PENDING IDs FOR TODAY (SQL transaction)
    # ALSO WHERE STATUS = RETRY AND LAST_ATTEMPTED < TODAY
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               merchant_customer_link_id,
               billing_merchant_id,
               amount,
               transaction_type_id,
               description,
               creation_date,
               payment_date,
               payment_source_id,
               status_id,
               batch_id,
               profile_id,
               service_id
        FROM customer_future_payments
        WHERE (status_id = ? AND payment_date = ?)
        FOR UPDATE/, [$pendingStatusID, $today], {})->{'result'};
    # if there are transactions to run.. set them to processing in the table
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        my $futurePayment = new PlugNPay::Merchant::Customer::FuturePayment();
        $futurePayment->_setFuturePaymentDataFromRow($row);
        push (@{$futurePayments}, $futurePayment);
      }

      # create a batch ID to group these payments
      # for any reason we need to find out what happened to a payment
      # check the logs for a specific batch ID
      $batchID = new PlugNPay::Util::UniqueID()->inHex();

      # UPDATE THOSE PENDING IDs TO PROCESSING AND ASSIGN A BATCH TO THOSE IDS, THEN COMMIT
      my $updateSQL = q/UPDATE customer_future_payments
                        SET status_id = ?,
                            batch_id = ?
                        WHERE id IN (/;
      my @params = map { '?' } @{$futurePayments};
      my @processingIDs = map { $_->{'futurePaymentID'} } @{$futurePayments};

      # set the state to processing 
      my $nextStateID = $futurePaymentStatus->loadStatusID('processing');
      $dbs->executeOrDie('merchant_cust', $updateSQL . join(',', @params) . ')', [$nextStateID, $batchID, @processingIDs]);
    }
  };

  if ($@) {
    $dbs->rollback('merchant_cust');
    # this wouldn't be good, need to send alert here saying that 
    # payments couldn't be set to processing
    my $alerter = new PlugNPay::Logging::Alert();
    $alerter->alert(8, 'Failed to submit batch of future payments to be processed. Error: ' . $@);

    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'future_payments' });
    $logger->log({
      'error'    => $@,
      'function' => '_loadPayments',
      'batchID'  => $batchID
    });

    $status->setFalse();
    $status->setError('Failed to gather pending transactions');
    return $status;
  }

  # we have updated the payments to processing status so commit
  $dbs->commit('merchant_cust');
  $status->setTrue();

  # we have the batch of payments, useful for diagnosing
  # if there are no errors and a future payment to process, lets iterate
  if (!$@ && @{$futurePayments} > 0) {
    foreach my $payment (@{$futurePayments}) {
      # run transaction, put into history, save recurring in results table
      eval {
        $self->_processPayment($payment);
      };
    }
  }

  return $status;
}

########################################################################
# Subroutine: _processPayments
# ----------------------------------------------------------------------
# Description:
#   Inputs a future payment object and will process it.
sub _processPayment {
  my $self = shift;
  my $payment = shift;

  eval {
    my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
    $merchantCustomer->loadMerchantCustomer($payment->{'merchantCustomerLinkID'});

    # load merchant and customer objects
    my $merchant = new PlugNPay::Merchant($merchantCustomer->getMerchantID());
    my $gatewayAccount = new PlugNPay::GatewayAccount($merchant->getMerchantUsername());

    # load payment source associated with profile
    my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
    $exposePaymentSource->loadExposedPaymentSource($payment->{'paymentSourceID'});

    my $paymentSource = new PlugNPay::Merchant::Customer::PaymentSource();
    $paymentSource->loadPaymentSource($exposePaymentSource->getPaymentSourceID());

    my $paymentSourceType = new PlugNPay::Merchant::Customer::PaymentSource::Type();
    $paymentSourceType->loadPaymentType($paymentSource->getPaymentSourceTypeID());
    my $paymentType = $paymentSourceType->getPaymentType();

    # load address for contact information
    my $exposeAddress = new PlugNPay::Merchant::Customer::Address::Expose();
    $exposeAddress->loadExposedAddress($paymentSource->getBillingAddressID());
    my $customerBillingInfo = new PlugNPay::Merchant::Customer::Address();
    $customerBillingInfo->loadAddress($exposeAddress->getAddressID());

    # create contact object
    my $contact = new PlugNPay::Contact();
    $contact->setFullName($customerBillingInfo->getName());
    $contact->setAddress1($customerBillingInfo->getLine1());
    $contact->setAddress2($customerBillingInfo->getLine2());
    $contact->setCity($customerBillingInfo->getCity());
    $contact->setState($customerBillingInfo->getStateProvince());
    $contact->setPostalCode($customerBillingInfo->getPostalCode());
    $contact->setCountry($customerBillingInfo->getCountry());
    $contact->setCompany($customerBillingInfo->getCompany());

    # load phones to set in contact information
    if ($merchantCustomer->getDefaultPhoneID()) {
      my $exposePhone = new PlugNPay::Merchant::Customer::Phone::Expose();
      $exposePhone->loadExposedPhone($merchantCustomer->getDefaultPhoneID());
      my $phone = new PlugNPay::Merchant::Customer::Phone();
      $phone->loadPhone($exposePhone->getPhoneID());
      $contact->setPhone($phone->getPhoneNumber());
    }

    if ($merchantCustomer->getDefaultFaxID()) {
      my $exposeFax = new PlugNPay::Merchant::Customer::Phone::Expose();
      $exposeFax->loadExposedPhone($merchantCustomer->getDefaultFaxID());
      my $fax = new PlugNPay::Merchant::Customer::Phone();
      $fax->loadPhone($exposeFax->getPhoneID());
      $contact->setFax($fax->getPhoneNumber());
    }   
 
    # if it is a profile payment, take into consideration the plan type, the amount due, currency
    # else, regular auth, with amount set
    my $transactionType = new PlugNPay::Membership::Plan::Type();
    $transactionType->loadPlanType($payment->{'transactionTypeID'});

    # load the type that is stored in this table.
    # regardless if it is a credit/auth based payment plan
    my $type = $transactionType->getType(); 

    my $currency = $gatewayAccount->getDefaultCurrency() || 'USD';
    my $amountDue = $payment->{'amount'};

    my ($planSettingsTransactionType);
    # if the payment contains a profile ID
    if ($payment->isProfilePayment()) {
      my $profile = new PlugNPay::Membership::Profile();
      $profile->loadBillingProfile($payment->{'profileID'});

      # load plan settings associated with profile
      my $planSettings = new PlugNPay::Membership::Plan::Settings();
      $planSettings->loadPlanSettings($profile->getPlanSettingsID());

      my $plan = new PlugNPay::Membership::Plan();
      $plan->loadPaymentPlan($planSettings->getPlanID());

      my $planTransactionType = new PlugNPay::Membership::Plan::Type();
      $planTransactionType->loadPlanType($plan->getPlanTransactionTypeID());
      $planSettingsTransactionType = $planTransactionType->getType();

      # load the currency of the plan
      my $currencyObj = new PlugNPay::Membership::Plan::Currency();
      $currencyObj->loadCurrency($planSettings->getCurrencyID());
      $currency = $currencyObj->getCurrencyCode();

      # need to check if the payment here is greater than their balance if
      # install billing is enabled on the plan settings, since it is possible 
      # for future payments to be processed that decrement their profile balance
      # before this payment processing...
      if ($planSettings->getInstallBilling()) {
        # important note! if the plan settings transaction type and payment type
        # are different, then the balance will increase... so do not do this check
        if ($planSettingsTransactionType ne $type) {
          if ($profile->getBalance() <= $amountDue + 1.00) {
            $amountDue = $profile->getBalance();
          }
        }
      }
    }

    if ($amountDue > 0) {
      # transaction time
      my $transTime = new PlugNPay::Sys::Time(); 

      # create transaction object
      my $transaction = new PlugNPay::Transaction($type, $paymentType);
      $transaction->setBillingInformation($contact);
      $transaction->setGatewayAccount($merchant->getMerchantUsername());
      $transaction->addTransFlag('recurring');
      $transaction->setAccountCode(4, $merchant->getMerchantUsername() . ':' . $merchantCustomer->getUsername());
      $transaction->setTime($transTime->inFormat('unix'));
      $transaction->setCurrency($currency);
      $transaction->setTransactionAmount($amountDue);
      $transaction->setTaxAmount(0);

      # set payment vehicle
      if ($paymentType =~ /^card$/i) {
        my $creditCard = new PlugNPay::CreditCard();
        $creditCard->setName($customerBillingInfo->getName() || $merchantCustomer->getName());
        $creditCard->fromToken($paymentSource->getToken());
        $creditCard->setExpirationMonth($paymentSource->getExpirationMonth());
        $creditCard->setExpirationYear($paymentSource->getExpirationYear());
        $transaction->setCreditCard($creditCard);
      } else {
        my $achType = new PlugNPay::Merchant::Customer::PaymentSource::ACH::Type();
        $achType->loadACHAccountType($paymentSource->getAccountTypeID());
   
        my $onlineCheck = new PlugNPay::OnlineCheck();
        $onlineCheck->setName($customerBillingInfo->getName());
        $onlineCheck->fromToken($paymentSource->getToken());
        $onlineCheck->setAccountType($achType->getAccountType());
        $transaction->setOnlineCheck($onlineCheck);
      }

      # check if transaction should be settled
      my $services = new PlugNPay::GatewayAccount::Services($merchant->getMerchantUsername());
      if ( ($services->getRecurBatch() && ref($transaction->getPayment()) =~ /^PlugNPay::CreditCard/) 
      || ($services->getCheckRecurringBatch() && ref($transaction->getPayment()) =~ /^PlugNPay::OnlineCheck/) ) {
        $transaction->setPostAuth(); 
      }

      # process the transaction
      my $transactionProcessor = new PlugNPay::Transaction::TransactionProcessor();
      my $response = $transactionProcessor->process($transaction, { 'sendEmailReceipt' => ($gatewayAccount->getFeatures()->get('sendEmailReceipt') ? 1 : 0) });

      my $transactionResults = {
        'transactionAmount'      => $amountDue,
        'transactionStatus'      => $response->getStatus(),
        'transactionDate'        => $transTime->inFormat('iso'),
        'description'            => $payment->{'description'},
        'transactionTypeID'      => $transactionType->getTypeID(),
        'orderID'                => $response->getTransaction()->getOrderID(),
        'transactionID'          => $response->getTransaction()->getPNPTransactionID(),
        'billingAccountID'       => $payment->{'billingAccountID'}
      };

      # save entry in history table
      my $history = new PlugNPay::Merchant::Customer::History();
      my $saveHistory = $history->saveHistoryEntry($merchantCustomer->getMerchantCustomerLinkID(), 
                                                   $transactionResults);
      if (!$saveHistory) {
        my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_future_payment' });
        $logger->log({
          'error'            => 'Failed to save in customer history table.',
          'function'         => '_processPayments',
          'profileID'        => $payment->{'profileID'},
          'merchantCustomer' => $merchantCustomer->getUsername(),
          'merchantID'       => $merchantCustomer->getMerchantID()
        });
      }

      # SAVE IN THE RESULTS TABLE IF RECURRING SERVICE
      my $service = new PlugNPay::Merchant::Customer::FuturePayment::Service();
      if ($service->loadService($payment->{'serviceID'}) =~ /RECURRING/i) {
        my $result = new PlugNPay::Membership::Results();
        if (!$result->saveTransactionResult($merchantCustomer->getMerchantCustomerLinkID(),
                                            $response,
                                            {
                                              'profileID' => $payment->{'profileID'},
                                              'batchID'   => $payment->{'batchID'},
                                              'transactionTypeID' => $transactionType->getTypeID()
                                            })) {
          # if the results of a recurring transaction were not saved
          my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_future_payment' });
          $logger->log({
            'error'            => 'Failed to save in recurring results table.',
            'function'         => '_processPayments',
            'profileID'        => $payment->{'profileID'},
            'merchantCustomer' => $merchantCustomer->getUsername(),
            'merchantID'       => $merchantCustomer->getMerchantID()
          });
        }
      } elsif ($service->loadService($payment->{'serviceID'}) =~ /USER/i && $payment->isProfilePayment()) {
        # if set by the user and has a profile
        my $profile = new PlugNPay::Membership::Profile();
        $profile->loadBillingProfile($payment->{'profileID'});

        my $balanceUpdateData = {};
        if ($planSettingsTransactionType ne $type) {
          # if plan is AUTH and the payment is a CREDIT, add to the balance.
          # if the plan is CREDIT and the payment is AUTH, add to the balance.
          $balanceUpdateData->{'customerBalance'} = ($profile->getBalance() + $amountDue);
        } else {
          # if the plan is AUTH and the payment is AUTH, subtract the balance.
          # if the plan is CREDIT and the payment is CREDIT, subtract the balance
          $balanceUpdateData->{'customerBalance'} = ($profile->getBalance() - $amountDue);
        }

        my $updateBalanceStatus = $profile->recurringUpdate($balanceUpdateData);
        if (!$updateBalanceStatus) {
          my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_future_payment' });
          $logger->log({
            'error'            => 'Failed to update customer balance.',
            'function'         => '_processPayments',
            'profileID'        => $payment->{'profileID'},
            'merchantCustomer' => $merchantCustomer->getUsername(),
            'merchantID'       => $merchantCustomer->getMerchantID()
          });
        }
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => '_processPayments',
      'batchID'  => $payment->{'batchID'}
    });

    my $problemID = new PlugNPay::Merchant::Customer::Job::Status()->loadStatusID('PROBLEM');

    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/UPDATE customer_future_payments
        SET status_id = ?
        WHERE id = ?/, [$problemID, $payment->{'futurePaymentID'}]);
  } else {
    my $completedID = new PlugNPay::Merchant::Customer::Job::Status()->loadStatusID('COMPLETED');

    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/UPDATE customer_future_payments
        SET status_id = ?
        WHERE id = ?/, [$completedID, $payment->{'futurePaymentID'}]);
  }
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'future_payment' });
  $logger->log($logInfo);
}

1;
