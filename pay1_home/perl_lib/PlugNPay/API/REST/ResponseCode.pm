package PlugNPay::API::REST::ResponseCode;

use strict;

use PlugNPay::DBConnection;

our $_codes;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  if (!defined $_codes) {
    $self->_loadCodes();
  }
  return $self;
}

sub setCode {
  my $self = shift;
  my $code = shift;
  $self->{'code'} = $code;
}

sub getCode {
  my $self = shift;
  return $self->{'code'};
}

sub getMessage {
  my $self = shift;
  return $_codes->{$self->getCode()};
}

sub _loadCodes {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT code, message
      FROM api_response_code
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  my %codes;
  if ($result) {
    foreach my $row (@{$result}) {
      $codes{$row->{'code'}} = $row->{'message'};
    }
  }
  $_codes = \%codes;
}
1;
