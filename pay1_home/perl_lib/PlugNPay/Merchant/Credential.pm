package PlugNPay::Merchant::Credential;

use strict;
use PlugNPay::Token;
use PlugNPay::Merchant;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Merchant::Proxy;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::RandomString;

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

sub setCredentialID {
  my $self = shift;
  my $credentialID = shift;
  $self->{'credentialID'} = $credentialID;
}

sub getCredentialID {
  my $self = shift;
  return $self->{'credentialID'};
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

sub setIdentifier {
  my $self = shift;
  my $identifier = shift;
  $self->{'identifier'} = $identifier;
}

sub getIdentifier {
  my $self = shift;
  return $self->{'identifier'};
}

sub setUsername {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return $self->{'username'};
}

sub setPasswordToken {
  my $self = shift;
  my $passwordToken = shift;

  my $token = new PlugNPay::Token();
  $token->fromBinary($passwordToken);
  $self->{'passwordToken'} = $token->inHex();
}

sub getPasswordToken {
  my $self = shift;
  return $self->{'passwordToken'};
}

sub setCertificate {
  my $self = shift;
  my $certificate = shift;
  $self->{'certificate'} = $certificate;
}

sub getCertificate {
  my $self = shift;
  return $self->{'certificate'};
}

sub loadMerchantCredentials {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $merchantCredentials = [];

  my @values = ();
  my $sql = q/SELECT id,
                     merchant_id,
                     identifier,
                     username,
                     password_token,
                     certificate
              FROM merchant_credential
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
        my $credential = new PlugNPay::Merchant::Credential();
        $credential->_setCredentialDataFromRow($row);
        push (@{$merchantCredentials}, $credential);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'function'   => 'loadMerchantCredentials',
      'merchantDB' => $merchantDB
    });
  }

  return $merchantCredentials;
}

sub loadMerchantCredential {
  my $self = shift;
  my $credentialID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               merchant_id,
               identifier,
               username,
               password_token,
               certificate
        FROM merchant_credential
        WHERE id = ?/, [$credentialID], {})->{'result'};
    if (@{$rows} > 0) {
      my $row = $rows->[0];
      $self->_setCredentialDataFromRow($row);
    }
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'function'   => 'loadMerchantCredential',
      'credentialID' => $credentialID
    });
  }
}

sub _setCredentialDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'credentialID'} = $row->{'id'};
  $self->{'merchantID'}   = $row->{'merchant_id'};
  $self->{'identifier'}   = $row->{'identifier'};
  $self->{'username'}     = $row->{'username'};
  $self->{'certificate'}  = $row->{'certificate'};
  $self->setPasswordToken($row->{'password_token'});
}

sub saveMerchantCredential {
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

  if (!$data->{'username'}) {
    push (@errorMsg, 'Username cannot be blank.');
  }

  if (!$data->{'password'}) {
    push (@errorMsg, 'Password cannot be blank.');
  }

  if (@errorMsg == 0) {
    my $token = new PlugNPay::Token();
    my $hexPassword = $token->getToken($data->{'password'}, 'CREDENTIAL');
    $token->fromHex($hexPassword);

    eval {
      my $params = [
        $merchantDB, 
        $self->_generateCredentialIdentifier($merchantDB),
        $data->{'username'}, 
        $token->inBinary(), 
        $data->{'certificate'}
      ];

      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/INSERT INTO merchant_credential 
          ( merchant_id,
            identifier, 
            username, 
            password_token, 
            certificate )
          VALUES(?,?,?,?,?)/, $params);
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'      => $@,
        'function'   => 'saveMerchantCredential',
        'merchantDB' => $self->{'merchantDB'}
      });

      push (@errorMsg, 'Error while attempting to save credentials.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

sub updateMerchantCredential {
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

  my ($username, $password, $certificate);

  if (exists $updateData->{'username'}) {
    if (!$updateData->{'username'}) {
      push (@errorMsg, 'Username cannot be blank.');
    }

    $username = $updateData->{'username'};
  } else {
    $username = $self->{'username'};
  }

 
  if (exists $updateData->{'password'}) {
    if (!$updateData->{'password'}) {
      push (@errorMsg, 'Password cannot be blank.');
    } 

    $password = $updateData->{'password'};
  } else {
    $password = $self->{'passwordToken'};
  }


  if (exists $updateData->{'certificate'}) {
    $certificate = $updateData->{'certificate'};
  } else {
    $certificate = $self->{'certificate'};
  }

  if (@errorMsg == 0) {
    my $token = new PlugNPay::Token();
    my $passwordToken = $token->getToken($password, 'CREDENTIAL');
    $token->fromHex($passwordToken);

    eval {
      my $params = [
        $username,
        $token->inBinary(), 
        $certificate, 
        $self->{'credentialID'}
      ];

      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/UPDATE merchant_credential
          SET username = ?, 
              password_token = ?, 
              certificate = ?
          WHERE id = ?/, $params);
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'      => $@,
        'function'   => 'updateMerchantCredential',
        'merchantDB' => $self->{'merchantDB'}
      });

      push (@errorMsg, 'Error while attempting to update credentials.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

sub deleteMerchantCredential {
  my $self = shift;
  my $credentialID = shift || $self->{'credentialID'};

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
        FROM merchant_credential
        WHERE id = ?/, [$credentialID]
    );
  };

  if ($@) {
    $self->_log({
      'error'        => $@,
      'function'     => 'deleteMerchantCredential',
      'merchantDB'   => $self->{'merchantDB'},
      'credentialID' => $credentialID
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete credentials.');
  }

  return $status;
}

sub doesUniqueCredentialIDExist {
  my $self = shift;
  my $credentialID = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $exists = 0;
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM merchant_credential
        WHERE identifier = ?
        AND merchant_id = ?/, [$credentialID, $merchantDB], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'                => $@,
      'function'             => 'doesUniqueCredentialIDExist',
      'merchantDB'           => $merchantDB,
      'credentialIdentifier' => $credentialID
    });
  }

  return $exists;
}

sub _generateCredentialIdentifier {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $uniqueID = new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);
  if ($self->doesUniqueCredentialIDExist($uniqueID, $merchantDB)) {
    return $self->_generateCredentialIdentifier($merchantDB);
  }

  return $uniqueID;
}

sub loadByCredentialIdentifier {
  my $self = shift;
  my $credentialIdentifier = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust', 
      q/SELECT id,
               merchant_id,
               identifier,
               username,
               password_token,
               certificate
        FROM merchant_credential
        WHERE identifier = ?
        AND merchant_id = ?/, [$credentialIdentifier, $merchantDB], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setCredentialDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'                => $@,
      'function'             => 'loadByCredentialIdentifier',
      'merchantDB'           => $merchantDB,
      'credentialIdentifier' => $credentialIdentifier
    });
  }
}

# table helpers

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getMerchantCredentialListSize {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $count = 0;
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM merchant_credential
        WHERE merchant_id = ?/, [$merchantDB], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'function'   => 'getMerchantCredentialListSize',
      'merchantDB' => $merchantDB
    });
  }

  return $count;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_credential' });
  $logger->log($logInfo);
}

1;
