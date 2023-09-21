package PlugNPay::Private::BillingStatus;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Database::QueryBuilder;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub load {
  my $self = shift;
  my $searchData = shift;

  if (!defined $searchData) {
    die "no search data sent to BillingStatus to load with!\n";
  }

  my $values = [];

  my @searchRequirements = ();

  if ($searchData->{'result'}) {
    push @searchRequirements, ' result = ? ';
    push @{$values}, lc($searchData->{'result'});
  }

  if ($searchData->{'username'}) {
    push @searchRequirements, ' username = ? ';
    push @{$values}, lc($searchData->{'username'});
  }

  if ($searchData->{'paymentType'}) {
    if ($searchData->{'paymentType'} eq 'ach') {
      push @searchRequirements, ' card_type IN ("checking", "savings") ';
    } elsif ($searchData->{'paymentType'} eq 'none') {
      push @searchRequirements, ' (card_type = "none" OR card_type = "" OR card_type IS NULL) ';
    } else {
      push @searchRequirements, ' card_type = ? '; 
      push @{$values}, lc($searchData->{'paymentType'});
    } 
  }

  if ($searchData->{'start_date'} || $searchData->{'end_date'}) {
    my $dateSearch = new PlugNPay::Database::QueryBuilder()->generateDateRange($searchData);
    push @searchRequirements, ' trans_date IN (' . $dateSearch->{'params'} . ') ';
    push @{$values}, @{$dateSearch->{'values'}};
  }

  my $dbs = new PlugNPay::DBConnection();
  my $orderBy = '';
  if (ref($searchData->{'orderBy'}) eq 'ARRAY') {
    my $columns = $dbs->getColumnsForTable({'database' => 'pnpmisc', 'table' => 'billingstatus', 'format' => 'lower'});
    my @validOrderByCols = ();
    foreach my $item (@{$searchData->{'orderBy'}}) {
      if (exists $columns->{lc($item)}) {
        push @validOrderByCols, lc($item);
      }
    }

    if (@validOrderByCols > 0) {
      $orderBy = ' ORDER BY ' . join(',',@validOrderByCols) . ' ';
    }
  } else {
    $orderBy = ' ORDER BY card_type,descr,username ';
  }

  my $search = '';
  if (@searchRequirements > 0) {
    $search = ' WHERE ' . join(' AND ', @searchRequirements) . ' ';
  }
  my $rows = $dbs->fetchallOrDie('pnpmisc', q/
     SELECT username,orderid,result,amount,card_number,exp_date,descr,trans_date,card_type,checknum
       FROM billingstatus
      / . $search . ' ' . $orderBy, $values, {})->{'result'};

  return $rows;
}

1;
