package PlugNPay::Membership::Results;

use strict;
use PlugNPay::Util;
use PlugNPay::Merchant;
use PlugNPay::Sys::Time;
use PlugNPay::Util::Status;
use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount;
use PlugNPay::Logging::Alert;
use PlugNPay::Logging::DataLog;
use PlugNPay::Merchant::Customer;
use PlugNPay::Membership::Profile;
use PlugNPay::Membership::Plan::Type;
use PlugNPay::Database::QueryBuilder;
use PlugNPay::GatewayAccount::Services;
use PlugNPay::Membership::Plan::Settings;
use PlugNPay::Membership::Plan::BillCycle;
use PlugNPay::Membership::Profile::Status;
use PlugNPay::Membership::PasswordManagement;
use PlugNPay::Merchant::Customer::Job::Status;
use PlugNPay::Merchant::Customer::PaymentSource;
use PlugNPay::Merchant::Customer::PaymentSource::Expose;

##################################################
# This module's purpose is for processing and 
# updating a customers billing profile based on
# the status of their recurring set transaction.
##################################################

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub setTransactionResultID {
  my $self = shift;
  my $transactionResultID = shift;
  $self->{'transactionResultID'} = $transactionResultID;
}

sub getTransactionResultID {
  my $self = shift;
  return $self->{'transactionResultID'};
}

sub setMerchantCustomerLinkID {
  my $self = shift;
  my $linkID = shift;
  $self->{'merchantCustomerLinkID'} = $linkID;
}

sub getMerchantCustomerLinkID {
  my $self = shift;
  return $self->{'merchantCustomerLinkID'};
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

sub setTransactionDateTime {
  my $self = shift;
  my $transactionDateTime = shift;
  $self->{'transactionDateTime'} = $transactionDateTime;
}

sub getTransactionDateTime {
  my $self = shift;
  return $self->{'transactionDateTime'};
}

sub setTransactionDate {
  my $self = shift;
  my $transactionDate = shift;
  $self->{'transactionDate'} = $transactionDate;
}

sub getTransactionDate {
  my $self = shift;
  return $self->{'transactionDate'};
}

sub setTransactionAmount {
  my $self = shift;
  my $transactionAmount = shift;
  $self->{'transactionAmount'} = $transactionAmount;
}

sub getTransactionAmount {
  my $self = shift;
  return $self->{'transactionAmount'};
}

sub setTransactionStatus {
  my $self = shift;
  my $transactionStatus = shift;
  $self->{'transactionStatus'} = $transactionStatus;
}

sub getTransactionStatus {
  my $self = shift;
  return $self->{'transactionStatus'};
}

sub setOrderID {
  my $self = shift;
  my $orderID = shift;
  $self->{'orderID'} = $orderID;
}

sub getOrderID {
  my $self = shift;
  return $self->{'orderID'};
}

sub setTransactionID {
  my $self = shift;
  my $transactionID = shift;
  $self->{'transactionID'} = $transactionID;
}

sub getTransactionID {
  my $self = shift;
  return $self->{'transactionID'};
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

sub setAuthorizationCode {
  my $self = shift;
  my $authorizationCode = shift;
  $self->{'authorizationCode'} = $authorizationCode;
}

sub getAuthorizationCode {
  my $self = shift;
  return $self->{'authorizationCode'};
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

sub loadTransactionResultsForProfile {
  my $self = shift;
  my $billingProfileID = shift;
  my $statusID = shift;
 
  my $results = [];

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               merchant_customer_link_id,
               status_id,
               trans_date_time,
               amount,
               trans_status,
               order_id,
               pnp_internal_transaction_id,
               transaction_type_id,
               authorization_code,
               trans_date,
               batch_id,
               profile_id
        FROM recurring1_results
        WHERE profile_id = ?
        AND status_id = ?/, [$billingProfileID, $statusID], {})->{'result'};
    foreach my $row (@{$rows}) {
      my $result = new PlugNPay::Membership::Results();
      $result->_setTransactionResultFromRow($row);
      push (@{$results}, $result);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadTransactionResultsForProfile'
    });
  }

  return $results;
}

#############################################
# Subroutine: loadTransactionResult
# -------------------------------------------
# Description:
#   Loads results for customer transaction.
sub loadTransactionResult {
  my $self = shift;
  my $transactionResultID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               merchant_customer_link_id,
               status_id,
               trans_date_time,
               trans_date,
               amount,
               trans_status,
               order_id,
               pnp_internal_transaction_id,
               transaction_type_id,
               authorization_code,
               batch_id,
               profile_id
        FROM recurring1_results
        WHERE id = ?/, [$transactionResultID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setTransactionResultFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadTransactionResult'
    });
  }
}

#############################################
# Subroutine: _setTransactionResultFromRow
# -------------------------------------------
# Description:
#   Inputs a row of data from table and sets
#   data in current object.
sub _setTransactionResultFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'transactionResultID'}    = $row->{'id'};
  $self->{'merchantCustomerLinkID'} = $row->{'merchant_customer_link_id'};
  $self->{'statusID'}               = $row->{'status_id'};
  $self->{'transactionDateTime'}    = $row->{'trans_date_time'};
  $self->{'transactionDate'}        = $row->{'trans_date'};
  $self->{'transactionAmount'}      = $row->{'amount'};
  $self->{'transactionStatus'}      = $row->{'trans_status'};
  $self->{'orderID'}                = $row->{'order_id'};
  $self->{'transactionID'}          = &PlugNPay::Util::binaryToHex($row->{'pnp_internal_transaction_id'});
  $self->{'transactionTypeID'}      = $row->{'transaction_type_id'};
  $self->{'authorizationCode'}      = $row->{'authorization_code'};
  $self->{'batchID'}                = $row->{'batch_id'};
  $self->{'profileID'}              = $row->{'profile_id'};
}

#############################################
# Subroutine: saveTransactionResult
# -------------------------------------------
# Description:
#   Saves results for merchant's
#   customers' recurring transactions.
sub saveTransactionResult {
  my $self = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};
  my $transactionResult = shift; # transaction response object
  my $paymentData = shift || {}; # if future payment

  my $saveStatus = new PlugNPay::Util::Status(1);
  eval {
    # trans from transaction response
    my $transaction = $transactionResult->getTransaction();

    # dates from trans
    my $transactionDate = new PlugNPay::Sys::Time('db_gm', $transaction->getTransactionDateTime());
    my $transDate = $transactionDate->inFormat('yyyymmdd');
    my $transactionDateTime = $transactionDate->inFormat('iso');

    # amount from trans
    my $amount = $transaction->getTransactionAmount();

    # status from trans response
    my $transactionStatus = $transactionResult->getStatus();

    # order and trans ID from transaction
    my $orderID = $transaction->getOrderID();
    my $transactionID = &PlugNPay::Util::hexToBinary($transaction->getPNPTransactionID());

    my $authorizationCode = $transactionResult->getAuthorizationCode();

    my $status = new PlugNPay::Merchant::Customer::Job::Status();
    my $statusID = $status->loadStatusID('PENDING');

    # profile ID, batch ID, type ID
    my $batchID           = $paymentData->{'batchID'};
    my $profileID         = $paymentData->{'profileID'};
    my $transactionTypeID = $paymentData->{'transactionTypeID'};

    my $params = [
      $merchantCustomerLinkID,
      $statusID,
      $transDate,
      $transactionDateTime,
      $amount,
      $transactionStatus,
      $orderID,
      $transactionID,
      $transactionTypeID,
      $authorizationCode,
      $batchID,
      $profileID
    ];

    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/INSERT INTO recurring1_results
        ( merchant_customer_link_id,
          status_id,
          trans_date,
          trans_date_time,
          amount,
          trans_status,
          order_id,
          pnp_internal_transaction_id,
          transaction_type_id,
          authorization_code,
          batch_id,
          profile_id )
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?)/, $params);
  };

  if ($@) {
    $self->_log({
      'error'                  => $@,
      'merchantCustomerLinkID' => $merchantCustomerLinkID,
      'function'               => 'saveTransactionResult'
    });

    $saveStatus->setFalse();
    $saveStatus->setError('Failed to save transaction results.');
  }

  return $saveStatus;
}

#############################################
# Subroutine: processMembership
# -------------------------------------------
# Description:
#   --DO NOT CALL THIS FUNCTION--
#   This subroutine gets called in a 
#   background process.
sub processMembership {
  my $self = shift;
  eval {
    $self->_processMembershipResults();
  };
}

###################################################################
# Subroutine: _processMembershipResults (Thread safe)
# -----------------------------------------------------------------
# Description:
#   Loads the recurring payments for todays date. 
#   If status is success, update profile to next bill cycle date.
#   Else, check the # of attempts, schedule next day or expire.
sub _processMembershipResults {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();

  my $results = [];

  eval {
    $dbs->begin('merchant_cust');

    # load pending and processing IDs to update the table
    my $jobStatus =  new PlugNPay::Merchant::Customer::Job::Status();
    my $pendingID = $jobStatus->loadStatusID('PENDING');
    my $processingID = $jobStatus->loadStatusID('PROCESSING');
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               merchant_customer_link_id,
               status_id,
               trans_date_time,
               trans_date,
               amount,
               trans_status,
               order_id,
               pnp_internal_transaction_id,
               transaction_type_id,
               batch_id,
               profile_id
        FROM recurring1_results
        WHERE status_id = ?
        FOR UPDATE/, [$pendingID], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        my $result = new PlugNPay::Membership::Results();
        $result->_setTransactionResultFromRow($row);
        push (@{$results}, $result);
      }

      # update the pending IDs to processing
      my $updateSQL = q/UPDATE recurring1_results
                        SET status_id = ?
                        WHERE id IN (/;
      my @params = map { '?' } @{$results};
      my @IDs = map { $_->getTransactionResultID() } @{$results};
      $dbs->executeOrDie('merchant_cust', $updateSQL . join(',', @params) . ')', [$processingID, @IDs]);
    }

    $dbs->commit('merchant_cust');
  };

  if ($@) {
    $dbs->rollback('merchant_cust');
    # this wouldn't be a huge deal as the results are never deleted until processed.
    # nonetheless alert because profiles were never updated

    my $alerter = new PlugNPay::Logging::Alert();
    $alerter->alert(9, 'Failed to process membership payments: ' . $@);

    $self->_log({
      'error' => $@,
      'function' => '_processRecurringResults',
      'message' => 'Membership transactions were not able to be processed.'
    });
  }

  # if there are results and no errors
  if (@{$results} > 0 && !$@) {
    # here is where we will post process the results
    # and create a report to be emailed to the merchants
 
    my $jobStatus = new PlugNPay::Merchant::Customer::Job::Status();

    my $completedID = $jobStatus->loadStatusID('COMPLETED');
    my $problemID = $jobStatus->loadStatusID('PROBLEM');
 
    my $merchantResults = {};
    foreach my $result (@{$results}) {
      # load billing profile
      my $profile = new PlugNPay::Membership::Profile();
      $profile->loadBillingProfile($result->getProfileID());

      my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
      $merchantCustomer->loadMerchantCustomer($profile->getMerchantCustomerLinkID());

      my $customer = new PlugNPay::Merchant::Customer();
      $customer->loadCustomer($merchantCustomer->getCustomerID());

      # create array of results for each merchant
      my $merchantName = new PlugNPay::Merchant($merchantCustomer->getMerchantID())->getMerchantUsername();

      my $gatewayAccount = new PlugNPay::GatewayAccount($merchantName);
      my $services = new PlugNPay::GatewayAccount::Services($merchantName);

      # eval this, in case something goes wrong, the profile is in sync with the results of the payment.
      my $updateMsg;
      eval {
        $dbs->begin('merchant_cust');
        if ($result->getTransactionStatus() =~ /success/i) {
          # this method reschedules the profile payment
          my $updateStatus = $profile->success($result->getTransactionAmount());
          if (!$updateStatus) {
            # failed to update profile
            $updateMsg = $updateStatus->getError();
            die; # die here to rollback
          } else {
            # if email flag is on, then email customer
            if ($gatewayAccount->getFeatures()->get('sendRecNotification') =~ /email_(customer|both)/) {
              my $company = $gatewayAccount->getMainContact()->getCompany();
              my $merchantEmail = $gatewayAccount->getMainContact()->getEmailAddress();

              my $messageData = {};
              $messageData->{'merchant'} = $merchantName;
              $messageData->{'to'} = $customer->getEmail();
              $messageData->{'from'} = $services->getFromEmail() || $merchantEmail;
              $messageData->{'subject'} = $company . " - Payment Success Notification";

              my $exposedPaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
              $exposedPaymentSource->loadExposedPaymentSource($profile->getPaymentSourceID());

              my $paymentSource = new PlugNPay::Merchant::Customer::PaymentSource();
              $paymentSource->loadPaymentSource($exposedPaymentSource->getPaymentSourceID());

              my $customerName = $merchantCustomer->getName();
              my $lastFour = $paymentSource->getLastFour();
              my $amount = $result->getTransactionAmount();
              my $notifyEmail = $services->getRecurringNotificationEmail();
              my $orderID = $result->getOrderID();
              if ($notifyEmail ne '') {
                $notifyEmail = $merchantEmail;
              }

              my $recurringMessage = "The payment account we have on file ending in $lastFour was charged $amount by $company.\n\n"
                                     . "If you have any questions about this charge, please contact $notifyEmail.\n\n\n"
                                     . "Name: $customerName\n"
                                     . "Order ID: $orderID\n"
                                     . "Amount: $amount\n";
              $messageData->{'content'} = $recurringMessage;
              $self->_notifyEmail($messageData);
            }
          }
        } else {
          # profile will be set to expired if it is the last attempt
          my $updateStatus = $profile->failure();
          if (!$updateStatus) {
            # failed to update profile
            $updateMsg = $updateStatus->getError();
            die; # die here to rollback
          } else {
            # if profile was set to expired, check to see if email flag is on, then email customer
            my $profileStatus = new PlugNPay::Membership::Profile::Status();
            $profileStatus->loadStatus($profile->getStatusID());
            if ( ($profileStatus->getStatus() =~ /expired/i) && ($gatewayAccount->getFeatures()->get('sendRecNotification') =~ /email_(customer|both)/) ) {
              my $company = $gatewayAccount->getMainContact()->getCompany();

              my $messageData = {};
              $messageData->{'merchant'} = $merchantName;
              $messageData->{'to'} = $customer->getEmail();
              $messageData->{'from'} = $services->getFromEmail() || $gatewayAccount->getMainContact()->getEmailAddress();
              $messageData->{'subject'} = $company . " - Payment Failure Notification";

              my $recurringMessage = $services->getFailedRecurringMessage();
              if ($recurringMessage ne '') {
                if ($recurringMessage =~ /\[FAILMESSAGE\]/) {
                  $recurringMessage =~ s/\[FAILMESSAGE\]/Unable to process payment. Please contact technical support./;
                }
                
                if ($recurringMessage =~ /\[PNP_username\]/) {
                  my $username = $merchantCustomer->getUsername();
                  $recurringMessage =~ s/\[PNP_username\]/$username/;
                }

                if ($recurringMessage =~ /\[PNP_company\]/) {
                  $recurringMessage =~ s/\[PNP_company\]/$company/;
                }
              } else {
                $recurringMessage = "An attempt to renew your subscription to $company has failed\n"
                                    . "because the charge was rejected by your credit card company. To\n"
                                    . "continue your subscription to our site please resubscribe with a\n"
                                    . "different credit card number.\n";
              }

              $messageData->{'content'} = $recurringMessage;
              $self->_notifyEmail($messageData);
            }
          }
        }
  
        $dbs->commit('merchant_cust');
      };

      if ($@) {
        $dbs->rollback('merchant_cust');

        $self->_log({
          'error'        => $@,
          'errorMessage' => $updateMsg,
          'function'     => '_processMembershipResults'
        });

        # mark the result as PROBLEM state.
        $dbs->executeOrDie('merchant_cust',
          q/UPDATE recurring1_results
            SET status_id = ?
            WHERE id = ?/, [$problemID, $result->getTransactionResultID()]);
      } else {
        # mark the result as COMPLETED state.
        $dbs->executeOrDie('merchant_cust',
          q/UPDATE recurring1_results
            SET status_id = ?
            WHERE id = ?/, [$completedID, $result->getTransactionResultID()]);

        # push into merchant batch of results
        push (@{$merchantResults->{$merchantName}}, $result);
      }
    }

    # done with parsing results
    foreach my $merchant (keys %{$merchantResults}) {
      # create a report for the merchant
      $self->_postProcessResults($merchant, $merchantResults->{$merchant});
    }
  }

  return 1;
}

###################################################################
# Subroutine: _postProcessResults
# ----------------------------------------------------------------
# Description:
#   Inputs merchant and a list of transaction results for
#   that merchant. The transaction results will be iterated 
#   through to create an email list of success and failures for 
#   the merchant. Also, refresh will be performed if necessary.
sub _postProcessResults {
  my $self = shift;
  my $merchant = shift;
  my $transactionResults = shift;

  my $gatewayAccount = new PlugNPay::GatewayAccount($merchant);
  my $services = new PlugNPay::GatewayAccount::Services($merchant);

  my $successList = '';
  my $failureList = '';
  foreach my $result (@{$transactionResults}) {
    # merchant customer link object
    my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
    $merchantCustomer->loadMerchantCustomer($result->getMerchantCustomerLinkID());

    # build email listing of successes and failures
    if ($result->getTransactionStatus() =~ /success/i) {
      $successList .= $merchantCustomer->getUsername() . ' ' . 
                      $merchantCustomer->getName() . ' ' . 
                      $result->getTransactionAmount() . ' ' . 
                      $result->getOrderID() . ' ' . 
                      $result->getAuthorizationCode() . "\n";
    } else {
      $failureList .= $merchantCustomer->getUsername() . ' ' .
                      $merchantCustomer->getName() . ' ' .
                      $result->getTransactionAmount() . "\n";
    }
  }
  
  if ( ($gatewayAccount->getFeatures()->get('sendRecNotification') =~ /email_(merchant|both)/) && ($successList ne '') ) {
    my $messageData = {};
    $messageData->{'merchant'} = $merchant;
 
    if ($services->getRecurringNotificationEmail()) {
      $messageData->{'to'} = $services->getRecurringNotificationEmail();
    } else {
      $messageData->{'to'} = $gatewayAccount->getMainContact()->getEmailAddress();
    }
  
    my $reseller = new PlugNPay::Reseller($gatewayAccount->getReseller());
    my $companies = $reseller->loadPrivateLabelCompany();
 
    my $from;
    if ($companies->{$reseller->getResellerAccount()}) {
      $from = $companies->{$reseller->getResellerAccount()};
    } else {
      $from = $companies->{'plugnpay'};
    }

    $messageData->{'from'} = $from;
    $messageData->{'subject'} = "$merchant - $from Recurring Payment Success Notification";
    $messageData->{'content'} = $successList;
    $self->_notifyEmail($messageData);
  }

  if ( ($services->getEmailChoice() =~ /email_(failure|merchant|both)/) && ($failureList ne '') ) {
    my $messageData = {};
    $messageData->{'merchant'} = $merchant;

    if ($services->getRecurringNotificationEmail()) {
      $messageData->{'to'} = $services->getRecurringNotificationEmail();
    } else {
      $messageData->{'to'} = $gatewayAccount->getMainContact()->getEmailAddress();
    }
 
    my $reseller = new PlugNPay::Reseller($gatewayAccount->getReseller());
    my $companies = $reseller->loadPrivateLabelCompany();

    my $from;
    if ($companies->{$reseller->getResellerAccount()}) {
      $from = $companies->{$reseller->getResellerAccount()};
    } else {
      $from = $companies->{'plugnpay'};
    }

    $messageData->{'from'} = $from;
    $messageData->{'bcc'} = "cprice\@plugnpay.com";
    $messageData->{'subject'} = "$merchant - $from Recurring Payment Failure Notification";
    $messageData->{'content'} = $failureList;
    $self->_notifyEmail($messageData);
  }

  # check if refresh necessary
  if ($services->getRefresh()) {
    my $passwordManagement = new PlugNPay::Membership::PasswordManagement();
    $passwordManagement->refresh($merchant); # results will be logged in pwd mgt
  }
}

##########################################
# Subroutine: _notifyEmail
# ---------------------------------------
# Description: 
#   Helper function to send email
sub _notifyEmail {
  my $self = shift;
  my $messageData = shift;

  my $email = new PlugNPay::Email();
  $email->setVersion('legacy');
  $email->setGatewayAccount($messageData->{'merchant'});
  $email->setTo($messageData->{'to'});
  $email->setFrom($messageData->{'from'});
  $email->setCC($messageData->{'cc'}) if $messageData->{'cc'};
  $email->setBCC($messageData->{'bcc'}) if $messageData->{'bcc'};
  $email->setSubject($messageData->{'subject'});
  $email->setContent($messageData->{'content'});
  $email->setFormat('text');
  $email->send();
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_history' });
  $logger->logInfo($logInfo);
}

1;
