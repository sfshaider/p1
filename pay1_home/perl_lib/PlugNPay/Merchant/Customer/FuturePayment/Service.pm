package PlugNPay::Merchant::Customer::FuturePayment::Service;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Cache::LRUCache;

our $idCache;
our $serviceCache;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  if (!defined $idCache || !defined $serviceCache) {
    $idCache = new PlugNPay::Util::Cache::LRUCache(3);
    $serviceCache = new PlugNPay::Util::Cache::LRUCache(3);
  }

  return $self;
}

sub setServiceID {
  my $self = shift;
  my $serviceID = shift;
  $self->{'serviceID'} = $serviceID;
}

sub getServiceID {
  my $self = shift;
  return $self->{'serviceID'};
}

sub setServiceName {
  my $self = shift;
  my $serviceName = shift;
  $self->{'serviceName'} = $serviceName;
}

sub getServiceName {
  my $self = shift;
  return $self->{'serviceName'};
}

sub loadService {
  my $self = shift;
  my $serviceID = shift;

  my $service;
  if ($idCache->contains($serviceID)) {
    $service = $idCache->get($serviceID);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT service
          FROM customer_future_payment_service
          WHERE id = ?/, [$serviceID], {})->{'result'};
      if (@{$rows} > 0) {
        $service = uc $rows->[0]{'service'};
        $idCache->set($serviceID, $service);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }

  return $service;
}

sub loadServiceID {
  my $self = shift;
  my $service = uc shift;

  my $serviceID;
  if ($serviceCache->contains($service)) {
    $serviceID = $serviceCache->get($service);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id
          FROM customer_future_payment_service
          WHERE UPPER(service) = ?/, [$service], {})->{'result'};
      if (@{$rows} > 0) {
        $serviceID = $rows->[0]{'id'};
        $serviceCache->set($service, $serviceID);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }

  return $serviceID;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'customer_future_payment_service' });
  $logger->log($logInfo);
}

1;
