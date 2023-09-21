package PlugNPay::API::REST::Responder::Reseller::Merchant::Adjustment;

use strict;
use PlugNPay::Reseller;
use PlugNPay::Reseller::Chain;
use PlugNPay::Transaction::Adjustment::Settings;
use PlugNPay::Transaction::Adjustment::Settings::Cap;
use PlugNPay::Transaction::Adjustment::Bucket;
use PlugNPay::Transaction::Adjustment::COA::Account;
use PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount;
use PlugNPay::Email;
use PlugNPay::UI::Template;
use JSON::XS qw(encode_json decode_json);

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;

  my $action = $self->getAction();
  my $data = $self->getInputData();
  my $reseller = $self->getResourceData()->{'reseller'};

  my $merchant = $self->getResourceData()->{'merchant'};
  my $ga = new PlugNPay::GatewayAccount($merchant);

  my $chain = new PlugNPay::Reseller::Chain();
  $chain->setReseller($self->getGatewayAccount());

  my $adjustmentInfo = [];

  # Changed to allow creation/modification by super-resellers or direct reseller.
  # This was done in JIRA issue RA-3, if necessary we can always restrict create at a later time.
  if (($action eq 'create' || $action eq 'update') && ($reseller eq $ga->getReseller() || $chain->hasDescendant($ga->getReseller()))){
    return $self->_createOrUpdate();
  } elsif ($ga->exists() && $action eq 'read' && ($reseller eq $ga->getReseller() || $chain->hasDescendant($ga->getReseller()))) {
    return $self->_read();
  }

}


sub _createOrUpdate {
  my $self = shift;

  my $merchant = $self->getResourceData()->{'merchant'};

  my $inputData = $self->getInputData();


  # check to ensure that there is a COA account with a merchant account set up.
  my $coaAccountSetup = 0;

  my $coaAccountIdentifier = $self->getInputData()->{'coaAccountIdentifier'} || $self->getCOAAccountIdentifier();

  my $coaAccount = new PlugNPay::Transaction::Adjustment::COA::Account();
  my $coaMerchantAccount;
  $coaAccount->setGatewayAccount($merchant);
  if ($coaAccount->exists()) {
    $coaAccount->load();
    $coaMerchantAccount = new PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount();
    $coaMerchantAccount->setGatewayAccount($merchant);
    $coaMerchantAccount->setMerchantAccountIdentifier($coaAccountIdentifier);
    if ($coaMerchantAccount->exists()) {
      $coaMerchantAccount->load();
      $coaAccountSetup = 1;
    }
  }

  if ($coaAccountSetup) {
    my $adjustmentSettings = new PlugNPay::Transaction::Adjustment::Settings($merchant);
    if ($adjustmentSettings->isSetup()) {
      $self->setAction('update');
    }

    # general settings
    my $modelID = $inputData->{'modelID'};
    my $enabled = $inputData->{'enabled'};
    my $customerCanOverride = $inputData->{'customerCanOverride'};
    my $overrideCheckboxIsChecked = $inputData->{'overrideCheckboxIsChecked'};
    my $checkCustomerState = $inputData->{'checkCustomerState'};
    my $adjustmentIsTaxable = $inputData->{'adjustmentIsTaxable'};
    my $processorDiscountRate = $inputData->{'processorDiscountRate'} || 0.00;

    # coa account
    my $coaAccountNumber             = $coaAccount->getAccountNumber();
    my $coaMerchantAccountIdentifier = $coaMerchantAccount->getMerchantAccountIdentifier();

    # authorization settings
    my $authorizationTypeID        = $inputData->{'authorization'}{'typeID'} || 2;
    my $authorizationFailureModeID = $inputData->{'authorization'}{'failureModeID'} || 2;
    my $authorizationAccount       = $inputData->{'authorization'}{'account'} || '';

    # threshold settings
    my $thresholdModeID  = $inputData->{'threshold'}{'modeID'};
    my $thresholdPercent = $inputData->{'threshold'}{'percent'};
    my $thresholdFixed   = $inputData->{'threshold'}{'fixed'};

    # buckets and bucket settings
    my $bucketModeID = $inputData->{'buckets'}{'modeID'};
    my $bucketDefaultSubtypeID = $inputData->{'buckets'}{'defaultTypeID'};

    my @bucketArray;
    foreach my $bucketInfo (@{$inputData->{'buckets'}{'bucket'}}) {
      my $bucket = new PlugNPay::Transaction::Adjustment::Bucket();
      $bucket->setPaymentVehicleSubtypeID($bucketInfo->{'typeID'});
      $bucket->setBase($bucketInfo->{'base'});
      $bucket->setTotalRate($bucketInfo->{'totalPercent'});
      $bucket->setFixedAdjustment($bucketInfo->{'fixedAdjustment'});
      $bucket->setCOARate($bucketInfo->{'coaPercent'});
      push @bucketArray,$bucket;
    }

    # caps and cap settings
    my $capModeID = $inputData->{'caps'}{'modeID'};
    my $capDefaultSubtypeID = $inputData->{'caps'}{'defaultTypeID'};

    my @capArray;
    foreach my $capInfo (@{$inputData->{'caps'}{'cap'}}) {
      my $cap = new PlugNPay::Transaction::Adjustment::Settings::Cap();
      $cap->setPaymentVehicleSubtypeID($capInfo->{'typeID'});
      $cap->setPercent($capInfo->{'percent'});
      $cap->setFixed($capInfo->{'fixed'});
      push @capArray,$cap;
    }

    # set general settings
    $adjustmentSettings->setEnabled($enabled);
    $adjustmentSettings->setModelID($modelID);
    $adjustmentSettings->setCustomerCanOverride($customerCanOverride);
    $adjustmentSettings->setOverrideCheckboxIsChecked($overrideCheckboxIsChecked);
    $adjustmentSettings->setCheckCustomerState($checkCustomerState);
    $adjustmentSettings->setAdjustmentIsTaxable($adjustmentIsTaxable);
    $adjustmentSettings->setProcessorDiscountRate($processorDiscountRate);

    # set coa account settings
    $adjustmentSettings->setCOAAccountNumber($coaAccountNumber);
    $adjustmentSettings->setCOAAccountIdentifier($coaMerchantAccountIdentifier);

    # authorization settings
    $adjustmentSettings->setAdjustmentAuthorizationTypeID($authorizationTypeID);
    $adjustmentSettings->setFailureModeID($authorizationFailureModeID);
    $adjustmentSettings->setAdjustmentAuthorizationAccount($authorizationAccount);

    # threshold settings
    $adjustmentSettings->setThresholdModeID($thresholdModeID);
    $adjustmentSettings->setPercentThreshold($thresholdPercent);
    $adjustmentSettings->setFixedThreshold($thresholdFixed);

    # bucket settings
    $adjustmentSettings->setBucketModeID($bucketModeID);
    $adjustmentSettings->setBucketDefaultSubtypeID($bucketDefaultSubtypeID);

    # cap settings
    $adjustmentSettings->setCapModeID($capModeID);
    $adjustmentSettings->setCapDefaultSubtypeID($capDefaultSubtypeID);

    # start a transaction
    my $dbs = new PlugNPay::DBConnection();
    $dbs->begin('pnpmisc');

    eval {
      $adjustmentSettings->save();

      # set buckets
      my $buckets = new PlugNPay::Transaction::Adjustment::Bucket($merchant);
      $buckets->setBuckets(\@bucketArray);

      # set caps
      my $caps = new PlugNPay::Transaction::Adjustment::Settings::Cap($merchant);
      $caps->setCaps(\@capArray);
    };

    if (!$@) {
      $dbs->commit('pnpmisc');
      if ($self->getAction() eq 'create') {
        $self->setResponseCode(201);
      } else {
        $self->setResponseCode(200);
      }
      return $self->_read();
    } else {
      $dbs->rollback('pnpmisc');
      $self->setResponseCode(520);
      $self->setError('An unknown error occurred.  Please contact support.');
    }
  } else {
    $self->setResponseCode(404);
    $self->setError('COA Account and/or COA Merchant Account do(es) not exist');
    return {};
  }
}

sub _read {
  my $self = shift;

  my $merchant = $self->getResourceData()->{'merchant'};

  my $adjustmentSettings = new PlugNPay::Transaction::Adjustment::Settings($merchant);
  my $adjustmentBuckets = new PlugNPay::Transaction::Adjustment::Bucket($merchant)->getBuckets({all => 1});;
  my $adjustmentCaps = new PlugNPay::Transaction::Adjustment::Settings::Cap($merchant)->getCaps();

  my %data;

  if ($adjustmentSettings->isSetup()) {
    # general settings
    $data{'enabled'} = $adjustmentSettings->getEnabled();
    $data{'modelID'} = $adjustmentSettings->getModelID();
    $data{'customerCanOverride'} = $adjustmentSettings->getCustomerCanOverride();
    $data{'overrideCheckboxIsChecked'} = $adjustmentSettings->getOverrideCheckboxIsChecked();
    $data{'checkCustomerState'} = $adjustmentSettings->getCheckCustomerState();
    $data{'adjustmentIsTaxable'} = $adjustmentSettings->getAdjustmentIsTaxable();

    # authorization settings
    my %authorization;
    $authorization{'failureModeID'} = $adjustmentSettings->getFailureModeID();
    $authorization{'typeID'} = $adjustmentSettings->getAdjustmentAuthorizationTypeID();
    $authorization{'account'} = $adjustmentSettings->getAdjustmentAuthorizationAccount();
    $data{'authorization'} = \%authorization;

    # threshold settings
    my %threshold;
    $threshold{'fixed'} = $adjustmentSettings->getFixedThreshold();
    $threshold{'percent'} = $adjustmentSettings->getPercentThreshold();
    $threshold{'modeID'} = $adjustmentSettings->getThresholdModeID();
    $data{'threshold'} = \%threshold;

    # caps
    my %caps;
    $caps{'modeID'} = $adjustmentSettings->getCapModeID();
    $caps{'defaultTypeID'} = $adjustmentSettings->getCapDefaultSubtypeID();
    my @capData;
    foreach my $cap (@{$adjustmentCaps}) {
      my %capInfo;
      $capInfo{'typeID'} = $cap->getPaymentVehicleSubtypeID();
      $capInfo{'fixed'} = $cap->getFixed();
      $capInfo{'percent'} = $cap->getPercent();
      push @capData,\%capInfo;
    }
    $caps{'cap'} = \@capData;
    $data{'caps'} = \%caps;

    # buckets
    my %buckets;
    $buckets{'modeID'} = $adjustmentSettings->getBucketModeID();
    $buckets{'defaultTypeID'} = $adjustmentSettings->getBucketDefaultSubtypeID();
    my @bucketData;
    foreach my $bucket (@{$adjustmentBuckets}) {
      my %bucketInfo;
      $bucketInfo{'typeID'} = $bucket->getPaymentVehicleSubtypeID();
      $bucketInfo{'base'} = $bucket->getBase();
      $bucketInfo{'coaPercent'} = $bucket->getCOARate();
      $bucketInfo{'totalPercent'} = $bucket->getTotalRate();
      $bucketInfo{'fixedAdjustment'} = $bucket->getFixedAdjustment();
      push @bucketData,\%bucketInfo;
    }
    $buckets{'bucket'} = \@bucketData;
    $data{'buckets'} = \%buckets;

    if (!$self->responseCodeSet()) {
      $self->setResponseCode(200)
    }
    return \%data;
  } elsif (!$self->responseCodeSet()) {
    $self->setResponseCode(404);
    $self->setError('No Adjustment settings found.');
    return {};
  }

}


sub getCOAAccountIdentifier {
  my $self = shift;

  my $merchant = $self->getResourceData()->{'merchant'};
  my $ga = new PlugNPay::GatewayAccount($merchant);

  my $identifier;

  my $cardProcessor = $ga->getCardProcessor();
  if ($cardProcessor) {
    my $cardAccount = new PlugNPay::Processor::Account({
      gatewayAccount => $merchant,
      processorName => $cardProcessor
    });
    my $ai = PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount::accountTypeAndIdentifier($cardAccount);
    $identifier = $ai->{'identifier'};
  } else {
    $identifier = 'error_bad_account';
  }

  return $identifier;
}


1;
