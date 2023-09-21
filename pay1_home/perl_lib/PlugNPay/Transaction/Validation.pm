package PlugNPay::Transaction::Validation;

use strict;
use warnings FATAL => 'all';
use PlugNPay::Die;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::Loader;
use PlugNPay::Util::Array qw(inArray);

#so it would need to take the input, query the db and validate a few important things like merchant, amount, maybe shipping info
sub validateTransactionForEmailing {
  my $transactionInput = shift;
  if (!defined $transactionInput || ref($transactionInput) ne 'HASH') {
    die 'invalid transaction input sent to validation for emailing';
  }

  # Parse input
  my $amount = $transactionInput->{'amount'};
  my $merchant = $transactionInput->{'gatewayAccount'};
  my $status = $transactionInput->{'status'};
  my $orderId = $transactionInput->{'merchantOrderId'};
  my $shippingInformation = $transactionInput->{'shippingInformation'};
  my $shouldCompareShipping = $transactionInput->{'shouldCompareShipping'};

  # Create load data
  my $loadQueryInputHash = {
    'gatewayAccount' => $merchant,
    'orderID'  => $orderId
  };
  
  # Load transaction data from database
  my $loader = new PlugNPay::Transaction::Loader({'loadPaymentInfo' => 0});
  my $loadedTransactions = $loader->load($loadQueryInputHash);
  my $loadedTransactionsForMerchant = $loadedTransactions->{$merchant};
  if (ref($loadedTransactionsForMerchant) ne 'HASH') {
    logValidationFailure({
      'message'  => 'unable to load transactions for merchant and orderId combination',
      'orderId'  => $orderId,
      'merchant' => $merchant
    });

    return 0;
  }
  
  # Make sure loaded data is actually trans object
  my $transactionToValidateAgainst = $loadedTransactionsForMerchant->{$orderId};
  if (!isTransactionObject($transactionToValidateAgainst)) {
    logValidationFailure({
      'message'  => 'unable to load transaction for orderId',
      'orderId'  => $orderId,
      'merchant' => $merchant
    });

    return 0;
  }

  # Check each field
  my $amountIsCorrect = $transactionToValidateAgainst->getTransactionAmount() eq $amount;
  my $statusIsCorrect = $transactionToValidateAgainst->getResponse()->getStatus() eq $status;
  my $orderIdIsSame   = $transactionToValidateAgainst->getOrderID() eq $orderId;
  my $merchantIsSame  = $transactionToValidateAgainst->getGatewayAccount() eq $merchant;

  # Shipping information check
  my $shippingIsTheSame = compareShippingInformation($shippingInformation, $transactionToValidateAgainst->getShippingInformation());
  
  # Do the boolean needful
  my $validated = $amountIsCorrect && $statusIsCorrect && $orderIdIsSame && $merchantIsSame && $shippingIsTheSame;

  if (!$validated) {
    logValidationFailure({
      'message'  => 'Transaction failed to validate',
      'orderId'  => $orderId,
      'merchant' => $merchant
    });
  }

  return $validated;
}

# Verifies data is a Trans Obj
sub isTransactionObject {
  my $transactionObject = shift;
  my $transactionObjectIsOk = 0;

  eval {
    if ($transactionObject->isa('PlugNPay::Transaction')) {
      $transactionObjectIsOk = 1;
    }
  };

  return $transactionObjectIsOk;
}

# Compare shipping data
sub compareShippingInformation {
  my $shippingInformation = shift;
  my $shippingInfoToCompare = shift;
  my $shippingIsTheSame = 1;

  if (ref($shippingInformation) eq 'HASH' && ref($shippingInfoToCompare) eq 'PlugNPay::Contact') {
    my %shipHashToCompare = $shippingInfoToCompare->toHash();
    foreach my $key (keys %{$shippingInformation}) {
      my $currentFieldIsTheSame = $shippingInformation->{$key} eq $shipHashToCompare{$key};
      if (inArray($key, ['phoneNumber', 'emailAddress'])) {
        eval {
          $currentFieldIsTheSame = checkPhoneOrEmail($shippingInformation->{$key}, $shipHashToCompare{$key});
        };
      }
      $shippingIsTheSame = $shippingIsTheSame && $currentFieldIsTheSame;
    }
  }

  return $shippingIsTheSame;
}

# Phone/Email is a map
sub checkPhoneOrEmail {
  my $phoneOrEmail = shift;
  my $loadedPhoneOrEmail = shift;
  my $isMatch = 1;
  if (ref($phoneOrEmail) eq 'HASH' || ref($loadedPhoneOrEmail) eq 'HASH') {
    foreach my $key (keys %{$phoneOrEmail}) {
      my $loadedValue = $loadedPhoneOrEmail->{$key};
      my $currentValue = $phoneOrEmail->{$key};
      $isMatch = $isMatch && ($loadedValue eq $currentValue);
    }
  } else {
    $isMatch = ($phoneOrEmail eq $loadedPhoneOrEmail);
  }

  return $isMatch;
}

# Logs to datalog
sub logValidationFailure {
  my $dataToLog = shift;
  if (!defined $dataToLog || ref($dataToLog) ne 'HASH') {
    return;
  }

  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'transaction_validation'});
  $logger->log($dataToLog);
}

1;
