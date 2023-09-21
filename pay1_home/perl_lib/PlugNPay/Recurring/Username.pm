package PlugNPay::Recurring::Username;

use strict;

use PlugNPay::Util::UniqueID;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub getUsername {
  my $self = shift;

  return $self->{'username'};
}

sub setUsername {
  my $self = shift;
  my $customer = shift;

  $self->{'username'} = $customer;
}

sub setMerchant {
  my $self = shift;
  my $merchant = shift;

  $self->{'merchant'} = $merchant;
}

sub getMerchant {
  my $self = shift;

  return $self->{'merchant'};
}

sub generateCustomerUsername {
  my $username = new PlugNPay::Util::UniqueID->generate();

  return $username;
}

sub exists {
  my $self = shift;
  my $info = shift || $self;
  my $merchant = lc $info->{'merchant'};
  my $username = lc $info->{'username'};

  my $exists;
  eval {
    my $table = 'customer';
    my $db = $merchant;

    if ($merchant eq 'pnpbilling') {
      $table = 'customers';
      $db = 'pnpmisc';
    }

    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare($db, qq/
        SELECT COUNT(username) as `exists`
        FROM $table
        WHERE LOWER(username) = LOWER(?)
    /);
    
    $sth->execute($username) or die $DBI::errstr;
    my $row = $sth->fetchall_arrayref({});
    $exists = $row->[0]{'exists'};
  };
  if($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'recurring'});
    $logger->log({'status' => 'FAILURE', 'message' => 'Failed to query customer username from merchant database.'});
  }
  return $exists;
}
1;
