package PlugNPay::Merchant::Customer::Job::Status;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Cache::LRUCache;

our $idCache;
our $statusCache;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  if (!defined $idCache || !defined $statusCache) {
    $idCache = new PlugNPay::Util::Cache::LRUCache(4);
    $statusCache = new PlugNPay::Util::Cache::LRUCache(4);
  }

  return $self;
}

sub loadStatus {
  my $self = shift;
  my $statusID = shift;

  my $status;
  if ($statusCache->contains($statusID)) {
    $status = $statusCache->get($statusID);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT status
          FROM merchant_cust_job_status
          WHERE id = ?/, [$statusID], {})->{'result'};
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        $statusCache->set($statusID, uc $row->{'status'});
        $status = uc $row->{'status'};
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }

  return $status;
}

sub loadStatusID {
  my $self = shift;
  my $status = uc shift;

  my $statusID;
  if ($idCache->contains($status)) {
    $statusID = $idCache->get($status);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id
          FROM merchant_cust_job_status
          WHERE UPPER(status) = ?/, [$status], {})->{'result'};
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        $idCache->set($status, $row->{'id'});
        $statusID = $row->{'id'};
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }

  return $statusID;
}

sub statusExists {
  my $self = shift;
  my $status = uc shift;

  if ($idCache->contains($status)) {
    return 1;
  }

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exist`
        FROM merchant_cust_job_status
        WHERE UPPER(status) = ?/, [$status], {})->{'result'};
    $exists = $rows->[0]{'exist'};
  };

  if ($@) {
    $self->_log({
      'error' => $@
    });
  }

  return $exists;
}

sub statusIDExists {
  my $self = shift;
  my $statusID = shift;

  if ($statusCache->contains($statusID)) {
    return 1;
  }

  my $exists = 0;
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exist`
        FROM merchant_cust_job_status
        WHERE id = ?/, [$statusID], {})->{'result'};
    $exists = $rows->[0]{'exist'};
  };

  if ($@) {
    $self->_log({
      'error' => $@
    });
  }

  return $exists;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'plugnpay-job-status' });
  $logger->log($logInfo);
}

1;
