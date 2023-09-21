package PlugNPay::Transaction::AccountType;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

our $idCache;
our $codeCache;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!defined $codeCache || !defined $idCache) {
    $codeCache = new PlugNPay::Util::Cache::LRUCache(4);
    $idCache = new PlugNPay::Util::Cache::LRUCache(4);
  }

  return $self;
}

sub loadAccountType {
  my $self = shift;
  my $value = shift;
  my $mode = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/
                           SELECT id,identifier 
                           FROM account_type
                           WHERE / . ($mode eq 'code' ? ' identifier = ? ' : ' id = ? '));
  $sth->execute($value) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $code = $rows->[0]{'identifier'};
  my $id = $rows->[0]{'id'};

  if ($id && defined $code) {
    $self->_addToCaches($id,$code);
  }
}

sub addAccountType {
  my $self = shift;
  my $name = lc shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/ INSERT IGNORE INTO account_type (identifier) VALUES (?) /);
  $sth->execute($name) or die $DBI::errstr;

  $self->loadAccountType($name,'code');
}

sub getAccountTypeName {
  my $self = shift;
  my $id = shift;

  unless ($idCache->contains($id)) {
    $self->loadAccountType($id,'id');
  }

  return $idCache->get($id);
}

sub getAccountTypeID {
  my $self = shift;
  my $name = lc shift;

  unless ($codeCache->contains($name)) {
    $self->loadAccountType($name,'code');
  }

  unless ($codeCache->contains($name)) {
    $self->addAccountType($name);
  }

  return $codeCache->get($name);
}

sub _addToCaches {
  my $self = shift;
  my $key = shift;
  my $value = shift;
  
  $codeCache->set($value,$key);
  $idCache->set($key,$value);

}

1;
