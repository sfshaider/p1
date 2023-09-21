package PlugNPay::Fraud::GeoLocate;

use strict;
use PlugNPay::DBConnection;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  my $ipaddress = shift || '';

  if ($ipaddress ne '') { 
    $self->setIPAddress($ipaddress); 
    $self->_load();
  }

  return $self;
}

sub setIPAddress {
  my $self = shift;
  my $ipaddress = shift;
  if ($ipaddress =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
    my $ipcheck = int(16777216*$1 + 65536*$2 + 256*$3 + $4);
    if (length($ipcheck) > 11) {
      $ipaddress = '';
    }
  } else {
    $ipaddress = '';
  }
  $self->{'ipAddress'} = $ipaddress;
}

sub getIPAddress {
  my $self = shift;
  return $self->{'ipAddress'};
}

sub getCountry {
  my $self = shift;

  return $self->{'ipCountry'} || '';
}

sub _load {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::database('fraudtrack');
  my $sth = $dbh->prepare(q/
    SELECT ipnum_from,ipnum_to,country_code
    FROM ip_country
    WHERE ipnum_to>=?
    ORDER BY ipnum_to ASC
    LIMIT 1
  /);
  $sth->execute($self->{'ipAddress'});

  my @results = $sth->fetchall_arrayref({});
  $self->{'ipCountry'} = $results[0];
}

1;
