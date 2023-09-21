package PlugNPay::Membership::Plan;

use strict;
use PlugNPay::Merchant;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Merchant::Proxy;
use PlugNPay::Logging::DataLog;
use PlugNPay::Membership::Group;
use PlugNPay::Util::RandomString;
use PlugNPay::Membership::Profile;
use PlugNPay::Membership::Plan::Type;
use PlugNPay::Membership::Plan::Currency;
use PlugNPay::Membership::Plan::Settings;
use PlugNPay::Membership::Plan::BillCycle;
use PlugNPay::Merchant::Customer::FuturePayment;

##################################################
# Module: Plan
# ------------------------------------------------
# Description:
#   Payment plans contain information of what is 
#   offered to customers from merchants. 
#   Subroutines in this module also input plan 
#   settings data, since the plan settings module
#   was written to programmitically find different
#   variations of a plan.

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $merchant = shift;
  if ($merchant) {
    if (ref($merchant) =~ /^PlugNPay::Merchant::Proxy/) {
      $self->{'merchantDB'} = $merchant;
    } else {
      $self->setMerchantID($merchant);
      $self->{'merchantDB'} = new PlugNPay::Merchant::Proxy($merchant);
    }
  }

  return $self;
}

sub setMerchantID {
  my $self = shift;
  my $merchant = shift;

  if ($merchant !~ /^[0-9]+$/) {
    $merchant = new PlugNPay::Merchant($merchant)->getMerchantID();
  }

  $self->{'merchantID'} = $merchant;
}

sub getMerchantID {
  my $self = shift;
  return $self->{'merchantID'};
}

sub setPlanID {
  my $self = shift;
  my $planID = shift;
  $self->{'planID'} = $planID;
}

sub getPlanID {
  my $self = shift;
  return $self->{'planID'};
}

sub setMerchantPlanID {
  my $self = shift;
  my $merchantPlanID = lc shift;
  $merchantPlanID =~ s/\s+/_/g;
  $self->{'merchantPlanID'} = $merchantPlanID;
}

sub getMerchantPlanID {
  my $self = shift;
  return $self->{'merchantPlanID'};
}

sub setPlanSettingsID {
  my $self = shift;
  my $settingsID = shift;
  $self->{'planSettingsID'} = $settingsID;
}

sub getPlanSettingsID {
  my $self = shift;
  return $self->{'planSettingsID'};
}

sub setPlanTransactionTypeID {
  my $self = shift;
  my $typeID = shift;
  $self->{'transactionTypeID'} = $typeID;
}

sub getPlanTransactionTypeID {
  my $self = shift;
  return $self->{'transactionTypeID'};
}

################################################
# Subroutine: loadPaymentPlans
# ----------------------------------------------
# Description:
#   Loads payment plans for a merchant.
sub loadPaymentPlans {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $plans = [];

  my @values = ();
  my $sql = q/SELECT id,
                     merchant_id,
                     merchant_plan_id,
                     plan_settings_id,
                     transaction_type_id
              FROM recurring1_plan
              WHERE merchant_id = ?
              ORDER BY id ASC/;

  push (@values, $merchantDB);

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
        my $plan = new PlugNPay::Membership::Plan($merchantDB);
        $plan->_setPlanDataFromRow($row);
        push (@{$plans}, $plan);
      } 
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadPaymentPlans'
    });
  }

  return $plans;
}

sub loadPaymentPlan {
  my $self = shift;
  my $planID = shift;
  
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               merchant_id,
               merchant_plan_id,
               plan_settings_id,
               transaction_type_id
        FROM recurring1_plan
        WHERE id = ?/, [$planID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setPlanDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadPaymentPlan'
    });
  }
}

sub _setPlanDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'planID'}                = $row->{'id'};
  $self->{'merchantID'}            = $row->{'merchant_id'};
  $self->{'merchantPlanID'}        = $row->{'merchant_plan_id'};
  $self->{'planSettingsID'}        = $row->{'plan_settings_id'};
  $self->{'transactionTypeID'}     = $row->{'transaction_type_id'};
}

#######################################
# Subroutine: savePaymentPlan
# -------------------------------------
# Description:
#   Saves a payment plan. Plan settings
#   are provided to this subroutine to 
#   be saved.
sub savePaymentPlan {
  my $self = shift;
  my $data = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $merchantDB = $self->{'merchantDB'};
  if (!$merchantDB->isMaster()) {
    $status->setFalse();
    $status->setError('Access denied.');
    return $status;
  }

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');

    my $merchantPlanID = lc $data->{'merchantPlanID'} || $self->{'merchantPlanID'};
    if (!$merchantPlanID) {
      $merchantPlanID = $self->_assignUniquePlanID();
    } else {
      $merchantPlanID =~ s/\s+/_/g;
      $merchantPlanID =~ s/[^a-zA-Z0-9_]//g;
      if (!$merchantPlanID) {
        push (@errorMsg, 'Unable to save payment plan. Invalid plan ID.');
      } elsif ($self->merchantPlanIDExists($merchantPlanID, $merchantDB)) {
        push (@errorMsg, 'Plan ID exists.');
      }
    }

    if (@errorMsg == 0) {
      ########################
      # Type of payment plan #
      ########################

      my $transTypeID;
      my $transType = new PlugNPay::Membership::Plan::Type();
      if ($data->{'transactionType'} =~ /^\d+$/) {
        $transType->loadPlanType($data->{'transactionType'});
      } else {
        $data->{'transactionType'} =~ s/[^a-zA-Z]//g;
        $transType->loadPlanTypeID($data->{'transactionType'});
      }

      if (!$transType->getTypeID()) {
        push (@errorMsg, 'Invalid plan transaction type.');
      } else {
        $transTypeID = $transType->getTypeID();
      }

      if (@errorMsg == 0) {
        #####################
        # Save payment plan #
        #####################
        my $insertedPlanID;
        my $params = [
          $merchantDB, 
          $merchantPlanID,
          $transTypeID
        ];

        my $sth = $dbs->executeOrDie('merchant_cust',
          q/INSERT INTO recurring1_plan 
            ( merchant_id, 
              merchant_plan_id, 
              transaction_type_id )
            VALUES (?,?,?)/, $params)->{'sth'};
        $insertedPlanID = $sth->{'mysql_insertid'};

        ########################
        # Save groups for plan #
        ########################
        if (exists $data->{'groups'}) {
          if (ref ($data->{'groups'}) eq 'ARRAY') {
            if (@{$data->{'groups'}} > 0) {
              my $group = new PlugNPay::Membership::Group($merchantDB);
              my $saveGroupStatus = $group->savePlanGroups($insertedPlanID, $data->{'groups'});
              if (!$saveGroupStatus) {
                push (@errorMsg, $saveGroupStatus->getError());
              }
            } 
          } else {
            push (@errorMsg, 'Invalid format of groups data.');
          }
        }

        if (@errorMsg == 0) {
          ####################
          # Load currency ID #
          ####################

          my $currencyID;
          my $currency = new PlugNPay::Membership::Plan::Currency();
          if ($data->{'currency'} =~ /^\d+$/) {
            $currency->loadCurrency($data->{'currency'});
          } else {
            $data->{'currency'} =~ s/[^a-zA-Z]//g;
            $currency->loadCurrencyID($data->{'currency'});
          }

          if (!$currency->getCurrencyID()) {
            push (@errorMsg, 'Invalid currency.');
          } else {
            $currencyID = $currency->getCurrencyID();
          }

          ######################
          # Load bill cycle ID #
          ######################
   
          my $billCycleObj = new PlugNPay::Membership::Plan::BillCycle();
          if ($data->{'billCycle'} =~ /^\d+$/) {
            $billCycleObj->loadBillCycle($data->{'billCycle'});
          } else {
            $billCycleObj->loadBillCycleID($data->{'billCycle'});
          }

          if (!$billCycleObj->getBillCycleID()) {
            push (@errorMsg, 'Invalid bill cycle.');
          }
    
          ######################
          # Save plan settings #
          ######################

          my $settings = new PlugNPay::Membership::Plan::Settings($merchantDB);
          my ($signupFee, $recurringFee, $loyaltyFee, $loyaltyCount, $balance);
          my ($initialDayDelay, $initialMonthDelay);
   
          if (!$settings->_validateMonetaryValue($data->{'signupFee'})) {
            push (@errorMsg, 'Sign up fee is not valid.');
          } else {
            $signupFee = $data->{'signupFee'};
          }
    
          # if we still do not have any errors at this point..
          if (@errorMsg == 0) {
            if ($billCycleObj->getCycleDuration() == 0) {
              $recurringFee = 0;
              $loyaltyFee = 0;
              $loyaltyCount = 0;
              $balance = undef;
              $initialDayDelay = 0;
              $initialMonthDelay = 0;
            } else {
              if (!$settings->_validateMonetaryValue($data->{'recurringFee'})) {
                push (@errorMsg, 'Recurring fee is not valid.');
              } else {
                $recurringFee = $data->{'recurringFee'};
              }
   
              if (!$settings->_validateMonetaryValue($data->{'loyaltyFee'})) {
                push (@errorMsg, 'Loyalty fee is not valid.');
              } else {
                $loyaltyFee = $data->{'loyaltyFee'};
              }
    
              if ($data->{'balance'}) {
                if (!$settings->_validateMonetaryValue($data->{'balance'})) {
                  push (@errorMsg, 'Balance is not valid.');
                } else {
                  $balance = $data->{'balance'};
                }
              }
            }
    
            $loyaltyCount = $data->{'loyaltyCount'} || 0;
            if ($loyaltyCount !~ /^\d+$/) {
              push (@errorMsg, 'Loyalty count is not valid.');
            }
    
            $initialDayDelay = $data->{'initialDayDelay'} || 3;
            if ($initialDayDelay !~ /^\d+$/) {
              push (@errorMsg, 'Invalid day delay value.');
            }
    
            $initialMonthDelay = $data->{'initialMonthDelay'} || 0;
            if ($initialMonthDelay !~ /^\d+$/) {
              push (@errorMsg, 'Invalid month delay value.');
            }

            if (@errorMsg == 0) {
              ######################
              # Save plan settings #
              ######################
    
              $settings->setPlanID($insertedPlanID);
              $settings->setCurrencyID($currencyID);
              $settings->setBillCycleID($billCycleObj->getBillCycleID());
              $settings->setSignUpFee($signupFee);
              $settings->setRecurringFee($recurringFee);
              $settings->setLoyaltyFee($loyaltyFee);
              $settings->setLoyaltyCount($loyaltyCount);
              $settings->setInitialMonthDelay($initialMonthDelay);
              $settings->setInitialDayDelay($initialDayDelay);
              $settings->setBalance($balance);
              my $saveStatus = $settings->savePlanSettings();
              if (!$saveStatus) {
                push (@errorMsg, $saveStatus->getError());
              } else {
                ##############################################
                # Update recurring plan with latest settings #
                ##############################################
                $dbs->executeOrDie('merchant_cust',
                  q/UPDATE recurring1_plan
                    SET plan_settings_id = ?
                    WHERE id = ?/, [$settings->getPlanSettingsID(), $insertedPlanID]); 
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
        'error'      => $@,
        'function'   => 'savePaymentPlan',
        'merchantDB' => $self->{'merchantDB'}
      });

      push (@errorMsg, 'Error while attempting to save payment plan.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

##################################
# Subroutine: updatePaymentPlan
# --------------------------------
# Description:
#   Updates payment plan info for
#   a merchant.
sub updatePaymentPlan {
  my $self = shift;
  my $updateData = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $merchantDB = $self->{'merchantDB'};
  if (!$merchantDB->isMaster()) {
    $status->setFalse();
    $status->setError('Access denied.');
    return $status;
  }

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');

    ###########################
    # Update merchant plan ID #
    ###########################
   
    my $updateMerchantPlanID = lc $updateData->{'merchantPlanID'};
    $updateMerchantPlanID =~ s/\s+/_/g;
    $updateMerchantPlanID =~ s/[^a-zA-Z0-9_]//g;

    if ($self->{'merchantPlanID'} ne $updateMerchantPlanID) {
      if (!$updateMerchantPlanID) {
        push (@errorMsg, 'Invalid plan ID.');
      } elsif ($self->merchantPlanIDExists($updateMerchantPlanID)) {
        push (@errorMsg, 'Plan ID already exists.');
      }
    }

    if (@errorMsg == 0) {
      ################################
      # Update plan transaction type #
      ################################

      my $updateTransactionTypeID;
      if (exists $updateData->{'transactionType'}) {
        my $transType = new PlugNPay::Membership::Plan::Type();
        if ($updateData->{'transactionType'} =~ /^\d+$/) {
          $transType->loadPlanType($updateData->{'transactionType'});
        } else {
          $updateData->{'transactionType'} =~ s/[^a-zA-Z]//g;
          $transType->loadPlanTypeID($updateData->{'transactionType'});
        }

        if (!$transType->getTypeID()) {
          push (@errorMsg, 'Invalid transaction type ID.');
        } else {
          $updateTransactionTypeID = $transType->getTypeID();
        }
      } else {
        $updateTransactionTypeID = $self->{'transactionTypeID'};
      }

      if (@errorMsg == 0) {
        ##################################
        # Update plan table with new IDs #
        ##################################
        my $params = [
          $updateMerchantPlanID,
          $updateTransactionTypeID,
          $self->{'planID'}
        ];

        $dbs->executeOrDie('merchant_cust',
          q/UPDATE recurring1_plan
            SET merchant_plan_id = ?,
                transaction_type_id = ?
            WHERE id = ?/, $params);

        ##########################
        # Update groups for plan #
        ##########################

        if (exists $updateData->{'groups'}) {
          if (ref ($updateData->{'groups'}) eq 'ARRAY') {
            my $group = new PlugNPay::Membership::Group($merchantDB);
            my $updateGroupStatus = $group->updatePlanGroups($self->{'planID'},
                                                             $updateData->{'groups'});
            if (!$updateGroupStatus) {
              push (@errorMsg, $updateGroupStatus->getError());
            }
          } else {
            push (@errorMsg, 'Invalid format of groups data.');
          }
        }

        if (@errorMsg == 0) {
          my $currentSettings = new PlugNPay::Membership::Plan::Settings($merchantDB);
          $currentSettings->loadPlanSettings($self->{'planSettingsID'});
          my $currentDigest = $currentSettings->getDigest();

          my $updateSettings = new PlugNPay::Membership::Plan::Settings($merchantDB);
          $updateSettings->setPlanID($self->{'planID'});

          ######################
          # Update currency ID #
          ######################
 
          my $updateCurrencyID;
          if (exists $updateData->{'currency'}) {
            my $currency = new PlugNPay::Membership::Plan::Currency();
            if ($updateData->{'currency'} =~ /^\d+$/) {
              $currency->loadCurrency($updateData->{'currency'});
            } else {
              $updateData->{'currency'} =~ s/[^a-zA-Z]//g;
              $currency->loadCurrencyID($updateData->{'currency'});
            }

            if (!$currency->getCurrencyID()) {
              push (@errorMsg, 'Invalid currency value.');
            } else {
              $updateCurrencyID = $currency->getCurrencyID();
            }
          } else {
            $updateCurrencyID = $currentSettings->getCurrencyID();
          }
    
          ########################
          # Update plan settings #
          ########################
    
          my ($signupFee, $recurringFee, $loyaltyFee, $loyaltyCount, $balance);
          my ($initialDayDelay, $initialMonthDelay);
    
          if (exists $updateData->{'signupFee'}) {
            if (!$currentSettings->_validateMonetaryValue($updateData->{'signupFee'})) {
              push (@errorMsg, 'Invalid sign up fee value.');
            } else {
              $signupFee = $updateData->{'signupFee'};
            }
          } else {
            $signupFee = $currentSettings->getSignUpFee();
          }
    
          my $updateBillCycleID;
          if (exists $updateData->{'billCycle'}) {
            my $billCycleObj = new PlugNPay::Membership::Plan::BillCycle();
            if ($updateData->{'billCycle'} =~ /^\d+$/) {
              $billCycleObj->loadBillCycle($updateData->{'billCycle'});
            } else {
              $billCycleObj->loadBillCycleID($updateData->{'billCycle'});
            }

            if (!$billCycleObj->getBillCycleID()) {
              push (@errorMsg, 'Invalid bill cycle ID.');
            } else {
              $updateBillCycleID = $billCycleObj->getBillCycleID();
            }
          } else {
            $updateBillCycleID = $currentSettings->getBillCycleID();
          }
    
          if (@errorMsg == 0) {
            my $updateBillCycle = new PlugNPay::Membership::Plan::BillCycle();
            $updateBillCycle->loadBillCycle($updateBillCycleID);
    
            if ($updateBillCycle->getCycleDuration() != 0) {
              if (exists $updateData->{'recurringFee'}) {
                if (!$currentSettings->_validateMonetaryValue($updateData->{'recurringFee'})) {
                  push (@errorMsg, 'Recurring fee is not valid.');
                } else {
                  $recurringFee = $updateData->{'recurringFee'};
                }
              } else {
                $recurringFee = $currentSettings->getRecurringFee();
              }
    
              if (exists $updateData->{'loyaltyFee'}) {
                if (!$currentSettings->_validateMonetaryValue($updateData->{'loyaltyFee'})) {
                  push (@errorMsg, 'Loyalty fee is not valid.');
                } else {
                  $loyaltyFee = $updateData->{'loyaltyFee'};
                }
              } else {
                $loyaltyFee = $currentSettings->getLoyaltyFee();
              }
    
              if (exists $updateData->{'balance'}) {
                if ($updateData->{'balance'}) {
                  if (!$currentSettings->_validateMonetaryValue($updateData->{'balance'})) {
                    push (@errorMsg, 'Balance is not valid.');
                  } else {
                    $balance = $updateData->{'balance'};
                  }
                } else {
                  $balance = undef;
                }
              } else {
                $balance = $currentSettings->getBalance();
              }
    
              if (exists $updateData->{'loyaltyCount'}) {
                if ($updateData->{'loyaltyCount'} !~ /^\d+$/) {
                  push (@errorMsg, 'Loyalty count is not valid.');
                } else {
                  $loyaltyCount = $updateData->{'loyaltyCount'};
                }
              } else {
                $loyaltyCount = $currentSettings->getLoyaltyCount();
              }
            } else {
              $recurringFee = 0;
              $loyaltyFee = 0;
              $loyaltyCount = 0;
              $balance = undef;
            }
    
            if (exists $updateData->{'initialDayDelay'}) {
              if ($updateData->{'initialDayDelay'} !~ /^\d+$/) {
                push (@errorMsg, 'Invalid day delay value.');
              } else {
                $initialDayDelay = $updateData->{'initialDayDelay'};
              }
            } else {
              $initialDayDelay = $currentSettings->getInitialDayDelay();
            }
    
            if (exists $updateData->{'initialMonthDelay'}) {
              if ($updateData->{'initialMonthDelay'} !~ /^\d+$/) {
                push (@errorMsg, 'Invalid month delay value.');
              } else {
                $initialMonthDelay = $updateData->{'initialMonthDelay'};
              }
            } else {
              $initialMonthDelay = $currentSettings->getInitialMonthDelay();
            }
    
            if (@errorMsg == 0) {
              $updateSettings->setBillCycleID($updateBillCycleID);
              $updateSettings->setSignUpFee($signupFee);
              $updateSettings->setCurrencyID($updateCurrencyID);
              $updateSettings->setRecurringFee($recurringFee);
              $updateSettings->setInitialMonthDelay($initialMonthDelay);
              $updateSettings->setInitialDayDelay($initialDayDelay);
              $updateSettings->setLoyaltyFee($loyaltyFee);
              $updateSettings->setLoyaltyCount($loyaltyCount);
              $updateSettings->setBalance($balance);
    
              my $updateDigest = $updateSettings->createDigest();
              # if the digests are different, then the settings must have changed
              if ($currentDigest ne $updateDigest) {
                $updateSettings->setDigest($updateDigest);
                my $updateStatus = $updateSettings->savePlanSettings();
                if (!$updateStatus) {
                  push (@errorMsg, $updateStatus->getError());
                } else {
                  $dbs->executeOrDie('merchant_cust',
                    q/UPDATE recurring1_plan
                      SET plan_settings_id = ?
                      WHERE id = ?/, [$updateSettings->getPlanSettingsID(), $self->{'planID'}]);

                  my $profile = new PlugNPay::Membership::Profile();
                  if (!$profile->isPlanSettingsUsedByProfile($self->{'planSettingsID'}) && (!$currentSettings->isActiveSettings())) {
                    $currentSettings->deletePlanSettings($self->{'planSettingsID'});
                  }

                  if ($updateTransactionTypeID != $self->{'transactionTypeID'}) {
                    if ($updateData->{'changePayments'}) {
                      # if the merchant wants to reschedule all the former payments
                      # of transaction type X and make them type Y.
                      my $planSettings = new PlugNPay::Membership::Plan::Settings();
                      my $planSettingIDs = $planSettings->loadSettingsVariationIDs($self->{'planID'});
           
                      my $profile = new PlugNPay::Membership::Profile();
                      my $planProfiles = $profile->loadPlanProfiles($planSettingIDs);
         
                      my $futurePayment = new PlugNPay::Merchant::Customer::FuturePayment();
                      my $updatePaymentStatus = $futurePayment->updatePaymentsPlanChange($planProfiles, $updateTransactionTypeID);
                      if (!$updatePaymentStatus) {
                        push (@errorMsg, $updatePaymentStatus->getError());
                      }
                    }
                  }
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
        'error'      => $@,
        'function'   => 'updatePaymentPlan',
        'merchantDB' => $self->{'merchantDB'}
      });

      push (@errorMsg, 'Error while attempting to update payment plan.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

#########################################
# Subroutine: deletePaymentPlan
# ---------------------------------------
# Description:
#   Deletes a plan for a merchant. If
#   plan settings are used in billing
#   profiles then it cannot be deleted.
sub deletePaymentPlan {
  my $self = shift;
  my $planID = shift || $self->{'planID'};

  my $status = new PlugNPay::Util::Status(1);
  my $dbs = new PlugNPay::DBConnection();
  my @errorMsg;

  if (!$self->{'merchantDB'}->isMaster()) {
    $status->setFalse();
    $status->setError('Access denied.');
    return $status;
  }

  if (!$self->{'planSettingsID'}) {
    $self->loadPaymentPlan($planID);
  }

  my $settings = new PlugNPay::Membership::Plan::Settings();
  my $planSettingIDs = $settings->loadSettingsVariationIDs($planID);
  my $profile = new PlugNPay::Membership::Profile();
  foreach my $settingID (@{$planSettingIDs}) {
    # check if setting variations exist in profile
    if ($profile->isPlanSettingsUsedByProfile($settingID)) {
      push (@errorMsg, 'Plan settings are in use for billing profile.');
      last;
    }
  }

  if (@errorMsg == 0) {
    eval {
      $dbs->begin('merchant_cust');
      $dbs->executeOrDie('merchant_cust',
        q/DELETE FROM recurring1_plan
          WHERE id = ?/, [$planID]);
    };

    if ($@) {
      $dbs->rollback('merchant_cust');
    } else {
      $dbs->commit('merchant_cust');
    }
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'      => $@,
        'planID'     => $planID,
        'function'   => 'deletePaymentPlan',
        'merchantDB' => $self->{'merchantDB'}
      });

      push (@errorMsg, 'Error while attempting to delete payment plan.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

########################################
# Subroutine: merchantPlanIDExists
# --------------------------------------
# Description:
#   Merchant plan ID is a unique value
#   set for a plan by a merchant.
sub merchantPlanIDExists {
  my $self = shift;
  my $merchantPlanID = shift;
  my $merchantDB = shift || $self->{'merchantDB'};
  
  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM recurring1_plan
        WHERE merchant_plan_id = ?
        AND merchant_id = ?/, [$merchantPlanID, $merchantDB], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'merchantPlanIDExists'
    });
  }

  return $exists;
}

sub loadByMerchantPlanID {
  my $self = shift;
  my $merchantPlanID = shift;
  my $merchantDB = shift || $self->{'merchantDB'};
  
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               merchant_id,
               merchant_plan_id,
               plan_settings_id,
               transaction_type_id
        FROM recurring1_plan
        WHERE merchant_plan_id = ?
        AND merchant_id = ?/, [$merchantPlanID, $merchantDB], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setPlanDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadByMerchantPlanID'
    });
  }
}

sub _assignUniquePlanID {
  my $self = shift;
  my $uniqueID = lc 'recurring_' . new PlugNPay::Util::RandomString()->randomAlphaNumeric(8);
  if ($self->merchantPlanIDExists($uniqueID)) {
    $uniqueID = $self->_assignUniquePlanID();
  }

  return $uniqueID;
}

#####################################
# Subroutine: checkSimilarSettings
# -----------------------------------
# Description:
#   Checks the plan table for any 
#   plans that contains a plan 
#   settings ID. Helper function to
#   keep that table clean.
sub checkSimilarSettings {
  my $self = shift;
  my $planSettingsID = shift;

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM recurring1_plan
        WHERE plan_settings_id = ?/, [$planSettingsID], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'checkSimilarSettings'
    });
  }

  return $exists;
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getPlanListSize {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM recurring1_plan
        WHERE merchant_id = ?/, [$merchantDB], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'getPlanListSize'
    });
  }

  return $count;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_plan' });
  $logger->log($logInfo);
}

1;
