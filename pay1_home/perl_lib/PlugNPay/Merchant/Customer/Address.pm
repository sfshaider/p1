package PlugNPay::Merchant::Customer::Address;

use strict;
use PlugNPay::Country;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Country::State;
use PlugNPay::Logging::DataLog;

########################################
# Module: Merchant::Customer::Address
# --------------------------------------
# Description:
#   This contains information about the
#   customer's address.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
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

sub setCustomerID {
  my $self = shift;
  my $customerID = shift;
  $self->{'customerID'} = $customerID;
}

sub getCustomerID {
  my $self = shift;
  return $self->{'customerID'};
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

sub setLine1 {
  my $self = shift;
  my $line1 = shift;
  $self->{'line1'} = $line1;
}

sub getLine1 {
  my $self = shift;
  return $self->{'line1'};
}

sub setLine2 {
  my $self = shift;
  my $line2 = shift;
  $self->{'line2'} = $line2;
}

sub getLine2 {
  my $self = shift;
  return $self->{'line2'};
}

sub setCity {
  my $self = shift;
  my $city = shift;
  $self->{'city'} = $city;
}

sub getCity {
  my $self = shift;
  return $self->{'city'};
}

sub setStateProvince {
  my $self = shift;
  my $stateProvince = shift;
  $self->{'state'} = $stateProvince;
}

sub getStateProvince {
  my $self = shift;
  return $self->{'state'};
}

sub setPostalCode {
  my $self = shift;
  my $postalCode = shift;
  $self->{'postalCode'} = $postalCode;
}

sub getPostalCode {
  my $self = shift;
  return $self->{'postalCode'};
}

sub setCountry {
  my $self = shift;
  my $country = shift;
  $self->{'country'} = $country;
}

sub getCountry {
  my $self = shift;
  return $self->{'country'};
}

sub setCompany {
  my $self = shift;
  my $company = shift;
  $self->{'company'} = $company;
}

sub getCompany {
  my $self = shift;
  return $self->{'company'};
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

#############################################
# Subroutine: loadAddresses
# ----------------------------------
# Description:
#   THIS IS NOT USED PUBLICLY.
#   See Merchant::Customer::Address::Expose
#   to load addresses for a given merchant.
#   This loads ALL of a customer's addresses.
sub loadAddresses {
  my $self = shift;
  my $customerID = shift;

  my $addresses = [];

  my @values = ();
  my $sql = q/SELECT id,
                     customer_id,
                     name,
                     line_1,
                     line_2,
                     city,
                     state_province,
                     postal_code,
                     country,
                     company
              FROM customer_address
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
        my $address = new PlugNPay::Merchant::Customer::Address();
        $address->_setAddressDataFromRow($row);
        push (@{$addresses}, $address);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadAddresses'
    });
  }

  return $addresses;
}

sub loadAddress {
  my $self = shift;
  my $addressID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               customer_id,
               name,
               line_1,
               line_2,
               city,
               state_province,
               postal_code,
               country,
               company
        FROM customer_address
        WHERE id = ?/, [$addressID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setAddressDataFromRow($rows->[0]);
    } 
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadAddress'
    });   
  }
}

sub _setAddressDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'addressID'}  = $row->{'id'};
  $self->{'customerID'} = $row->{'customer_id'};
  $self->{'name'}       = $row->{'name'};
  $self->{'line1'}      = $row->{'line_1'};
  $self->{'line2'}      = $row->{'line_2'};
  $self->{'city'}       = $row->{'city'};
  $self->{'state'}      = $row->{'state_province'};
  $self->{'postalCode'} = $row->{'postal_code'};
  $self->{'country'}    = $row->{'country'};
  $self->{'company'}    = $row->{'company'};
}

############################################
# Subroutine: saveAddress
# ------------------------------------------
# Description:
#   Saves an address entry for a customer. 
#   This subroutine checks to see if the 
#   address exists in the table first.
sub saveAddress {
  my $self = shift;
  my $customerID = shift;
  my $data = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $formattedData = $self->_formatAddressData({
    'name'       => $data->{'name'},
    'line1'      => $data->{'line1'},
    'line2'      => $data->{'line2'},
    'city'       => $data->{'city'},
    'state'      => $data->{'state'},
    'postalCode' => $data->{'postalCode'},
    'country'    => $data->{'country'},
    'company'    => $data->{'company'}
  });

  my $name = $formattedData->{'name'};
  my $company = $formattedData->{'company'};

  my $line1 = $formattedData->{'line1'};
  if (!$line1) {
    push (@errorMsg, 'Line 1 cannot be blank.');
  }

  my $line2 = $formattedData->{'line2'};

  my $city = $formattedData->{'city'};
  if (!$city) {
    push (@errorMsg, 'City cannot be blank.');
  }

  # validate state
  my $state = $formattedData->{'state'};
  if (!$state) {
    push (@errorMsg, 'Invalid state.');
  }

  my $postalCode = $formattedData->{'postalCode'};
  if (!$postalCode) {
    push (@errorMsg, 'Postal code cannot be blank.');
  }

  # validate country
  my $country = $formattedData->{'country'};
  if (!$country) {
    push (@errorMsg, 'Invalid country.');
  }

  if (@errorMsg == 0) {
    eval {
      # if the address exists, set the row id, otherwise insert the id
      my $addressID = $self->_doesAddressDataExist($formattedData, $customerID);
      if (!$addressID) {
        my $params = [
          $customerID,
          $name,
          $line1,
          $line2,
          $city,
          $state,
          $postalCode,
          $country,
          $company
        ];

        my $dbs = new PlugNPay::DBConnection();
        my $sth = $dbs->executeOrDie('merchant_cust',
          q/INSERT INTO customer_address
            ( customer_id,
              name,
              line_1,
              line_2,
              city,
              state_province,
              postal_code,
              country,
              company )
            VALUES (?,?,?,?,?,?,?,?,?)/, $params)->{'sth'};
        $addressID = $sth->{'mysql_insertid'};
      }

      $self->{'addressID'} = $addressID;
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'function'   => 'saveAddress',
        'error'      => $@,
        'customerID' => $customerID
      });

      push (@errorMsg, 'Error while attempting to save customer address.');
    }
 
    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

###############################
# Subroutine: updateAddress
# -----------------------------
# Description:
#   Always will insert a new 
#   row into the address table
#   if the data is different.
#   Expects data to be loaded
#   in the current object.
sub updateAddress {
  my $self = shift;
  my $updateData = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $addressID = $self->{'addressID'};

  my $name       = exists $updateData->{'name'}       ? $updateData->{'name'}       : $self->{'name'};
  my $line1      = exists $updateData->{'line1'}      ? $updateData->{'line1'}      : $self->{'line1'};
  my $line2      = exists $updateData->{'line2'}      ? $updateData->{'line2'}      : $self->{'line2'};
  my $city       = exists $updateData->{'city'}       ? $updateData->{'city'}       : $self->{'city'};
  my $state      = exists $updateData->{'state'}      ? $updateData->{'state'}      : $self->{'state'};
  my $postalCode = exists $updateData->{'postalCode'} ? $updateData->{'postalCode'} : $self->{'postalCode'};
  my $country    = exists $updateData->{'country'}    ? $updateData->{'country'}    : $self->{'country'};
  my $company    = exists $updateData->{'company'}    ? $updateData->{'company'}    : $self->{'company'};

  my $formattedData = $self->_formatAddressData({
    'name'       => $name,
    'line1'      => $line1,
    'line2'      => $line2,
    'city'       => $city,
    'state'      => $state,
    'postalCode' => $postalCode,
    'country'    => $country,
    'company'    => $company
  });

  $name = $formattedData->{'name'};
  $company = $formattedData->{'company'};

  if (!$formattedData->{'line1'}) {
    push (@errorMsg, 'Line 1 cannot be blank.');
  }

  $line1 = $formattedData->{'line1'};
  $line2 = $formattedData->{'line2'};

  $city = $formattedData->{'city'};
  if (!$city) {
    push (@errorMsg, 'City cannot be blank.');
  }

  $state = $formattedData->{'state'};
  if (!$state) {
    push (@errorMsg, 'Invalid state.');
  }

  $postalCode = $formattedData->{'postalCode'};
  if (!$postalCode) {
    push (@errorMsg, 'Postal code cannot be blank.');
  }

  $country = $formattedData->{'country'};
  if (!$country) {
    push (@errorMsg, 'Invalid country.');
  }

  if (@errorMsg == 0) {
    # if any data is different, insert new row
    if ($name       ne $self->{'name'}       ||
        $line1      ne $self->{'line1'}      ||
        $line2      ne $self->{'line2'}      ||
        $city       ne $self->{'city'}       ||
        $state      ne $self->{'state'}      ||
        $postalCode ne $self->{'postalCode'} ||
        $country    ne $self->{'country'}    ||
        $company    ne $self->{'company'}) {

      eval {
        $addressID = $self->_doesAddressDataExist($formattedData, $self->{'customerID'});
        if (!$addressID) {
          my $params = [
            $name,
            $line1,
            $line2,
            $city,
            $state,
            $postalCode,
            $country,
            $company,
            $self->{'customerID'}
          ];

          my $dbs = new PlugNPay::DBConnection();
          my $sth = $dbs->executeOrDie('merchant_cust',
            q/INSERT INTO customer_address
              ( name,
                line_1,
                line_2,
                city,
                state_province,
                postal_code,
                country,
                company,
                customer_id )
              VALUES (?,?,?,?,?,?,?,?,?)/, $params)->{'sth'};
          $addressID = $sth->{'mysql_insertid'};
        }

        $self->{'addressID'} = $addressID;
      };
    }
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'     => $@,
        'function'  => 'updateAddress',
        'addressID' => $self->{'addressID'}
      });

      push (@errorMsg, 'Error while attempting to update address.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

#######################################
# Subroutine: deleteAddress
# -------------------------------------
# Description:
#   Deletes an entry from the address
#   table if the address.
sub deleteAddress {
  my $self = shift;
  my $addressID = shift || $self->{'addressID'};

  my $status = new PlugNPay::Util::Status(1);

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM customer_address
        WHERE id = ?/, [$addressID]);
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_address' });
    $logger->log({
      'error'     => $@,
      'function'  => 'deleteAddress',
      'addressID' => $addressID 
    });

    $status->setFalse();
    $status->setError('Failed to delete customer address.');
  }

  return $status;
}

#########################################
# Subroutine: _formatAddressData
# ---------------------------------------
# Description:
#   Inputs a hash of address data and 
#   neatly normalizes it. Returns hash of 
#   formatted data with same key names.
sub _formatAddressData {
  my $self = shift;
  my $addressData = shift;

  my $name       = lc $addressData->{'name'} || '';
  my $line1      = lc $addressData->{'line1'};
  my $line2      = lc $addressData->{'line2'};
  my $city       = lc $addressData->{'city'};
  my $state      = lc $addressData->{'state'};
  my $postalCode = lc $addressData->{'postalCode'};
  my $country    = lc $addressData->{'country'};
  my $company    = lc $addressData->{'company'} || '';

  $name =~ s/[^a-z0-9 \.]//g;

  $line1 =~ s/[^a-z0-9 \.\,]//g;
  $line1 =~ s/ +/ /g;
  $line1 =~ s/ +$//g;

  $line2 =~ s/[^a-z0-9 \.\,\#]//g;
  $line2 =~ s/ +/ /g;
  $line2 =~ s/ +$//g;

  # capture number, name of street, last word is address suffix
  if ($line1 =~ /^([a-z0-9]+) ([a-z0-9\.\, ]*) ([a-z0-9\.\,]+?$)/) {
    $line1 = $1 . ' ' . $2 . ' ' . $3;
  }

  $city =~ s/ +$//g;
  $city =~ s/ +/ /g;

  $state =~ s/ +$//g;
  $state =~ s/ +/ /g;

  my $stateObj = new PlugNPay::Country::State($state);
  if ($stateObj->exists()) {
    $state = lc $stateObj->getState();
  } else {
    $state = undef;
  }

  $postalCode =~ s/ +$//g;
  $postalCode =~ s/ +/ /g;

  $country =~ s/ +$//g;
  $country =~ s/ +/ /g;

  my $countryObj = new PlugNPay::Country();
  if ($countryObj->exists($country)) {
    $country = lc $countryObj->getTwoLetter($country);
  } else {
    $country = undef;
  }

  $company =~ s/[^a-z0-9\_\-\&\'\" ]//g;

  return {
    'name'       => $name,
    'line1'      => $line1,
    'line2'      => $line2,
    'city'       => $city,
    'state'      => $state,
    'postalCode' => $postalCode,
    'country'    => $country,
    'company'    => $company
  };
}

###############################################
# Subroutine: _doesAddressDataExist
# ---------------------------------------------
# Description:
#   If the data exists in the address table it 
#   will return the ID of the row.
sub _doesAddressDataExist {
  my $self = shift;
  my $addressData = shift;
  my $customerID = shift;
  my $format = shift || undef;

  my $formattedAddressData = $addressData;
  if ($format) {
    $formattedAddressData = $self->_formatAddressData($addressData);
  }

  my $name       = lc $formattedAddressData->{'name'};
  my $line1      = lc $formattedAddressData->{'line1'};
  my $line2      = lc $formattedAddressData->{'line2'};
  my $city       = lc $formattedAddressData->{'city'};
  my $state      = lc $formattedAddressData->{'state'};
  my $postalCode = lc $formattedAddressData->{'postalCode'};
  my $country    = lc $formattedAddressData->{'country'};
  my $company    = lc $formattedAddressData->{'company'};

  my $params = [
    $name,
    $line1,
    $line2,
    $city,
    $state,
    $postalCode,
    $country,
    $company,
    $customerID
  ];

  my $dbs = new PlugNPay::DBConnection();
  my $rows = $dbs->fetchallOrDie('merchant_cust',
    q/SELECT id
      FROM customer_address
      WHERE name = ?
      AND line_1 = ?
      AND line_2 = ?
      AND city = ?
      AND state_province = ?
      AND postal_code = ?
      AND country = ?
      AND company = ?
      AND customer_id = ?/, $params, {})->{'result'};
  my $addressID;
  if (@{$rows} > 0) {
    $addressID = $rows->[0]{'id'};
  }

  return $addressID;
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getAddressListSize {
  my $self = shift;
  my $customerID = shift;

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM customer_address
        WHERE customer_id = ?/, [$customerID], {})->{'result'};
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

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_customer_address' });
  $logger->log($logInfo);
}

1;
