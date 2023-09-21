package PlugNPay::Country;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

our $countryCache;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;
  if (!defined $countryCache) {
    $countryCache = new PlugNPay::Util::Cache::LRUCache(1);
  }

  $self->loadCountries();

  my $country = shift;
  if ($country) {
    $self->setCountry($country);
  }

  return $self;
}

sub setCountry {
  my $self = shift;
  my $identifier = uc shift;
  $self->{'country'} = $identifier;
}

sub getNumeric {
  my $self = shift;
  my $country = uc shift || $self->{'country'};
  return $self->getCountryData($country)->{'numeric'};
}

sub getTwoLetter {
  my $self = shift;
  my $country = uc shift || $self->{'country'};
  return $self->getCountryData($country)->{'twoLetter'};
}

sub getThreeLetter {
  my $self = shift;
  my $country = uc shift || $self->{'country'};
  return $self->getCountryData($country)->{'threeLetter'};
}

sub getCommonName {
  my $self = shift;
  my $country = uc shift || $self->{'country'};
  return $self->getCountryData($country)->{'commonName'};
}

#############################################################
# The following two methods are for backwards compatibility #
#############################################################
sub twoFromThree {
  my $self = shift;
  my $input = uc shift;

  return $self->getTwoLetter($input);
}

sub threeFromTwo {
  my $self = shift;
  my $input = uc shift;

  return $self->getThreeLetter($input);
}
#############################################################

sub getCountries {
  my $self = shift;
  my $options = shift || {};

  if (!defined $self->{'countries'} && !$countryCache->contains('countries')) {
    $self->loadCountries();
  }

  my $output;
  my $countryList = $self->{'countries'} || $countryCache->get('countries');

  if (!defined $options->{'key'}) {
    $output = $countryList;
  } else {
    $output = {};
    foreach my $country (@{$countryList}) {
      $output->{$country->{$options->{'key'}}} = $country;
    }
  }

  return $output;
}

sub loadCountries {
  my $self = shift;

  if (!defined $self->{'countries'} && !$countryCache->contains('countries')) {
    my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

    my $sth = $dbh->prepare(q/
  	SELECT iso3166_numeric,
           iso3166_twoletter,
           iso3166_threeletter,
           common_name
  	FROM country_information
    /);

    $sth->execute();
    my $results = $sth->fetchall_arrayref({});
    my @countryData;

    if ($results) {
      foreach my $row (@{$results}) {
        my $data = {
          numeric => $row->{'iso3166_numeric'},
          twoLetter   => uc $row->{'iso3166_twoletter'},
          threeLetter => uc $row->{'iso3166_threeletter'},
          commonName  => $row->{'common_name'}
        };
        push @countryData,$data;
      }
      $self->{'countries'} = \@countryData;
      $countryCache->set('countries', \@countryData);
    }
  } elsif ($countryCache->contains('countries') && !defined $self->{'countries'}) {
    $self->{'countries'} = $countryCache->get('countries');
  }

  # this is here to preserve compatibility for now
  return $self->getCountries({key => 'twoLetter'});
}

sub exists {
  my $self = shift;
  my $identifier = shift;

  my $country = $self->getCountryData($identifier);

  return (keys %{$country} > 0);
}

sub getCountryData {
  my $self = shift;
  my $identifier = uc shift;

  my $countryData = $self->getCountries();

  # first try to match numeric if identifier is numeric, otherwise, match on twoLetter or threeLetter based on length.

  my $theCountry = {};
  if ($identifier =~ /^\d+$/) {
    foreach my $country (@{$countryData}) {
      if ($identifier eq $country->{'numeric'}) {
        $theCountry = $country;
        last;
      }
    }
  } elsif (length($identifier) == 2) {
    foreach my $country (@{$countryData}) {
      if ($identifier eq $country->{'twoLetter'}) {
        $theCountry = $country;
        last;
      }
    }
  } elsif (length($identifier) == 3) {
    foreach my $country (@{$countryData}) {
      if ($identifier eq $country->{'threeLetter'}) {
        $theCountry = $country;
        last;
      }
    }
  }

  return $theCountry;
}


# TODO: move this to PlugNPay::Country::State and add a call to it from here.
# do this to preserve heirarchy of tables and modules.
# UPDATE:: Actually get rid of this altogether.
sub loadCountryStateInfo {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
      SELECT c.iso3166_twoletter as country_code,
             c.common_name as country_name,
	     s.abbreviation as state_code,
	     s.common_name as state_name
      FROM country_information c, state_information s
      WHERE  s.country_id = c.iso3166_numeric
  /); # don't die!

  $sth->execute();
  my $results = $sth->fetchall_arrayref({});

  my %countryStateInfo;

  foreach my $row (@{$results}) {
    my $numeric = $row->{'country_code'};
    my $stateCode = $row->{'state_code'};
    my $stateName = $row->{'state_name'};

    if (!defined $countryStateInfo{$numeric}) {
      $countryStateInfo{$numeric} = {};
    }

    $countryStateInfo{$numeric}{$stateCode} = {'state_name' => $stateName};
  }

  return \%countryStateInfo;
}

# typo in this name, correcting and calling from typo'd name
# Get rid of this too...
sub loadcountriesAndStates {
  my $self = shift;
  print STDERR 'WARNING: Call to method loadcountriesAndStates() instead of loadCountriesAndStates() at ' . join(',',caller()) . "\n";
  return $self->loadCountriesAndStates();
}

# As well as this.   Add something to the state module...like...getStatesForCountry()?
sub loadCountriesAndStates {
  my $self = shift;
  my %countryInfo = %{$self->loadCountries()};
  my $countryStateInfo = $self->loadCountryStateInfo();

  foreach my $countryID (keys %{$countryStateInfo}) {
    $countryInfo{$countryID}{'states'} = $countryStateInfo->{$countryID};
  }

  return \%countryInfo;
}



1;
