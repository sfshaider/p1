package PlugNPay::GatewayAccount::EnabledCardTypes;

use strict;

use PlugNPay::GatewayAccount;
use PlugNPay::CreditCard::Type;
use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->initialize();
  my $enabledHashRef = shift;


  if (ref($enabledHashRef) eq 'HASH') {
    $self->setTypesFromHashRef($enabledHashRef);
  }

  return $self;
}

sub initialize{
  my $self = shift;
  $self->{'enabled'} = {};  
  $self->{'cardtypes'} = {};
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


sub addSubTypeByID {
  my $self = shift;
  my $cardTypes = new PlugNPay::CreditCard::Type();
  my $id =shift;
  
  my @results = $cardTypes->getTypeArray($id);
  
  $self->{'cardtypes'}{$results[0]}{$results[1]}=$id;
  $self->{'enabled'}{$id}=1;
}

sub addSubType {
  my $self = shift;
  my $type = shift;
  my $subtype = shift;

  my $cardTypes = new PlugNPay::CreditCard::Type();
  my $id = $cardTypes->getSubTypeID($type, $subtype);

  $self->{'cardtypes'}{$type}{$subtype}=$id;
  $self->{'enabled'}{$id}=1;
}

sub setTypesFromHashRef {
  my $self = shift;
  my $hashRef = shift;
  
  $self->{'cardtypes'} = $hashRef;
}

sub deleteSubType {
  my $self = shift;
  my $types = shift;
  my $subtype = shift;
   
  my $id = PlugNPay::CreditCard::Type::new()->getSubType($types,$subtype);
  delete $self->{'cardtypes'}{$types}{$subtype};
  delete $self->{'enabled'}{$id};
}

sub deleteSubTypeByID {
  my $self = shift;
  my $id = shift;
 
  my $cardTypes = new PlugNPay::CreditCard::Type();
  my @results = $cardTypes->getTypeArray($id);

  delete $self->{'cardtypes'}{$results[0]}{$results[1]};
  delete $self->{'enabled'}{$id};
}

sub hashToArray{
 my $self = shift;
  my @cardtypes;
  foreach my $type (keys %{$self->{'cardtypes'}}){
    foreach my $subtype (keys %{$self->{'cardtypes'}{$type}}){
      push @cardtypes, $self->{'cardtypes'}{$type}{$subtype};
    }
  }
  return @cardtypes;
}

sub save {
  my $self = shift;
  $self->_saveInDB();
}

sub load {
  my $self = shift;
  $self->_loadFromDB();
}

sub enableSubType {
  my $self = shift;
  my $id = shift;
  my $extra = $_;
  
  if ($id  =~ /^-?\d+\.?\d*$/) {
    $self->{'enabled'}{$id}=1;
  }
  else { 
    $id =$self->getSubType($id,$extra);
    $self->{'enabled'}{$id}=1;
  }
}

sub disableSubType {
  my $self = shift;
  my $id = shift;
  my $extra = $_;
 
  if ($id  =~ /^-?\d+\.?\d*$/) {
    $self->{'enabled'}{$id}=0;
  }
  else {
    $id =$self->getSubType($id,$extra);
    $self->{'enabled'}{$id}=0;
  }
}


sub _saveInDB {
  my $self = shift;
  my @cardtypes = $self->hashToArray();
  my $pairString = join(',',map { '(?,?,?)' } @cardtypes);

  my $dbs = PlugNPay::DBConnection::connections();

  my $sth = $dbs->getHandleFor('pnpmisc')->prepare(q/
    INSERT INTO customer_card_type_enabled
     (username,card_type_id,enabled)
    VALUES
     (?,?,?)
    ON DUPLICATE KEY UPDATE enabled=? 
  /);

  foreach my $id (@cardtypes){
   my $enabled = $self->{'enabled'}{$id};
   $sth->execute($self->getGatewayAccountName(), $id, $enabled, $enabled);
  }
}

sub _deleteFromDB {
  my $self = shift;
  my $dbs = PlugNPay::DBConnection::connections();

  my $sth = $dbs->getHandleFor('pnpmisc')->prepare(q/
    DELETE FROM customer_card_type_enabled
     WHERE username = ?
  /);

  $sth->execute($self->getGatewayAccountName());
}

sub _loadFromDB {
  my $self = shift;

  $self->initialize();

  my $dbs = PlugNPay::DBConnection::connections();
  my $sth = $dbs->getHandleFor('pnpmisc')->prepare(q/
    SELECT id
      FROM card_type
  /);

  $sth->execute(); 

  my $results = $sth->fetchall_arrayref({});

  my @cardtypes = map { $_->{'id'} } @{$results};

  foreach my $types (@cardtypes) {
    $self->addSubTypeByID($types);
  }
  
  $self->_loadEnabled();
  
}

sub _loadEnabled {
  my $self=shift;

  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
    SELECT card_type_id,enabled
    FROM customer_card_type_enabled
   WHERE username = ?
  /);
  $sth->execute($self->getGatewayAccountName());
  my $results = $sth->fetchall_arrayref({}); 
  foreach my $val (@{$results}){ 
    $self->{'enabled'}{$val->{'card_type_id'}} = $val->{'enabled'};
  }  
  $sth->finish();
}


sub getEnabledCardTypes {
  my $self = shift;
  my @enabled;
  my $typeCount = 0;
  my $typeTable = new PlugNPay::CreditCard::Type();
  my @cardtypes =  $typeTable ->getAllCardTypes();
  foreach my $type (keys %{$self->{'cardtypes'}})  {
    foreach my $subtype (keys %{$self->{'cardtypes'}{$type}}) {
      $typeCount += 1;
 
      my $id = $self->{'cardtypes'}{$type}{$subtype};
      if ($self->{'enabled'}{$id}) {
        push @enabled, $subtype;
      }
    }
  }
  unless($typeCount){
    return \@cardtypes
  }
  
  return \@enabled;
}

sub getDisabledCardTypes {
  my $self = shift;
  my @disabled;
  my $typeCount = 0;
  my $typeTable = new PlugNPay::CreditCard::Type();
  my @cardtypes =  $typeTable ->getAllCardTypes();
  foreach my $type (keys %{$self->{'cardtypes'}})  {
    foreach my $subtype (keys %{$self->{'cardtypes'}{$type}}) {
      $typeCount += 1;

      my $id = $self->{'cardtypes'}{$type}{$subtype};
      if (!$self->{'enabled'}{$id}) {
        push @disabled, $subtype;
      }
    }
  }
  unless($typeCount){
    return \@cardtypes
  }

  return \@disabled;
}

1;
