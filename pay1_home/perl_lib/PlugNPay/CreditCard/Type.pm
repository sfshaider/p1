package PlugNPay::CreditCard::Type;

use strict;

use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

our $_TypeToID;
our $_idToName;
our $_binToTypeID;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_TypeToID) {
    $_TypeToID = new PlugNPay::Util::Cache::LRUCache(30);
    $self->{'typeToIDMap'} = $_TypeToID;
  }


  if (!defined $_idToName) {
    $_idToName = new PlugNPay::Util::Cache::LRUCache(6);
    $self->{'idToNameMap'} = $_idToName;
  }

  if (!defined $_binToTypeID) {
    $_binToTypeID = new PlugNPay::Util::Cache::LRUCache(8);
    $self->{'binToTypeIDMap'} = $_binToTypeID;
  }

  return $self;
}

sub filterName {
  my $self = shift;
  my $type = shift;

  $type = lc $type;
  $type =~ s/[^a-z]//g;
  return $type;
}


sub getSubTypeID {
  my $self = shift;
  my $type=shift;
  my $subtype=shift;

  my $sth = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc')->prepare(q/
    SELECT id
      FROM card_type
     WHERE (type=? AND subtype=?) 
  /);

  $sth->execute($type,$subtype);

  my $results = $sth->fetchall_arrayref({});
  my $typeID = $results->[0]{'id'};
  $_TypeToID->set($type,$subtype,$typeID);

  return $typeID;
}

sub getTypeArray  {
  my $self = shift;
  my $id = shift;

  my $sth = new PlugNPay::DBConnection()->getHandleFor('pnpmisc')->prepare(q/
                         SELECT type,subtype
                         FROM card_type
                         WHERE id=?
            /);
  $sth->execute($id);
  
  my $results = $sth->fetchall_arrayref({});
  my @types  =($results->[0]{'type'}, $results->[0]{'subtype'});
  $_TypeToID-> set($types[0],$types[1],$id); 
  $sth->finish(); 
  return @types; 
}

sub getSubType {
  my $self = shift;
  my $id = shift;
  my $extra = $_;

  if ($id !~ /^\d$/) {
    if (defined $extra){ 
      $id = $self->getSubTypeID($id,$extra);
    }
    else{
      return 0;
    }
  }

  if ($_idToName->contains($id)) {
    return $_idToName->get($id);
  }

  my $sth = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc')->prepare(q/
    SELECT subtype 
      FROM card_type
     WHERE id = ?
  /);

  $sth->execute($id);

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    my $subtype = $results->[0]{'subtype'};
    $_idToName->set($id,$subtype);
    return $subtype;
  }
}

sub getType {
  my $self = shift;
  my $id = shift;

  if ($id !~ /^\d$/) {
    $id = $self->getTypeID($id,$_);
  }

  if ($_idToName->contains($id)) {
    return $_idToName->get($id);
  }

  my $sth = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc')->prepare(q/
    SELECT type
      FROM card_type
     WHERE id = ?
  /);

  $sth->execute($id);

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    my $type = $results->[0]{'type'} ;
    return $type;
  }
}


sub getAllCardTypes {
  my $self = shift;
  
  my $sth = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc')->prepare(q/
            SELECT subtype
            FROM card_type 
            /);
  $sth->execute();
  my @listOfTypes;
  my $results = $sth->fetchall_arrayref({});
  for (my $i = 0; $i<scalar @{$results};$i++){
    push @listOfTypes, $results->[$i]{'subtype'};
  }

  $sth->finish();
  return @listOfTypes; 
}

1;
