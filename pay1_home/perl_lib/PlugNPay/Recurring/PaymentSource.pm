package PlugNPay::Recurring::PaymentSource;

use strict;
use PlugNPay::Token;
use PlugNPay::CardData;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Recurring::BillMember;
use PlugNPay::CreditCard::Encryption;
use PlugNPay::Die;
use PlugNPay::Util::Cache::LRUCache;

# for compatibility with stuff stored previously to fix for account type
my $typeMap = {
  'card' => 'credit',
  'ach' => 'checking', # default to checking if specific type is not specified.
};

our $cache;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!$cache) {
    $cache = new PlugNPay::Util::Cache::LRUCache();
  }

  return $self;
}

sub setMerchantId {
  my $self = shift;
  my $merchantId = shift;
  $merchantId =~ s/[^0-9]//g;
  $self->{'merchantId'} = $merchantId;
}

sub getMerchantId {
  my $self = shift;
  return $self->{'merchantId'};
}

sub setCustomer {
  my $self = shift;
  my $customer = lc shift;
  $self->{'customer'} = $customer;
}

sub getCustomer {
  my $self = shift;
  return lc $self->{'customer'};
}

sub getSHACardNumber {
  my $self = shift;
  return $self->getHashedNumber();
}

sub getHashedNumber {
  my $self = shift;
  my $pd = $self->_hamburgerHelper();
  return $pd->getCardHash() if $pd;
}

sub getCardNumber {
  my $self = shift;
  return $self->{'cardNumber'};
}

sub setCardNumber {
  my $self = shift;
  my $cardNumber = shift;
  $self->{'cardNumber'} = $cardNumber;
}

sub getExpMonth {
  my $self = shift;
  return $self->getExpirationMonth();
}

sub getExpirationMonth {
  my $self = shift;
  return $self->{'expMonth'};
}

sub setExpMonth {
  my $self = shift;
  my $month = shift;
  $self->setExpirationMonth($month);
}

sub setExpirationMonth {
  my $self = shift;
  my $expMonth = shift;
  $self->{'expMonth'} = $expMonth;
}

sub getExpYear {
  my $self = shift;
  return $self->getExpirationYear();
}

sub getExpirationYear {
  my $self = shift;
  return $self->{'expYear'};
}

sub setExpYear {
  my $self = shift;
  my $year = shift;
  $self->setExpirationYear($year);
}

sub setExpirationYear {
  my $self = shift;
  my $expYear = shift;
  $self->{'expYear'} = $expYear;
}

sub setLength {
  my $self = shift;
  # stub to not break anything
}

sub getLength {
  my $self = shift;
  # stub to not break anything
}

sub getEncCardNumber {
  my $self = shift;
  my $encCardNumber;
  my $pd = $self->_hamburgerHelper();
  return $pd->getPerpetualEncryptedNumber() if $pd;
}

sub setEncCardNumber {
  my $self = shift;
  # stub so it doesn't die just yet.
}

sub getMaskedNumber {
  my $self = shift;
  my $encCardNumber;
  my $pd = $self->_hamburgerHelper();
  return $pd->getMaskedNumber() if $pd;
}

sub _hamburgerHelper {
  my $self = shift;
  my $pd;
  if ((grep { $self->getPaymentSourceType() eq $_ } ('checking','savings')) > 0) {
    $pd = new PlugNPay::OnlineCheck();
    $pd->setRoutingNumber($self->{'routingNumber'});
    $pd->setAccountNumber($self->{'accountNumber'});
  } elsif ((grep { $self->getPaymentSourceType() eq $_ } ('credit')) > 0) {
    $pd = new PlugNPay::CreditCard();
    $pd->setNumber($self->{'cardNumber'});
  } elsif ((grep { $self->getPaymentSourceType() eq $_ } ('check','invalid')) == 0) {
    die "Invalid payment type.";
  }

  return $pd;
}

sub setToken {
  my $self = shift;
  my $token = shift;
  $self->{'token'} = $token; # used for adjustment
}

sub getToken {
  my $self = shift;

  # if token is not set, load it before responding.
  if (!defined $self->{'token'}) {
    if (defined $self->{'cardNumber'}) {
      my $cc = new PlugNPay::CreditCard($self->{'cardNumber'});
      $self->{'token'} = $cc->getToken();
    } elsif (defined $self->{'routingNumber'} && defined $self->{'accountNumber'}) {
      my $oc = new PlugNPay::OnlineCheck();
      $self->{'token'} = $oc->getToken($self->{'routingNumber'} . ' ' . $self->{'accountNumber'});
    }
  }

  return $self->{'token'};
}

sub getPaymentSourceType {
  my $self = shift;
  my $type = $self->{'type'};
  return $typeMap->{$type} || $type;
}

sub setPaymentSourceType {
  my $self = shift;
  my $type = lc shift;
  $type = $typeMap->{$type} || $type;
  $self->{'type'} = $type;
}

sub isBusiness {
  my $self = shift;
  return $self->{'isBusiness'}
}

sub setIsNotBusiness {
  my $self = shift;
  $self->{'isBusiness'} = 0;
}

sub setIsBusiness {
  my $self = shift;
  $self->{'isBusiness'} = 1;
}

sub setRoutingNumber {
  my $self = shift;
  my $routingNumber = shift;
  $routingNumber =~ s/[^0-9]//g;
  $self->{'routingNumber'} = $routingNumber;
}

sub getRoutingNumber {
  my $self = shift;
  return $self->{'routingNumber'};
}

sub setAccountNumber {
  my $self = shift;
  my $accountNumber = shift;
  $accountNumber =~ s/[^0-9]//g;
  $self->{'accountNumber'} = $accountNumber;
}

sub getAccountNumber {
  my $self = shift;
  return $self->{'accountNumber'};
}

sub setOrderID {
  my $self = shift;
  my $orderID = shift;
  $self->{'orderID'} = $orderID;
}

sub getOrderID {
  my $self = shift;
  return $self->{'orderID'};
}

sub getErrorType {
  my $self = shift;
  return $self->{'errorType'};
}

sub clear {
  my $self = shift;
  $self->{'routingNumber'} = '';
  $self->{'accountNumber'} = '';
  $self->{'isBusiness'} = '';
  $self->{'token'} = '';
  $self->{'expMonth'} = '';
  $self->{'expYear'} = '';

}

sub update {
  my $self = shift;
  my $options = { suppressAlert => 1, suppressError => 1 };
  my $iid = new PlugNPay::GatewayAccount::InternalID();
  my $merchant = $iid->getUsernameFromId($self->getMerchantId());;
  my $customer = $self->getCustomer();
  $self->updatePaymentSource($merchant, $customer, $options);
}

sub updatePaymentSource {
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'recurring'});

  my $self = shift;
  my $merchant = shift;
  my $customer = lc shift;
  my $optionsOrSuppressAlert = shift;

  my ($suppressAlert, $suppressError);
  if (ref($optionsOrSuppressAlert) eq 'HASH') {
    $suppressAlert = $optionsOrSuppressAlert->{'suppressAlert'};
    $suppressError = $optionsOrSuppressAlert->{'suppressError'};
  } else {
    $suppressAlert = $optionsOrSuppressAlert;
  }

  my $dbs = new PlugNPay::DBConnection();

  my $currentPaymentSource = new PlugNPay::Recurring::PaymentSource();
  # do not used passed in options for this.
  $currentPaymentSource->loadPaymentSource($merchant, $customer, { suppressAlert => 1, suppressError => 1 });
  if ($currentPaymentSource->getErrorType() eq 'failure') {
    die('Failed to load current payment data.');
  }

  my $txDb = ($merchant eq 'pnpbilling' ? 'pnpmisc' : $merchant);

  my ($errorMsg, $performAuth);
  my $billStatus = '';

  eval {
    $dbs->begin($txDb);

    my ($encCardNumber, $length, $shaCardNumber, $masked, $exp);

    if ($self->getPaymentSourceType() eq 'credit') {
      if ($currentPaymentSource->getPaymentSourceType() eq $self->getPaymentSourceType() &&
          $self->{'cardNumber'} eq $currentPaymentSource->getMaskedNumber()) { # replace masked number with actual card number if it's the same
        $self->{'cardNumber'} = $currentPaymentSource->getCardNumber();
      }
      my $cc = new PlugNPay::CreditCard($self->{'cardNumber'});
      $cc->setExpirationMonth($self->{'expMonth'});
      $cc->setExpirationYear($self->{'expYear'});
      if ( !$cc->verifyLength() ) {
        $errorMsg = "Failed to update payment source. Invalid card length.";
        die $errorMsg;
      } elsif ( !$cc->verifyLuhn10() ) {
        $errorMsg = "Failed to update payment source. Invalid card number (luhn10 failure).";
        die $errorMsg;
      } elsif ( $cc->isExpired() ) {
        $errorMsg = "Failed to update payment source. Expired.";
        die $errorMsg;
      }

      $masked = $cc->getMaskedNumber();
      $exp = sprintf("%02d/%02d", $cc->getExpirationMonth(), $cc->getExpirationYear());
      $shaCardNumber = $cc->getEncHash();

      $encCardNumber = $cc->getPerpetualEncryptedNumber();
      if ($self->getCardNumber() ne $currentPaymentSource->getCardNumber()) {
        $performAuth = 1;
      }
    } elsif ((grep { $self->getPaymentSourceType() eq $_ } ('checking','savings','invalid')) > 0) {
      my $oc = new PlugNPay::OnlineCheck();
      $oc->setABARoutingNumber($self->{'routingNumber'});
      $oc->setAccountNumber($self->{'accountNumber'});

      if (!$oc->verifyABARoutingNumber()) {
        $errorMsg = "Failed to update payment source. Invalid routing number.";
        die $errorMsg;
      }
      $encCardNumber =  $oc->getPerpetualEncryptedNumber();

      $masked = $oc->getMaskedNumber();
      $shaCardNumber = $oc->getEncHash();
    } else {
      $errorMsg = "Failed update payment source. Invalid payment type";
      die $errorMsg;
    }

    my $updateInfo = {
      merchant => $merchant,
      accountType => $self->getPaymentSourceType(),
      encCardNumber => $encCardNumber,
      masked => $masked,
      expiration => $exp,
      hashed => $shaCardNumber,
      customer => $customer,
      isBusiness => $self->isBusiness()
    };

    eval {
      if ($merchant eq 'pnpbilling') {
        $self->gatewayAccountUpdatePaymentInfo($updateInfo);
      } else {
        $self->recurringDbUpdatePaymentInfo($updateInfo);
      }
    };

    if ($@) {
      $errorMsg = sprintf('[%s] failed to update info for customer [%s], error: [%s]', $merchant, $customer, $@);
      $logger->log({
        message => $errorMsg,
        merchant => $merchant,
        customer => $customer,
        error => $@
      });
      die $errorMsg;
    }

    # 0 auth is required by VISA
    my ($orderID, $transID);
    if ($self->getPaymentSourceType() eq 'credit' && $performAuth) {
      $logger->log({
        message => sprintf('[%s] doing avs check for customer [%s]', $merchant, $customer),
        merchant => $merchant,
        customer => $customer,
        action => 'avs check'
      });

      my $biller = new PlugNPay::Recurring::BillMember();
      my $response = $biller->billMember($merchant, $customer, {
        'amount' => 0.00,
        'description' => 'Add payment source zero auth.',
        'recInit' => 1
      });

      $response ||= {}; # prevents warnings

      if (!$response->{'status'}) {
        $errorMsg = $response->{'errorMessage'} || "Failed to process transaction.";
        die $errorMsg;
      } elsif ($response->{'transactionStatus'} ne 'success') {
        $errorMsg = $response->{'message'};
        die $errorMsg;
      }

      $orderID = $response->{'transactionDetails'}{'orderID'};
      $transID = $response->{'transactionDetails'}{'transactionID'};
      $billStatus = $response->{'billed'};
    } else {
      my $reason;

      if (!$performAuth) {
        $reason = "condition to perform auth not met";
      }

      if ($self->getPaymentSourceType() ne 'credit') {
        $reason = sprintf('payment source type is [%s]',$self->getPaymentSourceType());
      }

      $logger->log({
        message => sprintf('[%s] skipping avs check for customer [%s].  reason: [%s]', $merchant, $customer, $reason),
        merchant => $merchant,
        customer => $customer
      });
    }

    # yes.. transaction id in acct code 4, undef forces COALESCE to use current value in the queries later on in this file
    my $updateInfo = {
      merchant => $merchant,
      orderId => $orderID || undef,
      transId => $transID || undef,
      customer => $customer
    };

    if ($merchant eq 'pnpbilling') {
      $self->gatewayAccountUpdateOrderIdAndAcctCode4($updateInfo);
    } else {
      $self->recurringDbUpdateOrderIdAndAcctCode4($updateInfo);
    }
  };

  if ($@) {
    my $e1 = $@;
    eval {
      $dbs->rollback($txDb);
      $currentPaymentSource->save();
    };

    if ($@) {
      $e1 .= '  Rollback FAILED!';
    }

    if (!$errorMsg) {
      $errorMsg = 'Failed to update payment source.';
    }

    if ($e1) {
      $logger->log({
        message => sprintf('[%s] failed to update payment source for customer [%s],  error: [%s]', $merchant, $customer, $e1),
        status => 'FAILURE'
      });
    }

    return { 'status' => 0, 'errorMessage' => $errorMsg, billedStatus => $billStatus };
  } else {
    $dbs->commit($txDb);
    $logger->log({
      message => sprintf('[%s] committed changes to payment source for customer [%s]', $merchant, $customer),
      masked  => $self->getMaskedNumber(),
      expirationYear  => $self->getExpirationYear(),
      expirationMonth => $self->getExpirationMonth(),
      accountType => $self->getPaymentSourceType(),
      status => 'SUCCESS'
    });
  }

  return {
    status => 1 ,
    billedStatus => $billStatus
  };
}

sub load {
  my $self = shift;
  my $options = { suppressAlert => 1, suppressError => 1 };

  my $merchantId = $self->getMerchantId();
  my $customer = $self->getCustomer();
  if ($cache->contains("$merchantId:$customer")) {
  }

  my $iid = new PlugNPay::GatewayAccount::InternalID();
  my $merchant = $iid->getUsernameFromId($self->getMerchantId());
  my $customer = $self->getCustomer();
  $self->loadPaymentSource($merchant, $customer, $options);

  $self->cache();
}

sub loadPaymentSource {
  my $self = shift;
  my $merchant = shift;
  my $customer = lc shift;
  my $optionsOrSuppressAlert = shift;

  my ($suppressAlert, $suppressError, $lazyTokenLoad);
  if (ref($optionsOrSuppressAlert) eq 'HASH') {
    $suppressAlert = $optionsOrSuppressAlert->{'suppressAlert'};
    $suppressError = $optionsOrSuppressAlert->{'suppressError'};
    $lazyTokenLoad = $optionsOrSuppressAlert->{'lazyTokenLoad'};
  } else {
    $suppressAlert = $optionsOrSuppressAlert;
  }

  my $iid = new PlugNPay::GatewayAccount::InternalID();
  my $merchantId = $iid->getIdFromUsername($merchant);
  $self->setMerchantId($merchantId);
  $self->setCustomer($customer);

  eval {
    my $paymentData;
    if ($merchant eq 'pnpbilling') {
      $paymentData = $self->gatewayAccountLoadPaymentInfo({ customer => $customer, lazyTokenLoad => $lazyTokenLoad });
    } else {
      $paymentData = $self->recurringDbLoadPaymentInfo({ merchant => $merchant, customer => $customer });
    }

    eval {
      $self->_setPaymentSourceFromData($paymentData);
    };

    if ($@) {
      my $logger = new PlugNPay::Logging::DataLog({'collection' => 'attendant'});
      $logger->log({error => $@});
    }

  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'recurring'});
    $logger->log({ status => 'FAILURE', message => 'Failed loading payment source.', error => $@ });
    return 0;
  }

  return 1;
}

sub _setPaymentSourceFromData {
  my $self = shift;
  my $paymentData = shift;

  my $set = 0;

  $self->setPaymentSourceType($paymentData->{'accttype'}); # calling the setter filters it through the valid value map
  $self->{'isBusiness'} = $paymentData->{'isBusiness'};

  if (grep { $self->{'type'} eq $_} ('checking','savings','invalid')) {
    my $oc = new PlugNPay::OnlineCheck();
    if ($paymentData->{'enccardnumber'}) {
      $oc->setAccountFromEncryptedNumber($paymentData->{'enccardnumber'});
      $self->{'routingNumber'} = $oc->getRoutingNumber();
      $self->{'accountNumber'} = $oc->getAccountNumber();
      $set = 1;
    }
  } elsif ($self->{'type'} eq 'credit' || ($self->{'type'} eq 'invalid')) {
    my $cc = new PlugNPay::CreditCard();
    if ($paymentData->{'enccardnumber'}) {
      $cc->setNumberFromEncryptedNumber($paymentData->{'enccardnumber'});
      $self->{'cardNumber'} = $cc->getNumber();
      my ($expMonth, $expYear) = split('/', $paymentData->{'exp'});
      my $expMonth = sprintf("%02d",$expMonth);
      $self->{'expMonth'} = $expMonth;
      $self->{'expYear'} = $expYear;
      $set = 1;
    }
  }

  $self->{'orderID'} = $paymentData->{'orderid'};

  return $set;
}
sub deletePaymentSource {
  my $self = shift;
  my $merchant = shift;
  my $customer = lc shift;
  my $options = shift || {};
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'module_recurring_paymentsource'});
  my $result = 0;

  my $currentPaymentSource = new PlugNPay::Recurring::PaymentSource();
  $currentPaymentSource->loadPaymentSource($merchant, $customer, { suppressAlert => 1, suppressError => 1 });
  if ($currentPaymentSource->getErrorType() eq 'failure') {
    die('Failed to load current payment data.');
  }

  $logger->log({ message => 'deletePaymentSource() called', merchant => $merchant, customer => $customer });


  my $dbs = new PlugNPay::DBConnection();
  my $beginSuccessful;
  my $txDb = ($merchant eq 'pnpbilling' ? 'pnpmisc' : $merchant);

  # clear data in recurring table
  eval {
    $beginSuccessful = $dbs->begin($txDb);
    if ($merchant eq 'pnpbilling') {
      $self->gatewayAccountDeletePaymentInfo({ customer => $customer })
    } else {
      $self->recurringDbDeletePaymentInfo({ merchant => $merchant, customer => $customer });
    }
  };

  # check if there was an error in clearing data in table
  if ($@) {
    chomp $@;
    $logger->log({ status => 'FAILURE', merchant => $merchant, customer => $customer, message => 'Failed to remove payment data from recurring customer: ' . $@});
  } else {
    $result = 1;
    $self->clear();
  }

  # if the database connected, begin was successful, and deleteing the data from the microservice was successful, commit, otherwise, rollback
  eval {
    if ($beginSuccessful) { # can only happen if db connection was successsful
      if ($result) {
        $dbs->commit($txDb);
      } else {
        $dbs->rollback($txDb);
        $currentPaymentSource->save();
      }
    }
  };

  if ($@) {
    chomp $@;
    $logger->log({ status => 'FAILURE', merchant => $merchant, customer => $customer, message => 'Failed to delete payment source: ' . $@});
    $result = 0;
  }

  return $result;
}

sub save {
  my $self = shift;
  my $merchantId = $self->getMerchantId();
  my $iid = new PlugNPay::GatewayAccount::InternalID();
  my $merchant = $iid->getUsernameFromId($merchantId);
  my $customer = $self->getCustomer();

  my ($encCardNumber, $hashedCardNumber, $maskedCardNumber) = ('','','');
  if ((grep { $self->getPaymentSourceType() eq $_ } ('credit','checking','savings','invalid')) > 0) {
    # invalid might die, so don't die!  just let them remain blank
    eval {
      $encCardNumber = $self->getEncCardNumber();
      $hashedCardNumber = $self->getHashedNumber();
      $maskedCardNumber = $self->getMaskedNumber();
    };
  }

  my $updateInfo = {
    merchant => $merchant,
    accountType => $self->getPaymentSourceType(),
    encCardNumber => $encCardNumber,
    masked => $maskedCardNumber,
    expiration => sprintf('%02d/%02d', $self->getExpMonth(), $self->getExpYear()),
    hashed => $hashedCardNumber,
    customer => $customer,
    isBusiness => $self->isBusiness()
  };

  if ($merchant eq 'pnpbilling') {
    $self->gatewayAccountUpdatePaymentInfo($updateInfo);
  } else {
    $self->recurringDbUpdatePaymentInfo($updateInfo);
  }
}

## recurring customer databases
sub recurringDbLoadPaymentInfo {
  my $self = shift;
  my $input = shift;
  my $merchant = $input->{'merchant'};
  my $customer = $input->{'customer'};

  my $dbs = new PlugNPay::DBConnection();

  my $commcardtypeSQL = '';
  my $columnInfo = $dbs->getColumnsForTable({ database => $merchant, table => 'customer'});
  if ($columnInfo->{'commcardtype'}) {
    $commcardtypeSQL = ', commcardtype';
  }

  my $result = $dbs->fetchallOrDie($merchant, qq/
    SELECT exp, orderid, accttype $commcardtypeSQL
    FROM customer
    WHERE LOWER(username) = LOWER(?) LIMIT 1
  /, [$customer], {});

  my $row = $result->{'result'}[0];

  my $cds = new PlugNPay::CardData();
  my $enccardnumber = $cds->getRecurringCardData({ username => $merchant, customer => $customer });
  $self->{'errorType'} = $cds->getErrorType();
  $row->{'enccardnumber'} = $enccardnumber;
  $row->{'isBusiness'} = ($row->{'commcardtype'} eq 'business' ? 1 : 0);
  delete $row->{'commcardtype'};

  return $row;
}

sub recurringDbUpdatePaymentInfo {
  my $self = shift;
  my $input = shift;
  my $merchant = $input->{'merchant'};
  my $accountType = $input->{'accountType'};
  my $encCardNumber = $input->{'encCardNumber'};
  my $masked = $input->{'masked'};
  my $expiration = $input->{'expiration'};
  my $hashed = $input->{'hashed'};
  my $customer = $input->{'customer'};

  $merchant =~ s/[^a-z0-9]//g;

  my $cds = new PlugNPay::CardData();

  my $cardDataData = {
    username => $merchant,
    cardData => $encCardNumber,
    customer => $customer,
    suppressError => 1
  };

  my $response;
  if ($encCardNumber eq '') {
    $response = $cds->removeRecurringCardData($cardDataData);
  } else {
    $response = $cds->insertRecurringCardData($cardDataData);
  }

  if ($cds->getErrorType eq 'failure') {
    die("Failed to update payment source. Error from card data.");
  }

  my $commcardtype = ($self->isBusiness() ? 'business' : '');
  my $dbs = new PlugNPay::DBConnection();

  # I know I can do a single if here but it's easier to follow with the check
  # on $commcardtypeSQL
  my $commcardtypeSQL = '';
  my $columnInfo = $dbs->getColumnsForTable({ database => $merchant, table => 'customer'});
  if ($columnInfo->{'commcardtype'}) {
    $commcardtypeSQL = ', commcardtype = ?';
  }

  my $values = [$accountType, $masked, $expiration, $hashed, ""];
  push @{$values}, $commcardtype if ($commcardtypeSQL ne '');
  push @{$values}, $customer;

  $dbs->executeOrDie($merchant, qq/
    UPDATE customer
       SET accttype = ?,
           cardnumber = ?,
           exp = ?,
           shacardnumber = ?,
           enccardnumber = ?
           $commcardtypeSQL
     WHERE LOWER(username) = LOWER(?)
  /, $values);
}

sub recurringDbUpdateOrderIdAndAcctCode4 {
  my $self = shift;
  my $info = shift;

  my $merchant = lc $info->{'merchant'};
  my $orderId = $info->{'orderId'};
  my $transId = $info->{'transId'};
  my $customer = $info->{'customer'};

  $merchant =~ s/[^a-z0-9]//g;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie($merchant, q/
    UPDATE customer
       SET orderid    = COALESCE(?,orderid),
           acct_code4 = COALESCE(?,acct_code4)
     WHERE LOWER(username) = LOWER(?)
  /, [$orderId, $transId, $customer]);
}

sub recurringDbDeletePaymentInfo {
  my $self = shift;
  my $input = shift;
  my $merchant = $input->{'merchant'};
  my $customer = $input->{'customer'};

  $merchant =~ s/[^a-z0-9]//g;

  my $dbs = new PlugNPay::DBConnection();

  my $commcardtypeSQL = '';
  my $columnInfo = $dbs->getColumnsForTable({ database => $merchant, table => 'customer'});
  if ($columnInfo->{'commcardtype'}) {
    $commcardtypeSQL = ', commcardtype = ""';
  }

  $dbs->executeOrDie($merchant, qq/
    UPDATE customer
    SET shacardnumber = "",
        cardnumber = "",
        exp = "",
        orderid = "",
        accttype = ""
        $commcardtypeSQL
    WHERE LOWER(username) = LOWER(?)
  /, [$customer]);
}

sub fromRecurringDbPrefetch {
  my $self = shift;
  my $input = shift;
  my $merchant = $input->{'merchant'};
  my $customer = $input->{'customer'};

  my $iid = new PlugNPay::GatewayAccount::InternalID();
  my $merchantId = $iid->getIdFromUsername($merchant);

  my $cds = new PlugNPay::CardData();
  my $enccardnumber = $cds->getRecurringCardData({ username => $merchant, customer => $customer });
  $self->{'errorType'} = $cds->getErrorType();
  $input->{'enccardnumber'} = $enccardnumber;
  $input->{'isBusiness'} = ($input->{'commcardtype'} eq 'business' ? 1 : 0);
  delete $input->{'commcardtype'};

  $self->setMerchantId($merchantId);
  $self->setCustomer($customer);
  $self->_setPaymentSourceFromData($input);

  $self->cache();
}

sub cache {
  my $self = shift;
  my $merchantId = $self->getMerchantId();
  my $customer = $self->getCustomer();
  $cache->set("$merchantId:$customer", $self);
}

## customer accounts.
sub gatewayAccountLoadPaymentInfo {
  my $self = shift;
  my $input = shift;
  my $customer = $input->{'customer'};
  my $lazyTokenLoad = $input->{'lazyTokenLoad'};

  my $returnValues = {};

  my $dbs = new PlugNPay::DBConnection();
  my $result = $dbs->fetchallOrDie('pnpmisc', q/
    SELECT
      accttype,
      card_number,
      exp_date as exp,
      chkaccttype
    FROM customers
    WHERE LOWER(username) = LOWER(?)
  /, [$customer], {});
  my $row = $result->{'result'}[0];

  my $cd = new PlugNPay::CardData();
  my $enccardnumber = $cd->getRecurringCardData({ username => 'pnpbilling', customer => $customer });
  $self->{'errorType'} = $cd->getErrorType();
  $row->{'enccardnumber'} = $enccardnumber;
  $row->{'isBusiness'} = ($row->{'chkaccttype'} eq 'CCD' ? 1 : 0);

  return $row;
}


sub gatewayAccountUpdatePaymentInfo {
  my $self = shift;
  my $input = shift;
  my $accountType = $input->{'accountType'};
  my $encCardNumber = $input->{'encCardNumber'};
  my $masked = $input->{'masked'};
  my $expiration = $input->{'expiration'};
  my $customer = $input->{'customer'};
  my $isBusiness = $input->{'isBusiness'};
  my $merchant = 'pnpbilling';

  my $cds = new PlugNPay::CardData();

  my $cardDataData = {
    username => $merchant,
    cardData => $encCardNumber,
    customer => $customer,
    suppressError => 1
  };

  my $response;
  if ($encCardNumber eq '') {
    $response = $cds->removeRecurringCardData($cardDataData);
  } else {
    $response = $cds->insertRecurringCardData($cardDataData);
  }

  if ($response !~ /success/i) {
    die("Failed to update payment source. Error from card data.");
  }

  my $chkaccttype = ($isBusiness ? 'CCD' : 'PPD');

  $accountType ||= '';

  my $dbs = new PlugNPay::DBConnection();
  my $updateData = [$accountType, $masked, $expiration, $chkaccttype, $customer];

  $dbs->executeOrDie('pnpmisc', q/
    UPDATE customers
       SET accttype = ?,
           card_number = ?,
           exp_date = ?,
           chkaccttype = ?
     WHERE LOWER(username) = LOWER(?)
  /, $updateData);
}

sub gatewayAccountUpdateOrderIdAndAcctCode4 {
  my $self = shift;
  my $info = shift;
  my $customer = $info->{'customer'};
  my $orderId = $info->{'orderId'};
  my $transId = $info->{'transId'};

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpmisc', q/
    UPDATE customers
       SET orderid   = COALESCE(?,orderid),
           acctcode4 = COALESCE(?,acctcode4)
     WHERE LOWER(username) = LOWER(?)
  /, [$orderId, $transId, $customer]);
}

sub gatewayAccountDeletePaymentInfo {
  my $self = shift;
  my $input = shift;
  my $customer = $input->{'customer'};
  my $accountType = $self->getPaymentSourceType();

  $accountType ||= ''; # set to empty string if undefined

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpmisc', q/
    UPDATE customers
    SET card_number = "", exp_date = "", accttype = ?, orderid = "", chkaccttype = "", acctcode4 = ""
    WHERE LOWER(username) = ?
  /,[$accountType,$customer]);

  # best effort, perhaps an auditing script can be written to ensure there's no erroneous data left behind
  my $cd = new PlugNPay::CardData();
  eval {
    $cd->removeRecurringCardData({ username => 'pnpbilling', customer => $customer })
  };
}

1;
