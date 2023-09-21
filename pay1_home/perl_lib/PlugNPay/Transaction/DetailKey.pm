package PlugNPay::Transaction::DetailKey;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

our $idCache;
our $nameCache;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!defined $idCache || !defined $nameCache) {
    $idCache = new PlugNPay::Util::Cache::LRUCache(6);
    $nameCache = new PlugNPay::Util::Cache::LRUCache(6);
  } 

  return $self;
}

sub loadDetailKey {
  my $self = shift;
  my $value = shift;
  my $mode = shift;
  my $select = q/SELECT id,name
                 FROM transaction_additional_processor_detail_key
                 WHERE /;
  $select .= ($mode eq 'detail' ? ' name = ? ' : ' id = ? ');

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction', $select);
  $sth->execute($value) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $id = $rows->[0]{'id'};
  my $detailName = $rows->[0]{'name'};

  if ($id && defined $detailName) {
    $self->_addToCaches($id,$detailName);
  } 
}

sub getDetailKeyID {
  my $self = shift;
  my $name = shift;

  unless ($nameCache->contains($name)) {
    $self->loadDetailKey($name,'detail');
  }

  unless ($nameCache->contains($name)) {
    $self->insertNewDetailKey($name);
  }

  return $nameCache->get($name);
}

sub getDetailKeyName {
  my $self = shift;
  my $id = shift;

  unless ($idCache->contains($id)) {
    $self->loadDetailKey($id,'id');
  }


  return $idCache->get($id);
}

sub insertNewDetailKey {
  my $self = shift;
  my $keyName = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/
                             INSERT INTO transaction_additional_processor_detail_key
                             (name)
                             VALUES (?)
                           /);
  $sth->execute($keyName) or die $DBI::errstr;
  $self->loadDetailKey($keyName,'detail');
}

sub _addToCaches {
  my $self = shift;
  my $id = shift;
  my $value = shift;

  $idCache->set($id,$value);
  $nameCache->set($value,$id);
}

1;
