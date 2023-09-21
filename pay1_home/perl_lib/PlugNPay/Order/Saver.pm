package PlugNPay::Order::Saver;

use strict;
use PlugNPay::Order;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::Order::Detail;
use PlugNPay::Transaction::Saver;
use PlugNPay::Util::Status;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub save { # Saves Main order info
  my $self = shift;
  my $order = shift;
  my $time = new PlugNPay::Sys::Time();
  my $merchantOrderID = $order->getMerchantOrderID();
  my $id = $order->getMerchantID();
  my $status = new PlugNPay::Util::Status(1);
  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('pnp_transaction',q/
                           INSERT INTO `order`
                           (pnp_order_id,merchant_id,merchant_order_id,creation_date_time,merchant_classification_id)
                           VALUES (?,?,?,?,?)
                           /);
  eval {
    $sth->execute($order->getPNPOrderID(),$id,$merchantOrderID,$time->inFormat('iso_gm'),$order->getOrderClassifier()) or die $DBI::errstr;
  };

  if ($@) {
    $status->setFalse();
    $status->setError($@);
    $status->setErrorDetails('Error in saving order');
  }

  return $status;
}

sub saveOrderDetails { # Saves level 3 data
  my $self = shift;
  my $orderID = shift;
  my $orderDetails = shift;
  my $status = new PlugNPay::Util::Status(1);

  my @values = ();
  my @params = ();
  my $insert = 'INSERT INTO order_details
                (pnp_order_id,item_name,quantity,cost,
                 description,discount_amount,tax_amount,
                 commodity_code,item_info_1,item_info_2,
                 unit_of_measure,is_taxable)
                VALUES ';

  foreach my $item (@{$orderDetails}) {
    push @values, $orderID;
    push @values, $item->getName();
    push @values, $item->getQuantity();
    push @values, $item->getCost();
    push @values, $item->getDescription();
    push @values, $item->getDiscount();
    push @values, $item->getTax();
    push @values, $item->getCommodityCode();
    push @values, $item->getCustom1();
    push @values, $item->getCustom2();
    push @values, $item->getUnitOfMeasure();
    push @values, $item->isTaxable();
    push @params, '(?,?,?,?,?,?,?,?,?,?,?,?)';
  }

  $insert .= join(',',@params);

  if (@values > 0 && defined $orderID) {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnp_transaction',$insert);
    eval {
      $sth->execute(@values) or die $DBI::errstr;
    };

    if ($@) {
      $status->setFalse();
      $status->setError($@);
      $status->setErrorDetails('Error in saving order details');
    }
  }

  return $status;
}

sub saveTransactions { # Saves all transaction associated with order
  my $self = shift;
  my $order = shift;
  my $operation = shift;
  my $saver = new PlugNPay::Transaction::Saver();
  my @orderTransactions = @{$order->getOrderTransactions()};
  my @values = ();
  my @paramArr = ();
  my $success = $saver->save($order->getPNPOrderID(),\@orderTransactions,$operation);
  return $success;
}

sub legacySave {
  my $self = shift;
  my $orderData = shift;
  my $order = new PlugNPay::Order();

  return $self->save($order);
}

1;
