package PlugNPay::Merchant::Customer::PaymentSource::ACH::Type;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Cache::LRUCache;

our $idCache;
our $typeCache;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  if (!defined $idCache || !defined $typeCache) {
    $idCache = new PlugNPay::Util::Cache::LRUCache(2);
    $typeCache = new PlugNPay::Util::Cache::LRUCache(2);
  }

  return $self;
}

sub setAccountTypeID {
  my $self = shift;
  my $accountTypeID = shift;
  $self->{'accountTypeID'} = $accountTypeID;
}

sub getAccountTypeID {
  my $self = shift;
  return $self->{'accountTypeID'};
}

sub setAccountType {
  my $self = shift;
  my $accountType = shift;
  $self->{'accountType'} =  $accountType;
}

sub getAccountType {
  my $self = shift;
  return $self->{'accountType'};
}

sub loadACHAccountType {
  my $self = shift;
  my $accountTypeID = shift;

  my $accountType;
  if ($typeCache->contains($accountTypeID)) {
    $accountType = $typeCache->get($accountTypeID);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT account_type
          FROM customer_payment_source_ach_type
          WHERE id = ?/, [$accountTypeID], {})->{'result'};
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        $accountType = $row->{'account_type'};
        $typeCache->set($accountTypeID, $accountType);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }

  $self->{'accountTypeID'} = $accountTypeID;
  $self->{'accountType'} = $accountType;
}

sub loadACHAccountTypeID {
  my $self = shift;
  my $accountType = lc shift;

  my $accountTypeID;
  if ($idCache->contains($accountType)) {
    $accountTypeID = $idCache->get($accountType);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id
          FROM customer_payment_source_ach_type
          WHERE LOWER(account_type) = ?/, [$accountType], {})->{'result'};
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        $accountTypeID = $row->{'id'};
        $idCache->set($accountType, $accountTypeID);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }

  $self->{'accountTypeID'} = $accountTypeID;
  $self->{'accountType'} = $accountType;
}

sub loadACHAccountTypeHash {
  my $self = shift;

  my $accountTypes = {};
 
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id, 
               account_type
        FROM customer_payment_source_ach_type/, [], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        $accountTypes->{$row->{'id'}} = $row->{'account_type'};
      }
    }
  };

  if ($@) {
    $self->_log({
      'error' => $@
    });
  }

  return $accountTypes;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'customer_paymentsource_ach_type' });
  $logger->log($logInfo);
}

1;
