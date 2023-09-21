package PlugNPay::Membership::Plan::Type;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Cache::LRUCache;

our $idCache;
our $typeCache;

##########################################
# Module: Plan::Type
# ----------------------------------------
# Description:
#   Describes the type of transactions 
#   that will occur when a payment occurs.
#   i.e Auth | Credit

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

sub setType {
  my $self = shift;
  my $type = shift;
  $self->{'type'} = $type;
}

sub getType {
  my $self = shift;
  return $self->{'type'};
}

sub setTypeID {
  my $self = shift;
  my $typeID = shift;
  $self->{'typeID'} = $typeID;
}

sub getTypeID {
  my $self = shift;
  return $self->{'typeID'};
}

sub setDisplayName {
  my $self = shift;
  my $displayName = shift;
  $self->{'displayName'} = $displayName;
}

sub getDisplayName {
  my $self = shift;
  return $self->{'displayName'};
}

sub setDescription {
  my $self = shift;
  my $description = shift;
  $self->{'description'} = $description;
}

sub getDescription {
  my $self = shift;
  return $self->{'description'};
}

sub loadPlanType {
  my $self = shift;
  my $typeID = shift || $self->{'typeID'};

  if ($typeCache->contains($typeID)) {
    my $data = $typeCache->get($typeID);
    $self->_setTypeData($data);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id,
                 transaction_type,
                 display_name,
                 description
          FROM recurring1_transaction_type
          WHERE id = ?/, [$typeID], {})->{'result'};
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        $typeCache->set($typeID, $row);
        $self->_setTypeData($row);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

sub loadPlanTypeID {
  my $self = shift;
  my $type = uc shift;

  if ($idCache->contains($type)) {
    my $data = $idCache->get($type);
    $self->_setTypeData($data);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id
          FROM recurring1_transaction_type
          WHERE UPPER(transaction_type) = ?/, [$type], {})->{'result'};
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        $idCache->set($type, $row);
        $self->_setTypeData($row);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

sub _setTypeData {
  my $self = shift;
  my $data = shift;

  $self->{'type'}        = $data->{'transaction_type'};
  $self->{'typeID'}      = $data->{'id'};
  $self->{'displayName'} = $data->{'display_name'};
  $self->{'description'} = $data->{'description'};
}

#################################
# Subroutine: loadTypeSelect
# -------------------------------
# Description:
#   Helper function to load plan
#   transaction types into a 
#   html select tag.
sub loadTypeSelect {
  my $self = shift;

  my $typeList = {};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id, 
               display_name 
        FROM recurring1_transaction_type/, [], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        $typeList->{$row->{'id'}} = $row->{'display_name'};
      }
    }
  };

  if ($@) {
    $self->_log({
      'error' => $@
    });
  }

  return $typeList;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_plan_type' });
  $logger->log($logInfo);
}

1;
