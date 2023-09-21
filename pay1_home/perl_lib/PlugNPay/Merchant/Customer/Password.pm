package PlugNPay::Merchant::Customer::Password;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Util::UniqueID;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::RandomString;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub setMerchant {
  my $self = shift;
  my $merchant = shift;
  $self->{'merchant'} = $merchant;
}

sub getMerchant {
  my $self = shift;
  return $self->{'merchant'};
}

sub setCustomer {
  my $self = shift;
  my $customer = shift;
  $self->{'customer'} = $customer;
}

sub getCustomer {
  my $self = shift;
  return $self->{'customer'};
}

sub setResetURL {
  my $self = shift;
  my $resetURL = shift;
  $self->{'resetURL'} = $resetURL;
}

sub getResetURL {
  my $self = shift;
  return $self->{'resetURL'};
}

sub isExpired {
  my $self = shift;

  my $merchant = $self->{'merchant'};
  my $customer = $self->{'customer'};
  my $url      = $self->{'resetURL'};

  my $expired = 1;
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT expires
        FROM customer_reset_password
        WHERE merchant = ?
        AND customer = ?
        AND url = ?/, [$merchant, $customer, $url], {})->{'result'};
    if (@{$rows} > 0) {
      my $currentTime = new PlugNPay::Sys::Time()->nowInFormat('iso');
      my $expireTime = $rows->[0]{'expires'};
      if ($currentTime lt $expireTime) {
        $expired = 0;
      }
    }
  };

  if ($@) {
    $self->_log({
      'merchant' => $merchant,
      'customer' => $customer,
      'url'      => $url,
      'error'    => $@
    });
  }

  return $expired;
}

sub doesResetLinkExist {
  my $self = shift;

  my $merchant = $self->{'merchant'};
  my $customer = $self->{'customer'};
  my $url      = $self->{'resetURL'};

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM customer_reset_password
        WHERE merchant = ?
        AND customer = ?
       AND url = ?/, [$merchant, $customer, $url], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'customer' => $customer,
      'merchant' => $merchant,
      'error'    => $@
    });
  }

  return $exists;
}

sub generateActivateID {
  my $self = shift;

  my $merchant = $self->{'merchant'};
  my $customer = $self->{'customer'};
  my $url      = $self->{'resetURL'};

  my $activateID = new PlugNPay::Util::UniqueID()->inHex();

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/UPDATE customer_reset_password
        SET activated_id = ?
        WHERE merchant = ?
        AND customer = ?
        AND url = ?/, [$activateID, $merchant, $customer, $url]);
  };

  if ($@) {
    $activateID = undef;
    $self->_log({
      'error'    => $@,
      'merchant' => $merchant,
      'customer' => $customer
    });
  }

  return $activateID;
}

sub verifyActivation {
  my $self = shift;
  my $activateID = shift;

  my $merchant = $self->{'merchant'};
  my $customer = $self->{'customer'};
  my $url      = $self->{'resetURL'};

  my $exists = 0;

  eval {
    my $params = [
      $merchant,
      $customer,
      $url,
      $activateID
    ];

    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM customer_reset_password
        WHERE merchant = ?
        AND customer = ?
        AND url = ?
        AND activated_id = ?/, $params, {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'merchant' => $merchant,
      'customer' => $customer
    });
  }

  return $exists;
}

sub generatePasswordLink {
  my $self = shift;
  my $merchant = shift;
  my $customer = shift;

  my $status = new PlugNPay::Util::Status(1);

  my $time = new PlugNPay::Sys::Time();
  $time->addHours(3);

  my $randomString = new PlugNPay::Util::RandomString();
  my $resetLink = $randomString->randomAlphaNumeric(150);

  my $link = 'https://' . $ENV{'SERVER_NAME'} . "/customer_password_reset.cgi?merchant=$merchant&customer=$customer&reset-link=$resetLink";

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/INSERT INTO customer_reset_password
        ( merchant,
          customer,
          url,
          expires )
        VALUES (?,?,?,?)
        ON DUPLICATE KEY UPDATE
        url     = values(url),
        expires = values(expires)/, [$merchant, $customer, $resetLink, $time->inFormat('iso')]);
  };

  if ($@) {
    $self->_log({
      'merchant' => $merchant,
      'customer' => $customer,
      'error'    => $@
    });

    $status->setFalse();
    $status->setError('Failed to create reset password email.');
  }

  return { 'status' => $status, 'link' => $link };
}

sub resetPassword {
  my $self = shift;
  my $password = shift;

  my $status = new PlugNPay::Util::Status(1);
  my $errorMsg;

  my $merchant = $self->{'merchant'};
  my $customer = $self->{'customer'};

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link($merchant);
  $merchantCustomer->loadCustomerIDByUsername($customer);
  if ($merchantCustomer->getMerchantCustomerLinkID()) {
    my $updatePassword = $merchantCustomer->updateMerchantCustomer({
      'password' => $password
    });

    if (!$updatePassword) {
      $status->setFalse();
      $status->setError($updatePassword->getError());
    }
  } else {
    $status->setFalse();
    $status->setError('Customer does not exist.');
  }

  return $status;
}

sub deleteResetLink {
  my $self = shift;

  my $merchant = $self->{'merchant'};
  my $customer = $self->{'customer'};
  my $url      = $self->{'resetURL'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM customer_reset_password
        WHERE merchant = ?
        AND customer = ?
        AND url = ?/, [$merchant, $customer, $url]);
  };
  
  if ($@) {
    $self->_log({
      'merchant' => $merchant,
      'customer' => $customer,
      'error'    => $@
    });
  }
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'customer_reset_password' });
  $logger->log($logInfo);
}

1;
