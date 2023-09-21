package PlugNPay::Membership::Plan::Currency;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Cache::LRUCache;

our $idCache;
our $currencyCache;

###################################
# Module: Plan::Currency
# ---------------------------------
# Description:
#   Loads currency codes for a 
#   payment plan.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  if (!defined $currencyCache || !defined $idCache) {
    $currencyCache = new PlugNPay::Util::Cache::LRUCache(5);
    $idCache = new PlugNPay::Util::Cache::LRUCache(5);
  }

  return $self;
}

sub setCurrencyCode {
  my $self = shift;
  my $currencyCode = shift;
  $self->{'currencyCode'} = $currencyCode;
}

sub getCurrencyCode {
  my $self = shift;
  return $self->{'currencyCode'};
}

sub setCurrencyID {
  my $self = shift;
  my $currencyID = shift;
  $self->{'currencyID'} = $currencyID;
}

sub getCurrencyID {
  my $self = shift;
  return $self->{'currencyID'};
}

sub loadCurrency {
  my $self = shift;
  my $currencyID = shift || $self->{'currencyID'};

  if ($currencyCache->contains($currencyID)) {
    my $currencyCode = $currencyCache->get($currencyID);
    $self->{'currencyID'} = $currencyID;
    $self->{'currencyCode'} = $currencyCode;
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT iso_4217
          FROM currency
          WHERE id = ?/, [$currencyID], {})->{'result'};
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        my $currencyCode = uc $row->{'iso_4217'};
        $currencyCache->set($currencyID, $currencyCode);
        $self->{'currencyID'} = $currencyID;
        $self->{'currencyCode'} = $currencyCode;
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

sub loadCurrencyID {
  my $self = shift;
  my $currencyCode = uc shift;

  if ($idCache->contains($currencyCode)) {
    my $currencyID = $idCache->get($currencyCode);
    $self->{'currencyID'} = $currencyID;
    $self->{'currencyCode'} = $currencyCode;
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id
          FROM currency
          WHERE UPPER(iso_4217) = ?/, [$currencyCode], {})->{'result'};
      if (@{$rows} > 0) {
        my $currencyID = $rows->[0]{'id'};
        $self->{'currencyID'} = $currencyID;
        $self->{'currencyCode'} = $currencyCode;
        $idCache->set($currencyCode, $currencyID);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

########################################
# Subroutine: loadCurrencySelect
# --------------------------------------
# Description:
#   Helper function to load currencies 
#   into a html select tag.
sub loadCurrencySelect {
  my $self = shift;

  my $currencies = {};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id, iso_4217
        FROM currency/, [], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        $currencies->{$row->{'id'}} = $row->{'iso_4217'};
      }
    }
  };

  if ($@) {
    $self->_log({
      'error' => $@
    });
  } 

  return $currencies;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_currency' });
  $logger->log($logInfo);
}

1;
