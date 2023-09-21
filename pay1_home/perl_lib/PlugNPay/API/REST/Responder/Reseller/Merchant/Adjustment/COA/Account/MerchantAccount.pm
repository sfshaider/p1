package PlugNPay::API::REST::Responder::Reseller::Merchant::Adjustment::COA::Account::MerchantAccount;

use base 'PlugNPay::API::REST::Responder';

use strict;
use PlugNPay::GatewayAccount;
use PlugNPay::Reseller::Chain;
use PlugNPay::Processor::Account;
use PlugNPay::Transaction::Adjustment::Settings;
use PlugNPay::Transaction::Adjustment::COA::Account;
use PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount;
use PlugNPay::Transaction::Adjustment::COA::ProcessorMap;

sub _getOutputData {
  my $self = shift;

  my $action = $self->getAction();

  my $reseller = $self->getGatewayAccount();
  my $resellerChain = new PlugNPay::Reseller::Chain($reseller);
  my $merchant = $self->getResourceData()->{'merchant'};
  my $ga = new PlugNPay::GatewayAccount($merchant);
  my $merchantReseller = $ga->getReseller();

  #JIRA RA-3: Allow creation/updating of Adjustment accounts of subresellers
  #NOTE: Still restricting delete, seems like a good idea

  if ($action eq 'read' && ($reseller eq $merchantReseller || $resellerChain->hasDescendant($merchantReseller))) {
    return $self->_read();
  } elsif ($action eq 'delete' && $reseller eq $merchantReseller) {
    return $self->_delete();
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

  my $mcc = $self->getInputData()->{'mcc'};

  my $processor = new PlugNPay::Processor({shortName => $ga->getCardProcessor()});
  my $processorAccount = new PlugNPay::Processor::Account({gatewayAccount => $merchant,processorID => $processor->getID()});
  my $coaProcessorMap = new PlugNPay::Transaction::Adjustment::COA::ProcessorMap();
  my $coaProcessorID = $coaProcessorMap->getCOAProcessor($processor->getID());

  if (!defined $coaProcessorID) {
    $self->setResponseCode(422);
    $self->setError('Incompatible processor');
    return {};
  }

  my $countryInfo = new PlugNPay::Country($ga->getMainContact()->getCountry());
  my $countryCode = $countryInfo->getNumeric();

  my $accountType;

  my $identifier = $self->getInputData()->{'identifier'};

  my $ai = PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount::accountTypeAndIdentifier($processorAccount);
  $accountType = $ai->{'accountType'};
  $identifier = $ai->{'identifier'};

  # check to see if the merchant account already exists
  my $merchantAccount = new PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount();
  $merchantAccount->setGatewayAccount($merchant);
  $merchantAccount->setMerchantAccountIdentifier($identifier);

  if ($merchantAccount->exists()) {
    $self->setError('Merchant account already exists with identifier: ' . $identifier);
    $self->setResponseCode(409);
    return {};
  }

  $merchantAccount->setProcessorID($coaProcessorID);
  $merchantAccount->setMID($processorAccount->getSettings()->{'mid'});
  $merchantAccount->setMCC($mcc);
  $merchantAccount->setCountryCode($countryCode);
  $merchantAccount->setType($accountType);

  my $createStatus = $merchantAccount->create();
  if ($createStatus) {
    $self->setResponseCode(201);
    $self->_read();
  } else {
    $self->setError('Could not create merchant account.  Contact support.');
    $self->setResponseCode(409);
    return {};
  }
}

sub _read {
  my $self = shift;

  my $merchant = $self->getResourceData()->{'merchant'};
  my $ga = new PlugNPay::GatewayAccount($merchant);

  # read input data first, then resource data, for the identifier, as an update could change the identifier,
  # and the new one would be sent as input data
  my $identifier = $self->getInputData()->{'identifier'} || $self->getResourceData()->{'identifier'};
  my $processor = new PlugNPay::Processor({shortName => $ga->getCardProcessor()});
  my $processorAccount = new PlugNPay::Processor::Account({'processorName' => $ga->getCardProcessor(), 'gatewayAccount' => $merchant});
  my $ai = PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount::accountTypeAndIdentifier($processorAccount);

  $identifier = $ai->{'identifier'};

  my $merchantAccount = new PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount();
  $merchantAccount->setGatewayAccount($merchant);
  $merchantAccount->setMerchantAccountIdentifier($identifier);

  if (!$merchantAccount->exists()) {
    $self->setError('Merchant account not found for identifier: ' . $identifier);
    $self->setResponseCode(404);
    return {};
  }

  $merchantAccount->load();
  my $validMid = ($ga->checkMid() ? 'true' : 'false');

  my $accountData = {
    mcc => $merchantAccount->getMCC(),
    mid => $validMid

  };

  if (!$self->responseCodeSet()) {
    $self->setResponseCode('200');
  }

  return { merchantAccount => $accountData };
}

sub _update {
  my $self = shift;

  my $merchant = $self->getResourceData()->{'merchant'};
  my $ga = new PlugNPay::GatewayAccount($merchant);

  my $identifier = $self->getResourceData()->{'identifier'};
  my $processor = new PlugNPay::Processor({shortName => $ga->getCardProcessor()});
  my $processorAccount = new PlugNPay::Processor::Account({'processorName' => $ga->getCardProcessor(), 'gatewayAccount' => $merchant});
  my $ai = PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount::accountTypeAndIdentifier($processorAccount);
  $identifier = $ai->{'identifier'};

  my $merchantAccount = new PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount();
  $merchantAccount->setGatewayAccount($merchant);
  $merchantAccount->setMerchantAccountIdentifier($identifier);

  if (!$merchantAccount->exists()) {
    $self->setError('Merchant account not found for identifier: ' . $identifier);
    $self->setResponseCode(404);
    return {};
  }

  my $mcc = $self->getInputData()->{'mcc'};

  $merchantAccount->load();
  $merchantAccount->setMCC($mcc);
  my $updateResult = $merchantAccount->update();
  if (!$updateResult) {
    $self->setError('Could not update merchant account.  Contact support');
    $self->setResponseCode(520);
    return {};
  } else {
    $self->setResponseCode(200);
  }

  $self->_read();
}

sub _delete {
  my $self = shift;

  $self->setError('Merchant accounts can not be deleted');
  $self->setResponseCode(403);
  return {};
}

1;
