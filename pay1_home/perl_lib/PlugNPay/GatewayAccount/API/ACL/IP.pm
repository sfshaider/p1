package PlugNPay::GatewayAccount::API::ACL::IP;

# NOTE: This interfaces with pnpmisc.ipaddress

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::IP::Address;
use PlugNPay::Util::Cache::LRUCache;

our $ipCache;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!defined $ipCache) {
    $ipCache = new PlugNPay::Util::Cache::LRUCache(5);
  }

  return $self;
}

sub setUsername {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return $self->{'username'};
}

sub setIPAddress {
  my $self = shift;
  my $ipAddress = shift;
  $self->{'ipAddress'} = $ipAddress;
}

sub getIPAddress {
  my $self = shift;
  return $self->{'ipAddress'};
}

sub loadIP {
  my $self = shift;
  my $ipAddress = shift || $self->getIPAddress();
  my $username = shift || $self->getUsername();


  if (!$ipAddress || !$username) {
    die "Missing required data from loadIP\n";
  }

  my $ipChecker = new PlugNPay::Util::IP::Address();
  my $loaded = [];
  if ($ipChecker->isIPv4($ipAddress)) {
    my $cacheKey = $username . ':' . $ipAddress;
    if (!$ipCache->contains($cacheKey)) {
      $loaded = $self->_load($username,$ipAddress);
      if (@{$loaded} > 0) {
        $ipCache->set($cacheKey, $loaded);
      }
    } else {
      $loaded = $ipCache->get($cacheKey);
    }
  } else {
    die "Invalid IPv4 Address\n";
  }

  return $loaded;
}

sub _load {
  my $self = shift;
  my $username = shift;
  my $ipAddress = shift;
  my $rows = [];
  my $dbs = new PlugNPay::DBConnection();

  my $select = q/
    SELECT username, ipaddress, netmask
      FROM ipaddress
     WHERE username = ?
       AND ipaddress = ?
  /;
 
  eval {
    $rows = $dbs->fetchallOrDie('pnpmisc', $select, [$username, $ipAddress], {})->{'result'};
  };

  return $rows;
}

sub saveIP {
  my $self = shift;
  my $username = shift;
  my $ipAddress = shift;
  my $netMask = shift || 24;

  my $ipChecker = new PlugNPay::Util::IP::Address();
  if ($username ne '' && $ipChecker->isIPv4($ipAddress) && $netMask =~ /^\d{2}$/) {
    my $dbs = new PlugNPay::DBConnection();
    my $insert = q/
       INSERT INTO ipaddress (`username`, `ipaddress`, `netmask`)
            VALUES (?,?,?)
    /;
    eval {
      $dbs->executeOrDie('pnpmisc', $insert, [$username, $ipAddress, $netMask]);
    };
 
    my $cacheKey = $username . ':' . $ipAddress;
    if (!$@ && $ipCache->contains($cacheKey)) {
      my $existing = $ipCache->get($cacheKey);
      push @{$existing},{'username' => $username, 'ipaddress' => $ipAddress, 'netmask' => $netMask};
      $ipCache->set($cacheKey, $existing);
    } elsif ($@) {
      die $@ . "\n";
    }
  } else {
    die "invalid input in saveIP\n";
  }
}

1;
