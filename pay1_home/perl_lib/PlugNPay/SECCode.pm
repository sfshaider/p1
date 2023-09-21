package PlugNPay::SECCode;

use strict;
use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->_loadSECCodeData();

  return $self;
}

sub isValid {
  my $self = shift;
  my $code = shift;
  return (grep { /^$code$/ } keys %{$self->{'sec_code_data'}} ? 1 : 0);
}

sub isConsumer {
  my $self = shift;
  my $code = shift;

  return grep { /^$code$/ } @{$self->{'sec_code_data'}{'consumer'}};
}

sub isCommercial {
  my $self = shift;
  my $code = shift;

  return grep { /^$code$/ } @{$self->{'sec_code_data'}{'commercial'}};
}

sub _loadSECCodeData {
  my $self = shift;
  
  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT code,entity_type FROM sec_code
  /);

  $sth->execute();

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    foreach my $row (@{$results}) {
      if (!defined $self->{'sec_code_data'}) {
        $self->{'sec_code_data'} = {};
      }
      if (!defined $self->{'sec_code_data'}{$row->{'entity_type'}}) {
        $self->{'sec_code_data'}{$row->{'entity_type'}} = [];
      }
      push @{$self->{'sec_code_data'}{$row->{'entity_type'}}},$row->{'code'}
    }
  }
}

1;
