package PlugNPay::Merchant::Customer::PaymentSource;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::Merchant::Customer::PaymentSource::Type;
use PlugNPay::Merchant::Customer::PaymentSource::ACH::Type;

#############################################
# Module: Merchant::Customer::PaymentSource
# -------------------------------------------
# Description:
#   Payment source of a customer.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
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

sub setCustomerID {
  my $self = shift;
  my $customerID = shift;
  $self->{'customerID'} = $customerID;
}

sub getCustomerID {
  my $self = shift;
  return $self->{'customerID'};
}

sub setPaymentSourceTypeID {
  my $self = shift;
  my $paymentSourceTypeID = shift;
  $self->{'paymentSourceTypeID'} = $paymentSourceTypeID;
}

sub getPaymentSourceTypeID {
  my $self = shift;
  return $self->{'paymentSourceTypeID'};
}

sub setToken {
  my $self = shift;
  my $token = shift;

  if ($token !~ /^[a-fA-F0-9]+$/) {
    my $tk = new PlugNPay::Token();
    $tk->fromBinary($token);
    $token = $tk->inHex();
  }

  $self->{'token'} = $token;
}

sub getToken {
  my $self = shift;
  return $self->{'token'};
}

sub setExpirationMonth {
  my $self = shift;
  my $expMonth = shift;
  $self->{'expirationMonth'} = $expMonth;
}

sub getExpirationMonth {
  my $self = shift;
  return $self->{'expirationMonth'};
}

sub setExpirationYear {
  my $self = shift;
  my $expYear = shift;
  $self->{'expirationYear'} = $expYear;
}

sub getExpirationYear {
  my $self = shift;
  return $self->{'expirationYear'};
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

sub setBillingAddressID {
  my $self = shift;
  my $billingAddressID = shift;
  $self->{'billingAddressID'} = $billingAddressID;
}

sub getBillingAddressID {
  my $self = shift;
  return $self->{'billingAddressID'};
}

sub setIsCommercialCard {
  my $self = shift;
  my $isCommercial = shift;
  $self->{'isComm'} = $isCommercial;
}

sub getIsCommercialCard {
  my $self = shift;
  return $self->{'isComm'};
}

sub setLastUpdated {
  my $self = shift;
  my $lastUpdated = shift;
  $self->{'lastUpdated'} = $lastUpdated;
}

sub getLastUpdated {
  my $self = shift;
  return $self->{'lastUpdated'};
}

sub setLastFour {
  my $self = shift;
  my $last4 = shift;
  $self->{'lastFour'} = $last4;
}

sub getLastFour {
  my $self = shift;
  return $self->{'lastFour'};
}

sub setCardBrand {
  my $self = shift;
  my $brand = shift;
  $self->{'cardBrand'} = $brand;
}

sub getCardBrand {
  my $self = shift;
  return $self->{'cardBrand'};
}

sub setAccountTypeID {
  my $self = shift;
  my $accountTypeID = shift;
  $self->{'accountTypeID'} = $accountTypeID;
}

sub getAccountTypeID {
  my $self = shift;
  return $self->{'accountTypeID'};
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

# THIS IS NOT USED PUBLICLY #
sub loadPaymentSources {
  my $self = shift;
  my $customerID = shift;

  my $paymentSources = [];

  my @values = ();
  my $sql = q/SELECT id,
                     customer_id,
                     payment_source_type_id,
                     token,
                     expiration_month,
                     expiration_year,
                     description,
                     billing_address_id,
                     commercial_card,
                     last_updated,
                     last_four,
                     card_brand,
                     account_type_id
              FROM customer_payment_source
              WHERE customer_id = ?/;
  push (@values, $customerID);

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
        my $paymentSource = new PlugNPay::Merchant::Customer::PaymentSource();
        $paymentSource->_setPaymentSourceDataFromRow($row);
        push (@{$paymentSources}, $paymentSource);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadPaymentSources'
    });
  }

  return $paymentSources;
}

sub loadPaymentSource {
  my $self = shift;
  my $paymentSourceID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               customer_id,
               payment_source_type_id,
               token,
               expiration_month,
               expiration_year,
               description,
               billing_address_id,
               commercial_card,
               last_updated,
               last_four,
               card_brand,
               account_type_id
        FROM customer_payment_source
        WHERE id = ?/, [$paymentSourceID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setPaymentSourceDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadPaymentSource'
    });
  }
}

sub _setPaymentSourceDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'paymentSourceID'}     = $row->{'id'};
  $self->{'customerID'}          = $row->{'customer_id'};
  $self->{'paymentSourceTypeID'} = $row->{'payment_source_type_id'};
  $self->{'expirationMonth'}     = $row->{'expiration_month'};
  $self->{'expirationYear'}      = $row->{'expiration_year'};
  $self->{'description'}         = $row->{'description'};
  $self->{'billingAddressID'}    = $row->{'billing_address_id'};
  $self->{'isComm'}              = $row->{'commercial_card'};
  $self->{'lastUpdated'}         = $row->{'last_updated'};
  $self->{'lastFour'}            = $row->{'last_four'};
  $self->{'cardBrand'}           = $row->{'card_brand'};
  $self->{'accountTypeID'}       = $row->{'account_type_id'};

  # set token
  $self->setToken($row->{'token'});
}

###########################################
# Subroutine: savePaymentSource
# -----------------------------------------
# Description:
#   Saves a payment source in the customer
#   payment source table. This data can
#   be shared across merchants.
sub savePaymentSource {
  my $self = shift;
  my $data = shift;
  my $customerID = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $paymentSourceID;

  my $type = new PlugNPay::Merchant::Customer::PaymentSource::Type();
  if ($data->{'paymentType'} =~ /^\d+$/) {
    $type->loadPaymentType($data->{'paymentType'});
  } else {
    $type->loadPaymentTypeID($data->{'paymentType'});
  }

  if (!$type->getPaymentTypeID()) {
    $status->setFalse();
    $status->setError('Invalid payment type (card|ach).');
    return $status; # it's pointless to continue
  }

  my $paymentSourceData = {};
  my $token;
  if ($type->getPaymentType() =~ /^card$/i) {
    my $cc = new PlugNPay::CreditCard($data->{'cardNumber'});
    $cc->setExpirationMonth($data->{'expirationMonth'});
    $cc->setExpirationYear($data->{'expirationYear'});
    if (!$cc->verifyLuhn10() || !$cc->verifyLength()) {
      push (@errorMsg, 'Invalid card information.');
    } elsif ($cc->isExpired()) {
      push (@errorMsg, 'Credit card is expired.');
    } else {
      $token = $cc->getToken();
      if (!$token) {
        push (@errorMsg, 'Unable to reach payment token server, please contact technical support.');
      }
    }

    my $billingAddressID = $data->{'billingAddressID'};
    if (!$billingAddressID) {
      push (@errorMsg, 'Invalid address identifier');
    }

    # if errors dont attempt the insert
    if (@errorMsg == 0) {
      my $tk = new PlugNPay::Token();
      $tk->fromHex($token);

      $paymentSourceData->{'type'} = $type->getPaymentType();
      $paymentSourceData->{'token'} = $tk->inBinary();
      $paymentSourceData->{'expirationMonth'} = $cc->getExpirationMonth();
      $paymentSourceData->{'expirationYear'} = $cc->getExpirationYear();
      $paymentSourceData->{'billingAddressID'} = $billingAddressID;

      eval {
        $paymentSourceID = $self->_doesPaymentSourceDataExist($customerID, $paymentSourceData);
        if (!$paymentSourceID) {
          # insert it because it doesn't exist in the records.
          $cc->getMaskedNumber() =~ /(\d{4})$/;
          my $lastFour = $1;

          $paymentSourceID = $self->_insertPaymentSource({
            'customer_id'            => $customerID,
            'payment_source_type_id' => $type->getPaymentTypeID(),
            'token'                  => $tk->inBinary(),
            'last_four'              => $lastFour,
            'card_brand'             => $cc->getBrand(),
            'expiration_month'       => $cc->getExpirationMonth(),
            'expiration_year'        => $cc->getExpirationYear(),
            'commercial_card'        => $cc->isBusinessCard() || 0,
            'description'            => $data->{'description'},
            'billing_address_id'     => $billingAddressID,
            'last_updated'           => new PlugNPay::Sys::Time()->nowInFormat('iso')
          });
        }

        $self->{'paymentSourceID'} = $paymentSourceID;
      };
    }
  } else {
    my $ach = new PlugNPay::OnlineCheck();
    $ach->setABARoutingNumber($data->{'routingNumber'});
    $ach->setAccountNumber($data->{'accountNumber'});

    if (!$ach->verifyABARoutingNumber()) {
      push (@errorMsg, 'Invalid ach information.');
    } else {
      $token = $ach->getToken();
      if (!$token) {
        push (@errorMsg, 'Unable to reach payment token server, please contact technical support.');
      }
    }

    my $achType = new PlugNPay::Merchant::Customer::PaymentSource::ACH::Type();
    if ($data->{'accountType'} =~ /^\d+$/) {
      $achType->loadACHAccountType($data->{'accountType'});
    } else {
      $achType->loadACHAccountTypeID($data->{'accountType'});
    }

    if (!$achType->getAccountTypeID()) {
      push (@errorMsg, 'Invalid account type.');
    }

    my $billingAddressID = $data->{'billingAddressID'};
    if (!$billingAddressID) {
      push (@errorMsg, 'Invalid address identifier.');
    }

    if (@errorMsg == 0) {
      my $tk = new PlugNPay::Token();
      $tk->fromHex($token);

      my $paymentSourceData = {};
      $paymentSourceData->{'token'} = $tk->inBinary();
      $paymentSourceData->{'accountType'} = $achType->getAccountTypeID();
      $paymentSourceData->{'billingAddressID'} = $billingAddressID;

      eval {
        $paymentSourceID = $self->_doesPaymentSourceDataExist($customerID, $paymentSourceData);
        if (!$paymentSourceID) {
          # if it doesn't exist in customers records
          $ach->getAccountNumber() =~ /(\d{4})$/;
          my $lastFour = $1;

          $paymentSourceID = $self->_insertPaymentSource({
            'customer_id'            => $customerID,
            'payment_source_type_id' => $type->getPaymentTypeID(),
            'token'                  => $tk->inBinary(),
            'last_four'              => $lastFour,
            'account_type_id'        => $achType->getAccountTypeID(),
            'description'            => $data->{'description'},
            'billing_address_id'     => $billingAddressID,
            'last_updated'           => new PlugNPay::Sys::Time()->nowInFormat('iso')
          });
        }

        $self->{'paymentSourceID'} = $paymentSourceID;
      };
    }
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'function' => 'savePaymentSource',
        'error'    => $@
      });

      push (@errorMsg, 'Error while attempting to save payment source.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

##########################################
# Subroutine: updatePaymentSource
# ----------------------------------------
# Description:
#   Updates a customers entry in the 
#   payment source table.
sub updatePaymentSource {
  my $self = shift;
  my $updateData = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $paymentSourceID = $self->{'paymentSourceID'};

  my $type = new PlugNPay::Merchant::Customer::PaymentSource::Type();
  if ($updateData->{'paymentType'} =~ /^\d+$/) {
    $type->loadPaymentType($updateData->{'paymentType'});
  } else {
    $type->loadPaymentTypeID($updateData->{'paymentType'});
  }

  if (!$type->getPaymentTypeID()) {
    $status->setFalse();
    $status->setError('Invalid payment type.');
    return $status;
  }

  my ($changeType, $numberChange, $expMonth, $expYear, $cardBrand, $isComm, $token, $lastFour);

  # if type is different
  if ($type->getPaymentTypeID() != $self->getPaymentSourceTypeID()) {
    $changeType = 1;
  }

  if ($type->getPaymentType() =~ /^card$/i) {
    # if the card number field doesn't exist,
    # use the card we have on file.
    my $cc = new PlugNPay::CreditCard();
    if (exists $updateData->{'cardNumber'} || $changeType) {
      $cc->setNumber($updateData->{'cardNumber'});
      $cc->setExpirationMonth($updateData->{'expirationMonth'});
      $cc->setExpirationYear($updateData->{'expirationYear'});
      if (!$cc->verifyLuhn10() || !$cc->verifyLength()) {
        push (@errorMsg, 'Invalid card information.');
      } elsif ($cc->isExpired()) {
        push (@errorMsg, 'Credit card is expired.');
      } else {
        $token = $cc->getToken();
        if (!$token) {
          push (@errorMsg, 'Unable to reach payment token server, please contact technical support.');
        } else {
          # if the token is not the same,
          # it means the card number has changed
          if ($token ne $self->{'token'}) {
            $numberChange = 1;
          }

          $expMonth  = $cc->getExpirationMonth();
          $expYear   = $cc->getExpirationYear();
          $cardBrand = $cc->getBrand();
          $isComm    = $cc->isBusinessCard();

          $cc->getMaskedNumber() =~ /(\d{4})$/;
          $lastFour  = $1;
        }
      }
    } else {
      $lastFour  = $self->{'lastFour'};
      $token     = $self->{'token'};
      $expMonth  = $updateData->{'expirationMonth'} || $self->{'expirationMonth'};
      $expYear   = $updateData->{'expirationYear'} || $self->{'expirationYear'};

      $cc->setExpirationMonth($expMonth);
      $cc->setExpirationYear($expYear);
      if ($cc->isExpired()) {
        push (@errorMsg, 'Credit card is expired.');
      } else {
        $expMonth  = $cc->getExpirationMonth();
        $expYear   = $cc->getExpirationYear();
        $cardBrand = $self->{'cardBrand'};
        $isComm    = $self->{'isComm'};
      }
    }

    # if billing address exists
    my $billingAddressID;
    if (exists $updateData->{'billingAddressID'}) {
      if (!$updateData->{'billingAddressID'}) {
        push (@errorMsg, 'Invalid address identifier.');
      } else {
        $billingAddressID = $updateData->{'billingAddressID'};
      }
    } else {
      $billingAddressID = $self->{'billingAddressID'};
    }

    if (@errorMsg == 0) {
      # compare card data
      my $tk = new PlugNPay::Token();
      $tk->fromHex($token);
      if ($numberChange) {
        # new row
        eval {
          $paymentSourceID = $self->_doesPaymentSourceDataExist($self->{'customerID'}, {
            'type'             => $type->getPaymentType(),
            'token'            => $tk->inBinary(),
            'expirationMonth'  => $expMonth,
            'expirationYear'   => $expYear,
            'billingAddressID' => $billingAddressID
          });

          if (!$paymentSourceID) {
            # data does not exist, insert it
            $paymentSourceID = $self->_insertPaymentSource({
              'customer_id'            => $self->{'customerID'},
              'payment_source_type_id' => $type->getPaymentTypeID(),
              'token'                  => $tk->inBinary(),
              'last_four'              => $lastFour,
              'card_brand'             => $cardBrand,
              'expiration_month'       => $expMonth,
              'expiration_year'        => $expYear,
              'commercial_card'        => $isComm,
              'description'            => $updateData->{'description'},
              'billing_address_id'     => $billingAddressID,
              'last_updated'           => new PlugNPay::Sys::Time()->nowInFormat('iso')
            });
          }

          $self->{'paymentSourceID'} = $paymentSourceID;
        };
      } elsif ($expMonth         ne $self->{'expirationMonth'}  ||
               $expYear          ne $self->{'expirationYear'}   ||
               $billingAddressID != $self->{'billingAddressID'} ||
               $updateData->{'description'} ne $self->{'description'}) {
        eval {
          $paymentSourceID = $self->_doesPaymentSourceDataExist($self->{'customerID'}, {
            'type'             => $type->getPaymentType(),
            'token'            => $tk->inBinary(),
            'expirationMonth'  => $expMonth,
            'expirationYear'   => $expYear,
            'billingAddressID' => $billingAddressID
          });

          if (!$paymentSourceID) {
            # do an update on the row
              $self->_updatePaymentSource({
                'description'        => $updateData->{'description'},
                'expiration_month'   => $expMonth,
                'expiration_year'    => $expYear,
                'billing_address_id' => $billingAddressID,
                'last_updated'       => new PlugNPay::Sys::Time()->nowInFormat('iso')
              });
          } else {
            $self->{'paymentSourceID'} = $paymentSourceID;
          }
        };
      }
    }
  } else {
    my ($token, $lastFour);
    if (exists $updateData->{'routingNumber'} || exists $updateData->{'accountNumber'} || $changeType) {
      my $ach = new PlugNPay::OnlineCheck();
      $ach->setABARoutingNumber($updateData->{'routingNumber'});
      $ach->setAccountNumber($updateData->{'accountNumber'});
      if (!$ach->verifyABARoutingNumber()) {
        push (@errorMsg, 'Invalid ach information.');
      } else {
        $token = $ach->getToken();
        if (!$token) {
          push (@errorMsg, 'Unable to reach payment token server, please contact technical support.');
        } else {
          if ($token ne $self->{'token'}) {
            $numberChange = 1;
          }

          $ach->getAccountNumber() =~ /(\d{4})$/;
          $lastFour = $1;
        }
      }
    } else {
      $token = $self->{'token'};
      $lastFour = $self->{'lastFour'};
    }

    my $accountTypeID;
    if (exists $updateData->{'accountType'}) {
      my $achType = new PlugNPay::Merchant::Customer::PaymentSource::ACH::Type();
      if ($updateData->{'accountType'} =~ /^\d+$/) {
        $achType->loadACHAccountType($updateData->{'accountType'});
      } else {
        $achType->loadACHAccountTypeID($updateData->{'accountType'});
      }

      if (!$achType->getAccountTypeID()) {
        push (@errorMsg, 'Invalid account type');
      } else {
        $accountTypeID = $achType->getAccountTypeID();
      }
    } else {
      $accountTypeID = $self->{'accountTypeID'};
    }

    my $billingAddressID;
    if (exists $updateData->{'billingAddressID'}) {
      if (!$updateData->{'billingAddressID'}) {
        push (@errorMsg, 'Invalid address identifier.');
      } else {
        $billingAddressID = $updateData->{'billingAddressID'};
      }
    } else {
      $billingAddressID = $self->{'billingAddressID'};
    }

    if (@errorMsg == 0) {
      # compare ach data
      my $tk = new PlugNPay::Token();
      $tk->fromHex($token);
      if ($numberChange) {
        # new row
        eval {
          $paymentSourceID = $self->_doesPaymentSourceDataExist($self->{'customerID'}, {
            'type'             => $type->getPaymentTypeID(),
            'token'            => $tk->inBinary(),
            'billingAddressID' => $billingAddressID,
            'accountTypeID'    => $accountTypeID
          });

          if (!$paymentSourceID) {
            $paymentSourceID = $self->_insertPaymentSource({
              'customer_id'            => $self->{'customerID'},
              'payment_source_type_id' => $type->getPaymentTypeID(),
              'token'                  => $tk->inBinary(),
              'last_four'              => $lastFour,
              'account_type_id'        => $accountTypeID,
              'description'            => $updateData->{'description'},
              'billing_address_id'     => $billingAddressID,
              'last_updated'           => new PlugNPay::Sys::Time()->nowInFormat('iso')
            });
          }

          $self->{'paymentSourceID'} = $paymentSourceID;
        };
      } elsif ($accountTypeID    != $self->{'accountTypeID'}    ||
               $billingAddressID != $self->{'billingAddressID'} ||
               $updateData->{'description'} ne $self->{'description'}) {
        # do an update on the row
        eval {
          $paymentSourceID = $self->_doesPaymentSourceDataExist($self->{'customerID'}, {
            'type'             => $type->getPaymentTypeID(),
            'token'            => $tk->inBinary(),
            'billingAddressID' => $billingAddressID,
            'accountTypeID'    => $accountTypeID
          });

          if (!$paymentSourceID) {
            $self->_updatePaymentSource({
              'account_type_id'    => $accountTypeID,
              'billing_address_id' => $billingAddressID,
              'description'        => $updateData->{'description'},
              'last_updated'           => new PlugNPay::Sys::Time()->nowInFormat('iso')
            });
          } else {
            $self->{'paymentSourceID'} = $paymentSourceID;
          }
        };
      }
    }
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'    => $@,
        'function' => 'updatePaymentSource'
      });

      push (@errorMsg, 'Error while attempting to update payment source.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

####################################
# Subroutine: _insertPaymentSource
# ----------------------------------
# Description:
#   Inserts a payment source
sub _insertPaymentSource {
  my $self = shift;
  my $data = shift || {};

  my @fields = keys %{$data};
  my @values = values %{$data};
  my @params = map { '?' } @fields;

  my $sql = 'INSERT INTO customer_payment_source (' . join(',', @fields) . ') VALUES ( ' . join(',', @params) . ' )';

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->executeOrDie('merchant_cust', $sql, \@values)->{'sth'};
  return $sth->{'mysql_insertid'};
}

#########################################
# Subroutine: _updatePaymentSource
# ---------------------------------------
# Description:
#   Updates a payment source where the
#   token was not changed
sub _updatePaymentSource {
  my $self = shift;
  my $data = shift || {};

  my @params = map { $_ . ' = ?' } keys %{$data};
  my @values = values %{$data};

  my $sql = 'UPDATE customer_payment_source SET ' . join(',', @params) . ' WHERE id = ?';
  push (@values, $self->{'paymentSourceID'});

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('merchant_cust', $sql, \@values);
}

#########################################
# Subroutine: deletePaymentSource
# ---------------------------------------
# Description:
#   Deletes a payment source from a 
#   customers records.
sub deletePaymentSource {
  my $self = shift;
  my $paymentSourceID = shift || $self->{'paymentSourceID'};

  my $status = new PlugNPay::Util::Status(1);
  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM customer_payment_source
       WHERE id = ?/, [$paymentSourceID]);
  };

  if ($@) {
    $self->_log({
      'error'           => $@,
      'function'        => 'deletePaymentSource',
      'paymentSourceID' => $paymentSourceID
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete payment source.');
  }

  return $status;
}

############################################
# Subroutine: deleteCustomerPaymentSources
# ------------------------------------------
# Description:
#   Deletes all customer payment sources.
sub deleteCustomerPaymentSources {
  my $self = shift;
  my $customerID = shift || $self->{'customerID'};

  my $status = new PlugNPay::Util::Status(1);
  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM customer_payment_source
        WHERE customer_id = ?/, [$customerID]);
  };

  if ($@) {
    $self->_log({
      'error'      => $@,
      'function'   => 'deleteCustomerPaymentSources',
      'customerID' => $customerID
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete all customer payment sources.');
  }

  return $status;
}

#############################################
# Subroutine: _doesPaymentSourceDataExist
# -------------------------------------------
# Description:
#   Checks to see if the payment source
#   already exist in the customer's records
sub _doesPaymentSourceDataExist {
  my $self = shift;
  my $customerID = shift;
  my $paymentSourceData = shift;

  my $paymentSourceID;

  my $dbs = new PlugNPay::DBConnection();
  if ($paymentSourceData->{'type'} =~ /card/i) {
    my $params =[
      $paymentSourceData->{'token'},
      $paymentSourceData->{'expirationMonth'},
      $paymentSourceData->{'expirationYear'},
      $paymentSourceData->{'billingAddressID'},
      $customerID
    ];

    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id
        FROM customer_payment_source
        WHERE token = ?
        AND expiration_month = ?
        AND expiration_year = ?
        AND billing_address_id = ?
        AND customer_id = ?/, $params, {})->{'result'};
    if (@{$rows} > 0) {
      $paymentSourceID = $rows->[0]{'id'};
    }
  } else {
    my $params = [
      $paymentSourceData->{'token'},
      $paymentSourceData->{'billingAddressID'},
      $paymentSourceData->{'accountTypeID'},
      $customerID
    ];

    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id
        FROM customer_payment_source
        WHERE token = ?
        AND billing_address_id = ?
        AND account_type_id = ?
        AND customer_id = ?/, $params, {})->{'result'};
    if (@{$rows} > 0) {
      $paymentSourceID = $rows->[0]{'id'};
    }
  }

  return $paymentSourceID;
}

sub isBillingAddressUsed {
  my $self = shift;
  my $billingAddressID = shift;
  
  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM customer_payment_source
        WHERE billing_address_id = ?/, [$billingAddressID], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'isBillingAddressUsed'
    });
  }
  
  return $count;
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getPaymentSourceListSize {
  my $self = shift;
  my $customerID = shift; 

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM customer_payment_source
        WHERE customer_id = ?/, [$customerID], {})->{'result'};
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

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_paymentsource' });
  $logger->log($logInfo);
}

1;
