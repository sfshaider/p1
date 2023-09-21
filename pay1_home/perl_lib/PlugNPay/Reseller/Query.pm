package PlugNPay::Reseller::Query;

use strict;
use PlugNPay::DBConnection;

our $_cachedResellers_;

sub list {
  if ($_cachedResellers_) {
    # make a copy
    my @resellers = @{$_cachedResellers_};
    return \@resellers;
  }

  my $dbs = new PlugNPay::DBConnection();
  my $response = $dbs->fetchallOrDie('pnpmisc',q/
    SELECT username, name FROM salesforce
  /, [], {});
  my $rows = $response->{'result'};
  # only keep usernames where the username is not blank (or zero, but really, who has a username of 0)
  my %resellers = map { {"$_->{'username'}" => "$_->{'name'}"} } grep {$_->{'username'}} @{$rows};

  # make a copy to cache since we're returning a reference.
  my %cache = %resellers;
  $_cachedResellers_ = \%cache;

  return \%resellers;
}

1;
