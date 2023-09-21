package PlugNPay::Transaction::Flags;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

our $idCache;
our $flagCache;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!defined $idCache || !defined $flagCache) {
    $idCache = new PlugNPay::Util::Cache::LRUCache(6);
    $flagCache = new PlugNPay::Util::Cache::LRUCache(6);
  }

  return $self;
}

sub getFlagID {
  my $self = shift;
  my $name = shift;

  unless ($flagCache->contains($name)) {
    $self->loadFlags($name,'flag');
  }

  unless($flagCache->contains($name)) { #Auto add flag key/value if needed
    $self->addFlag($name);
  }

  return $flagCache->get($name);
}

sub getFlagName {
  my $self = shift;
  my $id = shift;

  unless ($idCache->contains($id)) {
    $self->loadFlags($id,'id');
  }

  return $idCache->get($id);
}

sub loadFlags {
  my $self = shift;
  my $value = shift;
  my $mode = lc shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/SELECT id,name FROM transflag WHERE / . ($mode eq 'flag' ? ' name = ? ' : ' id = ? '));
  $sth->execute($value) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $id = $rows->[0]{'id'};
  my $flag = $rows->[0]{'name'};

  if ($id && defined $flag) {
    $self->_addToCaches($id,$flag);
  }

}

sub addFlag {
  my $self = shift;
  my $name = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/INSERT INTO transflag (name) VALUES (?)/);
  $sth->execute($name) or die $DBI::errstr;

  $self->loadFlags($name,'flag');
}

sub _addToCaches {
  my $self = shift;
  my $key = shift;
  my $value = shift;

  $idCache->set($key,$value);
  $flagCache->set($value,$key);
}

1;
