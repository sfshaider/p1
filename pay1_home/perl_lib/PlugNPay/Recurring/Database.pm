package PlugNPay::Recurring::Database;

use strict;

use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::TimerCache;
use PlugNPay::Util::Array qw(inArray);

our $_raw_column_cache_;
our $_profile_table_ = 'customer';
our $_payment_source_potential_columns_ = [
  'exp',
  'enccardnumber',
  'shacardnumber',
  'accttype',
  'commcardtype',
  'cardnumber',
  'length',
  'orderid'
];

if (!defined $_raw_column_cache_) {
  $_raw_column_cache_ = new PlugNPay::Util::Cache::TimerCache(5); # cache for 5 seconds.  seems legit.  your average transaction.
}

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $input = shift;
  $self->{'database'} = lc $input->{'database'};
  if (!$self->{'database'}) {
    die('Invalid recurring database', {
      database => $self->{'database'}
    });
  }

  return $self;
}

sub profileColumns {
  my $self = shift;

  my $columnInfo = $self->_getRawCustomerColumnInfo();

  # profile coumns are everything except the payment source columns, we pretend they don't exist!
  my @columns = grep { !inArray($_,$self->paymentSourceColumns()) } keys %{$columnInfo};
  unshift @columns,'username';

  return \@columns;
}

sub profilTable {
  my $self = shift;

  return $_profile_table_;
}

sub paymentSourceColumns {
  my $self = shift;

  my $columnInfo = $self->_getRawCustomerColumnInfo();

  # filter out the profile columns
  my @columns = grep { inArray($_,$_payment_source_potential_columns_) } keys %{$columnInfo};
  unshift @columns,'username';

  return \@columns;
}

sub paymentSourceTable {
  my $self = shift;

  return $_profile_table_;
}

# gets raw column info for the customer table
sub _getRawCustomerColumnInfo {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();

  # for consiceness
  my $db = $self->{'database'};
  my $cacheKey = cacheKey($db,'customer');

  my $columnInfo;
  unless ($columnInfo = $_raw_column_cache_->get($cacheKey)) {
    $columnInfo = $dbs->getColumnsForTable({ database => $db, table => $_profile_table_ });
    $_raw_column_cache_->set($cacheKey,$columnInfo);
  }

  return $columnInfo;
}

sub cacheKey {
  my $database = shift;
  my $table = shift;
  return sprintf("%s|:|%s",$database,$table);
}

1;
