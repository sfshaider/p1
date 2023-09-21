package PlugNPay::Transaction::Vault;

use strict;
use PlugNPay::Contact;
use PlugNPay::CardData;
use PlugNPay::Sys::Time;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount;
use PlugNPay::Processor::Route;
use PlugNPay::Processor::Process;
use PlugNPay::Logging::MessageLog;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Order;
use PlugNPay::Transaction::Formatter;
use PlugNPay::Transaction::Updater;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub routeNewOrder {
  my $self = shift;
  my $operation = lc shift;
  my $order = shift;
  my $result = {};
  if ($operation eq 'forceauth') {
    $result = $self->forceAuthorizeNewProcessor($order); 
  } elsif ($operation eq 'storedata') {
    $result = $self->newProcess($order->getOrderTransactions());
    $result->{'status'} => 'success';
    $result->{'message'} => 'Attempted to preform storedata request';
  } else {
    $result = {'status' => 'failure', 'message' => 'Invalid Operation: ' . $operation};
  }

  return $result;
}

##############
# Force Auth #
##############
sub forceAuthorizeNewProcessor {
  my $self = shift;
  my $order = shift;
  my $status = 1;
  my $formatter = new PlugNPay::Transaction::Formatter();
  my $timeObj = new PlugNPay::Sys::Time();
  my $updater = new PlugNPay::Transaction::Updater();

  eval {
    $status = $order->save('AUTH');
    $order->saveOrderDetails();
  };

  my $errors;
  my $message;
  if (!$status || $@) {
    $message = 'Failed to forceauth order';
    if ($@) {
      new PlugNPay::Logging::DataLog({'collection' => 'order'})->log({
        'error' => $@,
        'orderID' => $order->getMerchantOrderID(),
        'username' => $order->getGatewayAccount(),
        'operation' => 'forceauth',
        'transactionIDs' => join(', ', @{$order->getOrderTransactionIDs()}),
        'orderClassifierID' => $order->getOrderClassifier() || ''
      });
    }
    my @failed = map{ $formatter->prepareTransaction($_); } @{$order->getOrderTransactions()};
    $errors = $updater->failPendingTransactions(\@failed, $@ || $message);
  } else {
    my $transactions = {};
    foreach my $trans (@{$order->getOrderTransactions()}) {
      $trans->addTransFlag('forceauth');
      my $transData = $formatter->prepareTransaction($trans);
      my $transHash = $transData->{'transactionData'};
      my $additionalProcessorDetails = $transData->{'additionalProcessorData'};
      $additionalProcessorDetails->{'operation_type'} = 'forceauth';
      $transHash->{'processor_reference_id'} = $trans->getAuthorizationCode();
      if ($trans->getAuthorizationCode()) {
        $message = 'Successful force authorization';
        $additionalProcessorDetails->{'processor_status'} = 'success';
        $transHash->{'wasSuccess'} = 'true';
      } else {
        $status = 0;
        $message = 'Force authorization missing required data: authorization code';
        $additionalProcessorDetails->{'processor_status'} = 'problem';
        $transHash->{'wasSuccess'} = 'false';
      }

      $additionalProcessorDetails->{'processor_message'} = $message;
      $transHash->{'additional_processor_details'} = $additionalProcessorDetails;
      $transHash->{'processor_transaction_date_time'} = $timeObj->nowInFormat('iso_gm');
      $transactions->{$trans->getPNPTransactionID()} = $transHash;
    }

    $errors = $updater->finalizeTransactions($transactions); 

    if (keys %{$errors} > 0) {
      $status = 0; 
      $message = 'Failed to finalize forceauth';
      new PlugNPay::Logging::DataLog({'collection' => 'order'})->log({
        'error' => 'failed to finalize force auth transactions',
        'orderID' => $order->getMerchantOrderID(),
        'username' => $order->getGatewayAccount(),
        'operation' => 'forceauth',
        'transactionIDs' => join(', ', keys %{$errors}),
        'orderClassifierID' => $order->getOrderClassifier() || ''
      });
    }
  }

  return {
    'status'   => $status ? 'success' : 'failure',
    'message'  => $message,
    'orderID'  => $order->getMerchantOrderID(),
    'merchant' => $order->getGatewayAccount()
  };
}

##############
# Store Data #
##############
sub process {
  my $self = shift;
  my $transactions = shift;
  my $oldProcessors = {};
  my $newProcessors = {};
  my $processorInfo = new PlugNPay::Processor::Route()->getProcessorPackageData();
  foreach my $transID (keys %{$transactions}) {
    my $transaction = $transactions->{$transID};
    my $gatewayAccount = new PlugNPay::GatewayAccount($transaction->getGatewayAccount());
    my $processor = ($transaction->getTransactionPaymentType() eq 'ach' ? $gatewayAccount->getCheckProcessor() : $gatewayAccount->getCardProcessor());
    if ($processorInfo->{$processor} =~ /PlugNPay::Processor::Route/) {
      $newProcessors->{$transID} = $transaction;
    } else {
      $oldProcessors->{$transID} = $transaction;
    }
  }

  my $responses = $self->oldProcess($oldProcessors);
  my $tempData = $self->newProcess($newProcessors);

  foreach my $id (keys %{$tempData}) {
    $responses->{$id} = $tempData->{$id};
  }

  return $responses;
}

# New Processing Method #
sub newProcess {
  my $self = shift;
  my $transactions = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $time = new PlugNPay::Sys::Time();
  my $responseHash = {};
  my $identifierHash = {};

  my $orderHash = {}; #HashRef of arrays of transactions
  foreach my $id (keys %{$transactions}) {
    my $transaction = $transactions->{$id};
    if (defined $orderHash->{$transaction->getGatewayAccount()}) {
      $orderHash->{$transaction->getGatewayAccount()}->addOrderTransaction($transaction);
    } else {
      my $order = new PlugNPay::Order();
      $order->setGatewayAccount($transaction->getGatewayAccount());
      $order->setCreationDate($time->nowInFormat('iso_gm'));
      $order->addOrderTransaction($transaction);
      $order->setMerchantOrderID($transaction->getOrderID());
      $orderHash->{$transaction->getGatewayAccount()} = $order;
    }

    $identifierHash->{$transaction->getPNPTransactioNID()} = $id;
  }

  foreach my $username (keys %{$orderHash}){
    my $order = $orderHash->{$username};
    my $isSuccess = $order->save();
    foreach my $transactionID (@{$order->getOrderTransactionIDs()}) {
      my $identifier = $identifierHash->{$transactionID};
      my $currentTransaction = $transactions->{$identifier};
      $currentTransaction->setPNPOrderID($order->getPNPOrderID());
      $responseHash->{$identifier}{'transaction'} = $currentTransaction;
      $responseHash->{$identifier}{'status'} = ($isSuccess ? 'success' : 'failure');
      $responseHash->{$identifier}{'date'} = $time->nowInFormat('iso_gm');
    }
  }
 
  return $responseHash;
}

# Old Processing Method #
sub oldProcess {
  my $self = shift;
  my $transactions = shift;
  my $logger = new PlugNPay::Logging::MessageLog();
  my $logMessage = '';
  my $fieldLengths = $self->getFieldLengths();

  my $insert = 'INSERT INTO trans_log 
        (username,orderid,card_name,
        card_addr,card_city,card_state,card_zip,
        card_country,publisheremail,card_number,card_exp,
        amount,trans_date,trans_time,trans_type,operation,
        result,enccardnumber,length,finalstatus,ipaddress,accttype,acct_code)
        VALUES ';

  my $parameters = '(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)';
  my @paramsArray = ();
  my @valuesToInsert;
  my $i = 1;

  my $responseHash = {};
  foreach my $transIdentifier ( keys %{$transactions} ) {
    my $trans = $transactions->{$transIdentifier};
    my $isSuccess = 1;
    my $contact = new PlugNPay::Contact();
    #Check Order ID
    my $orderID = $trans->getOrderID(); 

    if (!defined $orderID) {
      
      $orderID = new PlugNPay::Transaction::TransactionProcessor()->generateOrderID();
      $responseHash->{$transIdentifier}{'message'} = 'A transaction with Order ID ' . $orderID . ' was created and stored';
      $responseHash->{$transIdentifier}{'orderID'} = $orderID;

    } else {
      #Merchant passed Order ID
      if ($self->orderIDExists($orderID,  $trans->getGatewayAccount())){
        #We will not insert at the end of this because tried to insert existing order ID
        $isSuccess = 0;
        $responseHash->{$transIdentifier}{'message'} = 'Duplicate Order ID ' . $orderID . ' was found. Transaction was not stored!';
        $responseHash->{$transIdentifier}{'orderID'} = $orderID;

      } else {
        if (length($orderID) > $fieldLengths->{'ORDERID'}) {
          $isSuccess = 0;
          $responseHash->{$transIdentifier}{'message'} = 'Order ID ' . $orderID . ' was exceeds max length. Transaction was not stored!';
        } else {
          #Order ID that was passed by merchant is valid!
          $responseHash->{$transIdentifier}{'message'} = 'A transaction with Order ID ' . $orderID . ' was stored';
          $responseHash->{$transIdentifier}{'orderID'} = $orderID;
        }
      }
    }

    #Payment Check
    my $encCard;
    my $payType;
    my $cardNumber;
    my $expDate;
    if ($trans->getTransactionPaymentType() eq 'credit') {
      $payType = 'credit';  #used for accttype

      my $card = $trans->getCreditCard();
      $cardNumber = $card->getMaskedNumber(4,4,'*',2);  #card_number
      $expDate = $card->getExpirationMonth . '/' . $card->getExpirationYear(); #exp_date
      $encCard = $card->getYearMonthEncryptedNumber(); #Used for enccardnumber
      unless($card->verifyLength() && $card->verifyLuhn10() && !$card->isExpired()) { #If bad length, fails Luhn10 or is expired then cancell insert
        $isSuccess = 0;
        my $message = 'Bad Payment Information! ';
        $message .= 'Bad Card Number Length, ' if !$card->verifyLength();
        $message .= 'Luhn10 Failure, ' if !$card->verifyLuhn10();
        $message .= 'Card is expired, ' if $card->isExpired();
        $message .= 'Transaction ' . $transIdentifier . ' with Order ID: '. $orderID . ' was not stored!';
        $responseHash->{$transIdentifier}{'message'} = $message; 
      }

    } elsif ($trans->getTransactionPaymentType() eq 'ach') {
      my $ach = $trans->getOnlineCheck();

      $cardNumber = $ach->getMaskedNumber(4,4,'*',2); #card_num
      $encCard = $ach->encryptAccountInfoYearMonth();  #used for enccardnumber
      $payType = (defined $ach->getAccountType() ? $ach->getAccountType() : 'checking'); #accttype
      unless($ach->verifyABARoutingNumber()){
        $isSuccess = 0;
        $responseHash->{$transIdentifier}{'message'} = 'Invalid routing number, transaction '. $transIdentifier . ' with Order ID: ' . $orderID . ' could not be stored.';
      }
    } else {
      $isSuccess = 0;
      $responseHash->{$transIdentifier}{'message'} = 'Bad Payment Type, Transaction ' . $transIdentifier . ' with Order ID: ' . $orderID . ' was not inserted!';
    }

    $trans->setOrderID($orderID);

    my $time = new PlugNPay::Sys::Time();


    #  Special length check for fail/chop status
    if (length($encCard) > $fieldLengths->{'ENCCARDNUMBER'}) {
      $isSuccess = 0;
      $responseHash->{$transIdentifier}{'message'} = 'Card Encryption Error, Transaction '. $transIdentifier . ' with Order ID: ' . $orderID . " was not inserted!";
    }

    if (length($trans->getTransactionAmount()) > $fieldLengths->{'AMOUNT'}) {
      $isSuccess = 0;
      $responseHash->{$transIdentifier}{'message'} = 'Transaction amount exceeded limit! Transaction '. $transIdentifier . ' with Order ID: ' . $orderID . " was not inserted!";
    }

    if (length($trans->getGatewayAccount()) > $fieldLengths->{'USERNAME'}) {
      $isSuccess = 0;
      $responseHash->{$transIdentifier}{'message'} = 'Invalid account! Transaction '. $transIdentifier . ' with Order ID: ' . $orderID . " was not inserted!";
    }

    # try and put the card data into... carddata.
    eval {
      my $cd = new PlugNPay::CardData();
      $cd->insertOrderCardData({username => $trans->getGatewayAccount(), 
                                 orderID => $orderID, 
                                cardData => $encCard});
    };

    # if insert into carddata failed then it was not successful. (duh)
    if ($@) {
      $isSuccess = 0;
    }

    if ($isSuccess) {
      $contact = $trans->getBillingInformation();
      push @valuesToInsert, $trans->getGatewayAccount();  
      push @valuesToInsert, $orderID;  
      #Insert contact info
      push @valuesToInsert, substr($contact->getFullName(),0,$fieldLengths->{'CARD_NAME'});      #card_name
      push @valuesToInsert, substr($contact->getAddress1(),0,$fieldLengths->{'CARD_ADDR'});      #card_addr
      push @valuesToInsert, substr($contact->getCity(),0,$fieldLengths->{'CARD_CITY'});          #card_city
      push @valuesToInsert, substr($contact->getState(),0,$fieldLengths->{'CARD_STATE'});         #card_state
      push @valuesToInsert, substr($contact->getPostalCode(),0,$fieldLengths->{'CARD_ZIP'});    #card_zip
      push @valuesToInsert, substr($contact->getCountry(),0,$fieldLengths->{'CARD_COUNTRY'});       #card_country
      push @valuesToInsert, substr($contact->getEmailAddress(),0,$fieldLengths->{'PUBLISHEREMAIL'});  #publisheremail
      
      push @valuesToInsert, substr($cardNumber,0,$fieldLengths->{'CARD_NUMBER'});
      push @valuesToInsert, substr($expDate,0,$fieldLengths->{'CARD_EXP'});
      #Insert loggin info

      push @valuesToInsert, $trans->getTransactionAmount(); 
      push @valuesToInsert, substr($time->inFormat('yyyymmdd'),0,$fieldLengths->{'TRANS_DATE'}); #Insert Trans_Date
      push @valuesToInsert, substr($time->inFormat('gendatetime'),0,$fieldLengths->{'TRANS_TIME'}); #Insert Trans_Time

      push @valuesToInsert,'storedata';  #Transaciton Type
      push @valuesToInsert,'storedata';  #Operation
      push @valuesToInsert,'success';    #Result

      push @valuesToInsert, '';                #enccardnumber
      push @valuesToInsert, length($encCard);  #length

      push @valuesToInsert, 'success';   #Final Status
      push @valuesToInsert, $ENV{'REMOTE_ADDR'};  #IP Address

      push @valuesToInsert, substr($payType,0,$fieldLengths->{'ACCTTYPE'});  #accttype
      push @valuesToInsert, substr($trans->getAccountCode(1),0,$fieldLengths->{'ACCT_CODE'}); #acct_code
     
      push @paramsArray,$parameters;
    }

    #Logging
    $logMessage = 'MERCHANT: ' . $trans->getGatewayAccount() . ', ORDER ID: ' . $orderID . ', MASKED NUMBER: ' . $cardNumber;
    $logMessage .= ', CARD NAME: ' . $contact->getFullName() . ', AMOUNT: ' . $trans->getTransactionAmount() . ', STORE TIME: ' . $time->inFormat('db_local');

    unless($isSuccess) {
      $logMessage .= ', STATUS: Failed'; 
    } else {
      $logMessage .= ', STATUS: Successful';
    }

    $logMessage .= ', MESSAGE: ' . $responseHash->{$transIdentifier}{'message'};
    $logger->log($logMessage,{'vendor'=>'PlugNPay','context'=>'REST API'});

    $responseHash->{$transIdentifier}{'transaction'} = $trans;
    $responseHash->{$transIdentifier}{'status'} = ($isSuccess ? 'success' : 'failure');
    $responseHash->{$transIdentifier}{'date'} = $time->inFormat('iso_gm');
    #increment transactions inserted
    $i++;
  }
  $insert .= join(',',@paramsArray);
  if (@paramsArray > 0 ) {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpdata',$insert);
    $sth->execute(@valuesToInsert) or die $DBI::errstr; 
  }

  return $responseHash;
}

sub orderIDExists {
  my $self = shift;
  my $orderID = shift;
  my $gatewayAccount = shift;

  # the following is so that it can be called without having an instance of Vault
  if (!defined $orderID) {
    if (ref($self)) {
      $orderID = $self->getOrderID();
    } else {
      $orderID = $self;
    }
  }

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpdata');
  my $sth = $dbh->prepare(q/
    SELECT count(orderid) as `exists`
    FROM trans_log
    WHERE orderid = ?
    AND username = ?
  /);

  $sth->execute($orderID, $gatewayAccount);

  my $results = $sth->fetchall_arrayref({});
  if ($results && $results->[0]) {
    return ($results->[0]{'exists'}>0 );
  }
}

sub setOrderID {
  my $self = shift;
  my $orderid = shift;
  $self->{'orderid'} = $orderid;
}

sub getOrderID {
  my $self = shift;
  return $self->{'orderid'};
}

sub getFieldLengths {
  my $self = shift;
  my $lengths = $self->{'translog_field_lengths'};

  if (!defined $self->{'translog_field_lengths'}) {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
                           SELECT field_name,max_size
                           FROM database_field_size
                           WHERE database_name = ? AND table_name = ?
                           /);
    $sth->execute('pnpdata','trans_log') or die $DBI::errstr;
  
    my $rows = $sth->fetchall_arrayref({});
    my $fields = {};

    foreach my $row (@{$rows}){
      my $field = $row->{'field_name'};
      $fields->{$field} = $row->{'max_size'};
    }
    $lengths = $fields;
  }

  return $lengths;
}

1;
