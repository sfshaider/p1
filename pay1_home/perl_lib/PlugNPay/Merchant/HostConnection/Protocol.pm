package PlugNPay::Merchant::HostConnection::Protocol;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Cache::LRUCache;

our $protocolCache;
our $idCache;

###################################################
# Module: Merchant::HostConnection::Protocol
# -------------------------------------------------
# Description:
#   Loads protocols for merchant host connections.
#   Ex. FTP, SFTP, SCP

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $idCache || !defined $protocolCache) {
    $idCache = new PlugNPay::Util::Cache::LRUCache(4);
    $protocolCache = new PlugNPay::Util::Cache::LRUCache(4);
  }

  return $self;
}

sub setProtocolID {
  my $self = shift;
  my $protocolID = shift;
  $self->{'protocolID'} = $protocolID;
}

sub getProtocolID {
  my $self = shift;
  return $self->{'protocolID'};
}

sub setProtocol {
  my $self = shift;
  my $protocol = shift;
  $self->{'protocol'} = $protocol;
}

sub getProtocol {
  my $self = shift;
  return $self->{'protocol'};
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

sub _setProtocolData {
  my $self = shift;
  my $protocolData = shift;

  $self->{'protocolID'}  = $protocolData->{'id'};
  $self->{'protocol'}    = $protocolData->{'proto'};
  $self->{'description'} = $protocolData->{'description'};
}

sub loadProtocol {
  my $self = shift;
  my $protocolID = shift;

  if ($protocolCache->contains($protocolID)) {
    my $protocolData = $protocolCache->get($protocolID);
    $self->_setProtocolData($protocolData);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id,
                 proto,
                 description
          FROM merchant_host_connection_protocol
          WHERE id = ?/, [$protocolID], {})->{'result'};
      if (@{$rows} > 0) {
        $protocolCache->set($protocolID, $rows->[0]);
        $self->_setProtocolData($rows->[0]);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

sub loadProtocolID {
  my $self = shift;
  my $protocol = uc shift;

  if ($idCache->contains($protocol)) {
    my $protocolData = $idCache->get($protocol);
    $self->_setProtocolData($protocolData);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id,
                 proto,
                 description
          FROM merchant_host_connection_protocol
          WHERE UPPER(proto) = ?/, [$protocol], {})->{'result'};
      if (@{$rows} > 0) {
        $idCache->set($protocol, $rows->[0]);
        $self->_setProtocolData($rows->[0]);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

###################################
# Subroutine: loadProtocolSelect
# ---------------------------------
# Description:
#   Helper function to load 
#   protocols into html select tag
sub loadProtocolSelect {
  my $self = shift;

  my $protocols = {};
  
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               proto
        FROM merchant_host_connection_protocol/, [], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        $protocols->{$row->{'id'}} = $row->{'proto'};
      }
    }
  };

  if ($@) {
    $self->_log({
      'error' => $@
    });
  }

  return $protocols;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'host_connection_protocol' });
  $logger->log($logInfo);
}

1;
