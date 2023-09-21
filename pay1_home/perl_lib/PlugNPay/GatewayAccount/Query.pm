package PlugNPay::GatewayAccount::Query;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount;
use PlugNPay::Util::Array qw(inArray unique);
use PlugNPay::Util::Cache::LRUCache;
use PlugNPay::Database::Query;
use PlugNPay::Die;

our $_distinctColumnCache_;

if (!defined $_distinctColumnCache_) {
  $_distinctColumnCache_ = new PlugNPay::Util::Cache::LRUCache(5);
}

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

# used for web/private
sub query {
  my $self = shift;
  my $searchCriteria = shift || {};
  my $queryDetails = shift || {};
  my $options = shift || {};

  if (exists $searchCriteria->{'status'} && !$searchCriteria->{'useIndex'}) {
    $options->{'useIndex'} = 'customer_status_idx';
  }

  my $columns = PlugNPay::GatewayAccount::getColumns();

  my $gatewayAccounts = [];
  if (ref($searchCriteria ne 'HASH')) {
    return $gatewayAccounts;
  }

  my $q = new PlugNPay::Database::Query();

  $options->{'callback'} = sub {
    my $rows = shift;
    foreach my $row (@{$rows}) {
      my $ga = new PlugNPay::GatewayAccount();
      $ga->setAccountDataFromRow($row);
      push (@{$gatewayAccounts}, $ga);
    }
  };

  $q->queryTable({
    database => 'pnpmisc',
    table => 'customers',
    columns => $columns,
    searchCriteria => $searchCriteria,
    queryDetails => $queryDetails,
    options => $options
   });

  return $gatewayAccounts;
}

sub loadAccountsFromIds {
  my $self = shift;
  my $input = shift;
  my $ids = $input->{'ids'} || [];

  if (@{$ids} == 0) {
    return [];
  }

  my $dbs = new PlugNPay::DBConnection();
  my $columns = PlugNPay::GatewayAccount::getColumns();
  my $columnString = join(',', map { 'customers.' . $_ . ' as `' . $_ . '`' } @{$columns});
  my $idPlaceholders = join(',', map { '?' } @{$ids});

  my $query = qq/
    SELECT $columnString
      FROM customers, customer_id
     WHERE customer_id.username = customers.username
       AND customer_id.id in ($idPlaceholders)
     ORDER BY customers.username
  /;

  my $result = $dbs->fetchallOrDie('pnpmisc', $query, $ids, {});
  my $rows = $result->{'result'};
  my @accounts;
  foreach my $row (@{$rows}) {
    my $ga = new PlugNPay::GatewayAccount();
    $ga->setAccountDataFromRow($row);
    push @accounts, $ga;
  }
  return \@accounts;
}

sub distinctValues {
  my $self = shift;
  my $column = shift;
  my $options = shift;
  my @values;
  if ($_distinctColumnCache_->contains($column)) {
    return $_distinctColumnCache_->get($column);
  }

  my $columns = PlugNPay::GatewayAccount::getColumns();
  if (!inArray($column,$columns)) {
    die(sprintf('Invalid column: %s', $column));
  }

  my $collate = '';
  if ($options->{'collate'}) {
    $options->{'collate'} =~ s/[^a-zA-Z0-9_]//g;
    $collate = 'COLLATE ' . $options->{'collate'};
  }

  my $queryColumn = '`' . $column . '`';

  my $dbs = new PlugNPay::DBConnection();
  my $result = $dbs->fetchallOrDie('pnpmisc',qq/
    SELECT DISTINCT $queryColumn FROM customers $collate
  /,[],{});
  my $rows = $result->{'result'};

  my @rowValues = map { $_->{$column} } @{$rows};
  my $distinctValues = unique(\@rowValues, { quote => $options->{'quote'} });

  $_distinctColumnCache_->set($column, $distinctValues);

  return $distinctValues;
}

1;
