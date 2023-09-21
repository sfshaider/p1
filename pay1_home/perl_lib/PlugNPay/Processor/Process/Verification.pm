package PlugNPay::Processor::Process::Verification;

use strict;
use PlugNPay::Util::UniqueID;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::State;
use PlugNPay::Sys::Time;
use PlugNPay::GatewayAccount;
use PlugNPay::Transaction::State;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub setHexID {
  my $self = shift;
  my $hexID = shift;
  $self->{'hexID'} = $hexID;
}

sub getHexID {
  my $self = shift;
  return $self->{'hexID'};
}

sub setMaxReturnAmount {
  my $self = shift;
  my $maxReturnAmount = shift;
  $self->{'maxReturnAmount'} = $maxReturnAmount;
}

sub getMaxReturnAmount {
  my $self = shift;
  return $self->{'maxReturnAmount'};
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

sub setPNPOrderID {
  my $self = shift;
  my $pnpOrderID = shift;
  $self->{'pnpOrderID'} = $pnpOrderID;
}

sub getPNPOrderID {
  my $self = shift;
  return $self->{'pnpOrderID'};
}

sub setOriginalTransaction {
  my $self = shift;
  my $originalTransaction = shift;
  $self->{'originalTransaction'} = $originalTransaction;
}

sub getOriginalTransaction {
  my $self = shift;
  return $self->{'originalTransaction'};
}

sub setReturns {
  my $self = shift;
  my $returns = shift;
  $self->{'returns'} = $returns;
}

sub getReturns {
  my $self = shift;
  return $self->{'returns'};
}

# Make sure we have not returned more than original transaction amount #
sub checkReturnAmount {
  my $self = shift;
  my $pnpID = shift;
  my $merchant = shift;
  my $returnAmount = shift;
  my $processor = shift || undef;

  my $hexID = $pnpID;
  unless ($hexID =~ /^[a-fA-F0-9]+$/) {
    my $uuid = new PlugNPay::Util::UniqueID;
    $uuid->fromBinary($pnpID);
    $hexID = $uuid->inHex();
  }

  my $transactionSearch = {'username' => $merchant, 'pnp_transaction_ref_id' => $pnpID, 'transaction_state' => 'CREDIT'};
  if (!defined $processor) {
    $transactionSearch->{'processor'} = $processor;
  }

  my $loader = new PlugNPay::Transaction::Loader();
  my $transactions = $loader->load($transactionSearch)->{$merchant};
  my $originalTransaction = $loader->load({'username' => $merchant, 'transactionID' => $pnpID})->{$merchant}{$hexID};
  if (!defined $originalTransaction) {
    return 0;
  }

  my $total = 0;
  foreach my $transactionID (keys %{$transactions}) {
    my $transaction = $transactions->{$transactionID};
    if ($transactionID != $hexID && ref($transaction) =~ /PlugNPay::Transaction::Credit/ && $transaction->getTransactionState() !~ /void/i) {
      $total += $transaction->getTransactionAmount();
    }
  }

  if ((($originalTransaction->getTransactionAmount() - $total) >= $returnAmount) || $originalTransaction->getTransactionAmount() > $total) {
    $self->setHexID($hexID);
    $self->setMaxReturnAmount($originalTransaction->getTransactionAmount() - $total);
    $self->setOrderID($originalTransaction->getOrderID());
    $self->setPNPOrderID($originalTransaction->getPNPOrderID());
    $self->setOriginalTransaction($originalTransaction);
    $self->setReturns($transactions);
    return 1;
  } else {
    return 0;
  }
}

sub checkTransaction {
  my $self = shift;
  my $username = shift;
  my $data = shift;
  
  if (ref($data) ne 'HASH') {
    return;
  }

  my $loader = new PlugNPay::Transaction::Loader();
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $time = new PlugNPay::Sys::Time();
  my $stateMachine = new PlugNPay::Transaction::State();
  my $adjustedTime = $time->nowInFormat('iso');
  my $stateFromMode = $stateMachine->translateLegacyOperation($data->{'mode'}, 'success');
  my $loaded = $loader->load({'orderID' => $data->{'orderID'}, 'end_date' => $adjustedTime, 'username' => $username});
  my $transactions = $loaded->{$gatewayAccount->getGatewayAccountName()};
  my $responses = {};
  foreach my $tid (keys %{$transactions}) {
    my $transaction = $transactions->{$tid};
    my $parsedInfo = $self->processCheckResponse($tid,$transaction);
    $parsedInfo->{'transID'} = $tid;
    $parsedInfo->{'orderID'} = $transaction->getOrderID();
    if (!$responses->{$transaction->getOrderID()}) {
      $responses->{$transaction->getOrderID()} = $parsedInfo;
    } else {
      $responses->{$transaction->getOrderID()}{$tid} = $parsedInfo;
    }
  }
  return $responses;
}
  
sub processCheckResponse {
  my $self = shift;
  my $id = shift;
  my $trans = shift;
  my $response = {};
  my $loader = new PlugNPay::Transaction::Loader();
  my $stateMachine = new PlugNPay::Transaction::State();
  my $nextStates = $stateMachine->getStateMachine()->{$trans->getTransactionState()};

  my $isMarked = (uc($trans->getTransactionState()) eq 'POSTAUTH_READY' ? 1 : 0);
  if (!$isMarked && uc($trans->getTransactionState()) eq 'AUTH') {
    my $jobs = $loader->getTransactionSettlementJobs($trans->getPNPTransactionID());
    my $pnpID = $trans->getPNPTransactionID();
    if ($pnpID !~ /^[a-fA-F0-9]+$/) {
      my $uuid = new PlugNPay::Util::UniqueID();
      $uuid->fromBinary($pnpID);
      $pnpID = $uuid->inHex();
    }
      
    if ($jobs->{$id}) {
      $isMarked = 1;
    } elsif ($jobs->{$pnpID}) {
      $isMarked = 1;
    }
  }
  my $isStoredata = ($trans->getTransactionState() =~ /^STOREDATA/i ? 1 : 0);

  my $processorObj = new PlugNPay::Processor({'shortName' => $trans->getProcessor()});
  my $currency = ($trans->getCurrency() ? $trans->getCurrency() : 'usd');

  #Setup minor flags
  $response->{'void_flag'}     = ($trans->getTransactionState() =~ /^VOID/i ? 1 : 0);
  $response->{'mark_flag'}     = $isMarked;
  $response->{'storedata_flag'} = $isStoredata;
  $response->{'settled_flag'}  = (uc($trans->getTransactionState()) eq 'POSTAUTH' ? 1 : 0);
  $response->{'reauth_flag'}   = ($trans->getTransactionState() =~ /^AUTH[_PROBLEM|_PENDING]*/i ? 1 : 0);
  $response->{'mark_ret_flag'} = (uc($trans->getTransactionState()) eq 'CREDIT_PENDING' ? 1 : 0);
  $response->{'auth_flag'}     = (uc($trans->getTransactionState()) eq 'AUTH' ? 1 : 0);
  $response->{'locked_flag'}   = (uc($trans->getTransactionState()) eq 'POSTAUTH_PENDING' ? 1 : 0);
  $response->{'setlret_flag'}  = (uc($trans->getTransactionState()) eq 'CREDIT' ? 1 : 0);

  #Setup important action flags
  my $canReauth = ($trans->getTransactionState() !~ /_PENDING/i && $processorObj->getReauthAllowed() ? 1 : 0);
  $response->{'allow_reauth'}  = ($canReauth && !$isStoredata ? 1 : 0);
  $response->{'allow_void'}    = $stateMachine->checkNextState($trans->getTransactionState(),'VOID_PENDING');
  $response->{'allow_mark'}    = (!$isMarked && !$isStoredata ? 1 : 0);
  $response->{'allow_return'}  = ($trans->getTransactionState() =~ /SALE|POSTAUTH/i ? 1 : 0);

  #Setup transaction info
  $response->{'order-id'}      = $trans->getOrderID();
  $response->{'amount'}        = $currency . ' ' . $trans->getTransactionAmount();
  $response->{'pnp_transaction_id'} = $trans->getPNPTransactionID();
  if ($trans->getTransactionState() eq 'AUTH') {
    $response->{'authamt'}     = $currency . ' ' . $trans->getTransactionAmount();
  }

  return $response;
}

1;
