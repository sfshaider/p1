package PlugNPay::CreditCard::Brand;

use strict;
use PlugNPay::Logging::DataLog;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

our $_brandToID;
our $_idToFourCharacter;
our $_idToLegacyCharacter;
our $_idToName;
our $_binToBrandID;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_brandToID) {
    $_brandToID = new PlugNPay::Util::Cache::LRUCache(30);
    $self->{'brandToIDMap'} = $_brandToID;
  }

  if (!defined $_idToFourCharacter) {
    $_idToFourCharacter = new PlugNPay::Util::Cache::LRUCache(6);
    $self->{'idToFourCharacterMap'} = $_idToFourCharacter;
  }

  if (!defined $_idToLegacyCharacter) {
    $_idToLegacyCharacter = new PlugNPay::Util::Cache::LRUCache(6);
    $self->{'idToLegacyCharacterMap'} = $_idToLegacyCharacter;
  }

  if (!defined $_idToName) {
    $_idToName = new PlugNPay::Util::Cache::LRUCache(6);
    $self->{'idToNameMap'} = $_idToName;
  }

  if (!defined $_binToBrandID) {
    $_binToBrandID = new PlugNPay::Util::Cache::LRUCache(8);
    $self->{'binToBrandIDMap'} = $_binToBrandID;
  }

  return $self;
}

sub filterBrandName {
  my $self = shift;
  my $brand = shift;

  $brand = lc $brand;
  $brand =~ s/[^a-z ]//g;
  return $brand;
}

sub getBrandID {
  my $self = shift;
  my $raw = shift;

  if ($_brandToID->contains($raw) && defined $_brandToID->get($raw)) {
    my $id = $_brandToID->get($raw);
    if (defined $id) {
      return $id;
    }
  }

  my $rawFiltered = lc $raw;
  $rawFiltered =~ s/\s//g;

  my $rawUC = uc $raw;

  my $sth = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc')->prepare(q/
    SELECT id
      FROM card_brand
     WHERE name = ?
        OR REPLACE(name,' ','') = ?
        OR name = REPLACE(?,' ','')
        OR alt_name = ?
        OR REPLACE(alt_name,' ','') = ?
        OR alt_name = REPLACE(?,' ','')
        OR two_character = ?
        OR four_character = ?
        OR id = ?
  /);

  $sth->execute($raw,$raw,$raw,$raw,$raw,$raw,$rawUC,$rawUC,$raw);

  my $results = $sth->fetchall_arrayref({});

  my $brandID = $results->[0]{'id'};
 
  if (defined $brandID) {
    $_brandToID->set($raw,$brandID);
  }

  return $brandID;
}

sub getName {
  my $self = shift;
  my $id = shift;
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'credit_card'});
  my $logData = {'originalID' => $id};
  if ($id !~ /^\d+$/) {
    my $originalID = $id;
    $id = $self->getBrandID($id);
    $logData->{'alteredID'} = $id;

    if (!defined $id) {
      my @splitData = split(' ',$originalID);
      $id = $self->getBrandID($splitData[0]);
    }
  }

  if ($_idToName->contains($id) && defined $_idToName->get($id)) {
    my $name = $_idToName->get($id);
    $logData->{'cachedName'} = $name;
    $logger->log({'data' => $logData, 'module' => 'PlugNPay/CreditCard/Brand'});
    return $name;
  }

  my $sth = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc')->prepare(q/
    SELECT name
      FROM card_brand
     WHERE id = ?
  /);

  $sth->execute($id);

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    my $name = $results->[0]{'name'};
    if ($name) {
      $_idToName->set($id,$name);
    }
    $logData->{'loadedName'} = $name;
    $logger->log({'data' => $logData, 'module' => 'PlugNPay/CreditCard/Brand'});
    return $name;
  }
}


sub getFourCharacter {
  my $self = shift;
  my $id = shift;

  if ($id !~ /^\d+$/) {
    $id = $self->getBrandID($id);
  }

  if ($_idToFourCharacter->contains($id)) {
    return $_idToFourCharacter->get($id);
  }

  my $sth = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc')->prepare(q/
    SELECT four_character
      FROM card_brand
     WHERE id = ?
  /);

  $sth->execute($id);

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    my $fourCharacter = $results->[0]{'four_character'};
    $_idToFourCharacter->set($id,$fourCharacter);
    return $fourCharacter;
  }
}

sub getLegacyCharacter {
  my $self = shift;
  my $id = shift;

  if ($id !~ /^\d+$/) {
    $id = $self->getBrandID($id);
  }

  if ($_idToLegacyCharacter->contains($id)) {
    return $_idToLegacyCharacter->get($id);
  }

  my $sth = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc')->prepare(q/
    SELECT legacy_character
      FROM card_brand
     WHERE id = ?
  /);

  $sth->execute($id);

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    my $legacyCharacter = $results->[0]{'legacy_character'};
    $_idToLegacyCharacter->set($id,$legacyCharacter);
    return $legacyCharacter;
  }
}

sub getFourCharacterForBIN {
  my $self = shift;
  my $bin = shift;
  
  return $self->getFourCharacter($self->getBrandIDForBIN($bin));
}

sub getBrandIDForBIN {
  my $self = shift;
  my $bin = shift;

  $bin = substr($bin,0,6);

  if ($_binToBrandID->contains($bin)) {
    return $_binToBrandID->get($bin);
  }

  my $sth = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc')->prepare(q/
    SELECT brand_id, length(prefix) as `length`, prefix
      FROM card_brand_prefix
     WHERE substr(?,1,1) = substr(prefix,1,1)
      ORDER BY length(prefix) DESC
  /);

  $sth->execute($bin);

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    foreach my $prefixData (@{$results}) {
      my $length = $prefixData->{'length'};
      my $prefix = $prefixData->{'prefix'};
      my $brandID = $prefixData->{'brand_id'};

      my $binToCompare = substr($bin,0,$length);

      if ($binToCompare eq $prefix) {
        $_binToBrandID->set($bin,$brandID);
        return $brandID;
      }
    }
  }

  return undef;
}



sub getDefaultBrands {
  my $self = shift;

  my $sth = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc')->prepare(q/
    SELECT id
      FROM card_brand
     WHERE enabled_by_default = ?
  /);

  $sth->execute(1);

  my $results = $sth->fetchall_arrayref({});

  my @brands;
  if ($results) {
    @brands = map {$_->{'id'}} @{$results};
  }

  return \@brands;
}

sub getLogo {
  my $self = shift;
  my $id = shift;

  my $sth = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc')->prepare(q/
    SELECT small_logo_url
      FROM card_brand
     WHERE id = ?
  /);

  $sth->execute($id);

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    return $results->[0]{'small_logo_url'};
  }
}


1;
