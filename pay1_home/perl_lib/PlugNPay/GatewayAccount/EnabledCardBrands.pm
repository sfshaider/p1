package PlugNPay::GatewayAccount::EnabledCardBrands;

use strict;

use PlugNPay::GatewayAccount;
use PlugNPay::CreditCard::Brand;
use PlugNPay::Util::UniqueList;
use PlugNPay::Features;
use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->{'enabled'} = new PlugNPay::Util::UniqueList();
  $self->{'disabled'} = new PlugNPay::Util::UniqueList();

  my $enabledArrayRef = shift;


  if (ref($enabledArrayRef) eq 'ARRAY') {
    $self->setBrandsFromArrayRef($enabledArrayRef);
  }

  return $self;
}

sub setGatewayAccountName {
  my $self = shift;
  my $name = shift;
  $name = &PlugNPay::GatewayAccount::filterGatewayAccountName($name);
  $self->{'gatewayAccount'} = $name;
}

sub getGatewayAccountName {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub initialize {
  my $self = shift;

  $self->{'enabled'}->initialize();
  $self->{'disabled'}->initialize();
}


sub addBrand {
  my $self = shift;
  my $brand = shift;

  my $cardBrands = new PlugNPay::CreditCard::Brand();
  $brand = $cardBrands->getBrandID($brand);

  $self->{'enabled'}->addItem($brand);
}

sub setBrandsFromArrayRef {
  my $self = shift;
  my $arrayRef = shift;

  $self->{'enabled'}->fromArrayRef($arrayRef);
}

sub deleteBrand {
  my $self = shift;
  my $brand = shift;

  my $cardBrands = new PlugNPay::CreditCard::Brand();
  $brand = $cardBrands->getBrandID($brand);

  $self->{'enabled'}->deleteItem($brand);
}

sub brandIsEnabled {
  my $self = shift;
  my $brand = shift;

  my $cardBrands = new PlugNPay::CreditCard::Brand();
  $brand = $cardBrands->getBrandID($brand);

  return $self->{'enabled'}->containsItem($brand);
}


# By default, all brands are enabled for every merchant.
# Merchants only get added to table customer_card_brand_enabled when they want a card brand disabled.
# if a brand is in this table customer_card_brand_enabled and is a 1 then it is disabled.
# In summary:
# returns true(1) if row exists and enable column is 0
# returns false(0) otherwise

sub brandIsDisabled {
  my $self = shift;
  my $brandName = shift;

  my $cardBrands = new PlugNPay::CreditCard::Brand();
  my $brandID = $cardBrands->getBrandID($brandName);

  return $self->{'disabled'}->containsItem($brandID);
}


sub getEnabledBrandsFourCharacter {
  my $self = shift;
  my @brands = $self->{'enabled'}->getArray();
  my @fourCharacter;

  my $cardBrandData = new PlugNPay::CreditCard::Brand();

  foreach my $brand (@brands) {
    push @fourCharacter,$cardBrandData->getFourCharacter($brand);
  }

  return \@fourCharacter;
}

sub save {
  my $self = shift;
  $self->_saveInDB();
}

sub load {
  my $self = shift;

  $self->_loadFromDB();

  if ($self->{'enabled'}->size() == 0) {
    $self->_loadFromFeatures();
    if ($self->{'enabled'}->size() == 0) {
      $self->_loadFromDefaults();
    }
    $self->save();
  }
}

sub _saveInDB {
  my $self = shift;

  my $pairString = join(',',map { '(?,?,?)' } $self->{'enabled'}->getArray());

  $self->_deleteFromDB();

  my $dbs = PlugNPay::DBConnection::connections();

  my $sth = $dbs->getHandleFor('pnpmisc')->prepare(q/
     INSERT INTO customer_card_brand_enabled
     (`username`, `card_brand_id`, `enabled`)
     VALUES / . $pairString
  );

  my @values;

  foreach my $brand ($self->{'enabled'}->getArray()) {
    push @values,($self->getGatewayAccountName(),$brand,'1');
  }

  $sth->execute(@values);
}

sub _deleteFromDB {
  my $self = shift;
  my $dbs = PlugNPay::DBConnection::connections();

  my $sth = $dbs->getHandleFor('pnpmisc')->prepare(q/
    DELETE FROM customer_card_brand_enabled
     WHERE username = ?
  /);

  $sth->execute($self->getGatewayAccountName());
}

sub _loadFromDB {
  my $self = shift;

  $self->initialize();

  my $dbs = PlugNPay::DBConnection::connections();
  my $sth = $dbs->getHandleFor('pnpmisc')->prepare(q/
    SELECT card_brand_id, enabled
      FROM customer_card_brand_enabled
     WHERE username = ?
  /);

  $sth->execute($self->getGatewayAccountName());

  my $results = $sth->fetchall_arrayref({});

  my @enabledBrands;
  my @disabledBrands;
  foreach my $cardBrand (@{$results}) {
    if ($cardBrand->{'enabled'}) {
      push @enabledBrands,$cardBrand->{'card_brand_id'};
    } else {
      push @disabledBrands,$cardBrand->{'card_brand_id'};
    }
  }

  foreach my $brand (@enabledBrands) {
    $self->addBrand($brand);
  }

  foreach my $disabledBrand (@disabledBrands) {
    $self->addDisabledBrand($disabledBrand);
  }
}

sub _loadFromFeatures {
  my $self = shift;

  $self->initialize();

  my $features = new PlugNPay::Features($self->getGatewayAccountName(),'general');
  my @enabledRaw = @{$features->getFeatureValues('card-allowed')};

  foreach my $raw (@enabledRaw) {
    $self->addBrand($raw);
  }
}

# This is for when the feature finally goes away, to be called at the end of "_loadFromFeatures"
sub _expireFeature {
  my $self = shift;
  my $features = new PlugNPay::Features($self->getGatewayAccountName(),'general');
  if ($features->get('card-allowed') ne '') {
    $features->set('card-allowed-defunct',$features->get('card-allowed'));
    $features->removeFeature('card-allowed');
    $features->saveContext();
  }
}

sub _loadFromDefaults {
  my $self = shift;
  my $cardBrands = new PlugNPay::CreditCard::Brand();
  foreach my $brandID (@{$cardBrands->getDefaultBrands()}) {
    $self->{'enabled'}->addItem($brandID);
  }
}

sub addDisabledBrand {
  my $self = shift;
  my $brand = shift;

  my $cardBrands = new PlugNPay::CreditCard::Brand();
  $brand = $cardBrands->getBrandID($brand);

  $self->{'disabled'}->addItem($brand);
}

sub getDisabledBrandsByName {
  my $self = shift;
  my @brands = $self->{'disabled'}->getArray();
  my @name;

  my $cardBrandData = new PlugNPay::CreditCard::Brand();

  foreach my $brand (@brands) {
    push @name,$cardBrandData->getName($brand);
  }

  return \@name;
}


1;
