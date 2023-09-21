package PlugNPay::Util::UniqueList;

use strict;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->initialize();

  my $arrayRef = shift;
  if (ref($arrayRef) eq 'ARRAY') {
    $self->fromArrayRef($arrayRef);
  }

  return $self;
}

sub fromArrayRef {
  my $self = shift;
  my $arrayRef = shift;

  if ($self->size() != 0) {
    $self->initialize();
  }

  $self->addArrayRef($arrayRef);
}

sub addItem {
  my $self = shift;
  my $item = shift;

  if (defined $item) {
    $self->{'array'}{$item} = 1;
  }
}

sub addArrayRef {
  my $self = shift;
  my $arrayRef = shift;

  foreach my $item (@{$arrayRef}) {
    $self->addItem($item);
  }
}

sub removeItem {
  my $self = shift;
  my $item = shift;
  
  delete $self->{'array'}{$item};
}

sub removeArrayRef {
  my $self = shift;
  my $arrayRef = shift;

  foreach my $item (@{$arrayRef}) {
    $self->removeItem($item);
  }
}

sub containsItem {
  my $self = shift;
  my $item = shift;

  return $self->{'array'}{$item};
}

sub initialize {
  my $self = shift;

  $self->{'array'} = {};
}

sub size {
  my $self = shift;
  my $size = keys %{$self->{'array'}};

  return $size;
}

sub getArray {
  my $self = shift;
  return keys %{$self->{'array'}};
}


1;
