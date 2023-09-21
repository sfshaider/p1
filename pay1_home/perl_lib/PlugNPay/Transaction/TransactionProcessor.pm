package PlugNPay::Transaction::TransactionProcessor;

use strict;
use PlugNPay::Fraud;
use PlugNPay::Features;
use PlugNPay::ConvenienceFee;
use PlugNPay::COA;
use PlugNPay::Transaction::TransactionMagic;
use PlugNPay::Transaction::TransactionRouting;
use PlugNPay::Transaction::TestMode;
use PlugNPay::Sys::Time;
use PlugNPay::GatewayAccount;
use PlugNPay::GatewayAccount::EnabledCardBrands;
use PlugNPay::Logging::DataLog;
use PlugNPay::Receipt;
use PlugNPay::SECCode;
use PlugNPay::Transaction::Context;
use PlugNPay::Transaction::Logging::Adjustment;
use PlugNPay::Transaction::Response;
use PlugNPay::Transaction::MapLegacy;
use PlugNPay::Transaction::Security;
use PlugNPay::Country::State;
use PlugNPay::Transaction::Receipt;
use PlugNPay::Util::UniqueID;
use PlugNPay::Processor::Account;
use PlugNPay::Processor::Route;
use PlugNPay::Transaction::TransactionProcessor::Validate;
use PlugNPay::Transaction::TransactionProcessor::Transform;
use PlugNPay::Die;
use PlugNPay::Util::Array qw(inArray);
use JSON::XS;
use Time::HiRes;
use miscutils;

our $lastOrderID;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub disableTestMode {
  my $self = shift;
  delete $self->{'testMode'};
}

sub checkTransactionResponse {
  my $self = shift;
  my $transactionObj = shift;
  my $responseObj = shift;
  my $fraudString = shift;
  my $featuresObj = shift;
  my $transactionSecurity = new PlugNPay::Transaction::Security();
  my $settingsMatch = $transactionSecurity->checkFraudConfigAndResponse($transactionObj, $responseObj, $fraudString, $featuresObj);
  my $response = { 'shouldVoid' => 0 };
  if ($settingsMatch) {
    $response = $transactionSecurity->shouldAVSVoid($transactionObj, $responseObj, $fraudString, $featuresObj);
  }
  return $response;
}

sub processVoid {
  my $self = shift;
  my $transactionObject = shift;
  my $response = shift;
  my %error = (); # returned if wantarray() is true

  $transactionObject->setTransactionMode('void');
  $transactionObject->setTransactionState('VOID_PENDING');
  $transactionObject->setTransactionType('void');

  # create a new transaction object to process the void
  my $voidProcessor = new PlugNPay::Transaction::TransactionProcessor;
  my $voidResponse = $voidProcessor->process($transactionObject);
  if($voidResponse->getStatus() eq 'success') {
    my $paymentAccount = (defined $transactionObject->getPayment() ? $transactionObject->getPayment()->getMaskedNumber() : $transactionObject->getPNPToken());
    my $action = '/Transaction/' . (ucfirst lc $transactionObject->getTransactionType()) . '/' . (ucfirst lc $transactionObject->getTransactionPaymentType());
    my $message = { 'pt_order_id'           => $transactionObject->getOrderID(),
                    'pt_transaction_amount' => $transactionObject->getTransactionAmount(),
                    'payment_account'       => $paymentAccount,
                    'process_account'       => $transactionObject->getGatewayAccount(),
                    'transaction_type'      => $transactionObject->getTransactionType(),
                    'result'                => $response->getStatus
                  };

    my $env = new PlugNPay::Environment();
    $self->log({suser        => $env->get('PNP_USER'),
                duser        => $env->get('PNP_ACCOUNT'),
                src          => $env->get('PNP_CLIENT_IP'),
                deviceAction => $action,
                data         => $message
              });
  }

  if (wantarray()) {
    return ($voidResponse,\%error);
  }
  return $voidResponse;
}

########################################
# Route the transaction if appropriate #
########################################
sub routeTransaction {
  my $self = shift;
  my $transactionObject = shift;

  my $tr = new PlugNPay::Transaction::TransactionRouting();
  $tr->setTransaction($transactionObject);
  my $newUsername = $tr->tranRouting();
  if ($newUsername ne $transactionObject->getGatewayAccount()) {
    $transactionObject->setGatewayAccount($newUsername);
    my $logData = {
       'message'          => 'Transaction route returned new username',
       'originalUsername' => $transactionObject->getGatewayAccount(),
       'username'         => $newUsername,
       'orderID'          => $transactionObject->getOrderID(),
       'processor'        => $transactionObject->getProcessor(),
       'paymentType'      => $transactionObject->getTransactionPaymentType(),
       'transactionType'  => $transactionObject->getTransactionType(),
       'function'         => 'process'
    };
  }
}

#########################
# Process a transaction #
#########################
sub process {
  my $self = shift;
  my $transactionObject = shift;
  my $options = shift || {};

  # set the processor id on the transaction object, this will be useful later on.
  my $gatewayAccount = new PlugNPay::GatewayAccount($transactionObject->getGatewayAccount());
  my $transactionPaymentType = $transactionObject->getTransactionPaymentType();
  my $processor = $gatewayAccount->getProcessorByProcMethod($transactionPaymentType);
  my $processorObject = new PlugNPay::Processor({ shortName => $processor });
  my $processorId = $processorObject->getID();
  $transactionObject->setProcessorID($processorId);
  # set ids if they don't exist
  # Merchant Order ID
  if (!defined $transactionObject->getOrderID() || $transactionObject->getOrderID() eq '') {
    $transactionObject->setOrderID($self->generateOrderID());
  }

  # PNP Transaction ID
  if (!defined $transactionObject->getPNPTransactionID() || $transactionObject->getPNPTransactionID() eq '') {
    $transactionObject->setPNPTransactionID($self->generateId());
  }

  if (!defined $transactionObject->getPNPOrderID() || $transactionObject->getPNPOrderID() eq '') {
    $transactionObject->setPNPOrderID($self->generateId());
  }

  # get transactionId as a variable for code clarity
  my $referenceId = $transactionObject->getPNPTransactionReferenceID();
  my $transactionId = $transactionObject->getPNPTransactionID();

  my $transactionVersion;
  eval {
     $transactionVersion = $transactionObject->getTransactionVersion();
  };

  my $context = new PlugNPay::Transaction::Context({
    gatewayAccount => $gatewayAccount,
    transactionId => $referenceId || $transactionId,
    processorId => $processorId,
    transactionVersion => $transactionVersion
  });

  my $response;
  my $error; # returned if wantarray() is true

  eval { # so we can release the lock for the context.
    # store the base amount for logging later
    my $baseAmount = $transactionObject->getTransactionAmount();

    # route the transaction if the routing feature is set
    my $accountFeatures = $gatewayAccount->getFeatures();
    if ($accountFeatures->get('tranroutingflg') == 1) {
      $self->routeTransaction($transactionObject);
    }

    my %results;
    my $startTime = Time::HiRes::time();
    $response = new PlugNPay::Transaction::Response($transactionObject);
    $self->{'startTime'} = $startTime if !defined $self->{'startTime'};
    my $transformer = new PlugNPay::Transaction::TransactionProcessor::Transform({ context => $context });
    $transformer->transform({ transaction => $transactionObject });
    ### ADJUSTMENT ###
    my $convenienceFee = new PlugNPay::ConvenienceFee($transactionObject->getGatewayAccount());
    my $coa = new PlugNPay::COA($transactionObject->getGatewayAccount());

    $transactionObject->setBaseTransactionAmount($transactionObject->getTransactionAmount());
    $transactionObject->setBaseTaxAmount($transactionObject->getTaxAmount());

    if (inArray($transactionObject->getTransactionType(),['auth','reauth'])) {
      $self->adjustForSurcharge($transactionObject,$convenienceFee,$coa);
    };
    ### END ADJUSTMENT ###
    my $validator = new PlugNPay::Transaction::TransactionProcessor::Validate({ context => $context });

    my $validationStatus = $validator->canProceed({ transaction => $transactionObject });
    my %results;
    if (!$validationStatus) {
      my $errorMessage = $validationStatus->getError();
      $error = $errorMessage;
      $results{'errorMessage'} = $results{'MErrMsg'}     = $errorMessage;
      $results{'status'}       = $results{'FinalStatus'} = 'problem';
    } else {
      ########################################################
      # Enable test mode if the account is set to test mode. #
      # This stays set once it has been set until the object #
      # destroyed or if disableTestMode() is called          #
      ########################################################
      if ($gatewayAccount->isTestModeEnabled()) {
        $self->{'testMode'} = new PlugNPay::Transaction::TestMode();
      } else {
        $self->{'testMode'} = undef;
      }
      ########################################################
      # Generate a merchant order id if none exists already. #
      ########################################################
      if (!defined $transactionObject->getOrderID() || $transactionObject->getOrderID() eq '') {
         $transactionObject->setOrderID($self->generateOrderID());
      }

      ############################
      # Set the transaction time #
      ############################
      $transactionObject->setTime(time());

      ##################################################
      # |||                                        ||| #
      # ||| Abandon all hope all ye who enter here ||| #
      # vvv                                        vvv #
      ##################################################
      PlugNPay::Transaction::TransactionMagic::Confundo($transactionObject);

      # Get processor account
      my $processor;
      if ($transactionObject->getTransactionPaymentType() eq 'credit') {
        $processor = $gatewayAccount->getCardProcessor();
      } elsif ($transactionObject->getTransactionPaymentType() eq 'ach') {
        $processor = $gatewayAccount->getACHProcessor();
      }
      my $processorAccount = new PlugNPay::Processor::Account({
        gatewayAccount => $transactionObject->getGatewayAccount(),
        processorName => $processor
      });

      # Get authtype
      my $authType;
      my $processorSettings = $processorAccount->getSettings();
      for my $key (keys %{$processorSettings}) {
        if ($key eq 'authType') {
          $authType = ${$processorSettings}{$key};
        }
      }

      if ($transactionObject->getTransactionType() eq 'auth' && $authType eq 'authpostauth' && $transactionObject->getTransactionAmount() > 0) {
        $transactionObject->setPostAuth();
      }

      my $fraudConfig = new PlugNPay::Features("$gatewayAccount",'fraud_config');
      my $fraudObject = new PlugNPay::Fraud({'gatewayAccount' => $gatewayAccount->getGatewayAccountName(), 'fraudConfig' => $fraudConfig});

      #Pre Auth screen
      my $mode = $transactionObject->getTransactionMode();
      my $isAuth = ($mode =~ /^auth/i || $mode eq 'reauth' || (!$mode && $transactionObject->getTransactionType() eq 'auth')); #VT does not set mode
      if (!$transactionObject->getIgnoreFraudCheckResponse()) {
        if ($isAuth) {
          my $fraudResponse = $fraudObject->preAuthScreen($transactionObject);

          if ($fraudResponse->{'isDuplicate'}) {
            %results = (
              FinalStatus => 'duplicate',
              FraudMsg    => $fraudResponse->{'errors'},
              MErrMsg     => 'Transaction was flagged as a duplicate',
              MStatus     => 'duplicate',
              status => 'duplicate',
              duplicate => 1,
              errorMessage => 'transaction was flagged as duplicate'
            );
          } elsif ($fraudResponse->{'isFraud'}) {
            %results = (
              FinalStatus  => 'fraud',
              FraudMsg     => $fraudResponse->{'errors'},
              MErrMsg      => 'Transaction was flagged as fraudulent',
              MStatus      => 'fraud',
              'resp-code'  => 'P57',
              status       => 'fraud',
              errorMessage => 'transaction was flagged as fraudulent',
              fraudLogId   => $fraudResponse->{'logId'}
            );
          }
        }
      }

      my $startSendMServer = Time::HiRes::time();

      if ($self->{'testMode'} &&
          defined $transactionObject->getCreditCard() &&
          $self->{'testMode'}->isTestCard($transactionObject->getCreditCard()->getNumber())) {
        %results = $self->{'testMode'}->process($transactionObject);

        if ($results{'pnp_order_id'}) {
          $transactionObject->setPNPOrderID($results{'pnp_order_id'});
        }
      } elsif ($results{'FinalStatus'} !~ /fraud|badcard|duplicate/i) {
        eval { # this is in eval so that the context will always have a chance to release the lock
          (%results, $error) = %{$self->sendmserverWrapper({ transaction => $transactionObject, context => $context })};
        };
        $context->releaseLock();
      }

      my $endSendMServer = Time::HiRes::time();
      $self->{'sendMServerDuration'} = $endSendMServer - $startSendMServer;
      $response->setRawResponse(\%results);
      if (!$transactionObject->getIgnoreFraudCheckResponse()) {
        if ($isAuth) {
          my $postAuthResponse = $fraudObject->postAuthScreen($transactionObject, $response, $fraudConfig);
          if ($postAuthResponse->{'finalStatus'} eq 'fraud') {
            $response->setStatus('fraud');
            $response->setMessage($postAuthResponse->{'message'});
            if (ref($postAuthResponse->{'errors'}) eq 'HASH') {
              my %newFraudHash = (%{$response->getFraudMessage()}, %{$postAuthResponse->{'errors'}});
              $response->setFraudMessage(\%newFraudHash);
            }
          }
        }
      }
      my ($user,$account,$ip);

      my $env = new PlugNPay::Environment();
      if ($env) {
        $user = $env->get('PNP_USER');
        $account = $env->get('PNP_ACCOUNT');
        $ip = $env->get('PNP_CLIENT_IP');
      }

      my $paymentAccount = (defined $transactionObject->getPayment() ? $transactionObject->getPayment()->getMaskedNumber() : $transactionObject->getPNPToken());

      my $action = '/Transaction/' . (ucfirst lc $transactionObject->getTransactionType()) . '/' . (ucfirst lc $transactionObject->getTransactionPaymentType());
      my $message = { 'pt_order_id'           => $transactionObject->getOrderID(),
                      'pt_transaction_amount' => $transactionObject->getTransactionAmount(),
                      'payment_account'       => $paymentAccount,
                      'process_account'       => $transactionObject->getGatewayAccount(),
                      'transaction_type'      => $transactionObject->getTransactionType(),
                      'result'                => $response->getStatus()
                    };

      $self->log({suser        => $env->get('PNP_USER'),
                  duser        => $env->get('PNP_ACCOUNT'),
                  src          => $env->get('PNP_CLIENT_IP'),
                  deviceAction => $action,
                  data         => $message
                 });

      #checks fraud config and avs responses
      if ($response->getStatus() eq 'success') {
        my $avsCheck = $self->checkTransactionResponse($transactionObject, $response, $fraudConfig->getFeatureString(), $accountFeatures);
        if ($isAuth) {
          if ($avsCheck->{'shouldVoid'}) {
            $response->setStatus('badcard');
            my $voidResponse = $self->processVoid($transactionObject, $response);
            if (defined $voidResponse && $voidResponse->getStatus() eq 'success') {
              $response->setErrorMessage('Transaction Voided: ' . $avsCheck->{'reason'});
              $transactionObject->setReason($avsCheck->{'reason'});
            } else {
              $response->setErrorMessage('Transaction caught by AVS check but system was unable to void at this time');
            }
          } elsif (new PlugNPay::Transaction::Security()->shouldCVCVoid($transactionObject, $response, $fraudConfig->getFeatureString(), $accountFeatures)) {
            $response->setStatus('badcard');
            my $voidResponse = $self->processVoid($transactionObject, $response);
            if (defined $voidResponse && $voidResponse->getStatus() eq 'success') {
              my $voidMsg = 'CVV2/CVC2 number does not match card';
              $response->setErrorMessage('Transaction Voided: ' . $voidMsg);
              $transactionObject->setReason($voidMsg);
            } else {
              $response->setErrorMessage('Transaction failed CVV match but system was unable to void at this time');
            }
          } elsif ($response->getStatus() eq 'success' && $transactionObject->doPostAuth()) {
            # process a post auth if necessary
            my $postAuthObject = $transactionObject->clone();
            if ($transactionObject->getTransactionMode() eq 'auth') {
              $postAuthObject->setPostAuth();
            }
            $postAuthObject->setTransactionMode('postauth');
            $postAuthObject->setTransactionType('postauth');
            my $postAuthResponse = $self->process($postAuthObject);
            $response->setPostAuthResponse($postAuthResponse);
          }
        }
      }
      # create adjustment log object
      my $adjustmentLog = new PlugNPay::Transaction::Logging::Adjustment();
      $adjustmentLog->setGatewayAccount($transactionObject->getGatewayAccount());
      $adjustmentLog->setOrderID($transactionObject->getOrderID());
      $adjustmentLog->setBaseAmount($baseAmount);
      my $hexID = $transactionObject->getPNPTransactionID();
      if ($hexID) {
        my $id = new PlugNPay::Util::UniqueID();
        $id->fromHex($hexID);
        my $binaryID = $id->inBinary();
        $adjustmentLog->setPNPTransactionID($binaryID);
      }

      if ($isAuth && !$transactionObject->isConvenienceChargeTransaction() && $response->getStatus() eq 'success') {
        my $startSecondCharge = Time::HiRes::time();
        my $secondChargeResponse;
        my $failureRule;

        #####################################################
        # Check to see if a convinience charge should occur #
        # Ensure transaction is set up for it and the       #
        # merchant has a feature set for it.                #
        #####################################################
        if ($convenienceFee->getEnabled()) {
          $failureRule = $convenienceFee->getFailureRule();
          $secondChargeResponse = $self->useConvenienceFee($transactionObject,$convenienceFee);
        }

        ################################################################
        # Check to see if coa is used and apply any adjustments #
        # that may be required, including possibly charging a fee to   #
        # another account.                                             #
        ################################################################
        elsif ($coa->getEnabled() && !$self->overrideAdjustment($transactionObject,$coa)) {
          $failureRule = $coa->getFailureRule();
          $secondChargeResponse = $self->useCOA($transactionObject,$coa);
        }

        if (ref($secondChargeResponse) eq 'PlugNPay::Transaction::Response') {
          # If the response from useCOA is a transaction response
          if ($secondChargeResponse->getStatus() ne 'success' &&                         # and the status isn't a success, we want to void the transaction
              $failureRule eq 'void') {                                                   # if that is how coa is set up
            my $voidResponse = $self->processVoid($transactionObject, $response);
            
            if($voidResponse->getStatus() eq 'success') {

              # set the error flag and error message since the VFF Failed
              $results{'status'} = 'voided';
              $results{'errorMessage'} = 'Second Transaction Failed.';
              $transactionObject->setReason($results{'errorMessage'});

              my $paymentAccount = (defined $transactionObject->getPayment() ? $transactionObject->getPayment()->getMaskedNumber() : $transactionObject->getPNPToken());
              my $action = '/Transaction/' . (ucfirst lc $transactionObject->getTransactionType()) . '/' . (ucfirst lc $transactionObject->getTransactionPaymentType());
              my $message = { 'pt_order_id'           => $transactionObject->getOrderID(),
                              'pt_transaction_amount' => $transactionObject->getTransactionAmount(),
                              'payment_account'       => $paymentAccount,
                              'process_account'       => $transactionObject->getGatewayAccount(),
                              'transaction_type'      => $transactionObject->getTransactionType(),
                              'result'                => $response->getStatus
                            };

              $self->log({suser        => $env->get('PNP_USER'),
                          duser        => $env->get('PNP_ACCOUNT'),
                          src          => $env->get('PNP_CLIENT_IP'),
                          deviceAction => $action,
                          data         => $message
                         });
            }
          }

          my %secondChargeInformation;
          $secondChargeInformation{'gatewayAccount'} = $secondChargeResponse->getTransaction()->getGatewayAccount();
          $secondChargeInformation{'orderID'}        = $secondChargeResponse->getTransaction()->getOrderID();

          $transactionObject->setConvenienceChargeInfoForTransaction(\%secondChargeInformation);

          $adjustmentLog->setAdjustmentTotalAmount($secondChargeResponse->getTransaction()->getTransactionAmount());
          $adjustmentLog->setAdjustmentGatewayAccount($secondChargeResponse->getTransaction()->getGatewayAccount());
          $adjustmentLog->setAdjustmentOrderID($secondChargeResponse->getTransaction()->getOrderID());
          my $hexID = $secondChargeResponse->getTransaction()->getPNPTransactionID();
          if ($hexID) {
            my $id = new PlugNPay::Util::UniqueID();
            $id->fromHex($hexID);
            my $binaryID = $id->inBinary();
            $adjustmentLog->setAdjustmentPNPTransactionID($binaryID);
          }
        }

        my $endSecondCharge = Time::HiRes::time();
        $self->{'secondChargeDuration'} = $endSecondCharge - $startSecondCharge;
      } else {
        $adjustmentLog->setAdjustmentTotalAmount($transactionObject->getTransactionAmount() - $baseAmount);
      }

      if (substr($transactionObject->getTransactionType(),0,4) eq 'auth' && !$response->getDuplicate()) {
        $adjustmentLog->log();
      }
    }

    # Delete magensa data from the db
    if ($transactionObject->getTransactionPaymentType() =~ /^(credit|gift)$/) {
      my $cc = $transactionObject->getCreditCard();
      if ($cc) {
        my $magensaSwipe = $cc->getMagensa();
        my $ksn = $cc->getKSNFromSwipeData($magensaSwipe,$cc->getSwipeDevice());
        if ($ksn ne '') {
          if ($cc->magensaSwipeExists($ksn)) {
            $cc->deleteMagensaSwipeData($ksn);
          }
        }
      }
    }

    my $endTime = Time::HiRes::time();
    $self->{'endTime'} = $endTime;

    $self->{'transactionDuration'} = $results{'transactionDuration'} = $endTime - $startTime;
    # if there is a different status set, set it.
    if (defined $results{'status'} && $results{'status'} ne '') {
      $response->setStatus($results{'status'});
    }

    # if there was an error, set that in the response before returning it.
    if (defined $results{'errorMessage'} && $results{'errorMessage'} ne '') {
      $response->setErrorMessage($results{'errorMessage'});
    }

    if ($options->{'sendEmailReceipt'}) {
      my $sendIt = 1;

      # send only for auths
      $sendIt &= ($transactionObject->getTransactionType() eq 'auth');

      # do not send if avsonly is set
      $sendIt &= (!$transactionObject->hasTransFlag('avsonly'));

      # only send for success or otherwise recurring transactions
      $sendIt &= ($response->getStatus() eq 'success' || ($transactionObject->hasTransFlag('recurring') || $transactionObject->hasTransFlag('recinit')));
      if ($sendIt) {
        $self->sendEmailReceipt({ transaction => $transactionObject,
                                     response => $response,
                                    ccAddress => $options->{'ccAddress'} });
      }
    }
  };
  # TODO handle eval error
  $context->releaseLock();

  if (wantarray()) {
    return ($response,$error);
  }
  return $response;
}

sub getTransactionDuration {
  my $self = shift;
  return $self->{'transactionDuration'};
}

sub getSendMServerDuration {
  my $self = shift;
  return $self->{'sendMServerDuration'};
}

sub getSecondChargeDuration {
  my $self = shift;
  return $self->{'secondChargeDuration'}
}

sub getBuildSendMServerPairsDuration {
  my $self = shift;
  return $self->{'buildSendMServerPairsDuration'};
}

sub adjustForSurcharge {
  my $self = shift;
  my $transactionObject = shift;
  my $convenienceFee = shift;
  my $coa =  shift;

  #########################################################################################
  # Check to see if a convenience fee surcharge or card charge surcharge is taking place. #
  #########################################################################################
  my $transactionAmount = $transactionObject->getTransactionAmount();
  my $transactionTaxAmount = $transactionObject->getTaxAmount();

  my $adjustmentData;

  # get the billing state, default to the gateway account's state
  my $billingInformation = $transactionObject->getBillingInformation();
  my $billingState;
  if ($billingInformation) {
    $billingState = $billingInformation->getState();
  } else {
    my $gatewayAccount = new PlugNPay::GatewayAccount($transactionObject->getGatewayAccount());
    $billingState = $gatewayAccount->getMainContact()->getState();
  }

  # allow surcharge in all states by default
  my $stateCanSurcharge = 1;

  # if merchant only surcharges in states that allow it, check if state allows it
  if ($coa->getCheckCustomerState()) {
    my $stateObj = new PlugNPay::Country::State();
    $stateObj->setState($billingState);
    $stateCanSurcharge = $stateObj->getCanSurcharge();
  }

  if (!$self->overrideAdjustment($transactionObject,$coa)) {
    if ($convenienceFee->getEnabled() && $convenienceFee->isSurcharge()) {
      $transactionObject->adjustmentIsSurcharge();
      $adjustmentData = $self->getConvenienceFeeAdjustment($transactionObject,$convenienceFee);
    } elsif ($coa->getEnabled() && ($coa->isSurcharge() && $stateCanSurcharge) || $coa->isOptional()) {
      $transactionObject->adjustmentIsSurcharge();
      $adjustmentData = $self->getCOAAdjustment($transactionObject,$coa);
    } elsif ($coa->getEnabled() && $coa->isDiscount()) {
      $adjustmentData = $self->getCOAAdjustment($transactionObject,$coa);
    }
  }

  if ($adjustmentData) {
    $transactionObject->setTransactionAmountAdjustment($adjustmentData->{'adjustment'});

    # Apply the adjustment.
    $transactionAmount += $adjustmentData->{'adjustmentWithTax'};
    $transactionObject->setTransactionAmount($transactionAmount);

    $transactionTaxAmount += $adjustmentData->{'adjustmentTax'};
    $transactionObject->setTaxAmount($transactionTaxAmount);

    $transactionObject->setConvenienceChargeTransaction();
  }
}

sub getConvenienceFeeAdjustment {
  my $self = shift;
  my $transactionObject = shift;
  my $convenienceFeeObject = shift;

  # We need four things to calculate a convenience fee:  transaction amount, payment type (credit/ach), card category (if credit), and precision.
  # for now we let precision default to 2

  ##########################
  # Get transaction amount #
  # tax amount, and and    #
  # tax rate               #
  my $transactionAmount = $transactionObject->getTransactionAmount();
  my $taxAmount =         $transactionObject->getTaxAmount();
  my $effectiveTaxRate =  $transactionObject->getEffectiveTaxRate();

  ########################
  # Get the payment type #
  my $paymentType = $transactionObject->getTransactionPaymentType();

  #########################
  # Get the card category #
  my $category;
  if ($paymentType eq 'credit') {
    if (defined $transactionObject->getPayment()) {
      $category = $transactionObject->getPayment()->getCategory();
    } elsif ($transactionObject->getPNPToken() != "") {
      my $card = new PlugNPay::CreditCard();
      $card->fromToken($transactionObject->getPNPToken());
      $category = $card->getCategory();
    }
  }

  ###########################
  # Get the convenience fee #
  my $adjustment = $convenienceFeeObject->getConvenienceFee($transactionAmount,$paymentType,$category);

  ############################
  # Apply effective tax rate #
  my $adjustmentTax = ($adjustment * $effectiveTaxRate);
  my $adjustmentWithTax = $adjustment + $adjustmentTax;


  return {'adjustment' => $adjustment,
          'adjustmentWithTax' => $adjustmentWithTax,
          'adjustmentTax' => $adjustmentTax};
}

sub useConvenienceFee {
  my $self = shift;
  my $transactionObject = shift;
  my $convenienceFeeObject = shift;

  my $adjustmentData = $self->getConvenienceFeeAdjustment($transactionObject,$convenienceFeeObject);

  my $convenienceFeeResults;

  ################################
  # Clone the transaction object #
  my $convenienceTransactionObject = $transactionObject->clone();

  ##############################################
  # Generate a new OrderID for the transaciton #
  $convenienceTransactionObject->setOrderID($self->generateOrderID());

  #####################################################
  # Set the convenience fee amount in the transaction #
  $convenienceTransactionObject->setTransactionAmount($adjustmentData->{'adjustment'});

  #####################################################
  # Clear tax amount from convenience fee transaction #
  $convenienceTransactionObject->setTaxAmount(0);

  #########################################################
  # Store the amount of the fee in the transaction object #
  #########################################################
  $transactionObject->setTransactionAmountAdjustment($adjustmentData->{'adjustment'});

  ################################################
  # Set the account to run the transaction under #
  $convenienceTransactionObject->setGatewayAccount($convenienceFeeObject->getChargeAccount());

  my %transactionInformation;
  $transactionInformation{'gatewayAccount'} = $transactionObject->getGatewayAccount();
  $transactionInformation{'orderID'}        = $transactionObject->getOrderID();

  $convenienceTransactionObject->setConvenienceChargeInfoForTransaction(\%transactionInformation);
  $convenienceTransactionObject->setConvenienceChargeTransaction();

  $transactionObject->setConvenienceChargeTransactionLink($convenienceTransactionObject);

  if ($adjustmentData->{'adjustment'} == 0) {
    # no fee so fake success response
    $convenienceFeeResults = new PlugNPay::Transaction::Response($convenienceTransactionObject);
    $convenienceFeeResults->setStatus('success');
  } else {
    # process the convenience fee
    $convenienceFeeResults = $self->process($convenienceTransactionObject);
  }

  return $convenienceFeeResults;
}

sub getCOAAdjustment {
  my $self = shift;
  my $transactionObject = shift;
  my $coaObject = shift;

  my $transactionAmount = $transactionObject->getTransactionAmount();
  my $taxAmount =         $transactionObject->getTaxAmount();
  my $effectiveTaxRate =  $transactionObject->getEffectiveTaxRate();

  my $creditCard = $transactionObject->getCreditCard();

  my $adjustment;

  if ($creditCard) {
    my $cardNumber = $creditCard->getNumber();
    $adjustment = $coaObject->getAdjustment($cardNumber,$transactionAmount);
  } else {
    $adjustment = $coaObject->get('000000',$transactionAmount)->{'achAdjustment'};
  }

  my $adjustmentTax = ($adjustment * $effectiveTaxRate);
  my $adjustmentWithTax = $adjustment + $adjustmentTax;

  return {'adjustment' => $adjustment,
          'adjustmentWithTax' => $adjustmentWithTax,
          'adjustmentTax' => $adjustmentTax};
}

sub useCOA {
  my $self = shift;
  my $transactionObject = shift;
  my $coaObject = shift;

  my $model = $coaObject->getModel();

  my $result;

  my $adjustmentData = $self->getCOAAdjustment($transactionObject,$coaObject);

  # Act upon the model.  Note: InstantChoice does not have any actions. #
  if ( $coaObject->isFee() ) {
    ################################
    # Clone the transaction object #
    my $vffTransactionObject = $transactionObject->clone();
    $vffTransactionObject->setConvenienceChargeTransaction();

    my %transactionInformation;
    $transactionInformation{'gatewayAccount'} = $transactionObject->getGatewayAccount();
    $transactionInformation{'orderID'}        = $transactionObject->getOrderID();

    ##############################################
    # Generate a new OrderID for the transaciton #
    $vffTransactionObject->setOrderID($self->generateOrderID());

    $vffTransactionObject->setConvenienceChargeInfoForTransaction(\%transactionInformation);
    $vffTransactionObject->setGatewayAccount($coaObject->getChargeAccount());
    $vffTransactionObject->setTransactionAmount($adjustmentData->{'adjustment'});
    $vffTransactionObject->setTaxAmount(0);

    $transactionObject->setConvenienceChargeTransactionLink($vffTransactionObject);
    $transactionObject->setTransactionAmountAdjustment($adjustmentData->{'adjustment'});

    if ($coaObject->getAuthorizationType() eq 'authpostauth') {
      $vffTransactionObject->setPostAuth();
    }

    if ($adjustmentData->{'adjustment'} == 0) {
      # no fee so fake success response
      $result = new PlugNPay::Transaction::Response($vffTransactionObject);
      $result->setStatus('success');
    } else {
      # process the vff
      $result = $self->process($vffTransactionObject);
    }
  }

  return $result;
}

#Compatibility Function
sub sendEmailReceipt {
  my $self = shift;
  my $data = shift;
  return new PlugNPay::Transaction::Receipt()->sendEmailReceipt($data);
}

##########################################
# Wrapper to call miscutils::sendmserver #
##########################################
sub sendmserverWrapper {
  my $self = shift;
  my $input = shift;

  my $transactionObject = $input->{'transaction'};
  my $context = $input->{'context'};

  my @sendmserverData;

  # The first two arguments to transaction type are the gateway account and the transaction type, so populate those;
  my $operation = $transactionObject->getTransactionType();
  if ($transactionObject->doForceAuth()) {
    $operation = 'forceauth';
  }

  push @sendmserverData,$transactionObject->getGatewayAccount();
  push @sendmserverData,$operation;

  my $startPairs = Time::HiRes::time();
  my $map = new PlugNPay::Transaction::MapLegacy(); #Replaced sub buildSendMServerPairs
  my $pairs = $map->map($transactionObject);
  my $endPairs = Time::HiRes::time();
  $self->{'buildSendMServerPairsDuration'} = $endPairs - $startPairs;

  $pairs->{'username'} = $transactionObject->getGatewayAccount();
  $pairs->{'operation'} = $operation;

  my $router = new PlugNPay::Processor::Route();

  my ($transactionResults,$error) = $router->route({ transactionData => $pairs, transactionContext => $context, transactionObject => $transactionObject });
  if (wantarray()) {
    return ($transactionResults,$error);
  }
  return $transactionResults;
}

sub generateOrderID {
  # This can only generate 3 order id's per second due to the format of orderIDs.
  # If three have been generated, then it will sleep until the next second and try again..

  my $time = new PlugNPay::Sys::Time();
  my $now = $time->inFormat('gendatetime');
  my $pid = sprintf('%05d',$$);

  my $orderID = $now . $pid;
  if (defined $lastOrderID) {
    while ($orderID <= $lastOrderID) {
      if ($pid > (32768 * 2) ) {
        # sleep a bit until we have a new second
        do {
          if ( -e '/home/pay1/log/genorderid.log' && -w '/home/pay1/log/genorderid.log') {
            eval {
              my $orderIdDebugHandle;
              my $stackTrace = new PlugNPay::Util::StackTrace()->string(',');
              open($orderIdDebugHandle,'>>','/home/pay1/log/genorderid.log');
              print $orderIdDebugHandle sprintf("[PID:%d][SCRIPT:%s] I am sleepy! [STACKTRACE:%s]\n",$$,$ENV['SCRIPT_FILENAME'],$stackTrace);
              close($orderIdDebugHandle);
            };
            # TODO handle eval error
          }
          select(undef,undef,undef,0.1);
        } while ($now eq $time->nowInFormat('gendatetime'));
        $now = $time->nowInFormat('gendatetime');
        $pid = sprintf('%05d',$$);
        $orderID = $now . $pid;
      } else {
        $pid += 32768;
        $orderID = $now . $pid;
      }
    }
  }
  $lastOrderID = $orderID;
  return $orderID;
}

sub log {
  my $self = shift;
  my $data = shift;
  $data->{'package'} = 'PlugNPay::Transaction::TransactionProcessor';

  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'transaction'});
  $logger->log($data);
}

sub overrideAdjustment {
  my $self = shift;
  my $transactionObject = shift;
  my $coa =  shift;

  return $transactionObject->getOverrideAdjustment() && $coa->getCustomerCanOverride();
}

sub getCreditCardBrandName {
  my $self = shift;
  return $self->{'credit_card_brand_name'};
}

# Checks if a credit card number's brand is allowed.
# By default, all brands are enabled for every merchant.
# Merchants only get added to that table when they want a card brand disabled.
# If brand is in table customer_card_brand_enabled and is a 0 then it is disabled.
sub isCardBrandAllowed {
  my $self = shift;
  my $gatewayAccountName = shift;
  my $cardNumber = shift;

  my $creditCard = new PlugNPay::CreditCard();
  $creditCard->setNumber($cardNumber);
  my $brandname = $creditCard->getBrandName();

  my $enabledBrands = new PlugNPay::GatewayAccount::EnabledCardBrands();
  $enabledBrands->setGatewayAccountName($gatewayAccountName);
  $enabledBrands->load();

  $self->{'credit_card_brand_name'} = $brandname;
  my $isDisabled = $enabledBrands->brandIsDisabled($brandname);

  return !$isDisabled;
}

sub generateId {
  my $self = shift;
  my $uid = new PlugNPay::Util::UniqueID();
  return $uid->inHex();
}

1;
