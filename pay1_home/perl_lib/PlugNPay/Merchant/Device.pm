package PlugNPay::Merchant::Device;

use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Merchant::Device::Type;
use strict;

sub new {
  my $class = shift;
  my $self = {};

  bless $self,$class;

  return $self;
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

sub setMerchantID {
  my $self = shift;
  my $merchantID = shift;

  $self->{'merchantID'} = $merchantID;
}

sub getMerchantID {
  my $self = shift;

  return $self->{'merchantID'};
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

sub setTypeID {
  my $self = shift;
  my $type = shift;

  $self->{'typeID'} = $type;
}

sub getTypeID {
  my $self = shift;

  return $self->{'typeID'};
}

sub setType {
  my $self = shift;
  my $type = shift;

  $self->{'type'} = $type;
}

sub getType {
  my $self = shift;

  return $self->{'type'};
}

sub setDeviceID {
  my $self = shift;
  my $deviceID = shift;

  $self->{'deviceID'} = $deviceID;
}

sub getDeviceID {
  my $self = shift;

  return $self->{'deviceID'};
}

sub setSerialNumber {
  my $self = shift;
  my $serialNumber = shift;

  $self->{'serialNumber'} = $serialNumber;
}

sub getSerialNumber {
  my $self = shift;

  return $self->{'serialNumber'};
}

sub loadDeviceByDeviceID {
  my $self = shift;
  my $deviceID = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust',q /
                          SELECT id, merchant_id, name, type, serial_number
                          FROM merchant_device
                          WHERE device_id = ?
                         /);
  $sth->execute($deviceID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  if(@{$rows}) {
    my $row = $rows->[0];
    $self->setID($row->{'id'});
    $self->setMerchantID($row->{'merchant_id'});
    $self->setName($row->{'name'});
    $self->setTypeID($row->{'type'});
    $self->setDeviceID($deviceID);
    $self->setSerialNumber($row->{'serial_number'});
  }
}

sub loadMerchantTerminalSerialNumbers {
  my $self = shift;
  my $merchantID = shift;

  my $type = new PlugNPay::Merchant::Device::Type();
  $type->loadTypeByType('terminal');
  my $typeID = $type->getID();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/
                           SELECT serial_number, name
                           FROM merchant_device
                           WHERE merchant_id = ? AND type = ?
                         /);

  $sth->execute($merchantID,$typeID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $merchantTerminalSerialNumbers = {};
  if(@{$rows}) {
    foreach my $row (@{$rows}) {
      $merchantTerminalSerialNumbers->{$row->{'serial_number'}} = $row->{'name'};
    }
  }
  return $merchantTerminalSerialNumbers;
}

sub isDeviceConnectedToMerchant {
  my $self = shift;
  my $merchantID = shift;
  my $serialNumber = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust',q/
                    SELECT COUNT(id) as `connected`
                    FROM merchant_device
                    WHERE merchant_id = ? AND serial_number = ?
                   /);
  eval {
    $sth->execute($merchantID,$serialNumber) or die $DBI::errstr;
  };

  my $result;
  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Merchant'});
    $logger->log({
      'status'               => 'ERROR',
      'message'              => 'Failed to check if device is connected to merchant',
      'module'               => 'PlugNPay::Merchant::Device',
      'function'             => 'isDeviceConnectedToMerchant',
      'merchantID'           => $merchantID,
      'terminalSerialNumber' => $serialNumber,
      'error'                => $@
    });
    $result = 0;
  }

  my $row = $sth->fetchall_arrayref({});
  if (@{$row}) {
     $result = $row->[0]{'connected'};
  }
  return $result;
}

sub loadDeviceBySerialNumber {
  my $self = shift;
  my $serialNumber = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/
                          SELECT id, merchant_id, name, type, serial_number, device_id
                          FROM merchant_device
                          WHERE serial_number = ?
                          /);
  $sth->execute($serialNumber) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  if (@{$rows}) {
    my $row = $rows->[0];
    $self->setID($row->{'id'});
    $self->setMerchantID($row->{'merchant_id'});
    $self->setName($row->{'name'});
    $self->setTypeID($row->{'type'});
    $self->setDeviceID($row->{'device_id'});
    $self->setSerialNumber($serialNumber);
  }    
}

sub doesDeviceExist {
  my $self = shift;
  my $deviceID = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/
                           SELECT COUNT(device_id) as `exist`
                           FROM merchant_device
                           WHERE device_id = ?
                         /);
  $sth->execute($deviceID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  return $rows->[0]{'exist'};
}

sub doesSerialNumberExist {
  my $self = shift;
  my $serialNumber = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/
                          SELECT COUNT(serial_number) as `exist`
                          FROM merchant_device
                          WHERE serial_number = ?
                         /);
  $sth->execute($serialNumber) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  
  return $rows->[0]{'exist'}
}

sub loadDevice {
  my $self = shift;
  my $id = shift;

  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('merchant_cust', q/
                           SELECT merchant_id, name, type, device_id, serial_number
                           FROM merchant_device
                           WHERE id = ? /);

  $sth->execute($id) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  if(@{$rows}) {
    my $row = $rows->[0];
    $self->setID($id);
    $self->setMerchantID($row->{'merchant_id'});
    $self->setName($row->{'name'});
    $self->setTypeID($row->{'type'});
    $self->setDeviceID($row->{'device_id'});
    $self->setSerialNumber($row->{'serial_number'});
  }
}


sub loadMerchantDevices {
  my $self = shift;
  my $merchantID = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/
                           SELECT id
                           FROM merchant_device
                           WHERE merchant_id = ? /);

  $sth->execute($merchantID) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});

  my $devices = [];

  if(@{$rows}) {
    foreach my $row (@{$rows}) {
      my $device = new PlugNPay::Merchant::Device();
      $device->loadDevice($row->{'id'});
      push @{$devices},$device;
    }
  }
  return $devices;
}

sub insertDevice {
  my $self = shift;
  my $options = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('merchant_cust');

  my $sth = $dbs->prepare('merchant_cust', q/
                           INSERT INTO merchant_device (merchant_id,name, type, device_id, serial_number)
                           VALUES (?,?,?,?,?)
                          /);
  eval {
    $sth->execute($options->{'merchantID'}, $options->{'name'}, $options->{type}, $options->{'deviceID'}) or die $DBI::errstr;
  };

  if($@) {
    $dbs->rollback('merchant_cust');
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Merchant'});
    $logger->log({'message' => 'Failed to insert new merchant device for the merchant with an id of ' . $options->{'merchantID'}, 'error' => $@});
    return 0;
  }

  $dbs->commit('merchant_cust');
  return 1;
}

sub updateDevice {
  my $self = shift;
  my $options = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('merchant_cust');

  my $sth = $dbs->prepare('merchant_cust', q/
                           UPDATE merchant_device
                           SET merchant_id = ?, name = ?, type = ?, device_id = ?, serial_number = ?
                           WHERE id = ?  /);
  eval {
    $sth->execute($options->{'merchantID'}, $options->{'name'}, $options->{'type'},$options->{'tranDeviceID'}, $options->{'serialNumber'}, $options->{'deviceID'}) or die $DBI::errstr;
  };

  if($@) {
    $dbs->rollback('merchant_cust');
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Merchant'});
    $logger->log({'message' => 'Failed to update merchant device.', 'error' => $@});
    return 0;
  }

  $dbs->commit('merchant_cust');
  return 1;
}

sub deleteDevice {
  my $self = shift;
  my $id = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('merchant_cust');

  my $sth = $dbs->prepare('merchant_cust', q/
                           DELETE
                           FROM merchant_device
                           WHERE id = ?
                          /);
  eval {
    $sth->execute($id) or die $DBI::errstr;
  };

  if($@) {
    $dbs->rollback('merchant_cust');
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Merchant'});
    $logger->log({'message' => 'Failed to delete merchant device with an id of ' . $id , 'error' => $@});
    return 0;
  }

  $dbs->commit('merchant_cust');
  return 1;
}

1;
