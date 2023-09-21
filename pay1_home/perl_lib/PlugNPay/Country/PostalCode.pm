package PlugNPay::Country::PostalCode;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->{'postal_codes'} = new PlugNPay::Util::LRUCache(10);

  return $self;
}

sub setPostalCode {
  my $self = shift;
  my $postalCode = shift;
  $self->{'postalCode'} = $postalCode;
}

sub getPostalCode {
  my $self = shift;
  return $self->{'postalCode'};
}

sub getState {
  my $self = shift;
  $self->_loadIfNotLoaded();
  return $self->{'postal_codes'}->get($self->getPostalCode())->{'state'};
}

sub getCountryCode {
  my $self = shift;
  $self->_loadIfNotLoaded();
  return $self->{'postal_codes'}->get($self->getPostalCode())->{'country_code'};
}

sub getCountyTaxRate {
  my $self = shift;
  $self->_loadIfNotLoaded();
  return $self->{'postal_codes'}->get($self->getPostalCode())->{'county_tax_rate'};
}

sub getCityTaxRate {
  my $self = shift;
  $self->_loadIfNotLoaded();
  return $self->{'postal_codes'}->get($self->getPostalCode())->{'city_tax_rate'};
}

sub getSpecialTaxRate {
  my $self = shift;
  $self->_loadIfNotLoaded();
  return $self->{'postal_codes'}->get($self->getPostalCode())->{'special_tax_rate'};
}

sub getStateTaxRate {
  my $self = shift;
  my $state = new PlugNPay::Country::State($self->getState());
  return $state->getTaxRate();
}

sub getTaxRate {
  my $self = shift;
  
  my $taxRate = 0;
  $taxRate += $self->getStateTaxRate();
  $taxRate += $self->getCountyTaxRate();
  $taxRate += $self->getCityTaxRate();
  $taxRate += $self->getSpecialTaxRate();
}

sub _loadIfNotLoaded {
  my $self = shift;
  if (!$self->{'postal_codes'}->contains($self->getPostalCode())) {
    $self->_load();
  }
}

sub _load {
  my $self = shift;


  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT postal_code,country_id,state,region_code,county_rate,city_rate,special_rate
      FROM postal_code
     WHERE postal_code = ?
  /);

  $sth->execute($self->getPostalCode());

  my $results = $sth->fetchall_arrayref({});
  if ($results && $results->[0]) {
    $self->{'postal_codes'}->set($self->getPostalCode(),$results->[0]);
  }
}

sub transactionIsTaxable {
  my $self = shift;
  my $username = shift;
  my $shippingPostalCode = shift;

  my $nexus = new PlugNPay::GatewayAccount::Nexus($username);
}

sub getTaxRateForPostalCode {
  my $self = shift;
  my $postalCode = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT  FROM us_taxrate WHERE postal_code = ?
  /);

  $sth->execute($postalCode);

  my $results = $sth->fetchall_arrayref({});

  if ($results && $results->[0]) {
    return $results->[0]{'combined_rate'};
  }
}


1;
