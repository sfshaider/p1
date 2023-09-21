package PlugNPay::Util::Cache::TimerCache;

use strict;
use Time::HiRes qw(time);

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $duration = shift;
  $self->setDuration($duration || 1.0);

  return $self;
}

sub setDuration {
  my $self = shift;
  my $duration = shift;

  if ($duration =~ /^\d+(\.\d+)?$/) {
    $self->{'duration'} = $duration;
  } else {
    $self->{'duration'} = 1.0;
  }
}

sub getDuration {
  my $self = shift;

  if (!defined $self->{'duration'}) {
    $self->{'duration'} = 1.0;
  }

  return $self->{'duration'};
}

# note that this does *not* reset the expiration, that is intended behavior.
# also note that, unlike lrucache, there is no "contains" sub, as the data
# could expire between the contains and the get.  so be sure to check for
# undef!
sub get {
  my $self = shift;
  my $key = shift;

  if ($self->{'cache'}{$key}) {
    if ($self->{'cache'}{$key}{'expires'} <= time()) {
      delete $self->{'cache'}{$key};
      return undef;
    }
    return $self->{'cache'}{$key}{'value'};
  }
}

sub set {
  my $self = shift;
  my $key = shift;
  my $value = shift;

  $self->purge();

  my $item = {
    value => $value,
    expires => time() + $self->{'duration'}
  };

  $self->{'cache'}{$key} = $item;
}

sub remove {
  my $self = shift;
  my $key = shift;

  delete $self->{'cache'}{$key};
}

sub purge {
  my $self = shift;
  foreach my $key (keys %{$self->{'cache'}}) {
    if ($self->{'cache'}{$key}{'expires'} <= time()) {
      delete $self->{'cache'}{$key};
    }
  }
}

1;
