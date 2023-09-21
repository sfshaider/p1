#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );

use lib $ENV{'PNP_PERL_LIB'};


require_ok('PlugNPay::Recurring::Query'); # test that we can load the module!

TestLoadAllProfiles();
TestGetUsernames();

sub TestLoadAllProfiles {
  my $q = new PlugNPay::Recurring::Query({ database => 'jamestu2' });
  my $profiles = $q->queryProfiles();
  use Data::Dumper;
  diag(Dumper($profiles));
}

sub TestGetUsernames {
  my $q = new PlugNPay::Recurring::Query({ database => 'jamestu2' });
  my @usernames;
  $q->queryProfiles({
    options => {
      columns => ['username'],
      callback => sub {
        my $rows = shift;
        foreach my $row (@{$rows}) {
          push @usernames, $row->{'username'};
        }
      }
    }
  });
  use Data::Dumper;
  diag(Dumper(\@usernames));
}
