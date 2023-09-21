package PlugNPay::GatewayAccount::EnabledCardCombos;

use strict;

use PlugNPay::GatewayAccount;
use PlugNPay::CreditCard::Brand;
use PlugNPay::CreditCard::Type;
use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $gatewayAccount = shift;

  if ($gatewayAccount) {
    $self->setGatewayAccountName($gatewayAccount);
    $self->load();
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

sub enableComboByIDs {
  my $self = shift;
  my $brandID = shift;
  my $typeID = shift;

  $self->{'cardBrand'} = $brandID;
  $self->{'cardType'} = $typeID;
  $self->{'enabled'} = 1;

  $self->save();
}

sub disableComboByIDs {
  my $self = shift;
  my $brandID = shift;
  my $typeID = shift;

  $self->{'cardBrand'} = $brandID;
  $self->{'cardType'} = $typeID;
  $self->{'enabled'} = 0;

  $self->save();
}


sub save {
  my $self = shift;
  $self->_saveInDB();
}

sub load {
  my $self = shift;
  $self->_loadFromDB();
}

sub _saveInDB {
  my $self = shift;

  my $brandID = $self->{'cardBrand'};
  my $typeID = $self->{'cardType'};
  my $enabled = $self->{'enabled'};

  my $dbs = PlugNPay::DBConnection::connections();

  my $sth = $dbs->getHandleFor('pnpmisc')->prepare(q/
    INSERT INTO customer_card_combo_enabled
     (username,card_brand_id,card_type_id,enabled)
    VALUES
     (?,?,?,?)
    ON DUPLICATE KEY UPDATE enabled=?
  /);

  $sth->execute($self->getGatewayAccountName(), $brandID, $typeID, $enabled, $enabled);
}


sub _deleteFromDB {
  my $self = shift;
  my $dbs = PlugNPay::DBConnection::connections();

  my $sth = $dbs->getHandleFor('pnpmisc')->prepare(q/
    DELETE FROM customer_card_combo_enabled 
    WHERE username = ?
  /);

  $sth->execute($self->getGatewayAccountName());
}

sub _loadFromDB {
  my $self=shift;

  my $brandTable = new PlugNPay::CreditCard::Brand();
  my $typeTable = new PlugNPay::CreditCard::Type();

  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
    SELECT card_brand_id,card_type_id,enabled
    FROM customer_card_combo_enabled 
    WHERE username = ?
  /);
  $sth->execute($self->getGatewayAccountName());

  my $results = $sth->fetchall_arrayref({}); 
  foreach my $val (@{$results}){ 
    my $brand = $val->{'card_brand_id'};
    $brand = $brandTable->getName($brand);    

    my $type = $val->{'card_type_id'};
    $type = $typeTable->getSubType($type);

    my $combo = join('_',$brand,$type);
    $self->{'combos'}{$combo} = $val->{'enabled'};
  }  
  $sth->finish();
}

sub getEnabledCardCombos {
  my $self = shift;
  my @enabled;

  my $allCombos = $self->{'combos'};
  foreach my $combo (keys %{$allCombos})  {
    my $enabled = ${$allCombos}{$combo};
    if ($enabled) {
      push @enabled, $combo;
    }
  }
  return \@enabled;
}

sub getDisabledCardCombos {
  my $self = shift;
  my @disabled;

  my $allCombos = $self->{'combos'};
  foreach my $combo (keys %{$allCombos})  {
    my $enabled = ${$allCombos}{$combo};
    if (!$enabled) {
      push @disabled, $combo;
    }
  }
  return \@disabled;
}

1;
