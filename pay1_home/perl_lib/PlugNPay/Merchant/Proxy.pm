package PlugNPay::Merchant::Proxy;

use strict;
use PlugNPay::Merchant;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Cache::LRUCache;

use overload '""' => \&getMasterMerchantID;

our $proxyCache;

#########################################
# Module: PlugNPay::Merchant::Proxy
# ---------------------------------------
# Description:
#   Proxy object will contain info on
#   the master and linked account.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  if (!defined $proxyCache) {
    $proxyCache = new PlugNPay::Util::Cache::LRUCache(10);
  }

  my $merchant = shift;
  if ($merchant) {
    $self->setMerchantID($merchant);
    $self->_load();
  }

  return $self;
}

sub setMerchantID {
  my $self = shift;
  my $merchant = shift;

  if ($merchant !~ /^[0-9]+$/) {
    $merchant = new PlugNPay::Merchant($merchant)->getMerchantID();
  }

  $self->{'merchantID'} = $merchant;
}

sub getMerchantID {
  my $self = shift;
  return $self->{'merchantID'};
}

sub setMasterMerchantID {
  my $self = shift;
  my $masterMerchantID = shift;
  $self->{'masterMerchantID'} = $masterMerchantID;
}

sub getMasterMerchantID {
  my $self = shift;
  return $self->{'masterMerchantID'};
}

#################################
# Subroutine: isMaster
# -------------------------------
# Description:
#   Returns true if the merchant
#   is the master account
sub isMaster {
  my $self = shift;
  return ($self->{'masterMerchantID'} == $self->{'merchantID'});
}

############################################
# Subroutine: _load
# ------------------------------------------
# Description:
#   Loads the "database" of customers given
#   a merchant.
sub _load {
  my $self = shift;
  my $merchantID = $self->{'merchantID'};

  my $masterMerchantID;
  if ($proxyCache->contains($merchantID)) {
    $masterMerchantID = $proxyCache->get($merchantID);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT customer_dataset_id
          FROM merchant_customer_dataset
          WHERE merchant_id = ?/, [$merchantID], {})->{'result'};
      if (@{$rows} > 0) {
        $masterMerchantID = $rows->[0]{'customer_dataset_id'};
      } else {
        # if there is no master set, then the default is current merchant.
        $masterMerchantID = $merchantID;
        # attempt to save so load can be successful next time
        $self->saveMasterMerchantID($merchantID, $masterMerchantID);
      }

      $proxyCache->set($merchantID, $masterMerchantID);
    };

    if ($@) {
      $masterMerchantID = undef; # if the load fails from the db, avoid exposing the current account's customers

      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_database' });
      $logger->log({
        'error'      => $@,
        'function'   => '_load',
        'merchantID' => $merchantID
      });
    }
  }

  $self->{'masterMerchantID'} = $masterMerchantID;
}

sub saveMasterMerchantID {
  my $self = shift;
  my $merchantID = shift;
  my $masterMerchantID = shift || $merchantID;

  my $status = new PlugNPay::Util::Status(1);
  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/INSERT INTO merchant_customer_dataset
        ( merchant_id,
          customer_dataset_id )
        VALUES (?,?)/, [$merchantID, $masterMerchantID]);
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_database' });
    $logger->log({
      'error'                     => $@,
      'function'                  => 'saveMasterMerchantID',
      'merchantID'                => $merchantID,
      'merchantCustomerDataSetID' => $masterMerchantID 
    });

    $status->setFalse();
    $status->setError('Failed to save merchant customer database.');
  }

  return $status;
}

sub updateMasterMerchantID {
  my $self = shift;
  my $merchantID = shift;
  my $masterMerchantID = shift;

  my $status = new PlugNPay::Util::Status(1);
  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/UPDATE merchant_customer_dataset
        SET customer_dataset_id = ?
        WHERE merchant_id = ?/, [$masterMerchantID, $merchantID]);
    if ($proxyCache->contains($merchantID)) {
      $proxyCache->set($merchantID, $masterMerchantID);
    }
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_database' });
    $logger->log({
      'error'      => $@,
      'function'   => 'updateMasterMerchantID',
      'merchantID' => $merchantID
    });

    $status->setFalse();
    $status->setError('Failed to update merchant customer database.');
  }

  return $status;
}

1;
