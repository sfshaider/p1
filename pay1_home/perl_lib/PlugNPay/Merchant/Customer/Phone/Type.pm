package PlugNPay::Merchant::Customer::Phone::Type;

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
    $idCache = new PlugNPay::Util::Cache::LRUCache(4);
    $typeCache = new PlugNPay::Util::Cache::LRUCache(4);
  }

  return $self;
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

sub setType {
  my $self = shift;
  my $type = shift;
  $self->{'type'} = $type;
}

sub getType {
  my $self = shift;
  return $self->{'type'};
}

sub loadType {
  my $self = shift;
  my $typeID = shift;

  my $type;
  if ($idCache->contains($typeID)) {
    $type = $idCache->get($typeID);
    $self->{'type'} = $type;
    $self->{'typeID'} = $typeID;
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT type
          FROM customer_phone_general_type
          WHERE id = ?/, [$typeID], {})->{'result'};
      if (@{$rows} > 0) {
        $type = uc $rows->[0]{'type'};
        $idCache->set($typeID, $type);
        $self->{'type'} = $type;
        $self->{'typeID'} = $typeID;
      }
    };

    if ($@) {
      $self->_log({
        'error'    => $@,
        'function' => 'loadType'
      });
    }
  }
}

sub loadTypeID {
  my $self = shift;
  my $type = uc shift;

  my $typeID;
  if ($typeCache->contains($type)) {
    $typeID = $typeCache->get($type);
    $self->{'type'} = $type;
    $self->{'typeID'} = $typeID;
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id
          FROM customer_phone_general_type
          WHERE UPPER(type) = ?/, [$type], {})->{'result'};
      if (@{$rows} > 0) {
        $typeID = $rows->[0]{'id'};
        $typeCache->set($type, $typeID);
        $self->{'typeID'} = $typeID;
        $self->{'type'} = $type;
      }
    };

    if ($@) {
      $self->_log({
        'error'    => $@,
        'function' => 'loadTypeID'
      });
    }
  }
}

###################################
# Subroutine: loadPhoneTypeSelect
# ---------------------------------
# Description:
#   Helper function to load phone 
#   types into an HMTL select tag.
sub loadPhoneTypeSelect {
  my $self = shift;
  my $type = shift || undef;

  my $phoneTypes = {};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               type
        FROM customer_phone_general_type/, [], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        if ($type) {
          if ($type =~ /fax/i) {
            if ($row->{'type'} =~ /fax/i) {
              $phoneTypes->{$row->{'id'}} = $row->{'type'};
            }
          } elsif ($type =~ /phone/i) {
            if ($row->{'type'} !~ /fax/i) {
              $phoneTypes->{$row->{'id'}} = $row->{'type'};
            }
          }
        } else {
          $phoneTypes->{$row->{'id'}} = $row->{'type'};
        }
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadPhoneTypeSelect'
    });
  }

  return $phoneTypes;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'customer_phone_type' });
  $logger->log($logInfo);
}

1;
