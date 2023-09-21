package PlugNPay::Membership::Plan::Settings;

use strict;
use PlugNPay::Merchant;
use PlugNPay::Util::Hash;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::Membership::Plan;

########################################
# Module: Plan::Settings
# --------------------------------------
# Description:
#   The purpose of this module is to 
#   store payment plan settings. It 
#   reduces redundancy in the table by
#   reusing the settings if they exist.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $merchant = shift;
  
  if ($merchant) {
    $self->setMerchantID($merchant);
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

sub setPlanSettingsID {
  my $self = shift;
  my $planSettingID = shift;
  $self->{'planSettingsID'} = $planSettingID;
}

sub getPlanSettingsID {
  my $self = shift;
  return $self->{'planSettingsID'};
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

sub setSignUpFee {
  my $self = shift;
  my $signUpFee = shift || 0;
  $self->{'signupFee'} = sprintf("%.3f", $signUpFee);
}

sub getSignUpFee {
  my $self = shift;
  return $self->{'signupFee'};
}

sub setRecurringFee {
  my $self = shift;
  my $recurringFee = shift || 0;
  $self->{'recurringFee'} = sprintf("%.3f", $recurringFee);
}

sub getRecurringFee {
  my $self = shift;
  return $self->{'recurringFee'};
}

sub setCurrencyID {
  my $self = shift;
  my $currencyID = shift;
  $self->{'currencyID'} = $currencyID;
}

sub getCurrencyID {
  my $self = shift;
  return $self->{'currencyID'};
}

sub setBillCycleID {
  my $self = shift;
  my $billCycleID = shift;
  $self->{'billCycleID'} = $billCycleID;
}

sub getBillCycleID {
  my $self = shift;
  return $self->{'billCycleID'};
}

sub setInitialMonthDelay {
  my $self = shift;
  my $delay = shift;
  $self->{'initialMonthDelay'} = int($delay);
}

sub getInitialMonthDelay {
  my $self = shift;
  return $self->{'initialMonthDelay'};
}

sub setInitialDayDelay {
  my $self = shift;
  my $delay = shift;
  $self->{'initialDayDelay'} = int($delay);
}

sub getInitialDayDelay {
  my $self = shift;
  return $self->{'initialDayDelay'};
}

sub setLoyaltyFee {
  my $self = shift;
  my $loyaltyFee = shift || 0;
  $self->{'loyaltyFee'} = sprintf("%.3f", $loyaltyFee);
}

sub getLoyaltyFee {
  my $self = shift;
  return $self->{'loyaltyFee'};
}

sub setLoyaltyCount {
  my $self = shift;
  my $loyaltyCount = shift || 0;
  $self->{'loyaltyCount'} = int($loyaltyCount);
}

sub getLoyaltyCount {
  my $self = shift;
  return $self->{'loyaltyCount'};
}

sub setBalance {
  my $self = shift;
  my $balance = shift;

  if ($balance) {
    $balance = sprintf("%.3f", $balance);
  }

  $self->{'balance'} = $balance;
}

sub getBalance {
  my $self = shift;
  return $self->{'balance'};
}

##################################
# Subroutine: isActiveSettings
# --------------------------------
# Description:
#   Returns true if payment plan
#   settings are the active for
#   the plan.
sub isActiveSettings {
  my $self = shift;
  my $planSettingsID = shift || $self->{'planSettingsID'};

  if (!$self->{'planID'}) {
    $self->loadPlanSettings($planSettingsID);
  }

  my $plan = new PlugNPay::Membership::Plan();
  $plan->loadPaymentPlan($self->{'planID'});
  return ($plan->getPlanSettingsID() == $planSettingsID);
}

###################################
# Subroutine: setInstallBilling
# ---------------------------------
# Description:
#   If this value is set, the plan
#   is install billing.
sub setInstallBilling {
  my $self = shift;
  my $installBilling = shift;
  $self->{'installBilling'} = $installBilling;
}

sub getInstallBilling {
  my $self = shift;
  return $self->{'installBilling'};
}

sub setDigest {
  my $self = shift;
  my $digest = shift;
  $self->{'digest'} = $digest;
}

sub getDigest {
  my $self = shift;
  return $self->{'digest'};
}

###########################################
# Subroutine: createDigest
# -----------------------------------------
# Description:
#   The digest is created from an array of
#   plan settings. The idea here is to 
#   keep the plan settings table clean with
#   only variations of payment plans that 
#   are currently used.
sub createDigest {
  my $self = shift;
  my $formattedString = $self->_formatDigest();

  my $util = new PlugNPay::Util::Hash();
  $util->add($formattedString);
  my $digest = $util->sha1('0b');
  return $digest;
}

###########################################
# Subroutine: _formatDigest
# -----------------------------------------
# Description:
#   Perl hashes don't guarentee order of 
#   the keys, so to ensure that the input
#   is the same format everytime, an array
#   is used.
sub _formatDigest {
  my $self = shift;
  my @digestArr = (
    $self->{'merchantID'},
    $self->{'planID'},
    $self->{'signupFee'},
    $self->{'recurringFee'},
    $self->{'currencyID'},
    $self->{'billCycleID'},
    $self->{'initialMonthDelay'},
    $self->{'initialDayDelay'},
    $self->{'loyaltyFee'},
    $self->{'loyaltyCount'},
    $self->{'balance'}
  );
  
  return join (',', @digestArr);
}

#########################################
# Subroutine: checkDigestExists
# ---------------------------------------
# Description:
#   Returns 1 or 0 if the digest exists.
sub checkDigestExists {
  my $self = shift;
  my $digest = shift || $self->{'digest'};

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM recurring1_plan_settings
        WHERE digest = ?/, [$digest], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'checkDigestExists' 
    });
  }

  return $exists;
}

#########################################
# Subroutine: loadIDFromDigest
# ---------------------------------------
# Description:
#   Returns the id of the plan settings
#   if the digest exists.
sub loadIDFromDigest {
  my $self = shift;
  my $digest = shift || $self->{'digest'};

  my $planSettingsID;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id
        FROM recurring1_plan_settings
        WHERE digest = ?/, [$digest], {})->{'result'};
    if (@{$rows} > 0) {
      $planSettingsID = $rows->[0]{'id'};
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadIDFromDigest'
    });
  }
  
  return $planSettingsID;
}

###################################
# Subroutine: savePlanSettings
# ---------------------------------
# Description:
#   Saves settings for a payment
#   plan if the variation doesn't
#   already exist.
sub savePlanSettings {
  my $self = shift;
 
  my $status = new PlugNPay::Util::Status(1);
  my $digest;
  eval {
    if (!$self->{'digest'}) {
      $digest = $self->createDigest();
    } else {
      $digest = $self->{'digest'};
    }

    my $planSettingsID;
    if ($self->checkDigestExists($digest)) {
      $planSettingsID = $self->loadIDFromDigest($digest);
    } else {
      my $params = [
        $self->{'merchantID'}, 
        $self->{'planID'}, 
        $self->{'signupFee'}, 
        $self->{'recurringFee'},
        $self->{'currencyID'},
        $self->{'billCycleID'},
        $self->{'initialMonthDelay'},
        $self->{'initialDayDelay'},
        $self->{'loyaltyFee'},
        $self->{'loyaltyCount'},
        $self->{'balance'},
        $digest
      ];

      my $dbs = new PlugNPay::DBConnection();
      my $sth = $dbs->executeOrDie('merchant_cust',
        q/INSERT INTO recurring1_plan_settings 
          ( merchant_id,
            plan_id,
            signup_fee,
            recurring_fee,
            currency_id,
            bill_cycle_id,
            initial_month_delay,
            initial_day_delay,
            loyalty_fee,
            loyalty_count,
            balance,
            digest )
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?)/, $params)->{'sth'};
      $planSettingsID = $sth->{'mysql_insertid'};
    }

    $self->{'planSettingsID'} = $planSettingsID;
  };

  if ($@) {
    $self->_log({
      'function' => 'savePlanSettings',
      'error'    => $@
    });

    $status->setFalse();
    $status->setError('Error while attempting to save payment plan settings.');
  }

  return $status;
}

########################################
# Subroutine: loadPlanSettings
# --------------------------------------
# Description:
#   Loads a plan's settings given the
#   settings ID from the plan object.
sub loadPlanSettings {
  my $self = shift;
  my $planSettingsID = shift || $self->{'planSettingsID'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               merchant_id,
               plan_id,
               signup_fee,
               recurring_fee,
               currency_id,
               bill_cycle_id,
               initial_month_delay,
               initial_day_delay,
               loyalty_fee,
               loyalty_count,
               balance,
               digest
        FROM recurring1_plan_settings
        WHERE id = ?/, [$planSettingsID], {})->{'result'};
    if (@{$rows} > 0) {
      my $row = $rows->[0];
      $self->{'planSettingsID'} = $row->{'id'};
      $self->{'merchantID'}     = $row->{'merchant_id'};
      $self->{'planID'}         = $row->{'plan_id'};
      $self->{'billCycleID'}    = $row->{'bill_cycle_id'};
      $self->{'currencyID'}     = $row->{'currency_id'};
      $self->{'digest'}         = $row->{'digest'};

      # format these 
      $self->setSignUpFee($row->{'signup_fee'});
      $self->setRecurringFee($row->{'recurring_fee'});
      $self->setInitialMonthDelay($row->{'initial_month_delay'});
      $self->setInitialDayDelay($row->{'initial_day_delay'});
      $self->setLoyaltyFee($row->{'loyalty_fee'});
      $self->setLoyaltyCount($row->{'loyalty_count'});
   
      if ($row->{'balance'}) {
        $self->setBalance($row->{'balance'});
        $self->{'installBilling'} = 1;
      } else {
        $self->{'installBilling'} = 0;
      } 
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadPlanSettings'
    });
  }
}

###########################################
# Subroutine: loadSettingsVariationIDs
# -----------------------------------------
# Description:
#   Loads all the variations of settings 
#   for a given plan.
sub loadSettingsVariationIDs {
  my $self = shift;
  my $planID = shift;
  
  my $ids = [];

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id
        FROM recurring1_plan_settings
        WHERE plan_id = ?/, [$planID], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        push (@{$ids}, $row->{'id'});
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadSettingsVariationIDs'
    });
  }

  return $ids;
}

#########################################
# Subroutine: deletePlanSettings
# ---------------------------------------
# Description:
#   Given a payment plan settings id, 
#   deletes the row from the settings 
#   table.
sub deletePlanSettings {
  my $self = shift;
  my $planSettingsID = shift || $self->{'planSettingsID'};
  
  my $status = new PlugNPay::Util::Status(1);

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM recurring1_plan_settings
        WHERE id = ?/, [$planSettingsID]);
  };

  if ($@) {
    $self->_log({
      'error'          => $@,
      'function'       => 'deletePlanSettings',
      'planSettingsID' => $planSettingsID
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete settings.');
  }
 
  return $status;
}

##########################################
# Subroutine: deleteSettingsForPlan
# ----------------------------------------
# Description:
#   Deletes the settings when a payment
#   plan is deleted.
sub deleteSettingsForPlan {
  my $self = shift;
  my $planID = shift;
  
  my $status = new PlugNPay::Util::Status(1);

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM recurring1_plan_settings
      WHERE plan_id = ?/, [$planID]);
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'deleteSettingsForPlan',
      'planID'   => $planID
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete payment plan settings.');
  }
 
  return $status;
}

##########################################
# Subroutine: _validateMonetaryValue
# ----------------------------------------
# Description:
#   Returns true if valid currency value.
sub _validateMonetaryValue {
  my $self = shift;
  my $value = shift;
  return ($value =~ /^\d*\.?\d+$/);
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_plan_settings' });
  $logger->log($logInfo);
}

1;
