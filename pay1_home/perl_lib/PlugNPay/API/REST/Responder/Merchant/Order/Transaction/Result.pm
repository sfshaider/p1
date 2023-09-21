package PlugNPay::API::REST::Responder::Merchant::Order::Transaction::Result;

use strict;
use PlugNPay::Order::Loader;
use PlugNPay::Util::UniqueID;
use PlugNPay::Processor::Process;
use PlugNPay::Transaction::State;
use PlugNPay::Transaction::JSON;
use PlugNPay::Processor::Process::Verification;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::Loader;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  my $data = {};
  if ($action eq 'read') {
    $data = $self->_read();
  } else {
    $self->setResponseCode('501');
  }

  return $data;
}

# Redeem transactions #
sub _read {
  my $self = shift;
  my $transactionID = $self->getResourceData()->{'transaction'};
  my $orderID = $self->getResourceData()->{'order'};
  my $merchant = $self->getResourceData()->{'merchant'};
  my $resultType = lc($self->getResourceData()->{'result'});

  if ((defined $orderID || defined $transactionID) && defined $resultType && $resultType eq 'return') {
    my $id = (defined $transactionID ? $transactionID : $orderID);
    return $self->getReturnsTotal($id,$merchant);
  } elsif (defined $transactionID) {
    return $self->getPending($transactionID);
  } elsif(defined $merchant) {
    return $self->getReports($merchant);
  } else {
    $self->setResponseCode('404');
    return {};
  }
}

sub getPending {
  my $self = shift;
  my $pendingID = shift;

  my @responseArray = ();
  my $pendingTransID;
  if ($pendingID  =~ /^[a-fA-F0-9]+$/) {
    my $uuid = new PlugNPay::Util::UniqueID();
    $uuid->fromHex($pendingID);
    $pendingTransID = $uuid->inBinary();
  } else {
    $self->setResponseCode('403');
    return {};
  }

  my $transLoader = new PlugNPay::Transaction::Loader();
  my $pendingCheck = $transLoader->checkIsPending($pendingTransID);
  my $responseHash = {};
  if ($pendingCheck->{$pendingTransID}) {
    eval {
      my $process = new PlugNPay::Processor::Process();
      my $data = $process->getProcessedTransactions($pendingTransID);
      foreach my $key (keys %{$data}) {
        if (ref($data->{$key}) eq 'ARRAY') {
          push @responseArray,@{$data->{$key}};
        } else {
          push @responseArray,$data->{$key};
        }
      }
    };

    if ($@) {
      $self->setResponseCode('520');
      my $message = {'error' => $@,
                     'function' => 'retrievePending',
                     'module' => 'results responder',
                     'transID' => $pendingID
      };
      new PlugNPay::Logging::DataLog({'collection' => 'transaction'})->log($message);

      $responseHash = {'message' => 'Unknown error occurred'};
    } else {
      $self->setResponseCode('200');
      $responseHash = {'transaction' => $responseArray[0], 'sentID' => $pendingID, 'message' => 'Transaction successfully redeemed'};
    }
  } else {
    $self->setResponseCode(200);
    $responseHash = {'transaction' => {}, 'sendID' => $pendingID, 'message' => 'This transaction has already been redeemed.'};
  }

  return $responseHash;
}

sub getReports {
  my $self = shift;
  my $merchant = shift;
  my $options = $self->getResourceOptions();
  my $stateMachine = new PlugNPay::Transaction::State();
  my $searchHash = {'gatewayAccount' => $merchant,'transaction_state_id' => $stateMachine->getStates()->{'POSTAUTH'}};

  if (defined $options && ref($options) eq 'HASH') {
    $searchHash->{'start_time'} = $options->{'start_time'} if defined $options->{'start_time'};
    $searchHash->{'end_time'} = $options->{'end_time'} if defined $options->{'end_time'};
  }

  my $transactionResponder = new PlugNPay::API::REST::Responder::Merchant::Order::Transaction();
  my $transactions = $transactionResponder->loadTransactions([$searchHash]);
  #No reason to reinvent the wheel here...
  if ($transactionResponder->getResponseCode() eq '520') {
    $self->setResponseCode('520');
    $self->setError($transactionResponder->getError());
    return {'error' => $transactionResponder->getError()};
  } else {
    $self->setResponseCode('200');
    return $transactions;
  }
}

sub getReturnsTotal {
  my $self = shift;
  my $pnpID = shift;
  my $merchant = shift || $self->getGatewayAccount();
  my $verifier = new PlugNPay::Processor::Process::Verification();
  my $returnAmount = $self->getResourceOptions()->{'return_amount'};
  my $verified = $verifier->checkReturnAmount($pnpID,$merchant,$returnAmount);

  if ($verified) {
    $self->setResponseCode('200');
    my $hashedTrans = new PlugNPay::Transaction::JSON()->transactionToJSON($verifier->getOriginalTransaction());
    $hashedTrans->{'maxReturnAmount'} = $verifier->getMaxReturnAmount() || $verifier->getOriginalTransaction()->getTransactionAmount();
    $hashedTrans->{'returnAmount'} = $returnAmount;
    $hashedTrans->{'hexTransactionID'} = $verifier->getHexID();
    $hashedTrans->{'merchantOrderID'} = $verifier->getOrderID() || $self->getMerchantOrderID($verifier->getPNPOrderID());

    return $hashedTrans;
  } else {
    $self->setResponseCode('422');
    return {'error' => 'return amount exceeded', 'message' => 'The amount for this return exceeds original transaction amount'};
  }

}

sub getMerchantOrderID {
  my $self = shift;
  my $pnpID = shift;

  my $loader = new PlugNPay::Order::Loader();

  my $loaded = $loader->loadOrderIDs($pnpID);

  return $loaded->{'merchant_order_id'};
}

1;
