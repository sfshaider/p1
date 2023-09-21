package PlugNPay::Util::Memcached;

use strict;

use Cache::Memcached;

sub new {
  my $class = shift;
  my $self = {};

  my $namespace = shift;

  $self->{'client'} = getMemcachedClient($namespace);

  bless $self, $class;
  return $self;
}

sub getMemcachedClient {
  my $namespace = shift || 'default-namespace';

  my $client = new Cache::Memcached {
    servers => [ "localhost:11211" ],
    debug => 0,
    compress_threshold => 10_000,
    namespace => $namespace
  }
}

sub set {
  my $self = shift;
  my $key = shift,        # scalar
  my $value = shift;      # can be an array ref or hash ref
  my $expiration = shift; # seconds

  eval {
    if (defined $expiration) {
      $expiration = getExpirationWithJitter($expiration);
      $self->{'client'}->set($key, $value, $expiration);
    } else {
      $self->{'client'}->set($key, $value);
    }
  };

  if ($@) {
    my $caller = join(':',caller());
    die(sprintf('Error setting data in memcached from %s: %s', $caller, $@))
  }
}

sub get {
  my $self = shift;
  my $key = shift;
  my $data;
  
  eval {
    $data = $self->{'client'}->get($key);
  };

  if ($@) {
    my $caller = join(':',caller());
    die(sprintf('Error getting data in memcached from %s: %s', $caller, $@))
  }

  return $data;
}

sub delete {
  my $self = shift;
  my $key = shift;

  eval {
    $self->{'client'}->delete($key);
  };

  if ($@) {
    my $caller = join(':',caller());
    die(sprintf('Error deleting data from memcached from %s: %s', $caller, $@))
  }
}

# returns an expiration that is +/- 20% of original expiration  
sub getExpirationWithJitter {
  my $expiration = shift;
  my $twentyPercent = int($expiration/5);
  my $randMax = $twentyPercent * 2 + 1;
  my $integer = int(rand($randMax));
  my $jitter = $integer - $twentyPercent;
  return $expiration + $jitter;
}

1;