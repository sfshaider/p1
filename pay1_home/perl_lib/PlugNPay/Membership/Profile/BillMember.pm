package PlugNPay::Membership::Profile::BillMember;

use strict;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::Membership::Profile;
use PlugNPay::Membership::Plan::Type;
use PlugNPay::Membership::Plan::Currency;
use PlugNPay::Membership::Plan::Settings;
use PlugNPay::Membership::Profile::Status;
use PlugNPay::Merchant::Customer::BillMember;
use PlugNPay::Merchant::Customer::PaymentSource::Expose;

####################################################
# Module: Membership::Profile::BillMember
# --------------------------------------------------
# Description:
#   Module wraps Merchant::Customer::BillMember
#   for billing customer's billing profiles.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

###################################################
# Subroutine: billMemberProfile
# -------------------------------------------------
# Description:
#   Processes a transaction for a billing profile.
#   If the billing profile's plan settings is an 
#   install billing plan, the amount is subtracted
#   from the profile balance.
sub billMemberProfile {
  my $self = shift;
  my $merchantCustomerLinkID = shift;
  my $billingProfileIdentifier = shift;
  my $data = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $transactionData = {};
  my $dbs = new PlugNPay::DBConnection();

  my $profile = new PlugNPay::Membership::Profile();
  $profile->loadByBillingProfileIdentifier($billingProfileIdentifier, $merchantCustomerLinkID);
  if (!$profile->getBillingProfileID()) {
    $status->setFalse();
    $status->setError('Billing profile identifier invalid.');
    return { 'status' => $status }; # return because this needs to be valid.
  }

  eval {
    $dbs->begin('merchant_cust');

    # check the status of the profile
    my $profileStatus = new PlugNPay::Membership::Profile::Status();
    $profileStatus->loadStatus($profile->getStatusID());

    if ($profileStatus->getStatus() !~ /active/i) {
      push (@errorMsg, 'Billing profile is not active.');
    } elsif (!$profile->getPaymentSourceID()) {
      push (@errorMsg, 'Unable to bill profile without payment source.');
    }

    # validate amount
    my $amount = $data->{'amount'};
    if ($amount !~ /^\d*\.?\d+$/) {
      push (@errorMsg, 'Invalid amount.');
    }

    my $tax = $data->{'tax'} || 0;
    if ($tax !~ /^\d*\.?\d+$/) {
      push (@errorMsg, 'Invalid tax amount.');
    }

    my $operation = $data->{'operation'};
    if ($operation ne '') {
      if ($operation !~ /^(auth|credit)$/i) {
        push (@errorMsg, 'Invalid payment operation [ ' . $operation . ' ].');
      }
    }

    if (@errorMsg == 0) {
      my $exposePaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
      $exposePaymentSource->loadExposedPaymentSource($profile->getPaymentSourceID());

      my $planSettings = new PlugNPay::Membership::Plan::Settings();
      $planSettings->loadPlanSettings($profile->getPlanSettingsID());
  
      my $plan = new PlugNPay::Membership::Plan();
      $plan->loadPaymentPlan($planSettings->getPlanID());

      my $planType = new PlugNPay::Membership::Plan::Type();
      $planType->loadPlanType($plan->getPlanTransactionTypeID());
      my $transactionType = $planType->getType();

      my $currencyObj = new PlugNPay::Membership::Plan::Currency();
      $currencyObj->loadCurrency($planSettings->getCurrencyID());

      # if this is a sign up fee payment, then it doesn't affect the balance of the profile.
      if (!$data->{'isSignUpFee'}) {
        if ($profile->getChargeSignUpFee()) {
          push (@errorMsg, 'Unable to bill profile until sign up fee is paid.');
        } else {
          my $updateBalance = ($transactionType =~ /auth/i && $operation =~ /auth/i) || ($transactionType =~ /credit/i && $operation =~ /credit/i);

          # update the customer profile now, so if the transaction fails, roll back
          # or commit if successful.
          if ($planSettings->getInstallBilling()) {
            if ($amount > $profile->getBalance() && $updateBalance) {
              push (@errorMsg, 'Amount cannot be greater than remaining balance on profile.');
            } else {
              if (!$operation) {
                $operation = $transactionType;
              }

              if ($updateBalance) {
                my $balanceUpdateData = {};
                $balanceUpdateData->{'customerBalance'} = ($profile->getBalance() - $amount);

                my $updateProfileStatus = $profile->recurringUpdate($balanceUpdateData);
                if (!$updateProfileStatus) {
                  push (@errorMsg, $updateProfileStatus->getError());
                } 
              }
            }
          } else {
            push (@errorMsg, 'Unable to bill member without balance on profile.');
          }
        }
      } else {
        if ($profile->getChargeSignUpFee() == 0) {
          push (@errorMsg, 'Sign up fee has already been paid.');
        } else {
          $operation = 'auth'; # all sign up fees are authorizations
          my $updateProfileStatus = $profile->recurringUpdate({
            'chargeSignUpFee' => 0
          });

          if (!$updateProfileStatus) {
            push (@errorMsg, $updateProfileStatus->getError());
          } 
        }
      }

      if (@errorMsg == 0) {
        my $biller = new PlugNPay::Merchant::Customer::BillMember();
        my $billStatus = $biller->billCustomer($profile->getMerchantCustomerLinkID(),
                                               $exposePaymentSource->getIdentifier(), {
          'amount'              => $amount,
          'tax'                 => $tax,
          'currency'            => $currencyObj->getCurrencyCode(),
          'transactionType'     => $operation,
          'description'         => $data->{'description'} || 'Bill member: ' . $billingProfileIdentifier,
          'billingAccount'      => $data->{'billingAccount'}
        });

        if (!$billStatus->{'status'}) {
          push (@errorMsg, $billStatus->{'status'}->getError());
        } else {
          $transactionData = $billStatus->{'transactionDetails'};
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_profile_billmember' });
      $logger->log({
        'function'         => 'billMemberProfile',
        'billingProfileID' => $billingProfileIdentifier,
        'error'            => $@
      });

      push (@errorMsg, 'Error while attempting to bill member profile.');
    }

    $status->setFalse();
    $status->setError(join(' ' , @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return { 'status' => $status, 'transactionDetails' => $transactionData };
}

1;
