package PlugNPay::Transaction::TransactionProcessor::Validate;
# Protego Diabolica:
#   Creates a protective circle — those who are truly on Grindelwald’s side can walk through the flame
#
# Does various checks on a transaction, similar to trans_admin in remote_strict, to ensure the operation
# is allowed.

use strict;
use PlugNPay::Util::Status;
use PlugNPay::Order::Loader;
use PlugNPay::Util::UniqueID;
use PlugNPay::Transaction::State;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Util::UniqueID;

our $nextStateForMode = {
  reauth => 'AUTH_REVERSAL_PENDING',
  void => 'VOID',
  mark => 'POSTAUTH_READY',
  return => 'CREDIT_PENDING'
};

our $modeCheckFunction = {
  credit => \&checkCredit,
  return => \&checkCredit,
  reauth => \&checkAuthReversal,
  void => \&checkVoid,
  mark => \&checkMark,
};

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $input = shift;
  if (!defined $input->{'context'} || ref($input->{'context'}) eq '') {
    die("object requires a transaction context");
  }
  $self->{'context'} = $input->{'context'};
  $self->{'modeCheckFunction'} = $modeCheckFunction;

  return $self;
}


# canProceed: returns a status stating wether or not a transaction can run
#   input: PlugNPay::Transation object
#   output: PlugNPay::Util::Status object
#
sub canProceed {
  my $self = shift;
  my $input = shift;
  my $transaction = $input->{'transaction'};

  my $username = $transaction->getGatewayAccount();
  my $processorId = $transaction->getProcessor();
  my $orderId = $transaction->getOrderID();
  my $transactionId = $transaction->getPNPTransactionID();
  my $amount = $transaction->getTransactionAmount();

  my $status = new PlugNPay::Util::Status(1);

  my $isDuplicate = $self->checkDuplicate({
    transaction => $transaction
  });

  if ($isDuplicate) {
    $status->setFalse();
    $status->setError('duplicate operation found for this transaction');
    return $status;
  }

  if (!$username) {
    $status->setFalse();
    $status->setError('Transaction gateway account is undefined.');
    return $status;
  }

  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  if (!defined $gatewayAccount) {
    $status->setFalse();
    $status->setError('Transaction gateway account does not exist.');
    return $status;
  } elsif (!$gatewayAccount->canProcessTransactions()){
    $status->setFalse();
    $status->setError('This account may not process transactions at this time.  Contact support.');
    return $status;
  }

  if (!$transactionId) {
    $status->setFalse();
    $status->setError('transaction id is undefined.');
    return $status;
  }

  if (!defined $amount) {
    $status->setFalse();
    $status->setError('transaction amount is undefined.');
    return $status;
  }

  if (!$transaction->validate()) {
    $status->setFalse();
    $status->setError($transaction->getValidationError());
    return $status;
  }

  my $mode = $transaction->getTransactionMode();

  $mode = 'mark' if $mode eq 'postauth';

  if ($mode eq 'auth' || $mode eq 'authprev') {
    my $authStatus = $self->checkAuth({ transaction => $transaction, gatewayAccount => $gatewayAccount });
    if (!$authStatus) {
      return $authStatus;
    }
  }

  my $currentTransactionData = $self->{'context'}->getDBTransactionData();
  my $currentTransactionHistory = $self->{'context'}->getTransactionHistory();

  if ($currentTransactionData) {
    my $transactionRefId = PlugNPay::Util::UniqueID::fromBinaryToHex($transaction->getPNPTransactionReferenceID());
    my $currentTransactionDataPNPOrderId = PlugNPay::Util::UniqueID::fromBinaryToHex($currentTransactionData->getPNPOrderID());

    if ($mode eq 'auth') {
      if ($transaction->getPNPTransactionID() eq $currentTransactionData->getPNPOrderID()) {
        $status->setFalse();
        $status->setError('an authorization for that transaction id already exists');
        return $status;
      }
    }

    # return status (default true) if a "prev" transaction, which is if the ref id of $transaction matches $currentTransactionData pnp order id
    if (
      $transactionRefId eq $currentTransactionDataPNPOrderId &&
      inArray($mode,['auth','credit'])
    ) {
      return $status;
    }

    my $nextState = $nextStateForMode->{$mode};
    my $currentTransactionState = $currentTransactionData->getTransactionState();
    my $stateMachine = new PlugNPay::Transaction::State();
    if ($stateMachine->checkNextState($currentTransactionState,$nextState)) {
      my $func = $self->{'modeCheckFunction'}{$mode};
      if (defined $func) {
        $status = &{$func}($self,{
          currentTransactionData => $currentTransactionData,
          currentTransactionHistory => $currentTransactionHistory,
          newTransactionData => $transaction
        });
        if ($status) {
          $transaction->setTransactionState($nextState);
        }
      }
    } else {
      $status->setFalse();
      my $errorMessage = sprintf("transaction state may not be changed from %s to %s",$currentTransactionState, $nextState);
      $status->setError($errorMessage);
    }
  } else { # for when there isn't any current transaction data
    my $func = $self->{'modeCheckFunction'}{$mode};
    if (defined $func) {
      $status = &{$func}($self,{
        newTransactionData => $transaction
      });
    }
  }

  return $status;
}

sub checkAuthReversal { # a.k.a. reauth
  my $self = shift;
  my $input = shift;
  my $transaction = $input->{'newTransactionData'};
  my $currentTransactionData = $input->{'currentTransactionData'};
  my $currentTransactionHistory = $input->{'currentTransactionHistory'};

  my $status = new PlugNPay::Util::Status(1);

  my $transactionStates = new PlugNPay::Transaction::State();
  my $authReversalPendingStateId = $transactionStates->getTransactionStateID('AUTH_REVERSAL_PENDING');
  my $authStateId = $transactionStates->getTransactionStateID('AUTH');

  my $reauthFound = 0;
  foreach my $historyItem (@{$currentTransactionHistory}) {
    if ($historyItem->{'new_state_id'} == $authStateId &&
        $historyItem->{'previous_state_id'} == $authReversalPendingStateId) {
      $reauthFound = 1;
      last;
    }
  }

  my $limitAuthReversals = $self->{'context'}->getAccountFeatures()->get('limitAuthReversals') ? 1 : 0;

  if ($reauthFound && !$limitAuthReversals) {
    $status->setFalse();
    $status->setError('auth reversal limit reached for this transaction');
  }

  if ($transaction->getTaxAmount() == 0 && $currentTransactionData->getTaxAmount() > 0) {
    $status->setFalse();
    $status->setError('auth reversal amount must include tax amount if the original authorization included a tax amount');
  }

  # auth reversals must be for a lower amount than the auth amount, or less than the total auth amount if override adjustment is set.
  if ($transaction->getTransactionAmount() >= $currentTransactionData->getTransactionAmount()) {
    $status->setFalse();
    $status->setError('auth reversal amount must be less than the auth amount');
  }

  return $status;
}

sub checkDuplicate {
  my $self = shift;
  my $input = shift;
  my $transaction = $input->{'transaction'};
  my $transLoader = new PlugNPay::Transaction::Loader( { 'loadPaymentData' => 1 } );

  my $duplicate;

  my $databaseType = $self->{'context'}->getTransactionVersion();

  eval {
    $duplicate = $transLoader->duplicateCheck({
      amount => $transaction->getTransactionAmount(),
      gatewayAccount => $transaction->getGatewayAccount(),
      token => $transaction->getPNPToken(),
      databaseType => $databaseType
    });
  };

  return $duplicate ? 1 : 0;
}

sub checkAuth {
  my $self = shift;
  my $input = shift;
  my $transaction = $input->{'transaction'};
  my $gatewayAccount = $input->{'gatewayAccount'};

  my $status = new PlugNPay::Util::Status(1);

  my $mode = $transaction->getTransactionMode();

  my $currency = $transaction->getCurrency();
  my $amount = $transaction->getTransactionAmount();
  my $features = $gatewayAccount->getFeatures();
  my $increaseLimitFeature = $features->get('highflg') eq '1';

  my $limit = 99999.99;
  if ($increaseLimitFeature) {
    $limit = 999999.99;
  }

  if ($currency eq '388') { # 388 = JMD, Jamaican Dollar
    # limit specified by Processor NCB?
    $limit = 200000000.00;
  }

  if ($transaction->getTransactionAmount() > $limit) {
    $status->setFalse();
    my $errorMessage = sprintf("transaction exceeds limit of %.02f",$limit);
    $status->setError($errorMessage);
    return $status;
  }

  if ( defined $transaction->getCreditCard() ) {
    my $brandData = $self->_isCardBrandEnabled($transaction->getGatewayAccount(), $transaction->getCreditCard()->{'cardNumber'});

    my $cardBrandEnabled = $brandData->{'enabled'};
    my $cardBrandName = $brandData->{'brand'};
    if ( !$cardBrandEnabled ) {
      $status->setFalse();
      $status->setError('Card Brand, '. $cardBrandName . ', not supported.');
    }
  }


  return $status;
}

sub checkCredit {
  my $self = shift;
  my $input = shift;
  my $transaction = $input->{'newTransactionData'};
  my $originalTransaction = $input->{'currentTransactionData'};

  my $status = new PlugNPay::Util::Status(0);

  # return undef if transaction is not a return
  my $mode = $transaction->getTransactionMode();

  if (!($mode eq 'return' || $mode eq 'credit')) {
    $status->setError('not a return, this is likely a bug');
    return $status;
  }

  if ($mode eq 'return' && $originalTransaction) {
    my $originalAmount = $originalTransaction->getTransactionAmount();
    my $returnAmount = $transaction->getTransactionAmount();

    if ($originalAmount < $returnAmount) {
      $status->setError('return amount may not exceed the authorization amount');
      return $status;
    }
  } elsif ($mode eq 'credit') {
    my $un = $transaction->getGatewayAccount();
    my $gw = new PlugNPay::GatewayAccount($un);
    if (!$gw->canProcessCredits()) {
      $status->setError('Account may not process credits');
      return $status;
    }
  }

  $status->setTrue();
  return $status;
}

sub checkVoid {
  my $self = shift;
  my $input = shift;
  my $currentTransactionData = $input->{'currentTransactionData'};
  my $newTransactionData = $input->{'newTransactionData'};

  # is there a reason to deny a void if the state transition is allowed?

  my $status = new PlugNPay::Util::Status(1);

  return $status;
}

sub checkPostauth {
  return checkMark(@_);
}

sub checkMark {
  my $self = shift;
  my $input = shift;
  my $currentTransactionData = $input->{'currentTransactionData'};
  my $newTransactionData = $input->{'newTransactionData'};

  my $status = new PlugNPay::Util::Status(1);

  if (!$currentTransactionData) {
    $status->setFalse();
    $status->setError('Transaction requesed does not exist.');
  }

  return $status;
}

sub _loadTransaction {
  my $self = shift;
  my $transaction = shift;
  my $gatewayAccount = $transaction->getGatewayAccount();
  my $transactionId = $transaction->getPNPTransactionID();

  my $transactionLoader = new PlugNPay::Transaction::Loader();
  my $previousState = $transactionLoader->load({ gatewayAccount => $gatewayAccount, transactionID => $transactionId });
}

sub _loadOrderData {
  my $self = shift;
  my $referenceTransaction = shift;

  my $orderId = $referenceTransaction->getPNPOrderID();
  my $transactionId = $referenceTransaction->getPNPTransactionID();
  my $merchantTransactionId = $referenceTransaction->getMerchantTransactionID();
  my $processor = $referenceTransaction->getProcessor();
  my $gatewayAccount = $referenceTransaction->getGatewayAccount();

  # if there is no order id present, use the pnp transaction id or merchant transaction id as the order id.
  $orderId ||= $transactionId || $merchantTransactionId;
  $orderId = PlugNPay::Util::UniqueID::fromBinaryToHex($orderId);

  my $orderLoader = new PlugNPay::Order::Loader();
  my $order = $orderLoader->load({ gatewayAccount => $gatewayAccount, orderId => $orderId });
  return $order;
}

sub _isCardBrandEnabled {
  my $self = shift;
  my $gatewayAccountName = shift;
  my $cardNumber = shift;

  my $creditCard = new PlugNPay::CreditCard();
  $creditCard->setNumber($cardNumber);
  my $brandname = $creditCard->getBrandName();

  my $enabledBrands = new PlugNPay::GatewayAccount::EnabledCardBrands();
  $enabledBrands->setGatewayAccountName($gatewayAccountName);
  $enabledBrands->load();

  my $isDisabled = $enabledBrands->brandIsDisabled($brandname);

  return { enabled => !$isDisabled, brand => $brandname };
}

1;
