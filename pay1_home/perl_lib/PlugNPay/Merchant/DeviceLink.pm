package PlugNPay::Merchant::DeviceLink;

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

sub setLinkTypeID {
  my $self = shift;
  my $linkTypeID = shift;

  $self->{'linkTypeID'} = $linkTypeID;
}

sub getLinkTypeID {
  my $self = shift;

  return $self->{'linkTypeID'};
}

sub setParentDeviceID {
  my $self = shift;
  my $parentDeviceID = shift;

  $self->{'parentDeviceID'} = $parentDeviceID;
}

sub getParentDeviceID {
  my $self = shift;

  return $self->{'parentDeviceID'};
}

sub setChildDeviceID {
  my $self = shift;
  my $childDeviceID = shift;

  $self->{'childTypeID'} = $childDeviceID;
}

sub getChildDeviceID {
  my $self = shift;

  return $self->{'childDeviceID'};
}

sub loadLinkedTranCloudDevice {
  my $self = shift;
  my $terminalID = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/
                           SELECT parent_device_id
                           FROM merchant_device_link
                           WHERE child_device_id = ?
                         /);

  $sth->execute($terminalID) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});
  my $tranCloudID;

  if(@{$rows}) {
     $tranCloudID = $rows->[0]{'parent_device_id'};
  }
  return $tranCloudID;
}

sub isDeviceLinked {
  my $self = shift;
  my $parentDeviceID = shift || $self->getParentDeviceID();
  my $childDeviceID = shift || $self->getChildDeviceID();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/
                           SELECT COUNT(id)  as `linked`
                           FROM merchant_device_link
                           WHERE parent_device_id = ? AND child_device_id = ?
                         /);
  $sth->execute($parentDeviceID,$childDeviceID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  if(@{$rows}) {
    return $rows->[0]{'linked'};
  }
}

sub loadDeviceLink {
  my $self = shift;
  my $id = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust', q/
                            SELECT merchant_id, link_type_id, parent_device, child_device_id
                            FROM merchant_device_link
                            WHERE id = ? /);

  $sth->execute($id) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});

  if(@{$rows}) {
    my $row = $rows->[0];
    $self->setID($id);
    $self->setMerchantID($row->{'merchant_id'});
    $self->setLinkTypeID($row->{'link_type_id'});
    $self->setParentDeviceID($row->{'parent_device_id'});
    $self->setChildDeviceID($row->{'child_device_id'});
  }
}


sub loadMerchantDeviceLinks {
  my $self = shift;
  my $merchantID = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('merchant_cust',q/
                           SELECT id
                           FROM merchant_device_link
                           WHERE merchant_id = ?
                          /);

  $sth->execute($merchantID) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});
  my $deviceLinks = [];
  if(@{$rows}) {
    foreach my $row (@{$rows}) {
      my $deviceLink = new PlugNPay::Merchant::DeviceLink();
      $deviceLink->loadDeviceLink($row->{'id'});
      push @{$deviceLinks},$deviceLink;
    }
  }
  return $deviceLinks;
}

sub insertDeviceLink {
  my $self = shift;
  my $options = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('merchant_cust');

  my $sth = $dbs->prepare('merchant_cust', q/
                           INSERT INTO merchant_device_link (merchant_id, link_type_id, parent_device_id, child_device_id)
                           VALUES (?,?,?,?)
                          /);
  eval {
    $sth->execute($options->{'merchantID'}, $options->{'linkTypeID'}, $options->{'parentDeviceID'}, $options->{'childDeviceID'}) or die $DBI::errstr;
  };

  if($@) {
    $dbs->rollback('merchant_cust');
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Merchant'});
    $logger->log({'message' => 'Failed to insert device link.', 'error' => $@});
    return 0;
  }

  $dbs->commit('merchant_cust');
  return 1;
}

sub deleteDeviceLink {
  my $self = shift;
  my $deviceID = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('merchant_cust');

  my $sth = $dbs->prepare('merchant_cust', q/
                           DELETE
                           FROM merchant_device_link
                           WHERE id = ?
                          /);

  eval {
    $sth->execute($deviceID) or die $DBI::errstr;
  };

  if($@) {
    $dbs->rollback('merchant_cust');
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Merchant'});
    $logger->log({'message' => 'Failed to remove device link', 'error' => $@});
    return 0;
  }

  $dbs->commit('merchant_cust');
  return 1;
}


sub updateDeviceLink {
  my $self = shift;
  my $options = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('merchant_cust');

  my $sth = $dbs->prepare('merchant_cust', q/
                           UPDATE merchant_device_link
                           SET merchant_id, link_type_id, parent_device_id, child_device_id
                           id = ?
                           /);


  eval {
    $sth->execute($options->{'merchantID'}, $options->{'linkTypeID'}, $options->{'parentDeviceID'}, $options->{'childDeviceID'}, $options->{'deviceLinkID'}) or die $DBI::errstr;
  };

  if($@) {
    $dbs->rollback('merchant_cust');
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Merchant'});
    $logger->log({'message' => 'Failed to update device link.', 'error' => $@});
    return 0;
  };

  $dbs->commit('merchant_cust');
  return 1;
}

1;