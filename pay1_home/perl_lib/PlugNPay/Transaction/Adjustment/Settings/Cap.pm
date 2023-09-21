package PlugNPay::Transaction::Adjustment::Settings::Cap;

use strict;

use PlugNPay::DBConnection;
use PlugNPay::Util::RPN;
use PlugNPay::Util::Clone;

our $_capModes;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_capModes) {
    $self->_loadCapModes();
  }

  my $settings = shift;
  if (ref $settings eq 'HASH') {
    if (defined $settings->{'gatewayAccount'}) {
      $self->setGatewayAccount($settings->{'gatewayAccount'});
    }
  
    if (defined $settings->{'defaultPaymentVehicleSubtypeID'}) {
      $self->setDefaultPaymentVehicleSubtypeID($settings->{'defaultPaymentVehicleSubtypeID'});
    }
  
    if (defined $settings->{'transactionAmount'}) {
      $self->setTransactionAmount($settings->{'transactionAmount'});
    }

    if (defined $settings->{'modeID'}) {
      $self->setID($settings->{'modeID'});
    }
  } elsif (ref $settings eq '') {
    $self->setGatewayAccount($settings);
  }
 
  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setTransactionAmount {
  my $self = shift;
  my $transactionAmount = shift;
  $self->{'transactionAmount'} = $transactionAmount;
}

sub getTransactionAmount {
  my $self = shift;
  return $self->{'transactionAmount'};
}

sub setDefaultPaymentVehicleSubtypeID {
  my $self = shift;
  my $defaultPaymentVehicleSubtypeID = shift;
  $self->{'defaultPaymentVehicleSubtypeID'} = $defaultPaymentVehicleSubtypeID;
}

sub getDefaultPaymentVehicleSubtypeID {
  my $self = shift;
  return $self->{'defaultPaymentVehicleSubtypeID'};
}

sub setPercent {
  my $self = shift;
  my $capPercent = shift;
  $self->{'capPercent'} = $capPercent;
}

sub getPercent {
  my $self = shift;
  return $self->{'capPercent'};
}

sub setFixed {
  my $self = shift;
  my $fixedCap = shift;
  $self->{'fixedCap'} = $fixedCap;
}

sub getFixed {
  my $self = shift;
  return $self->{'fixedCap'};
}

sub setID {
  my $self = shift;
  my $id = shift;
  $self->{'id'} = $id;
}

sub getID {
  my $self = shift;
  return $self->{'id'};
}

sub setMode {
  my $self = shift;
  my $mode = shift;
  $self->{'mode'} = $mode;
}

sub getMode {
  my $self = shift;
  return $self->{'mode'};
}

sub setEnabled {
  my $self = shift;
  my $enabled = shift;
  $self->{'enabled'} = $enabled;
}

sub getEnabled {
  my $self = shift;
  return $self->{'enabled'};
}

sub setName {
  my $self = shift;
  my $name = shift;
  $self->{'name'} = $name;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub setPaymentVehicleSubtypeID {
  my $self = shift;
  my $id = shift;
  $self->{'paymentVehicleSubtypeID'} = $id;
}

sub getPaymentVehicleSubtypeID {
  my $self = shift;
  return $self->{'paymentVehicleSubtypeID'};
}

sub setDescription {
  my $self = shift;
  my $description = shift;
  $self->{'description'} = $description;
}

sub getDescription {
  my $self = shift;
  return $self->{'description'};
}

sub getEnabledModes {
  my $self = shift;

  my @enabledModes;

  foreach my $mode (@{$_capModes}) {
    if ($mode->{enabled} == 1) {
      my $enabledMode = new ref($self);
      $enabledMode->loadMode($mode->{'id'});
      push @enabledModes,$enabledMode;
    }
  }

  return \@enabledModes;
}

sub calculateCap {
  my $self = shift;
  my $rpn = new PlugNPay::Util::RPN();


  $rpn->addVariable('transactionAmount', $self->getTransactionAmount());
  $rpn->addVariable('percent',($self->getPercent() / 100) * $self->getTransactionAmount());
  $rpn->addVariable('fixed',$self->getFixed());
  $rpn->setFormula($self->_infoForCapMode($self->getID(),'formula'));
  return $rpn->calculate();
}

sub _infoForCapMode {
  my $self = shift;
  my $mode = shift;
  my $key = shift;
  foreach my $validMode (@{$_capModes}) {
    if ($mode eq $validMode->{'id'} || $mode eq $validMode->{'mode'}) {
      return $validMode->{$key};
    }
  }
}

sub getCap {
  my $self = shift;
  my $vehicleSubtypeID = shift;

  if (!defined $self->{'caps'}) {
    $self->_loadCaps();
  }

  # if requested cap is not defined, try the default
  if (!defined $self->{'caps'}{$vehicleSubtypeID}) {
    $vehicleSubtypeID = $self->getDefaultPaymentVehicleSubtypeID();
  }

  # if neither the requested nor the default are defined, return the transaction amount
  if (defined $self->{'caps'}{$vehicleSubtypeID}) {
    return $self->{'caps'}{$vehicleSubtypeID}->calculateCap();
  } else {
    return $self->getTransactionAmount();
  }
}

sub getCaps {
  my $self = shift;
  if (!defined $self->{'caps'}) {
    $self->_loadCaps();
  }

  # change return value to array
  my @caps;
  foreach my $cap (values %{$self->{'caps'}}) {
    push @caps,$cap;
  }
  
  return \@caps;
}

sub _loadCaps {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT payment_vehicle_subtype_id, fixed, percent
      FROM adjustment_cap
     WHERE username = ?
  /) or die($DBI::errstr);

  $sth->execute($self->getGatewayAccount()) or die($DBI::errstr);

  my $result = $sth->fetchall_arrayref({});
  my $cloner = new PlugNPay::Util::Clone();

  my %caps;
  if ($result) {
    foreach my $row (@{$result}) {
      my $cap = $cloner->deepClone($self);
      $cap->setFixed($row->{'fixed'});
      $cap->setPercent($row->{'percent'});
      $cap->setPaymentVehicleSubtypeID($row->{'payment_vehicle_subtype_id'});
      $caps{$row->{'payment_vehicle_subtype_id'}} = $cap;
    }
  }
  $self->{'caps'} = \%caps;
}

sub loadMode {
  my $self =shift;
  my $id = shift;
  $self->setID($id);
  $self->_loadMode();
}

sub _loadMode {
  my $self = shift;
  my $idOrMode = $self->getID() || $self->getMode() || shift;
  foreach my $mode (@{$_capModes}) {
    if ($idOrMode eq $mode->{'id'} || $idOrMode eq $mode->{'mode'}) {
      $self->setID($mode->{'id'});
      $self->setMode($mode->{'mode'});
      $self->setEnabled($mode->{'enabled'});
      $self->setName($mode->{'name'});
      $self->setDescription($mode->{'description'});
    }
  }
}

sub _loadCapModes {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id,mode,formula,enabled,name,description FROM adjustment_cap_mode
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  if ($result) {
    my @modes;
    foreach my $row (@{$result}) {
      my $mode = {
        id => $row->{'id'},
        mode => $row->{'mode'},
        formula => $row->{'formula'},
        enabled => $row->{'enabled'},
        name => $row->{'name'},
        description => $row->{'description'},
      };

      push @modes,$mode;
    }

    $_capModes = \@modes;
  }
}

sub _removeAll {
  my $self = shift;

  my $username = shift || $self->getGatewayAccount();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/
        DELETE FROM adjustment_cap
        WHERE username=?
  /);

  $sth->execute($username);
}

sub setCaps {
  my $self = shift;
  my $caps = shift;

  if (!defined $caps) {
    return;
  }

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('pnpmisc');

  $self->_removeAll();

  if (!@{$caps}) {           # if there are no caps then 
    $dbs->commit('pnpmisc'); # commit the removal of the existing caps
    return 1;
  }

  my @placeholders;
  my @values;
  
  my %capsHash;
  foreach my $cap (@{$caps}) {
    push @placeholders,'(?,?,?,?)';
    push @values, $self->getGatewayAccount();
    push @values, $cap->getPaymentVehicleSubtypeID();
    push @values, $cap->getFixed();
    push @values, $cap->getPercent();
    $capsHash{$cap->getPaymentVehicleSubtypeID()} = $cap;
  }

  $self->{'caps'} = \%capsHash;

  my $query = q/
    INSERT INTO adjustment_cap ( username, payment_vehicle_subtype_id, fixed, percent)
         VALUES / . join(',',@placeholders);

  my $sth;
  if (@{$caps} && ($sth = $dbs->prepare('pnpmisc',$query)) && $sth->execute(@values)) {
    $dbs->commit('pnpmisc');
  } else {
    $dbs->rollback('pnpmisc');
  }
}

1;
