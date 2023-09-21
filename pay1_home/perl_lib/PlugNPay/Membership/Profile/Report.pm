package PlugNPay::Membership::Profile::Report;

use strict;
use PlugNPay::Merchant;
use PlugNPay::Sys::Time;
use PlugNPay::Logging::DataLog;
use PlugNPay::Merchant::Customer;
use PlugNPay::Membership::Results;
use PlugNPay::Membership::Profile;
use PlugNPay::Database::QueryBuilder;
use PlugNPay::Membership::Plan::Type;
use PlugNPay::Merchant::Customer::Link;
use PlugNPay::Merchant::Customer::Job::Status;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub loadProfileHistory {
  my $self = shift;
  my $profileIdentifier = shift;
  my $merchantCustomerLinkID = shift;

  my $results = [];
  eval {
    my $profile = new PlugNPay::Membership::Profile();
    $profile->loadByBillingProfileIdentifier($profileIdentifier, $merchantCustomerLinkID);
    if ($profile->getProfileID()) {
      my $jobStatus = new PlugNPay::Merchant::Customer::Job::Status();
      my $completedStatusID = $jobStatus->loadStatusID('COMPLETED');

      my $result = new PlugNPay::Membership::Results();
      $results = $result->loadTransactionResultsForProfile($profile->getBillingProfileID(),
                                                           $completedStatusID);
    }
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_reporting' });
    $logger->log({
      'error'                    => $@,
      'merchantCustomerLinkID'   => $merchantCustomerLinkID,
      'billingProfileIdentifier' => $profileIdentifier
    });
  }

  my $processedResult = {};
  if (!$@ && @{$results} > 0) {
    my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
    $merchantCustomer->loadMerchantCustomer($merchantCustomerLinkID);

    my $customer = new PlugNPay::Merchant::Customer();
    $customer->loadCustomer($merchantCustomer->getCustomerID());

    my $merchant = new PlugNPay::Merchant();
    $merchant->loadMerchantUsername($merchantCustomer->getMerchantID());

    $processedResult->{'merchant'} = $merchant->getMerchantUsername();
    $processedResult->{'customer'} = {
      'username' => $merchantCustomer->getUsername(),
      'email'    => $customer->getEmail(),
      'name'     => $merchantCustomer->getName()
    };

    $processedResult->{'billingProfile'} = $profileIdentifier;

    # amounts
    $processedResult->{'totalAmount'} = 0;
    $processedResult->{'billed'} = 0;
    $processedResult->{'credited'} = 0;
    
    # information on results
    $processedResult->{'results'} = [];
    foreach my $result (@{$results}) {
      my $resultData = {};
      $resultData->{'transactionStatus'} = $result->getTransactionStatus();
      $resultData->{'transactionAmount'} = $result->getTransactionAmount();
      $resultData->{'transactionDate'} = new PlugNPay::Sys::Time('iso', $result->getTransactionDateTime())->inFormat('db_gm');
      if ($result->getTransactionStatus() =~ /success/i) {
        $resultData->{'authorizationCode'} = $result->getAuthorizationCode();

        my $planType = new PlugNPay::Membership::Plan::Type();
        $planType->loadPlanType($result->getTransactionTypeID());
        if ($planType->getType() =~ /auth/i) {
          $processedResult->{'billed'} += $result->getTransactionAmount();
          $processedResult->{'totalAmount'} += $result->getTransactionAmount();
        } else {
          $processedResult->{'credited'} += $result->getTransactionAmount();
          $processedResult->{'totalAmount'} -= $result->getTransactionAmount();
        }
      }

      push (@{$processedResult->{'results'}}, $resultData);
    }
  }

  return $processedResult;
}

1;
