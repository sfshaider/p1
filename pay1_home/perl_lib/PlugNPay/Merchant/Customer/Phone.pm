package PlugNPay::Merchant::Customer::Phone;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::Merchant::Customer::Link;
use PlugNPay::Merchant::Customer::Phone::Type;

#############################################
# Module: Merchant::Customer::Phone
# -------------------------------------------
# Description:
#   A customer's phone record.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
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

sub setCustomerID {
  my $self = shift;
  my $customerID = shift;
  $self->{'customerID'} = $customerID;
}

sub getCustomerID {
  my $self = shift;
  return $self->{'customerID'};
}

sub setPhoneNumber {
  my $self = shift;
  my $phoneNumber = shift;
  $self->{'phoneNumber'} = $phoneNumber;
}

sub getPhoneNumber {
  my $self = shift;
  return $self->{'phoneNumber'};
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

sub setGeneralTypeID {
  my $self = shift;
  my $generalTypeID = shift;
  $self->{'generalTypeID'} = $generalTypeID;
}

sub getGeneralTypeID {
  my $self = shift;
  return $self->{'generalTypeID'};
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

############################################
# Subroutine: loadPhones
# ------------------------------------------
# Description:
#   THIS IS NOT USED PUBLICLY
#   Loads all the phone entrys for a given
#   customer.
sub loadPhones {
  my $self = shift;
  my $customerID = shift;

  my $phones = [];

  my @values = ();
  my $sql = q/SELECT id,
                     customer_id,
                     phone,
                     description,
                     general_type_id
              FROM customer_phone
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
        my $phone = new PlugNPay::Merchant::Customer::Phone();
        $phone->_setPhoneDataFromRow($row);
        push (@{$phones}, $phone);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadPhones'
    });
  }

  return $phones;
}

sub loadPhone {
  my $self = shift;
  my $phoneID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               customer_id,
               phone,
               description,
               general_type_id
        FROM customer_phone
        WHERE id = ?/, [$phoneID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setPhoneDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadPhone'
    });
  }
}

sub _setPhoneDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'phoneID'}       = $row->{'id'};
  $self->{'customerID'}    = $row->{'customer_id'};
  $self->{'phoneNumber'}   = $row->{'phone'};
  $self->{'description'}   = $row->{'description'};
  $self->{'generalTypeID'} = $row->{'general_type_id'};
}

##################################
# Subroutine: savePhone
# --------------------------------
# Description:
#   Saves a phone for a customer.
sub savePhone {
  my $self = shift;
  my $customerID = shift;
  my $data = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $phoneNumber = $data->{'phoneNumber'};
  $phoneNumber =~ s/[^0-9]//g;
  if (!$phoneNumber) {
    push (@errorMsg, 'Phone number cannot be blank.');
  }

  my $generalTypeID;
  if ($data->{'generalType'} !~ /^\d+$/) {
    my $type = new PlugNPay::Merchant::Customer::Phone::Type();
    $type->loadTypeID($data->{'generalType'});
    $generalTypeID = $type->getTypeID();
  } else {
    $generalTypeID = $data->{'generalType'};
  }

  if (!$generalTypeID) {
    push (@errorMsg, 'Invalid general type.');
  }

  my $description = $data->{'description'};

  eval {
    my $phoneID = $self->_doesPhoneDataExist({ 
      'phoneNumber' => $phoneNumber, 
      'description' => $description,
      'type'        => $generalTypeID
    }, $customerID);

    if (!$phoneID) {
      my $params = [
        $customerID,
        $phoneNumber,
        $description,
        $generalTypeID
      ];

      my $dbs = new PlugNPay::DBConnection();
      my $sth = $dbs->executeOrDie('merchant_cust',
       q/INSERT INTO customer_phone
         ( customer_id,
           phone,
           description,
           general_type_id )
         VALUES (?,?,?,?)/, $params)->{'sth'};
      $phoneID = $sth->{'mysql_insertid'};
    }

    $self->{'phoneID'} = $phoneID;
  };

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'      => $@,
        'function'   => 'savePhone',
        'customerID' => $customerID
      });

      push (@errorMsg, 'Error while attempting to save phone.');
    } 

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

################################
# Subroutine: updatePhone
# ------------------------------
# Description:
#   Updates a customer's phone
#   entry.
sub updatePhone {
  my $self = shift;
  my $updateData = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $phoneID = $self->{'phoneID'}; # already loaded from exposed

  my $phoneNumber = exists $updateData->{'phoneNumber'} ? $updateData->{'phoneNumber'} : $self->{'phoneNumber'};
  $phoneNumber =~ s/[^0-9]//g;
  if (!$phoneNumber) {
    push (@errorMsg, 'Phone number cannot be blank.');
  }

  my $generalTypeID;
  my $generalType = exists $updateData->{'generalType'} ? $updateData->{'generalType'} : $self->{'generalTypeID'};
  if ($generalType !~ /^\d+$/) {
    my $type = new PlugNPay::Merchant::Customer::Phone::Type();
    $type->loadTypeID($generalType);
    $generalTypeID = $type->getTypeID();
  } else {
    $generalTypeID = $generalType;
  }

  if (!$generalTypeID) {
    push (@errorMsg, 'Invalid general type.');
  }

  my $description = exists $updateData->{'description'} ? $updateData->{'description'} : $self->{'description'};

  # check if the data hasn't changed
  if ($self->{'phoneNumber'}   ne $phoneNumber
   || $self->{'generalTypeID'} != $generalTypeID 
   || $self->{'description'}   ne $description) {
    # if any data is different from this, or any row in the table, insert a new row
    eval {
      $phoneID = $self->_doesPhoneDataExist({ 
        'phoneNumber' => $phoneNumber, 
        'type'        => $generalTypeID,
        'description' => $description
      }, $self->{'customerID'});

      if (!$phoneID) {
        my $params = [
          $self->{'customerID'},
          $description, 
          $phoneNumber,
          $generalTypeID
        ];

        my $dbs = new PlugNPay::DBConnection();
        my $sth = $dbs->executeOrDie('merchant_cust',
          q/INSERT INTO customer_phone
            ( customer_id,
              description,
              phone,
              general_type_id )
            VALUES (?,?,?,?)/, $params)->{'sth'};
        $phoneID = $sth->{'mysql_insertid'};
      }

      $self->{'phoneID'} = $phoneID;
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'function'   => 'updatePhone',
        'error'      => $@,
        'customerID' => $self->{'customerID'}
      });

      push (@errorMsg, 'Error while attempting to update phone.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

##################################
# Subroutine: deletePhone
# --------------------------------
# Description:
#   Deletes a customers phones 
#   from my records.
sub deletePhone {
  my $self = shift;
  my $phoneID = shift;

  my $status = new PlugNPay::Util::Status(1);

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM customer_phone
        WHERE id = ?/, [$phoneID]);
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'deletePhone',
      'phoneID'  => $phoneID
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete phone.');
  }

  return $status;
}

sub _doesPhoneDataExist {
  my $self = shift;
  my $data = shift;
  my $customerID = shift;

  my $params = [
    $data->{'phoneNumber'},
    $data->{'type'},
    $data->{'description'},
    $customerID
  ];

  # die here, wrapped in eval in update and save
  my $dbs = new PlugNPay::DBConnection();
  my $rows = $dbs->fetchallOrDie('merchant_cust',
    q/SELECT id
      FROM customer_phone
      WHERE phone = ?
      AND general_type_id = ?
      AND description = ?
      AND customer_id = ?/, $params, {})->{'result'};
  my $existingID;
  if (@{$rows} > 0) {
    $existingID = $rows->[0]{'id'};
  }

  return $existingID;
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getPhoneListSize {
  my $self = shift;
  my $customerID = shift;

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM customer_phone
        WHERE customer_id = ?/, [$customerID], {})->{'result'};
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

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'customer_phone' });
  $logger->log($logInfo);
}

1;
