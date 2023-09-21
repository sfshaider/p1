package PlugNPay::Order::Report::Status;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

our $idCache;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  if (!defined $idCache) {
    $idCache = new PlugNPay::Util::Cache::LRUCache(4);
  }

  return $self;
}

sub loadStatusID {
  my $self = shift;
  my $status = uc shift;

  my $statusID;
  if ($idCache->contains($status)) {
    $statusID = $idCache->get($status);
  } else {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc', q/SELECT id
                                         FROM orders_s3_status
                                         WHERE UPPER(status) = ?/);
    $sth->execute($status) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    if (@{$rows} > 0) {
      $statusID = $rows->[0]{'id'};

      $idCache->set($status, $statusID);
    }
  }

  return $statusID;
}

1;
