package PlugNPay::Order;

use strict;
use PlugNPay::Transaction;
use PlugNPay::DBConnection;
use PlugNPay::Order::Saver;
use PlugNPay::Order::Loader;
use PlugNPay::Order::Detail;
use PlugNPay::Util::UniqueID;
use PlugNPay::Transaction::Saver;
use PlugNPay::Transaction::Loader;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::Formatter;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Transaction::TransactionProcessor;

################ Order #################
# This is the new Order object module  #
# can contain an array of transactions #
########################################

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $orderID = shift;
  if (!defined $orderID || !$self->verifyPNPOrderID($orderID)) {
    $orderID = $self->generatePNPOrderID();
  }
  $self->setPNPOrderID($orderID);
  return $self;
}

#####################
# Setters & Getters #
#####################
sub setOrder { #Probably wont be used, but you never know
  my $self = shift;
  my $orderData = shift;
  $self->{'orderData'} = $orderData;
}

sub getOrder {
  my $self = shift;
  return $self->{'orderData'};
}

# setPNPOrderID : supports both legacy order ids (numeric only) and hex/binary order ids
sub setPNPOrderID {
  my $self = shift;
  my $orderID = shift || '';
  my $id;
  if ($orderID && $orderID =~ /[^A-Za-z0-9]/) {
    $id = PlugNPay::Util::UniqueID::fromBinaryToHex($orderID);
  }
  $self->_setOrderData('pnp_order_id',$id);
}

# getPNPOrderID : supports both legacy order ids (numeric only) and hex/binary order ids
sub getPNPOrderID {
  my $self = shift;
  my $id = $self->_getOrderData('pnp_order_id');
  if ($id =~ /[A-Za-z]/ && length($id) > 23) {
    $id = PlugNPay::Util::UniqueID::fromHexToBinary($id);
  }
  return $id;
}

sub setMerchantID {
  my $self = shift;
  my $merchantID = shift;
  $self->_setOrderData('merchant_id',$merchantID);
}

sub getMerchantID {
  my $self = shift;
  return $self->_getOrderData('merchant_id');
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
  my $process = new PlugNPay::GatewayAccount::InternalID();
  my $merchantID = $process->getMerchantID($gatewayAccount);
  $self->setMerchantID($merchantID);
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setMerchantOrderID {
  my $self = shift;
  my $merchantOrderID = shift;
  if (length($merchantOrderID) > 20) {
    die "Merchant Order ID is too long!";
  }
  $self->_setOrderData('merchant_order_id',$merchantOrderID);
}

sub getMerchantOrderID {
  my $self = shift;
  my $id =  $self->_getOrderData('merchant_order_id');
  if (!defined $id) {
    $id = $self->generateMerchantOrderID();
    $self->setMerchantOrderID($id);
  }

  return $id;
}

sub setCreationDate {
  my $self = shift;
  my $creationDate = shift;
  $self->_setOrderData('creation_date',$creationDate);
}

sub getCreationDate {
  my $self = shift;
  return $self->_getOrderData('creation_date');
}

sub setOrderDetails {
  my $self = shift;
  my $orderDetails = shift;
  $self->_setOrderData('order_details',$orderDetails);
}

sub getOrderDetails {
  my $self = shift;
  return $self->_getOrderData('order_details');
}

sub addOrderDetail {
  my $self = shift;
  my $detail = shift;

  if (ref($detail) eq 'PlugNPay::Order::Detail') {
    push @{$self->{'orderData'}{'order_details'}},$detail;
  } elsif (ref($detail) eq 'HASH') {
    my $detailObj = new PlugNPay::Order::Detail($detail);
    push @{$self->{'orderData'}{'order_details'}},$detailObj;
  }
}

sub setOrderTransactionIDs {
  my $self = shift;
  my $orderTransactionIDs = shift;
  $self->_setOrderData('order_transaction_ids',$orderTransactionIDs);
}

sub getOrderTransactionIDs {
  my $self = shift;
  return $self->_getOrderData('order_transaction_ids');
}

sub addOrderTransactionID {
  my $self = shift;
  my $id = shift;
  push @{$self->{'orderData'}{'order_transaction_ids'}},$id;
}

sub setOrderTransactions {
  my $self = shift;
  my $orderTransactions = shift;
  foreach my $transaction (@{$orderTransactions}) {
    $self->addOrderTransaction($transaction);
  }
}

sub getOrderTransactions {
  my $self = shift;
  return $self->_getOrderData('order_transactions');
}

sub addOrderTransaction {
  my $self = shift;
  my $transaction = shift;
  if (ref($transaction) =~ /^PlugNPay::Transaction/) {
    my $pnpID = $transaction->getPNPTransactionID();
    unless (defined $pnpID && $transaction->verifyTransactionID($pnpID)) {
      $pnpID = $transaction->generateTransactionID();
      $transaction->setPNPTransactionID($pnpID);
    }
    $self->addOrderTransactionID($pnpID);
    push @{$self->{'orderData'}{'order_transactions'}},$transaction;
  } elsif (ref($transaction) eq 'HASH') {
    my $transactionObj = new PlugNPay::Transaction::Formatter()->makeTransactionObject($transaction);
    my $pnpID = $transactionObj->getPNPTransactionID();
    unless (defined $pnpID && $transactionObj->verifyTransactionID($pnpID)) {
      $transactionObj->setPNPTransactionID($transactionObj->generateTransactionID());
    }
    $self->addOrderTransactionID($transactionObj->getPNPTransactionID());
    push @{$self->{'orderData'}{'order_transactions'}},$transactionObj;
  }
}

sub setOrderClassifier {
  my $self = shift;
  my $orderClassifier = shift;
  if( length($orderClassifier) > 20 ) {
    $orderClassifier = substr($orderClassifier,0,20);
  }

  $self->_setOrderData('orderClassifier',$orderClassifier);
}

sub getOrderClassifier {
  my $self = shift;
  return $self->_getOrderData('orderClassifier');
}

#############
# Functions #
#############
sub save {
  my $self = shift;
  my $operation = shift;
  my $dbs = new PlugNPay::DBConnection();

  $dbs->begin('pnp_transaction');
  my $saver = new PlugNPay::Order::Saver();
  my $success;
  eval {
    $success = $saver->save($self);
    if ($success) {
      if (!$saver->saveTransactions($self,$operation)) {
        $success->setFalse();
      }
    }
  };

  if ($success) {
    $dbs->commit('pnp_transaction');
  } else {
    $dbs->rollback('pnp_transaction');
    my $dataLog = new PlugNPay::Logging::DataLog({'collection' => 'order'});
    $dataLog->log({
      'message'  => 'Order save failed.',
      'orderID'  => $self->getMerchantOrderID(),
      'merchant' => $self->getGatewayAccount(),
      'error'    => $@ || ($success->getError() . ' - ' . $success->getErrorDetails()),

    });
  }

  return $success;
}

sub saveOrderDetails {
  my $self = shift;
  my $saver = new PlugNPay::Order::Saver();
  my $status =  $saver->saveOrderDetails($self->getOrderDetails());

  if (!$status) {
    my $dataLog = new PlugNPay::Logging::DataLog({'collection' => 'order'});
    $dataLog->log({
      'message'  => 'Order details save failed.',
      'orderID'  => $self->getMerchantOrderID(),
      'merchant' => $self->getGatewayAccount(),
      'error'    => $status->getError() . ' - ' . $status->getErrorDetails()
    });
  }

  return $status;
}

sub update {
  my $self = shift;
  my $operation = shift;

  my $saver = new PlugNPay::Order::Saver();

  $saver->saveTransactions($self,$operation);
  $saver->saveOrderDetails($self->getOrderDetails());

  return 1;
}

sub loadOrderIDs {
  my $self = shift;
  my $id = shift;
  my $username = shift;
  my $util = new PlugNPay::GatewayAccount::InternalID();
  if (defined $username && $username !~ /^\d+$/) {
    $username = $util->getMerchantID($username);
  }

  my $loader = new PlugNPay::Order::Loader();
  my $idHash = $loader->loadOrderIDs($id,$username);

  $self->_setOrderData('id',$idHash->{'id'});
  $self->setMerchantOrderID($idHash->{'merchant_order_id'});
  $self->setMerchantID($idHash->{'merchant_id'});
  $self->setCreationDate($idHash->{'creation_date'});

  return 1;
}

sub load {
  my $self = shift;
  my $id = shift;
  my $username = shift;
  my $util = new PlugNPay::GatewayAccount::InternalID();
  if (defined $username && $username !~ /^\d+$/) {
    $username = $util->getMerchantID($username);
  }
  my $loader = new PlugNPay::Order::Loader();
  my $tranLoader = new PlugNPay::Transaction::Loader();
  my $loadedOrder = $loader->load($id,$username);
  $self->setOrder($loadedOrder);
  $self->setPNPOrderID($loadedOrder->{'pnp_order_id'});
  $self->setOrderTransactions($tranLoader->loadTransactions($self->getTransactionIDs()));

  return $self->getOrder();
}

sub exists {
  my $self = shift;
  my $orderID = shift;
  my $username = shift;
  my $util = new PlugNPay::GatewayAccount::InternalID();
  if (defined $username) {
    $username = $util->getMerchantID($username);
  }

  my $select = q/
                SELECT COUNT(pnp_order_id) AS `exists`
                FROM `order`
                WHERE /;
  my @values;
  if (defined $username) {
    $select .= ' merchant_order_id = ? AND merchant_id = ?';
    @values = ($orderID,$username);
  } else {
    $select .= ' pnp_order_id = ?';
    @values = ($orderID);
  }

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',$select);
  $sth->execute(@values) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $row = $rows->[0];

  return $row->{'exists'};
}

sub newOrder {
  my $self = shift;
  my $orderHash = shift;
  if (ref($orderHash) eq 'HASH') {
    $self->setPNPOrderID($orderHash->{'pnp_order_id'});
    $self->setMerchantOrderID($orderHash->{'merchant_order_id'});
    $self->setCreationDate($orderHash->{'creation_date'});
    $self->setOrderDetails($orderHash->{'order_details'});
    $self->setOrderTransactions($orderHash->{'order_transaction_ids'});
    $self->setOrderTransactions($orderHash->{'order_transactions'});

  } elsif (ref($orderHash) eq 'PlugNPay::Order') {
    $self->setOrder($orderHash->getOrder());
  }
}

##############
# Formatters #
##############

# This is just for ease of use #
sub verifyPNPOrderID {
  my $self = shift;
  my $id = shift;

  my $uuid = new PlugNPay::Util::UniqueID();
  if ($id =~ /^[0-9a-fA-F]+$/) {
    $uuid->fromHex($id);
  } else {
    $uuid->fromBinary($id);
  }

  my $valid = $uuid->validate();
  if ($valid && !$self->exists($id)) {
    return 1;
  } else {
    return 0;
  }
}

sub generatePNPOrderID {
  my $self = shift;
  my $UIDGen = new PlugNPay::Util::UniqueID();
  $UIDGen->generate();
  my $id = $UIDGen->inBinary();

  return $id;
}

sub verifyMerchantOrderID {
  my $self = shift;
  my $id = shift;
  my $util = new PlugNPay::GatewayAccount::InternalID();
  my $merchant = $self->getGatewayAccount();
  if (!defined $merchant) {
    $merchant = $util->getMerchantName($id);
  }

  return $self->exists($id,$merchant);
}

sub generateMerchantOrderID {
  my $self = shift;
  return new PlugNPay::Transaction::TransactionProcessor()->generateOrderID();
}

#####################
# Private Functions #
#####################
sub _setOrderData {
  my $self = shift;
  my $key = shift;
  my $data = shift;
  $self->{'orderData'}{$key} = $data;
}

sub _getOrderData {
  my $self = shift;
  my $key = shift;

  return $self->{'orderData'}{$key};
}

sub isOrderIdLikelyLegacy {
  my $orderId = shift;
  if ($orderId =~ /^[0-9]+$/) {
    return 1;
  }
  return 0;
}

1;
