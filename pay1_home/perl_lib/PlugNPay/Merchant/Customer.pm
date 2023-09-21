package PlugNPay::Merchant::Customer;

use strict;
use PlugNPay::Email;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;

######################################
# Module: Merchant::Customer
# ------------------------------------
# Description:
#   The base of a customer. Consists
#   of an email and name.

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
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

sub setEmail {
  my $self = shift;
  my $email = shift;
  $self->{'email'} = $email;
}

sub getEmail {
  my $self = shift;
  return $self->{'email'};
}

sub loadCustomer {
  my $self = shift;
  my $customerID = shift;
 
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               email
        FROM customer
        WHERE id = ?/, [$customerID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setCustomerDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadCustomer'
    });
  }
}

sub _setCustomerDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->setCustomerID($row->{'id'});
  $self->setEmail($row->{'email'});
}

sub saveCustomer {
  my $self = shift;
  my $data = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $email = exists $data->{'email'} ? $data->{'email'} : $self->{'email'};
  if (!$email) {
    $email = $self->_generateEmail();
  } else {
    # validate email
    $email = lc $email;
    my ($username, $domain) = split('@', $email);
    if (!$username || !$domain) {
      push (@errorMsg, 'Invalid email address.');
    }
  }

  if (@errorMsg == 0) {
    my $customer = new PlugNPay::Merchant::Customer();
    $customer->loadCustomerFromEmail($email);
    my $customerID = $customer->getCustomerID();
    if (!$customerID) {
      eval {
        # insert new customer
        my $dbs = new PlugNPay::DBConnection();
        my $sth = $dbs->executeOrDie('merchant_cust',
          q/INSERT INTO customer
            ( email )
            VALUES (?)/, [$email])->{'sth'};
        $customerID = $sth->{'mysql_insertid'};
      };
    }

    $self->{'customerID'} = $customerID;
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'    => $@,
        'function' => 'saveCustomer'
      });

      push (@errorMsg, 'Error while attempting to save customer.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } 

  return $status;
}

sub deleteCustomer {
  my $self = shift;
  my $customerID = shift || $self->{'customerID'};

  my $status = new PlugNPay::Util::Status(1);
  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM customer
        WHERE id = ?/, [$customerID]);
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'deleteCustomer'
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete customer.');
  }

  return $status;
}

sub _generateEmail {
  my $self = shift;
  my $randomEmail = lc new PlugNPay::Util::RandomString()->randomAlphaNumeric(20) . '@plugnpay.pnp';
  if ($self->customerEmailExists($randomEmail)) {
    $randomEmail = $self->_generateEmail();
  }

  return $randomEmail;
}

sub customerEmailExists {
  my $self = shift;
  my $email = uc shift;

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->executeOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM customer
        WHERE UPPER(email) = ?/, [$email], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'customerEmailExists'
    });
  }

  return $count;
}

sub loadCustomerFromEmail {
  my $self = shift;
  my $email = uc shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               email
        FROM customer
        WHERE UPPER(email) = ?/, [$email], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setCustomerDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadCustomerFromEmail'
    });
  }
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'customer' });
  $logger->log($logInfo);
} 

1;
