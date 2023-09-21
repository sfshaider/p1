package PlugNPay::Merchant;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Util::Cache::LRUCache;

our $cache;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $cache) {
    $cache = new PlugNPay::Util::Cache::LRUCache(5);
  }

  my $merchant = shift;
  if ($merchant =~ /^[0-9]+$/) {
    $self->loadMerchantUsername($merchant);
  } elsif ($merchant) {
    $self->loadMerchant($merchant);
  }
  
  return $self;
}

sub loadMerchants {
  my $self = shift;
  
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/SELECT username
                                             FROM merchant/);
  $sth->execute() or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  
  my $merchants = [];
  if (@{$rows} > 0) {
    foreach my $row (@{$rows}) {
      push (@{$merchants}, $row->{'username'});
    }
  }

  return $merchants;
}

sub loadMerchant {
  my $self = shift;
  my $username = shift || $self->getMerchantUsername();
  my $merchantID;

  if ($cache->contains($username)) {
    $merchantID = $cache->get($username);
  } else {
    my $internalID = new PlugNPay::GatewayAccount::InternalID();
    $merchantID = $internalID->getIdFromUsername($username);

    if ($self->hasMerchantID($merchantID)) {
      $merchantID = $self->loadMerchantID($username);
    } else {
      my $dbs = new PlugNPay::DBConnection();
      my $sth = $dbs->prepare('merchant_cust', q/INSERT INTO merchant (id, username)
                                                 VALUES (?,?)/);
      $sth->execute($merchantID, $username) or die $DBI::errstr;
      $merchantID = $sth->{'mysql_insertid'};
    }
    $cache->set($username, $merchantID);
  }

  $self->setMerchantUsername($username);
  $self->setMerchantID($merchantID);
}

sub loadMerchantID {
  my $self = shift;
  my $username = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/SELECT id 
                                             FROM merchant
                                             WHERE username = ?/);
  $sth->execute($username) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  return $rows->[0]{'id'};
}

sub hasMerchantID {
  my $self = shift;
  my $merchantID = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/SELECT COUNT(*) AS `exists`
                                             FROM merchant
                                             WHERE id = ?/);
  $sth->execute($merchantID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  return $rows->[0]{'exists'};
}

sub loadMerchantUsername {
  my $self = shift;
  my $merchantID = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/SELECT username
                                             FROM merchant
                                             WHERE id = ?/);
  $sth->execute($merchantID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  
  if (@{$rows} > 0) {
    my $row = $rows->[0];
    my $username = $row->{'username'};

    $self->setMerchantUsername($username);
    $self->setMerchantID($merchantID);
  }
}

sub setMerchantUsername {
  my $self = shift;
  my $merchant = shift;
  $self->{'merchant'} = $merchant;
}

sub getMerchantUsername {
  my $self = shift;
  return $self->{'merchant'};
}

sub setMerchantID {
  my $self = shift;
  my $merchantID = shift;
  $self->{'merchantID'} = $merchantID;
}

sub getMerchantID {
  my $self = shift;
  return $self->{'merchantID'};
}

sub setMerchantCustomers {
  my $self = shift;
  my $customers = shift;

  $self->{'customers'} = $customers;
}

sub getMerchantCustomers {
  my $self = shift;

  return $self->{'customers'};
}

1; 
