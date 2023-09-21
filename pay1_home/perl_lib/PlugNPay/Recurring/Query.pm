package PlugNPay::Recurring::Query;

use strict;
use PlugNPay::Die;
use PlugNPay::Recurring::Database;
use PlugNPay::Database::Query;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $input = shift;
  $self->{'database'} = $input->{'database'};
  if (!$self->{'database'}) {
    die('Invalid recurring database', {
      database => $self->{'database'}
    });
  }

  return $self;
}

sub queryProfiles {
  my $self = shift;
  my $input = shift;

  my $criteria = $input->{'criteria'} || {};
  my $modifiers = $input->{'modifiers'} || {};
  my $options = $input->{'options'} || {};

  my $database = $self->{'database'};

  my $profileDb = new PlugNPay::Recurring::Database({ database => $database });
  my $columns = $profileDb->profileColumns();
  my $table = $profileDb->profilTable();

  my $q = new PlugNPay::Database::Query();

  my $profiles = [];

  # set a callback to return an array of profile objects if a callback is not defined.
  $options->{'callback'} ||= sub {
    my $rows = shift;
    foreach my $row (@{$rows}) {
      my $profile = new PlugNPay::Recurring::Profile();
      $profile->setProfileFromRow($row);
      push (@{$profiles}, $profile);
    }
  };

  $q->queryTable({
    database => $database,
    table => $table,
    columns => $columns,
    searchCriteria => $criteria,
    queryDetails => $modifiers,
    options => $options
   });

  return $profiles;
}


1;
