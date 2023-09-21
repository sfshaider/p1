push @testsToRun, sub {
  my $testName = 'v1_return_setup';
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
  $fraudConfig->saveContext();

  my $adjSettings = new PlugNPay::Transaction::Adjustment::Settings($account);
  $adjSettings->setEnabled(0);
  $adjSettings->save();

  pass($testName);
};

# Auth -> Return
# This should cause a VOID
push @testsToRun, sub {
  my $testName = 'v1_testReturnAuthorization';

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

  # mark transaction
  my $transactionId = $transaction1->{'pnpTransactionID'};
  my $orderId = $transaction1->{'pnpOrderID'};

  # this is where the return is actually tested...
  # this should actually end up with a void
  $authData = basicAuthData(); # format for a return is the same as an auth
  $authData->{'processMode'} = 'sync';
  # except we use transactionRefId instead of order id
  $authData->{'transactionRefID'} = $transactionId;
  # and of course, mode is return, not auth...
  $authData->{'payment'}{'mode'} = 'return';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  $responseData = post($account,$url,$request);

  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'},'VOID',$testName .': check that the transaction state is VOID');
  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'},'success',$testName .': check return status');
  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'pnpOrderID'},$orderId,$testName .': check return orderId');
};

push @testsToRun, sub {
  my $testName = 'v1_testReturnAuthorizationNoTransactionRef';

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

  # mark transaction
  my $transactionId = $transaction1->{'pnpTransactionID'};
  my $orderId = $transaction1->{'pnpOrderID'};

  # this is where the return is actually tested...
  # this should actually end up with a void
  $authData = basicAuthData(); # format for a return is the same as an auth
  $authData->{'processMode'} = 'sync';

  # and of course, mode is return, not auth...
  $authData->{'payment'}{'mode'} = 'return';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  $responseData = post($account,$url,$request);
  isnt($responseData->{'content'}{'data'}{'errors'}{'transaction1'},undef,$testName .': check that error for transaction is not undefiend');
  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'},undef,$testName .': check that the transaction is undefined');
};

push @testsToRun, sub {
  my $testName = 'v1_testCreditNotAllowed';

  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $gatewayAccount = new PlugNPay::GatewayAccount($account);
  $gatewayAccount->setCanProcessCredits(0);
  $gatewayAccount->save();


  # this is where the return is actually tested...
  # this should actually end up with a void
  my $authData = basicAuthData(); # format for a return is the same as an auth
  $authData->{'processMode'} = 'sync';

  # and of course, mode is return, not auth...
  $authData->{'payment'}{'mode'} = 'credit';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  isnt($responseData->{'content'}{'data'}{'errors'}{'transaction1'},undef,$testName .': check that error for transaction is not undefiend');
  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'},undef,$testName .': check that the transaction  is undefined');
};

push @testsToRun, sub {
  my $testName = 'v1_testCredit';

  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $gatewayAccount = new PlugNPay::GatewayAccount($account);
  $gatewayAccount->setCanProcessCredits(1);
  $gatewayAccount->save();

  # this is where the return is actually tested...
  # this should actually end up with a void
  my $authData = basicAuthData(); # format for a return is the same as an auth
  $authData->{'processMode'} = 'sync';

  # and of course, mode is return, not auth...
  $authData->{'payment'}{'mode'} = 'credit';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'},'CREDIT',$testName .': check that the transaction state is CREDIT');
  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'},'success',$testName .': check credit status');
};

# Auth -> Return for partial amount. Auth not settled!
# This should cause an Auth Reversal (reauth)
push @testsToRun, sub {
  my $testName = 'v1_testPartialReturnAuthorization';

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
  my $authResponse = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};

  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};

  # mark transaction
  my $transactionId = $transaction1->{'pnpTransactionID'};
  my $orderId = $transaction1->{'pnpOrderID'};

  # this is where the return is actually tested...
  # this should actually end up with a reauth
  $authData = basicAuthData(); # format for a return is the same as an auth
  $authData->{'processMode'} = 'sync';
  my $returnAmount = 0.05;
  my $originalAuthAmount = $authData->{'amount'};
  # my $returnAmount = $authData->{'amount'} - $returnAmount;
  $authData->{'amount'} = $returnAmount;
  # except we use transactionRefId instead of order id
  $authData->{'transactionRefID'} = $transactionId;
  # and of course, mode is return, not auth...
  $authData->{'payment'}{'mode'} = 'return';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  $responseData = post($account,$url,$request);
  $url = '/api/merchant/order/transaction/:' . $transactionId;
  my $getResponseData = get($account,$url,$request);

  my $returnResponse = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};

  is($returnResponse->{'status'},'success',$testName .': check return status');
  is($returnResponse->{'pnpOrderID'},$authResponse->{'pnpOrderID'},$testName .': check return order id');
  is($returnResponse->{'merchantOrderID'},$authResponse->{'merchantOrderID'},$testName .': check return merchant order id');
  is($returnResponse->{'transactionState'},'AUTH',$testName .': check that the transaction state is AUTH for unified processor');
  is($returnResponse->{'baseAmount'},$originalAuthAmount - $returnAmount,$testName .': check auth amount for return converted to reauth');
};

push @testsToRun, sub {
  my $testName = 'v1_testFullReturnAuthorization';
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
  my $orderId = $transaction1->{'pnpOrderID'};

  # this is where the return is actually tested...
  # this should actually end up with a void
  $authData = basicAuthData(); # format for a return is the same as an auth
  $authData->{'processMode'} = 'sync';
  # except we use transactionRefId instead of order id
  $authData->{'transactionRefID'} = $transactionId;
  # and of course, mode is return, not auth...
  $authData->{'payment'}{'mode'} = 'return';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };
  $responseData = post($account,$url,$request);
  my $returnResponse = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};

  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'},'success',$testName .': check return status');
  is($returnResponse->{'merchantOrderID'},$transaction1->{'merchantOrderID'},$testName .': check return merchant order id');
  is($returnResponse->{'pnpOrderID'},$transaction1->{'pnpOrderID'},$testName .': check that order id matches auth');
  is($returnResponse->{'transactionState'},'VOID',$testName .': check that the transaction state is VOID');
};

# Auth -> Return
# this will fail not due to the amount being over, but due to the fact that you can't return
# against an unsettled auth
push @testsToRun, sub {
  my $testName = 'v1_testReturnAuthorizationOverAmount';
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
  my $authResponse = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};

  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};

  my $transactionId = $transaction1->{'pnpTransactionID'};
  my $orderId = $transaction1->{'pnpOrderID'};

  # this is where the return is actually tested...
  # this should actually end up with a void
  $authData = basicAuthData(); # format for a return is the same as an auth
  $authData->{'processMode'} = 'sync';
  # except we use transactionRefId instead of order id
  $authData->{'transactionRefID'} = $transactionId;
  $authData->{'amount'} = $authData->{'amount'} + 1;

  # and of course, mode is return, not auth...
  $authData->{'payment'}{'mode'} = 'return';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  $responseData = post($account,$url,$request);
  my $returnResponse = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};
  my $errors1 = $responseData->{'content'}{'data'}{'errors'}{'transaction1'};
  if ($errors1) { # error expected for async
    like($errors1->{'message'},qr/auth reversal amount must be less than the auth amount/, $testName .': error contains "auth reversal amount must be less than the auth amount"');
  } else {
    fail( $testName .': expected error');
  }
};

push @testsToRun, sub {
  my $testName = 'v1_testReturnMarkedAuthorization';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $mr = new PlugNPay::API::MockRequest();
  $mr->setResource('/api/merchant/order/transaction');
  $mr->setMethod('POST');
  $mr->addHeaders({
    'content-type' => 'application/json'
  });
  my $authData = basicAuthData();
  $authData->{'processMode'} = 'sync';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };
  my $content = encode_json($request);
  $mr->setContent($content);

  my $rest = new PlugNPay::API::REST('/api', { mockRequest => $mr });
  $rest->setRequestGatewayAccount($account);
  my $response = $rest->respond({ skipHeaders => 1 });
  my $responseData = decode_json($response);
  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};

  # mark transaction
  my $transactionId = $transaction1->{'pnpTransactionID'};
  my $orderId = $transaction1->{'pnpOrderID'};
  $mr->setMethod('PUT');
  $request = {
    transactions => [{
      'transactionID' => $transactionId
    }]
  };
  $content = encode_json($request);
  $mr->setContent($content);

  $rest = new PlugNPay::API::REST('/api', { mockRequest => $mr });
  $rest->setRequestGatewayAccount($account);
  $response = $rest->respond({ skipHeaders => 1 });
  $responseData = decode_json($response);

  # this is where the return is actually tested...
  # this should actually end up with a void
  $authData = basicAuthData(); # format for a return is the same as an auth
  $authData->{'processMode'} = 'sync';
  # except we use transactionRefId instead of order id
  $authData->{'transactionRefID'} = $transactionId;
  # and of course, mode is return, not auth...
  $authData->{'payment'}{'mode'} = 'return';
  $mr->setMethod('POST'); # post for returns
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };
  my $content = encode_json($request);
  $mr->setContent($content);

  $rest = new PlugNPay::API::REST('/api', { mockRequest => $mr });
  $rest->setRequestGatewayAccount($account);
  $response = $rest->respond({ skipHeaders => 1 });
  $responseData = decode_json($response);

  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'},'success',$testName .': check return status');
  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'pnpOrderID'},$orderId,$testName .': check return orderId');
};

push @testsToRun, sub {
  my $testName = 'v1_testReturnSettledAuthorization';
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

  # mark transaction
  my $transactionId = $transaction1->{'pnpTransactionID'};
  my $orderId = $transaction1->{'pnpOrderID'};
  $request = {
    transactions => [{
      'transactionID' => $transactionId
    }]
  };
  $responseData = put($account,$url,$request);

  # need to settle a tran to return it...well sort of.
  # transforming it into a void is a different test...
  my $settler = new PlugNPay::Processor::Process::Settlement();
  my $settleResult = $settler->settleTransactions({
    $account => [ $transactionId ]
  });

  # this is where the return is actually tested...
  $authData = basicAuthData(); # format for a return is the same as an auth
  $authData->{'processMode'} = 'sync';
  # except we use transactionRefId instead of order id
  $authData->{'transactionRefID'} = $transactionId;
  # and of course, mode is return, not auth...
  $authData->{'payment'}{'mode'} = 'return';
  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };
  $responseData = post($account,$url,$request);
  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'},'success',$testName .': check return status');
  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'pnpOrderID'},$orderId,$testName .': check return orderId');
};

push @testsToRun, sub {
  my $testName = 'v1_testReturnSettledAuthorizationOverAmount';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  # set up testproc1 to settle
  my $gatewayAccount = new PlugNPay::GatewayAccount($account);
  my $features = $gatewayAccount->getFeatures();
  my $currentTestProc1ReturnValue = $features->get('testproc1Return');
  $features->set('testproc1Return','realtime');
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

  # mark transaction
  my $transactionId = $transaction1->{'pnpTransactionID'};
  my $orderId = $transaction1->{'pnpOrderID'};
  $request = {
    transactions => [{
      'transactionID' => $transactionId
    }]
  };
  $responseData = put($account,$url,$request);

  # need to settle a tran to return it...well sort of.
  # transforming it into a void is a different test...
  if ($transaction1->{'processor'} eq 'testprocessor') {
    settleLegacyTestProcessorTransaction($account,$transactionId);
  } elsif ($transaction1->{'processor'} eq 'testprocessor2') {
    my $settler = new PlugNPay::Processor::Process::Settlement();
    my $settleResult = $settler->settleTransactions({
      $account => [ $transactionId ]
    });
  } else {
    fail('only testprocessor or testprocessor2 can be tested');
  }


  # this is where the return is actually tested...
  $authData = basicAuthData(); # format for a return is the same as an auth
  $authData->{'processMode'} = 'sync';
  # except we use transactionRefId instead of order id
  $authData->{'transactionRefID'} = $transactionId;
  # and of course, mode is return, not auth...
  $authData->{'payment'}{'mode'} = 'return';
  $authData->{'amount'} = $authData->{'amount'} + 1;

  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  $responseData = post($account,$url,$request);
  my $errors1 = $responseData->{'content'}{'data'}{'errors'}{'transaction1'};
  if ($errors1) { # error expected for async
    like($errors1->{'message'},qr/return amount may not exceed/, $testName .': error contains "return amount may not exceed"');
  } else {
    fail($testName .': expected error');
  }
  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'status'},'problem',$testName .': check return status');
  is($responseData->{'content'}{'data'}{'transactions'}{'transaction1'}{'transactionState'},'CREDIT',$testName .': check return transactionState');

  $features->set('testproc1Return',$currentTestProc1ReturnValue);
  $features->saveContext();
};

push @testsToRun, sub {
  my $testName = 'v1_testAsynchronousAuthorizationReturn';
  my $account = $ENV{'PNP_ACCOUNT'};
  my $url = '/api/merchant/order/transaction';

  my $authData = basicAuthData();

  my $request = {
    transactions => {
      transaction1 => $authData
    }
  };

  my $responseData = post($account,$url,$request);
  my $transaction1 = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};
  my $errors1 = $responseData->{'content'}{'data'}{'errors'}{'transaction1'};
  if ($errors1) { # error expected for async
    like($errors1->{'message'},qr/sync/,$testName .': expected error for async with "legacy" testprocessor');
  } else {
    my $finalStatus = $transaction1->{'finalStatus'};
    is($finalStatus,'pending',$testName .': test asynchronous authorization');

    my $transactionId = $transaction1->{'pnpTransactionID'};
    my $orderId = $transaction1->{'pnpOrderID'};

    # load database response
    $url = '/api/merchant/order/transaction/:' . $transactionId;
    my $authResponse = get($account,$url);
    my $transaction1Response = $authResponse->{'content'}{'data'}{'transactions'}{$transactionId};
    is($transaction1Response->{'transactionState'},'AUTH', $testName .': check that auth was successful');

    # this is where the return is actually tested...
    # this should actually end up with a void
    $authData = basicAuthData(); # format for a return is the same as an auth
    # except we use transactionRefId instead of order id
    $authData->{'transactionRefID'} = $transactionId;
    # and of course, mode is return, not auth...
    $authData->{'payment'}{'mode'} = 'return';
    my $request = {
      transactions => {
        transaction1 => $authData
      }
    };
    $url = '/api/merchant/order/transaction';
    $responseData = post($account,$url,$request);
    my $returnPendingResponse = $responseData->{'content'}{'data'}{'transactions'}{'transaction1'};
    # load database response
    $url = '/api/merchant/order/transaction/:' . $transactionId;
    my $returnResponse = get($account,$url);
    my $transaction1ReturnResponse = $returnResponse->{'content'}{'data'}{'transactions'}{$transactionId};
    is($transaction1ReturnResponse->{'status'},'success',$testName .': check return status');
    is($transaction1ReturnResponse->{'pnpOrderID'},$orderId,$testName .': check that order id matches auth');
    is($transaction1ReturnResponse->{'transactionState'},'VOID',$testName .': check that the transaction state is VOID');
  }
};
