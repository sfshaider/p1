package PlugNPay::Fraud::Config;

use strict;
use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $account = shift;
  $self->{'gatewayAccount'} = $account;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub getBlockedCountries {
  my $self = shift;
  my $blockedCountries = $self->_getBlockedCountries();
  my @blocked = keys %{$blockedCountries};
  return \@blocked;
}

sub _getBlockedCountries {
  my $self = shift;
  
  if (!defined $self->{'blockedCountries'}) {
    $self->{'blockedCountries'} = {};
  }

  return $self->{'blockedCountries'};
}

sub addBlockedCountry {
  my $self = shift;
  my $country = shift;

  my $blockedCountries = $self->_getBlockedCountries();
  $blockedCountries->{$country} = 1;
}

sub removeBlockedCountry {
  my $self = shift;
  my $country = shift;

  my $blockedCountries = $self->_getBlockedCountries();
  delete $blockedCountries->{$country};
}



### Load and Save methods ###


sub _loadBlockedCountriesList {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = new $dbs->prepare('fraudtrack',q/
    SELECT entry FROM country_fraud WHERE username = ?
  /);

  $sth->execute($self->getGatewayAccount());

  my $results = $sth->fetchall_arrayref({});

  my %blockedCountries;
  if ($results) {
    %blockedCountries = map { $_->{'entry'} => 1 } @{$results};
  }

  $self->{'blockedCountries'} = \%blockedCountries;
}

sub _saveBlockedCountriesList {
  my $self = shift;

  $self->_clearBlockedCountriesList();

  my $blockedCountries = $self->getBlockedCountries();
  my $placeholders = join(',',map { '(?,?)' } @{$blockedCountries});
  my @values = map { ($self->getGatewayAccount(),$_) } @{$blockedCountries};

  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('fraudtrack',q/
    INSERT INTO country_fraud (username,entry) VALUES / . $placeholders
  );

  $sth->execute(@values);
}

sub _clearBlockedCountriesList {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('fraudtrack',q/
    DELETE FROM country_fraud WHERE username = ?
  /);

  $sth->execute($self->getGatewayAccount());
}
 

  

1;
