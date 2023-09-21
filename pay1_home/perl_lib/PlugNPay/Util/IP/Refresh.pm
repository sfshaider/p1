package PlugNPay::Util::IP::Refresh;

use strict;
use PlugNPay::DBConnection;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  $self->loadAddresses();
  $self->loadAccessAddresses();

  return $self;
}

sub getAddressesForPort {
  my $self = shift;
  my $port = shift;
  
  if (!defined $self->{'addresses'} || ref($self->{'addresses'}) ne 'HASH') { 
    $self->loadAddresses();
  }

  return $self->{'addresses'}{$port};
}

sub loadAddresses {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');

  my $sth = $dbs->prepare(q/SELECT address,port
                            FROM merchant_refresh_host
                           /);
  $sth->execute() or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});

  my $addressHash = {};
  foreach my $row (@{$rows}) {
    if (!defined $addressHash->{$row->{'port'}}) {
      my @array = ($row->{'address'});
      $addressHash->{$row->{'port'}} = \@array; 
    } else {
      push @{$addressHash->{$row->{'port'}}},$row->{'address'};
    }
  }

  $self->{'addresses'} = $addressHash;

  return $addressHash;
}

sub saveAddresses {
  my $self = shift;
  my $addresses = shift; #Array of Hashes

  if (ref($addresses) ne 'ARRAY') {
    die 'invalid input';
  }
  
  my $insert = 'INSERT INTO merchant_refresh_host
                (username,address,port)
                VALUES ';
  my @params = ();
  my @values = ();
  foreach my $address (@{$addresses}) {
    push @values, $address->{'username'};
    push @values,$address->{'ip_address'};
    push @values,$address->{'port'};
  
    push @params,'(?,?,?)';
  }
 
  if (@params > 0) {
    my $dbs = new PlugNPay::DBConnection()->getHandleFor("pnpmisc");
    my $sth = $dbs->prepare($insert . join(',',@params));
    $sth->execute(@values) or die $DBI::errstr;
    $sth->finish();

    $self->loadAddresses();

    return 1;
  } else {
    return 0;
  }
}

sub checkValidAccessAddress {
  my $self = shift;
  my $originIP = shift || $ENV{'REMOTE_ADDR'};

  my $validAddresses = $self->loadAccessAddresses();

  return $validAddresses->{$originIP};
}


sub loadAccessAddresses {
  my $self = shift;
  if (!defined $self->{'access_addresses'} || ref($self->{'access_addresses'}) ne 'HASH') {
    $self->_loadAccessAddresses();
  }

  return $self->{'access_addresses'};
}

sub _loadAccessAddresses {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');

  my $sth = $dbs->prepare(q/SELECT address,is_valid
                            FROM merchant_refresh_access_address
                           /);
  $sth->execute() or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  
  my $validAddresses = {};

  foreach my $row (@{$rows}){
    $validAddresses->{$row->{'address'}} = $row->{'is_valid'};
  }
  $self->{'access_addresses'} = $validAddresses;

  return $validAddresses;
}

sub saveValidAddresses {
  my $self = shift;
  my $addresses = shift; #Array

  if (ref($addresses) ne 'ARRAY') {
    die 'invalid input';
  }

  my $insert = 'INSERT INTO merchant_refresh_access_address
                (address,is_valid)
                VALUES ';
  my @params = ();
  my @values = ();
  foreach my $address (@{$addresses}) {
    push @values, $address;
    push @values,'1';

    push @params,'(?,?)';
  }

  if (@params > 0) {
    my $dbs = new PlugNPay::DBConnection()->getHandleFor("pnpmisc");
    my $sth = $dbs->prepare($insert . join(',',@params));
    $sth->execute(@values) or die $DBI::errstr;
    $sth->finish();

    $self->_loadAccessAddresses();

    return 1;
  } else {
    return 0;
  }
}

1;
