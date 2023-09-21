package PlugNPay::Transaction::Logging::Adjustment;

use strict;
use PlugNPay::Transaction::Logging::Adjustment::State;
use PlugNPay::COA;
use PlugNPay::ConvenienceFee;
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

sub setBaseAmount {
  my $self = shift;
  my $amount = shift;
  $self->{'baseAmount'} = $amount;
}

sub getBaseAmount {
  my $self = shift;
  return $self->{'baseAmount'} || 0;
}

sub setAdjustmentAmount {
  my $self = shift;
  my $amount = shift;
  $self->{'adjustmentTotal'} = $amount;
}

sub getAdjustmentAmount {
  my $self = shift;
  return $self->{'adjustmentTotal'} || 0;
}

# deprecated, use getAdjustmentAmount
sub setAdjustmentTotalAmount {
  my $self = shift;
  return $self->setAdjustmentAmount(@_);
}

# deprecated, use getAdjustmentAmount
sub getAdjustmentTotalAmount {
  my $self = shift;
  return $self->getAdjustmentAmount(@_);
}

sub getTransactionTotalAmount {
  my $self = shift;
  return ($self->getAdjustmentTotalAmount() + $self->getBaseAmount());
}

sub getCOA {
  my $self = shift;
  if (!defined $self->{'coa'}) {
    $self->{'coa'} = new PlugNPay::COA($self->getGatewayAccount());
    $self->{'coa'}->loadSettings();
  }
  return $self->{'coa'};
}

sub getConvFee {
  my $self = shift;
  if (!defined $self->{'convFee'}) {
    $self->{'convFee'} = new PlugNPay::ConvenienceFee($self->getGatewayAccount());
    $self->{'convFee'}->load();
  }
  return $self->{'convFee'};
}

sub getStateID {
  my $self = shift;

  my $state = new PlugNPay::Transaction::Logging::Adjustment::State();

  $state->setGatewayAccount($self->getGatewayAccount());
  # coa stuff
  $state->setCOAData($self->getCOA()->getState());
  $state->setFormula($self->getCOA()->getFormula());
  $state->setModel($self->getCOA()->getModel());
  # conv adjustment stuff
  $state->setBucketData($self->getConvFee()->getBuckets());
  $state->setMode($self->getConvFee()->getMode());

  if ($state->exists()) {
    $state->load();
  } else {
    $state->save();
    $state->load();
  }
  my $stateID = $state->getID();

  return $stateID;
}

sub setOrderID {
  my $self = shift;
  my $orderID = shift;
  $self->{'orderID'} = $orderID;
}

sub getOrderID {
  my $self = shift;
  return $self->{'orderID'};
}

sub setAdjustmentOrderID {
  my $self = shift;
  my $orderID = shift;
  $self->{'adjustmentOrderID'} = $orderID;
}

sub getAdjustmentOrderID {
  my $self = shift;
  return $self->{'adjustmentOrderID'} || '';
}

sub setAdjustmentGatewayAccount {
  my $self = shift;
  my $account = shift;
  $self->{'adjustmentGatewayAccount'} = $account;
}

sub getAdjustmentGatewayAccount {
  my $self = shift;
  return $self->{'adjustmentGatewayAccount'} || '';
}

sub setAdjustmentMode {
  my $self = shift;
  my $adjustmentMode = shift;
  $self->{'adjustmentMode'} = $adjustmentMode;
}

sub getAdjustmentMode {
  my $self = shift;
  return $self->{'adjustmentMode'};
}

sub setAdjustmentModel {
  my $self = shift;
  my $adjustmentModel = shift;
  $self->{'adjustmentModel'} = $adjustmentModel;
}

sub getAdjustmentModel {
  my $self = shift;
  return $self->{'adjustmentModel'};
}

sub setPNPTransactionID {
  my $self = shift;
  my $id = shift;
  $self->{'pnpTransactionID'} = $id;
}

sub getPNPTransactionID {
  my $self = shift;
  return $self->{'pnpTransactionID'};
}

sub setAdjustmentPNPTransactionID {
  my $self = shift;
  my $id = shift;
  $self->{'adjustmentPNPTransactionID'} = $id;
}

sub getAdjustmentPNPTransactionID {
  my $self = shift;
  return $self->{'adjustmentPNPTransactionID'};
}

sub log {
  my $self = shift;

  if (!$self->getCOA()->getEnabled() && !$self->getConvFee()->getEnabled()) {
    return;
  }

  my $dbs = new PlugNPay::DBConnection();

  my $data = {
    username => $self->getGatewayAccount(),
    order_id => $self->getOrderID(),
    base_amount => $self->getBaseAmount(),
    adjustment_total_amount => $self->getAdjustmentTotalAmount(),
    adjustment_state_id => $self->getStateID(),
    adjustment_username => $self->getAdjustmentGatewayAccount(),
    adjustment_order_id => $self->getAdjustmentOrderID()
  };

  my $columnInfo = $dbs->getColumnsForTable({ database => 'pnpmisc', table => 'adjustment_log' });

  if (defined $columnInfo->{'pnp_transaction_id'} && defined $columnInfo->{'adjustment_pnp_transaction_id'}) {
    $data->{'pnp_transaction_id'} = $self->getPNPTransactionID();
    $data->{'adjustment_pnp_transaction_id'} = $self->getAdjustmentPNPTransactionID();
  }

  my $query = 'INSERT INTO adjustment_log (`' . join('`,`',keys(%{$data})) . '`) VALUES (' . join(',',map { '?' } keys(%{$data})) . ')';

  my @vals = values(%{$data});
  $dbs->executeOrDie('pnpmisc', $query, \@vals);
}

sub load {
  my $self = shift;

  if ($self->getGatewayAccount() && $self->getOrderID()) {
    $self->_loadByGatewayAccountAndOrderID();
  }
}

sub _loadByGatewayAccountAndOrderID {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT username,order_id,base_amount,adjustment_total_amount,adjustment_state_id,adjustment_username,adjustment_order_id
      FROM adjustment_log
     WHERE username = ? AND order_id = ?
  /);

  $sth->execute($self->getGatewayAccount(),$self->getOrderID());

  my $result = $sth->fetchall_arrayref({});

  if ($result && $result->[0]) {
    $self->_setFromRow($result->[0]);
  }
}

sub _setFromRow {
  my $self = shift;
  my $row = shift;
  my $object = shift || $self;

  $object->setBaseAmount($row->{'base_amount'});
  $object->setAdjustmentTotalAmount($row->{'adjustment_total_amount'});
  $object->setAdjustmentGatewayAccount($row->{'adjustment_username'});
  $object->setAdjustmentOrderID($row->{'adjustment_order_id'});
}

sub loadMultiple {
  my $self = shift;
  my $orderIDsArrayRef = shift;

  my $placeholders = join(',',map { '?' } @{$orderIDsArrayRef});

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT username,order_id,base_amount,adjustment_total_amount,adjustment_state_id,adjustment_username,adjustment_order_id
      FROM adjustment_log
     WHERE username = ?
       AND order_id in (/ . $placeholders . q/)
  /);

  $sth->execute($self->getGatewayAccount(),@{$orderIDsArrayRef});

  my $result = $sth->fetchall_arrayref({});

  my %adjustments;

  if ($result) {
    foreach my $row (@{$result}) {
      my $entry = new ref($self);
      $entry->setGatewayAccount($self->getGatewayAccount);
      $entry->setOrderID($row->{'order_id'});

      $self->_setFromRow($row,$entry);

      $adjustments{$row->{'order_id'}} = $entry;
    }
  }

  return \%adjustments;
}

sub loadMultipleWithStateInfo {
  my $self = shift;
  my $orderIDsArrayRef = shift;

  my $placeholders = join(',',map { '?' } @{$orderIDsArrayRef});

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT l.username,l.order_id,l.base_amount,l.adjustment_total_amount,
           l.adjustment_state_id,l.adjustment_username,l.adjustment_order_id,
           s.mode, s.model
      FROM adjustment_log l, adjustment_log_state s
     WHERE l.username = ?
       AND s.id = l.adjustment_state_id
       AND l.order_id in (/ . $placeholders . q/)
  /);

  $sth->execute($self->getGatewayAccount(),@{$orderIDsArrayRef});

  my $result = $sth->fetchall_arrayref({});

  my %adjustments;

  if ($result) {
    foreach my $row (@{$result}) {
      my $entry = new ref($self);
      $entry->setGatewayAccount($self->getGatewayAccount());
      $entry->setOrderID($row->{'order_id'});

      $self->_setFromRow($row,$entry);
      $entry->setAdjustmentMode($row->{'mode'});
      $entry->setAdjustmentModel($row->{'model'});

      $adjustments{$row->{'order_id'}} = $entry;
    }
  }

  return \%adjustments;
}

1;
