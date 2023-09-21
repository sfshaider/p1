package PlugNPay::Merchant::Customer::PaymentSource::Expose;

use strict;
use PlugNPay::Merchant;
use PlugNPay::Util::Status;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::RandomString;
use PlugNPay::Merchant::Customer::Link;
use PlugNPay::Merchant::Customer::BillMember;
use PlugNPay::Merchant::Customer::PaymentSource;
use PlugNPay::Merchant::Customer::FuturePayment;
use PlugNPay::Merchant::Customer::Address::Expose;
use PlugNPay::Merchant::Customer::PaymentSource::Type;
use PlugNPay::Merchant::Customer::PaymentSource::Expose;
use PlugNPay::Merchant::Customer::PaymentSource::ACH::Type;

#####################################################
# Module: Merchant::Customer::PaymentSource::Expose
# ---------------------------------------------------
# Description:
#   Payment sources that a merchant has on record for
#   a customer.

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

sub setPaymentSourceID {
  my $self = shift;
  my $paymentSourceID = shift;
  $self->{'paymentSourceID'} = $paymentSourceID;
}

sub getPaymentSourceID {
  my $self = shift;
  return $self->{'paymentSourceID'};
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

sub setOrderID {
  my $self = shift;
  my $orderID = shift;
  $self->{'orderID'} = $orderID;
}

sub getOrderID {
  my $self = shift;
  return $self->{'orderID'};
}

sub setTransactionID {
  my $self = shift;
  my $transactionID = shift;
  $self->{'transactionID'} = $transactionID;
}

sub getTransactionID {
  my $self = shift;
  return $self->{'transactionID'};
}

sub setBillingAccount {
  my $self = shift;
  my $billingAccount = shift;
  $self->{'billingAccount'} = $billingAccount;
}

sub getBillingAccount {
  my $self = shift;
  return $self->{'billingAccount'};
}

sub loadExposedPaymentSources {
  my $self = shift;
  my $merchantCustomerLinkID = shift || $self->getMerchantCustomerLinkID();

  my $exposedPaymentSources = [];

  my @values = ();
  my $sql = q/SELECT id,
                     identifier,
                     merchant_customer_link_id,
                     customer_payment_source_id,
                     order_id,
                     transaction_id
              FROM merchant_customer_link_expose_payment_source
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
        my $exposedPaymentSource = new PlugNPay::Merchant::Customer::PaymentSource::Expose();
        $exposedPaymentSource->_setLinkDataFromRow($row);
        push (@{$exposedPaymentSources}, $exposedPaymentSource);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadExposedPaymentSources'
    });
  }

  return $exposedPaymentSources;
}

sub loadExposedPaymentSource {
  my $self = shift;
  my $linkID = shift || $self->{'linkID'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               identifier,
               merchant_customer_link_id,
               customer_payment_source_id,
               order_id,
               transaction_id
        FROM merchant_customer_link_expose_payment_source
        WHERE id = ?/, [$linkID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setLinkDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadExposedPaymentSource'
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
               merchant_customer_link_id,
               customer_payment_source_id,
               order_id,
               transaction_id
        FROM merchant_customer_link_expose_payment_source
        WHERE identifier = ?
        AND merchant_customer_link_id = ?/, [$identifier, $merchantCustomerLinkID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setLinkDataFromRow($rows->[0]);
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
  $self->{'orderID'}                = $row->{'order_id'};
  $self->{'identifier'}             = $row->{'identifier'};
  $self->{'transactionID'}          = $row->{'transaction_id'};
  $self->{'paymentSourceID'}        = $row->{'customer_payment_source_id'};
  $self->{'merchantCustomerLinkID'} = $row->{'merchant_customer_link_id'};
}

##########################################
# Subroutine: saveExposedPaymentSource
# ----------------------------------------
# Description:
#   Saves a payment source to a merchant's
#   records for a customer. Saves the 
#   initial payment source.
sub saveExposedPaymentSource {
  my $self = shift;
  my $paymentSourceData = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');

    # load merchant customer
    my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
    $merchantCustomer->loadMerchantCustomer($merchantCustomerLinkID);

    # get merchant and customer ID
    my $merchantID = $merchantCustomer->getMerchantID();
    my $customerID = $merchantCustomer->getCustomerID();

    my $billingMerchant = $merchantID;
    if ($self->{'billingAccount'}) {
      $billingMerchant = $self->{'billingAccount'};
    }

    # this needs to happen here because payment source addresses 
    # are exposed to merchants. so load the exposed address ID
    # and send it in the save payment source request.
    if ($paymentSourceData->{'useDefaultAddress'}) {
      # if the useDefaultAddress field is sent, load the default address ID
      my $defaultAddressID = $merchantCustomer->getDefaultAddressID();
      if (!$defaultAddressID) {
        push (@errorMsg, 'Failed to create payment source. No default address available.');
      } else {
        $paymentSourceData->{'billingAddressID'} = $defaultAddressID;
      }
    } else {
      # verify the exposed address belongs to the merchant
      my $exposeAddress = new PlugNPay::Merchant::Customer::Address::Expose();
      $exposeAddress->loadByLinkIdentifier($paymentSourceData->{'billingAddressID'}, $merchantCustomerLinkID);
      if (!$exposeAddress->getLinkID()) {
        push (@errorMsg, 'Invalid address identifier.');
      } else {
        $paymentSourceData->{'billingAddressID'} = $exposeAddress->getLinkID();
      }
    }

    if (@errorMsg > 0) {
      return; # no point in continuing
    }

    # save the payment source. which checks to see if it already exists.
    my $paymentSource = new PlugNPay::Merchant::Customer::PaymentSource();
    my $savePaymentSource = $paymentSource->savePaymentSource($paymentSourceData, $customerID);
    if (!$savePaymentSource) {
      push (@errorMsg, $savePaymentSource->getError());
      return; # why continue if we failed to save
    }

    # get the payment source ID
    my $paymentSourceID = $paymentSource->getPaymentSourceID();

    # before we do anything, make sure the payment source ID does not already exist
    # for the customer.
    if ($self->doesExposedPaymentSourceExist($paymentSourceID, $merchantCustomerLinkID)) {
      push (@errorMsg, 'Payment source information exists for customer.');
      return; # returning a lot because it doens't make sense to keep going.
    }

    # if no errors, continue to zero auth
    if (@errorMsg == 0) {
      # if it saved and non existing, a zero auth MUST be performed.
      my $zeroAuthResponse = $self->_performAuth($paymentSourceID,
                                                 $merchantCustomerLinkID,
                                                 $billingMerchant);
      if (!$zeroAuthResponse->{'status'}) {
        push (@errorMsg, $zeroAuthResponse->{'status'}->getError());
      }

      if (@errorMsg == 0) {
        # get the order id and transaction id from the zero auth and store it 
        # with the exposed payment source.
        my $orderID = $zeroAuthResponse->{'transactionDetails'}{'orderID'};
        my $transactionID = $zeroAuthResponse->{'transactionDetails'}{'transactionID'};

        # generate an identifier for the payment source
        my $identifier = $self->_generateUniquePaymentSourceID($merchantCustomerLinkID);

        my $params = [
          $merchantCustomerLinkID,
          $paymentSourceID,
          $identifier,
          $transactionID,
          $orderID
        ];

        # save the exposed payment source information
        $dbs->executeOrDie('merchant_cust',
          q/INSERT INTO merchant_customer_link_expose_payment_source
            ( merchant_customer_link_id,
              customer_payment_source_id,
              identifier,
              transaction_id,
              order_id )
            VALUES (?,?,?,?,?)/, $params);
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      $self->_log({ 
        'error'                  => $@,
        'function'               => 'saveExposedPaymentSource',
        'merchantCustomerLinkID' => $merchantCustomerLinkID
      });

      push (@errorMsg, 'Error while attempting to save payment source.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

#########################################
# Subroutine: updateExposedPaymentSource
# ---------------------------------------
# Description:
#   Updates the link between a merchant's
#   customer and a payment source. The
#   current exposed payment source
#   must be loaded before calling this.
sub updateExposedPaymentSource {
  my $self = shift;
  my $updatePaymentSourceData = shift;
  my $linkID = shift || $self->{'linkID'};

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');

    # if the current payment source id is 
    # not loaded, load using the link ID
    if (!$self->{'paymentSourceID'}) {
      $self->loadExposedPaymentSource($linkID);
      if (!$self->{'paymentSourceID'}) {
        push (@errorMsg, 'Unable to update payment source data.');
        return;
      }
    }

    # load merchant customer link
    my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
    $merchantCustomer->loadMerchantCustomer($self->{'merchantCustomerLinkID'});

    my $billingMerchant = $merchantCustomer->getMerchantID();
    if ($self->{'billingAccount'}) {
      $billingMerchant = $self->{'billingAccount'};
    }

    # load the current payment source data
    my $paymentSource = new PlugNPay::Merchant::Customer::PaymentSource();
    $paymentSource->loadPaymentSource($self->{'paymentSourceID'});

    if ($updatePaymentSourceData->{'useDefaultAddress'}) {
      # if the useDefaultAddress field is sent, load the default address ID
      my $defaultAddressID = $merchantCustomer->getDefaultAddressID();
      if (!$defaultAddressID) {
        push (@errorMsg, 'No default address is available');
      } else {
        $updatePaymentSourceData->{'billingAddressID'} = $defaultAddressID;
      }
    } else {
      # verify the exposed address belongs to the merchant
      my $exposeAddress = new PlugNPay::Merchant::Customer::Address::Expose();
      $exposeAddress->loadByLinkIdentifier($updatePaymentSourceData->{'billingAddressID'}, $self->{'merchantCustomerLinkID'});
      if (!$exposeAddress->getLinkID()) {
        push (@errorMsg, 'Invalid address identifier.');
      } else {
        $updatePaymentSourceData->{'billingAddressID'} = $exposeAddress->getLinkID();
      }
    }

    if (@errorMsg > 0) {
      return; # exit because we errored up top
    }

    # try to update the payment source info since 
    # the information might not change.
    my $updatePaymentSource = $paymentSource->updatePaymentSource($updatePaymentSourceData);
    if (!$updatePaymentSource) {
      push (@errorMsg, $updatePaymentSource->getError());
      return; # nothing more
    }

    # get the payment source ID from the data just updated
    my $updatedPaymentSourceID = $paymentSource->getPaymentSourceID();

    # if the payment source ID did not change then this update is complete.
    if ($updatedPaymentSourceID != $self->{'paymentSourceID'}) {
      # check to see if the payment source data already exists for the new payment source ID
      if ($self->doesExposedPaymentSourceExist($updatedPaymentSourceID, $self->{'merchantCustomerLinkID'})) {
        push (@errorMsg, 'Payment source information exists for customer.');
        return;
      }

      # MUST perform zero auth
      my $zeroAuthResponse = $self->_performAuth($updatedPaymentSourceID,
                                                 $self->{'merchantCustomerLinkID'},
                                                 $billingMerchant);
      if (!$zeroAuthResponse->{'status'}) {
        push (@errorMsg, $zeroAuthResponse->{'status'}->getError());
      }
 
      if (@errorMsg == 0) {
        # get the order id and transaction id from the zero auth
        my $orderID = $zeroAuthResponse->{'transactionDetails'}{'orderID'};
        my $transactionID = $zeroAuthResponse->{'transactionDetails'}{'transactionID'};

        # save the new payment source ID
        $dbs->executeOrDie('merchant_cust', 
          q/UPDATE merchant_customer_link_expose_payment_source
           SET customer_payment_source_id = ?,
               order_id = ?,
               transaction_id = ?
           WHERE id = ?/, [$updatedPaymentSourceID, $orderID, $transactionID, $linkID]);

        # if the payment source is not EXPOSED
        # then it does not have a place in this world
        if (!$self->isPaymentSourceUsed($self->{'paymentSourceID'})) {
          $paymentSource->deletePaymentSource($self->{'paymentSourceID'});
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_paymentsource_expose' });
      $logger->log({ 
        'error'    => $@,
        'function' => 'updateExposedPaymentSource',
        'linkID'   => $linkID
      });

      push (@errorMsg, 'Error while attempting to update customer payment source.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

###########################################
# Subroutine: deleteExposedPaymentSource
# -----------------------------------------
# Description:
#   Deletes payment source from merchant's
#   records for the customer.
sub deleteExposedPaymentSource {
  my $self = shift;
  my $linkID = shift || $self->{'linkID'};

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  if (!$self->{'paymentSourceID'}) {
    $self->loadExposedPaymentSource($linkID);
  }

  my $profile = new PlugNPay::Membership::Profile();
  if ($profile->isPaymentSourceUsed($linkID)) {
    push (@errorMsg, 'Payment source is currently active in billing profile.');
  }

  my $futurePayments = new PlugNPay::Merchant::Customer::FuturePayment();
  if ($futurePayments->isPaymentSourceUsed($linkID)) {
    push (@errorMsg, 'Future payment scheduled with current payment source.');
  }

  if (@errorMsg == 0) {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/DELETE FROM merchant_customer_link_expose_payment_source
          WHERE id = ?/, [$linkID]);

      my $paymentSourceID = $self->{'paymentSourceID'};
      if (!$self->isPaymentSourceUsed($paymentSourceID)) {
        my $paymentSource = new PlugNPay::Merchant::Customer::PaymentSource();
        $paymentSource->deletePaymentSource($paymentSourceID);
      }
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({ 
        'error'    => $@,
        'function' => 'deleteExposedPaymentSource',
        'linkID'   => $linkID
      });

      push (@errorMsg, 'Error while attempting to delete payment source.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

sub _generateUniquePaymentSourceID {
  my $self = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};

  my $uniqueID = new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);
  if ($self->doesUniquePaymentSourceIDExist($uniqueID, $merchantCustomerLinkID)) {
    return $self->_generateUniquePaymentSourceID($merchantCustomerLinkID);
  }

  return $uniqueID;
}

sub doesUniquePaymentSourceIDExist {
  my $self = shift;
  my $uniqueID = shift;
  my $merchantCustomerLinkID = shift || $self->{'merchantCustomerLinkID'};

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM merchant_customer_link_expose_payment_source
        WHERE identifier = ?
        AND merchant_customer_link_id = ?/, [$uniqueID, $merchantCustomerLinkID], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'doesUniquePaymentSourceIDExist'
    });
  }

  return $exists;
}

sub doesExposedPaymentSourceExist {
  my $self = shift;
  my $paymentSourceID = shift;
  my $merchantCustomerLinkID = shift;

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM merchant_customer_link_expose_payment_source
        WHERE customer_payment_source_id = ?
        AND merchant_customer_link_id = ?/, [$paymentSourceID, $merchantCustomerLinkID], {})->{'result'};
    $exists = $rows->[0]{'exists'}
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'doesExposedPaymentSourceExist'
    });
  }
  
  return $exists;
}

sub isPaymentSourceUsed {
  my $self = shift;
  my $paymentSourceID = shift;

  my $inUse = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `inUse`
        FROM merchant_customer_link_expose_payment_source
        WHERE customer_payment_source_id = ?/, [$paymentSourceID], {})->{'result'};
    $inUse = $rows->[0]{'inUse'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'isPaymentSourceUsed'
    });
  }

  return $inUse;
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getPaymentSourceListSize {
  my $self = shift;
  my $merchantCustomerLinkID = shift;

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM merchant_customer_link_expose_payment_source
        WHERE merchant_customer_link_id = ?/, [$merchantCustomerLinkID], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'getPaymentSourceListSize'
    });
  }

  return $count;
}

#################################################
# Subroutine: _performAuth
# -----------------------------------------------
# Description:
#   For every new payment source added, this
#   will be called to perform a ZERO dollar auth
#   on using that payment information.
sub _performAuth {
  my $self = shift;
  my $paymentSourceID = shift;
  my $merchantCustomerLinkID = shift;
  my $merchant = shift;

  # load payment source
  my $paymentSource = new PlugNPay::Merchant::Customer::PaymentSource();
  $paymentSource->loadPaymentSource($paymentSourceID);

  # if card, zero auth
  my $paymentSourceType = new PlugNPay::Merchant::Customer::PaymentSource::Type();
  $paymentSourceType->loadPaymentType($paymentSource->getPaymentSourceTypeID());
  if ($paymentSourceType->getPaymentType() !~ /^card$/i) {
    return { 'status' => new PlugNPay::Util::Status(1) };
  }

  my $biller = new PlugNPay::Merchant::Customer::BillMember();
  return $biller->billCustomer($merchantCustomerLinkID,
                               $paymentSource, {
    'transactionType' => 'auth',
    'amount'          => 0,
    'tax'             => 0,
    'description'     => 'Zero Auth',
    'billingAccount'  => $merchant,
    'transflags'      => ['recinit']
  });
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_paymentsource_expose' });
  $logger->log($logInfo);
}

1;
