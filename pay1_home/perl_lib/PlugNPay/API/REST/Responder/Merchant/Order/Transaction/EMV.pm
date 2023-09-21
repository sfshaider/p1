package PlugNPay::API::REST::Responder::Merchant::Order::Transaction::EMV;

use strict;

use PlugNPay::Order;
use PlugNPay::Contact;
use PlugNPay::Transaction;
use PlugNPay::Util::UniqueID;
use PlugNPay::Transaction::State;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::Updater;
use PlugNPay::Processor::SemiIntegrated;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::GatewayAccount::LinkedAccounts;
use base 'PlugNPay::API::REST::Responder';

 ###################
 # Get Output Data #
 ###################

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  my $resourceData = $self->getResourceData();
  my $transID = $resourceData->{'transaction'};
  my $response = {};

  if ($action eq 'create') {
    $response = $self->_create();
  } elsif ($action eq 'read') {
    if ($transID eq '') {
      $response = $self->_read_all();
    } else {
      $response = $self->_read();
    }
  } elsif ($action eq 'update') {
    $response = $self->_update();
  } elsif ($action eq 'delete') {
    $response = $self->_delete();
  } else {
    $self->setResponseCode(501);
    $response = {};
  }

  return $response;
}

 ##########
 # Create #
 ##########

sub _create {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $merchant = $resourceData->{'merchant'};  # url data

  if (!$merchant) {
    $merchant = $self->getGatewayAccount();
  } else {
    if ($merchant ne $self->getGatewayAccount()) {
      my $linked = new PlugNPay::GatewayAccount::LinkedAccounts($merchant)->isLinkedTo($self->getGatewayAccount());
      if (!$linked) {
        $self->setResponseCode(403);
        return {'status' => 'ERROR', 'message' => 'Access Denied. Invalid merchant account.'};
      }
    }
  }

  my $inputData = $self->getInputData();

  # optional
  my $transactionData = $inputData->{'transactionData'};
  my $billing = $inputData->{'billingInfo'};
  my $orderID = $inputData->{'orderID'};

  # REQUIRED to make transaction
  my $totalAmount = $inputData->{'amountCharged'} || $inputData->{'amount'};
  my $feeAmount = ($inputData->{'feeAmount'} =~ m/^\d+.\d{2}$/ ? $inputData->{'feeAmount'} : 0.00);
  my $baseAmount = $totalAmount - $feeAmount;

  my $totalTax = ($inputData->{'taxCharged'} =~ m/^\d+.\d{2}$/ ? $inputData->{'taxCharged'} : 0.00);
  my $feeTax = ($inputData->{'feeTax'} =~ m/^\d+.\d{2}$/ ? $inputData->{'feeTax'} : 0.00);
  my $baseTax = $totalTax - $feeTax;
  $baseAmount -= $totalTax;

  my $state = $inputData->{'operation'};

  # get MerchantID
  my $internalID = new PlugNPay::GatewayAccount::InternalID();
  my $merchantID = $internalID->getMerchantID($merchant);

  # validate currency USD
  my $validAmount = ($totalAmount =~ m/^-?\d+.\d{2}$/);

  if(!$validAmount) {
    $self->setResponseCode(422);
    return {'status' => 'ERROR', 'message' => 'Invalid Amount'};
  }

  # Contact Data
  my $contact = new PlugNPay::Contact();

  if(ref $billing eq 'HASH' && %{$billing}) {
    $contact->setFullName($billing->{'name'});
    $contact->setCompany($billing->{'company'});
    $contact->setAddress1($billing->{'address'});
    $contact->setAddress2($billing->{'address2'});
    $contact->setCity($billing->{'city'});
    $contact->setState($billing->{'state'});
    $contact->setPostalCode($billing->{'postalCode'});
    $contact->setCountry($billing->{'country'});
    $contact->setEmailAddress($billing->{'email'});
    $contact->setPhone($billing->{'phone'});
    $contact->setFax($billing->{'fax'});
  }

  # get StateID
  my $transactionState = new PlugNPay::Transaction::State();
  my $stateID = $transactionState->getStates()->{$state};
  my $type =  "emv";

  my $trans = new PlugNPay::Transaction($state, $type);

  my $finalizeFlag = ref $transactionData eq 'HASH' && %{$transactionData};
  my $accountCodes = $finalizeFlag ? $transactionData->{'account_code'} : '';
  # Set Transaction Data
  if (ref $accountCodes eq 'HASH' && %{$accountCodes}) {
    foreach my $code (keys %$accountCodes) {
      $trans->setAccountCode($code, $accountCodes->{$code});
    }
  }

  $trans->setBillingInformation($contact);
  $trans->setTransactionState($stateID);
  $trans->setBaseTransactionAmount($baseAmount);
  $trans->setTransactionAmount($totalAmount);
  $trans->setTransactionAmountAdjustment($feeAmount);
  $trans->setGatewayAccount($merchant);
  $trans->setTransactionType($state);
  $trans->setBaseTaxAmount($baseTax);
  $trans->setTaxAmount($totalTax);

  if ($state eq 'return' && $inputData->{'transactionRefID'}) {
    $trans->setPNPTransactionReferenceID($inputData->{'transactionRefID'});
  }

  # Create Order
  my $order = new PlugNPay::Order();

  if($orderID ne '') {
    $trans->setOrderID($orderID);
    $order->setMerchantOrderID($orderID);
  }

  $order->addOrderTransaction($trans);
  $order->setMerchantID($merchantID);

  # Save Order
  my $results = $order->save($state);
  my $response = {};

  if ($results) {
    # success
    my $binID = $trans->getPNPTransactionID();
    my $uuid = new PlugNPay::Util::UniqueID();
    my $transID = $uuid->fromBinary($binID);
    # if any additional, call update
    if($finalizeFlag) {
      my $finalize = $self->_finalize($transactionData, $transID);
      if($finalize) {
        $self->setResponseCode(201);
        $response = {'status' => 'SUCCESS', 'message' => 'Created and updated transaction', 'transaction_id' => $transID};
      } else {
        $self->setResponseCode(520);
        $response = {'status' => 'ERROR', 'message' => 'Created but unable to update transaction', 'transaction_id' => $transID};
      }
    } else {
      $self->setResponseCode(201);
      $response = {'status' => 'SUCCESS', 'message' => 'Created Transaction', 'transaction_id' => $transID};
    }
  } else {
    # fail
    $self->setResponseCode(400);
    $response = {'status' => 'FAILURE', 'message' => 'Unable to create transaction'};
  }

  return $response;
}

sub _finalize {
  my $self = shift;
  my $options = shift;
  my $transID = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();


  my $loadedTransaction = $self->_loadTransactions($merchant,$transID);
  my $processor = $loadedTransaction->{$merchant}{$transID}{'processor'};
  my $state = $loadedTransaction->{$merchant}{$transID}{'transaction_state'};

  if ($state !~ /_PENDING$/) {
    return 0; 
  }

  my $pnpProcessor = new PlugNPay::Processor::SemiIntegrated();

  if ($processor eq 'plugnpay') {
    if ($pnpProcessor->doesTransactionExist($transID)) {
      $pnpProcessor->removePendingTransaction($transID);
    }
  }

  my $updater = new PlugNPay::Transaction::Updater();
  my $errors = $updater->finalizeTransactions({
    $transID => {
      'pnp_transaction_id'           => $transID,
      'wasSuccess'                   => $options->{'wasSuccess'},
      'processor_token'              => $options->{'processorToken'},
      'pnp_transaction_ref_id'       => $options->{'transactionRefID'},
      'processor_reference_id'       => $options->{'processorReferenceID'},
      'authorization_code'           => $options->{'authorizationCode'},
      'cvv_response'                 => $options->{'cvvResponse'},
      'avs_response'                 => $options->{'avsResponse'},
      'additional_processor_details' => $options->{'additionalProcessorDetails'}
    }
  });

  return !(exists $errors->{$transID} && $errors->{$transID} == 1);
}

 #######################################################
 # Read - Returns one transaction using transaction id #
 #######################################################

sub _read {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $transID = $resourceData->{'transaction'};
  my $gatewayAccount = $resourceData->{'merchant'};

  if(defined $transID && defined $gatewayAccount) {
    my $response = {};
    eval {
      $response = $self->_loadTransactions($gatewayAccount, $transID);
    };
    if($@) {
      $self->setResponseCode(520);
      $response = {'status' => 'FAILURE', 'message' => 'An unknown error has occured' };
    }
    $self->setResponseCode(200);
    return {'status' => 'SUCCESS', 'message' => 'Loaded Transactions','transactions' => $response };
  } else {
    return {'status' => 'FAILURE', 'message' => 'Merchant and Transaction ID not set'};
  }
}
 ################################################3###########
 # Read All - Returns all transactions under given merchant #
 ############################################################

sub _read_all {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $gatewayAccount = $resourceData->{'merchant'};

  if(defined $gatewayAccount) {
    my $response;

    eval {
      $response = $self->_loadTransactions($gatewayAccount);
    };
    if($@) {
      $self->setResponseCode(520);
      $response = {'status' => 'FAILURE', 'message' => 'An unknown error has occurred'};
    }

    $self->setResponseCode(200);
    return {'status' => 'SUCCESS', 'message' => 'Loaded Transactions','transactions' => $response };
  } else {
    $self->setResponseCode(422);
    return {'status' => 'FAILURE', 'message' => 'Bad gateway account'};
  }
}

 ######################################
 # Loads transactions for GET methods #
 ######################################

sub _loadTransactions {
  my $self = shift;
  my $gatewayAccount = shift;
  my $transID = shift || undef;

  my $loader = new PlugNPay::Transaction::Loader();
  my $transaction;

  eval {
    if(defined $transID) {
      $transaction = $loader->newLoad({ 'pnp_transaction_id' => $transID, 'username' => $gatewayAccount });
    } else {
      $transaction = $loader->newLoad({ 'username' => $gatewayAccount });
    }
  };
  if($@) {
    $transaction = {};
  }
  return $transaction;
}

sub _update {
  my $self = shift;
  my $transID = $self->getResourceData()->{'transaction'};
  my $inputData = $self->getInputData();

  my $finalize = $self->_finalize($inputData,$transID);

  my $response;
  if ($finalize) {
    $self->setResponseCode(200);
    $response = {'status' => 'SUCCESS', 'message' => 'Successfully updated transaction', 'transaction_id' => $transID};
  } else {
    $self->setResponseCode(520);
    $response = {'status' => 'ERROR', 'message' => 'Unable to update transaction', 'transaction_id' => $transID};
  }
  return $response;
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $transID = $self->getResourceData()->{'transaction'};

  if (!$transID) {
    $self->setResponseCode(400);
    return {'status' => 'ERROR', 'message' => 'No transaction id sent in request.'};
  }

  my $loadedTransaction = $self->_loadTransactions($merchant,$transID);
  $loadedTransaction = new PlugNPay::Transaction::Loader()->makeTransactionObj($loadedTransaction)->{$merchant}{$transID};

  my $response = {'status' => 'SUCCESS', 'message' => 'Successfully voided transaction.', 'transaction_id' => $transID};
  $self->setResponseCode(200);

  my $pnpProcessor = new PlugNPay::Processor::SemiIntegrated();

  if (ref($loadedTransaction) !~ /PlugNPay::Transaction/ || !$pnpProcessor->doesTransactionExist($transID)) {
    $self->setResponseCode(404);
    $response = {'status' => 'ERROR', 'message' => 'Transaction does not exist.', 'transaction_id' => $transID};
  } elsif (lc $loadedTransaction->getProcessor() eq 'plugnpay') {
    my $updater = new PlugNPay::Transaction::Updater();
    my $stateID = new PlugNPay::Transaction::State()->getTransactionStateID('VOID');

    eval {
      $updater->prepareForTransactionAlter({ 'state' => $stateID, 'pnp_transaction_id' => $loadedTransaction->getPNPTransactionID()});
    };

    if ($@) {
      $self->setResponseCode(422);
      $response = { 'status' => 'ERROR', 'message' => 'Failed to update transaction.', 'transaction_id' => $transID };
    }
    my $status = $pnpProcessor->removePendingTransaction($transID);
    if (!$status) {
      $response->{'message'} = 'Successfully voided, but failed to removed from pin pad.';
    }
  } else {
    $self->setResponseCode(422);
    $response = {'status' => 'ERROR', 'message' => 'Processor not supported.', 'transaction_id' => $transID};
  }
  return $response;
}

1;
