package PlugNPay::Fraud::Duplicate;

use strict;
use PlugNPay::Features;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::GatewayAccount;
use PlugNPay::Transaction::Loader::Fraud;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $username = shift;
  if ($username) {
    $self->setGatewayAccount($username);
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  my $gaObject = new PlugNPay::GatewayAccount($gatewayAccount);
  $self->setFraudConfig($gaObject->getParsedFraudConfig());
  $self->setFeatures($gaObject->getFeatures());
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setFraudConfig {
  my $self = shift;
  my $fraudConfig = shift;

  if (ref($fraudConfig) ne 'PlugNPay::Features') {
    my $config = new PlugNPay::Features('fraud');
    $config->parseFeatureString($fraudConfig);
    $fraudConfig = $config;
  }

  $self->{'fraudConfig'} = $fraudConfig;
}

sub getFraudConfig {
  my $self = shift;
  return $self->{'fraudConfig'};
}

sub setFeatures {
  my $self = shift;
  my $features = shift;

  if (ref($features) ne 'PlugNPay::Features') {
    my $config = new PlugNPay::Features();
    $config->parseFeatureString($features);
    $features = $config;
  }

  $self->{'features'} = $features;
}

sub getFeatures {
  my $self = shift;
  return $self->{'features'};
}

sub isDuplicate {
  my $self = shift;
  my $originalTrans = shift;
  my $fraudConfig = shift || $self->getFraudConfig();
  my $features = shift || $self->getFeatures();
  my $loader = new PlugNPay::Transaction::Loader::Fraud();
  my $isDuplicate = 0;
  my $transaction = $originalTrans->clone();

  if ($transaction->getAccountCode(1) ne 'PremierGift') {
    my $duplicateCheckTime = $fraudConfig->get('dupchktime');
    $duplicateCheckTime =~ s/[^0-9]//g;
    
    #why? I do not know but this is what the old code checked
    if ($duplicateCheckTime < 1 || $duplicateCheckTime > 9999) {
      $duplicateCheckTime = 5;
    }

    my $timeObj = new PlugNPay::Sys::Time();
    $timeObj->subtractMinutes($duplicateCheckTime);

    my @duplicateCheckItems = split('|', $features->get('dupchklist'));
    my $searchItems = $self->parseCheckList($transaction, $fraudConfig->get('dupchkvar'));

    if (@duplicateCheckItems > 0) {
      push @duplicateCheckItems, $transaction->getGatewayAccount();
      $searchItems->{'username'} = \@duplicateCheckItems;
    } else {
      $searchItems->{'username'}   = $transaction->getGatewayAccount();
    }

    $searchItems->{'transaction_mode'} = $transaction->getTransactionMode() || $transaction->getTransactionState();
    $searchItems->{'transaction_amount'} = $transaction->getTransactionAmount();
    $searchItems->{'transaction_date_time'} = $timeObj->inFormat('db_gm');
    $searchItems->{'pnp_token'}  = $transaction->getPayment()->getToken();
    $searchItems->{'shacardnumber'} = $transaction->getPayment()->getCardHash();
    $searchItems->{'processor'} = $transaction->getProcessor();
    $searchItems->{'billing_name'} = $transaction->getBillingInformation()->getFullName();
    if (!$searchItems->{'billing_name'} || $searchItems->{'billing_name'} =~ /\s+/) {
      $searchItems->{'billing_name'} = $transaction->getPayment()->getName();
    }
    $searchItems->{'billing_postal_code'} = $transaction->getBillingInformation()->getPostalCode();
    $searchItems->{'payment_type'} = $transaction->getTransactionPaymentType();

    $isDuplicate = $loader->loadDuplicate($searchItems);
  }

  return $isDuplicate;
}

sub parseCheckList {
  my $self = shift;
  my $transaction = shift;
  my $items = shift;

  my @variables = split('|', $items);
  my $checks = {};
  foreach my $var (@variables) {
    if ($var eq 'acct_code') {
       $checks->{'account_code'}{1} = $transaction->getAccountCode(1);
    } elsif ($var eq 'acct_code2') {
       $checks->{'account_code'}{2} = $transaction->getAccountCode(2);
    } elsif ($var eq 'acct_code3') {
       $checks->{'account_code'}{3} = $transaction->getAccountCode(3);
    } elsif ($var eq 'acct_code4') {
       $checks->{'account_code'}{4} = $transaction->getAccountCode(4);
    }
  }

  return $checks;
}

sub log {
  my $self = shift;
  my $error = shift;
  my $data = shift;
  
  new PlugNPay::Logging::DataLog({'collection' => 'fraudtrack'})->log({
    'error'  => $error,
    'data'   => $data,
    'module' => ref($self)
  });
}

1;
