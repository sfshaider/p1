package PlugNPay::Order::JSON;

use strict;
use PlugNPay::Contact;
use PlugNPay::Sys::Time;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::JSON;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub ordersToJSON {
  my $self = shift;
  my $orders = shift;
  my @convertedOrders = ();
  foreach my $order (@{$orders}) {
    my $newHash = {};
    my $customDateTime = $order->{'creation_date_time'};
    if ($customDateTime) {
      $customDateTime = new PlugNPay::Transaction::JSON()->convertTimeFormat($customDateTime);
    }

    $newHash->{'merchantOrderID'} = $order->{'merchant_order_id'}|| '';
    $newHash->{'identifier'} = $order->{'identifier'} || '';
    $newHash->{'creationDate'} = $customDateTime;
    $newHash->{'authAmount'} = $order->{'auth_amount'} || '';
    $newHash->{'creditAmount'} = $order->{'credit_amount'} || '';
    $newHash->{'amount'} = $order->{'amount'} || '';
    $newHash->{'customers'} = $order->{'customers'} || '';
    $newHash->{'transStatus'} = $order->{'trans_status'} || '';
    $newHash->{'cardNumbers'} = $order->{'card_numbers'} || '';
    $newHash->{'accountCodes'} = $order->{'account_codes'} || '';
    $newHash->{'transactionStates'} = $order->{'transaction_states'} || '';
    push @convertedOrders, $newHash;
  }

  return \@convertedOrders;
}

sub legacyOrdersToJSON {
  my $self = shift;
  my $orders = shift;
  my @convertedOrders = ();
  my $time = new PlugNPay::Sys::Time();
  my $loader = new PlugNPay::Transaction::Loader();
  foreach my $orderID (keys %{$orders}) {
    my $order = $loader->convertToTransactionObject($orders->{$orderID});
    my $hash = {};
    $hash->{'merchantOrderID'} = $orderID;
    $hash->{'identifier'} = $order->getGatewayAccount();
    my $extra = $order->getExtraTransactionData();
    if (ref($extra) eq 'HASH' && $extra->{'creation_date'} =~ /^\d{6}T\d{6}Z/) {
      $time->fromFormat('iso',$extra->{'creation_date'});
      $hash->{'creationDate'} = $time->inFormat('db_gm');
    } elsif ($order->getTransactionDateTime()) {
      my $dbTime = $time->inFormatDetectType('db_gm',$order->getTransactionDateTime());
      $dbTime =~ s/[^\d :-]//g;
      $hash->{'creationDate'} = $dbTime;
    } elsif ($order->getOrderID()) {
      my $genDateTime = substr($order->getOrderID(),0,8);
      $time->fromFormat('gendatetime',$genDateTime);
      $hash->{'creationDate'} = $time->inFormat('db_gm');
    } elsif($order->getTime()) {
      $time->fromFormat('unix',$order->getTime());
      $hash->{'creationDate'} = $time->inFormat('db_gm');
    } else {
      $hash->{'creationDate'} = '';
    }

    if ($hash->{'creationDate'} ne '') {
      $hash->{'creationDate'} = new PlugNPay::Transaction::JSON()->convertTimeFormat($hash->{'creationDate'});
    }

    $hash->{'amount'} = sprintf("%.2f",$order->getTransactionAmount());
    $hash->{'transStatus'} = $self->buildLegacyStatuses($order);
    $hash->{'transactionStates'} = [$order->getTransactionState()];
    $hash->{'customers'} = $order->getBillingInformation()->getFullName() || '';
    my $payment = $order->getPayment();
    $hash->{'cardNumbers'} = [$payment->getMaskedNumber()];
    $hash->{'accountCodes'} = [$order->getAccountCode(1),$order->getAccountCode(2),$order->getAccountCode(3),$order->getAccountCode(4)];

    push @convertedOrders,$hash;
  }
  return \@convertedOrders;
}  

sub itemizationToJSON {
  my $self = shift;
  my $items = shift;
  my @convertedItems = ();
  foreach my $item (@{$items}) {
    my $newHash = {};
    $newHash->{'name'} = $item->{'name'} || '';
    $newHash->{'cost'} = $item->{'cost'}|| '';
    $newHash->{'description'} = $item->{'description'} || '';
    $newHash->{'discount'} = $item->{'discount'} || '';
    $newHash->{'quantity'} = $item->{'quantity'} || '';
    $newHash->{'tax'} = $item->{'tax'} || '';
    $newHash->{'commodityCode'} = $item->{'commodityCode'} || '';
    $newHash->{'custom1'} = $item->{'custom_1'} || '';
    $newHash->{'custom2'} = $item->{'custom_2'} || '';
    $newHash->{'isTaxable'} = $item->{'isTaxable'} || '';
    $newHash->{'unit'} = $item->{'unit'} || '';
    push @convertedItems, $newHash;
  }

  return \@convertedItems;
}

sub buildLegacyStatuses {
  my $self = shift;
  my $order = shift;
  my $transState = $order->getTransactionState();
  my $status;
  my ($stateName, $subStateName) = split('_',$transState);
  
  if (uc($stateName) eq 'POSTAUTH') {
    if( $subStateName eq 'READY') {
      $status = 'Marked';
    } else {
      $status = 'Settlement';
    }
  } elsif ($stateName =~ /^[AUTH|REAUTH]/i) {
    $status = 'Authorization';
  } elsif ($stateName =~ /^SALE/i) {
    $status = 'Sale';
  } elsif ($stateName =~ /VOID/i) {
    $status = 'Voided';
  } elsif ($stateName =~ /CREDIT|RETURN/i) {
    if ($order->getPNPTransactionReferenceID()) {
      $status = 'Return';
    } else {
      $status = 'Credit';
    }
  } else {
    $status = ucfirst($stateName);
  }

  if ($status ne 'Voided' && $status ne 'Marked') {
    if ($subStateName eq 'PROBLEM') {
      if ($stateName eq 'AUTH' || $stateName eq 'SALE' || $stateName eq 'CREDIT') {
        my $extraData = $order->getExtraTransactionData();
        $status .= ($extraData->{'response_data'}{'status'} =~ /badcard|decline/i ? ' Declined' : ' Failure');
      } else {
        $status .= ' Failure';
      }
    } elsif ($subStateName eq 'PENDING') {
      $status .= ' Pending';
    } else {
      $status .= ' Successful';
    }
  }

  return $status;
}

1;
