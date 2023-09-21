package PlugNPay::Currency::LegacyHash::Tied;

use strict;
use Tie::Hash;
use vars qw(@ISA);

use PlugNPay::Currency::LegacyHash;

@ISA = qw(Tie::StdHash);

our $_data_;

sub TIEHASH {
  my $self = {};
  bless $self,shift;

  my $mapping = shift; # hash ref, { key => "key", value => "key" }
  my $key = $mapping->{'key'};
  my $value = $mapping->{'value'};

  $self->{'!@#$%^&*_mapping_*&^%$#@!'} = $mapping; # a name unlikely to be used in the hash

  return $self;
}

sub _load {
  my $self = shift;

  if (!defined $_data_) {
    my $dataSource = new PlugNPay::Currency();
    $_data_ = $dataSource->loadAllCurrencyData();
  }

  # only load data once from _data_
  if (defined $self->{'!@#$%^&*_mapping_*&^%$#@!'}) {
    my $keyKey   = $self->{'!@#$%^&*_mapping_*&^%$#@!'}{'key'};
    my $valueKey = $self->{'!@#$%^&*_mapping_*&^%$#@!'}{'value'};

    $self->DELETE('!@#$%^&*_mapping_*&^%$#@!');
    # print STDERR Dumper($_data_); use Data::Dumper;

    foreach my $data (values %{$_data_}) {
      $self->STORE(lc $data->{$keyKey}, $data->{$valueKey});
    }
  }
}

sub FETCH {
  my $self = shift;
  my $key = lc shift;

  $self->_load();

  return $self->{$key};
}

sub FIRSTKEY {
  my $self = shift;

  $self->_load();
  my @keys = keys %{$self};
  my $firstKey = shift @keys;
  return $firstKey;
}

1;
