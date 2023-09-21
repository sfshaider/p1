package PlugNPay::Membership::Plan::PasswordDigestType;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Cache::LRUCache;

our $digestCache;
our $idCache;

#########################################
# Module: PasswordDigestType
# ---------------------------------------
# Description:
#   This module loads information for
#   password management. The payment
#   plan will determine what type of
#   password hash the remote server uses.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  if (!defined $digestCache || !defined $idCache) {
    $digestCache = new PlugNPay::Util::Cache::LRUCache(3);
    $idCache = new PlugNPay::Util::Cache::LRUCache(3);
  } 

  return $self;
}

sub setDigestID {
  my $self = shift;
  my $digestID = shift;
  $self->{'digestID'} = $digestID;
}

sub getDigestID {
  my $self = shift;
  return $self->{'digestID'};
}

sub setDigestType {
  my $self = shift;
  my $digestType = shift;
  $self->{'digestType'} = $digestType;
}

sub getDigestType {
  my $self = shift;
  return $self->{'digestType'};
}

sub loadDigest {
  my $self = shift;
  my $digestID = shift || $self->{'digestID'};

  if ($digestCache->contains($digestID)) {
    my $digestType = $digestCache->get($digestID);
    $self->{'digestID'} = $digestID;
    $self->{'digestType'} = $digestType;
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT type
          FROM recurring1_password_digest_type
          WHERE id = ?/, [$digestID], {})->{'result'};
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        my $digestType = uc $row->{'type'};
        $self->{'digestID'} = $digestID;
        $self->{'digestType'} = $digestType;
        $digestCache->set($digestID, $digestType);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

sub loadDigestID {
  my $self = shift;
  my $type = uc shift;

  if ($idCache->contains($type)) {
    my $typeID = $idCache->get($type);
    $self->{'digestType'} = $type;
    $self->{'digestID'} = $typeID;
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id
          FROM recurring1_password_digest_type
          WHERE UPPER(type) = ?/, [$type], {})->{'result'};
      if (@{$rows} > 0) {
        my $digestID = $rows->[0]{'id'};
        $self->{'digestType'} = $type;
        $self->{'digestID'} = $digestID;
        $idCache->set($type, $digestID);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

################################
# Subroutine: loadDigestSelect
# ------------------------------
# Description:
#   Helper function to loads 
#   password digest types into
#   a html select tag.
sub loadDigestSelect {
  my $self = shift;
 
  my $digestList = {};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id, 
               type
        FROM recurring1_password_digest_type/, [], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        $digestList->{$row->{'id'}} = $row->{'type'};
      }
    }
  };

  if ($@) {
    $self->_log({
      'error' => $@
    });
  }

  return $digestList;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_password_digest_type' });
  $logger->log($logInfo);
}

1;
