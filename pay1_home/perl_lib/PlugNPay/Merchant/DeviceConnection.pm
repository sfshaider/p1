package PlugNPay::Merchant::DeviceConnection;

use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Merchant::Device;
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

sub setDeviceID {
  my $self = shift;
  my $deviceID = shift;

  $self->{'deviceID'} = $deviceID;
}

sub getDeviceID {
  my $self = shift;

  return $self->{'deviceID'};
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


sub setIPAddress {
  my $self = shift;
  my $ipAddress = shift;

  $self ->{'ipAddress'} = $ipAddress;
}

sub getIPAddress {
  my $self = shift;

  return $self->{'ipAddress'};
}

sub setPort {
  my $self = shift;
  my $port = shift;

  $self->{'port'} = $port;
}

sub getPort {
  my $self = shift;

  return $self->{'port'};
}

sub loadDeviceIPAndPort {
  my $self = shift;
  my $deviceID = shift;
  
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/
                          SELECT ipaddress, port
                          FROM merchant_device_connection
                          WHERE device_id = ?
                         /);
  $sth->execute($deviceID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  if(@{$rows}) {
    my $row = $rows->[0];
    $self->setIPAddress($row->{'ipaddress'});
    $self->setPort($row->{'port'});
  }
}

sub loadDeviceConnection {
  my $self = shift;
  my $id = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust',q/
                    SELECT merchant_id, device_id, description, ipaddress, port
                    FROM merchant_device_connection
                    WHERE id = ?  /);

  $sth->execute($id) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});

  if(@{$rows}) {
    my $row = $rows->[0];
    $self->setID($id);
    $self->setMerchantID($row->{'merchant_id'});
    $self->setDeviceID($row->{'device_id'});
    $self->setDescription($row->{'description'});
    $self->getIPAddress($row->{'ipaddress'});
    $self->setPort($row->{'port'});
  }
}


sub loadMerchantDeviceConnections {
  my $self = shift;
  my $merchantID = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/
                           SELECT id
                           FROM merchant_device_connection
                           WHERE merchant_id = ? /);

  $sth->execute($merchantID) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});

  my $deviceConnections = [];

  if(@{$rows}) {
    foreach my $row (@{$rows}) {
      my $deviceConnection = new PlugNPay::Merchant::DeviceConnection();
      $deviceConnection->loadDeviceConnection($row->{'id'});
      push @{$deviceConnections},$deviceConnection;
    }
  }

  return $deviceConnections;
}


sub deleteDeviceConnection {
  my $self = shift;
  my $deviceConnectionID = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('merchant_cust');

  my $sth = $dbs->prepare('merchant_cust', q/
                           DELETE
                           FROM merchant_device_connection
                           WHERE id = ? /);
  eval {
    $sth->execute($deviceConnectionID) or die $DBI::errstr;
  };

  if($@) {
    $dbs->rollback('merchant_cust');
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Merchant'});
    $logger->log({'message' => 'Failed to remove device connection', 'error' => $@});
    return 0;
  }

  $dbs->commit('merchant_cust');
  return 1;
}


sub insertDeviceConnection {
  my $self = shift;
  my $options = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('merchant_cust');

  my $sth = $dbs->prepare('merchant_cust', q/
                           INSERT INTO merchant_device_connection (merchant_id, device_id, description, ipaddress, port)
                           VALUES (?,?,?,?,?) /);

  eval {
    $sth->execute($options->{'merchantID'}, $options->{'deviceID'}, $options->{'description'}, $options->{'ipAddress'}, $options->{'port'}) or die $DBI::errstr;
  };

  if($@) {
    $dbs->rollback('merchant_cust');
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Merchant'});
    $logger->log({'message' => 'Failed to insert device connection.', 'error' => $@});
    return 0;
  }

  $dbs->commit('merchant_cust');
  return 1;
}

sub updateDeviceConnection {
  my $self = shift;
  my $options = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('merchant_cust');

  my $sth = $dbs->prepare('merchant_cust', q/
                           UPDATE merchant_device_connection
                           SET merchant_id = ?, device_id = ?, description = ?, ipaddress = ? , port = ?
                           WHERE id = ? /);

  eval {
    $sth->execute($options->{'merchantID'}, $options->{'deviceID'}, $options->{'description'}, $options->{'ipAddress'}, $options->{'port'}, $options->{'deviceConnectionID'}) or die $DBI::errstr;
  };

  if($@) {
    $dbs->rollback('merchant_cust');
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Merchant'});
    $logger->log({'message' => 'Failed to update device connection', 'error' => $@});
    return 0;
  }

  $dbs->commit('merchant_cust');
  return 1;
}

1;
