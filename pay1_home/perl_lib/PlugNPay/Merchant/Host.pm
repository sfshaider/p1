package PlugNPay::Merchant::Host;

use strict;
use PlugNPay::Util::IP;
use PlugNPay::Merchant;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Merchant::Proxy;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::RandomString;

######################################
# Module: Merchant::Host
# ------------------------------------
# Description:
#   Merchant's server address info.

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

sub setHostID {
  my $self = shift;
  my $hostID = shift;
  $self->{'hostID'} = $hostID;
}

sub getHostID {
  my $self = shift;
  return $self->{'hostID'};
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

sub setFQDN {
  my $self = shift;
  my $FQDN = shift;
  $self->{'fqdn'} = $FQDN;
}

sub getFQDN {
  my $self = shift;
  return $self->{'fqdn'};
}

sub setIPAddress {
  my $self = shift;
  my $ipAddress = shift;
  $self->{'ipAddress'} = $ipAddress;
}

sub getIPAddress {
  my $self = shift;
  return $self->{'ipAddress'};
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

sub loadMerchantHosts {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $hosts = [];

  my @values = ();
  my $sql = q/SELECT id,
                     identifier,
                     merchant_id,
                     fqdn,
                     ipaddress,
                     description
              FROM merchant_host
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
        my $host =  new PlugNPay::Merchant::Host();
        $host->_setHostDataFromRow($row);
        push (@{$hosts}, $host);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'function'   => 'loadMerchantHosts',
      'merchantDB' => $merchantDB
    });
  }

  return $hosts;
}

sub loadMerchantHost {
  my $self = shift;
  my $hostID = shift || $self->{'hostID'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               merchant_id,
               fqdn,
               ipaddress,
               description
        FROM merchant_host
        WHERE id = ?/, [$hostID], {})->{'result'};
    if (@{$rows} > 0) {
      my $row = $rows->[0];
      $self->_setHostDataFromRow($row);
    }
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'function'   => 'loadMerchantHost',
      'merchantDB' => $self->{'merchantDB'}
    });
  }
}

sub _setHostDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'hostID'}      = $row->{'id'};
  $self->{'fqdn'}        = $row->{'fqdn'};
  $self->{'ipAddress'}   = $row->{'ipaddress'};
  $self->{'identifier'}  = $row->{'identifier'};
  $self->{'merchantID'}  = $row->{'merchant_id'};
  $self->{'description'} = $row->{'description'};
}

################################
# Subroutine: saveMerchantHost
# ------------------------------
# Description:
#   Saves server information to
#   a merchant's records.
sub saveMerchantHost {
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

  if (!$data->{'fqdn'}) {
    push (@errorMsg, 'Domain name cannot be blank.');
  }

  if (!$data->{'ipAddress'}) {
    push (@errorMsg, 'IP Address cannot be blank.');
  } else {
    my $IP = new PlugNPay::Util::IP();
    if (!$IP->validateIPv4Address($data->{'ipAddress'})) {
      push (@errorMsg, 'Unable to update merchant host. Invalid IP Address.');
    }
  }

  if (@errorMsg == 0) {
    my $params = [
      $merchantDB,
      $self->_generateHostIdentifier($merchantDB),
      $data->{'fqdn'}, 
      $data->{'ipAddress'},
      $data->{'description'}
    ];

    eval {
      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/INSERT INTO merchant_host 
          ( merchant_id,
            identifier,
            fqdn, 
            ipaddress, 
            description )
          VALUES (?,?,?,?,?)/, $params);
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'function'   => 'saveMerchantHost',
        'error'      => $@,
        'merchantDB' => $self->{'merchantDB'}
      });

      push (@errorMsg, 'Error while attempting to save host.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

##################################
# Subroutine: updateMerchantHost
# --------------------------------
# Description:
#   Updates server info from a
#   merchant's records.
sub updateMerchantHost {
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

  my ($fqdn, $ipAddress, $description);
  if (exists $updateData->{'fqdn'}) {
    if (!$updateData->{'fqdn'}) {
      push (@errorMsg, 'Domain name cannot be blank.');
    }

    $fqdn = $updateData->{'fqdn'};
  } else {
    $fqdn = $self->{'fqdn'};
  }

  if (exists $updateData->{'ipAddress'}) {
    if (!$updateData->{'ipAddress'}) {
      push (@errorMsg, 'IP Address cannot be blank.');
    } else {
      my $IP = new PlugNPay::Util::IP();
      if (!$IP->validateIPv4Address($updateData->{'ipAddress'})) {
        push (@errorMsg, 'Invalid IP Address.');
      }
    }

    $ipAddress = $updateData->{'ipAddress'};
  } else {
    $ipAddress = $self->{'ipAddress'};
  }

  if (exists $updateData->{'description'}) {
    $description = $updateData->{'description'};
  } else {
    $description = $self->{'description'};
  }

  if (@errorMsg == 0) {
    my $params = [
      $fqdn,
      $ipAddress, 
      $description,
      $self->{'hostID'}
    ];

    eval {
      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/UPDATE merchant_host
          SET fqdn = ?, 
              ipaddress = ?, 
              description = ?
          WHERE id = ?/, $params);
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'      => $@,
        'function'   => 'updateMerchantHost',
        'merchantDB' => $merchantDB
      });

      push (@errorMsg, 'Error while attempting to update host.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

###################################
# Subroutine: deleteMerchantHost
# ---------------------------------
# Description:
#   Deletes server information from
#   merchant's records.
sub deleteMerchantHost {
  my $self = shift;
  my $hostID = shift || $self->{'hostID'};

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
        FROM merchant_host
        WHERE id = ?/, [$hostID]);
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'hostID'     => $hostID,
      'function'   => 'deleteMerchantHost',
      'merchantDB' => $self->{'merchantDB'}
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete host.');
  }

  return $status;
}

sub _generateHostIdentifier {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $uniqueID = new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);
  if ($self->doesUniqueHostIDExist($uniqueID, $merchantDB)) {
    return $self->_generateHostIdentifier($merchantDB);
  }

  return $uniqueID;
}

sub doesUniqueHostIDExist {
  my $self = shift;
  my $hostID = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM merchant_host
        WHERE identifier = ?
        AND merchant_id = ?/, [$hostID, $merchantDB], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'hostID'     => $hostID,
      'function'   => 'doesUniqueHostIDExist',
      'merchantDB' => $merchantDB
    });
  }

  return $exists;
}

sub loadByHostIdentifier {
  my $self = shift;
  my $hostIdentifier = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               merchant_id,
               fqdn,
               ipaddress,
               description
        FROM merchant_host
        WHERE identifier = ?
        AND merchant_id = ?/, [$hostIdentifier, $merchantDB], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setHostDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'              => $@,
      'function'           => 'loadByHostIdentifier',
      'merchantDB'         => $merchantDB,
      'hostIdentifier'     => $hostIdentifier
    });
  }
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getMerchantHostListSize {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM merchant_host
        WHERE merchant_id = ?/, [$merchantDB], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({ 
      'error'              => $@,
      'function'           => 'getMerchantHostListSize',
      'merchantDB'         => $merchantDB
    });
  }

  return $count;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_host' });
  $logger->log($logInfo);
}

1;
