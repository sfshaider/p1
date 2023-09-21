package PlugNPay::Merchant::VerificationHash;

use strict;
use PlugNPay::Username;
use PlugNPay::Sys::Time;
use PlugNPay::Util::Hash;
use PlugNPay::Merchant::VerificationHash::Inbound;
use PlugNPay::Merchant::VerificationHash::Outbound;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub isAuthorized {
  my $self = shift;
  my $merchant = shift;

  my $username = new PlugNPay::Username($merchant);
  return ($username->getSecurityLevel() == '0');
}

sub loadHash {
  my $self = shift;
  my $merchant = shift;
  my $type = shift;

  my $hashData = {};
  if ($type eq 'inbound') {
    my $authorizationHash = new PlugNPay::Merchant::VerificationHash::Inbound();
    $hashData = $authorizationHash->loadVerificationHash($merchant);
  } elsif ($type eq 'outbound') {
    my $verificationHash = new PlugNPay::Merchant::VerificationHash::Outbound();
    $hashData = $verificationHash->loadVerificationHash($merchant);
  }

  return $hashData;
}

sub createHash {
  my $self = shift;
  my $merchant = shift;
  my $type = shift;
  my $hashData = shift;

  my $status = new PlugNPay::Util::Status(1);
  my $errorMsg;

  if (!$self->isAuthorized($merchant)) {
    $status->setFalse();
    $status->setError('Your security level prevents access to this function.');
    return $status;
  }

  # create new hashed key
  my $time = new PlugNPay::Sys::Time()->nowInFormat('iso');
  my $plainText = $time . $ENV{'SSL_SESSION_ID'} . $time;
  my $hasher = new PlugNPay::Util::Hash();
  $hasher->add($plainText);
  my $hashedString = $hasher->sha1();
  my $hashKey = substr($hashedString, 0, 25);

  my $requestedFields = $hashData->{'fields'} || [];
  if (ref($requestedFields) !~ /ARRAY/) {
    $errorMsg = 'Invalid data type for fields.';
  } else {
    # check existing features
    my $features = new PlugNPay::Features($merchant,'general');
    if ($type eq 'inbound') {
      my $timeWindow = $hashData->{'timeWindow'};
      if ($timeWindow !~ /^\d+$/) {
        $errorMsg = 'Invalid time window.';
      } else {
        my $data = { 'fields' => $requestedFields, 'timeWindow' => $timeWindow };
        my $authorizationHash = new PlugNPay::Merchant::VerificationHash::Inbound();
        my $authorizationStatus = $authorizationHash->saveVerificationHash($merchant, $hashKey, $data);
        if (!$authorizationStatus) {
          $errorMsg = $authorizationStatus->getError();
        }
      }
    } elsif ($type eq 'outbound') {
      my $verificationHash = new PlugNPay::Merchant::VerificationHash::Outbound();
      my $verificationStatus = $verificationHash->saveVerificationHash($merchant, $hashKey, $requestedFields);
      if (!$verificationStatus) {
        $errorMsg = $verificationStatus->getError();
      }
    } else {
      $errorMsg = 'Invalid hash type.';
    }
  }

  if ($errorMsg) {
    $status->setFalse();
    $status->setError($errorMsg);
  }

  return $status;
}

sub deleteHash {
  my $self = shift;
  my $merchant = shift;
  my $type = shift;

  my $status = new PlugNPay::Util::Status(1);
  my $errorMsg;

  if (!$self->isAuthorized($merchant)) {
    $status->setFalse();
    $status->setError('Your security level prevents access to this function.');
    return $status;
  }

  if ($type eq 'inbound') {
    my $authorizationHash = new PlugNPay::Merchant::VerificationHash::Inbound();
    my $authStatus = $authorizationHash->deleteVerificationHash($merchant);
    if (!$authStatus) {
      $errorMsg = $authStatus->getError();
    }
  } elsif ($type eq 'outbound') {
    my $verificationHash = new PlugNPay::Merchant::VerificationHash::Outbound();
    my $verificationStatus = $verificationHash->deleteVerificationHash($merchant);
    if (!$verificationStatus) {
      $errorMsg = $verificationStatus->getError();
    }
  } else {
    $errorMsg = 'Invalid hash type.';
  }

  if ($errorMsg) {
    $status->setFalse();
    $status->setError($errorMsg);
  }
  
  return $status;
}

sub doesHashExist {
  my $self = shift;
  my $merchant = shift;
  my $type = shift;

  if ($type eq 'inbound') {
    my $authHash = new PlugNPay::Merchant::VerificationHash::Inbound();
    return $authHash->doesVerificationHashExist($merchant);
  } elsif ($type eq 'outbound') {
    my $verificationHash = new PlugNPay::Merchant::VerificationHash::Outbound();
    return $verificationHash->doesVerificationHashExist($merchant);
  }
}

1;
