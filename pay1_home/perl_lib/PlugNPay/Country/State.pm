package PlugNPay::Country::State;

use strict;
use PlugNPay::Country;
use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $state = shift;
  if ($state) {
    $self->setState($state);
  }

  return $self;
}

sub setState {
  my $self = shift;
  my $state = uc shift;
  $self->{'state'} = $state;
  $self->_load();
}

sub getState {
  my $self = shift;
  return $self->{'state'};
}

sub setName {
  my $self = shift;
  my $name = shift;
  $self->{'name'} = $name;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub setCountry {
  my $self = shift;
  my $countryCode = shift;
  $self->{'country'} = $countryCode;
}

sub getCountry {
  my $self = shift;
  return $self->{'country'};
}

sub setTaxRate {
  my $self = shift;
  my $taxRate = shift;
  $self->{'taxRate'} = $taxRate;
}

sub getTaxRate {
  my $self = shift;
  return $self->{'taxRate'};
}

sub setCanSurcharge {
  my $self = shift;
  my $can = shift;
  $self->{'canSurcharge'} = $can;
}

sub getCanSurcharge {
  my $self = shift;
  if (!$self->_getExists()) {
    return 1;
  }

  return ($self->{'canSurcharge'} ? 1 : 0);
}

sub _load {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT tax_rate,common_name,country_id,can_surcharge
      FROM state_information
     WHERE abbreviation = ?
  /);

  $sth->execute($self->getState());

  my $result = $sth->fetchall_arrayref({});

  if ($result && $result->[0]) {
    $self->setCanSurcharge($result->[0]{'can_surcharge'});
    $self->setName($result->[0]{'common_name'});
    $self->setCountry($result->[0]{'country_id'});
    $self->setTaxRate($result->[0]{'tax_rate'});
    $self->_setExists(1);
  }
}

sub exists {
  my $self = shift;
  my $abbreviationOrName = shift || $self;

  my $exists;

  if (ref($self) ne '' && ref($self) eq ref($abbreviationOrName)) {
    $exists = $self->_getExists();
  } else {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT count(*) AS `exists` FROM state_information WHERE abbreviation = ? OR common_name = ?
    /);

    $sth->execute($abbreviationOrName,$abbreviationOrName);

    my $result = $sth->fetchall_arrayref({});

    if ($result && $result->[0]) {
      $exists = $result->[0]{'exists'};
      if (ref($self)) {
        $self->_setExists($exists);
      }
    }
  }
  return ($exists ? 1 : 0);
}

sub getStatesForCountry {
  my $self = shift;
  my $countryIdentifier = shift;

  my $countryID = new PlugNPay::Country($countryIdentifier)->getNumeric();
  
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT abbreviation, common_name
      FROM state_information
     WHERE country_id = ?
  /);

  $sth->execute($countryID);

  my $results = $sth->fetchall_arrayref({});

  my @states;
  if ($results) {
    foreach my $row (@{$results}) {
      my $state = {
        abbreviation => $row->{'abbreviation'},
        commonName => $row->{'common_name'}
      };
      push @states,$state;
    }
  }

  return \@states;
}

sub getSurchargeEligibleCountries {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/SELECT DISTINCT country_id
                                         FROM state_information/);
  $sth->execute();
  my $rows = $sth->fetchall_arrayref({});

  my $countries = {};
  foreach my $row (@{$rows}) {
    my $country = new PlugNPay::Country($row->{'country_id'});
    $countries->{$country->getNumeric()} = 1;
  }

  return $countries;
}

sub _setExists {
  my $self = shift;
  my $exists = shift;
  $self->{'exists'} = $exists;
}

sub _getExists {
  my $self = shift;
  return ($self->{'exists'} ? 1 : 0);
}

1;
