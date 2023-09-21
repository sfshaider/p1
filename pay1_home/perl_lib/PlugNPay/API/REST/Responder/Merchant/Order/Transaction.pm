package PlugNPay::API::REST::Responder::Merchant::Order::Transaction;

use strict;
use PlugNPay::Token;
use PlugNPay::Sys::Time;
use PlugNPay::Transaction;
use PlugNPay::GatewayAccount;
use PlugNPay::Util::UniqueID;
use PlugNPay::Transaction::State;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::JSON;
use PlugNPay::Transaction::JSON::Versioned;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::Formatter;
use PlugNPay::Processor::Process;
use PlugNPay::Processor::Process::Void;
use PlugNPay::Processor::Process::Settlement;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Transaction::Logging::Adjustment;
use PlugNPay::Processor;
use PlugNPay::Util::IP::Address;
use PlugNPay::Util::UniqueID;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Util::Clone;
use PlugNPay::GatewayAccount::LinkedAccounts;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  my $response = {};

  my $merchant = $self->getResourceData()->{'merchant'};
  if ($merchant ne '' && $merchant ne $self->getGatewayAccount()) {
    my $accounts = new PlugNPay::GatewayAccount::LinkedAccounts($self->getGatewayAccount());
    if (!$accounts->isLinkedTo($merchant)) {
      $self->setResponseCode(403);
      $self->setError('Permission denied to specified account');
      return {'status' => 'failure', 'message' => 'Permission denied'};
    }
  }


  if ($action eq 'read') { #Load Transaction(s) (GET)
    $response = $self->_read();
  } elsif ($action eq 'create') { #New Transaction(s) (POST)
    $response = $self->_create();
  } elsif ($action eq 'update') { #Settle Transaction(s) (PUT)
    $response = $self->_update();
  } elsif ($action eq 'options') { #For CORS only
    $response = $self->_options();
  } elsif ($action eq 'delete') { #Void Transaction(s)
    $response = $self->_delete();
  } else {
   $self->setResponseCode(501);
   $self->setError('Invalid Action: ' . $action);
   $response =  {'status' => 'failure', 'message' => 'Invalid Action'};
  }

  return $response;
}

#####################
# Options Functions #
#####################
# For CORS Preflight
sub _options {
  my $self = shift;
  $self->setResponseCode(200);
  return {};
}

####################
# Create Functions #
####################
# New Transaction(s)
sub _create {
  my $self = shift;
  my $info = $self->getInputData();
  my $transactions = $info->{'transactions'};
  if (ref($transactions) ne 'HASH') {
    $self->setResponseCode(422);
    $self->setError('Bad data type: ' . ref($transactions));
    return {};
  }

  my @keys = keys %{$transactions};
  if ( @keys > 20 ) {
    $self->setResponseCode(422);
    return {'status' => 'failure', 'message' => 'Transaction limit is 20 per request'};
  } elsif (@keys < 1) {
    $self->setResponseCode(422);
    return {'status' => 'failure', 'message' => 'No Transactions Set'};
  } else {
    $self->setResponseCode(200);
    my $response = $self->_processTransactions($transactions);
    return $response;
  }
}

sub _processTransactions {
  my $self = shift;
  my $transactions = shift;
  my $time = new PlugNPay::Sys::Time();
  my $transactionList = {};
  my $errorList = {};
  my $transactionProcessor = new PlugNPay::Transaction::TransactionProcessor();
  my $runSync = $self->getRequestOptions()->{'synchronous'};

  my $featuresAccountUsername = $self->getGatewayAccount();
  my $featuresAccount = new PlugNPay::GatewayAccount($featuresAccountUsername);
  my $features = $featuresAccount->getFeatures();

  my $shrinkResponse = $features->get('rest_api_shrink_response');

  my $originalStates = {};

  foreach my $transID (keys %{$transactions}) {
    my $data = $transactions->{$transID};
    my $message = '';
    my $status = 0;
    my @datetime = split(' ',$time->inFormat('db'));

    my $type = lc($data->{'payment'}{'type'});
    my $mode = lc($data->{'payment'}{'mode'});

    # check for errors
    if (not ($mode =~ /^auth/ || $mode eq 'forceauth' || $mode eq 'sale' || $mode eq 'return' || $mode eq 'credit')) {
      # mode error
      if ($mode eq 'void') {
        $errorList->{$transID}{'message'} = 'Transaction was not processed: use DELETE method for voids';
      } elsif ($mode eq 'capture' || $mode eq 'postauth') {
        $errorList->{$transID}{'message'} = 'Transaction was not processed: use PUT method for captures';
      } else {
        $errorList->{$transID}{'message'} = 'Transaction was not processed: bad payment mode';
      }
      $errorList->{$transID}{'amount'} = $data->{'amount'};
      $errorList->{$transID}{'mode'} = $mode;
      $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
    }

    if (!$data->{'transactionRefID'} && $mode ne 'return') {
      if ($type eq 'credit' || $type eq 'card' || $type eq 'gift') {
        if (!$self->containsCardPaymentInfo($data)) {
          $errorList->{$transID}{'message'} = 'Transaction was not processed: no payment data';
          $errorList->{$transID}{'amount'} = $data->{'amount'};
          $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
        }
      } elsif ($type eq 'ach') {
        my $hasACHData = (defined $data->{'payment'}{'ach'}{'accountNumber'} && defined $data->{'payment'}{'ach'}{'routingNumber'});
        if (!defined $data->{'payment'}{'ach'}{'token'} && !$hasACHData) {
          $errorList->{$transID}{'message'} = 'Transaction was not processed: no payment data';
          $errorList->{$transID}{'amount'} = $data->{'amount'};
          $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
        }
      } else {
        # type error
        $errorList->{$transID}{'message'} = 'Transaction was not processed: bad payment type';
        $errorList->{$transID}{'amount'} = $data->{'amount'};
        $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
      }
    }

    # no errors, process transactions
    my $trans = new PlugNPay::Transaction($mode, $type);
    if (!defined $trans) {
      # Bad transaction
      $self->setResponseCode(520);
      $self->log({'message' => 'Error creating transaction in responder', 'mode' => $mode, 'type'=>$type});
      return {'status'=> 'failure', 'message'=> 'Unknown error occurred'};
    }

    my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();

    my $contact = new PlugNPay::Contact();
    if (defined $data->{'billingInfo'}) {
      $contact->setFullName($data->{'billingInfo'}{'name'});
      $contact->setAddress1($data->{'billingInfo'}{'address'});
      $contact->setAddress2($data->{'billingInfo'}{'address2'});
      $contact->setCity($data->{'billingInfo'}{'city'});
      $contact->setState($data->{'billingInfo'}{'state'});
      $contact->setPostalCode($data->{'billingInfo'}{'postalCode'});
      $contact->setCountry($data->{'billingInfo'}{'country'});
      $contact->setEmailAddress($data->{'billingInfo'}{'email'});
      $contact->setPhone($data->{'billingInfo'}{'phone'});
    }
    $trans->setBillingInformation($contact);

    my $shipcontact = new PlugNPay::Contact();
    if (defined $data->{'shippingInfo'}) {
      $shipcontact->setFullName($data->{'shippingInfo'}{'name'});
      $shipcontact->setAddress1($data->{'shippingInfo'}{'address'});
      $shipcontact->setAddress2($data->{'shippingInfo'}{'address2'});
      $shipcontact->setCity($data->{'shippingInfo'}{'city'});
      $shipcontact->setState($data->{'shippingInfo'}{'state'});
      $shipcontact->setPostalCode($data->{'shippingInfo'}{'postalCode'});
      $shipcontact->setCountry($data->{'shippingInfo'}{'country'});
      $shipcontact->setEmailAddress($data->{'shippingInfo'}{'email'});
      $shipcontact->setPhone($data->{'shippingInfo'}{'phone'});
      $trans->setShippingNotes($data->{'shippingInfo'}{'notes'});
    }
    $trans->setShippingInformation($shipcontact);

    my $orderID = $data->{'orderID'} || $data->{'merchantOrderID'};
    if (defined $orderID) {
      $trans->setOrderID($orderID);
    }

    $trans->setGatewayAccount($merchant);
    $trans->setTime($time->inFormat('unix'));

    # set account codes, accountCode is preferred, TODO: update docs
    my $accountCodes = $data->{'accountCode'} || $data->{'accountCodes'} || {};
    $trans->setAccountCode(1,$accountCodes->{1} || '');
    $trans->setAccountCode(2,$accountCodes->{2} || '');
    $trans->setAccountCode(3,$accountCodes->{3} || '');

    $trans->setCurrency($data->{'currency'});
    $trans->setTransactionAmount($data->{'amount'});
    $trans->setTaxAmount($data->{'taxAmount'});

    my $adjustmentAmount = $data->{'surchargeAmount'} || $data->{'feeAmount'};
    $trans->setTransactionAmountAdjustment($adjustmentAmount);
    if ($data->{'surchargeAmount'} > 0) {
      $trans->adjustmentIsSurcharge();
    }

    my $adjustmentTaxAmount = $data->{'surchargeTaxAmount'} || $data->{'feeTaxAmount'};
    $trans->setBaseTaxAmount($data->{'taxAmount'} - $adjustmentTaxAmount);

    my $submittedPaymentData = 0;

    if ($data->{'purchaseOrderNumber'}) {
      $trans->setPurchaseOrderNumber($data->{'purchaseOrderNumber'});
    }

    if ($self->getContext() eq 'attendant') {
      my $customer = $self->getResourceData()->{'customer'};
      $trans->setAccountCode(4,$customer);
    }

    $trans->setCustomData($data->{'customData'});
    $trans->setPNPTransactionReferenceID($data->{'transactionRefID'}) if $data->{'transactionRefID'};
    if ($data->{'tds'}) {
      $trans->setXID($data->{'tds'}{'xid'});
      $trans->setECI($data->{'tds'}{'eci'});
      $trans->setCAVV($data->{'tds'}{'cavv'});
    }

    my $token = new PlugNPay::Token();

    if (($mode eq 'credit' || $mode =~ /^auth/) && $data->{'transactionRefID'}) {
      my $loaded;
      my $loader = new PlugNPay::Transaction::Loader({'loadPaymentData' => 1});
      eval {
        $loaded = $loader->load({'gatewayAccount' => $merchant, 'transactionID' => $data->{'transactionRefID'}})->{$merchant}{$data->{'transactionRefID'}};
      };

      #Some serious needful
      if (ref($loaded) =~ /^PlugNPay::Transaction::/ && !$@) {
        my $loadedPayment = $loaded->getPayment();
        $loadedPayment->fromToken($loaded->getPNPToken());
        if ($type eq 'ach') {
          $trans->setOnlineCheck($loadedPayment);
        } else {
          $trans->setCreditCard($loadedPayment);
        }
        $trans->setPNPToken($loaded->getPNPToken());
        $trans->setBillingInformation($loaded->getBillingInformation());
      } else {
        $self->log({'message' => 'failed to do ' . $mode . 'prev', 'error' => $@, 'mode' => 'POST', 'merchant' => $merchant, 'refID' => $data->{'transactionRefID'}});
        $errorList->{$transID}{'message'} = 'Transaction was not processed: bad reference ID for transaction';
        $errorList->{$transID}{'amount'} = $data->{'amount'};
        $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
        $errorList->{$transID}{'mode'} = $mode . 'prev';
      }
    } else {
      if ($type eq 'credit' || $type eq 'card' || $type eq 'gift') {
        #Verify Card Info
        my $month = $data->{'payment'}{'card'}{'expMonth'};
        my $year = $data->{'payment'}{'card'}{'expYear'};

        $month =~ s/^0+//g; #Clear off extra 0's from month (fixes 0012, 011, etc)
        if (length($month) < 2) {
          $month = '0' . $month; #If month is a single digit pad 1 zero to front
        }
        $year = substr($year,-2,2);  #Get last two digits of year
        my $cardNumber = $data->{'payment'}{'card'}{'number'};
        if (defined $data->{'payment'}{'card'}{'token'}) {
          if (!$cardNumber) {
            $cardNumber = $token->fromToken($data->{'payment'}{'card'}{'token'});
          }
          $trans->setPNPToken($data->{'payment'}{'card'}{'token'});
        }

        my $card = new PlugNPay::CreditCard();
        $card->setName($data->{'billingInfo'}{'name'});
        my $cardObjectIsValid = 0;
        my $cardObjectErrorMessage = '';
        if (defined $data->{'payment'}{'dukpt'}) {
          # for shorthand
          my $dukpt = $data->{'payment'}{'dukpt'};

          # dukpt fields
          my $ksn = $dukpt->{'ksn'};
          my $deviceSerial = $dukpt->{'deviceSerial'};
          my $track1 = $dukpt->{'track1'};
          my $track2 = $dukpt->{'track2'};
          my $track3 = $dukpt->{'track3'};

  
          my $decrypted = $card->fromDukpt({
            ksn => $ksn,
            deviceSerial => $deviceSerial,
            track1 => $track1,
            track2 => $track2,
            track3 => $track3
          });
          

          if (!$decrypted) {
            $errorList->{$transID}{'message'} = 'Failed to decrypt DUKPT data';
          } else {
            $cardObjectIsValid = 1;
          }
        } elsif ($data->{'payment'}{'card'}{'magstripe'}) {
          $card->setMagstripe($data->{'payment'}{'card'}{'magstripe'});
          $cardObjectIsValid = 1;
        } elsif ($data->{'payment'}{'card'}{'magensa'}) {
          my $decryptedData = $card->decryptMagensa($data->{'payment'}{'card'}{'magensa'});
          $card->setMagstripe($decryptedData->{'Track1'} . $decryptedData->{'Track2'});

          my $decryptedCardNumber = $decryptedData->{'card-number'};
          $card->setName($data->{'billingInfo'}{'name'});
          $card->setNumber($decryptedCardNumber);
          if ($decryptedData->{'error'}) {
            $errorList->{$transID}{'message'} = 'Magensa Decrypt Error: ' . $decryptedData->{'errorMessage'};
            $errorList->{$transID}{'amount'} = $data->{'amount'};
            $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
          } else {
            $cardObjectIsValid = 1;
          }
        } elsif ($data->{'payment'}{'card'}{'encryptedPGPData'}) {

          my $decryptionStatus = $card->decryptPGPData($data->{'payment'}{'card'}{'encryptedPGPData'});
          if (!$decryptionStatus) {
            $errorList->{$transID}{'message'} = $decryptionStatus->getError() . ': ' . $decryptionStatus->getErrorDetails();
            $errorList->{$transID}{'amount'} = $data->{'amount'};
            $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
          } else {
            $cardObjectIsValid = 1;
          }
        } elsif ($cardNumber) {
          $card->setNumber($cardNumber);
          $card->setExpirationMonth($month);
          $card->setExpirationYear($year);
          $card->setSecurityCode($data->{'payment'}{'card'}{'cvv'});
          if ($card->isExpired()) {
            $errorList->{$transID}{'message'} = 'Transaction was not processed: Card is expired';
            $errorList->{$transID}{'amount'} = $data->{'amount'};
            $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
          } elsif (!$card->verifyLuhn10()) {
            $errorList->{$transID}{'message'} = 'Transaction was not processed: Card number failed luhn10 check';
            $errorList->{$transID}{'amount'} = $data->{'amount'};
            $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
          } elsif (!$card->verifyLength()) {
            $errorList->{$transID}{'message'} = 'Transaction was not processed: Card number is not of valid length';
            $errorList->{$transID}{'amount'} = $data->{'amount'};
            $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
          } else {
            $cardObjectIsValid = 1;
          }
        }

        $submittedPaymentData = $cardObjectIsValid;

        if ($cardObjectIsValid) {
          $trans->setCreditCard($card);
        }
      } elsif ($type eq 'ach') {
        #Verify ACH Info
        my $routingNumber = $data->{'payment'}{'ach'}{'routingNumber'};
        my $accountNumber = $data->{'payment'}{'ach'}{'accountNumber'};

        if ($data->{'payment'}{'ach'}{'token'}) {
          $trans->setPNPToken($data->{'payment'}{'ach'}{'token'});
          if (!$routingNumber || !$accountNumber) {
            my @achInfo = split(' ',$token->fromToken($data->{'payment'}{'ach'}{'token'}));
            $routingNumber =  $achInfo[0];
            $accountNumber =  $achInfo[1];
          }
        }

        my $check = new PlugNPay::OnlineCheck();
        $check->setName($data->{'billingInfo'}{'name'});
        $check->setABARoutingNumber($routingNumber);
        $check->setAccountNumber($accountNumber);
        $check->setAccountType($data->{'payment'}{'ach'}{'accountType'});

        $submittedPaymentData = ($routingNumber && $accountNumber);

        my $secCode = $data->{'payment'}{'ach'}{'secCode'} || 'WEB';
        $trans->setSECCode($secCode);

        $trans->setOnlineCheck($check);
      }
    }

    if ($mode eq 'return') {
      my $refId = $data->{'transactionRefID'} || $data->{'orderID'};
      if (!defined $refId || $refId eq '') {
        $self->log({'message' => 'failed to do return, missing transactionRefID', 'mode' => 'POST', 'merchant' => $merchant});
        $errorList->{$transID}{'message'} = 'Transaction was not processed: missing transactionRefID';
        $errorList->{$transID}{'amount'} = $data->{'amount'};
        $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
      } else {
        $trans->setPNPTransactionReferenceID($refId);
      }
    }

    if ($mode eq 'forceauth') {
      if ($data->{'authorizationCode'}) {
        $trans->setAuthorizationCode($data->{'authorizationCode'});
      } else {
        $self->log({'message' => 'failed to do forceauth, missing authorizationCode', 'mode' => 'POST', 'merchant' => $merchant});
        $errorList->{$transID}{'message'} = 'Transaction was not processed: missing authorizationCode';
        $errorList->{$transID}{'amount'} = $data->{'amount'};
        $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
      }
    }

    foreach my $flag (@{$data->{'flags'}}) {
      if ($flag eq 'authpostauth' || $flag eq 'postauth') {
        $trans->setPostAuth();
      } else {
        $trans->addTransFlag($flag);
      }
    }

    my $shouldRunSync = ($data->{'processMode'} eq 'sync' || $runSync ? 1 : 0);
    if ($shouldRunSync) {
      $trans->setToSynchronous();
    } else {
      $trans->setToAsynchronous();
      # If they send async but it's a perl processor, THEN WE MUST FAIL!
      my $currentProcessor = new PlugNPay::Processor();
      unless ($currentProcessor->usesUnifiedProcessing($trans->getProcessor(), $trans->getTransactionPaymentType())) {
        $self->log({'message' => 'failed to perform transaction', 'error' => 'processor only supports synchronous processing', 'mode' => 'POST', 'merchant' => $merchant, 'processor' => $trans->getProcessor()});
        $errorList->{$transID}{'message'} = 'Attempted to run synchronous processor asynchronously, please set processMode as sync and run again';
        $errorList->{$transID}{'amount'} = $data->{'amount'};
        $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
        $errorList->{$transID}{'processor'} = $trans->getProcessor();
      }
    }

    my $securityHash = $data->{'security'} || {};
    my $ipAddressCheck = new PlugNPay::Util::IP::Address();

    $trans->setInitialOrderID($data->{'initialOrderID'});
    if ($self->getAuthenticationType() eq 'apiKey') {
      if (defined $securityHash->{'ipAddress'} && $ipAddressCheck->getIPVersion($securityHash->{'ipAddress'}) eq '4') {
        $trans->setIPAddress($securityHash->{'ipAddress'});
      }
    } elsif ($self->getAuthenticationType() eq 'session' || !$self->getAuthenticationType()) {
      my $env = new PlugNPay::Environment();
      $trans->setIPAddress($env->get('PNP_CLIENT_IP'));
    }

    $transactionList->{$transID} = $trans;
  }

  my @transactionsToLoad;
  my $processedTransactions = {};
  my $converter = new PlugNPay::Transaction::JSON();
  my $stateMachine = new PlugNPay::Transaction::State();
  foreach my $id (keys %{$transactionList}) {
    $originalStates->{$id} = $transactionList->{$id}->clone();
    if (!defined $errorList->{$id}) {
      eval {
        my $tran = $transactionList->{$id};
        my ($response,$error) = $transactionProcessor->process($tran);
        my $hex = PlugNPay::Util::UniqueID::fromBinaryToHex($tran->getPNPTransactionID());
        my $gatewayAccount = $tran->getGatewayAccount();
        my $loadData = { gatewayAccount => "$gatewayAccount", transactionID => $hex};
        if ($response) {
          $tran->setResponse($response);
          my $originalTrans = $response->getTransaction();
          $processedTransactions->{PlugNPay::Util::UniqueID::fromBinaryToHex($originalTrans->getPNPTransactionID())} = $id;
        }

        push @transactionsToLoad, $loadData;

        if ($error) {
            $errorList->{$id}{'message'} = $error;
            $errorList->{$id}{'status'} = 'error';
        } else {
          if (!defined $response->getStatus()) {
            $errorList->{$id}{'message'} = 'An unknown error occurred during processing';
            $errorList->{$id}{'status'} = 'error';
          } elsif ($response->getStatus() !~ /^(success|pending)$/i) {
            $errorList->{$id}{'message'} = $response->getMessage();
            $errorList->{$id}{'status'} = lc($response->getStatus());
            if ($response->getStatus() eq 'fraud') {
              $errorList->{$id}{'fraudLogId'} = $response->getFraudLogId();
            }
          }
        }
      };
      if ($@) {
        $self->log({
          message => 'error while processing transaction',
          transactionInputId => $id,
          transactionAccount => $transactionList->{$id}->getGatewayAccount(),
          apiAccount => $self->getGatewayAccount(),
          error => $@
        });
      }
    }
  }

  my $loadedTransactions = $self->_loadTransactions(\@transactionsToLoad, 1, 1);
  my $transactionResults = $self->formatTransactionResults({
            transactionList => $transactionList,
            originalStates => $originalStates,
            identifierMap => $processedTransactions,
            reloadedData => $loadedTransactions,
            options => {
              'shrink' => $shrinkResponse,
              'v1:method:POST' => 1,
              'v1:suppressAdditionalMerchantData' => 1,
              'v1:suppressAdditionalProcessorData' => 1
            }
  });

  my $output = {
                 'transactions' => $transactionResults,
                 'errors' => $errorList
               };
  return $output;
}

sub containsCardPaymentInfo {
  my $self = shift;
  my $data = shift;
  my $contains = 0;
  my @types = ('token','number','magstripe','magensa','encryptedPGPData');
  foreach  my $type (@types) {
    $contains ||= defined $data->{'payment'}{'card'}{$type};
  }

  $contains ||= defined $data->{'payment'}{'type'} && $data->{'payment'}{'type'} eq 'card' && defined $data->{'payment'}{'dukpt'};

  return $contains;
}

####################
# Update Functions #
####################
# Mark for Settlement
sub _update {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $data = $self->getInputData();

  my $response = {'transactions' => {}, 'errors' => {}};
  my $batchMode = defined $data->{'transactions'} && (ref($data->{'transactions'}) eq 'ARRAY' || ref($data->{'transactions'} eq 'HASH'));
  my $transactionMode = defined $data->{'transaction'};

  my $batchResponse;
  my $response = {};
  if ($batchMode || $transactionMode) {
    if ($transactionMode) {
      $data->{'transactions'} ||= [];
      push @{$data->{'transactions'}},$data->{'transaction'};
      $batchMode = 1;
    }
    if ($batchMode) {
      my $transactionsBatch = [];
      if (ref($data->{'transactions'}) eq 'ARRAY') {
        $transactionsBatch = $data->{'transactions'};
      } elsif (ref($data->{'transactions'}) eq 'HASH') {
        my @tb = values(@{$data->{'transactions'}});
        $transactionsBatch = \@tb;
      }
      $batchResponse = $self->_markBatch($merchant,$transactionsBatch);

      # create array for Loader
      my @transactionsToLoad = grep { !$batchResponse->{$_}{'error'} && !inArray($batchResponse->{$_}{'status'},['success','pending']) } keys %{$batchResponse};
      my @transactionsToLoad = map { { gatewayAccount => $merchant, transactionID => $_ } } @transactionsToLoad;

      my $loadedTransactions = $self->_loadTransactions(\@transactionsToLoad, 1, 1);
      my $transactionProcessor = new PlugNPay::Transaction::TransactionProcessor();
      my $formatter = new PlugNPay::Transaction::Formatter();

      my %transactionResults;
      my %identifierMap;
      foreach my $merchantTranList (values %{$loadedTransactions}) {
        foreach my $transId (keys %{$merchantTranList}) {
          $identifierMap{$transId} = $transId;
        }
      }

      my %transactionList = map { $_ => $batchResponse->{$_}{'result'}->getTransaction() } keys %{$batchResponse};

      my $formattedResults = {};

      $formattedResults = $self->formatTransactionResults({
                transactionList => \%transactionList,
                identifierMap => \%identifierMap,
                reloadedData => $loadedTransactions,
                options => {
                  'v1:suppressAdditionalProcessorData' => 1
                }
      });

      $response->{'transactions'} = $formattedResults;

      # create an array of transactions with errors
      my @errorTransactions  = grep { $batchResponse->{$_}{'error'} } keys %{$batchResponse};
      my $errorInfo = {};
      foreach my $errorTransactionId (@errorTransactions) {
        next if inArray($batchResponse->{$errorTransactionId}{'status'},['success','pending']);
        $errorInfo->{$errorTransactionId} = {
          logId => $batchResponse->{$errorTransactionId}{'errorLogId'},
          errorMessage => $batchResponse->{$errorTransactionId}{'error'}
        };
      }
      my @errors = map { $batchResponse->{$_} } @errorTransactions;
      my $errors = {};
      if (@errorTransactions > 0) {
        $errors = {
          status => 'some transactions failed to mark',
          error => 'multiple.  provide log id to support if available',
          errorLogIds => $errorInfo
        };
      }
      $response->{'errors'} = $errors;

      $self->setResponseCode(200);
      return $response;
    }
  } else {
    # error, bad input, nothing to do.
    $self->setResponseCode(400);
    $self->setError('Nothing to do.');
    return {};
  }
}

sub _markBatch {
  my $self = shift;
  my $gatewayAccount = shift;
  my $transactionsData = shift;

  my %results;
  foreach my $transactionData (@{$transactionsData}) {
    my $markResponse = $self->_markTransaction($gatewayAccount,$transactionData);
    my $transactionId = $markResponse->{'transactionId'};
    my $error = $markResponse->{'errorMessage'} if !inArray($markResponse->{'status'},['success','pending']);

    $results{$transactionId} = {
      error => $error,
      result => $markResponse->{'result'}
    };
  }
  return \%results;
}

sub _markTransaction {
  my $self = shift;
  my $gatewayAccount = shift;
  my $transactionData = shift;

  if (ref($transactionData) ne 'HASH') {
    $transactionData = { transactionId => $transactionData };
  }

  # any variation of the id
  my $transactionId = $transactionData->{'transactionId'}    || $transactionData->{'transactionID'} ||
                      $transactionData->{'pnpTransactionId'} || $transactionData->{'pnpTransactionID'};
  my $result;
  my $error;

  my $loader = new PlugNPay::Transaction::Loader({'loadPaymentData' => 1});
  my $loaded = $loader->load({'transactionID' => $transactionId, 'gatewayAccount' => $gatewayAccount});
  my $transaction = $loaded->{$gatewayAccount}{$transactionId};

  if ($transaction) {
    my $amount = $transactionData->{'settlementAmount'};
    if (defined $amount) {
      $transaction->setTransactionAmount($amount);
    }
    $transaction->setTransactionType('postauth');
    $transaction->setTransactionMode('postauth');

    my $tp = new PlugNPay::Transaction::TransactionProcessor();
    ($result,$error) = $tp->process($transaction);
    next if $error;
    my $resultTransaction = $result->getTransaction();
    my $resultTransactionId = $resultTransaction->getPNPTransactionID(); # just in case something got screwy and the transaction id changed..
    $resultTransactionId = PlugNPay::Util::UniqueID::fromBinaryToHex($resultTransactionId);
    $error = $result->getErrorMessage();
    if (!$error && $resultTransactionId ne $transactionId) {
      $error = 'unexpected change in transaction id: ' . $resultTransactionId . ' vs ' . $transactionId . ' vs ' . PlugNPay::Util::UniqueID::fromBinaryToHex($transaction->getPNPTransactionID());
      $transactionId = $resultTransactionId;
    }
  } else {
    $error = "Transaction does not exist";
  }

  # set error to true if error is undefined and result is undefined.
  my $errorStatus = ($error || (!$error && !defined $result)) ? 1 : 0;
  my $logId;
  if ($errorStatus) {
    (undef,$logId) = $self->log({
      message => 'mark of transaction failed',
      gatewayAccount => $gatewayAccount,
      transactionId => $transactionId,
      error => $error || $@ | 'Unknown error'
    });
  }

  return { transactionId => $transactionId, result => $result, error => $errorStatus, errorMessage => $error, errorLogId => $logId };
}

####################
# Delete Functions #
####################
# For Voids
sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $orderId = $self->getResourceData()->{'transaction'};
  my $res = $self->voidSingleTransaction($merchant,$orderId);
  return $res;
}

sub voidSingleTransaction {
  my $self = shift;
  my $merchant = shift;
  my $orderId = shift ;

  my $featuresAccountUsername = $self->getGatewayAccount();
  my $featuresAccount = new PlugNPay::GatewayAccount($featuresAccountUsername);
  my $features = $featuresAccount->getFeatures();

  my $shrinkResponse = $features->get('rest_api_shrink_response');

  my $response = { 'transactions' => {}, 'errors' => {}};
  my $converter = new PlugNPay::Transaction::JSON();

  if (!defined $orderId || $orderId eq '' || !defined $merchant) {
    $self->setResponseCode(404);
    $self->setError('no transaction id or username sent');
    my $responseID = $orderId || $merchant || 't1';
    $response->{'errors'} = { $responseID => {'status' => 'failure', 'message' => 'bad request data', 'username' => $merchant, 'orderID' => $orderId}};
  }

  my $loader = new PlugNPay::Transaction::Loader({'loadPaymentData' => 1});
  $response = {};
  my $transaction;
  my $transactionList = {};
  my $originalStates = {};

  eval {
    my $query = {'transactionID' => $orderId, 'gatewayAccount' => $merchant};
    my $transactions = $loader->load($query);

    $transaction = $transactions->{$merchant}{$orderId};
    if (defined $transaction) {
      $transactionList->{$orderId} = $transaction;
      $originalStates->{$orderId} = $transaction->clone();
      my $voidResponse = $self->_void($transaction);
      my $processedTransactions = {$orderId => $orderId}; # required for reformat functionality
      if ($voidResponse->getStatus() ne 'success') {
        $response->{'errors'}{$orderId} = {
          'status' => $voidResponse->getStatus(),
          'message' => $voidResponse->getMessage(),
          'orderID' => $transaction->getPNPOrderID()
        };
      }
      $transaction->setResponse($voidResponse);

      my $loadedTransactions = $self->_loadTransactions([{ 'gatewayAccount' => $merchant, 'transactionID' => $orderId }]);
      my $transactionResults = $self->formatTransactionResults({
        transactionList => $transactionList,
        originalStates => $originalStates,
        identifierMap => $processedTransactions,
        reloadedData => $loadedTransactions,
        options => {
          'shrink' => $shrinkResponse,
          'v1:method:DELETE' => 1,
          'v1:suppressAdditionalProcessorData' => 1,
          'v1:void' => 1
        }
      });

      $response->{'transactions'} = $transactionResults;
      $self->setResponseCode(200);
    }
  };

  my $primaryError = $@;
  if (defined $transaction && !$primaryError) {
    eval { 
      my $adjustmentLogger = new PlugNPay::Transaction::Logging::Adjustment();
      $adjustmentLogger->setGatewayAccount($transaction->getGatewayAccount());
      $adjustmentLogger->setOrderID($transaction->getOrderID());
      $adjustmentLogger->load();

      if(defined $adjustmentLogger->getAdjustmentOrderID() && $adjustmentLogger->getAdjustmentOrderID() ne '' && !$primaryError) {
        my $adjustmentID = $adjustmentLogger->getAdjustmentOrderID();
        my $adjustmentAccount = $adjustmentLogger->getAdjustmentGatewayAccount() || $merchant;
        my $adjustmentTransaction = $loader->load({'transactionID' => $adjustmentID, 'gatewayAccount' => $adjustmentAccount})->{$adjustmentAccount}{$adjustmentID};
        my $voidedAdjustmentTransactionResult = $self->_void($adjustmentTransaction);
        my $responseID = $adjustmentID;
        if ($responseID eq $orderId) {
          $responseID = 'adj-' . $responseID;
        }

        if ($voidedAdjustmentTransactionResult->getStatus() ne 'success') {
          $response->{'errors'}{$responseID} = {
            'status' => $voidedAdjustmentTransactionResult->getStatus(),
            'message' => $voidedAdjustmentTransactionResult->getMessage(),
            'orderID' => $voidedAdjustmentTransactionResult->getTransaction()->getOrderID()
          };
        } else {
          my $adjustmentResponse = $converter->transactionToJSON($voidedAdjustmentTransactionResult->getTransaction());
          $adjustmentResponse->{'status'} = $voidedAdjustmentTransactionResult->getStatus();
          $adjustmentResponse->{'message'} = $voidedAdjustmentTransactionResult->getMessage();

          $response->{'transactions'}{$responseID} = $adjustmentResponse;
        }
      }
    };
    if ($@) {
      $response->{'warnings'}{$orderId} = {
          'message' => 'An error occured while voiding adjustment transaction',
          'status' => 'failure'
      };
      $self->log({
        'user'=>$self->getGatewayAccount(),
        'error'=>$@,
        'message' => 'failed to void adjustment transaction!',
        'merchant' => $merchant,
        'pnpOrderId' => $orderId
      });
    }
  } elsif (!defined $transaction) {
    $self->setResponseCode(404);
    $response->{'errors'}{$orderId} = {
      'message' => 'Transaction does not exist',
      'status' => 'failure'
    };
  } else {
    $self->setResponseCode(520);
    $self->setError('An error occured while voiding');
    $self->log({'responder'=>'transaction','action'=>'delete','user'=>$self->getGatewayAccount(),'error'=>$primaryError});
    $response->{'errors'}{$orderId} = {
      'message' => 'An error occurred while voiding transaction',
      'status' => 'failure'
    };
  }

  return $response;
}

sub _void {
  my $self = shift;
  my $transaction = shift;
  $transaction->void();

  my $transactionProcessor = new PlugNPay::Transaction::TransactionProcessor();
  my $voidResponse = $transactionProcessor->process($transaction);

  return $voidResponse;
}


##################
# Read Functions #
##################
# Request Transaction Information
sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $orderID = $self->getResourceData()->{'order'};
  my $transID = $self->getResourceData()->{'transaction'};
  my $response = { 'transactions' => {}, 'errors' => {}};
  my $util = new PlugNPay::Transaction::JSON();
  my $options = $self->getResourceOptions();
  my $isBatching = lc($options->{'is_batching'}) eq 'true';

  my $loaded;
  my $transactions;
  my %processedTransactions;
  my %loadData = %{$options};
  $loadData{'gatewayAccount'} = $merchant if defined $merchant;
  $loadData{'orderID'} = $orderID if defined $orderID;
  $loadData{'transactionID'} = $transID if defined $transID;

  if (defined $orderID && defined $merchant) {
    eval {
      $loaded = $self->_loadTransactions([\%loadData], 1, 1);
    };

    if ($@) {
      $self->setResponseCode(520);
      $self->log({'responder'=>'transaction','action'=>'read', 'user' =>$self->getGatewayAccount(),'error'=>$@});
      return {'error' => 'An unknown error occurred during load'};
    } else {
      $transactions = $self->_flattenMerchantTransactionHash($loaded);
      %processedTransactions = map { $_ => $_ } keys %{$transactions};
    }
  } elsif (defined $merchant && defined $transID) {
    eval {
      $loaded = $self->_loadTransactions([\%loadData], 1, 1); # Don't need payment data or adj trans
    };

    if ($@) {
      $self->setResponseCode(520);
      $self->log({'responder'=>'transaction','action'=>'read', 'user' =>$self->getGatewayAccount(),'error'=>$@});
      return {'error' => 'An unknown error occurred during load'};
    }

    if (keys %{$loaded} > 0) {
      $transactions = $self->_flattenMerchantTransactionHash($loaded);
      %processedTransactions = map { $_ => $_ } keys %{$transactions};
    } else {
      $self->setResponseCode(404);
      $response->{'errors'} = {$transID => {'message' => 'transaction not found', 'status' => 'failure'}};
    }
  } elsif (defined $merchant && $isBatching) {
    #load postauth transactions
    my $ga = new PlugNPay::GatewayAccount($merchant);
    my $cardProcessor = $ga->getCardProcessor();
    my $stateMachine = new PlugNPay::Transaction::State();
    $self->setResponseCode(200);

    $loadData{'processor'} = $cardProcessor;
    $loadData{'transaction_state_id'} = $stateMachine->getStates()->{'AUTH'};

    eval {
      $loaded = $self->_loadTransactions([\%loadData], 1, 1); #Don't need payment data or adj trans
    };

    if ($@) {
      $self->setResponseCode(520);
      $self->log({'responder'=>'transaction','action'=>'read', 'user' =>$self->getGatewayAccount(),'error'=>$@});
      return {'error' => 'An unknown error occurred during load'};
    }

    my $checkForJobs = [];
    my $uuid = new PlugNPay::Util::UniqueID();
    foreach my $merchant (keys %{$loaded}) {
      foreach my $transID (keys %{$loaded->{$merchant}}) {
        push @{$checkForJobs},$transID;
      }
    }

    my $transactionLoader = new PlugNPay::Transaction::Loader({'loadPaymentData' => 1});
    my $jobs = $transactionLoader->getTransactionSettlementJobs($checkForJobs);
    foreach my $merchant (keys %{$loaded}) {
      foreach my $transID (keys %{$loaded->{$merchant}}) {
        my $trans = $loaded->{$merchant}{$transID};
        my $canBatch = (!defined $jobs->{$transID}) && ($trans->getTransactionState() =~ /^AUTH/i) && ($trans->getTransactionAmount() > 0);
        if ($isBatching && !$canBatch) {
          delete $loaded->{$merchant}{$transID};
        }
      }
    }

    $transactions = $self->_flattenMerchantTransactionHash($loaded);
    %processedTransactions = map { $_ => $_ } keys %{$transactions};
  } else {
    eval {
      $loaded = $self->_loadTransactions([\%loadData], 1, 1); #Don't need payment data or adj trans
    };

    if ($@) {
      $self->setResponseCode(520);
      $self->log({'responder'=>'transaction','action'=>'read', 'user' =>$self->getGatewayAccount(),'error'=>$@});
      return {'error' => 'An unknown error occurred during load'};
    }

    $transactions = $self->_flattenMerchantTransactionHash($loaded);
    %processedTransactions = map { $_ => $_ } keys %{$transactions};
  }

  if (defined $transactions && defined $loaded) {
    my $transactionResults = $self->formatTransactionResults({
      transactionList => $transactions,
      identifierMap => \%processedTransactions,
      reloadedData => $loaded,
      options => {
        'v1:suppressAdditionalProcessorData' => 1
      }
    });
    $response->{'transactions'} = $transactionResults;
    $self->setResponseCode(200);
  }

  if (keys(%{$response->{'transactions'}}) == 0 && keys(%{$response->{'errors'}}) == 0) {
    $self->setResponseCode(404);
  }

  return $response;
}

sub _merchantTransactionHashToTransactionHash {
  my $self = shift;
  my $merchantTransactionHash = shift;
  my %transactionHash;
  my $tranJson = new PlugNPay::Transaction::JSON();
  foreach my $merchant (keys %{$merchantTransactionHash}) {
    foreach my $transaction (keys %{$merchantTransactionHash->{$merchant}}) {
      my $j = $tranJson->transactionToJSON($merchantTransactionHash->{$merchant}{$transaction});
      $j->{'status'} = $j->{'finalStatus'};
      $transactionHash{$transaction} = $j;
    }
  }

  return \%transactionHash;
}

sub _flattenMerchantTransactionHash {
  my $self = shift;
  my $merchantTransactionHash = shift;
  my %transactionHash;
  foreach my $merchant (keys %{$merchantTransactionHash}) {
    foreach my $transaction (keys %{$merchantTransactionHash->{$merchant}}) {
      $transactionHash{$transaction} = $merchantTransactionHash->{$merchant}{$transaction};
    }
  }

  return \%transactionHash;
}

# Load Functions #
sub _loadTransactions {
  my $self = shift;
  my $dataArray = shift;
  my $shouldLoadPaymentData = shift;
  my $shouldLoadAdjustment = shift;
  my $loader = new PlugNPay::Transaction::Loader({'loadPaymentData' => (!defined $shouldLoadPaymentData ? 1 : $shouldLoadPaymentData)});
  my $transactions = {};
  my $adjustmentLogger = new PlugNPay::Transaction::Logging::Adjustment();
  my $util = new PlugNPay::Transaction::JSON();
  my $responses = {};

  eval{
    # $dataArray is an array of hashes in the format { gatewayAccount => 'x', transactionID => 'y' }
    $transactions = $loader->load($dataArray);
  };

  if ($@) {
    $self->setResponseCode(520);
    $self->setError('An internal error occurred: while loading transactions.');
    $self->log({'responder'=>'transaction','function' => 'load', 'user' => $self->getGatewayAccount(),'error'=>$@});
    return {};
  }

  my $tokenObj = new PlugNPay::Token();

  # Duplicate hex vals (pnpToken, pnpTransID) are for compatibility! #
  foreach my $merchant (keys %{$transactions}) {
    foreach my $transID (keys %{$transactions->{$merchant}}) {
      my $t = $transactions->{$merchant}{$transID};
      my $transTime = new PlugNPay::Sys::Time();
      $transTime->fromFormat('db_gm',$t->getTransactionDateTime());
      my $timeCheck = new PlugNPay::Sys::Time();
      $timeCheck->subtractMinutes(1);

      if ($t->getResponse()->getStatus() eq 'pending' && $transTime->isAfter($timeCheck)) {
        # attempt to load result from processor,
        # then reload the result from the database
        $self->requestPending($transID);
        my $reloaded = $loader->load([{
          gatewayAccount => $merchant,
          transactionID => $transID
        }]);
        $transactions->{$merchant}{$transID} = $reloaded->{$merchant}{$transID};
      }
    }
  }

  return $transactions;
}

sub formatTransactionResults {
  my $self = shift;
  my $input = shift;
  my $transactionList = $input->{'transactionList'};
  my $originalStates = $input->{'originalStates'};
  my $identifierMap = $input->{'identifierMap'};
  my $reloadedData = $input->{'reloadedData'};
  my $options = $input->{'options'} || {};
  my $featuresAccountUsername = $self->getGatewayAccount();
  my $featuresAccount = new PlugNPay::GatewayAccount($featuresAccountUsername);
  my $features = $featuresAccount->getFeatures();
  my $resourceOptions = $self->getResourceOptions();

  # if format is sent, default to current format.
  my $format;
  if (exists $resourceOptions->{'format'}) {
    $format = $resourceOptions->{'format'} || 'current';
  }

  my %transactionResults;

  foreach my $merchantTranList (values %{$reloadedData}) {
    foreach my $transId (keys %{$merchantTranList}) {
      my $resultId = $identifierMap->{$transId};
      my $jsonFormatter = new PlugNPay::Transaction::JSON();
      my $transaction = $merchantTranList->{$transId};

      if (!$transaction->getPurchaseOrderNumber() && defined $transactionList->{$resultId}->getPurchaseOrderNumber()) {
        my $purchaseOrderNumber = $transactionList->{$resultId}->getPurchaseOrderNumber();
        $transaction->setPurchaseOrderNumber($purchaseOrderNumber);
      }
      my $responseFormattedTran = $jsonFormatter->transactionToJSON($transaction);
      my $transaction = $transactionList->{$identifierMap->{$transId}};
      my $originalTransaction = $originalStates->{$identifierMap->{$transId}};
      # the following to be re-added in the future so it stays here
      # if ($features->get('rest_api_transaction_version') ne '') {
      #   $self->setWarning('An older response format is currently enabled for this account.  Please contact support for more information.');
      # }
      if ($format || $features->get('rest_api_transaction_version') ne '') {
        my $reformatter = new PlugNPay::Transaction::JSON::Versioned();
        $responseFormattedTran = $reformatter->reformat({
          version => $format || $features->get('rest_api_transaction_version'),
          formatted => $responseFormattedTran,
          transaction => $transaction,
          originalTransaction => $originalTransaction,
          options => $options
        });
      }

      $transactionResults{$resultId} = $responseFormattedTran;
    }
  }

  return \%transactionResults;
}

sub requestPending {
  my $self = shift;
  my $transactionID = shift;

  my $response;
  my @responseArray;
  eval {
    my $process = new PlugNPay::Processor::Process();
    my $data = $process->getProcessedTransactions($transactionID);
    foreach my $key (keys %{$data}) {
      if (ref($data->{$key}) eq 'ARRAY') {
        push @responseArray,@{$data->{$key}};
      } else {
        push @responseArray,$data->{$key};
      }
    }
  };
  return $response;
}

1;
