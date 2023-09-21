package PlugNPay::Util::Clone;

use strict;
use Scalar::Util 'blessed';

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub deepClone {
  my $self = shift;
  my $input = shift;
  my $settings = shift || {maxDepth => 20};
  my $depth = shift || 0;

  if ($depth >= $settings->{'maxDepth'}) {
    die('Clone reached maximum depth.');
  }

  my $unbless = $settings->{'unbless'};

  my $type = ref($input);
  my $object = blessed($input);

  # base case good for non-references and code references ('CODE')
  my $output = $input;

  my $bless_it = ($object && !$unbless);

  if ($type ne '' && $type ne 'CODE') {
    if ($type eq 'SCALAR' || ($object && $input->isa('SCALAR'))) {
      my $tmp = ${$input};
      $output = \$tmp;
      bless $output,$type if $bless_it;
    } elsif ($type eq 'ARRAY' || ($object && $input->isa('ARRAY'))) {
      my @tmp = map { $self->deepClone($_,$settings,$depth+1) } @{$input};
      $output = \@tmp;
      bless $output,$type if $bless_it;
    } elsif ($type eq 'HASH' || ($object && $input->isa('HASH'))) {
      my %tmp = map { $self->deepClone($_,$settings,$depth+1) => $self->deepClone($input->{$_},$settings,$depth+1) } keys %{$input};
      $output = \%tmp;
      bless $output,$type if $bless_it;
    }
  }

  return $output;
}

1;
