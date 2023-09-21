package PlugNPay::API::Key::Name;

use strict;
use PlugNPay::Util::Encryption::Random;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::Util::StackTrace;
use MIME::Base64;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub getID {
  my $self = shift;
  if (!defined $self->{'id'}) {
    die('API Key ID not loaded.' . "\n" . new PlugNPay::Util::StackTrace()->string() . "\n");
  }
  return $self->{'id'};
}

sub setID {
  my $self = shift;
  $self->{'id'} = shift;
}

sub setCustomerID {
  my $self = shift;
  my $customerID = shift;
  $customerID =~ s/[^\d]//g;
  $self->{'customerID'} = $customerID;
}

sub getCustomerID {
  my $self = shift;
  return $self->{'customerID'};
}

sub setName {
  my $self = shift;
  my $keyName = shift;
  $self->{'name'} = $keyName;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub exists {
  my $self = shift;

  my $id = $self->{'id'};
  my $keyName = $self->{'name'};
  my $customerID = $self->{'customerID'};

  my $result;

  eval {
    my $dbs = new PlugNPay::DBConnection();

    my $query = q/
      SELECT count(id) as `exists`
        FROM api_key_name
       WHERE id = ? OR (customer_id = ? AND name = ?)
    /;

    my $response = $dbs->fetchallOrDie('pnpmisc',$query,[$id,$customerID,$keyName], {});

    $result = $response->{'result'};
  };

  if ($@) {
    die('Failed to check if key name exists.');
  }

  if ($result && $result->[0] && $result->[0]{'exists'}) {
    $self->load(); # probably gonna need it anyway
  }
}

sub load {
  my $self = shift;

  my $id = $self->{'id'};
  my $keyName = $self->{'name'};
  my $customerID = $self->{'customerID'};

  if (defined $id && defined $keyName && defined $customerID) {
    # it's already loaded...
    return;
  }

  my $result;

  eval {
    my $dbs = new PlugNPay::DBConnection();

    my $query = q/
      SELECT id, customer_id, name
        FROM api_key_name
       WHERE id = ? OR (customer_id = ? AND name = ?)
    /;

    my $response = $dbs->fetchallOrDie('pnpmisc',
                                       $query,
                                       [$id,$customerID,$keyName],
                                       {}); 

    $result = $response->{'result'};
  };


  if ($@) {
    die('Failed to load key name.');
  }


  if ($result && $result->[0]) {
    my $row = $result->[0];
    $self->setID($row->{'id'});
    $self->setCustomerID($row->{'customer_id'});
    $self->setName($row->{'name'});
  } else {
    die('Key name [' . $keyName . '] does not exist.' . "\n" . new PlugNPay::Util::StackTrace()->string() . "\n");
  }
}

sub save {
  my $self = shift;
  
  my $keyName = $self->getName();
  my $customerID = $self->getCustomerID();

  my $query = q/
    INSERT IGNORE INTO api_key_name
      (customer_id,name)
    VALUES
      (?,?)
  /;

  eval {
    my $dbs = new PlugNPay::DBConnection();

    $dbs->executeOrDie('pnpmisc',
                       $query,
                       [$customerID,$keyName]);

    $self->load();
  };

  if ($@) {
    die('Failed to save key name.' . "\n" . new PlugNPay::Util::StackTrace()->string() . "\n");
  }
}

sub delete {
  my $self = shift;

  my $id = $self->{'id'};
  my $customerID = $self->{'customerID'};
  my $keyName = $self->{'name'};

  my $query;
  my @values;

  if (defined $id) {
    $query = q/ DELETE FROM api_key_name WHERE id = ? /;
    push @values, $id;
  } elsif (defined $customerID && defined $keyName) {
    $query = q/ DELETE FROM api_key_name WHERE customer_id = ? and key_name = ? /;
    push @values, ($customerID,$keyName);
  }

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('pnpmisc', $query, \@values);
  };

  if ($@) {
    die('Failed to delete key.' . "\n" . new PlugNPay::Util::StackTrace()->string() . "\n");
  }
}


1;
