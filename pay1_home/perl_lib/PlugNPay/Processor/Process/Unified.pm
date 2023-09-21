package PlugNPay::Processor::Process::Unified;

use strict;
use PlugNPay::Processor::Process::Unified::Mark;
use PlugNPay::Processor::ResponseCode;

our $__collection__ = 'unified_processors';

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub sendmserver {
  my $self        = shift;
  my $transaction = shift;
  my $context = shift;
  my $username    = $transaction->{'username'};
  my $operation   = $transaction->{'operation'};
  my %data        = %{ $transaction->{'query'} };

  my $logger = new PlugNPay::Logging::DataLog( { 'collection' => $__collection__ } );

  $transaction->{'paymethod'} = lc $transaction->{'paymethod'};
  my $payType = $transaction->{'paymethod'} =~ /checking|savings/ ? 'ach' : $transaction->{'paymethod'};
  $transaction->{'payType'} = $payType;

  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $processors = {
    'ach'    => $gatewayAccount->getCheckProcessor(),
    'card'   => $gatewayAccount->getCardProcessor(),
    'tds'    => $gatewayAccount->getTDSProcessor(),
    'wallet' => $gatewayAccount->getWalletProcessor(),
    'emv'    => $gatewayAccount->getEmvProcessor(),
  };
  my $processor;
  my $isTDS = $data{'tdsflag'};
  if ( $isTDS && defined $processors->{'tds'} ) {
    $processor = $processors->{'tds'};
  } else {
    $processor = $processors->{$payType} || $processors->{'card'};
  }
  $transaction->{'processor'} = $processor;

  if ( $data{'refnumber'} && !$data{'processor_reference_id'} ) {
    $data{'processor_reference_id'} = $data{'refnumber'};
  } elsif ( $data{'processor_reference_id'} && !$data{'refnumber'} ) {
    $data{'refnumber'} = $data{'processor_reference_id'};
  }

  if ( lc($operation) =~ /sale/ || ( lc($operation) =~ /^auth/ && ( $data{'transflags'} =~ /capture/ || $data{'transflags'} =~ /recurring/ || $data{'transflags'} =~ /recinit/ ) ) ) {
    my $conditionChecker = new PlugNPay::Processor::Mode($processor);
    if ( $conditionChecker->evaluateConditions( 'sale', \%data ) ) {
      $operation = 'sale';
      $transaction->{'operation'} = 'sale';
    } else {
      $operation = 'auth';
      $transaction->{'operation'} = 'auth';
    }
  }

  my @transFlags = split( ',', $data{'transflags'} );
  my $transFlagMap = {};
  foreach my $flag (@transFlags) {
    $transFlagMap->{$flag} = 1;
  }

  if ( ( $payType eq 'credit' || $payType eq 'card' ) && $transFlagMap->{'gift'} ) {
    $payType = 'gift';
    if ( $operation eq 'credit' && $transFlagMap->{'reload'} ) {
      $operation = 'reload';
    } elsif ( $operation eq 'credit' && $transFlagMap->{'issue'} ) {
      $operation = 'issue';
    } elsif ( $transFlagMap->{'balance'} ) {
      $operation = 'balance';
    }
  }

  my $transactionObj = $self->createTransactionObject({ transactionData => $transaction, context => $context });
  $transactionObj->setPNPOrderID($data{'pnp_order_id'});
  $transactionObj->setPNPTransactionID($data{'pnp_transaction_id'});
  my $payment = $transactionObj->getPayment();
  my $token;
  if ($payment) {
    $token = $payment->getToken();
  }

  if ( !defined $token || $token eq '' ) {
    $logger->log( { 'status' => 'problem', 'message' => 'token error in sendmserver', 'orderID' => $data{'orderID'}, 'username' => $transactionObj->getGatewayAccount() } );
    return {
      'FinalStatus' => 'problem',
      'MStatus'     => 'problem',
      'MErrMsg'     => 'Payment token server is unreachable, unable to process.'
    };
  }

  if ( lc($operation) eq 'forceauth' && !$transactionObj->doForceAuth() ) {
    $transactionObj->setForceAuth();
  }

  #Build order, moved so both processing and force auth could use
  my $order = new PlugNPay::Order();
  if ($transactionObj->getPNPOrderID()) {
    $order->setPNPOrderID($transactionObj->getPNPOrderID());
  } else {
    $transactionObj->setPNPOrderID($order->getPNPOrderID());
  }

  $order->setMerchantID( new PlugNPay::GatewayAccount::InternalID()->getMerchantID( $transactionObj->getGatewayAccount() ) );
  my $merchantOrderID = $transactionObj->getOrderID();
  if ( defined $merchantOrderID && $merchantOrderID ne '' ) {
    $order->setMerchantOrderID($merchantOrderID);
  } else {
    $order->setMerchantOrderID( $order->generateMerchantOrderID() );
  }

  $order->setOrderClassifier( $transactionObj->getMerchantClassifierID() );
  $order->addOrderTransaction($transactionObj);
  foreach my $key ( keys %data ) {
    if ( $key =~ /item(\d+)$/ ) {
      my $detail = new PlugNPay::Order::Detail();
      $detail->setCost( $data{$key}{'cost'} );
      $detail->setDescription( $data{$key}{'description'} );
      $detail->setQuantity( $data{$key}{'quantity'} );
      $detail->setDiscount( $data{$key}{'customa'} );
      $detail->setTax( $data{$key}{'customb'} );
      $detail->setCommodityCode( $data{$key}{'customc'} );
      $detail->setCustom1( $data{$key}{'customd'} );
      $detail->setCustom2( $data{$key}{'custome'} );
      $detail->setUnitOfMeasure( $data{$key}{'unit'} );
      $detail->setTaxable( $data{$key}{'taxable'} );
      $detail->setName( $data{$key}{'item'} );
      $order->addOrderDetail($detail);
    }
  }

  if ( lc($operation) eq 'storedata' || lc($operation) eq 'forceauth' ) {
    my $vault = new PlugNPay::Transaction::Vault();
    my $results = $vault->routeNewOrder( $operation, $order );
    return {
      'FinalStatus'        => $results->{'status'},
      'MStatus'            => $results->{'status'},
      'MErrMsg'            => $results->{'message'},
      'orderID'            => $results->{'orderID'},
      'auth-code'          => $transactionObj->getAuthorizationCode(),
      'cvvresp'            => 'A',
      'avs-resp'           => 'A',
      'pnp_order_id'       => $order->getPNPOrderID(),
      'pnp_transaction_id' => $transactionObj->getPNPTransactionID()
    };
  } elsif ( $isTDS && defined $processors->{'tds'} ) {
    return { 'MStatus' => 'failure', 'MErrMsg' => 'TDS Not availble currently, resumbit transaction with tdsflag = 0' };
  } else {
    my $processObj = new PlugNPay::Processor::Process( $transaction->{'operation'}, { 'async' => $transactionObj->isAsynchronous() } );
    my $processorObject = new PlugNPay::Processor( { 'id' => $transactionObj->getProcessorID() } );
    if ( $processorObject->getStatus() ne 'down' ) {
      my $orderResponse = $processObj->processTransaction($transactionObj);

      # The response is a Hash.... full of arrays of hashes!
      my @key;

      eval { @key = keys %{$orderResponse}; };
      if ($@) {
        if ($@) {
          $logger->log( { 'error' => $@ },{ stackTraceEnabled => 1 } );
        }
        return { 'FinalStatus' => 'problem', 'MErrMsg' => 'Processing error occurred: ' . $@, 'MStatus' => 'problem' };
      } else {
        my $uuid = new PlugNPay::Util::UniqueID();
        $uuid->fromBinary( $transactionObj->getPNPTransactionID() );
        my $response = $orderResponse->{ $key[0] }->{ $uuid->inHex() };

        # Why did we do this? Because miscutils expects a single hash back.
        my $responseCode = new PlugNPay::Processor::ResponseCode();
        my $newFinalStatus = $responseCode->getResultForCode( $response->{'processor_code'} );
        $response->{'FinalStatus'} = $newFinalStatus || $response->{'FinalStatus'};

        return $response;
      }
    } else {
      $logger->log(
        { 'processor' => $processorObject->getShortName(),
          'status'    => $processorObject->getStatus(),
          'orderID'   => $order->getMerchantOrderID(),
          'merchant'  => $transactionObj->getGatewayAccount()
        }
      );
      return { 'FinalStatus' => 'problem', 'MErrMsg' => 'The processor ' . $processorObject->getName() . ' is currently down.', 'MStatus' => 'Problem' };
    }
  }
}

sub createTransactionObject {
  my $self = shift;
  my $input = shift;
  my $transactionData = $input->{'transactionData'};
  my $context = $input->{'context'};

  my $logger = new PlugNPay::Logging::DataLog( { 'collection' => $__collection__ } );


  my %data = %{$transactionData->{'query'}}; # i'm just a copy of a copy of a copy...

  my $username  = $data{'username'};
  my $operation = $data{'operation'};
  my $processor = $transactionData->{'processor'};
  my $payType = $transactionData->{'payType'};

  my $transactionObj;
  $transactionObj = new PlugNPay::Transaction( $operation, $payType );
  my $additionalProcessorData = $data{'processorDataDetails'};

  if ( ref($transactionObj) !~ /^PlugNPay::Transaction/ ) {
    $logger->log( { 'status' => 'error', 'message' => 'Transaction was not created properly, created: ' . ref($transactionObj), 'username' => $username } );
    return {
      'FinalStatus' => 'problem',
      'MStatus'     => 'problem',
      'MErrMsg'     => 'Data submitted was insufficient to create Transaction, operation: ' . $operation . ', payment type: ' . $transactionData->{'paymethod'}
    };
  }

  if ( defined $data{'authorization_code'} || defined $data{'auth-code'} ) {
    $transactionObj->setAuthorizationCode( $data{'authorization_code'} || $data{'auth-code'} );
  }

  my ( $currency, $amount ) = split( ' ', $data{'amount'} );
  my $merchantOrderID = $data{'orderID'};
  if ( defined $data{'refnumber'} || defined $data{'processor_reference_id'} || defined $data{'pnp_transaction_ref_id'} || defined $data{'processor_token'} && !( ref($transactionObj) =~ /::PrePaid/ ) )
  {
    my $storedData = {};
    my $loader     = new PlugNPay::Transaction::Loader();
    $storedData = $loader->getReturnedProcessorData( \%data, $payType, $username );

    my $authCode       = ( $data{'authorization_code'}     ? $data{'authorization_code'}     : $storedData->{'authorization_code'} );
    my $procRefID      = ( $data{'processor_reference_id'} ? $data{'processor_reference_id'} : $storedData->{'processor_reference_id'} );
    my $pnpRefID       = ( $data{'pnp_transaction_ref_id'} ? $data{'pnp_transaction_ref_id'} : $storedData->{'pnp_transaction_id'} );
    my $processorToken = ( $data{'processor_token'}        ? $data{'processor_token'}        : $storedData->{'processor_token'} );
    my $pnpToken       = ( $data{'pnp_token'}              ? $data{'pnp_token'}              : $storedData->{'pnp_token'} );

    # TODO make sure this happens in transform
    # if ( $operation =~ /credit/ || $operation =~ /return/ ) {    #Need to load missing info for Returns
    #   my $verifier = new PlugNPay::Processor::Process::Verification();
    #   my $valid = $verifier->checkReturnAmount( $pnpRefID, $username, $amount, $processor );
    #   if ( !$data{'card-name'} || !$data{'card-address1'} || !$data{'card-zip'} ) {
    #     my $loadedData = $loader->newLoad( { 'username' => $username, 'pnp_transaction_id' => $pnpRefID } );
    #     $data{'card-name'}     = ( defined $data{'name'}        ? $data{'name'}        : $loadedData->{'billing_information'}{'name'} );
    #     $data{'card-address1'} = ( defined $data{'address'}     ? $data{'address'}     : $loadedData->{'billing_information'}{'address'} );
    #     $data{'card-address2'} = ( defined $data{'address2'}    ? $data{'address2'}    : $loadedData->{'billing_information'}{'address2'} );
    #     $data{'card-city'}     = ( defined $data{'city'}        ? $data{'city'}        : $loadedData->{'billing_information'}{'city'} );
    #     $data{'card-state'}    = ( defined $data{'state'}       ? $data{'state'}       : $loadedData->{'billing_information'}{'state'} );
    #     $data{'card-country'}  = ( defined $data{'country'}     ? $data{'country'}     : $loadedData->{'billing_information'}{'country'} );
    #     $data{'card-zip'}      = ( defined $data{'postal_code'} ? $data{'postal_code'} : $loadedData->{'billing_information'}{'postal_code'} );
    #     $data{'email'}         = ( defined $data{'email'}       ? $data{'email'}       : $loadedData->{'billing_information'}{'email'} );
    #     $data{'fax'}           = ( defined $data{'fax'}         ? $data{'fax'}         : $loadedData->{'billing_information'}{'fax'} );
    #     $data{'phone'}         = ( defined $data{'phone'}       ? $data{'phone'}       : $loadedData->{'billing_information'}{'phone'} );
    #     if ( defined $loadedData->{'card_information'} ) {
    #       $data{'card-exp'} = ( defined $data{'card_expiration'} ? $data{'card_expiration'} : $loadedData->{'card_information'}{'card_expiration'} );
    #     }
    #   }
    #
    #   unless ($valid) {
    #     $logger->log( { 'status' => 'problem', 'message' => 'return amount is invalid', 'orderID' => $data{'orderID'}, 'username' => $username } );
    #     return {
    #       'FinalStatus' => 'Error',
    #       'MStatus'     => 'Error',
    #       'MErrMsg'     => 'Tried to return for an amount greater than the original transaction amount'
    #     };
    #   }
    # }

    $transactionObj->setProcessorToken($processorToken);
    $transactionObj->setAuthorizationCode($authCode);
    $transactionObj->setProcessorReferenceID($procRefID);
    $transactionObj->setPNPTransactionReferenceID($pnpRefID);
    $additionalProcessorData = $storedData->{'additional_processor_details'};
    $transactionObj->setPNPToken($pnpToken);
  } elsif ( ( defined $data{'authorization_code'} || defined $data{'processor_reference_id'} || defined $data{'pnp_transaction_ref_id'} || defined $data{'processor_token'} )
    && ref($transactionObj) =~ /::PrePaid/ ) {
    $transactionObj->setProcessorToken( $data{'processor_token'} );
    $transactionObj->setAuthorizationCode( $data{'authorization_code'} );
    $transactionObj->setProcessorReferenceID( $data{'processor_reference_id'} );
    $transactionObj->setPNPTransactionReferenceID( $data{'pnp_transaction_ref_id'} );
  }

  my $env = new PlugNPay::Environment();
  my $ipaddress = ( $data{'ipaddress'} ? $data{'ipaddress'} : $env->get('PNP_CLIENT_IP') );
  $transactionObj->setIPAddress($ipaddress);

  my $billingContact = new PlugNPay::Contact();
  $billingContact->setFullName( $data{'card-name'} );
  $billingContact->setAddress1( $data{'card-address1'} || $data{'card-address'} );
  $billingContact->setAddress2( $data{'card-address2'} );
  $billingContact->setCity( $data{'card-city'} );
  $billingContact->setState( $data{'card-state'} );
  $billingContact->setCountry( $data{'card-country'} );
  $billingContact->setCompany( $data{'card-company'} );
  $billingContact->setPostalCode( $data{'card-zip'} );
  $billingContact->setEmailAddress( $data{'email'} );
  $billingContact->setPhone( $data{'phone'} );
  $billingContact->setFax( $data{'fax'} );
  $transactionObj->setBillingInformation($billingContact);

  my $shippingContact = new PlugNPay::Contact();
  $shippingContact->setFullName( $data{'shipname'} );
  $shippingContact->setAddress1( $data{'address1'} );
  $shippingContact->setAddress2( $data{'address2'} );
  $shippingContact->setCity( $data{'city'} );
  $shippingContact->setState( $data{'state'} );
  $shippingContact->setCountry( $data{'country'} );
  $shippingContact->setCompany( $data{'shipcompany'} );
  $shippingContact->setPostalCode( $data{'zip'} );
  $shippingContact->setEmailAddress( $data{'shipemail'} );
  $shippingContact->setPhone( $data{'shipphone'} );
  $transactionObj->setShippingInformation($shippingContact);

  $transactionObj->setGatewayAccount($username);
  $transactionObj->setCurrency($currency);
  $transactionObj->setTransactionAmount($amount);
  $transactionObj->setBaseTransactionAmount( $data{'base_amount'} || $amount );
  $transactionObj->setTaxAmount( $data{'tax'} );
  $transactionObj->setBaseTaxAmount( $data{'base_tax'} || 0 );
  $transactionObj->setMerchantClassifierID( $data{'order-id'} );
  $transactionObj->setMerchantTransactionID($merchantOrderID);
  $transactionObj->setPNPTransactionID( $data{'pnp_transaction_id'} );
  $transactionObj->setPurchaseOrderNumber( $data{'ponumber'} );
  $transactionObj->setInitialOrderID( $data{'origorderid'} );

  foreach my $flag (split(',', $data{'transflags'})) {
    $transactionObj->addTransFlag($flag);
  }

  $transactionObj->setProcessorDataDetails($additionalProcessorData);
  $transactionObj->setExtraTransactionData( $data{'extra_data'} );
  if ( $data{'marketdata'} ) {
    $transactionObj->setCustomData( { 'marketdata' => $data{'marketdata'} } );
  }
  if ( $payType eq 'credit' || $payType eq 'gift' || $payType eq 'prepaid' || $payType eq 'card' || $payType eq 'emv' ) {
    my $card = new PlugNPay::CreditCard();
    if ( $data{'magstripe'} || $data{'magensacc'} ) {
      my $magstripe = $data{'magstripe'};
      my $magensa   = $data{'magensacc'};

      if ($magensa) {
        $card->setMagensa($magensa);
        my $decryptedData = $card->decryptMagensa($magensa);

        my $magensaMagstripe = $decryptedData->{'magstripe'};
        $card->setMagstripe($magensaMagstripe);

        my $decryptedCardNumber = $decryptedData->{'card-number'};
        $card->setNumber($decryptedCardNumber);

        if ( $decryptedData->{'error'} ) {
          my $error = 'Magensa Decrypt Error: ' . $decryptedData->{'errorMessage'};
          $transactionObj->setValidationError($error);
        }
      } elsif ($magstripe) {
        $card->setMagstripe($magstripe);
      }
    } else {
      if ( $transactionObj->getPNPToken() || $data{'pnp_token'} ) {
        my $pnpToken = $transactionObj->getPNPToken() || $data{'pnp_token'};
        $card->fromToken($pnpToken);
      } else {
        $card->setNumber( $data{'card-number'} );
      }
      $card->setSecurityCode( $data{'card-cvv'} );
      my ( $expMonth, $expYear ) = split( '/', $data{'card-exp'} );
      $card->setExpirationMonth($expMonth);
      $card->setExpirationYear($expYear);
      $card->setName( $data{'card-name'} );
    }

    if ( $payType eq 'gift' || $payType eq 'prepaid' ) {
      $transactionObj->setGiftCard($card);
    } else {
      $transactionObj->setCreditCard($card);
    }
  } elsif ( $payType eq 'ach' ) {
    my $ach = new PlugNPay::OnlineCheck();
    $ach->setAccountType( $data{'accttype'} );
    $transactionObj->setSECCode( $data{'checktype'} );
    if ( $transactionObj->getPNPToken() || $data{'pnp_token'} ) {
      my $pnpToken = $transactionObj->getPNPToken() || $data{'pnp_token'};
      $ach->fromToken($pnpToken);
    } else {
      $ach->setAccountNumber( $data{'accountnum'} );
      if ( $ach->verifyABARoutingNumber( $data{'routingnum'} ) ) {
        $ach->setABARoutingNumber( $data{'routingnum'} );
      } else {
        $ach->setInternationalRoutingNumber( $data{'routingnum'} );
      }
    }
    $ach->setName( $data{'card-name'} );
    $transactionObj->setOnlineCheck($ach);
  }

  # Check Account Codes #
  if ( defined $data{'acct_code'} ) {
    $transactionObj->setAccountCode( 1, $data{'acct_code'} );
  }

  if ( defined $data{'acct_code2'} ) {
    $transactionObj->setAccountCode( 2, $data{'acct_code2'} );
  }

  if ( defined $data{'acct_code3'} ) {
    $transactionObj->setAccountCode( 3, $data{'acct_code3'} );
  }

  if ( defined $data{'acct_code4'} ) {
    $transactionObj->setAccountCode( 4, $data{'acct_code4'} );
  }

  if ( defined $data{'transflags'} && $data{'transflags'} =~ /debug_mode/ ) {
    $self->debugLog( \%data );
  }

  if ( $data{'processMode'} eq 'async' ) {
    $transactionObj->setToAsynchronous();
  } else {
    $transactionObj->setToSynchronous();
  }
  return $transactionObj;
}

# sub updateTransaction {
#   my $self               = shift;
#   my $transaction        = shift;
#   my $username           = $transaction->{'username'};
#   my $operation          = $transaction->{'operation'};
#   my %data               = %{ $transaction->{'query'} };
#   my $loader             = new PlugNPay::Transaction::Loader();
#   my $stateMachine       = new PlugNPay::Transaction::State();
#   my $loadedTransactions = {};
#   my @transIDs           = ();
#   my $pnp_transaction_id = undef;
#   my $hexID;
#   my @settlementArray = ();
#
#   if ( defined $data{'pnp_transaction_id'} ) {
#     $pnp_transaction_id = PlugNPay::Util::UniqueID::fromHexToBinary($data{'pnp_transaction_id'});
#     $hexID = PlugNPay::Util::UniqueID::fromBinaryToHex($data{'pnp_transaction_id'});
#
#     push @transIDs, $pnp_transaction_id;
#     $loadedTransactions = $loader->newLoad( { 'pnp_transaction_id' => $pnp_transaction_id } )->{$username}{$hexID};
#     if ( $stateMachine->getStateNames()->{ $loadedTransactions->{'transaction_state_id'} } !~ /POSTAUTH/i ) {
#       my $settlementAmount = ( $loadedTransactions->{'settlement_amount'} ? $loadedTransactions->{'settlement_amount'} : $loadedTransactions->{'transaction_amount'} );
#       push @settlementArray, { 'pnp_transaction_id' => $pnp_transaction_id, 'settlement_amount' => $settlementAmount };
#     }
#   } else {
#     my ( $currency, $amount ) = split( / /, $data{'amount'} );
#     my $options = {
#       'merchant' => $transaction->{'username'},
#       'amount'   => $amount || $data{'amount'},
#       'currency' => $currency
#     };
#     if ( $data{'transdate'} ) {
#       $options->{'transaction_date_time'} = $data{'transdate'},;
#     }
#
#     my $loaded = $loader->newLoad($options)->{ $transaction->{'username'} };
#
#     push @transIDs, ( keys %{$loaded} );
#
#     if ( @transIDs != 1 ) {
#       if ( @transIDs > 1 ) {
#         my @transactionsToUpdate = ();
#
#         foreach my $transID (@transIDs) {
#           push @transactionsToUpdate, $loaded->{$transID};
#           my $settlementAmount = ( $loaded->{$transID}{'settlement_amount'} ? $loaded->{$transID}{'settlement_amount'} : $loaded->{$transID}{'transaction_amount'} );
#           if ( $stateMachine->getStateNames()->{ $loaded->{$transID}{'transaction_state_id'} } !~ /POSTAUTH/i ) {
#             push @settlementArray, { 'pnp_transaction_id' => $transID, 'settlement_amount' => $settlementAmount };
#           }
#         }
#         $loadedTransactions = \@transactionsToUpdate;
#       } else {
#         return { 'FinalStatus' => 'problem', 'MStatus' => 'Failure', 'MErrMsg' => 'Transaction not found' };
#       }
#     } else {
#       my $settlementAmount = ( $loaded->{ $transIDs[0] }{'settlement_amount'} ? $loaded->{ $transIDs[0] }{'settlement_amount'} : $loaded->{ $transIDs[0] }{'transaction_amount'} );
#       if ( $stateMachine->getStateNames()->{ $loaded->{ $transIDs[0] }{'transaction_state_id'} } !~ /POSTAUTH/i ) {
#         push @settlementArray, { 'pnp_transaction_id' => $transIDs[0], 'settlement_amount' => $settlementAmount };
#       }
#       $loadedTransactions = [ $loaded->{ $transIDs[0] } ];
#     }
#   }
#
#   if ( $operation =~ /^void/ ) {
#     my $processObj   = new PlugNPay::Processor::Process::Void();
#     my $pending      = $processObj->void($loadedTransactions);
#     my $responses    = $processObj->redeemPending($pending);
#     my @keys         = keys %{$responses};
#     my $transactions = $responses->{ $keys[0] };
#     if ( defined $hexID ) {
#       return $transactions->{$hexID};
#     } else {
#       my @responseIDs = keys %{$transactions};
#       return $transactions->{ $responseIDs[0] };
#     }
#   } elsif ( lc($operation) =~ /postauth/ ) {
#     my $processObj = new PlugNPay::Processor::Process::Settlement();
#     my $success    = $processObj->markForSettlement( \@settlementArray );
#     if ($success) {
#       return { 'FinalStatus' => 'success', 'MStatus' => 'Success', 'MErrMsg' => 'Successfully settled transactions', 'transactions' => \@settlementArray };
#     } else {
#       return { 'FinalStatus' => 'problem', 'MStatus' => 'Failure', 'MErrMsg' => 'Unable to mark transactions' };
#     }
#   } else {
#     return { 'FinalStatus' => 'problem', 'MStatus' => 'Failure', 'MErrMsg' => 'Invalid Operation' };
#   }
# }



1;
