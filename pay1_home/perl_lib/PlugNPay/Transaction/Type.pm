package PlugNPay::Transaction::Type;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

our $typeCache;
our $idCache;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!defined $idCache || !defined $typeCache) {
    $idCache = new PlugNPay::Util::Cache::LRUCache(2);
    $typeCache = new PlugNPay::Util::Cache::LRUCache(2);
  }

  return $self;
}

sub getTransactionTypeID {
  my $self = shift;
  my $type = lc shift;
  $type = $self->validateType($type);

  unless ($typeCache->contains($type)) {
    $self->loadTransactionType($type,'type');
  }

  return $typeCache->get($type);
}

sub getTransactionTypeName {
  my $self = shift;
  my $id = shift;
  
  unless ($idCache->contains($id)) {
    $self->loadTransactionType($id,'id');
  }

  return $idCache->get($id);
}

sub loadTransactionType {
  my $self = shift;
  my $value = shift;
  my $mode = shift;
  
  my $where = ($mode eq 'type' ? ' type = ? ' : ' id = ? ');

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/ 
                           SELECT id,type 
                           FROM transaction_type  
                           WHERE / . $where); 
  $sth->execute($value) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $id = $rows->[0]{'id'};
  my $type = $rows->[0]{'type'};
  if ($id && defined $type) {
    $self->_addToCaches($id,$type);
  }
}

sub validateType {
  my $self = shift;
  my $type = lc shift;
  my $returnType;

  if ($type =~ /return/ || $type =~ /void/ || $type =~ /credit/) {
    $returnType = 'credit';
  } else {
    $returnType = 'authorization';
  }

  return $returnType;
}

sub _addToCaches {
  my $self = shift;
  my $key = shift;
  my $value = shift;

  $idCache->set($key,$value);
  $typeCache->set($value,$key);
}

1;
