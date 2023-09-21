package PlugNPay::API::REST::Responder::Merchant::Adjustment;

use strict;
use PlugNPay::COA;
use PlugNPay::Country;
use PlugNPay::CreditCard;
use PlugNPay::Token::Client;
use PlugNPay::Token::Request;
use PlugNPay::Transaction::Adjustment;
use PlugNPay::GatewayAccount::LinkedAccounts;
use PlugNPay::Transaction::Adjustment::Result;
use PlugNPay::Transaction::Adjustment::Settings;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $data = {};
  my $action = lc $self->getAction();

  my $merchant = $self->getResourceData()->{'merchant'};
  my $accounts = new PlugNPay::GatewayAccount::LinkedAccounts($self->getGatewayAccount());

  if ($action eq 'create') {
    if ($accounts->isLinkedTo($merchant)) {
      $data = $self->_create($merchant);
    } else {
      $data = $self->_create();
    }
  } elsif ($action eq 'read') {
    if ($accounts->isLinkedTo($merchant)) {
      $data = $self->_read($merchant);
    } else {
      $data = $self->_read();
    }
  }

  return $data;
}

sub _create {
  my $self = shift;
  my $data = $self->getInputData();
  my $username = shift || $self->getGatewayAccount();

  # normal Adjustment required stuff
  my $transactionAmount = $data->{'transactionAmount'};
  my $transactionIdentifier = $data->{'transactionIdentifier'};
  my $discountRate = $data->{'discountRate'};
  my $fixedDiscount = $data->{'fixedDiscount'};

  # overrides
  my $mcc = $data->{'mcc'};
  my $accountType = $data->{'accountType'};

  # geographic fields
  my $state = $data->{'state'};
  my $countryCode = $data->{'countryCode'};

  my @calculations = @{$data->{'transactionInformation'}};
  my %results;

  # preprocessing stage 1, collect card number and token data from request
  # get tokens for card numbers, and card numbers for tokens
  my %cardNumbersToTokens;
  my %tokensToCardNumbers;

  foreach my $info (@calculations) {
    my $cardNumber = $info->{'cardNumber'};
    my $token = $info->{'token'};

    if ($cardNumber) {
      $cardNumbersToTokens{$cardNumber} = '';
    }
    if ($token) {
      $tokensToCardNumbers{$token} = '';
    }
  }

  # preprocessing stage 2, get tokens for card numbers and card numbers for tokens
  my @cardNumbers = keys(%cardNumbersToTokens);
  my @tokens = keys(%tokensToCardNumbers);
  my $cardNumbersToTokens = $self->requestTokens(\@cardNumbers);
  my $tokensToCardNumbers = $self->redeemTokens(\@tokens);
  my $enabled = new PlugNPay::Transaction::Adjustment::Settings($username)->getEnabled();
  # processing
  foreach my $info (@calculations) {
    my $paymentVehicleIdentifier = $info->{'paymentVehicleIdentifier'};
    my $cardNumber = $info->{'cardNumber'};
    my $token = $info->{'token'};
    my $vehicleType = uc $info->{'paymentVehicleType'};
    my $vehicleSubtype = $info->{'paymentVehicleSubtype'};

    # load missing data
    $cardNumber ||= $tokensToCardNumbers->{$token};
    $token      ||= $cardNumbersToTokens->{$cardNumber};

    # get specific transaction amount or global if no calculation specific one provided
    my $calculationTransactionAmount = $info->{'transactionAmount'} || $transactionAmount;

    # get specific transaction identifier or global if no calculation specific one provided
    my $calculationTransactionIdentifier = $info->{'transactionIdentifier'} || $transactionIdentifier;

    my $adjustmentDiscountRate = (defined $info->{'discountRate'} ? $info->{'discountRate'} : $discountRate);
    my $adjustmentFixedDiscount = (defined $info->{'fixedDiscount'} ? $info->{'fixedDiscount'} : $fixedDiscount);

    # get specific overrides
    my $calculationMCC = $info->{'mcc'} || $mcc;
    my $calculationAccountType = $info->{'accountType'} || $accountType;

    my $calculationState = $info->{'state'} || $state;
    my $calculationCountryCode = $info->{'countryCode'} || $countryCode;

    my $adjustmentCalculator = new PlugNPay::Transaction::Adjustment($username); #$self->getGatewayAccount());
    my %result;

    # some checks and setup depending on the payment vehicle type
    if ($vehicleType eq 'CARD') {
      if (defined $cardNumber) {
    #    if (defined $token) {
    #      $cardNumber = $token;
    #    }
        $adjustmentCalculator->setCardNumber($cardNumber);
      } else {
        $result{'error'} = 1;
        $result{'errorMessage'} = 'paymentVehicleType is CARD but no card number or token provided.';
      }
    } elsif ($vehicleType eq 'WALLET' && !defined $vehicleSubtype) {
      $result{'error'} = 1;
      $result{'errorMessage'} = 'paymentVehicleType is WALLET but no paymentVehicleSubtype is defined.';
    }

    # if no errors, we can calculate.
    if (!$result{'error'}) {
      $adjustmentCalculator->setTransactionAmount($calculationTransactionAmount);
      $adjustmentCalculator->setTransactionIdentifier($calculationTransactionIdentifier);
      $adjustmentCalculator->setDiscountRate($adjustmentDiscountRate);
      $adjustmentCalculator->setFixedDiscount($adjustmentFixedDiscount);

      if ($calculationCountryCode) {
        my $country = new PlugNPay::Country();
        if ($country->exists($calculationCountryCode)) {
          $adjustmentCalculator->setCountryCode($country->getNumeric($calculationCountryCode));
          $adjustmentCalculator->setState($calculationState);
        } else {
          $self->setWarning('Country [ ' . $calculationCountryCode . ' ] is invalid, surcharge will be calculated');
        }
      }

      my $adjustmentResults;

      # if error calculating we then still return 0 for adjustment and fake a success.
      if ($enabled) {
        $adjustmentResults = $adjustmentCalculator->calculate();
        if (defined $adjustmentResults->getWarning()) {
          $self->setWarning($adjustmentResults->getWarning());
        }

        if (defined $adjustmentResults->getError()) {
          $self->setError($adjustmentResults->getError());
        }
      } else {
        $adjustmentResults = new PlugNPay::Transaction::Adjustment::Result();
        my $cc = new PlugNPay::CreditCard($cardNumber);
        $adjustmentResults->setCardBrand($cc->getBrand());
        $adjustmentResults->setCardType($cc->getType());
      }

      my $default = {
        'cap'        => '0.00',
        'rate'       => 0.00,
        'adjustment' => 0.00,
        'fixed'      => 0,
      };

      # set results for a card calculation
      if ($vehicleType eq 'CARD') {
        $result{'token'} = $token;
        $result{'brand'} = $adjustmentResults->getCardBrand();
        $result{'category'} = $adjustmentResults->getCardType();

        if (keys %{$adjustmentResults->getAdjustmentData('cardMin')} > 0) {
          $result{'minimumAdjustment'} = $adjustmentResults->getAdjustmentData('cardMin');
        } else {
          $result{'minimumAdjustment'} = $default;
        }

        if (keys %{$adjustmentResults->getAdjustmentData('cardMax')} > 0) {
          $result{'maximumAdjustment'} = $adjustmentResults->getAdjustmentData('cardMax');
        } else {
          $result{'maximumAdjustment'} = $default;
        }

        if (keys %{$adjustmentResults->getAdjustmentData('calculated')} > 0) {
          $result{'calculatedAdjustment'} = $adjustmentResults->getAdjustmentData('calculated');
        } else {
          $result{'calculatedAdjustment'} = $default;
        }

        if (keys %{$adjustmentResults->getAdjustmentData('regulatedDebit')} > 0) {
          $result{'regulatedDebitAdjustment'} = $adjustmentResults->getAdjustmentData('regulatedDebit');
        } else {
          $result{'regulatedDebitAdjustment'} = $default;
        }
      } elsif ($vehicleType eq 'ACH') {
        if (keys %{$adjustmentResults->getAdjustmentData('ach')} > 0) {
          $result{'calculatedAdjustment'} = $adjustmentResults->getAdjustmentData('ach');
        } else {
          $result{'calculatedAdjustment'} = $default;
        }
      } elsif ($vehicleType eq 'WALLET') {
        my $subtype = lc $vehicleSubtype;
        if (keys %{$adjustmentResults->getAdjustmentData($subtype)} > 0) {
          $result{'calculatedAdjustment'} = $adjustmentResults->getAdjustmentData($subtype);
        } else {
          $result{'calculatedAdjustment'} = $default;
        }
      }

      $results{$paymentVehicleIdentifier} = \%result;
    }

  }

  $self->setResponseCode(201);
  return \%results;
}

sub _read {
  my $self = shift;
  my $merchant = shift || $self->getGatewayAccount();

  my $coa = new PlugNPay::COA($merchant);
  $self->setResponseCode(200);

  return {'enabled' => ($coa->getEnabled() ? 'true' : 'false')};
}

sub requestTokens {
  my $self = shift;
  my $cardNumbersArrayRef = shift;

  # build identifiers
  my $i = 1;
  my %cardNumbers = map { ('id' . $i++) => $_ } @{$cardNumbersArrayRef};

  my $request = new PlugNPay::Token::Request();

  $request->setRequestType('REQUEST_TOKENS');

  foreach my $identifier (keys %cardNumbers) {
    $request->addCardNumber($identifier,$cardNumbers{$identifier},25);
  }

  my $client = new PlugNPay::Token::Client();
  $client->setRequest($request);
  my $response = $client->getResponse();

  my %tokens;
  foreach my $identifier (keys %cardNumbers) {
    $tokens{$cardNumbers{$identifier}} = $response->get($identifier);
  }

  return \%tokens;
}

sub redeemTokens {
  my $self = shift;
  my $tokensArrayRef = shift;

  # build identifiers
  my $i = 1;
  my %tokens = map { ('id' . $i++) => $_ } @{$tokensArrayRef};

  my $request = new PlugNPay::Token::Request();

  $request->setRequestType('REDEEM_TOKENS');
  $request->setRedeemMode('PROCESSING');

  foreach my $identifier (keys %tokens) {
    $request->addToken($identifier,$tokens{$identifier},25);
  }

  my $client = new PlugNPay::Token::Client();
  $client->setRequest($request);
  my $response = $client->getResponse();

  my %cardNumbers;
  foreach my $identifier (keys %tokens) {
    $cardNumbers{$tokens{$identifier}} = $response->get($identifier);
  }

  return \%cardNumbers;
}


1;
