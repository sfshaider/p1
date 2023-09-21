package PlugNPay::Util::Temp;

use strict;
use PlugNPay::AWS::Lambda;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::AWS::ParameterStore;

#########################################################
# Calls tmp lambda
# 
# 1. Create new object
#   my $rs = new PlugNPay::Util::Temp();
#
# 2. Load in parameters
#   $rs->setKey('test');
#
#   // value must be a hash
#   $rs->setValue({ 'data' => ['1', '2', '3'] });
#   $rs->setPassword('testing123');
#  
#   // for updating an existing record with new password
#   $rs->setNewPassword('testing1234'); 
#
#   // set expiration time in hours
#   // the default is 1 week
#   $rs->setExpirationTime(3);  // 3 hours
#   $rs->setExpirationTime(-1); // does not expire
#
# 3. Call store/fetch/updatePassword/delete
#   my $status = $rs->store();
#   my $status = $rs->fetch();
#   my $status = $rs->updatePassword();
#   my $status = $rs->delete();
#
#   // updatePassword does not allow value to be updated
#   // use store to update the value AND password if necessary
#
#   my $value;
#   if (!$status) {
#     // error
#     print $status->getError();
#   } else {
#     // no error
#     $value = $rs->getValue();
#   }

our $PNP_TMP_LAMBDA;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  if (!defined $PNP_TMP_LAMBDA || $PNP_TMP_LAMBDA eq '') {
    &PlugNPay::Util::Temp::loadParameters();
  }

  return $self;
}

sub loadParameters {
  $PNP_TMP_LAMBDA = &PlugNPay::AWS::ParameterStore::getParameter('/LAMBDA/TMP');
  if ($PNP_TMP_LAMBDA eq '') {
    die('failed to load lambda to execute for TMP');
  }
}

sub setKey {
  my $self = shift;
  my $key = shift;
  $self->{'key'} = $key;
}

sub getKey {
  my $self = shift;
  return $self->{'key'};
}

sub setValue {
  my $self = shift;
  my $value = shift;
  $self->{'value'} = $value;
}

sub getValue {
  my $self = shift;
  return $self->{'value'} || {};
}

sub setExpirationTime {
  my $self = shift;
  my $expirationTime = shift;
  $self->{'expirationTime'} = $expirationTime;
}

sub getExpirationTime {
  my $self = shift;
  return $self->{'expirationTime'};
}

sub setPassword {
  my $self = shift;
  my $password = shift;
  $self->{'password'} = $password;
}

sub setNewPassword {
  my $self = shift;
  my $newPassword = shift;
  $self->{'newPassword'} = $newPassword;
}

sub store {
  my $self = shift;

  my $key            = shift || $self->{'key'};
  my $value          = shift || $self->{'value'};
  my $password       = shift || $self->{'password'};
  my $expirationTime = shift || $self->{'expirationTime'};

  if (!$key || !$value || !$password) {
    die "Insufficient data sent";
  }

  my $storeData = {
    'key'         => $key,
    'value'       => $value,
    'password'    => $password
  };

  if (defined $self->{'newPassword'}) {
    $storeData->{'newPassword'} = $self->{'newPassword'};
  }

  if (defined $expirationTime) {
    $storeData->{'expiration'} = $expirationTime;
  } else {
    $storeData->{'expiration'} = 168; # week
  }

  my $status = new PlugNPay::Util::Status(1);
  my $response = &PlugNPay::AWS::Lambda::invoke({
      'lambda'         => $PNP_TMP_LAMBDA,
      'invocationType' => 'RequestResponse', 
      'data' => $storeData  
  });

  my ($error, $message);
  my $payload = $response->{'payload'};
  if (defined $payload) {
    $error = $payload->{'error'};
    $message = $payload->{'message'};
  } else {
    $error = $response->{'status'};
    $message = $response->{'error'};
  }

  if ($error) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'lambda_tmp' });
    $logger->log({ 'error' => $message });

    $status->setFalse();
    $status->setError($message);
  } else {
    # updating returns the previous value
    if (exists $payload->{'value'}) {
      $self->{'value'} = $payload->{'value'};
    }
  }

  return $status;
}

sub fetch {
  my $self = shift;

  my $key = shift      || $self->{'key'};
  my $password = shift || $self->{'password'};

  if (!$key || !$password) {
    die "Insufficient data sent";
  }

  my $status = new PlugNPay::Util::Status(1);
  my $response = &PlugNPay::AWS::Lambda::invoke({
      'lambda'         => $PNP_TMP_LAMBDA,
      'InvocationType' => 'RequestResponse', 
      'data' => {
        'key'         => $key,
        'password'    => $password
      }
  });

  my ($error, $message);
  my $payload = $response->{'payload'};
  if (defined $payload) {
    $error = $payload->{'error'};
    $message = $payload->{'message'};
  } else {
    $error = $response->{'status'};
    $message = $response->{'error'};
  }

  if ($error) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'lambda_tmp' });
    $logger->log({ 'error' => $message });

    $status->setFalse();
    $status->setError($message);
  } else {
    $self->{'value'} = $payload->{'value'};
  }

  return $status;
}

sub updatePassword {
  my $self = shift;

  my $key = shift         || $self->{'key'};
  my $password = shift    || $self->{'password'};
  my $newPassword = shift || $self->{'newPassword'};

  if (!$key || !$password || !$newPassword) {
    die "Insufficient data sent";
  }

  my $status = new PlugNPay::Util::Status(1);
  my $response = &PlugNPay::AWS::Lambda::invoke({
      'lambda'         => $PNP_TMP_LAMBDA,
      'InvocationType' => 'RequestResponse', 
      'data' => {
        'key'         => $key,
        'password'    => $password,
        'newPassword' => $newPassword
      }
  });

  my ($error, $message);
  my $payload = $response->{'payload'};
  if (defined $payload) {
    $error = $payload->{'error'};
    $message = $payload->{'message'};
  } else {
    $error = $response->{'status'};
    $message = $response->{'error'};
  }

  if ($error) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'lambda_tmp' });
    $logger->log({ 'error' => $message });

    $status->setFalse();
    $status->setError($message);
  }

  return $status;
}

sub delete {
  my $self = shift;

  my $key = shift         || $self->{'key'};
  my $password = shift    || $self->{'password'};

  if (!$key || !$password) {
    die "Insufficient data sent";
  }

  my $status = new PlugNPay::Util::Status(1);
  my $response = &PlugNPay::AWS::Lambda::invoke({
      'lambda'         => $PNP_TMP_LAMBDA,
      'InvocationType' => 'RequestResponse', 
      'data' => {
        'key'         => $key,
        'password'    => $password,
        'expiration'  => 0
      }
  });

  my ($error, $message);
  my $payload = $response->{'payload'};
  if (defined $payload) {
    $error = $payload->{'error'};
    $message = $payload->{'message'};
  } else {
    $error = $response->{'status'};
    $message = $response->{'error'};
  }

  if ($error) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'lambda_tmp' });
    $logger->log({ 'error' => $message });

    $status->setFalse();
    $status->setError($message);
  }

  return $status;
}

1;
