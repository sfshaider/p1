push @testsToRun, sub {
  my $testName = 'edge_auth_setup';
  my $account = $ENV{'PNP_ACCOUNT'};

  my $gatewayAccount = new PlugNPay::GatewayAccount($account);
  $gatewayAccount->setLive();
  $gatewayAccount->save();
  $gatewayAccount->setCardProcessor('testprocessor');

  my $features = new PlugNPay::Features($account,'general');

  $features->set('rest_api_transaction_version','');
  $features->set('testproc1Settle',0);
  $features->saveContext();

  my $fraudConfig = new PlugNPay::Features($account,'fraud_config');

  $fraudConfig->set('avs','2');
  $fraudConfig->set('cvv_avs','');
  $fraudConfig->set('dupchk','0');
  $fraudConfig->set('dupchkresp','problem');
  $fraudConfig->saveContext();
  $fraudConfig->saveContext();

  my $adjSettings = new PlugNPay::Transaction::Adjustment::Settings($account);
  $adjSettings->setEnabled(0);
  $adjSettings->save();

  pass($testName);
};

# Auth (synchronous)
push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorization';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

    my $fraudConfig = new PlugNPay::Features($account,'fraud_config');
  my $dupCheckValue = $fraudConfig->get('dupchk');
  my $dupCheckResponseValue = $fraudConfig->get('dupchkresp');
  $fraudConfig->set('dupchk','0');
  $fraudConfig->set('dupchkresp','echo');
  $fraudConfig->saveContext();

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $state = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'};
  my $finalStatus = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'finalStatus'};
  my $status = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'};
  my $processorMessage = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'processorMessage'};
  my $acctCodeHash = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'accountCode'};
  is($state,'AUTH',$testName .': test synchronous authorization state is AUTH');
  is($acctCodeHash->{'1'},'1234',$testName .': test account code 1 has proper value');
  is($acctCodeHash->{'2'},'g2g',$testName .': test account code 2 has proper value');
  is($finalStatus,undef,$testName .': test synchronous authorization finalStatus is undefined');
  is($status,undef,$testName .': test synchronous transaction status is undefined');
  isnt($processorMessage,'',$testName .': test processorMessage value is not empty');

  $fraudConfig->set('dupchk',$dupCheckValue);
  $fraudConfig->set('dupchkresp',$dupCheckResponseValue);
  $fraudConfig->saveContext();
};

# Auth with DUKPT (synchronous)
push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorizationDukpt';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

    my $fraudConfig = new PlugNPay::Features($account,'fraud_config');
  my $dupCheckValue = $fraudConfig->get('dupchk');
  my $dupCheckResponseValue = $fraudConfig->get('dupchkresp');
  $fraudConfig->set('dupchk','0');
  $fraudConfig->set('dupchkresp','echo');
  $fraudConfig->saveContext();

  my $authData = basicAuthData();
  # this test data is for an expired card so that's all we can test right now
  $authData->{'payment'}{'dukpt'} = {
    ksn => 'FF002629159014E000B5',
    track2 => '7B197416C765B898FBE585441859E97E35E2876FB14841F219CF5B56E4219C6C4DD4CE5030C25770'
  };
  # remove auth card data so dukpt data is used for sure
  delete $authData->{'payment'}{'card'};

  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $errors = $responseData->{'content'}{'data'}{'errors'}{'transaction1'};
  my $status = $errors->{'status'};
  my $message = $errors->{'message'};
  is($status,'error',$testName .': test synchronous transaction duckpt status is error');
  is($message,'Card is expired.',$testName .': test synchronous transaction dukpt message is card is expired');

  $fraudConfig->set('dupchk',$dupCheckValue);
  $fraudConfig->set('dupchkresp',$dupCheckResponseValue);
  $fraudConfig->saveContext();
};

# Auth (synchronous)
push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorizationWithSurcharge';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

    my $fraudConfig = new PlugNPay::Features($account,'fraud_config');
  my $dupCheckValue = $fraudConfig->get('dupchk');
  my $dupCheckResponseValue = $fraudConfig->get('dupchkresp');
  $fraudConfig->set('dupchk','0');
  $fraudConfig->set('dupchkresp','echo');
  $fraudConfig->saveContext();

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  $authData->{'amount'} = '10.00';
  $authData->{'feeAmount'} = '5.00';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};
  my $amount = $transaction1->{'amount'};
  my $state = $transaction1->{'transactionState'};
  my $finalStatus = $transaction1->{'finalStatus'};
  my $status = $transaction1->{'status'};
  my $processorMessage = $transaction1->{'processorMessage'};
  my $acctCodeHash = $transaction1->{'accountCode'};
  is($amount,'10.00',$testName . ': test amount is the same');
  is($state,'AUTH',$testName .': test synchronous authorization state is AUTH');
  is($acctCodeHash->{'1'},'1234',$testName .': test account code 1 has proper value');
  is($acctCodeHash->{'2'},'g2g',$testName .': test account code 2 has proper value');
  is($finalStatus,undef,$testName .': test synchronous authorization finalStatus is undefined');
  is($status,undef,$testName .': test synchronous transaction status is undefined');
  isnt($processorMessage,'',$testName .': test processorMessage value is not empty');

  $fraudConfig->set('dupchk',$dupCheckValue);
  $fraudConfig->set('dupchkresp',$dupCheckResponseValue);
  $fraudConfig->saveContext();
};

# Auth (synchronous) Verify PO Number
push @testsToRun, sub {
  my $testName = 'edge_testAuthPurchaseOrderNumber';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

    my $fraudConfig = new PlugNPay::Features($account,'fraud_config');
  my $dupCheckValue = $fraudConfig->get('dupchk');
  my $dupCheckResponseValue = $fraudConfig->get('dupchkresp');
  $fraudConfig->set('dupchk','0');
  $fraudConfig->set('dupchkresp','echo');
  $fraudConfig->saveContext();

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  $authData->{'purchaseOrderNumber'} = '4561237890';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $poNumber = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'purchaseOrderNumber'};

  is($poNumber, '4561237890', 'edge_testAuthPurchaseOrderNumber: Purchase Order Number matches input');

  $fraudConfig->set('dupchk',$dupCheckValue);
  $fraudConfig->set('dupchkresp',$dupCheckResponseValue);
  $fraudConfig->saveContext();
};

# Auth (synchronous) 4Cs failure without ponum
push @testsToRun, sub {
  my $testName = 'edge_testAuthPurchaseOrderNumberFailure';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';
  my $gaObj = new PlugNPay::GatewayAccount($account);
  my $originalProc = $gaObj->getCardProcessor();
  $gaObj->setCardProcessor('cccc2');
  $gaObj->save();

    my $fraudConfig = new PlugNPay::Features($account,'fraud_config');
  my $dupCheckValue = $fraudConfig->get('dupchk');
  my $dupCheckResponseValue = $fraudConfig->get('dupchkresp');
  $fraudConfig->set('dupchk','0');
  $fraudConfig->set('dupchkresp','echo');
  $fraudConfig->saveContext();

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $status = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'};
  isnt($status,'success', 'edge_testAuthPurchaseOrderNumberFailure: transaction failed due to missing purchase order number');

  $fraudConfig->set('dupchk',$dupCheckValue);
  $fraudConfig->set('dupchkresp',$dupCheckResponseValue);
  $fraudConfig->saveContext();

  $gaObj->setCardProcessor($originalProc);
  $gaObj->save();
};

push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorizationDuplicate';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $fraudConfig = new PlugNPay::Features($account,'fraud_config');
  my $dupCheckValue = $fraudConfig->get('dupchk');
  my $dupCheckResponseValue = $fraudConfig->get('dupchkresp');
  $fraudConfig->set('dupchk','1');
  $fraudConfig->set('dupchkresp','problem');
  $fraudConfig->saveContext();

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $errors = $responseData->{'content'}{'data'}{'errors'}{'transaction1'};
  my $status = $errors->{'status'};
  is($status,'duplicate',$testName .': test synchronous transaction status is duplicate');

  $fraudConfig->set('dupchk',$dupCheckValue);
  $fraudConfig->set('dupchkresp',$dupCheckResponseValue);
  $fraudConfig->saveContext();
};

push @testsToRun, sub {
  my $testName = 'edge_testAVSOnlyPassAVS';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';
  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  # Set amount for testproc1 avs failure
  $authData->{'amount'} = '0.00';
  $authData->{'flags'} = ['avsonly'];
  $authData->{'billingInfo'}{'postalCode'} = '50000'; # returns M for match of address
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };
  my $responseData = post($account,$url,$request);
  my $state = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'};
  my $finalStatus = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'finalStatus'};
  my $status = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'};
  my $processorMessage = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'processorMessage'};
  my $message = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'message'};
  is($state,'AUTH',$testName .': test synchronous transaction state is AUTH');
  is($finalStatus,undef,$testName .': test synchronous transaction finalStatus is undef');
  is($status,undef,$testName .': test synchronous transaction status is undef');
};

push @testsToRun, sub {
  my $testName = 'edge_testAVSOnlyFailAVS';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';
  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  # Set amount for testproc1 avs failure
  $authData->{'amount'} = '0.00';
  $authData->{'flags'} = ['avsonly'];
  $authData->{'billingInfo'}{'postalCode'} = '10000'; # returns N for non-match of address
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };
  my $responseData = post($account,$url,$request);
  my $state = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'};
  my $finalStatus = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'finalStatus'};
  my $status = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'};
  my $processorMessage = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'processorMessage'};
  my $message = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'message'};
  is($state,'VOID',$testName .': test synchronous transaction state is VOID');
  is($finalStatus,undef,$testName .': test synchronous transaction finalStatus is undef');
  is($status,undef,$testName .': test synchronous transaction status is undef');
};

push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorizationFailAVS';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';
  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  # Set amount for testproc1 avs failure
  $authData->{'amount'} = '1026.00';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };
  my $responseData = post($account,$url,$request);
  my $state = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'};
  my $finalStatus = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'finalStatus'};
  my $status = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'};
  my $processorMessage = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'processorMessage'};
  my $message = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'message'};
#badcard
  is($state,'VOID',$testName .': test synchronous transaction state is VOID');
  is($finalStatus,undef,$testName .': test synchronous transaction finalStatus is undef');
  is($status,undef,$testName .': test synchronous transaction status is undef');
};

push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorizationFailCVV';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';
  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  # Set amount for testproc1 avs failure
  $authData->{'amount'} = '1028.00';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };
  my $responseData = post($account,$url,$request);
  my $state = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'};
  my $finalStatus = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'finalStatus'};
  my $status = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'};
  my $processorMessage = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'processorMessage'};
  my $message = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'message'};
#badcard
  is($state,'VOID',$testName .': test synchronous transaction state is VOID');
  is($finalStatus,undef,$testName .': test synchronous transaction finalStatus is badcard');
  is($status,undef,$testName .': test synchronous transaction status is badcard');
};

# AuthPostAuth (synchronous)
$tests{'edge_testSynchronousAuthorizationWithPostauth'} = sub {
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  $authData->{'flags'} = ['authpostauth'];
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $state = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'};
  my $status = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'};
  my $finalStatus = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'finalStatus'};
  my $processorMessage = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'processorMessage'};
  #success
  is($state,'POSTAUTH_READY','edge_testSynchronousAuthorizationWithPostauth: test synchronous authorization state is POSTAUTH_READY');
  is($finalStatus,undef,'edge_testSynchronousAuthorizationWithPostauth: test synchronous authorization postauth finalStatus is pending');
  is($status,undef,'edge_testSynchronousAuthorizationWithPostauth: test synchronous transaction status is success');
  isnt($processorMessage,'','edge_testSynchronousAuthorizationWithPostauth: test processorMessage value is not empty');
};

# Authprev
push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorizationPrev';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $authPrevData = {
    "processMode"=> "sync",
    "initialOrderID"=> $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'merchantOrderID'},
    "transactionRefID"=> $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'pnpTransactionID'},
    "payment" => { "type" => "card", "mode" => "auth" }
  };

  my $prevrequest = {
    transactions => {
      transaction1 => $authPrevData
    }
  };

  my $prevResponseData = post($account,$url,$prevrequest);

  my $state =       $prevResponseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'};
  my $finalStatus = $prevResponseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'finalStatus'};
  my $status =      $prevResponseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'};
# success
  is($state,'AUTH',$testName .': test synchronous authorization state is AUTH');
  is($finalStatus,undef,$testName .': test synchronous authorization finalStatus is undef');
  is($status,undef,$testName .': test synchronous transaction status is success is undef');
};

push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorizationVoid';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $features = new PlugNPay::Features($account,'general');
  my $testproc1SettleFeatureValue = $features->get('testproc1Settle');
  $features->set('testproc1Settle','1');
  $features->saveContext();

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);

  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};
  my $transactionId = $transaction1->{'pnpTransactionID'};

  my $state = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'};
  my $finalStatus = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'finalStatus'};
  my $status = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'};

  is($state,'AUTH','edge_testSynchronousAuthorizationVoid: test synchronous authorization state is AUTH');

  my $voidUrl = sprintf('%s/:%s',$url,$transactionId);
  my $voidResponseData = del($account,$voidUrl,{});
  $state =       $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionState'};
  $finalStatus = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'finalStatus'};
  $status =      $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'status'};
  is($state,'VOID',$testName .': test synchronous authorization state is VOID after void call');
  is($finalStatus,undef,$testName .': test synchronous authorization VOID is undef');
  is($status,undef,$testName .': test synchronous transaction status is undef');

  $features->set('testproc1Settle',$testproc1SettleFeatureValue);
  $features->saveContext();
};


push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorizationVoidFailure';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);

  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};
  my $transactionId = $transaction1->{'pnpTransactionID'};

  my $state = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'};
  my $finalStatus = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'finalStatus'};
  my $status = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'};
  #success
  is($state,'AUTH','edge_testSynchronousAuthorizationVoidFailure: test synchronous authorization state is AUTH');
  is($finalStatus,undef,'edge_testSynchronousAuthorizationVoidFailure: test synchronous authorization AUTH is undef');
  is($status,undef,'edge_testSynchronousAuthorizationVoidFailure: test synchronous transaction status is undef');

  # modify transactionId so that it's invalid
  $transactionId .= 9;
  my $voidUrl = sprintf('%s/:%s',$url,$transactionId);
  my $voidResponseData = del($account,$voidUrl,{});
  $state = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionState'};
  $finalStatus = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'finalStatus'};
  $status = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'status'};
# see test name
  isnt($state,'VOID',$testName .': test synchronous authorization state is not VOID after void call');
  is($finalStatus,undef,$testName .': test synchronous authorization VOID is not success');
  is($status,undef,$testName .': test synchronous transaction status is success');
};

# Auth (expect invalid processor)
push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorizationProcessorDown';
  my $account = $ENV{'PNP_ACCOUNT'};

  # we're going to change the account processor temporarily.
  # then do everything in an eval so we can reset the account back to live if it fails
  my $ga = new PlugNPay::GatewayAccount($account);
  my $proc = $ga->getCardProcessor();
  $ga->setCardProcessor('downprocessor');
  $ga->save();
  eval {
    my $url = '/api/merchant/order/transaction';

    my $authData = basicAuthData();
    # SET PROCESS MODE TO SYNC!!!
    $authData->{'processMode'} = 'sync';
    my $request = {
      transactions => {
        transaction1 => $authData
      }
    };

    my $responseData = post($account,$url,$request);
    my $errors1 = $responseData->{'content'}{'data'}{'errors'}{'transaction1'};
    if ($errors1) { # error expected for async
      like($errors1->{'message'},qr/is currently down/, $testName .': error says processor is down');
    } else {
      fail($testName .': expected processor down error');
    }
  };
  $ga->setCardProcessor($proc);
  my $success = $ga->save();
};

# Auth (expect account cancelled)
push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorizationAccountCancelled';
  my $account = $ENV{'PNP_ACCOUNT'};

  # we're going to change the account status temporarily.
  # then do everything in an eval so we can reset the account back to live if it fails
  my $ga = new PlugNPay::GatewayAccount($account);
  $ga->setCancelled();
  ok($ga->save(),$testName .': attempt to change account to cancelled for test to proceed');
  eval {
    my $url = '/api/merchant/order/transaction';

    my $authData = basicAuthData();
    # SET PROCESS MODE TO SYNC!!!
    $authData->{'processMode'} = 'sync';
    my $request = {
      transactions => {
        transaction1 => $authData
      }
    };

    my $responseData = post($account,$url,$request);
    my $errors1 = $responseData->{'content'}{'data'}{'errors'}{'transaction1'};
    if ($errors1) { # error expected for async
      like($errors1->{'message'},qr/may not process/, $testName .': error says account may not process');
    } else {
      fail($testName .': expected may not process accounts error');
    }
  };
  $ga->setForceStatusChange(1);
  $ga->setLive();
  ok($ga->save(),$testName .': revert account status');
};

# Auth (expect failure for luhn 10)
push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorizationFailLuhn';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  $authData->{'payment'}{'card'}{'number'} = '4111111111111112'; # fails luhn 10
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $errors1 = $responseData->{'content'}{'data'}{'errors'}{'transaction1'};
  if ($errors1) {
    like($errors1->{'message'},qr/luhn10/, $testName .': error contains luhn10');
  } else {
    fail($testName .': expected luhn10 failre');
  }
};

# Auth (asynchronous error for luhn 10)
push @testsToRun, sub {
  my $testName = 'edge_testAsynchronousAuthorizationFailLuhn';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  # set up transaction data
  my $authData = basicAuthData();
  $authData->{'payment'}{'card'}{'number'} = '4111111111111112'; # fails luhn 10
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  # call the transaction api to process the transaction
  my $responseData = post($account,$url,$request);
  my $errors1 = $responseData->{'content'}{'data'}{'errors'}{'transaction1'};
  if ($errors1) { # error expected for async
    if ($errors1->{'processor'} eq 'testprocessor') {
      pass($testName .': expected error for async with "legacy" testprocessor');
    } else {
      like($errors1->{'message'},qr/luhn10/, $testName .': error contains luhn10');
    }
  } else {
    fail($testName .': expected luhn10 error');
  }
};

push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthorizationFailHighAmount';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  $authData->{'amount'} = '1000000.00'; # to high!
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $finalStatus = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'finalStatus'};
  my $error = $responseData->{'content'}{'data'}{'errors'}{'transaction1'}{'message'};

  is($finalStatus,undef,$testName .': test synchronous authorization');
  isnt($error,undef,$testName .': ensure error message exists');
};



push @testsToRun, sub {
  my $testName = 'edge_testReadAuthorization';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $authData = basicAuthData();
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};

  # read response
  my $transactionId = $transaction1->{'pnpTransactionID'};
  $url = '/api/merchant/order/transaction/:' . $transactionId;

  $responseData = get($account,$url);
  my $processorMessage = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'processorMessage'};
  isnt($responseData->{'content'}{'data'}{'transactions'}{$transactionId},undef,$testName .': check that transaction gets loaded');
  isnt($processorMessage,'',$testName .': test processorMessage value is not empty');
};

push @testsToRun, sub {
  my $testName = 'edge_testMarkAuthorization';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $features = new PlugNPay::Features($account,'general');
  my $testproc1SettleFeatureValue = $features->get('testproc1Settle');
  $features->set('testproc1Settle','0');
  $features->saveContext();

  my $authData = basicAuthData();
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);

  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};
  my $transactionId = $transaction1->{'pnpTransactionID'};

  my $url2 = '/api/merchant/order/transaction/:' . $transactionId;
  $responseData = get($account,$url2,$request);
  if(ok($transactionId,$testName .': check that there is a transaction id')) {
    # read response
    $url = '/api/merchant/order/transaction/';

    $request = {
      transactions => [{
        transactionID => $transactionId
      }]
    };
    $responseData = put($account,$url,$request);
    my $transactionState = $responseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionState'};
    is($transactionState,'POSTAUTH_READY',$testName .': ensure transaction state is postauth ready');
  } else {
    fail($testName .': auth failed')
  }

  $features->set('testproc1Settle',$testproc1SettleFeatureValue);
  $features->saveContext();
};

push @testsToRun, sub {
  my $testName = 'edge_testSettleAuthorization';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $authData = basicAuthData();
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};
  my $transactionId = $transaction1->{'pnpTransactionID'};

  if(ok($transactionId,$testName .': check that there is a transaction id')) {
    # read response
    $url = '/api/merchant/order/transaction/';

    $request = {
      transactions => [{
        transactionID => $transactionId
      }]
    };
    $responseData = put($account,$url,$request);
    $url = '/api/merchant/order/transaction/:' . $transactionId . '/';
    $responseData = get($account,$url);

    if ($transaction1->{'processor'} eq 'testprocessor') {
      settleLegacyTestProcessorTransaction($account,$transactionId);
    } elsif ($transaction1->{'processor'} eq 'testprocessor2') {
      my $settler = new PlugNPay::Processor::Process::Settlement();
      my $settleResult = $settler->settleTransactions({
        $account => [ $transactionId ]
      });
    } else {
      fail($testName .'only testprocessor and testprocessor2 can be tested');
    }

    $url = '/api/merchant/order/transaction/:' . $transactionId . '/';
    my $afterSettled = get($account,$url);
    my $settledData = $afterSettled->{'content'}{'data'}{'transactions'}{$transactionId};
    is($settledData->{'transactionState'},'POSTAUTH',$testName .': ensure transaction has state of POSTAUTH after settlement');
  }
};

push @testsToRun, sub {
  my $testName = 'edge_testMarkAuthorizationLower';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $authData = basicAuthData();
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };
  my $responseData = post($account,$url,$request);
  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};

  my $transactionId = $transaction1->{'pnpTransactionID'};
  my $settlementAmount = 0.50;
  $request = {
    transactions => [{
      transactionId => $transactionId,
      settlementAmount => $settlementAmount
    }]
  };
  $responseData = put($account,$url,$request);
  my $processorMessage = $responseData->{'content'}{'data'}{'transactions'}{$transactionId}{'processorMessage'};
  my $transactionState = $responseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionState'};
  my $markedAmount = $responseData->{'content'}{'data'}{'transactions'}{$transactionId}{'amount'};
  is($transactionState,'POSTAUTH_READY',$testName .': ensure transaction state is postauth ready');
  is(0,$settlementAmount - $markedAmount,$testName .': ensure transaction was marked for the lower amount');
  is($processorMessage,'',$testName .': test processorMessage value is empty for postauth (marking does not connect to processor)');
};

push @testsToRun, sub {
  my $testName = 'edge_testAsynchronousAuthorization';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $authData = basicAuthData();
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,'/api/merchant/order/transaction',$request);
  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};
  my $errors1 = $responseData->{'content'}{'data'}{'errors'}{'transaction1'};
  if ($errors1) { # error expected for async
    is($errors1->{'processor'},'testprocessor',$testName .': expected error for async with "legacy" testprocessor');
  } else {
    my $finalStatus = $transaction1->{'finalStatus'};
    is($finalStatus,'pending',$testName .': test that authorization is pending');
    my $transactionId = $transaction1->{'pnpTransactionID'};
    $responseData = get($account,'/api/merchant/order/transaction/:' . $transactionId,$request);

    $url = '/api/merchant/order/transaction/:' . $transactionId;
    $responseData = get($account,$url,$request);

    my $transaction1Response = $responseData->{'content'}{'data'}{'transactions'}{$transactionId};
    is($transaction1Response->{'transactionState'},'AUTH',$testName .': check that transaction state is auth');
  }
};

# Auth with Fee Transaction, the void
push @testsToRun, sub {
  my $testName = 'edge_testSynchronousAuthWithConvenienceFeeThenVoid';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $features = new PlugNPay::Features($account,'general');
  my $testproc1SettleFeatureValue = $features->get('testproc1Settle');
  $features->set('testproc1Settle','1');
  $features->saveContext();

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);

  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};
  my $transactionId = $transaction1->{'pnpTransactionID'};

  my $state = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'};

  is($state,'AUTH','edge_testSynchronousAuthorizationVoid: test synchronous authorization state is AUTH');

  my $voidUrl = sprintf('%s/:%s',$url,$transactionId);
  my $voidResponseData = del($account,$voidUrl,{});
  $state =       $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionState'};
  my $tStatus =  $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionStatus'};
  my $accountCode = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'accountCode'};
  my $shipcity = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'shippingInfo'}{'city'};
  is($state,'VOID',$testName .': test synchronous authorization state is VOID after void call');
  is($tStatus->{'state'},'VOID',$testName .': test transaction state -> state is VOID');
  is($tStatus->{'status'},'Successful',$testName .': test transaction state -> status is Successful');

  $features->set('testproc1Settle',$testproc1SettleFeatureValue);
  $features->saveContext();
};
