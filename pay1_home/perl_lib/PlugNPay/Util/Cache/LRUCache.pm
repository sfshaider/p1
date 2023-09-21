package PlugNPay::Util::Cache::LRUCache;

use strict;
use PlugNPay::Die;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $size = shift;
  $self->setMaxSize($size);

  return $self;
}

sub setMaxSize {
  my $self = shift;
  my $size = shift;

  if ($size =~ /^\d+$/) {
    $self->{'maxSize'} = $size;
  } else {
    $self->{'maxSize'} = 1;
  }
}

sub getMaxSize {
  my $self = shift;

  if (!defined $self->{'maxSize'}) {
    $self->{'maxSize'} = 1;
  }

  return $self->{'maxSize'};
}


sub get {
  my $self = shift;
  my $key = shift;

  $self->_setRecent($key);
  return $self->{'cache'}{$key};
}

sub set {
  my $self = shift;
  my $key = shift;
  my $value = shift;

  $self->{'cache'}{$key} = $value;
  $self->_setRecent($key);
  $self->_checkMax();
}

sub contains {
  my $self = shift;
  my $key = shift;

  return ((grep { /^$key$/ } keys %{$self->{'cache'}}) ? 1 : 0);
}

sub remove {
  my $self = shift;
  my $key = shift;

  if (defined $self->{'lruArray'}) {
    my @array = grep { $_ ne $key } @{$self->{'lruArray'}};
    $self->{'lruArray'} = \@array;
  }

  delete $self->{'cache'}{$key};
}

sub setLastStatus {
  my $self = shift;
  $self->{'lastStatus'} = shift;
}

sub getLastStatus {
  my $self = shift;
  return $self->{'lastStatus'};
}

sub _setRecent {
  my $self = shift;
  my $key = shift;

  my @array;

  # if the array exists, remove the key from it if it's there
  if (defined $self->{'lruArray'}) {
    # delete the element from the array of keys if it exists
    my $originalSize = @array;

    eval {
      @array = grep { "$_" ne "$key" } @{$self->{'lruArray'}};
    };
    if ($@ ne '') {
      die($@);
    }

    my $deletedSize = @array;

    if ($originalSize > $deletedSize) {
      $self->setLastStatus('hit');
    } else {
      $self->setLastStatus('miss');
    }
  }

  # put the key to the front of the array of keys
  unshift @array,$key;

  # set the array to the modified array
  $self->{'lruArray'} = \@array;
}

sub _checkMax {
  my $self = shift;

  if (@{$self->{'lruArray'}} > $self->getMaxSize()) {
    my $elementToDelete = pop @{$self->{'lruArray'}};
    delete $self->{'cache'}{$elementToDelete};
  }
}



1;
