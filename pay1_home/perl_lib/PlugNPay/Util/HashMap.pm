package PlugNPay::Util::HashMap;

use strict;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub hashMerge {
  my $self = shift;
  my $hash1 = shift;
  my $hash2 = shift;

  if (!keys(%{$hash1})) { # if hash1 is empty, return hash2, even if hash2 is empty
    return $hash2;
  }

  if (!keys(%{$hash2})) { # if hash2 is empty, return hash1
    return $hash1;
  }

  # if neither are empty, merge them!
  my $merged = {};
  foreach my $key (keys %{$hash1}) {
    $merged->{$key} = $hash1->{$key};
  }

  foreach my $key (keys %{$hash2}) {
    if(!defined $merged->{$key}) {
      $merged->{$key} = $hash2->{$key};
    } else {
      if (ref( $merged->{$key} ) eq 'ARRAY' && ref($hash2->{$key}) eq 'ARRAY') {
        my @array = (@{$merged->{$key}},@{$hash2->{$key}});
        $merged->{$key} = \@array;
      } elsif (ref($merged->{$key}) eq ref($merged->{$key})) {
        $merged->{$key} = $self->hashMerge($merged->{$key},$hash2->{$key});
      } else {
        die "Incompatible merge types!\n";
      }
    }
  }

  return $merged;
}

1;
