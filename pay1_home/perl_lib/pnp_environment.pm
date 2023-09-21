#!/usr/bin/perl

use strict;

# the purpose of this module is to provide a safer way of accessing environment variables within a cgi script. When the script is loaded, the environment is copied into
# the local value %settings.  Get then queries this copy to get the values, so if environmental variables change, the original values are not affected

package pnp_environment;

my %settings = %ENV;

sub new
{
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self, $class;
  return $self;
}  


sub get
{
  my $self = shift;
  my $key = shift || $self;
  if ($key !~ /^PNP_/) { return ''; }
  return $settings{$key};
}

1;
