package PlugNPay::Membership::Profile;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::Util::Status;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Membership::Plan;
use PlugNPay::Membership::Group;
use PlugNPay::Util::RandomString;
use PlugNPay::Merchant::Customer::Link;
use PlugNPay::GatewayAccount::Services;
use PlugNPay::Membership::Plan::Settings;
use PlugNPay::Membership::Plan::BillCycle;
use PlugNPay::Membership::Profile::Status;
use PlugNPay::Membership::PasswordManagement;
use PlugNPay::Membership::Profile::BillMember;
use PlugNPay::Merchant::Customer::FuturePayment;
use PlugNPay::Merchant::Customer::PaymentSource;
use PlugNPay::Merchant::Customer::PaymentSource::Expose;

########################################################
# Module: Profile
# ------------------------------------------------------
# Description:
#   Customer billing profiles. Contain information about
#   the payment plan, their payment source, status on
#   the merchant's remote site, and information for the
#   current billing period.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  
  return $self;
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

sub setBillingProfileID {
  my $self = shift;
  my $profileID = shift;
  $self->{'billingProfileID'} = $profileID;
}

sub getBillingProfileID {
  my $self = shift;
  return $self->{'billingProfileID'};
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

sub setPlanSettingsID {
  my $self = shift;
  my $planSettingsID = shift;
  $self->{'planSettingsID'} = $planSettingsID;
}

sub getPlanSettingsID {
  my $self = shift;
  return $self->{'planSettingsID'};
}

sub setBalance {
  my $self = shift;
  my $balance = shift;
  $self->{'balance'} = $balance;
}

sub getBalance {
  my $self = shift;
  return $self->{'balance'};
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

sub setStatusID {
  my $self = shift;
  my $statusID = shift;
  $self->{'statusID'} = $statusID;
}

sub getStatusID {
  my $self = shift;
  return $self->{'statusID'};
}

sub setLoyaltyCount {
  my $self = shift;
  my $loyaltyCount = shift;
  $self->{'loyaltyCount'} = $loyaltyCount;
}

sub getLoyaltyCount {
  my $self = shift;
  return $self->{'loyaltyCount'};
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

sub setCurrentCycleStartDate {
  my $self = shift;
  my $currentCycleStartDate = shift;
  $self->{'currentCycleStartDate'} = $currentCycleStartDate;
}

sub getCurrentCycleStartDate {
  my $self = shift;
  return $self->{'currentCycleStartDate'};
}

sub setCurrentCycleEndDate {
  my $self = shift;
  my $currentCycleEndDate = shift;
  $self->{'currentCycleEndDate'} = $currentCycleEndDate;
}

sub getCurrentCycleEndDate {
  my $self = shift;
  return $self->{'currentCycleEndDate'};
}

sub setLastSuccessfulBillDate {
  my $self = shift;
  my $lastBillDate = shift;
  $self->{'lastSuccessfulBillDate'} = $lastBillDate;
}

sub getLastSuccessfulBillDate {
  my $self = shift;
  return $self->{'lastSuccessfulBillDate'};
}

sub setLastAttemptDate {
  my $self = shift;
  my $lastAttemptDate = shift;
  $self->{'lastAttemptDate'} = $lastAttemptDate;
}

sub getLastAttemptDate {
  my $self = shift;
  return $self->{'lastAttemptDate'};
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

sub setPartialDayCredit {
  my $self = shift;
  my $partialDayCredit = shift;
  $self->{'partialDayCredit'} = $partialDayCredit;
}

sub getPartialDayCredit {
  my $self = shift;
  return $self->{'partialDayCredit'};
}

sub setChargeSignUpFee {
  my $self = shift;
  my $chargeSignUpFee = shift;
  $self->{'chargeSignUpFee'} = $chargeSignUpFee;
}

sub getChargeSignUpFee {
  my $self = shift;
  return $self->{'chargeSignUpFee'};
}

sub setAllowRenewal {
  my $self = shift;
  my $allowRenewal = shift;
  $self->{'allowRenewal'} = $allowRenewal;
}

sub getAllowRenewal {
  my $self = shift;
  return $self->{'allowRenewal'};
}

sub setAttempts {
  my $self = shift;
  my $attempts = shift;
  $self->{'attempts'} = $attempts;
}

sub getAttempts {
  my $self = shift;
  return $self->{'attempts'};
}

##############################################
# Subroutine: loadBillingProfiles
# --------------------------------------------
# Description:
#   Loads all the profiles for a given 
#   merchant customer link ID.
sub loadBillingProfiles {
  my $self = shift;
  my $merchantCustomerLinkID = shift;

  my $customerProfiles = [];

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               merchant_customer_link_id,
               plan_settings_id, 
               status_id,
               payment_source_id,
               balance,
               loyalty_count,
               creation_date,
               current_cycle_start_date,
               current_cycle_end_date,
               last_successful_bill_date,
               last_attempt_date,
               description,
               partial_day_credit,
               charge_signup_fee,
               allow_renewal,
               attempts
        FROM recurring1_profile
        WHERE merchant_customer_link_id = ?/, [$merchantCustomerLinkID], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        my $profile = new PlugNPay::Membership::Profile();
        $profile->_setBillingProfileDataFromRow($row);
        push (@{$customerProfiles}, $profile);
      } 
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadBillingProfiles'
    });
  }

  return $customerProfiles;
}

################################################
# Subroutine: loadBillingProfile
# ----------------------------------------------
# Description:
#   Loads billing profile based on id in table.
sub loadBillingProfile {
  my $self = shift;
  my $billingProfileID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               merchant_customer_link_id,
               plan_settings_id,
               status_id,
               payment_source_id,
               balance,
               loyalty_count,
               creation_date,
               current_cycle_start_date,
               current_cycle_end_date,
               last_successful_bill_date,
               last_attempt_date,
               description,
               partial_day_credit,
               charge_signup_fee,
               allow_renewal,
               attempts
        FROM recurring1_profile
        WHERE id = ?/, [$billingProfileID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setBillingProfileDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadBillingProfile'
    });
  }
}

sub _setBillingProfileDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'billingProfileID'}       = $row->{'id'};
  $self->{'identifier'}             = $row->{'identifier'};
  $self->{'merchantCustomerLinkID'} = $row->{'merchant_customer_link_id'};
  $self->{'planSettingsID'}         = $row->{'plan_settings_id'};
  $self->{'statusID'}               = $row->{'status_id'};
  $self->{'paymentSourceID'}        = $row->{'payment_source_id'};
  $self->{'balance'}                = $row->{'balance'};
  $self->{'loyaltyCount'}           = $row->{'loyalty_count'};
  $self->{'creationDate'}           = $row->{'creation_date'};
  $self->{'currentCycleStartDate'}  = $row->{'current_cycle_start_date'};
  $self->{'currentCycleEndDate'}    = $row->{'current_cycle_end_date'};
  $self->{'lastSuccessfulBillDate'} = $row->{'last_successful_bill_date'};
  $self->{'lastAttemptDate'}        = $row->{'last_attempt_date'};
  $self->{'description'}            = $row->{'description'};
  $self->{'partialDayCredit'}       = $row->{'partial_day_credit'};
  $self->{'chargeSignUpFee'}        = $row->{'charge_signup_fee'};
  $self->{'allowRenewal'}           = $row->{'allow_renewal'};
  $self->{'attempts'}               = $row->{'attempts'};
}

####################################################
# Subroutine: saveBillingProfile
# --------------------------------------------------
# Description:
#   Saves a billing profile for a given customer.
sub saveBillingProfile {
  my $self = shift;
  my $merchantCustomerLinkID = shift;
  my $data = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $status = new PlugNPay::Util::Status(1);

  my $saveResponse = {};

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
  $merchantCustomer->loadMerchantCustomer($merchantCustomerLinkID);
  my $merchantID = $merchantCustomer->getMerchantID();

  my $plan = new PlugNPay::Membership::Plan($merchantID);
  $plan->loadByMerchantPlanID($data->{'planID'});
  if (!$plan->getPlanID()) {
    $status->setFalse();
    $status->setError('Invalid payment plan id.');
    return $status;
  }

  my $insertedProfileID; # used if successful eval

  my @errorMsg;
  eval {
    $dbs->begin('merchant_cust');

    my $planSettings = new PlugNPay::Membership::Plan::Settings($merchantID);
    $planSettings->loadPlanSettings($plan->getPlanSettingsID());

    my $billCycle = new PlugNPay::Membership::Plan::BillCycle();
    $billCycle->loadBillCycle($planSettings->getBillCycleID());

    my $paymentSourceID;
    if (!$data->{'paymentSourceID'}) {
      if ( ($planSettings->getRecurringFee() > 0) || ($planSettings->getLoyaltyFee() > 0) ) {
        push (@errorMsg, 'Payment source required for this profile.'); 
      } elsif ( ($planSettings->getSignUpFee() > 0) && ($data->{'chargeSignUpFee'} != 0) ) {
        push (@errorMsg, 'Payment source required for sign up fee.');
      } else {
        $paymentSourceID = undef;
      }
    } else {
      my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
      $exposePaymentSource->loadByLinkIdentifier($data->{'paymentSourceID'}, $merchantCustomerLinkID);
      if (!$exposePaymentSource->getLinkID()) {
        push (@errorMsg, 'Invalid customer payment source identifier.');
      } else {
        $paymentSourceID = $exposePaymentSource->getLinkID();
      }
    }

    my $description = $data->{'description'};
    my $time = new PlugNPay::Sys::Time();
    my $creationTime = $time->nowInFormat('iso');
  
    my $cycleEndDate;
    if ($billCycle->getCycleDuration() == 0) {
      if (!$data->{'currentCycleEndDate'}) {
        $data->{'currentCycleEndDate'} = '99990909';
      }

      if ($data->{'currentCycleEndDate'} le $time->nowInFormat('yyyymmdd')) {
        push (@errorMsg, 'End date for billing profile cannot be today or before today.');
      } else {
        if ($data->{'currentCycleEndDate'} =~ /^(\d{4})(\d{2})(\d{2})$/) {
          if (!$time->validDate($3, $2, $1)) {
            push (@errorMsg, 'Invalid end date.');
          } else {
            $cycleEndDate = new PlugNPay::Sys::Time('yyyymmdd', $data->{'currentCycleEndDate'})->inFormat('iso');
          }
        } else {
          push (@errorMsg, 'Invalid end date format (use YYYY/MM/DD).');
        }
      }
    } else {
      my $totalDelayDays = (($planSettings->getInitialMonthDelay() * 30) + $planSettings->getInitialDayDelay());
      $time->addDays($totalDelayDays);
      $cycleEndDate = $time->inFormat('iso');
    }

    # check plan type
    my $plan = new PlugNPay::Membership::Plan();
    $plan->loadPaymentPlan($planSettings->getPlanID());

    my $planType = new PlugNPay::Membership::Plan::Type();
    $planType->loadPlanType($plan->getPlanTransactionTypeID());
    my $transactionType = $planType->getType();

    # charge sign up fee unless option is passed in to omit or charge with first payment
    # if plan transaction type is credit based, there is no sign up fee
    my $chargeSignUpFee = 1;
    my $billMemberImmediately = 0;
    if ($data->{'chargeSignUpFee'} == 0) {
      $chargeSignUpFee = 0;
    } else {
      if ($data->{'chargeImmediately'}) {
        $billMemberImmediately = 1;
      }
    }

    if ($transactionType =~ /credit/i) {
      $chargeSignUpFee = 0;
    }

    # if they don't get recur billed and they are trying to charge a valid sign up fee with their first
    # recur bill payment that obviously wouldn't work.
    if ($chargeSignUpFee == 1 && $billCycle->getCycleDuration() == 0) {
      push (@errorMsg, 'Unable to schedule sign up fee with first payment, bill cycle is 0.');
    }

    my $profileStatus = new PlugNPay::Membership::Profile::Status();
    if ($data->{'status'} =~ /^\d+$/) {
      $profileStatus->loadStatus($data->{'status'});
    } else {
      $profileStatus->loadStatusID($data->{'status'});
    }

    if (!$profileStatus->getStatusID()) {
      push (@errorMsg, 'Invalid billing profile status.');
    }

    my $allowRenewal = (exists $data->{'allowRenewal'} ? $data->{'allowRenewal'} : 1); # default allow renewal
    my $identifier = $self->_generateUniqueProfileID($merchantCustomerLinkID);

    if (@errorMsg == 0) {
      my $params = [
        $identifier,
        $merchantCustomerLinkID, 
        $plan->getPlanSettingsID(), 
        $profileStatus->getStatusID(),
        $paymentSourceID,
        $planSettings->getBalance(),
        0,
        $creationTime,
        $creationTime,
        $cycleEndDate,
        $description,
        0,
        $chargeSignUpFee,
        $allowRenewal,
        0
      ];

      my $sth = $dbs->executeOrDie('merchant_cust',
        q/INSERT INTO recurring1_profile
          ( identifier,
            merchant_customer_link_id,
            plan_settings_id,
            status_id,
            payment_source_id,
            balance,
            loyalty_count,
            creation_date,
            current_cycle_start_date,
            current_cycle_end_date,
            description,
            partial_day_credit,
            charge_signup_fee,
            allow_renewal,
            attempts )
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)/, $params)->{'sth'};
      $insertedProfileID = $sth->{'mysql_insertid'};

      my $group = new PlugNPay::Membership::Group($merchantID);
      if (exists $data->{'groups'}) {
        if (ref($data->{'groups'}) eq 'ARRAY') {
          my $saveProfileGroupStatus = $group->saveProfileGroups($insertedProfileID, $data->{'groups'});
          if (!$saveProfileGroupStatus) {
            push (@errorMsg, $saveProfileGroupStatus->getError());
          }
        } else {
          push (@errorMsg, 'Invalid group data format.');
        }
      }

      if (@errorMsg == 0) {
        if ($billCycle->getCycleDuration() != 0) {
          my $futurePayment = new PlugNPay::Merchant::Customer::FuturePayment();
          my $scheduleStatus = $futurePayment->scheduleRecurringPayment($insertedProfileID);
          if (!$scheduleStatus) {
            push (@errorMsg, $scheduleStatus->getError());
          } else {
            if ($billMemberImmediately && $chargeSignUpFee) {
              my $billMember = new PlugNPay::Membership::Profile::BillMember($merchantID);
              my $response = $billMember->billMemberProfile($merchantCustomerLinkID, 
                                                            $identifier, {
                'amount'      => $planSettings->getSignUpFee(),
                'description' => 'Sign up fee -- ' . $identifier,
                'isSignUpFee' => 1
              });

              if (!$response->{'status'}) {
                push (@errorMsg, $response->{'status'}->getError());
              } else {
                $saveResponse->{'transaction'} = $response->{'transactionDetails'};
              }
            }
          }
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      $self->_log({
        'error'                  => $@,
        'function'               => 'saveBillingProfile',
        'merchantCustomerLinkID' => $merchantCustomerLinkID
      });

      push (@errorMsg, 'Error while attempting to save billing profile.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');

    my $gatewayAccount = new PlugNPay::Merchant($merchantID)->getMerchantUsername();
    my $services = new PlugNPay::GatewayAccount::Services($gatewayAccount);
    # if refresh add to password managemnet
    if ($services->getRefresh()) {
      my $passwordManagement = new PlugNPay::Membership::PasswordManagement();
      $passwordManagement->manageCustomer($insertedProfileID);
    }
  }

  $saveResponse->{'status'} = $status;
  return $saveResponse;
}

####################################################
# Subroutine: updateBillingProfile
# --------------------------------------------------
# Description:
#   Updates a billing profile. This subroutine must
#   update the scheduled pending future payment.
#   If status changes, this must call password 
#   management to reflect changes on remote server.
#   This subroutine expects the profile to be
#   loaded in the object calling update.
sub updateBillingProfile {
  my $self = shift;
  my $updateData = shift;
  
  my $updateStatus = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
  $merchantCustomer->loadMerchantCustomer($self->{'merchantCustomerLinkID'});
  my $merchantID = $merchantCustomer->getMerchantID();

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');

    my $currentPlanSettings = new PlugNPay::Membership::Plan::Settings();
    $currentPlanSettings->loadPlanSettings($self->{'planSettingsID'});

    my ($billCycleID, $currencyID, $signupFee, $recurringFee, $loyaltyFee, $loyaltyCount, $balance);
    my ($initialDayDelay, $initialMonthDelay);
    my ($currentCycleStartDate, $currentCycleEndDate);
    my ($chargeSignupFee);

    ########################
    # Update plan settings #
    ########################

    $chargeSignupFee = $self->{'chargeSignUpFee'};
    if ($chargeSignupFee) {
      ###################################
      # Update sign up fee if not paid  #
      ###################################
      if (exists $updateData->{'signupFee'}) {
        if (!$currentPlanSettings->_validateMonetaryValue($updateData->{'signupFee'})) {
          push (@errorMsg, 'Invalid sign up fee value.');
        } else {
          $signupFee = $updateData->{'signupFee'};
          if ($signupFee == 0) {
            $chargeSignupFee = 0;
          }
        }
      } else {
        $signupFee = $currentPlanSettings->getSignUpFee();
      }
    } else {
      $signupFee = $currentPlanSettings->getSignUpFee();
    }

    #######################
    # Update currency ID  #
    #######################

    if (exists $updateData->{'currency'}) {
      my $currency = new PlugNPay::Membership::Plan::Currency();
      if ($updateData->{'currency'} =~ /^\d+$/) {
        $currency->loadCurrency($updateData->{'currency'});
      } else {
        $updateData->{'currency'} =~ s/[^a-zA-Z]//g;
        $currency->loadCurrencyID($updateData->{'currency'});
      }

      if (!$currency->getCurrencyID()) {
        push (@errorMsg, 'Invalid currency.');
      } else {
        $currencyID = $currency->getCurrencyID();
      }
    } else {
      $currencyID = $currentPlanSettings->getCurrencyID();
    }

    #####################
    # Update bill cycle #
    #####################

    if (exists $updateData->{'billCycle'}) {
      my $billCycleObj = new PlugNPay::Membership::Plan::BillCycle();
      if ($updateData->{'billCycle'} =~ /^\d+$/) {
        $billCycleObj->loadBillCycle($updateData->{'billCycle'});
      } else {
        $billCycleObj->loadBillCycleID($updateData->{'billCycle'});
      }

      if (!$billCycleObj->getBillCycleID()) {
        push (@errorMsg, 'Invalid bill cycle value.');
      } else {
        $billCycleID = $billCycleObj->getBillCycleID();
      }
    } else {
      $billCycleID = $currentPlanSettings->getBillCycleID();
    }

    if (@errorMsg == 0) {
      my $billCycle = new PlugNPay::Membership::Plan::BillCycle();
      $billCycle->loadBillCycle($billCycleID);

      if ($billCycle->getCycleDuration() == 0) {
        #########################
        # If billing cycle is 0 #
        #########################
        $recurringFee = 0;
        $loyaltyFee = 0;
        $loyaltyCount = 0;
        $initialDayDelay = 0;
        $initialMonthDelay = 0;
        $balance = undef;
      } else {
        ################################
        # If billing cycle is non zero #
        ################################
        if (exists $updateData->{'recurringFee'}) {
          if (!$currentPlanSettings->_validateMonetaryValue($updateData->{'recurringFee'})) {
            push (@errorMsg, 'Recurring fee is not valid.');
          } else {
            $recurringFee = $updateData->{'recurringFee'};
          }
        } else {
          $recurringFee = $currentPlanSettings->getRecurringFee();
        }

        if (exists $updateData->{'loyaltyFee'}) {
          if (!$currentPlanSettings->_validateMonetaryValue($updateData->{'loyaltyFee'})) {
            push (@errorMsg, 'Loyalty fee is not valid.');
          } else {
            $loyaltyFee = $updateData->{'loyaltyFee'};
          }
        } else {
          $loyaltyFee = $currentPlanSettings->getLoyaltyFee();
        }

        if (exists $updateData->{'loyaltyCount'}) {
          if ($updateData->{'loyaltyCount'} !~ /^\d+$/) {
            push (@errorMsg, 'Loyalty count is not valid.');
          } else {
            $loyaltyCount = $updateData->{'loyaltyCount'};
          }
        } else {
          $loyaltyCount = $currentPlanSettings->getLoyaltyCount();
        }

        if (exists $updateData->{'initialDayDelay'} || exists $updateData->{'initialMonthDelay'}) {
          $initialDayDelay   = $updateData->{'initialDayDelay'};
          $initialMonthDelay = $updateData->{'initialMonthDelay'};
 
          if ($initialDayDelay !~ /^\d+$/) {
            push (@errorMsg, 'Invalid day delay.');
          }

          if ($initialMonthDelay !~ /^\d+$/) {
            push (@errorMsg, 'Invalid month delay.');
          }
        } else {
          $initialMonthDelay = $currentPlanSettings->getInitialMonthDelay();
          $initialDayDelay = $currentPlanSettings->getInitialDayDelay();
        }

        ####################################
        # Balance is transfered to profile #
        ####################################
 
        $balance = $currentPlanSettings->getBalance();
      }

      if (@errorMsg == 0) {
        my $updatePlanSettings = new PlugNPay::Membership::Plan::Settings($merchantID);
        $updatePlanSettings->setPlanID($currentPlanSettings->getPlanID());
        $updatePlanSettings->setSignUpFee($signupFee);
        $updatePlanSettings->setRecurringFee($recurringFee);
        $updatePlanSettings->setLoyaltyFee($loyaltyFee);
        $updatePlanSettings->setLoyaltyCount($loyaltyCount);
        $updatePlanSettings->setBillCycleID($billCycleID);
        $updatePlanSettings->setBalance($balance);
        $updatePlanSettings->setInitialMonthDelay($initialMonthDelay);
        $updatePlanSettings->setInitialDayDelay($initialDayDelay);
        $updatePlanSettings->setCurrencyID($currencyID);

        my $updateDigest = $updatePlanSettings->createDigest();
        $updatePlanSettings->setDigest($updateDigest);

        my ($sth, $planSettingsID, $settingsChanged);
        if ($updateDigest ne $currentPlanSettings->getDigest()) {
          $settingsChanged = 1;
          $updatePlanSettings->savePlanSettings();
          $planSettingsID = $updatePlanSettings->getPlanSettingsID();
        } else {
          $planSettingsID = $self->{'planSettingsID'};
        }

        ##################
        # Update profile #
        ##################

        my $billCycleChange = 0;
        if ($billCycle->getBillCycleID() != $currentPlanSettings->getBillCycleID()) {
          $billCycleChange = 1;
          $currentCycleStartDate = new PlugNPay::Sys::Time()->nowInFormat('iso'); # new start cycle date
        } else {
          $currentCycleStartDate = $self->{'currentCycleStartDate'};
          $currentCycleEndDate = $self->{'currentCycleEndDate'};
        }

        if ($billCycle->getCycleDuration() == 0) {
          ######################################
          # Update end date if bill cycle is 0 #
          ######################################

          if (exists $updateData->{'currentCycleEndDate'}) {
            if ($updateData->{'currentCycleEndDate'} =~ /^(\d{4})(\d{2})(\d{2})$/) {
              my $timeObj = new PlugNPay::Sys::Time();
              if (!$timeObj->validDate($3, $2, $1)) {
                push (@errorMsg, 'Invalid billing profile end date.');
              } else {
                $currentCycleEndDate = new PlugNPay::Sys::Time('yyyymmdd', $updateData->{'currentCycleEndDate'})->inFormat('iso');
              }
            } else {
              push (@errorMsg, 'Invalid end date format (use YYYY/MM/DD).');
            }
          } else {
            $currentCycleEndDate = new PlugNPay::Sys::Time('yyyymmdd', '99990909')->inFormat('iso');
          }
        } else {
          ##########################################################
          # Update end date if not billed OR bill cycle is changed #
          ##########################################################
          if ( ((exists $updateData->{'initialDayDelay'} || exists $updateData->{'initialMonthDelay'}) && !$self->{'lastSuccessfulBillDate'}) || ($billCycleChange) ) {
            my $delayDates = new PlugNPay::Sys::Time();
            $delayDates->addDays((($initialMonthDelay) * 31) + $initialDayDelay);
            $currentCycleEndDate = $delayDates->inFormat('iso');
          }
        }

        ##############################################
        # Update description and ensure it is unique #
        ##############################################

        my $description = exists $updateData->{'description'} ? $updateData->{'description'} : $self->{'description'};

        #################################
        # Update profile payment source #
        #################################

        my $paymentSourceID;
        if (exists $updateData->{'paymentSourceID'} && !$updateData->{'paymentSourceID'}) {
          if ( ($updatePlanSettings->getRecurringFee() > 0 || $updatePlanSettings->getLoyaltyFee() > 0) ) {
            push (@errorMsg, 'Payment source required for this billing profile.');
          } elsif ( ($self->{'chargeSignUpFee'}) && ($updatePlanSettings->getSignUpFee() > 0) ) {
            push (@errorMsg, 'Payment source required for sign up fee.');
          } else {
            $paymentSourceID = undef;
          }
        } elsif ($updateData->{'paymentSourceID'}) {
          my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
          $exposePaymentSource->loadByLinkIdentifier($updateData->{'paymentSourceID'}, $self->{'merchantCustomerLinkID'});
          $paymentSourceID = $exposePaymentSource->getLinkID();
          if (!$paymentSourceID) {
            push (@errorMsg, 'Invalid customer payment source identifier.');
          }
        } else {
          if (!$self->{'paymentSourceID'}) {
            if ( ($updatePlanSettings->getRecurringFee() > 0) && ($updatePlanSettings->getLoyaltyFee() > 0) ) {
              push (@errorMsg, 'Payment source required for this profile.');
            } elsif ( ($self->{'chargeSignUpFee'}) && ($updatePlanSettings->getSignUpFee() > 0) ) {
              push (@errorMsg, 'Payment source required for sign up fee.');
            }
          }

          $paymentSourceID = $self->{'paymentSourceID'};
        }

        if (@errorMsg == 0) {
          #####################################
          # Update customer remaining balance #
          #####################################

          my $updatedSettings = new PlugNPay::Membership::Plan::Settings($merchantID);
          $updatedSettings->loadPlanSettings($planSettingsID);

          my $customerBalance;
          if ($updatedSettings->getInstallBilling()) {
            if (exists $updateData->{'customerBalance'}) {
              if (!$updatedSettings->_validateMonetaryValue($updateData->{'customerBalance'})) {
                push (@errorMsg, 'Customer balance is not valid.');
              } else {
                $customerBalance = $updateData->{'customerBalance'};
              }
            } else {
              $customerBalance = $self->{'balance'};
            }
          }

          ########################
          # Update allow renewal #
          ########################

          my $allowRenewal;
          if (exists $updateData->{'allowRenewal'}) {
            if ($updateData->{'allowRenewal'} !~ /^0|1$/) {
              push (@errorMsg, 'Invalid allow renewal value.');
            } else {
              $allowRenewal = $updateData->{'allowRenewal'};
            }
          } else {
            $allowRenewal = $self->{'allowRenewal'};
          }

          ############################
          # Update status of profile #
          ############################

          my $statusID;
          if (exists $updateData->{'status'}) {
            my $currentStatus = new PlugNPay::Membership::Profile::Status();
            $currentStatus->loadStatus($self->{'statusID'});
   
            my $updateStatus = new PlugNPay::Membership::Profile::Status();
            if ($updateData->{'status'} =~ /^\d+$/) {
              $updateStatus->loadStatus($updateData->{'status'});
            } else {
              $updateStatus->loadStatusID($updateData->{'status'});
            }
  
            if (!$updateStatus->getStatusID()) {
              push (@errorMsg, 'Invalid billing profile status.');
            } elsif ( ($currentStatus->getStatus() ne 'active') && ($updateStatus->getStatus() eq 'active') && (!$allowRenewal) ) {
              push (@errorMsg, 'Profile is unable to be renewed.');
            } else {
              $statusID = $updateStatus->getStatusID();
            }
          } else {
            $statusID = $self->{'statusID'};
          }
  
          if (@errorMsg == 0) {
            my $params = [
              $planSettingsID,          
              $statusID,
              $paymentSourceID,
              $customerBalance,
              $description,
              $currentCycleStartDate,
              $currentCycleEndDate,
              $allowRenewal,
              $chargeSignupFee,
              $self->{'billingProfileID'}
            ];
  
            $dbs->executeOrDie('merchant_cust',
              q/UPDATE recurring1_profile
                SET plan_settings_id = ?,
                    status_id = ?,
                    payment_source_id = ?,
                    balance = ?,
                    description = ?,
                    current_cycle_start_date = ?,
                    current_cycle_end_date = ?,
                    allow_renewal = ?,
                    charge_signup_fee = ?
                WHERE id = ?/, $params);
  
            if (exists $updateData->{'groups'}) {
              if (ref($updateData->{'groups'}) =~ /ARRAY/) {
                my $group = new PlugNPay::Membership::Group($merchantID);
                my $updateGroupStatus = $group->updateProfileGroups($self->{'billingProfileID'}, 
                                                                    $updateData->{'groups'});
                if (!$updateGroupStatus) {
                  push (@errorMsg, $updateGroupStatus->getError());
                }
              }
            }
  
            if (@errorMsg == 0) {
              # remove the pending future payment in the table and just reschedule.
              my $futurePayment = new PlugNPay::Merchant::Customer::FuturePayment();
              if (!$futurePayment->removePendingRecurring($self->{'billingProfileID'})) {
                push (@errorMsg, 'Unable to remove scheduled payment. Please contact technical support.');
              } else {
                my $scheduleStatus = $futurePayment->scheduleRecurringPayment($self->{'billingProfileID'});
                if (!$scheduleStatus) {
                  push (@errorMsg, $scheduleStatus->getError());
                }
              }
  
              if ($settingsChanged) {
                # if the settings are not used in any other billing profiles AND not active
                if (!$self->isPlanSettingsUsedByProfile($self->{'planSettingsID'}) && !$currentPlanSettings->isActiveSettings()) {
                  $currentPlanSettings->deletePlanSettings($self->{'planSettingsID'});
                }
              }
            }
          }
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      $self->_log({
        'error'                  => $@,
        'function'               => 'updateBillingProfile',
        'merchantCustomerLinkID' => $self->{'merchantCustomerLinkID'}
      });

      push (@errorMsg, 'Error while attempting to update billing profile.');
    }

    $updateStatus->setFalse();
    $updateStatus->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');

    my $gatewayAccount = new PlugNPay::Merchant($merchantID)->getMerchantUsername();
    my $services = new PlugNPay::GatewayAccount::Services($gatewayAccount);
    # if refresh add to password managemnet
    if ($services->getRefresh()) {
      my $passwordManagement = new PlugNPay::Membership::PasswordManagement();
      $passwordManagement->manageCustomer($self->{'billingProfileID'});
    }
  }
  
  return $updateStatus;
}

############################################################
# Subroutine: deleteBillingProfile
# ----------------------------------------------------------
# Description:
#   Deletes a billing profile from customer records. Must 
#   call password remote to remove from remote server.
sub deleteBillingProfile {
  my $self = shift;
  my $billingProfileID = shift || $self->{'billingProfileID'};

  my $deleteStatus = new PlugNPay::Util::Status(1);

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
  $merchantCustomer->loadMerchantCustomer($self->{'merchantCustomerLinkID'});

  if (!$self->{'planSettingsID'}) {
    $self->loadBillingProfile($billingProfileID);
  }
   
  my $planSettings = new PlugNPay::Membership::Plan::Settings();
  $planSettings->loadPlanSettings($self->{'planSettingsID'});
  my $planID = $planSettings->getPlanID();

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM recurring1_profile
        WHERE id = ?/, [$billingProfileID]);  
    if (!$self->isPlanSettingsUsedByProfile($self->{'planSettingsID'}) && !$planSettings->isActiveSettings()) {
      $planSettings->deletePlanSettings($self->{'planSettingsID'});
    }
  };
  
  if ($@) {
    $dbs->rollback('merchant_cust');
    $self->_log({
      'error'            => $@,
      'function'         => 'deleteBillingProfile',
      'billingProfileID' => $billingProfileID
    });

    $deleteStatus->setFalse();
    $deleteStatus->setError('Error while attempting to delete billing profile.');
  } else {
    $dbs->commit('merchant_cust');

    # password management
    my $gatewayAccount = new PlugNPay::Merchant($merchantCustomer->getMerchantID())->getMerchantUsername();
    my $services = new PlugNPay::GatewayAccount::Services($gatewayAccount);
    if ($services->getRefresh()) {
      # explicitly call remove from remote
      my $passwordManagement = new PlugNPay::Membership::PasswordManagement();
      $passwordManagement->removeCustomer($merchantCustomer->getUsername(), 
                                          $planID);
    }
  }

  return $deleteStatus;
}

###########################################
# Subroutine: isPaymentSourceUsed
# -----------------------------------------
# Description:
#   Inputs a payment source ID. If it isn't
#   being used in a billing profile, it
#   return 0
sub isPaymentSourceUsed {
  my $self = shift;
  my $paymentSourceID = shift;

  my $inUse = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `inUse`
        FROM recurring1_profile
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

###########################################
# Subroutine: loadPlanProfiles
# -----------------------------------------
# Description:
#   Loads the profiles that are associated 
#   with the merchant plan. This is used
#   when deleting a merchant group.
sub loadPlanProfiles {
  my $self = shift;
  my $planSettingIDs = shift;

  my $billingProfileIDs = [];

  if (@{$planSettingIDs} > 0) {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $sql = q/SELECT id
                  FROM recurring1_profile
                  WHERE plan_settings_id in (/;
      my @placeholders = map {'?'} @{$planSettingIDs};
      my $rows = $dbs->fetchallOrDie('merchant_cust', $sql . join (',', @placeholders) . ')', $planSettingIDs, {})->{'result'};
      if (@{$rows} > 0) {
        foreach my $row (@{$rows}) {
          push (@{$billingProfileIDs}, $row->{'id'});
        }
      }
    };

    if ($@) {
      $self->_log({
        'error'    => $@,
        'function' => 'loadPlanProfiles'
      });
    }
  }

  return $billingProfileIDs;
}

##########################################
# Subroutine: isPlanSettingsUsedByProfile
# ----------------------------------------
# Description:
#   Inputs a plan settings ID and 
#   checks to see if any profiles
#   are using those settings.
#   Helps keep plan settings table
#   clean.
sub isPlanSettingsUsedByProfile {
  my $self = shift;
  my $settingID = shift;

  my $exists = 0;

  eval {
    # check in both profile and plan table
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM recurring1_profile
        WHERE plan_settings_id = ?/, [$settingID], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'isPlanSettingsUsedByProfile'
    });
  }
  
  return $exists;
}

sub _generateUniqueProfileID {
  my $self = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};

  my $uniqueID = new PlugNPay::Util::RandomString()->randomAlphaNumeric(24);
  if ($self->doesUniqueProfileIDExist($uniqueID, $merchantCustomerLinkID)) {
    return $self->_generateUniqueProfileID($merchantCustomerLinkID);
  }

  return $uniqueID;
}

sub doesUniqueProfileIDExist {
  my $self = shift;
  my $uniqueID = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM recurring1_profile
        WHERE identifier = ?
       AND merchant_customer_link_id = ?/, [$uniqueID, $merchantCustomerLinkID], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'doesUniqueProfileIDExist'
    });
  }

  return $exists;
}

#############################################
# Subroutine: loadByBillingProfileIdentifier
# -------------------------------------------
# Description:
#   Given an identifier and link
#   id, loads the profile data
sub loadByBillingProfileIdentifier {
  my $self = shift;
  my $profileIdentifier = shift;
  my $merchantCustomerLinkID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               merchant_customer_link_id,
               plan_settings_id, 
               status_id,
               payment_source_id,
               balance,
               loyalty_count,
               creation_date,
               current_cycle_start_date,
               current_cycle_end_date,
               last_successful_bill_date,
               last_attempt_date,
               description,
               partial_day_credit,
               charge_signup_fee,
               allow_renewal,
               attempts
        FROM recurring1_profile
        WHERE identifier = ?
        AND merchant_customer_link_id = ?/, [$profileIdentifier, $merchantCustomerLinkID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setBillingProfileDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadByBillingProfileIdentifier'
    });
  }
}

######################################
# Subroutine: success
# ------------------------------------
# Description:
#   Call when a profile's transaction
#   was successful. The profile will
#   need to be loaded before invoking.
#   Only input required is the amount
#   if install billing is applicable.
sub success {
  my $self = shift;
  my $amount = shift;

  # status object to return
  my $status = new PlugNPay::Util::Status(1);

  my $planSettings = new PlugNPay::Membership::Plan::Settings();
  $planSettings->loadPlanSettings($self->{'planSettingsID'});

  my $billCycle = new PlugNPay::Membership::Plan::BillCycle();
  $billCycle->loadBillCycle($planSettings->getBillCycleID());

  # new start date of the cycle is one day after the current end date.
  my $startDate = new PlugNPay::Sys::Time('iso', $self->{'currentCycleEndDate'});
  $startDate->addDays(1);

  # new end date will be next bill cycle
  my $endDate = new PlugNPay::Sys::Time('yyyymmdd', $self->_getNextEndDate());

  # partial day credit
  my $updatePartialDayCredit = ($self->{'partialDayCredit'} + $billCycle->getPartialDayCredit());
  if ($updatePartialDayCredit >= 1) {
    # if partial day credit overflowed, add extra day
    $endDate->addDays(1);
    $updatePartialDayCredit -= 1;
  }

  # dates in iso format
  my $updateCycleStartDate = $startDate->inFormat('iso');
  my $updateCycleEndDate = $endDate->inFormat('iso');

  # update loyalty count for profile
  my $updateLoyaltyCount = ($self->{'loyaltyCount'} + 1);

  # update data, reset attempts to 0
  my $updateData = {
    'attempts'               => 0,
    'profileLoyaltyCount'    => $updateLoyaltyCount,
    'currentCycleEndDate'    => $updateCycleEndDate,
    'currentCycleStartDate'  => $updateCycleStartDate,
    'partialDayCredit'       => $updatePartialDayCredit,
    'lastAttempted'          => new PlugNPay::Sys::Time()->nowInFormat('iso'),
    'lastSuccessfulBillDate' => new PlugNPay::Sys::Time()->nowInFormat('iso')
  };

  if ($planSettings->getInstallBilling()) {
    $updateData->{'customerBalance'} = ($self->{'balance'} - $amount);   
  }

  # if this is true, their first payment included it, so now it's false.
  if ($self->{'chargeSignUpFee'}) {  
    $updateData->{'chargeSignUpFee'} = 0;
  }

  # update profile for success
  my $updateStatus = $self->recurringUpdate($updateData);
  if (!$updateStatus) {
    $status->setFalse();
    $status->setError($updateStatus->getError());
  }

  return $status;
}

######################################
# Subroutine: failure
# ------------------------------------
# Description:
#   Call when a profile's transaction
#   was a failure. The profile will
#   need to be loaded before invoking.
#   This requires no input.
sub failure {
  my $self = shift;
  my $status = new PlugNPay::Util::Status(1);

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
  $merchantCustomer->loadMerchantCustomer($self->{'merchantCustomerLinkID'});

  my $gatewayAccount = new PlugNPay::Merchant($merchantCustomer->getMerchantID())->getMerchantUsername();

  my $currentAttempts = ($self->{'attempts'} + 1); # current attempts
  # load service to get recurring lookahead (attempts) setting
  my $service = new PlugNPay::GatewayAccount::Services($gatewayAccount);

  my $updateData = {};
  if ( ($currentAttempts >= $service->getLookAhead())
  || (new PlugNPay::Sys::Time('iso', $self->{'currentCycleEndDate'})->inFormat('yyyymmdd') <= new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd')) ) {
    # update status of profile
    my $profileStatus = new PlugNPay::Membership::Profile::Status();
    $profileStatus->loadStatusID('EXPIRED');
    $updateData->{'statusID'} = $profileStatus->getStatusID();
  }

  # increment attempts, update last attempted
  $updateData->{'attempts'} = $currentAttempts;
  $updateData->{'lastAttempted'} = new PlugNPay::Sys::Time()->nowInFormat('iso');

  # update profile for failure
  my $updateStatus = $self->recurringUpdate($updateData);
  if (!$updateStatus) {
    $status->setFalse();
    $status->setError($updateStatus->getError());
  }

  return $status;
}

######################################
# Subroutine: getNextEndDate
# ------------------------------------
# Description:
#   Programatically calculates the
#   next end date for the profile
#   based on the bill cycle. Returns
#   date in YYYYMMDD format.
######################################
sub _getNextEndDate {
  my $self = shift;
  my $endDate = new PlugNPay::Sys::Time('iso', $self->{'currentCycleEndDate'});

  my $planSettings = new PlugNPay::Membership::Plan::Settings();
  $planSettings->loadPlanSettings($self->{'planSettingsID'});

  my $billCycle = new PlugNPay::Membership::Plan::BillCycle();
  $billCycle->loadBillCycle($planSettings->getBillCycleID());

  my $date = $endDate->inFormat('yyyymmdd');

  my $newEndDate; # future date without lookahead
  if (uc $billCycle->getCycleUnit() =~ /MONTH/) {
    (my $currentYear = $date) =~ s/(\d{4})\d{2}\d{2}/$1/;
    (my $currentMonth = $date) =~ s/\d{4}(\d{2})\d{2}/$1/;
    (my $currentDayOfMonth = $date) =~ s/\d{4}\d{2}(\d{2})/$1/;

    my $addedMonths = ( $billCycle->getCycleDuration() + $currentMonth );

    my $nextDate = $self->_getNextMonth($addedMonths, $currentYear);
    my $nextMonth = $nextDate->{'month'};
    my $nextYear = $nextDate->{'year'};

    my $timeObj = new PlugNPay::Sys::Time();
    my $lastDayOfMonth = $timeObj->getLastOfMonth($nextMonth, $nextYear);
    if ($currentDayOfMonth <= $lastDayOfMonth) {
      my $tempDate = new PlugNPay::Sys::Time('yyyymmdd', $nextYear . sprintf('%02d', $nextMonth) . sprintf('%02d', $currentDayOfMonth));
      $newEndDate = $tempDate->inFormat('yyyymmdd');
    } else {
      my $differenceInDays = ($currentDayOfMonth - $lastDayOfMonth);
      my $tempDate = new PlugNPay::Sys::Time('yyyymmdd', $nextYear . sprintf('%02d', $nextMonth) . sprintf('%02d', $lastDayOfMonth));
      $tempDate->addDays($differenceInDays);
      $newEndDate = $tempDate->inFormat('yyyymmdd');
    }
  } else {
    my $daysCycle = $billCycle->getCycleDuration();
    if (($billCycle->getPartialDayCredit() + $self->{'partialDayCredit'}) >= 1) {
      $endDate->addDays($daysCycle + 1);
    } else {
      $endDate->addDays($daysCycle);
    }

    $newEndDate = $endDate->inFormat('yyyymmdd');
  }

  return $newEndDate;
}

#################################
# Subroutine: _getNextMonth
# -------------------------------
# Description:
#   Recursive function to find
#   the next valid month.
sub _getNextMonth {
  my $self = shift;
  my $months = shift;
  my $years = shift;

  if ($months <= 12) {
    return { 'month' => $months, 'year' => $years };
  } else {
    return $self->_getNextMonth(($months - 12), $years + 1);
  }
}

################################################
# Subroutine: recurringUpdate
# ----------------------------------------------
# Description:
#   This subroutine is used when processing
#   recurring transaction results. It will
#   update profile data that the user does not
#   have control over.
sub recurringUpdate {
  my $self = shift;
  my $updateData = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $lastAttempted          = $updateData->{'lastAttempted'}          || $self->{'lastAttemptDate'};
  my $partialDayCredit       = $updateData->{'partialDayCredit'}       || $self->{'partialDayCredit'};
  my $profileLoyaltyCount    = $updateData->{'profileLoyaltyCount'}    || $self->{'loyaltyCount'};
  my $lastSuccessfulBillDate = $updateData->{'lastSuccessfulBillDate'} || $self->{'lastSuccessfulBillDate'};
  my $currentCycleStartDate  = $updateData->{'currentCycleStartDate'}  || $self->{'currentCycleStartDate'};
  my $currentCycleEndDate    = $updateData->{'currentCycleEndDate'}    || $self->{'currentCycleEndDate'};
  my $customerBalance        = $updateData->{'customerBalance'}        || $self->{'balance'};
  my $statusID               = $updateData->{'statusID'}               || $self->{'statusID'};

  my $attempts               = (defined $updateData->{'attempts'}        ? $updateData->{'attempts'}        : $self->{'attempts'});
  my $chargeSignUpFee        = (defined $updateData->{'chargeSignUpFee'} ? $updateData->{'chargeSignUpFee'} : $self->{'chargeSignUpFee'});

  eval {
    my $params = [
      $partialDayCredit,
      $customerBalance,
      $chargeSignUpFee,
      $lastAttempted,
      $lastSuccessfulBillDate,
      $profileLoyaltyCount,
      $currentCycleStartDate,
      $currentCycleEndDate,
      $statusID,
      $attempts,
      $self->{'billingProfileID'}
    ];

    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust', 
      q/UPDATE recurring1_profile
        SET partial_day_credit = ?,
            balance = ?,
            charge_signup_fee = ?,
            last_attempt_date = ?,
            last_successful_bill_date = ?,
            loyalty_count = ?,
            current_cycle_start_date = ?,
            current_cycle_end_date = ?,
            status_id = ?,
            attempts = ?
        WHERE id = ?/, $params);

    # remove the pending future payment in the table and reschedule.
    # since the balance updated
    my $futurePayment = new PlugNPay::Merchant::Customer::FuturePayment();
    if (!$futurePayment->removePendingRecurring($self->{'billingProfileID'})) {
      push (@errorMsg, 'Unable to removed scheduled payment date.');
    } else {
      my $scheduleStatus = $futurePayment->scheduleRecurringPayment($self->{'billingProfileID'});
      if (!$scheduleStatus) {
        push (@errorMsg, $scheduleStatus->getError());
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'      => $@,
        'function'   => 'recurringUpdate',
        'message'    => 'Billing profile was not updated.',
        'updateData' => $updateData
      });

      push (@errorMsg, 'Error while attempting to update profile membership information.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_profile' });
  $logger->log($logInfo);
}

1;
