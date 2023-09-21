package PlugNPay::Merchant::Customer::Link;

use strict;
use PlugNPay::Merchant;
use PlugNPay::Util::Hash;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Merchant::Proxy;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::RandomString;
use PlugNPay::Merchant::Customer;
use PlugNPay::Membership::Profile;
use PlugNPay::GatewayAccount::Services;
use PlugNPay::Merchant::Customer::Phone;
use PlugNPay::Membership::Plan::Settings;
use PlugNPay::Merchant::Customer::Address;
use PlugNPay::Merchant::Customer::Settings;
use PlugNPay::Membership::PasswordManagement;
use PlugNPay::Merchant::Customer::Phone::Type;
use PlugNPay::Merchant::Customer::Phone::Expose;
use PlugNPay::Merchant::Customer::Address::Expose;
use PlugNPay::Membership::Plan::PasswordDigestType;

####################################################
# Module: Merchant::Customer::Link
# --------------------------------------------------
# Description:
#   Link of the customer and the merchant. The 
#   username is stored in this link object since 
#   the same customer can contain a different 
#   username under a different merchant.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  # input the initializing merchant acct
  my $merchant = shift;
  if ($merchant) {
    $self->setMerchantID($merchant);
  }

  return $self;
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

sub setMerchantID {
  my $self = shift;
  my $merchant = shift;

  if ($merchant !~ /^[0-9]+$/) {
    $merchant = new PlugNPay::Merchant($merchant)->getMerchantID();
  }

  # set proxy
  my $merchantDB = new PlugNPay::Merchant::Proxy($merchant);
  $self->{'merchantDatabaseID'} = $merchantDB;
  $self->{'merchantID'} = $merchant;
}

sub getMerchantID {
  my $self = shift;
  return $self->{'merchantID'};
}

sub setMerchantDatabaseID {
  my $self = shift;
  my $merchantDatabaseID = shift;
  $self->{'merchantDatabaseID'} = $merchantDatabaseID;
}

sub getMerchantDatabaseID {
  my $self = shift;
  return $self->{'merchantDatabaseID'};
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

sub setUsername {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return $self->{'username'};
}

sub setName {
  my $self = shift;
  my $name = shift;
  $self->{'name'} = $name;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub setHashedPassword {
  my $self = shift;
  my $hashedPassword = shift;
  $self->{'hashedPassword'} = $hashedPassword;
}

sub getHashedPassword {
  my $self = shift;
  return $self->{'hashedPassword'};
}

sub setPasswordDigestTypeID {
  my $self = shift;
  my $passwordDigestTypeID = shift;
  $self->{'passwordDigestTypeID'} = $passwordDigestTypeID;
}

sub getPasswordDigestTypeID {
  my $self = shift;
  return $self->{'passwordDigestTypeID'};
}

sub setDefaultAddressID {
  my $self = shift;
  my $defaultAddressID = shift;
  $self->{'defaultAddressID'} = $defaultAddressID;
}

sub getDefaultAddressID {
  my $self = shift;
  return $self->{'defaultAddressID'};
}

sub setDefaultPhoneID {
  my $self = shift;
  my $phoneID = shift;
  $self->{'defaultPhoneID'} = $phoneID;
}

sub getDefaultPhoneID {
  my $self = shift;
  return $self->{'defaultPhoneID'};
}

sub setDefaultFaxID {
  my $self = shift;
  my $faxID = shift;
  $self->{'defaultFaxID'} = $faxID;
}

sub getDefaultFaxID {
  my $self = shift;
  return $self->{'defaultFaxID'};
}

sub loadMerchantCustomers {
  my $self = shift;
  my $merchantDBID = shift || $self->{'merchantDatabaseID'};

  my $customers = [];

  my @values = ();
  my $sql = q/SELECT id,
                     merchant_id,
                     customer_id,
                     username,
                     name,
                     hashed_password,
                     default_address_id,
                     default_phone_id,
                     default_fax_id
              FROM merchant_customer_link
              WHERE merchant_id = ?
              ORDER BY id ASC/;

  push (@values, $merchantDBID);

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
        my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
        $merchantCustomer->_setMerchantCustomerDataFromRow($row);
        push (@{$customers}, $merchantCustomer); 
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadMerchantCustomers'
    });
  }

  return $customers;
}

sub loadMerchantCustomer {
  my $self = shift;
  my $linkID = shift || $self->{'merchantCustomerLinkID'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               merchant_id,
               customer_id,
               username,
               name,
               hashed_password,
               password_digest_type_id,
               default_address_id,
               default_phone_id,
               default_fax_id
        FROM merchant_customer_link
        WHERE id = ?/, [$linkID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setMerchantCustomerDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadMerchantCustomer'
    });
  }
}

sub _setMerchantCustomerDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->setMerchantID($row->{'merchant_id'});
  $self->{'merchantCustomerLinkID'} = $row->{'id'};
  $self->{'customerID'}             = $row->{'customer_id'};
  $self->{'username'}               = $row->{'username'};
  $self->{'name'}                   = $row->{'name'};
  $self->{'hashedPassword'}         = $row->{'hashed_password'};
  $self->{'passwordDigestTypeID'}   = $row->{'password_digest_type_id'};
  $self->{'defaultAddressID'}       = $row->{'default_address_id'};
  $self->{'defaultPhoneID'}         = $row->{'default_phone_id'};
  $self->{'defaultFaxID'}           = $row->{'default_fax_id'};
}

####################################
# Subroutine: saveMerchantCustomer
# ----------------------------------
# Description:
#   If the customer exists in the 
#   plugnpay customers table, then
#   save that ID to the merchant
#   customer link, otherwise insert.
sub saveMerchantCustomer {
  my $self = shift;
  my $customerData = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $status = new PlugNPay::Util::Status(1);
  
  my $errorMsg;
  eval {
    $dbs->begin('merchant_cust');

    my $customer = new PlugNPay::Merchant::Customer();
    my $customerSaveStatus = $customer->saveCustomer({
      'email' => $customerData->{'email'}
    });

    if (!$customerSaveStatus) {
      $errorMsg = $customerSaveStatus->getError();
      die;
    }

    # use the customer ID that given back.
    my $saveLinkStatus = $self->_saveMerchantCustomer({
      'username'  => $customerData->{'username'},
      'name'      => $customerData->{'name'},
      'password'  => $customerData->{'password'},
      'addresses' => $customerData->{'addresses'},
      'phones'    => $customerData->{'phones'} 
    }, $customer->getCustomerID(), $self->{'merchantDatabaseID'});
    if (!$saveLinkStatus) {
      $errorMsg = $saveLinkStatus->getError();
      die;
    }

    $dbs->commit('merchant_cust');
  };

  if ($@) {
    $dbs->rollback('merchant_cust');
    if (!$errorMsg) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_link '});
      $logger->log({
        'function'     => 'saveMerchantCustomer',
        'error'        => $@,
        'customerData' => $customerData,
        'merchantID'   => $self->{'merchantID'},
        'merchantDB'   => $self->{'merchantDBID'}
      });

      $errorMsg = 'Failed to save merchant customer.';
    }

    $status->setFalse();
    $status->setError($errorMsg);
  }

  return $status;
}

######################################
# Subroutine: _saveMerchantCustomer
# ------------------------------------
# Description:
#   Saves the link to the database.
sub _saveMerchantCustomer {
  my $self = shift;
  my $data = shift;
  my $customerID = shift;
  my $merchantDBID = $self->{'merchantDatabaseID'};

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');

    # does the customer already exist for the merchant
    if ($self->isMerchantCustomer($customerID, $merchantDBID)) {
      push (@errorMsg, 'Customer email already exists.');
      return; # return because it doesn't make sense to attempt anything
    }

    my $username;
    my $maxUsernameLength = $self->_getMaxUsernameLength(new PlugNPay::Merchant($merchantDBID)->getMerchantUsername());
    if ($data->{'username'}) {
      $username = lc $data->{'username'};
      if (!$username || $username !~ /^[a-z0-9\.\@\-\_\!]+$/ || $username =~ /^\d+$/) {
        push (@errorMsg, 'Invalid characters in username. Usernames must only include these characters: [ A-Z, 0-9, @, ., -, _, ! ]');
      } elsif (length($username) > $maxUsernameLength) {
        push (@errorMsg, 'Username exceeds maximum limitation of characters: ' . $maxUsernameLength);
      }

      if (@errorMsg == 0) {
        # only perform this check if there are no previous errors..
        if ($self->usernameExists($username, $merchantDBID)) {
          push (@errorMsg, 'Username already exists.');
        }
      }
    } else {
      $username = lc $self->_generateUsername($maxUsernameLength);
    }

    # if no errors, continue
    if (@errorMsg == 0) {
      my $name = lc $data->{'name'} || '';
      my $password = '';
      if (!$data->{'password'}) {
        $password = new PlugNPay::Util::RandomString()->randomAlphaNumeric(12);
      } else {
        $password = $data->{'password'};
      }

      my ($hashedPassword, $digestTypeID);
      my $globalSettings = new PlugNPay::Merchant::Customer::Settings();
      if ($globalSettings->getSetting('passwordDigest') =~ /bcrypt/i) {
        my $hasher = new PlugNPay::Util::Hash();
        $hasher->add($password);
        $hashedPassword = $hasher->bcrypt();

        my $digestType = new PlugNPay::Membership::Plan::PasswordDigestType();
        $digestType->loadDigestID('bcrypt');
        $digestTypeID = $digestType->getDigestID();
      }

      my $sth = $dbs->executeOrDie('merchant_cust',
        q/INSERT INTO merchant_customer_link
          ( merchant_id, 
            customer_id, 
            username,
            name,
            hashed_password,
            password_digest_type_id )
          VALUES (?,?,?,?,?,?)/, [$merchantDBID, $customerID, $username, $name, $hashedPassword, $digestTypeID])->{'sth'};
      my $insertedLinkID = $sth->{'mysql_insertid'};
      $self->{'customerID'} = $customerID;
      $self->{'username'} = $username;

      if (ref ($data->{'addresses'}) eq 'ARRAY') {
        foreach my $customerAddress (@{$data->{'addresses'}}) {
          my $exposeAddress = new PlugNPay::Merchant::Customer::Address::Expose();
          my $saveExposeStatus = $exposeAddress->saveExposedAddress($customerAddress, 
                                                                    $insertedLinkID,
                                                                    { 'makeDefault' => $customerAddress->{'makeDefault'} });
          if (!$saveExposeStatus) {
            push (@errorMsg, $saveExposeStatus->getError());
            last;
          }
        }
      }

      if (ref ($data->{'phones'}) eq 'ARRAY') {
        foreach my $customerPhone (@{$data->{'phones'}}) {
          my $exposePhone = new PlugNPay::Merchant::Customer::Phone::Expose();
          my $saveExposeStatus = $exposePhone->saveExposedPhone($customerPhone,
                                                                $insertedLinkID,
                                                                { 'makeDefault' => $customerPhone->{'makeDefault'} });
          if (!$saveExposeStatus) {
            push (@errorMsg, $saveExposeStatus->getError());
            last;
          }
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      $self->_log({
        'function'     => '_saveMerchantCustomer',
        'error'        => $@,
        'merchantDB'   => $merchantDBID
      });

      push (@errorMsg, 'Error while attempting to save customer.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

######################################
# Subroutine: updateMerchantCustomer
# ------------------------------------
# Description:
#   Updates the link of merchant and
#   customer. The link merely changes
#   the customer ID column. Expects
#   the customer link to be loaded
#   in current object.
sub updateMerchantCustomer {
  my $self = shift;
  my $updateData = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');

    # load the original customer
    my $customer = new PlugNPay::Merchant::Customer();

    # customer will contain an ID each route
    if (exists $updateData->{'email'}) {
      # could be different underlying customer, so call save
      my $saveCustomerStatus = $customer->saveCustomer({ 'email' => $updateData->{'email'} });
      if (!$saveCustomerStatus) {
        push (@errorMsg, $saveCustomerStatus->getError());
        return; # pointless to continue
      }
    } else {
      # if no update data for email exists, the underlying customer is the same
      $customer->loadCustomer($self->{'customerID'});
    }

    # if these are different, perform a check if the ID is already in the merchant's link table.
    if ($self->{'customerID'} != $customer->getCustomerID()) {
      if ($self->isMerchantCustomer($customer->getCustomerID())) {
        push (@errorMsg, 'Customer already exists in records.');
        return; # resistance is futile
      }
    }

    # update username if necessary
    my $username = $self->{'username'};
    if (exists $updateData->{'username'}) {
      $username = lc $updateData->{'username'};

      # check if username is different
      if ($username ne $self->{'username'}) {
        my $maxUsernameLength = $self->_getMaxUsernameLength(new PlugNPay::Merchant($self->{'merchantDatabaseID'})->getMerchantUsername());
        if (!$username || $username !~ /^[a-z0-9\.\@\-\_\!]+$/ || $username =~ /^\d+$/) {
          push (@errorMsg, 'Invalid characters in username. Usernames must only include these characters: [ A-Z, 0-9, @, ., -, _, ! ]');
        } elsif (length($username) > $maxUsernameLength) {
          push (@errorMsg, 'Username exceeds maximum limitation of characters: ' . $maxUsernameLength);
        }

        if (@errorMsg == 0) {
          if ($self->usernameExists($username, $self->{'merchantDatabaseID'})) {
            push (@errorMsg, 'Username already exists.');
          }
        }
      }
    }

    # if no errors.. go forth
    if (@errorMsg == 0) {
      my $name;
      if (exists $updateData->{'name'}) {
        $name = lc $updateData->{'name'};
      } else {
        $name = $self->{'name'};
      }

      # update customer password #
      my ($hashedPassword, $digestTypeID);
      my $changedPassword = 0;

      # if password is not sent in, or it's not defined, reuse the same.
      if (exists $updateData->{'password'}) {
        if ($updateData->{'password'}) {
          $changedPassword = 1;

          my $globalSettings = new PlugNPay::Merchant::Customer::Settings();
          if ($globalSettings->getSetting('passwordDigest') =~ /bcrypt/i) {
            my $hasher = new PlugNPay::Util::Hash();
            $hasher->add($updateData->{'password'});
            $hashedPassword = $hasher->bcrypt();

            my $digestType = new PlugNPay::Membership::Plan::PasswordDigestType();
            $digestType->loadDigestID('bcrypt');
            $digestTypeID = $digestType->getDigestID();
          }
        } else {
          $hashedPassword = $self->{'hashedPassword'};
          $digestTypeID = $self->{'passwordDigestTypeID'};
        }
      } else {
        $hashedPassword = $self->{'hashedPassword'};
        $digestTypeID = $self->{'passwordDigestTypeID'};
      }

      # If updating primary address #
      my $updateAddressID;
      if (exists $updateData->{'defaultAddressID'} && $updateData->{'defaultAddressID'}) {
        my $exposeAddress = new PlugNPay::Merchant::Customer::Address::Expose();
        $exposeAddress->loadByLinkIdentifier($updateData->{'defaultAddressID'}, $self->{'merchantCustomerLinkID'});
        if (!$exposeAddress->getLinkID()) {
          push (@errorMsg, 'Invalid address identifier.');
        } else {
          $updateAddressID = $exposeAddress->getLinkID();
        }
      } elsif (exists $updateData->{'defaultAddressID'}) {
        $updateAddressID = undef;
      } else {
        $updateAddressID = $self->{'defaultAddressID'}; 
      }

      # If updating primary phone #
      my $updatePhoneID;
      if (exists $updateData->{'defaultPhoneID'} && $updateData->{'defaultPhoneID'}) {
        my $exposePhone = new PlugNPay::Merchant::Customer::Phone::Expose();
        $exposePhone->loadByLinkIdentifier($updateData->{'defaultPhoneID'}, $self->{'merchantCustomerLinkID'});
        if (!$exposePhone->getLinkID()) {
          push (@errorMsg, 'Invalid phone identifier.');
        } else {
          my $phone = new PlugNPay::Merchant::Customer::Phone();
          $phone->loadPhone($exposePhone->getPhoneID());

          my $type = new PlugNPay::Merchant::Customer::Phone::Type();
          $type->loadType($phone->getGeneralTypeID());
 
          if (uc ($type->getType()) eq 'FAX') {
            push (@errorMsg, 'Invalid phone type for default phone.');
          } else {
            $updatePhoneID = $exposePhone->getLinkID();
          }
        }
      } elsif (exists $updateData->{'defaultPhoneID'}) {
        $updatePhoneID = undef;
      } else {
        $updatePhoneID = $self->{'defaultPhoneID'};
      }

      # If updating primary fax #
      my $updateFaxID;
      if (exists $updateData->{'defaultFaxID'} && $updateData->{'defaultFaxID'}) {
        my $exposeFax = new PlugNPay::Merchant::Customer::Phone::Expose();
        $exposeFax->loadByLinkIdentifier($updateData->{'defaultFaxID'}, $self->{'merchantCustomerLinkID'});
        if (!$exposeFax->getLinkID()) {
          push (@errorMsg, 'Invalid fax identifier.');
        } else {
          my $fax = new PlugNPay::Merchant::Customer::Phone();
          $fax->loadPhone($exposeFax->getPhoneID());

          my $type = new PlugNPay::Merchant::Customer::Phone::Type();
          $type->loadType($fax->getGeneralTypeID());
          if (uc ($type->getType()) ne 'FAX') {
            push (@errorMsg, 'Invalid phone type for default fax.');
          } else {
            $updateFaxID = $exposeFax->getLinkID();
          }
        }
      } elsif (exists $updateData->{'defaultFaxID'}) {
        $updateFaxID = undef;
      } else {
        $updateFaxID = $self->{'defaultFaxID'};
      }

      if (@errorMsg == 0) {
        my $params = [
          $username,
          $name,
          $hashedPassword,
          $digestTypeID,
          $customer->getCustomerID(),
          $updateAddressID,
          $updatePhoneID,
          $updateFaxID,
          $self->{'merchantCustomerLinkID'}
        ];

        $dbs->executeOrDie('merchant_cust',
          q/UPDATE merchant_customer_link
            SET username = ?,
                name = ?,
                hashed_password = ?,
                password_digest_type_id = ?,
                customer_id = ?,
                default_address_id = ?,
                default_phone_id = ?,
                default_fax_id = ?
            WHERE id = ?/, $params);

        if ($changedPassword) {
          my $services = new PlugNPay::GatewayAccount::Services(new PlugNPay::Merchant($self->{'merchantDatabaseID'})->getMerchantUsername());
          if ($services->getRefresh()) {
            my $profile = new PlugNPay::Membership::Profile();
            my $billingProfiles = $profile->loadBillingProfiles($self->{'merchantCustomerLinkID'});
            if (@{$billingProfiles} > 0) {
              # if customer updates their password, go update the passwords on the remote servers
              my $passwordManagement = new PlugNPay::Membership::PasswordManagement();
              foreach my $billingProfile (@{$billingProfiles}) {
                $passwordManagement->manageCustomer($billingProfile);
              }
            }
          }
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_link' });
      $logger->log({
        'function'               => 'updateMerchantCustomer',
        'error'                  => $@,
        'merchantCustomerLinkID' => $self->{'merchantCustomerLinkID'}
      });

      push (@errorMsg, 'Error while attempting to update customer.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

#######################################
# Subroutine: removeMerchantCustomer
# -------------------------------------
# Description:
#   Removes a link between a merchant
#   and customer.
sub removeMerchantCustomer {
  my $self = shift;
  my $customerID = shift || $self->{'customerID'};
  my $merchantDBID = shift || $self->{'merchantDatabaseID'};

  my $status = new PlugNPay::Util::Status(1);

  eval {
    # load the profiles first, that way when the customer is deleted, we can 
    # still remove them from the remote sites.
    my $profile = new PlugNPay::Membership::Profile();
    my $billingProfiles = $profile->loadBillingProfiles($self->{'merchantCustomerLinkID'});

    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM merchant_customer_link
        WHERE customer_id = ?
        AND merchant_id = ?/, [$customerID, $merchantDBID]);

    # password management
    my $gatewayAccount = new PlugNPay::Merchant($merchantDBID)->getMerchantUsername();
    my $services = new PlugNPay::GatewayAccount::Services($gatewayAccount);
    if ($services->getRefresh()) {
      if (@{$billingProfiles} > 0) {
        my $passwordManagement = new PlugNPay::Membership::PasswordManagement();
        foreach my $billingProfile (@{$billingProfiles}) {
          my $paymentPlanSettings = new PlugNPay::Membership::Plan::Settings();
          $paymentPlanSettings->loadPlanSettings($billingProfile->getPlanSettingsID());
          $passwordManagement->removeCustomer($self->{'username'}, 
                                              $paymentPlanSettings->getPlanID());
        }
      }
    }

    # try to clean up customers, must check to see if customer exists
    # for another merchant..
    if (!$self->_isCustomerExposed($customerID)) {
      my $customer = new PlugNPay::Merchant::Customer();
      $customer->deleteCustomer($customerID);
    }
  };

  if ($@) {
    $self->_log({
      'function'   => 'removeMerchantCustomer',
      'error'      => $@,
      'merchantID' => $self->{'merchantID'},
      'merchantDB' => $merchantDBID,
      'customerID' => $customerID
    });

    $status->setFalse();
    $status->setError('Error while attempting to remove customer.');
  }

  return $status;
}

sub isMerchantCustomer {
  my $self = shift;
  my $customerID = shift;
  my $merchantDBID = shift || $self->{'merchantDatabaseID'};

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM merchant_customer_link
        WHERE customer_id = ?
        AND merchant_id = ?/, [$customerID, $merchantDBID], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'isMerchantCustomer'
    });
  }

  return $count;
}

sub _isCustomerExposed {
  my $self = shift;
  my $customerID = shift;

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM merchant_customer_link
        WHERE customer_id = ?/, [$customerID], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => '_isCustomerExposed'
    });
  }

  return $count;
}

sub usernameExists {
  my $self = shift;
  my $username = lc shift;
  my $merchantDBID = shift || $self->{'merchantDatabaseID'};

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM merchant_customer_link
        WHERE merchant_id = ?
        AND username = ?/, [$merchantDBID, $username], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'username' => $username,
      'function' => 'usernameExists'
    });
  }

  return $exists;
}

sub _generateUsername {
  my $self = shift;
  my $maxLength = shift;
  my $merchantDBID = shift || $self->{'merchantDatabaseID'};

  my $randomUsername = 'customer_' . lc new PlugNPay::Util::RandomString()->randomAlphaNumeric($maxLength - 9);
  if ($self->usernameExists($randomUsername, $merchantDBID)) {
    $randomUsername = $self->_generateUsername($maxLength, $merchantDBID);
  }
  return $randomUsername;
}

sub _getMaxUsernameLength {
  my $self = shift;
  my $merchant = shift;

  my $lowestMax;
  if (ref ($merchant) eq 'ARRAY') {
    if (@{$merchant} > 0) {
      foreach my $merchantName (@{$merchant}) {
        my $services = new PlugNPay::GatewayAccount::Services($merchantName);
        if (!$lowestMax) {
          $lowestMax = $services->getMaxUsernameLength();
        } else {
          if ($lowestMax > $services->getMaxUsernameLength()) {
            $lowestMax = $services->getMaxUsernameLength();
          }
        }
      }
    }
  } else {
    my $services = new PlugNPay::GatewayAccount::Services($merchant);
    $lowestMax = $services->getMaxUsernameLength();
  }

  if (!$lowestMax) {
    $lowestMax = 24;
  }

  return $lowestMax;
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getMerchantCustomerListSize {
  my $self = shift;
  my $merchantDBID = shift || $self->{'merchantDatabaseID'};

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM merchant_customer_link
        WHERE merchant_id = ?/, [$merchantDBID], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'getMerchantCustomerListSize'
    });
  }

  return $count;
}

sub loadCustomerIDByUsername {
  my $self = shift;
  my $username = lc shift;
  my $merchantDBID = shift || $self->{'merchantDatabaseID'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               merchant_id,
               customer_id,
               username,
               name,
               hashed_password,
               password_digest_type_id,
               default_address_id,
               default_phone_id,
               default_fax_id
        FROM merchant_customer_link
        WHERE merchant_id = ?
        AND username = ?/, [$merchantDBID, $username], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setMerchantCustomerDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadCustomerIDByUsername'
    });
  }
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_link' });
  $logger->log($logInfo);
}

1;
