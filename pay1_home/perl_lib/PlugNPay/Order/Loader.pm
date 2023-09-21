package PlugNPay::Order::Loader;

use strict;
use PlugNPay::Transaction::Loader;
use PlugNPay::Logging::Performance;
use PlugNPay::Logging::DataLog;
use PlugNPay::Order::Loader::Unified;
use PlugNPay::Order::Loader::Legacy;
use PlugNPay::Order;
use PlugNPay::Die;
use PlugNPay::Util::UniqueID;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;
  return $self;
}

# attempts to load new, if nothing found, loads old.
sub load {
  my $self = shift;
  my $nextVariable = shift;
  my $orderID;
  my $username;
  my $orderObject;
  if (ref($nextVariable) eq 'HASH') {
    $orderID = $nextVariable->{'orderId'} || $nextVariable->{'orderID'};
    $username = $nextVariable->{'gatewayAccount'};
    $orderObject = $nextVariable->{'orderObject'};
  } else {
    $orderID = $nextVariable;
    $username = shift;
  }

  my $likelyLegacy = PlugNPay::Order::isOrderIdLikelyLegacy($orderID);
  my $data;

  # if likely legacy, try loading from legacy first.
  if ($likelyLegacy) {
    $data = new PlugNPay::Order::Loader::Legacy()->load($orderID, $username);
  }

  # then try loading from unified....
  if (!$data) {
    $data = new PlugNPay::Order::Loader::Unified()->load($orderID, $username);
  }

  # if it wasn't likely legacy, try loading it from legacy now.
  if (!$data && !$likelyLegacy) {
    $data = new PlugNPay::Order::Loader::Legacy()->load($orderID, $username);
  }

  if ($data && $orderObject) {
    if (ref($orderObject) ne 'PlugNPay::Order') {
      die('order object value is not an order object!');
      $orderObject->setMerchantOrderID($data->{'merchant_order_id'});
      $orderObject->setCreationDate($data->{'creation_date'});
      $orderObject->setMerchantClassifierID($data->{'merchant_classification_id'});
      $orderObject->setPNPOrderID($data->{'pnp_order_id'}) if $data->{'pnp_order_id'}; # do not set order id if pnp_order_id does not exist
      $orderObject->setOrderTransactionIDs($data->{'order_transaction_ids'});
    } else {
      $orderObject = new PlugNPay::Order();
      $orderObject->newOrder($data);
    }
    return $orderObject;
  } else {
    return $data;
  }
}

# Loads level 3 data
sub loadOrderDetails {
  my $self = shift;
  my $orderID = shift;
  my $useLegacy = shift;
  my $rows;

  if ($useLegacy) {
    $rows = new PlugNPay::Order::Loader::Unified()->loadOrderDetails($orderID);
  } else {
    $rows = new PlugNPay::Order::Loader::Legacy()->loadOrderDetails($orderID);
  }

  return $rows;
}

sub loadDetailsByMerchant {
  my $self = shift;
  my $merchantOrderID = shift;
  my $gatewayAccount = shift;

  my $items;
  #comment out legacyStatus for now, not used.
  if ($self->orderExists($merchantOrderID,$gatewayAccount)) { # && !$self->legacyStatus($merchantOrderID,$gatewayAccount)) {
    my $loader = new PlugNPay::Order::Loader::Unified();
    $items = $loader->loadDetailsByMerchOrderID($merchantOrderID,$gatewayAccount);
  } else {
    # For Compatibility
    my $loader = new PlugNPay::Order::Loader::Legacy();
    $items = $loader->loadOrderDetails($merchantOrderID,$gatewayAccount);
  }

  return $items;
}

#Compatibility, seek and destroy
#Not sure where this is used, refactored because it was a duplicate
sub loadOrderIDs {
  my $self = shift;
  my $id = shift;
  my $merchID = shift;

  my $iid = new PlugNPay::GatewayAccount::InternalID;
  my $username = $iid->getUsernameFromId($merchID);

  my $data = $self->load($id, $username);

  #this wasn't originally loaded by this func, so delete?
  delete $data->{'order_details'};
  delete $data->{'order_transaction_ids'};

  return $data;
}

#Compatibility
sub query {
  my $self = shift;
  my $processor = shift;
  my $vehicle = shift;
  my $queryData = shift;

  return new PlugNPay::Order::Loader::Unified()->query($processor, $vehicle, $queryData);
}

#Compatibility
sub loadOrdersByMerchant {
  my $self = shift;
  my $usernames = shift;

  return new PlugNPay::Order::Loader::Unified()->loadOrdersByMerchants($usernames);
}

# Loads orders by using transaction level info, then loads with some trans data
# This is really annoying but, you know, compatibility with old code...
sub loadExtendedOrders {
  my $self = shift;
  my $data = shift;
  return $self->loadOrdersOptions($data, { format => 'hash' });
}

# this does the same as loadExtendedOrders but skips loading some of the transaction data by passing
# some settings to Transaction::Loader
sub loadOrdersSummary {
  my $self = shift;
  my $data = shift;
  return $self->loadOrdersOptions($data, { format => 'hash', summary => 1 });
}

sub loadOrdersOptions {
  my $self = shift;
  my $data = shift;
  my $options = shift;
  my @extendedOrders = ();
  my @searchData = ();
  new PlugNPay::Logging::Performance('Order::Loader::loadExtenedOrders');

  my $orders = new PlugNPay::Order::Loader::Unified($self->getLoadLimit())->loadOrders($data->{'new'});
  my $legacyOrders = new PlugNPay::Order::Loader::Legacy($self->getLoadLimit())->loadOrders($data->{'legacy'});
  push @{$orders},@{$legacyOrders};

  #Now we need to load extended order data
  foreach my $order (@{$orders}) {
    $order->{'pnp_order_id'} = new PlugNPay::Util::UniqueID()->fromBinaryToHex($order->{'pnp_order_id'});
    push @searchData, {'gatewayAccount' => $order->{'identifier'},'orderID' => $order->{'pnp_order_id'}};
  }

  my $transactionLoaderOptions = {'loadPaymentData' => 0, 'returnAsHash' => 1};

  if ($options->{'format'} eq 'hash') {
    $transactionLoaderOptions->{'returnAsHash'} = 1;
  }

  if ($options->{'summary'}) {
    $transactionLoaderOptions->{'loadDetailData'} = 0;
    $transactionLoaderOptions->{'loadPaymentData'} = 1;
  }
  my $loader = new PlugNPay::Transaction::Loader($transactionLoaderOptions);
  my $loadedData = $loader->load(\@searchData);
  foreach my $order (@{$orders}) {
    my $merchant = $order->{'identifier'};
    push @extendedOrders,$self->loadOrderStatus($order,$loadedData->{$merchant});
  }

  new PlugNPay::Logging::Performance('Order::Loader::loadExtenedOrders');

  return \@extendedOrders;
}

#Super sweet exists
sub orderExists {
  my $self = shift;
  my $merchantOrderID = shift;
  my $merchant = shift;
  my $isLegacy = shift;

  my $exists = 0;
  if ($isLegacy) {
    $exists = new PlugNPay::Order::Loader::Legacy()->orderExists($merchantOrderID, $merchant);
  } else {
    $exists = new PlugNPay::Order::Loader::Unified()->orderExists($merchantOrderID, $merchant);
  }

  return $exists;
}

#Checks if the "isLegacy" flag set in new db
sub legacyStatus {
  my $self = shift;
  my $orderID = shift;
  my $merchant = shift;

  return new PlugNPay::Order::Loader::Unified()->getLegacyStatus($orderID, $merchant);
}

#compatibility and needs to be removed, SEEK AND DESTROY!
sub loadLegacyItemization {
  my $self = shift;
  my $orderID = shift;
  my $merchant = shift;

  return new PlugNPay::Order::Loader::Legacy()->getOrderDetails($orderID, $merchant);
}

#the spooktacular function, not an actual load
sub loadOrderStatus {
  my $self = shift;
  my $order = shift;
  my $transactions = shift;
  my $authAmount = 0;
  my $creditAmount = 0;
  my %customersHash = ();
  my @statuses = ();
  my @bins = ();
  my @acctCodes = ();
  my @transStateArray = ();
  foreach my $transID (keys %{$transactions}) {
    if ($transactions->{$transID}{'merchant_order_id'} eq $order->{'merchant_order_id'}) {
      my $customer = $transactions->{$transID}{'billing_information'}{'name'};
      $customer =~ s/^\s+|\s+$//g;
      if ($customer && !$customersHash{$customer}) {
        $customersHash{$customer} = 1;
      }

      my $transState = $transactions->{$transID}{'transaction_state'};
      my ($stateName, $subStateName) = split('_',$transState);
      if ($transState eq 'AUTH' && $transactions->{$transID}{'pnp_job_id'}) {
        $transState = 'POSTAUTH_READY';
      }

      if ($stateName ne 'CREDIT') {
        if ($transState eq 'POSTAUTH') {
          my $settledAmount = $transactions->{$transID}{'settled_amount'};
          $authAmount += ($settledAmount ? $settledAmount : $transactions->{$transID}{'transaction_amount'});
        } elsif ($transState eq 'POSTAUTH_READY') {
          my $markAmount = $transactions->{$transID}{'settlement_amount'};
          $authAmount += ($markAmount ? $markAmount : $transactions->{$transID}{'transaction_amount'});
        } else {
          $authAmount += $transactions->{$transID}{'transaction_amount'};
        }
      }

      if ($stateName eq 'CREDIT' && $subStateName ne 'PROBLEM') {
        $creditAmount += $transactions->{$transID}{'transaction_amount'};
      }

      my $hasJobID = $transactions->{$transID}{'pnp_job_id'};
      my $status;
      if ($stateName eq 'POSTAUTH') {
        if ($subStateName eq 'READY') {
          $status = 'Marked';
        } else {
          $status = 'Settlement';
        }
      } elsif ($stateName eq 'AUTH') {
        if ($hasJobID) {
          $status = 'Marked';
        } else {
          $status = 'Authorization';
        }
      } elsif ($stateName eq 'SALE') {
        $status = 'Sale';
      } elsif ($stateName eq 'VOID') {
        $status = 'Voided';
      } elsif ($stateName eq 'CREDIT') {
        $status = ($transactions->{$transID}{'pnp_transaction_ref_id'} || $transactions->{$transID}{'refnumber'} ? 'Return' : 'Credit');
      } else {
        $status = ucfirst($stateName);
      }

      if ($transState ne 'POSTAUTH_READY' && !$hasJobID && $transState !~ /VOID/i) {
        if ($subStateName eq 'PROBLEM') {
          if ($stateName eq 'AUTH' || $stateName eq 'SALE' || $stateName eq 'CREDIT') {
            $status .= ($transactions->{$transID}{'status'} =~ /badcard|decline/i ? ' Declined' : ' Failure');
          } else {
            $status .= ' Failure';
          }
        } elsif ($subStateName eq 'PENDING') {
          $status .= ' Pending';
        } else {
          $status .= ' Successful';
        }
      }

      push @statuses,$status;
      my $cardInfo = $transactions->{$transID}{'card_information'};
      if (defined $cardInfo) {
        push @bins, $cardInfo->{'card_first_six'} . '**' . $cardInfo->{'card_last_four'};
      }

      push @acctCodes,$transactions->{$transID}{'account_codes'};
      push @transStateArray,$transState;
    }
  }
  my $response = $order;
  $response->{'amount'}             = sprintf("%.2f",($authAmount - $creditAmount));
  $response->{'auth_amount'}        = sprintf("%.2f",$authAmount);
  $response->{'credit_amount'}      = sprintf("%.2f",$creditAmount);
  $response->{'customers'}          = join(', ', keys %customersHash);
  $response->{'trans_status'}       = join(', ',@statuses);
  $response->{'card_numbers'}       = \@bins;
  $response->{'account_codes'}      = \@acctCodes;
  $response->{'transaction_states'} = \@transStateArray;

  return $response;
}

#Checks both DBs to see what is where
sub checkDatabasesToLoad {
  my $self = shift;
  my $username = shift;
  my $options = shift;

  return {
    'new' => new PlugNPay::Order::Loader::Unified()->checkDatabase($username,$options),
    'old' => new PlugNPay::Order::Loader::Legacy()->checkDatabase($username,$options)
  };
}

sub getOrdersListSize { #refactor to load both?
  my $self = shift;
  my $data = shift;

  return new PlugNPay::Order::Loader::Unified()->getOrdersListSize($data);
}

#Compatibility, seek and destroy
sub getLegacyOrdersListSize {
  my $self = shift;
  my $data = shift;

  return new PlugNPay::Order::Loader::Legacy()->getOrderListSize($data);
}

#Responder interface funcs
sub setLoadLimit {
  my $self = shift;
  my $limitHash = shift;

  $self->{'limitData'} = $limitHash;
}

sub getLoadLimit {
  my $self = shift;

  return $self->{'limitData'};
}

#Logging
sub log {
  my $self = shift;
  my $data = shift;
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'order'});

  $logger->log($data);
}

1;
