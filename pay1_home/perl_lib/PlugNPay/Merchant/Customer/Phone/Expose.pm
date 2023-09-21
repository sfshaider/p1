package PlugNPay::Merchant::Customer::Phone::Expose;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::RandomString;
use PlugNPay::Merchant::Customer::Link;
use PlugNPay::Merchant::Customer::Phone;
use PlugNPay::Merchant::Customer::Phone::Type;

############################################
# Module: Merchant::Customer::Phone::Expose
# ------------------------------------------
# Description:
#   Link between a merchant's customer and
#   a customer phone.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub setLinkID {
  my $self = shift;
  my $linkID = shift;
  $self->{'linkID'} = $linkID;
}

sub getLinkID {
  my $self = shift;
  return $self->{'linkID'};
}

sub setMerchantCustomerLinkID {
  my $self = shift;
  my $merchantCustomerLinkID = shift;
  $self->{'merchantCustomerLinkID'} = $merchantCustomerLinkID;
}

sub getMerchantCustomerLinkID {
  my $self = shift;
  return $self->{'merchantCustomerLinkID'};
}

sub setPhoneID {
  my $self = shift;
  my $phoneID = shift;
  $self->{'phoneID'} = $phoneID;
}

sub getPhoneID {
  my $self = shift;
  return $self->{'phoneID'};
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

sub loadExposedPhones {
  my $self = shift;
  my $merchantCustomerLinkID = shift || $self->getMerchantCustomerLinkID();

  my $exposedPhones = [];

  my @values = ();
  my $sql = q/SELECT id,
                     identifier,
                     customer_phone_id,
                     merchant_customer_link_id
              FROM merchant_customer_link_expose_phone
              WHERE merchant_customer_link_id = ?
              ORDER BY id ASC/;
  push (@values, $merchantCustomerLinkID);

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
        my $exposedPhone = new PlugNPay::Merchant::Customer::Phone::Expose();
        $exposedPhone->_setLinkDataFromRow($row);
        push (@{$exposedPhones}, $exposedPhone);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadExposedPhones'
    });
  }

  return $exposedPhones;
}

sub loadExposedPhone {
  my $self = shift;
  my $linkID = shift || $self->{'linkID'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               customer_phone_id,
               merchant_customer_link_id
        FROM merchant_customer_link_expose_phone
        WHERE id = ?/, [$linkID], {})->{'result'};
    if (@{$rows} > 0) {
      my $row = $rows->[0];
      $self->_setLinkDataFromRow($row);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadExposedPhone'
    });
  }
}

sub loadByLinkIdentifier {
  my $self = shift;
  my $identifier = shift;
  my $merchantCustomerLinkID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               customer_phone_id,
               merchant_customer_link_id
        FROM merchant_customer_link_expose_phone
        WHERE identifier = ?
        AND merchant_customer_link_id = ?/, [$identifier, $merchantCustomerLinkID], {})->{'result'};
    if (@{$rows} > 0) {
      my $row = $rows->[0];
      $self->_setLinkDataFromRow($row);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadByLinkIdentifier'
    });
  }
}

sub _setLinkDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'linkID'}                 = $row->{'id'};
  $self->{'identifier'}             = $row->{'identifier'};
  $self->{'phoneID'}                = $row->{'customer_phone_id'};
  $self->{'merchantCustomerLinkID'} = $row->{'merchant_customer_link_id'};
}

sub saveExposedPhone {
  my $self = shift;
  my $phoneData = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};
  my $options = shift || {};

  my $dbs = new PlugNPay::DBConnection();
  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  eval {
    $dbs->begin('merchant_cust');

    # load merchant customer object
    my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
    $merchantCustomer->loadMerchantCustomer($merchantCustomerLinkID);

    # save phone data
    my $phone = new PlugNPay::Merchant::Customer::Phone();
    my $savePhoneStatus = $phone->savePhone($merchantCustomer->getCustomerID(), $phoneData);
    if (!$savePhoneStatus) {
      push (@errorMsg, $savePhoneStatus->getError());
      return;  # no reason to continue if saving the phone data failed
    }

    # get phone id
    my $phoneID = $phone->getPhoneID();

    # does phone data exist
    if ($self->doesExposedPhoneExist($phoneID, $merchantCustomerLinkID)) {
      push (@errorMsg, 'Customer already has saved phone data.');
    }

    if (@errorMsg == 0) {
      my $identifier = $self->_generateUniquePhoneID($merchantCustomerLinkID);
      my $params = [
        $merchantCustomerLinkID,
        $phoneID,
        $identifier
      ];

      # save exposed phone
      my $sth = $dbs->executeOrDie('merchant_cust',
        q/INSERT INTO merchant_customer_link_expose_phone
          ( merchant_customer_link_id,
            customer_phone_id,
            identifier )
          VALUES (?,?,?)/, $params)->{'sth'};
      my $phoneLinkID = $sth->{'mysql_insertid'};

      # if make default is passed, then it will set phone id
      # in the merchant customer link table
      if ($options->{'makeDefault'}) {
        $phone->loadPhone($phoneID);

        my $type = new PlugNPay::Merchant::Customer::Phone::Type();
        $type->loadType($phone->getGeneralTypeID());

        if (uc ($type->getType()) eq 'FAX') {
          my $updateStatus = $merchantCustomer->updateMerchantCustomer({ 'defaultFaxID' => $identifier });
          if (!$updateStatus) {
            push (@errorMsg, $updateStatus->getError());
          }
        } else {
          my $updateStatus = $merchantCustomer->updateMerchantCustomer({ 'defaultPhoneID' => $identifier });
          if (!$updateStatus) {
            push (@errorMsg, 'Failed to save phone.');
          }
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');

    if ($@) {
      $self->_log({
        'error'                  => $@,
        'function'               => 'saveExposedPhone',
        'merchantCustomerLinkID' => $merchantCustomerLinkID
      });

      push (@errorMsg, 'Error while attempting to save customer phone.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

sub updateExposedPhone {
  my $self = shift;
  my $updatePhoneData = shift;
  my $linkID = shift || $self->{'linkID'};

  my $dbs = new PlugNPay::DBConnection();
  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  eval {
    $dbs->begin('merchant_cust');

    # if the phone id is not loaded
    if (!$self->{'phoneID'}) {
      $self->loadExposedPhone($linkID);
      if (!$self->{'phoneID'}) {
        push (@errorMsg, 'Unable to update phone data.');
        return; # the caller did not load the exposed data first, so return.
      }
    }

    # load merchant customer object
    my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
    $merchantCustomer->loadMerchantCustomer($self->{'merchantCustomerLinkID'});

    # load current phone data
    my $phone = new PlugNPay::Merchant::Customer::Phone();
    $phone->loadPhone($self->{'phoneID'});

    # update the phone data
    my $updatePhoneStatus = $phone->updatePhone($updatePhoneData);
    if (!$updatePhoneStatus) {
      push (@errorMsg, $updatePhoneStatus->getError());
      return; # return if failed to update.
    }

    # updated phone ID
    my $updatedPhoneID = $phone->getPhoneID();

    # if the phone id is not different, update is done.
    if ($updatedPhoneID != $self->{'phoneID'}) {
      # does the phone id exist in the merchant's records
      if ($self->doesExposedPhoneExist($updatedPhoneID, $self->{'merchantCustomerLinkID'})) {
        push (@errorMsg, 'Customer already has saved phone information.');
      }

      if (@errorMsg == 0) {
        # update the exposed phone record
        $dbs->executeOrDie('merchant_cust',
          q/UPDATE merchant_customer_link_expose_phone
            SET customer_phone_id = ?
            WHERE id = ?/, [$updatedPhoneID, $linkID]);
        # clean up
        if (!$self->isPhoneUsed($self->{'phoneID'})) {
          $phone->deletePhone($self->{'phoneID'});
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');

    if ($@) {
      $self->_log({
        'error'    => $@,
        'linkID'   => $linkID,
        'function' => 'updateExposedPhone'
      });

      push (@errorMsg, 'Error while attempting to update customer phone.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

sub deleteExposedPhone {
  my $self = shift;
  my $linkID = shift || $self->{'linkID'};

  my $status = new PlugNPay::Util::Status(1);

  eval {
    if (!$self->{'phoneID'}) {
      $self->loadExposedPhone($linkID); # need phone ID for cleanup
    }

    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM merchant_customer_link_expose_phone
        WHERE id = ?/, [$linkID]);

    # clean up
    eval {
      if (!$self->isPhoneUsed($self->{'phoneID'})) {
        my $phone = new PlugNPay::Merchant::Customer::Phone();
        $phone->deletePhone($self->{'phoneID'});
      }
    };
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'linkID'   => $linkID,
      'function' => 'deleteExposedPhone'
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete customer phone.');
  }

  return $status;
}

sub doesExposedPhoneExist {
  my $self = shift;
  my $phoneID = shift;
  my $merchantCustomerLinkID = shift;

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM merchant_customer_link_expose_phone
        WHERE customer_phone_id = ?
        AND merchant_customer_link_id = ?/, [$phoneID, $merchantCustomerLinkID], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'doesExposedPhoneExist'
    });
  }

  return $exists;
}

sub isPhoneUsed {
  my $self = shift;
  my $phoneID = shift;

  my $inUse = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `inUse`
        FROM merchant_customer_link_expose_phone
        WHERE customer_phone_id = ?/, [$phoneID], {})->{'result'};
    $inUse = $rows->[0]{'inUse'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'isPhoneUsed'
    });
  }

  return $inUse;
}

sub _generateUniquePhoneID {
  my $self = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};

  my $uniqueID = new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);
  if ($self->doesUniquePhoneIDExist($uniqueID, $merchantCustomerLinkID)) {
    return $self->_generateUniquePhoneID($merchantCustomerLinkID);
  }

  return $uniqueID;
}

sub doesUniquePhoneIDExist {
  my $self = shift;
  my $uniqueID = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM merchant_customer_link_expose_phone
        WHERE identifier = ?
        AND merchant_customer_link_id = ?/, [$uniqueID, $merchantCustomerLinkID], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'doesUniquePhoneIDExist'
    });
  }

  return $exists;
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getPhoneListSize {
  my $self = shift;
  my $merchantCustomerLinkID = shift;

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM merchant_customer_link_expose_phone
        WHERE merchant_customer_link_id = ?/, [$merchantCustomerLinkID], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'getPhoneListSize'
    });
  }

  return $count;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_phone_expose' });
  $logger->log($logInfo);
}

1;
