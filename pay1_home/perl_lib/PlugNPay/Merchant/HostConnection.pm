package PlugNPay::Merchant::HostConnection;

use strict;
use PlugNPay::Merchant;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Merchant::Host;
use PlugNPay::Merchant::Proxy;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::RandomString;
use PlugNPay::Merchant::Credential;
use PlugNPay::Merchant::HostConnection::Protocol;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $merchant = shift;
  if ($merchant) {
    if (ref($merchant) =~ /^PlugNPay::Merchant::Proxy/) {
      $self->{'merchantDB'} = $merchant;
    } else {
      $self->setMerchantID($merchant);
      $self->{'merchantDB'} = new PlugNPay::Merchant::Proxy($merchant);
    }
  }

  return $self;
}

sub setHostConnectionID {
  my $self = shift;
  my $hostConnectionID = shift;
  $self->{'hostConnectionID'} = $hostConnectionID;
}

sub getHostConnectionID {
  my $self = shift;
  return $self->{'hostConnectionID'};
}

sub setIdentifier {
  my $self = shift;
  my $identifier = shift;
  $self->{'identifier'} = $identifier;
}

sub getIdentifier {
  my $self = shift;
  return $self->{'identifier'};
}

sub setMerchantID {
  my $self = shift;
  my $merchant = shift;

  if ($merchant !~ /^[0-9]+$/) {
    $merchant = new PlugNPay::Merchant($merchant)->getMerchantID();
  }

  $self->{'merchantID'} = $merchant;
}

sub getMerchantID {
  my $self = shift;
  return $self->{'merchantID'};
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

sub setHostID {
  my $self = shift;
  my $hostID = shift;
  $self->{'hostID'} = $hostID;
}

sub getHostID {
  my $self = shift;
  return $self->{'hostID'};
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

sub setProtocolID {
  my $self = shift;
  my $protocolID = shift;
  $self->{'protocolID'} = $protocolID;
}

sub getProtocolID {
  my $self = shift;
  return $self->{'protocolID'};
}

sub setCredentialID {
  my $self = shift;
  my $credentialID = shift;
  $self->{'credentialID'} = $credentialID;
}

sub getCredentialID {
  my $self = shift;
  return $self->{'credentialID'};
}

sub setPath {
  my $self = shift;
  my $path = shift;
  $self->{'path'} = $path;
}

sub getPath {
  my $self = shift;
  return $self->{'path'};
}

sub loadMerchantHostConnections {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $connections = [];

  my @values = ();
  my $sql = q/SELECT id,
                     merchant_id,
                     identifier,
                     description,
                     host_id,
                     port,
                     protocol_id,
                     credential_id,
                     path
              FROM merchant_host_connection
              WHERE merchant_id = ?
              ORDER BY id ASC/;
  push (@values, $merchantDB);

  my $limit = '';
  if ( (defined $self->{'limitData'}{'limit'}) && (defined $self->{'limitData'}{'offset'}) ) {
    $limit = ' LIMIT ?,? ';
    push (@values, $self->{'limitData'}{'offset'});
    push (@values, $self->{'limitData'}{'limit'});
  }

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust', $sql . $limit, \@values, {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        my $hostConnection = new PlugNPay::Merchant::HostConnection();
        $hostConnection->_setHostConnectionDataFromRow($row);
        push (@{$connections}, $hostConnection);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'function'   => 'loadMerchantHostConnections',
      'merchantDB' => $merchantDB
    });
  }

  return $connections;
}

sub loadHostConnection {
  my $self = shift;
  my $hostConnectionID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               merchant_id,
               identifier,
               description,
               host_id,
               port,
               protocol_id,
               credential_id,
               path
       FROM merchant_host_connection
       WHERE id = ?/, [$hostConnectionID], {})->{'result'};
    if (@{$rows}) {
      my $row = $rows->[0];
      $self->_setHostConnectionDataFromRow($row);
    }
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'function'   => 'loadHostConnection',
      'merchantDB' => $self->{'merchantDB'}
    });
  }
}

sub _setHostConnectionDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'hostConnectionID'} = $row->{'id'};
  $self->{'merchantID'}       = $row->{'merchant_id'};
  $self->{'identifier'}       = $row->{'identifier'};
  $self->{'description'}      = $row->{'description'};
  $self->{'hostID'}           = $row->{'host_id'};
  $self->{'port'}             = $row->{'port'};
  $self->{'protocolID'}       = $row->{'protocol_id'};
  $self->{'credentialID'}     = $row->{'credential_id'};
  $self->{'path'}             = $row->{'path'};
}

sub saveMerchantHostConnection {
  my $self = shift;
  my $data = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $merchantDB = $self->{'merchantDB'};
  if (!$merchantDB->isMaster()) {
    $status->setFalse();
    $status->setError('Access denied.');
    return $status;
  }

  my $host = new PlugNPay::Merchant::Host($merchantDB);
  $host->loadByHostIdentifier($data->{'hostIdentifier'});
  if (!$host->getHostID()) {
    push (@errorMsg, 'Invalid host identifier.');
  }

  my $credential = new PlugNPay::Merchant::Credential($merchantDB);
  $credential->loadByCredentialIdentifier($data->{'credentialIdentifier'});
  if (!$credential->getCredentialID()) {
    push (@errorMsg, 'Invalid credential identifier.');
  }

  my $protocolID;
  my $protocol = new PlugNPay::Merchant::HostConnection::Protocol();
  if ($data->{'protocol'} =~ /^\d+$/) {
    $protocol->loadProtocol($data->{'protocol'});
    $protocolID = $protocol->getProtocolID();
    if (!$protocolID) {
      push (@errorMsg, 'Invalid protocol ID.');
    }
  } else {
    $data->{'protocol'} =~ s/[^a-zA-Z]//g;
    $protocol->loadProtocolID($data->{'protocol'});
    $protocolID = $protocol->getProtocolID();
    if (!$protocolID) {
      push (@errorMsg, 'Invalid protocol.');
    }
  }

  if ($data->{'port'} !~ /^\d+$/ || $data->{'port'} > 65535 || $data->{'port'} < 0) {
    push (@errorMsg, 'Invalid port value.');
  }

  if (!$data->{'path'}) {
    push (@errorMsg, 'Invalid path.');
  }

  if (@errorMsg == 0) {
    my $params = [
      $merchantDB,
      $self->_generateHostConnectionIdentifier($merchantDB),
      $data->{'description'},
      $host->getHostID(),
      $data->{'port'}, 
      $protocolID, 
      $credential->getCredentialID(),
      $data->{'path'}
    ];

    eval {
      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/INSERT INTO merchant_host_connection 
          ( merchant_id,
            identifier,
            description,
            host_id,
            port,
            protocol_id,
            credential_id,
            path )
          VALUES(?,?,?,?,?,?,?,?)/, $params);
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'      => $@,
        'function'   => 'saveMerchantHostConnection',
        'merchantDB' => $merchantDB
      });

      push (@errorMsg, 'Error while attempting to save host connection.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

sub updateMerchantHostConnection {
  my $self = shift;
  my $updateData = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $merchantDB = $self->{'merchantDB'};
  if (!$merchantDB->isMaster()) {
    $status->setFalse();
    $status->setError('Access denied.');
    return $status;
  }

  my ($hostID, $credentialID, $protocolID, $port, $path, $description);
  if (exists $updateData->{'hostIdentifier'}) {
    my $host = new PlugNPay::Merchant::Host($merchantDB);
    $host->loadByHostIdentifier($updateData->{'hostIdentifier'});
    $hostID = $host->getHostID();
    if (!$hostID) {
      push (@errorMsg, 'Invalid host identifier.');
    }
  } else {
    $hostID = $self->{'hostID'};
  }

  if (exists $updateData->{'credentialIdentifier'}) {
    my $credential = new PlugNPay::Merchant::Credential($merchantDB);
    $credential->loadByCredentialIdentifier($updateData->{'credentialIdentifier'});
    $credentialID = $credential->getCredentialID();
    if (!$credentialID) {
      push (@errorMsg, 'Invalid credential Identifier.');
    }
  } else {
    $credentialID = $self->{'credentialID'};
  }

  if (exists $updateData->{'protocol'}) {
    my $protocol = new PlugNPay::Merchant::HostConnection::Protocol();
    if ($updateData->{'protocol'} =~ /^\d+$/) {
      $protocol->loadProtocol($updateData->{'protocol'});
      $protocolID = $protocol->getProtocolID();
      if (!$protocolID) {
        push (@errorMsg, 'Invalid protocol ID.');
      }
    } else {
     $updateData->{'protocol'} =~ s/[^a-zA-Z]//g;
     $protocol->loadProtocolID($updateData->{'protocol'});
      $protocolID = $protocol->getProtocolID();
      if (!$protocolID) {
        push (@errorMsg, 'Invalid protocol.');
      }
    }
  } else {
    $protocolID = $self->{'protocolID'};
  }

  if (exists $updateData->{'port'}) {
    if ($updateData->{'port'} !~ /^\d+$/ || $updateData->{'port'} > 65535 || $updateData->{'port'} < 0) {
      push (@errorMsg, 'Invalid port value.');
    }

    $port = $updateData->{'port'};
  } else {
    $port = $self->{'port'};
  }

  if (exists $updateData->{'path'}) {
    if (!$updateData->{'path'}) {
      push (@errorMsg, 'Invalid path.');
    }

    $path = $updateData->{'path'};
  } else {
    $path = $self->{'path'};
  }

  if (exists $updateData->{'description'}) {
    $description = $updateData->{'description'};
  } else {
    $description = $self->{'description'};
  }

  if (@errorMsg == 0) {
    eval {
      my $params = [
        $description, 
        $hostID, 
        $port, 
        $protocolID, 
        $credentialID, 
        $path, 
        $self->{'hostConnectionID'}
      ];

      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/UPDATE merchant_host_connection
          SET description = ?, 
              host_id = ?, 
              port = ?,
              protocol_id = ?,
              credential_id = ?,
              path = ?
          WHERE id = ?/, $params);
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'      => $@,
        'function'   => 'updateMerchantHostConnection',
        'merchantDB' => $merchantDB
      });

      push (@errorMsg, 'Error while attempting to update host connection.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

sub deleteMerchantHostConnection {
  my $self = shift;
  my $hostConnectionID = shift || $self->{'hostConnectionID'};

  my $status = new PlugNPay::Util::Status(1);

  my $merchantDB = $self->{'merchantDB'};
  if (!$merchantDB->isMaster()) {
    $status->setFalse();
    $status->setError('Access denied.');
    return $status;
  }

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE
        FROM merchant_host_connection
        WHERE id = ?/, [$hostConnectionID]);
  };

  if ($@) {
    $self->_log({
      'function'   => 'deleteMerchantHostConnection',
      'error'      => $@,
      'merchantDB' => $self->{'merchantDB'}
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete host connection.');
  }

  return $status;
}

sub _generateHostConnectionIdentifier {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $uniqueID = new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);
  if ($self->doesUniqueHostConnectionIDExist($uniqueID, $merchantDB)) {
    return $self->_generateHostConnectionIdentifier($merchantDB);
  }

  return $uniqueID;
}

sub doesUniqueHostConnectionIDExist {
  my $self = shift;
  my $hostConnectionID = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM merchant_host_connection
        WHERE identifier = ?
        AND merchant_id = ?/, [$hostConnectionID, $merchantDB], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'function'   => 'doesUniqueHostConnectionIDExist',
      'merchantDB' => $merchantDB
    });
  }

  return $exists;
}

sub loadByHostConnectionIdentifier {
  my $self = shift;
  my $hostConnectionIdentifier = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               merchant_id,
               identifier,
               description,
               host_id,
               port,
               protocol_id,
               credential_id,
               path
       FROM merchant_host_connection
       WHERE identifier = ?
       AND merchant_id = ?/, [$hostConnectionIdentifier, $merchantDB], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setHostConnectionDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'function'   => 'loadByHostConnectionIdentifier',
      'merchantDB' => $merchantDB
    });
  }
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getMerchantHostConnectionListSize {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM merchant_host_connection
        WHERE merchant_id = ?/, [$merchantDB], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'function'   => 'getMerchantHostConnectionListSize',
      'merchantDB' => $merchantDB
    });
  }

  return $count;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_host_connection' });
  $logger->log($logInfo);
}

1;
