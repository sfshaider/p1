package PlugNPay::Transaction::Adjustment::Result;

use strict;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub setWarning {
  my $self = shift;
  my $warning = shift;
  $self->{'warning'} = $warning;
}

sub getWarning {
  my $self = shift;
  return $self->{'warning'};
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

sub setAdjustmentData {
  my $self = shift;
  my $adjustment = shift;
  my $type = shift || 'calculated';
  $self->{'adjustments'}{$type} = $adjustment;
}

sub getAdjustmentData {
  my $self = shift;
  my $type = shift || 'calculated';
  return $self->{'adjustments'}{$type} || {};
}

sub getAdjustment {
  my $self = shift;
  my $type = shift;
  return $self->getAdjustmentData($type)->{'adjustment'};
}

sub getTotalRate {
  my $self = shift;
  my $type = shift;
  return $self->getAdjustmentData($type)->{'rate'};
}

sub getFixedAdjustment {
  my $self = shift;
  my $type = shift;
  return $self->getAdjustmentData($type)->{'fixed'};
}

sub getAdjustmentTypes {
  my $self = shift;
  my @types = keys %{$self->{'adjustments'} || {}};
  return \@types;
}

sub getMaxAdjustment {
  my $self = shift;
  return $self->_getMaxAdjustmentInfo()->{'adjustment'};
}

sub getMaxAdjustmentType {
  my $self = shift;
  return $self->_getMaxAdjustmentInfo()->{'type'};
}

sub _getMaxAdjustmentInfo {
  my $self = shift;
  my $currentMaxAdjustment = 0;
  my $currentMaxAdjustmentType;
  foreach my $type (@{$self->getAdjustmentTypes}) {
    if ($self->getAdjustment($type) > $currentMaxAdjustment) {
      $currentMaxAdjustmentType = $type;
      $currentMaxAdjustment = $self->getAdjustment($type);
    }
  }
  return { type => $currentMaxAdjustmentType, adjustment => $currentMaxAdjustment };
}

sub getMinAdjustment {
  my $self = shift;
  return $self->_getMinAdjustmentInfo()->{'adjustment'};
}

sub getMinAdjustmentType {
  my $self = shift;
  return $self->_getMinAdjustmentInfo()->{'type'};
}

sub _getMinAdjustmentInfo {
  my $self = shift;
  my $currentMinAdjustment;
  my $currentMinAdjustmentType;
  foreach my $type (@{$self->getAdjustmentTypes}) {
    if (!defined $currentMinAdjustment) {
      $currentMinAdjustment = $self->getAdjustment($type);
      $currentMinAdjustmentType = $type;
    } else {
      if ($self->getAdjustment($type) < $currentMinAdjustment) {
        $currentMinAdjustmentType = $type;
        $currentMinAdjustment = $self->getAdjustment($type);
      }
    }
  }
  return { type => $currentMinAdjustmentType, adjustment => $currentMinAdjustment };
}


sub setModel {
  my $self = shift;
  my $model = shift;
  $self->{'model'} = $model;
}

sub getModel {
  my $self = shift;
  return $self->{'model'};
}

sub setThreshold {
  my $self = shift;
  my $threshold = shift;
  $self->{'threshold'} = $threshold;
}

sub getThreshold {
  my $self = shift;
  return $self->{'threshold'};
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

sub setCardType {
  my $self = shift;
  my $cardType = shift;
  $self->{'cardType'} = $cardType;
}

sub getCardType {
  my $self = shift;
  return $self->{'cardType'};
}

1;
