package PlugNPay::API::REST::Responder::Reseller::Merchant::Adjustment::COA::Account;

use base 'PlugNPay::API::REST::Responder';

use strict;
use PlugNPay::GatewayAccount;
use PlugNPay::Reseller::Chain;
use PlugNPay::Processor::Account;
use PlugNPay::Transaction::Adjustment::Settings;
use PlugNPay::Transaction::Adjustment::COA::Account;
use PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount;

sub _getOutputData {
  my $self = shift;

  my $action = $self->getAction();

  my $reseller = $self->getGatewayAccount();
  my $resellerChain = new PlugNPay::Reseller::Chain($reseller);
  my $merchant = $self->getResourceData()->{'merchant'};
  my $ga = new PlugNPay::GatewayAccount($merchant);
  my $merchantReseller = $ga->getReseller();

  #JIRA RA-3: Allow resellers to create/modify adjustment for subreseller's merchants
  if ($action eq 'read' && ($reseller eq $merchantReseller || $resellerChain->hasDescendant($merchantReseller))) {
    return $self->_read();
  } elsif ($reseller eq $merchantReseller || $resellerChain->hasDescendant($merchantReseller)) {
    if ($action eq 'create') {
      return $self->_create();
    } elsif ($action eq 'update') {
      return $self->_update();
    }
  }
}

sub _create {
  my $self = shift;

  my $merchant = $self->getResourceData()->{'merchant'};
  my $ga = new PlugNPay::GatewayAccount($merchant);

  my $inputData = $self->getInputData();

  # get the ach fee from the input data
  my $achFee = $inputData->{'achFee'} || 0.00;

  # get the company name
  my $companyName = $ga->getCompanyName();

  my $notes = 'Created by: ' . $self->getGatewayAccount();

  my $coaAccount = new PlugNPay::Transaction::Adjustment::COA::Account();
  $coaAccount->setGatewayAccount($merchant);
  if ($coaAccount->exists()) {
    $self->setResponseCode(409);
    $self->setError('COA Account already exists for merchant');
    return {};
  }

  $coaAccount->setName($companyName);
  $coaAccount->setNotes($notes);
  $coaAccount->setACHFee($achFee);
  $coaAccount->create();

  $self->setResponseCode(201);
  return $self->_read();
}

sub _read {
  my $self = shift;

  my $merchant = $self->getResourceData()->{'merchant'};
  my $ga = new PlugNPay::GatewayAccount($merchant);

  my $adjustmentSettings = new PlugNPay::Transaction::Adjustment::Settings($merchant);
  my $coaAccountNumber = $adjustmentSettings->getCOAAccountNumber();
  my $coaAccount = new PlugNPay::Transaction::Adjustment::COA::Account();
  $coaAccount->setGatewayAccount($merchant);
  $coaAccount->setAccountNumber($coaAccountNumber);
  $coaAccount->load();
  my $validMid = ($ga->checkMid() ? 'true' : 'false');

  # return not found if there is no account number
  if (!$coaAccount->getAccountNumber()) {
    $self->setResponseCode(404);
    $self->setError('Account not found.');
    return { mid => $validMid };
  # return conflict if the gateway account for the coa account does not match the customer
  } elsif ($merchant ne $coaAccount->getGatewayAccount()) {
    $self->setResponseCode(409);
    return {};
  }


  my $accountData = {
    accountNumber => $coaAccount->getAccountNumber(),
    achFee => $coaAccount->getACHFee(),
    mid => $validMid
  };

  if (!$self->responseCodeSet()) {
    $self->setResponseCode('200');
  }
  return { account => $accountData };
}

sub _update {
  my $self = shift;

  my $merchant = $self->getResourceData()->{'merchant'};
  my $ga = new PlugNPay::GatewayAccount($merchant);

  my $coaAccount;
  my $adjustmentSettings = new PlugNPay::Transaction::Adjustment::Settings($merchant);
  my $coaAccountNumber = $adjustmentSettings->getCOAAccountNumber();
  $coaAccount = new PlugNPay::Transaction::Adjustment::COA::Account();
  $coaAccount->setGatewayAccount($merchant);
  $coaAccount->setAccountNumber($coaAccountNumber);

  if ($coaAccount->exists()) {
    $coaAccount->load();
    # get the ach fee from the input data
    my $achFee = $self->getInputData()->{'achFee'} || 0.00;
    $coaAccount->setACHFee($achFee);
    if (!$coaAccount->update()) {
      $self->setResponseCode(520);
    }
    $self->{'coaAccount'} = $coaAccount;
    $self->_read();
  } else {
    $self->setResponseCode(404);
  }
}



1;
