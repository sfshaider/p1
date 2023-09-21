package PlugNPay::Merchant::Customer::PaymentSource::Type;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Cache::LRUCache;

our $cache;
our $idCache;

###################################################
# Module: Merchant::Customer::PaymentSource::Type
# -------------------------------------------------
# Description:
#   Loads the types of payment sources. CARD || ACH

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;

  if (!defined $cache || !defined $idCache) {
    $cache = new PlugNPay::Util::Cache::LRUCache(2);
    $idCache = new PlugNPay::Util::Cache::LRUCache(2);
  }

  return $self;
}

sub setPaymentTypeID {
  my $self = shift;
  my $paymentTypeID = shift;
  $self->{'paymentTypeID'} = $paymentTypeID;
}

sub getPaymentTypeID {
  my $self = shift;
  return $self->{'paymentTypeID'};
}

sub setPaymentType {
  my $self = shift;
  my $paymentType = shift;
  $self->{'paymentType'} = $paymentType;
}

sub getPaymentType {
  my $self = shift;
  return $self->{'paymentType'};
}

sub loadPaymentType {
  my $self = shift;
  my $typeID = shift;

  my $type;
  if ($cache->contains($typeID)) {
    $type = $cache->get($typeID);
    $self->{'paymentTypeID'} = $typeID;
    $self->{'paymentType'} = $type;
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT type 
          FROM customer_payment_source_type
          WHERE id = ?/, [$typeID], {})->{'result'};
      if (@{$rows} > 0) {
        $type = uc $rows->[0]{'type'};
        $cache->set($typeID, $type);
        $self->{'paymentTypeID'} = $typeID;
        $self->{'paymentType'} = $type;
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

sub loadPaymentTypeID {
  my $self = shift;
  my $type = uc shift;

  my $typeID;
  if ($idCache->contains($type)) {
    my $typeID = $idCache->get($type);
    $self->{'paymentTypeID'} = $typeID;
    $self->{'paymentType'} = $type;
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id
          FROM customer_payment_source_type
          WHERE UPPER(type) = ?/, [$type], {})->{'result'};
      if (@{$rows} > 0) {
        $typeID = $rows->[0]{'id'};
        $idCache->set($type, $typeID);
        $self->{'paymentTypeID'} = $typeID;
        $self->{'paymentType'} = $type;
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

######################################
# Subroutine: loadPaymentTypeSelect
# ------------------------------------
# Description:
#   Helper function for loading types
#   into html select tag.
sub loadPaymentTypeSelect {
  my $self = shift;
 
  my $paymentTypes = {};
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id, 
               type
        FROM customer_payment_source_type/, [], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        $paymentTypes->{$row->{'id'}} = $row->{'type'};
      }
    }
  };

  if ($@) {
    $self->_log({
      'error' => $@
    });
  }

  return $paymentTypes;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'customer_paymentsource_type' });
  $logger->log($logInfo);
}

1;
