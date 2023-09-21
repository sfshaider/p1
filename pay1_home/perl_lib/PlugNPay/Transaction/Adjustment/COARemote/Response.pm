package PlugNPay::Transaction::Adjustment::COARemote::Response;

use strict;

use PlugNPay::DBConnection;

our $_subtypeMap;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_subtypeMap) {
    $self->_loadSubtypeMap();
  }

  return $self;
}

sub setError {
  my $self = shift;
  my $error = shift;
  $self->{'error'} = $error;
}

sub getError {
  my $self = shift;
  return $self->{'error'};
}

sub setErrorMessage {
  my $self = shift;
  my $errorMessage = shift;
  $self->{'errorMessage'} = $errorMessage;
}

sub getErrorMessage {
  my $self = shift;
  return $self->{'errorMessage'};
}

sub setAdjustment {
  my $self = shift;
  my $adjustment = shift;
  my $adjustmentType = lc shift || 'calculated';
  if (!defined $self->{'adjustment'}) {
    $self->{'adjustment'} = {};
  }
  $self->{'adjustment'}{$adjustmentType} = $adjustment;
}

sub getAdjustment {
  my $self = shift;
  my $adjustmentType = lc shift;
  if (!defined $self->{'adjustment'}) {
    $self->{'adjustment'} = {};
  }
  return $self->{'adjustment'}{$adjustmentType};
}

sub setCardType {
  my $self = shift;
  my $cardType = shift;
  $self->{'cardType'} = $cardType;
}

sub getCardType {
  my $self = shift;
  return $self->{'cardType'};
}

sub setMaxCardType {
  my $self = shift;
  my $maxCardType = shift;
  $self->{'maxCardType'} = $maxCardType;
}

sub getMaxCardType {
  my $self = shift;
  return $self->{'maxCardType'};
}

sub setMinCardType {
  my $self = shift;
  my $minCardType = shift;
  $self->{'minCardType'} = $minCardType;
}

sub getMinCardType {
  my $self = shift;
  return $self->{'minCardType'};
}

sub setCardBrand {
  my $self = shift;
  my $cardBrand = shift;
  $self->{'cardBrand'} = $cardBrand;
}

sub getCardBrand {
  my $self = shift;
  return $self->{'cardBrand'};
}

sub setIsDebit {
  my $self = shift;
  my $isDebit = shift;
  $self->{'isDebit'} = $isDebit;
}

sub getIsDebit {
  my $self = shift;
  return $self->{'isDebit'} || ($self->{'cardType'} eq 'debit');
}

sub setRequestor {
  my $self = shift;
  my $requestor = shift;
  $self->{'requestor'} = $requestor;
}

sub getRequestor {
  my $self = shift;
  return $self->{'requestor'};
}

sub getSubtypeID {
  my $self = shift;
  return $_subtypeMap->{$self->getCardType()};
}

sub getMaxSubtypeID {
  my $self = shift;
  return $_subtypeMap->{$self->getMaxCardType()};
}

sub getMinSubtypeID {
  my $self = shift;
  return $_subtypeMap->{$self->getMinCardType()};
}

sub _loadSubtypeMap {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT subtype_id, card_type FROM adjustment_coaremote_response_subtype_map
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  my %map;
  if ($result) {
    foreach my $row (@{$result}) {
      $map{$row->{'card_type'}} = $row->{'subtype_id'};
    }
  }

  $_subtypeMap = \%map; 
}



1;
