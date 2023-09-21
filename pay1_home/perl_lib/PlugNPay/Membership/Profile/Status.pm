package PlugNPay::Membership::Profile::Status;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Cache::LRUCache;

our $statusCache;
our $idCache;

######################################
# Module: Profile::Status
# ------------------------------------
# Description:
#   Profile statuses to determine 
#   whether the customer is actively
#   getting billed or has access to
#   remote server.

sub new {
  my $class = shift;
  my $self = {};

  bless $self, $class;
  
  if (!defined $statusCache || !defined $idCache) {
    $statusCache = new PlugNPay::Util::Cache::LRUCache(4);
    $idCache = new PlugNPay::Util::Cache::LRUCache(4);
  }

  return $self;
}

sub setStatusID {
  my $self = shift;
  my $statusID = shift;
  $self->{'statusID'} = $statusID;
}

sub getStatusID {
  my $self = shift;
  return $self->{'statusID'};
}

sub setStatus {
  my $self = shift;
  my $status = shift;
  $self->{'status'} = $status;
}

sub getStatus {
  my $self = shift;
  return $self->{'status'};
}

sub loadStatus {
  my $self = shift;
  my $statusID = shift || $self->{'statusID'};

  if ($statusCache->contains($statusID)) {
    my $status = $statusCache->get($statusID);
    $self->{'status'} = $status;
    $self->{'statusID'} = $statusID;
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT status
          FROM recurring1_profile_status
          WHERE id = ?/, [$statusID], {})->{'result'};
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        my $status = uc $row->{'status'};
        $statusCache->set($statusID, $status);
        $self->{'status'} = $status;
        $self->{'statusID'} = $statusID;
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

sub loadStatusID {
  my $self = shift;
  my $status = uc shift;
 
  if ($idCache->contains($status)) {
    my $statusID = $idCache->get($status);
    $self->{'statusID'} = $statusID;
    $self->{'status'} = $status;
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id
          FROM recurring1_profile_status
          WHERE UPPER(status) = ?/, [$status], {})->{'result'};
      if (@{$rows} > 0) {
        my $statusID = $rows->[0]{'id'};
        $idCache->set($status, $statusID);
        $self->{'statusID'} = $statusID;
        $self->{'status'} = $status;
      }
    };
  }

  if ($@) {
    $self->_log({
      'error' => $@
    });
  }
}

sub loadAllStatuses {
  my $self = shift;

  my $statuses = [];

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT status
        FROM recurring1_profile_status/, [], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        push (@{$statuses}, uc $row->{'status'});
      }
    }
  };

  if ($@) {
    $self->_log({
      'error' => $@
    });
  }

  return $statuses;
}

####################################
# Subroutine: loadStatusSelect
# ----------------------------------
# Description:
#   Helper function that loads 
#   profile statuses into a html
#   select tag.
sub loadStatusSelect {
  my $self = shift;

  my $statusHash = {};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id, status
        FROM recurring1_profile_status/, [], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        $statusHash->{$row->{'id'}} = uc $row->{'status'};
      }
    }
  };

  if ($@) {
    $self->_log({
      'error' => $@
    });
  }

  return $statusHash;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_profile_status' });
  $logger->log($logInfo);
}

1;
