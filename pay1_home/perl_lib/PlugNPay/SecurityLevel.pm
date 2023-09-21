package PlugNPay::SecurityLevel;

use strict;
use PlugNPay::DBConnection;


our $_data;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  $self->loadIfNotLoaded();

  return $self;
}

sub loadIfNotLoaded {

  if (ref($_data) eq 'HASH') {
    return;
  }

  my %accessData;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
                           SELECT area,security_level
                           FROM security_level_access
                          /);

  $sth->execute();

  my $results = $sth->fetchall_arrayref({});

  for my $row (@{$results}) {
    if (!defined $accessData{$row->{'area'}}) {
      $accessData{$row->{'area'}} = [];
    }
    push @{$accessData{$row->{'area'}}},$row->{'security_level'};
  }

  $_data = \%accessData;
}

sub securityLevelHasAccessTo {
  my $self = shift;
  my $securityLevel = shift;
  my $area = shift;
  if ( grep { /^$securityLevel$/ } @{$_data->{$area}} ) {
    return 1;
  }
  return 0;
}

1;
