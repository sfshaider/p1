package PlugNPay::Fraud::Country;

use strict;
use PlugNPay::Country;
use PlugNPay::DBConnection;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub isBlocked {
  my $self = shift;
  my $username;
  if (ref($self) eq 'PlugNPay::Fraud::Country') {
    $username = shift;
  } else {
    $username = $self;
  }

  my $country = shift;
  if (length($country) != 2) {
    my $countryObject = new PlugNPay::Country($country);
    $country = uc($countryObject->getTwoLetter());
  }

  my $dbs = new PlugNPay::DBConnection();
  my $select = q/
    SELECT COUNT(*) AS `count`
      FROM country_fraud
     WHERE username = ? AND entry = ?
  /;

  my $rows = [];
  eval { 
    $rows = $dbs->fetchallOrDie('fraudtrack', $select, [$username, $country], {})->{'result'};
  };

  return $rows->[0]{'count'};
}

1;
