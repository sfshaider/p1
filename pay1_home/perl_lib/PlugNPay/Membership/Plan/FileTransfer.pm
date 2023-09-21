package PlugNPay::Membership::Plan::FileTransfer;

use strict;
use PlugNPay::Merchant;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Merchant::Proxy;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::RandomString;
use PlugNPay::Merchant::HostConnection;

##########################################
# Module: Plan::FileTransfer
# ----------------------------------------
# Description:
#   File transfers are for the purpose of
#   password management. The settings 
#   contain information about how to 
#   activate the remote server and where
#   to transfer the htpasswd file.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

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

sub setFileTransferID {
  my $self = shift;
  my $fileTransferID = shift;
  $self->{'fileTransferID'} = $fileTransferID;
}

sub getFileTransferID {
  my $self = shift;
  return $self->{'fileTransferID'};
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

sub setDescription {
  my $self = shift;
  my $description = shift;
  $self->{'description'} = $description
}

sub getDescription {
  my $self = shift;
  return $self->{'description'};
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

sub setRenamePreviousSuffix {
  my $self = shift;
  my $renamePrevSuffix = shift;
  $self->{'renamePrevSuffix'} = $renamePrevSuffix;
}

sub getRenamePreviousSuffix {
  my $self = shift;
  return $self->{'renamePrevSuffix'};
}

sub setActivationURL {
  my $self = shift;
  my $activationURL = shift;
  $self->{'activationURL'} = $activationURL
}

sub getActivationURL {
  my $self = shift;
  return $self->{'activationURL'};
}

################################################
# Subroutine: loadMerchantFileTransferSettings
# ----------------------------------------------
# Description:
#   Loads file transfer settings for a merchant.
sub loadMerchantFileTransferSettings {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $fileTransferSettings = [];

  my @values = ();
  my $sql = q/SELECT id,
                     identifier,
                     merchant_id,
                     description,
                     host_connection_id,
                     rename_previous_suffix,
                     activation_url
              FROM recurring1_file_transfer
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
        my $fileTransfer = new PlugNPay::Membership::Plan::FileTransfer($self->{'merchantID'});
        $fileTransfer->_setFileTransferDataFromRow($row);
        push (@{$fileTransferSettings}, $fileTransfer);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadMerchantFileTransferSettings'
    });
  }

  return $fileTransferSettings;
}

########################################
# Subroutine: loadFileTransferSettings
# --------------------------------------
# Description:
#   Given an id, loads the file transfer
#   settings.
sub loadFileTransferSettings {
  my $self = shift;
  my $fileTransferID = shift || $self->{'fileTransferID'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               merchant_id,
               description,
               host_connection_id,
               rename_previous_suffix,
               activation_url
        FROM recurring1_file_transfer
        WHERE id = ?/, [$fileTransferID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setFileTransferDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadFileTransferSettings'
    });
  }
}

###############################################
# Subroutine: loadByFileTransferIdentifier
# ---------------------------------------------
# Description:
#   Loads the file transfer data in the file
#   transfer settings table from the unique 
#   ID assigned.
sub loadByFileTransferIdentifier {
  my $self = shift;
  my $identifier = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               merchant_id,
               description,
               host_connection_id,
               rename_previous_suffix,
               activation_url
        FROM recurring1_file_transfer
        WHERE identifier = ?
        AND merchant_id = ?/, [$identifier, $merchantDB], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setFileTransferDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    'error'    => $@,
    'function' => 'loadByFileTransferIdentifier'
  }
}

sub _setFileTransferDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'fileTransferID'}   = $row->{'id'};
  $self->{'identifier'}       = $row->{'identifier'};
  $self->{'merchantID'}       = $row->{'merchant_id'};
  $self->{'description'}      = $row->{'description'};
  $self->{'activationURL'}    = $row->{'activation_url'};
  $self->{'hostConnectionID'} = $row->{'host_connection_id'};
  $self->{'renamePrevSuffix'} = $row->{'rename_previous_suffix'};
}

##########################################
# Subroutine: saveFileTransferSettings
# ----------------------------------------
# Description:
#   Saves file transfer settings for a 
#   merchant.
sub saveFileTransferSettings {
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

  my $hostConnection = new PlugNPay::Merchant::HostConnection($merchantDB);
  $hostConnection->loadByHostConnectionIdentifier($data->{'hostConnectionIdentifier'});
  if (!$hostConnection->getHostConnectionID()) {
    push (@errorMsg, 'Invalid host connection identifier.');
  }

  if (!$data->{'activationURL'}) {
    push (@errorMsg, 'Activation url cannot be blank.');
  } elsif (!$self->isActivationURLUnique($data->{'activationURL'})) {
    push (@errorMsg, 'Activation url exists in transfer settings.');
  }

  if (@errorMsg == 0) {
    eval {
      my $params = [
        $merchantDB,
        $self->_generateUniqueFileTransferID(),
        $data->{'description'},
        $hostConnection->getHostConnectionID(),
        $data->{'renamePreviousSuffix'},
        $data->{'activationURL'}
      ];

      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/INSERT INTO recurring1_file_transfer
          ( merchant_id,
            identifier,
            description,
            host_connection_id,
            rename_previous_suffix,
            activation_url )
          VALUES (?,?,?,?,?,?)/, $params);
    };
  }
 
  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'      => $@,
        'function'   => 'saveFileTransferSettings',
        'merchantDB' => $self->{'merchantDB'}
      });

      push (@errorMsg, 'Error while attempting to save file transfer settings.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

##########################################
# Subroutine: updateFileTransferSettings
# ----------------------------------------
# Description:
#   Updates an existing file transfer 
#   settings row.
sub updateFileTransferSettings {
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

  my ($description, $prevSuffix, $hostConnectionID, $activationURL);
  if (exists $updateData->{'description'}) {
    $description = $updateData->{'description'};
  } else {
    $description = $self->{'description'};
  }

  if (exists $updateData->{'renamePreviousSuffix'}) {
    $prevSuffix = $updateData->{'renamePreviousSuffix'};
  } else {
    $prevSuffix = $self->{'renamePrevSuffix'};
  }

  if (exists $updateData->{'hostConnectionIdentifier'}) {
    my $hostConnection = new PlugNPay::Merchant::HostConnection($merchantDB);
    $hostConnection->loadByHostConnectionIdentifier($updateData->{'hostConnectionIdentifier'});
    $hostConnectionID = $hostConnection->getHostConnectionID();
    if (!$hostConnectionID) {
      push (@errorMsg, 'Invalid host connection identifier.');
    }
  } else {
    $hostConnectionID = $self->{'hostConnectionID'};
  }

  if (exists $updateData->{'activationURL'}) {
    if (!$updateData->{'activationURL'}) {
      push (@errorMsg, 'Activation url cannot be blank.');
    } elsif (!$self->isActivationURLUnique($updateData->{'activationURL'})) {
      push (@errorMsg, 'Activation url exists in transfer settings.');
    }

    $activationURL = $updateData->{'activationURL'};
  } else {
    $activationURL = $self->{'activationURL'};
  }

  if (@errorMsg == 0) {
    eval {
      my $params = [
        $description, 
        $hostConnectionID, 
        $prevSuffix, 
        $activationURL, 
        $self->{'fileTransferID'}
      ];

      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/UPDATE recurring1_file_transfer
          SET description = ?,
              host_connection_id = ?,
              rename_previous_suffix = ?,
              activation_url = ?
          WHERE id = ?/, $params);
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'      => $@,
        'function'   => 'updateFileTransferSettings',
        'merchantDB' => $self->{'merchantDB'}
      });

      push (@errorMsg, 'Error while attempting to update file transfer settings.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }
  
  return $status;
}

###########################################
# Subroutine: deleteFileTransferSettings
# -----------------------------------------
# Description:
#   Deletes the file transfer setting row
#   from the merchant's records.
sub deleteFileTransferSettings {
  my $self = shift;
  my $fileTransferID = shift || $self->{'fileTransferID'};

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
      q/DELETE FROM recurring1_file_transfer
        WHERE id = ?/, [$fileTransferID]);
  };

  if ($@) {
    $self->_log({
      'error'          => $@,
      'function'       => 'deleteFileTransferSettings',
      'fileTransferID' => $fileTransferID,
      'merchantDB'     => $self->{'merchantDB'}
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete file transfer settings.');
  }

  return $status;
}

sub _generateUniqueFileTransferID {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $uniqueID = new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);
  if ($self->doesUniqueFileTransferIDExist($uniqueID, $merchantDB)) {
    return $self->_generateUniqueFileTransferID($merchantDB);
  }

  return $uniqueID;
}

sub isActivationURLUnique {
  my $self = shift;
  my $activationURL = shift;

  my $exists = 0;
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM recurring1_file_transfer
        WHERE activation_url = ?/, [$activationURL], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
     $self->_log({
      'error'    => $@,
      'function' => 'isActivationURLUnique'
    });
  }

  return $exists;
}

sub doesUniqueFileTransferIDExist {
  my $self = shift;
  my $uniqueID = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM recurring1_file_transfer
        WHERE identifier = ?
        AND merchant_id = ?/, [$uniqueID, $merchantDB], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'doesUniqueFileTransferIDExist'
    });
  }
  
  return $exists;
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getFileTransferListSize {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM recurring1_file_transfer
        WHERE merchant_id = ?/, [$merchantDB], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'getFileTransferListSize'
    });
  }

  return $count;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_plan_filetransfer' });
  $logger->log($logInfo);
}

1;
