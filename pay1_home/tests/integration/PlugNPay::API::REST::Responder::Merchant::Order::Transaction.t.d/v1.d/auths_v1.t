push @testsToRun, sub {
  my $testName = 'v1_auth_setup';
  my $account = $ENV{'PNP_ACCOUNT'};

  my $gatewayAccount = new PlugNPay::GatewayAccount($account);
  $gatewayAccount->setLive();
  $gatewayAccount->save();

  my $features = new PlugNPay::Features($account,'general');

  $features->set('rest_api_transaction_version','v1');
  $features->set('testproc1Settle',0);
  $features->saveContext();

  my $fraudConfig = new PlugNPay::Features($account,'fraud_config');

  $fraudConfig->set('avs','2');
  $fraudConfig->set('cvv_avs','');
  $fraudConfig->set('dupchk','0');
  $fraudConfig->set('dupchkresp','problem');
  $fraudConfig->saveContext();

  my $adjSettings = new PlugNPay::Transaction::Adjustment::Settings($account);
  $adjSettings->setEnabled(0);
  $adjSettings->save();

  pass($testName);
};

# Auth (synchronous)
push @testsToRun, sub {
  my $testName = 'v1_testSynchronousAuthorization';
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
  my $state = $transaction1->{'transactionState'};
  my $finalStatus = $transaction1->{'finalStatus'};
  my $status = $transaction1->{'status'};
  my $processorMessage = $transaction1->{'processorMessage'};
  my $phone = $transaction1->{'billingInfo'}{'phone'};

  my $accountCode = $transaction1->{'accountCode'};
  my $accountCode2 = $transaction1->{'accountCode2'};

  is($accountCode,'1234',$testName .': test account code 1 has proper value');
  is($accountCode2,'g2g',$testName .': test account code 2 has proper value');
  is($phone,'555-555-5555',$testName .': test synchronous authorization phone is set');
  is($state,'AUTH',$testName .': test synchronous authorization state is AUTH');
  is($finalStatus,'success',$testName .': test synchronous authorization finalStatus');
  is($status,'success',$testName .': test synchronous transaction status is success');
  isnt($processorMessage,'',$testName .': test processorMessage value is not empty');
};

push @testsToRun, sub {
  my $testName = 'v1_testSynchronousAuthorizationDuplicate';
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
  my $testName = 'v1_testSynchronousAuthorization:shrink:v1:1';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $gatewayAccount = new PlugNPay::GatewayAccount($account);
  my $features = $gatewayAccount->getFeatures();
  my $currentTestProc1SettleValue = $features->get('testproc1Settle');
  my $currentPostAuthPendingValue = $features->get('postauthpending');
  $features->set('rest_api_shrink_response','v1:1');
  $features->saveContext();

  eval {
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
    my $state = $transaction1->{'transactionState'};
    my $finalStatus = $transaction1->{'finalStatus'};
    my $status = $transaction1->{'status'};
    my $processorMessage = $transaction1->{'processorMessage'};
    my $phone = $transaction1->{'billingInfo'}{'phone'};
    my $history = $transaction1->{'transactionHistory'};

    is($phone,'555-555-5555',$testName .': test synchronous authorization phone is set');
    is($state,'AUTH',$testName .': test synchronous authorization state is AUTH');
    is($finalStatus,'success',$testName .': test synchronous authorization finalStatus');
    is($status,'success',$testName .': test synchronous transaction status is success');
    isnt($processorMessage,'',$testName .': test processorMessage value is not empty');
    ok(keys %{$history} == 0,$testName .': test transactionHistory is empty');
  };

  $features->set('rest_api_shrink_response','');
  $features->saveContext();
};

push @testsToRun, sub {
  my $testName = 'v1_testSynchronousAuthorizationFailAVS';
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

  is($state,'VOID',$testName .': test synchronous transaction state is VOID');
  is($finalStatus,'badcard',$testName .': test synchronous transaction finalStatus is badcard');
  is($status,'badcard',$testName .': test synchronous transaction status is badcard');
  like($processorMessage,qr/voided/i,$testName .': test synchronous transactionprocessorMessage says transaction voided');
  like($message,qr/voided/i,$testName .': test synchronous transaction message says transaction voided');
};

push @testsToRun, sub {
  my $testName = 'v1_testSynchronousAuthorizationFailCVV';
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

  is($state,'VOID',$testName .': test synchronous transaction state is VOID');
  is($finalStatus,'badcard',$testName .': test synchronous transaction finalStatus is badcard');
  is($status,'badcard',$testName .': test synchronous transaction status is badcard');
  like($processorMessage,qr/voided/i,$testName .': test synchronous transaction processorMessage says transaction voided');
  like($message,qr/voided/i,$testName .': test synchronous transaction message says transaction voided');

};

# AuthPostAuth (synchronous)
push @testsToRun, sub {
  my $testName = 'v1_testSynchronousAuthorizationWithPostauth';
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

  is($state,'AUTH',$testName .': test synchronous authorization state is AUTH');
  is($finalStatus,'success',$testName .': test synchronous authorization finalStatus is success');
  is($status,'success',$testName .': test synchronous transaction status is success');
  isnt($processorMessage,'',$testName .': test processorMessage value is not empty');
};

# Authprev
push @testsToRun, sub {
  my $testName = 'v1_testSynchronousAuthorizationPrev';
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

  is($state,'AUTH',$testName .': test synchronous authorization state is AUTH');
  is($finalStatus,'success',$testName .': test synchronous authorization');
  is($status,'success',$testName .': test synchronous transaction status is success');
};

push @testsToRun, sub {
  my $testName = 'v1_testSynchronousAuthorizationVoid';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  $authData->{'accountCode'}{'1'} = '';
  $authData->{'shippingInfo'} = {};
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

  is($state,'AUTH',$testName .': test synchronous authorization state is AUTH');
  is($finalStatus,'success',$testName .': test synchronous authorization AUTH is success');
  is($status,'success',$testName .': test synchronous transaction status is success');

  my $voidUrl = sprintf('%s/:%s',$url,$transactionId);
  my $voidResponseData = del($account,$voidUrl,{});
  $state =       $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionState'};
  $finalStatus = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'finalStatus'};
  $status =      $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'status'};
  my $tStatus =  $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionStatus'};
  my $accountCode = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'accountCode'};
  my $shipcity = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'shippingInfo'}{'city'};
  is($state,'VOID',$testName .': test synchronous authorization state is VOID after void call');
  is($finalStatus,'success',$testName .': test synchronous authorization AUTH was success');
  is($status,'success',$testName .': test synchronous transaction status is success');
  is($tStatus->{'state'},'Authorization',$testName .': test transaction state -> state is Authorization');
  is($tStatus->{'status'},'Successful',$testName .': test transaction state -> status is Successful');
};

push @testsToRun, sub {
  my $testName = 'v1_testSynchronousAuthorizationVoidFailureSettled';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  # set up testproc1 to settle
  my $gatewayAccount = new PlugNPay::GatewayAccount($account);
  my $features = $gatewayAccount->getFeatures();
  my $currentTestProc1SettleValue = $features->get('testproc1Settle');
  my $currentPostAuthPendingValue = $features->get('postauthpending');
  $features->set('testproc1Settle','1');
  $features->set('postauthpending','no');
  $features->saveContext();

  my $authData = basicAuthData();
  # SET PROCESS MODE TO SYNC!!!
  $authData->{'processMode'} = 'sync';
  $authData->{'accountCode'}{'1'} = '';
  $authData->{'shippingInfo'} = {};
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

  is($state,'AUTH',$testName .': test synchronous authorization state is AUTH');
  is($finalStatus,'success',$testName .': test synchronous authorization AUTH is success');
  is($status,'success',$testName .': test synchronous transaction status is success');

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

    is($transactionState,'POSTAUTH',$testName .': ensure transaction state is postauth (settled)');
  } else {
    fail($testName .': auth failed')
  }
  my $voidUrl = sprintf('%s/:%s',$url,$transactionId);
  my $voidResponseData = del($account,$voidUrl,{});
  $state =       $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionState'};
  $finalStatus = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'finalStatus'};
  $status =      $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'status'};
  my $tStatus = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionStatus'};
  my $accountCode = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'accountCode'};
  my $shipcity = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'shippingInfo'}{'city'};
  is($state,'POSTAUTH',$testName .': test synchronous authorization state is VOID after failed void call');
  is($finalStatus,'success',$testName .': test synchronous authorization VOID is problem');
  is($status,'problem',$testName .': test synchronous transaction status is problem');
  is($tStatus->{'state'},'Settlement',$testName .': test transaction state -> state is Settlement');
  is($tStatus->{'status'},'Successful',$testName .': test transaction state -> status is Successful');

  $features->set('testproc1Settle',$currentTestProc1SettleValue);
  $features->set('postauthpending',$currentPostAuthPendingValue);
  $features->saveContext();
};

push @testsToRun, sub {
  my $testName = 'v1_testSynchronousAuthorizationVoidFailureNonexistant';
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

  is($state,'AUTH',$testName .': test synchronous authorization state is AUTH');
  is($finalStatus,'success',$testName .': test synchronous authorization AUTH is success');
  is($status,'success',$testName .': test synchronous transaction status is success');

  # modify transactionId so that it's invalid
  $transactionId .= 9;
  my $voidUrl = sprintf('%s/:%s',$url,$transactionId);
  my $voidResponseData = del($account,$voidUrl,{});
  $state = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionState'};
  $finalStatus = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'finalStatus'};
  $status = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'status'};
  isnt($state,'VOID',$testName .': test synchronous authorization state is not VOID after void call');
  isnt($finalStatus,'success',$testName .': test synchronous authorization VOID is not success');
  is($status,undef,$testName .': test synchronous transaction status is success');
};

# Auth (expect invalid processor)
push @testsToRun, sub {
  my $testName = 'v1_testSynchronousAuthorizationProcessorDown';
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
      fail($testName .'expected processor down error');
    }
  };
  $ga->setCardProcessor($proc);
  my $success = $ga->save();
};

# Auth (expect account cancelled)
push @testsToRun, sub {
  my $testName = 'v1_testSynchronousAuthorizationAccountCancelled';
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
  my $testName = 'v1_testSynchronousAuthorizationFailLuhn';
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
  my $testName = 'v1_testAsynchronousAuthorizationFailLuhn';
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
  my $testName = 'v1_testSynchronousAuthorizationFailHighAmount';
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
  my $testName = 'v1_testReadAuthorization';
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
  my $testName = 'v1_testMarkAuthorization';
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
};

push @testsToRun, sub {
  my $testName = 'v1_testSettleAuthorization';
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
      fail($testName .': Only testprocessor and testprocessor2 can be tested');
    }

    $url = '/api/merchant/order/transaction/:' . $transactionId . '/';
    my $afterSettled = get($account,$url);
    my $settledData = $afterSettled->{'content'}{'data'}{'transactions'}{$transactionId};
    is($settledData->{'transactionState'},'POSTAUTH',$testName .': ensure transaction has state of POSTAUTH after settlement');
  }
};

push @testsToRun, sub {
  my $testName = 'v1_testAuthPostAuthSettle';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  # set up testproc1 to settle
  my $features = new PlugNPay::Features($account,'general');
  my $currentTestProc1SettleValue = $features->get('testproc1Settle');
  my $currentPostAuthPendingValue = $features->get('postauthpending');
  $features->set('testproc1Settle','1');
  $features->set('postauthpending','no');
  $features->saveContext();

  my $f2 = new PlugNPay::Features($account, 'general');

  my $authData = basicAuthData();
  $authData->{'processMode'} = 'sync';
  $authData->{'flags'} = ['postauth'];
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};
  my $transactionId = $transaction1->{'pnpTransactionID'};

  if(ok($transactionId,$testName .': check that there is a transaction id')) {
    # read get
    $url = '/api/merchant/order/transaction/:' . $transactionId . '/';
    my $afterSettled = get($account,$url);
    my $settledData = $afterSettled->{'content'}{'data'}{'transactions'}{$transactionId};
    is($settledData->{'transactionState'},'POSTAUTH',$testName .': ensure transaction has state of POSTAUTH after settlement');
  }

  $features->set('testproc1Settle',$currentTestProc1SettleValue);
  $features->set('postauthpending',$currentPostAuthPendingValue);
  $features->saveContext();
};

push @testsToRun, sub {
  my $testName = 'v1_testMarkAuthorizationLower';
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
  my $transactionState = $responseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionState'};
  my $markedAmount = $responseData->{'content'}{'data'}{'transactions'}{$transactionId}{'amount'};
  is($transactionState,'POSTAUTH_READY',$testName .': ensure transaction state is postauth ready');
  is(0,$settlementAmount - $markedAmount,$testName .': ensure transaction was marked for the lower amount');
};

push @testsToRun, sub {
  my $testName = 'v1_testAsynchronousAuthorization';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction/:';

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
  my $testName = 'v1_testSynchronousAuthWithConvenienceFeeThenVoid';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = 'api/merchant/order/transaction';

  # Set up adjustment with convenience fee.
  my $aas = new PlugNPay::Transaction::Adjustment::Settings('pnpdemo');
  $aas->setEnabled(1);
  $aas->setModelID(9);
  $aas->setAdjustmentAuthorizationAccount('pnpdemo');
  $aas->save();

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

  is($state,'AUTH',$testName .': test synchronous authorization state is AUTH');
  is($finalStatus,'success',$testName .': test synchronous authorization AUTH is success');
  is($status,'success',$testName .': test synchronous transaction status is success');

  my $voidUrl = sprintf('%s/:%s',$url,$transactionId);
  my $voidResponseData = del($account,$voidUrl,{});
  my $adjustmentInfo = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'adjustmentInformation'};
  my $adjustmentId = $adjustmentInfo->{'adjustmentOrderID'};
  my $adjustmentAcct = $adjustmentInfo->{'adjustmentAccount'};
  my $adjustmentState = $voidResponseData->{'content'}{'data'}{'transactions'}{$adjustmentId}{'transactionState'};
  $state =       $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionState'};
  $finalStatus = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'finalStatus'};
  $status =      $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'status'};
  my $tStatus =  $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'transactionStatus'};
  my $accountCode = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'accountCode'};
  my $shipcity = $voidResponseData->{'content'}{'data'}{'transactions'}{$transactionId}{'shippingInfo'}{'city'};
  is($state,'VOID',$testName .': test synchronous authorization state is VOID after void call');
  is($finalStatus,'success',$testName .': test synchronous authorization VOID was success');
  is($status,'success',$testName .': test synchronous transaction status is success');
  is($tStatus->{'state'},'Authorization',$testName .': test transaction state -> state is Authorization');
  is($tStatus->{'status'},'Successful',$testName .': test transaction state -> status is Successful');
  is($adjustmentState,'VOID',$testName .': test adjustment state is VOID');
};