package PlugNPay::Transaction::Adjustment;

use strict;

use PlugNPay::Country;
use PlugNPay::Currency;
use PlugNPay::Country::State;
use PlugNPay::GatewayAccount;
use PlugNPay::Transaction::Adjustment::Settings;
use PlugNPay::Transaction::Adjustment::Model;
use PlugNPay::Transaction::Adjustment::Bucket;
use PlugNPay::Transaction::Adjustment::COARemote;
use PlugNPay::Transaction::Adjustment::Settings::BucketMode;
use PlugNPay::Transaction::Adjustment::Settings::Threshold;
use PlugNPay::Transaction::Adjustment::Settings::Cap;
use PlugNPay::Transaction::Adjustment::Result;
use PlugNPay::Transaction::PaymentVehicle::Subtype;
use PlugNPay::Transaction::PaymentVehicle;
use PlugNPay::Util::RPN;
use PlugNPay::Util::Cache::TimerCache;

our $_bucketCache_;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!$_bucketCache_) {
    $_bucketCache_ = new PlugNPay::Util::Cache::TimerCache(60);
  }

  my $gatewayAccount = shift;

  if ($gatewayAccount) {
    $self->setGatewayAccount($gatewayAccount);
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
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

sub setPaymentVehicle {
  my $self = shift;
  my $paymentVehicle = shift;
  $self->{'paymentVehicle'} = $paymentVehicle;
}

sub getPaymentVehicle {
  my $self = shift;
  return $self->{'paymentVehicle'};
}

sub setCardNumber {
  my $self = shift;
  my $cardNumber = shift;
  $self->{'cardNumber'} = $cardNumber;
}

sub getCardNumber {
  my $self = shift;
  return $self->{'cardNumber'};
}

sub setTransactionIdentifier {
  my $self = shift;
  my $transactionIdentifier = shift;
  $self->{'transactionIdentifier'} = $transactionIdentifier;
}

sub getTransactionIdentifier {
  my $self = shift;
  return $self->{'transactionIdentifier'};
}

sub setDiscountRate {
  my $self = shift;
  my $discountRate = shift;
  $self->{'discountRate'} = $discountRate;
}

sub getDiscountRate {
  my $self = shift;
  return $self->{'discountRate'};
}

sub setFixedDiscount {
  my $self = shift;
  my $fixedDiscount = shift;
  $self->{'fixedDiscount'} = $fixedDiscount;
}

sub getFixedDiscount {
  my $self = shift;
  return $self->{'fixedDiscount'};
}

sub setCountryCode {
  my $self = shift;
  my $countryCode = shift;
  $self->{'countryCode'} = $countryCode;
}

sub getCountryCode {
  my $self = shift;
  return $self->{'countryCode'};
}

sub setState {
  my $self = shift;
  my $state = shift;
  $self->{'state'} = $state;
}

sub getState {
  my $self = shift;
  return $self->{'state'};
}

sub calculate {
  my $self = shift;

  # create the response object
  my $result = new PlugNPay::Transaction::Adjustment::Result();

  my $gatewayAccount = new PlugNPay::GatewayAccount($self->getGatewayAccount);

  # load the settings
  my $settings = new PlugNPay::Transaction::Adjustment::Settings($self->getGatewayAccount);

  # load the model data
  my $model = new PlugNPay::Transaction::Adjustment::Model($settings->getModelID());

  # if the model is surcharge and a country was sent, check the country/state info
  # calculate if all else fails
  if ($model->getModel() =~ /^surcharge$/ && $self->{'countryCode'}) {
    my $countries = new PlugNPay::Country::State()->getSurchargeEligibleCountries();
    # if the country code exists in this hash, then check the state table
    if (exists $countries->{$self->{'countryCode'}}) {
      my $state = new PlugNPay::Country::State($self->{'state'});
      my $country = new PlugNPay::Country($state->getCountry());

      # check if valid state for country and exists
      if ($state->exists() && $country->getNumeric() == $self->{'countryCode'}) {
        # if the surcharge is false for state, don't calculate
        if (!$state->getCanSurcharge()) {
          return $result;
        }
      } else {
        $result->setWarning('state [ ' . $self->{'state'} . ' ], country [ ' . new PlugNPay::Country($self->{'countryCode'})->getThreeLetter() . ' ] not valid, surcharge was calculated');
      }
    }
  }

  # get the available transaction payment vehicle subtypes
  my $availableSubtypes = $gatewayAccount->getPaymentVehicleSubtypes();

  my $coaRemote = new PlugNPay::Transaction::Adjustment::COARemote();

  $coaRemote->setAdjustmentVersion($settings->getVersion());
  $coaRemote->setAccountNumber($settings->getCOAAccountNumber());
  $coaRemote->setAccountIdentifier($settings->getCOAAccountIdentifier());
  $coaRemote->setTransactionAmount($self->getTransactionAmount());
  $coaRemote->setTransactionIdentifier($self->getTransactionIdentifier());
  $coaRemote->setCardNumber($self->getCardNumber);

  my $coaResponse = $coaRemote->getResponse();

  my $thresholdCalculator = new PlugNPay::Transaction::Adjustment::Settings::Threshold($settings->getThresholdModeID());
  $thresholdCalculator->setTransactionAmount($self->getTransactionAmount());
  $thresholdCalculator->setFixed($settings->getFixedThreshold());
  $thresholdCalculator->setPercent($settings->getPercentThreshold());
  my $threshold = $thresholdCalculator->calculateThreshold();

  my $capCalculator = new PlugNPay::Transaction::Adjustment::Settings::Cap({ gatewayAccount => $self->getGatewayAccount(),
                                                                             transactionAmount => $self->getTransactionAmount(),
                                                                             modeID => $settings->getCapModeID(),
                                                                             defaultPaymentVehicleSubtypeID => $settings->getCapDefaultSubtypeID() });

  my %adjustments;

  my $discountRate = $settings->getDiscountRate();
  if (defined $self->getDiscountRate()) {
    if (!defined $settings->getMaxDiscountRate() || $self->getDiscountRate() < $settings->getMaxDiscountRate()) {
      $discountRate = $self->getDiscountRate();
    } elsif (defined $settings->getMaxDiscountRate()) {
      $discountRate = $settings->getMaxDiscountRate();
    }
  }

  my $fixedDiscount = $settings->getFixedDiscount();
  if (defined $self->getFixedDiscount()) {
    if (!defined $settings->getMaxFixedDiscount() || $self->getFixedDiscount() < $settings->getMaxFixedDiscount()) {
      $fixedDiscount = $self->getFixedDiscount();
    } elsif (defined $settings->getMaxFixedDiscount()) {
      $fixedDiscount = $settings->getMaxFixedDiscount();
    }
  }

  my $calculateSubtypeSettings = {
    bucketModeID => $settings->getBucketModeID(),
    defaultSubtypeID => $settings->getBucketDefaultSubtypeID(),
    maxCOAAdjustmentAmount => $coaResponse->getAdjustment('maximum'),
    threshold => $threshold,
    formula => $model->getFormula(),
    discountRate => $discountRate,
    fixedDiscount => $fixedDiscount,
    processorDiscountRate => $settings->getProcessorDiscountRate()
  };

  # loop through each available subtype and calculate the fee for each, ignoring card types except regulated debit
  foreach my $subtype (@{$availableSubtypes}) {
    delete $calculateSubtypeSettings->{'isDebit'};
    my $coaAdjustmentAmount = 0;
    my $paymentVehicleSubtypeInfo = new PlugNPay::Transaction::PaymentVehicle::Subtype($subtype);
    my $paymentVehicleSubtype = $paymentVehicleSubtypeInfo->getSubtype();
    my $paymentVehicleInfo = new PlugNPay::Transaction::PaymentVehicle($paymentVehicleSubtypeInfo->getPaymentVehicleID());
    my $paymentVehicle = $paymentVehicleInfo->getVehicle();

    $calculateSubtypeSettings->{'subtypeID'} = $subtype;
    $calculateSubtypeSettings->{'cap'} = $capCalculator->getCap($subtype);

    if ($paymentVehicle eq 'ACH') {
      $calculateSubtypeSettings->{'coaAdjustmentAmount'} = $coaResponse->getAdjustment('ach');
      $adjustments{'ach'} = $self->calculateSubtype($calculateSubtypeSettings);
    } elsif ($paymentVehicle eq 'CARD' && $paymentVehicleSubtype eq 'DEBIT') {
      $calculateSubtypeSettings->{'coaAdjustmentAmount'} = $coaResponse->getAdjustment('regulatedDebit');
      $calculateSubtypeSettings->{'isDebit'} = 1;
      $adjustments{'regulatedDebit'} = $self->calculateSubtype($calculateSubtypeSettings);
    } elsif ($paymentVehicle eq 'WALLET' && $paymentVehicleSubtype eq 'SEQR') {
      $calculateSubtypeSettings->{'coaAdjustmentAmount'} = $coaResponse->getAdjustment('seqr');
      $adjustments{'seqr'} = $self->calculateSubtype($calculateSubtypeSettings);
    }
  }

  # delete the debit flag if it's set
  delete $calculateSubtypeSettings->{'isDebit'};

  # calculate the minimum and maximum card amounts
  # max
  my $maxSubtypeID = $coaResponse->getMaxSubtypeID();
  $calculateSubtypeSettings->{'cap'} = $capCalculator->getCap($maxSubtypeID);
  $calculateSubtypeSettings->{'coaAdjustmentAmount'} = $coaResponse->getAdjustment('maximum');
  $calculateSubtypeSettings->{'subtypeID'} = $maxSubtypeID;
  $adjustments{'cardMax'} = $self->calculateSubtype($calculateSubtypeSettings);
  # min
  my $minSubtypeID = $coaResponse->getMinSubtypeID();
  $calculateSubtypeSettings->{'cap'} = $capCalculator->getCap($minSubtypeID);
  $calculateSubtypeSettings->{'coaAdjustmentAmount'} = $coaResponse->getAdjustment('minimum');
  $calculateSubtypeSettings->{'subtypeID'} = $minSubtypeID;
  $adjustments{'cardMin'} = $self->calculateSubtype($calculateSubtypeSettings);

  # get the calculated fee
  my $calculatedSubtypeID = $coaResponse->getSubtypeID();
  if ($coaResponse->getIsDebit()) {
    $calculateSubtypeSettings->{'isDebit'} = 1;
  }
  $calculateSubtypeSettings->{'cap'} = $capCalculator->getCap($calculatedSubtypeID);
  $calculateSubtypeSettings->{'coaAdjustmentAmount'} = $coaResponse->getAdjustment('calculated');
  $calculateSubtypeSettings->{'subtypeID'} = $calculatedSubtypeID;
  $adjustments{'calculated'} = $self->calculateSubtype($calculateSubtypeSettings);

  foreach my $feeType (keys %adjustments) {
    $result->setAdjustmentData($adjustments{$feeType},$feeType);
  }

  $result->setModel($model->getModel());
  $result->setThreshold($threshold);
  $result->setCardBrand($coaResponse->getCardBrand());
  $result->setCardType($coaResponse->getCardType());

  return $result;
}

sub calculateSubtype {
  my $self = shift;
  my $settings = shift;
  my $subtypeID = $settings->{'subtypeID'};
  my $defaultSubtypeID = $settings->{'defaultSubtypeID'};
  my $coaAdjustmentAmount = $settings->{'coaAdjustmentAmount'} || 0;
  my $maxCOAAdjustmentAmount = $settings->{'maxCOAAdjustmentAmount'};
  my $bucketModeID = $settings->{'bucketModeID'};
  my $isDebit = $settings->{'isDebit'} || 0;
  my $threshold = $settings->{'threshold'};
  my $formula = $settings->{'formula'} || 0;
  my $cap = $settings->{'cap'};
  my $discountRate = $settings->{'discountRate'};
  my $fixedDiscount = $settings->{'fixedDiscount'};
  my $processorDiscountRate = $settings->{'processorDiscountRate'};

  my $bucketModeInfo = new PlugNPay::Transaction::Adjustment::Settings::BucketMode($bucketModeID);
  my $bucketMode = $bucketModeInfo->getMode();

  my $amount = $self->getTransactionAmount();

  my $bucketLoader = new PlugNPay::Transaction::Adjustment::Bucket();
  $bucketLoader->setMode($bucketMode);
  $bucketLoader->setGatewayAccount($self->getGatewayAccount());
  $bucketLoader->setPaymentVehicleSubtypeID($subtypeID);
  $bucketLoader->setDefaultPaymentVehicleSubtypeID($defaultSubtypeID);
  $bucketLoader->setTransactionAmount($amount);

  my $buckets = $self->getBucketsForSubtypeID($bucketLoader);

  my $bucketAmount = $amount;

  my $calculatedAdjustment = 0;

  my $totalRate = 0;
  my $fixedAdjustment = 0;

  foreach my $bucket (@{$buckets}) {
    # if the bucket mode is stepped, only get the portion that needs to be calculated
    # in this particular bucket and decrement the total amount by that amount
    if ($bucketModeInfo->getMode() eq 'stepped') {
      $bucketAmount = $amount - $bucket->getBase();
      $amount = $amount - $bucketAmount;
    }

    $totalRate += $bucket->getTotalRate();
    $fixedAdjustment += $bucket->getFixedAdjustment();

    my $rpn = new PlugNPay::Util::RPN();
    $rpn->addVariable('coaRate',$bucket->getCOARate()/100);
    $rpn->addVariable('maxCOA',$maxCOAAdjustmentAmount);
    $rpn->addVariable('coa',$coaAdjustmentAmount);
    $rpn->addVariable('totalRate',$bucket->getTotalRate()/100);
    $rpn->addVariable('total',$bucketAmount);
    $rpn->addVariable('fixedAdjustment',$bucket->getFixedAdjustment());
    $rpn->addVariable('debit',$isDebit);
    $rpn->addVariable('pdr',$processorDiscountRate/100);
    $rpn->addVariable('transactionAmount',$self->getTransactionAmount());
    $rpn->setFormula($formula);

    $calculatedAdjustment += $rpn->calculate();
  }

  # apply the threshold
  $calculatedAdjustment = (abs($calculatedAdjustment) >= $threshold ? $calculatedAdjustment : 0);

  # apply the cap
  if (defined $cap) {
    $calculatedAdjustment = ($calculatedAdjustment > $cap ? $cap : $calculatedAdjustment);
  }

  if (defined $discountRate) {
    $calculatedAdjustment -= ($calculatedAdjustment * ($discountRate/100));
  }

  if (defined $fixedDiscount) {
    $calculatedAdjustment -= $fixedDiscount;
  }


  if (ref($self->getGatewayAccount()) !~ /^PlugNPay::GatewayAccount/) {
    $self->setGatewayAccount(new PlugNPay::GatewayAccount($self->getGatewayAccount()));
  }

  my $procAccountSettings = new PlugNPay::Processor::Account({
    processorName => $self->getGatewayAccount()->getCreditCardProcessor(),
    gatewayAccount => $self->getGatewayAccount()
  });
  my $currency = $procAccountSettings->getSettingValue("currency");

  use PlugNPay::Debug;
  debug { currencyIs => $currency };

  my $formattedCalculatedAdjustment = new PlugNPay::Currency($currency)->format($calculatedAdjustment, { 'digitSeparator' => '', 'truncate' => 1 });

  return { adjustment => $formattedCalculatedAdjustment, rate => $totalRate, fixed => $fixedAdjustment, cap => $cap };
}

sub getBucketsForSubtypeID {
  my $self = shift;
  my $bucketLoader = shift;

  my $allTheBuckets = $_bucketCache_->get($self->getGatewayAccount());
  if ($allTheBuckets ne undef) {
    $self->{'allBuckets'} = $allTheBuckets;
  } else {
    my $bucketData = $bucketLoader->getAllBuckets();
    $_bucketCache_->set($self->getGatewayAccount(),$bucketData);
    $self->{'allBuckets'} = $bucketData;
  }

  my $subtypeID = $bucketLoader->getPaymentVehicleSubtypeID();
  if (!$bucketLoader->bucketExistsForSubtypeID($subtypeID)) {
    $subtypeID = $bucketLoader->getDefaultPaymentVehicleSubtypeID();
  }

  my $transactionAmount = $bucketLoader->getTransactionAmount();
  my $bucketMode = $bucketLoader->getMode();

  my $allBuckets = $self->{'allBuckets'};

  my @buckets;
  if (defined($transactionAmount)) {
    my @bucketsForSubtype;
    foreach my $bucket (@{$allBuckets}) {
      if (($bucket->{'paymentVehicleSubtypeID'} eq $subtypeID) && ($bucket->{'base'} <= $transactionAmount)) {
        push @bucketsForSubtype, $bucket;
      }
    }

    # do descending sort by 'base'
    my @sortedBuckets = sort {$b->{'base'} <=> $a->{'base'}} @bucketsForSubtype;

    # if mode is 'single' only add highest bucket
    if ($bucketMode eq 'single' && $sortedBuckets[0]) {
      push @buckets, @sortedBuckets[0];
    }
    else {
      @buckets = @sortedBuckets;
    }
  }

  return \@buckets;
}


1;
