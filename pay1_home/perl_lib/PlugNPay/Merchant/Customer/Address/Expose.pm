package PlugNPay::Merchant::Customer::Address::Expose;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::RandomString;
use PlugNPay::Merchant::Customer::Link;
use PlugNPay::Merchant::Customer::Address;
use PlugNPay::Merchant::Customer::PaymentSource;

###############################################
# Module: Merchant::Customer::Address::Expose
# ---------------------------------------------
# Description:
#   Exposed addresses are customer addresses
#   that are visible to the merchant that the
#   customer belongs to.

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

sub setAddressID {
  my $self = shift;
  my $addressID = shift;
  $self->{'addressID'} = $addressID;
}

sub getAddressID {
  my $self = shift;
  return $self->{'addressID'};
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

sub loadExposedAddresses {
  my $self = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};

  my $exposedAddresses = [];

  my @values = ();
  my $sql = q/SELECT id,
                     identifier,
                     customer_address_id,
                     merchant_customer_link_id
              FROM merchant_customer_link_expose_address
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
        my $exposedAddress = new PlugNPay::Merchant::Customer::Address::Expose();
        $exposedAddress->_setLinkDataFromRow($row);
        push (@{$exposedAddresses}, $exposedAddress);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadExposedAddresses'
    });
  }

  return $exposedAddresses;
}

sub loadExposedAddress {
  my $self = shift;
  my $linkID = shift || $self->{'linkID'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               customer_address_id,
               merchant_customer_link_id
        FROM merchant_customer_link_expose_address
        WHERE id = ?/, [$linkID], {})->{'result'};
    if (@{$rows} > 0) {
      my $row = $rows->[0];
      $self->_setLinkDataFromRow($row);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadExposedAddress'
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
               customer_address_id,
               merchant_customer_link_id
        FROM merchant_customer_link_expose_address
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
  $self->{'addressID'}              = $row->{'customer_address_id'};
  $self->{'merchantCustomerLinkID'} = $row->{'merchant_customer_link_id'};
}

##################################
# Subroutine: saveExposedAddress
# --------------------------------
# Description:
#   Saves a customer address ID
#   to the exposed table.
sub saveExposedAddress {
  my $self = shift;
  my $addressData = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};
  my $options = shift || {};

  my $dbs = new PlugNPay::DBConnection();
  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  eval {
    $dbs->begin('merchant_cust');

    # load the merchant customer link
    my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
    $merchantCustomer->loadMerchantCustomer($merchantCustomerLinkID);

    # save the address, will also check to see if exists
    my $address = new PlugNPay::Merchant::Customer::Address();
    my $saveAddressStatus = $address->saveAddress($merchantCustomer->getCustomerID(), $addressData);
    if (!$saveAddressStatus) {
      push (@errorMsg, $saveAddressStatus->getError());
      return; # no reason to continue
    }

    # get the address ID
    my $addressID = $address->getAddressID();

    # check to see if the address exists already in the merchant's records
    if ($self->doesExposedAddressExist($addressID, $merchantCustomerLinkID)) {
      push (@errorMsg, 'Customer already has address information.');
    }

    if (@errorMsg == 0) {
      # generate an identifier for the address
      my $identifier = $self->_generateUniqueAddressID($merchantCustomerLinkID);

      # save exposed address
      my $sth = $dbs->executeOrDie('merchant_cust',
        q/INSERT INTO merchant_customer_link_expose_address
          ( merchant_customer_link_id,
            customer_address_id,
            identifier )
          VALUES (?,?,?)/, [$merchantCustomerLinkID, $addressID, $identifier])->{'sth'};
      my $addressLinkID = $sth->{'mysql_insertid'};

      # if the make default option is passed then it will set it as the default
      # in the merchant_customer_link table
      if ($options->{'makeDefault'}) {
        my $updateStatus = $merchantCustomer->updateMerchantCustomer({ 'defaultAddressID' => $identifier });
        if (!$updateStatus) {
          push (@errorMsg, 'Failed to save address.');
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      $self->_log({
        'function'               => 'saveExposedAddress',
        'error'                  => $@,
        'merchantCustomerLinkID' => $merchantCustomerLinkID
      });

      push (@errorMsg, 'Error while attempting to save customer address.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

######################################
# Subroutine: updateExposedAddress
# ------------------------------------
# Description:
#   Updates the link between address
#   and merchant customer. Expects
#   the link object to be loaded.
sub updateExposedAddress {
  my $self = shift;
  my $updateAddressData = shift;
  my $linkID = shift || $self->{'linkID'};

  my $dbs = new PlugNPay::DBConnection();
  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  eval {
    $dbs->begin('merchant_cust');

    # if the address isn't loaded
    # load using link ID
    if (!$self->{'addressID'}) {
      $self->loadExposedAddress($linkID);
      if (!$self->{'addressID'}) {
        push (@errorMsg, 'Unable to update address data.');
        return; # the caller did not load the exposed data first, so return.
      }
    }

    # load the merchant customer link
    my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
    $merchantCustomer->loadMerchantCustomer($self->{'merchantCustomerLinkID'});

    # load address first
    my $address = new PlugNPay::Merchant::Customer::Address();
    $address->loadAddress($self->{'addressID'});

    # update the address, will also check to see if exists
    my $updateAddressStatus = $address->updateAddress($updateAddressData);
    if (!$updateAddressStatus) {
      push (@errorMsg, $updateAddressStatus->getError());
      return; # return here if update fails.
    }

    # get updated address ID
    my $updatedAddressID = $address->getAddressID();

    # if the address ID did not change, the update is done
    if ($updatedAddressID != $self->{'addressID'}) {
      # check to see if the address exists in the merchant's records
      if ($self->doesExposedAddressExist($updatedAddressID, $self->{'merchantCustomerLinkID'})) {
        push (@errorMsg, 'Customer already has saved address information.');
      }

      if (@errorMsg == 0) {
        # update the exposed address
        $dbs->executeOrDie('merchant_cust',
          q/UPDATE merchant_customer_link_expose_address
            SET customer_address_id = ?
            WHERE id = ?/, [$updatedAddressID, $linkID]);
        if (!$self->isAddressUsed($self->{'addressID'}) && !new PlugNPay::Merchant::Customer::PaymentSource()->isBillingAddressUsed($self->{'addressID'})) {
          $address->deleteAddress($self->{'addressID'}); # try cleaning up
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      $self->_log({
        'function' => 'updateExposedAddress',
        'error'    => $@
      });

      push (@errorMsg, 'Error while attempting to update customer address.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

#########################################
# Subroutine: deleteExposedAddress
# ---------------------------------------
# Description:
#   Deletes a link between the customer
#   address and the merchant customer.
#   Expects the link object to be loaded.
sub deleteExposedAddress {
  my $self = shift;
  my $linkID = shift || $self->{'linkID'};

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  if (!$self->{'addressID'}) {
    $self->loadExposedAddress($linkID);
  }

  # do not delete an address if it belongs to a payment source.
  if (new PlugNPay::Merchant::Customer::PaymentSource()->isBillingAddressUsed($linkID)) {
    push (@errorMsg, 'Address is currently used in payment source.');
  }

  if (@errorMsg == 0) {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/DELETE FROM merchant_customer_link_expose_address
          WHERE id = ?/, [$linkID]);

      if (!$self->isAddressUsed($self->{'addressID'})) {
        my $address = new PlugNPay::Merchant::Customer::Address();
        $address->deleteAddress($self->{'addressID'});
      }
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'    => $@,
        'function' => 'deleteExposedAddress'
      });

      push (@errorMsg, 'Error while attempting to delete customer address.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

sub doesExposedAddressExist {
  my $self = shift;
  my $addressID = shift;
  my $merchantCustomerLinkID = shift;

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM merchant_customer_link_expose_address
        WHERE customer_address_id = ?
        AND merchant_customer_link_id = ?/, [$addressID, $merchantCustomerLinkID], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'doesExposedAddressExist'
    });
  }

  return $exists;
}

sub isAddressUsed {
  my $self = shift;
  my $addressID = shift;

  my $inUse = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `inUse`
        FROM merchant_customer_link_expose_address
        WHERE customer_address_id = ?/, [$addressID], {})->{'result'};
    $inUse = $rows->[0]{'inUse'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'doesUniqueAddressIDExist'
    });
  }

  return $inUse;
}

sub _generateUniqueAddressID {
  my $self = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};

  my $uniqueID = new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);
  if ($self->doesUniqueAddressIDExist($uniqueID, $merchantCustomerLinkID)) {
    return $self->_generateUniqueAddressID($merchantCustomerLinkID);
  }

  return $uniqueID;
}

sub doesUniqueAddressIDExist {
  my $self = shift;
  my $uniqueID = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM merchant_customer_link_expose_address
        WHERE identifier = ?
        AND merchant_customer_link_id = ?/, [$uniqueID, $merchantCustomerLinkID], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'doesUniqueAddressIDExist'
    });
  }

  return $exists;
}

sub getAddressListSize {
  my $self = shift;
  my $merchantCustomerLinkID = shift;

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM merchant_customer_link_expose_address
        WHERE merchant_customer_link_id = ?/, [$merchantCustomerLinkID], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'getAddressListSize'
    });
  }

  return $count;
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_address_expose' });
  $logger->log($logInfo);
}

1;
