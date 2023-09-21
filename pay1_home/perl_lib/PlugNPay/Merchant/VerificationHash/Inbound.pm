package PlugNPay::Merchant::VerificationHash::Inbound;

use strict;
use PlugNPay::Features;
use PlugNPay::Util::Status;
use PlugNPay::GatewayAccount;
use PlugNPay::Logging::DataLog;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub getDefaultFields {
  my $self = shift;
  my $defaultFields = [
    'publisher-name',
    'orderID',
    'card-amount',
    'acct_code'
  ];
}

sub loadVerificationHash {
  my $self = shift;
  my $merchant = shift;

  my $authorizationHash = {};

  # load auth hash feature
  my $features = new PlugNPay::Features($merchant,'general');
  my $values = $features->getFeatureValues('authhashkey');

  my $timeWindow = shift(@{$values}); # shift off timestamp
  my $hashKey    = shift(@{$values}); # shift off key

  # seperate fields from custom fields
  my %defaultFields = map { $_ => 1 } @{$self->getDefaultFields()};
  my @fields = ();
  my @customFields = ();

  foreach my $value (@{$values}) {
    if (exists $defaultFields{$value}) {
      push (@fields, $value);
    } else {
      push (@customFields, $value);
    }
  }

  $authorizationHash = { 
    'authHashKey'  => $hashKey,
    'timeWindow'   => $timeWindow,
    'fields'       => \@fields,
    'customFields' => \@customFields,
    'values'       => $values # to demonstrate order of values
  };

  return $authorizationHash;
}

sub saveVerificationHash {
  my $self = shift;
  my $merchant = shift;
  my $hashKey = shift;
  my $authHashData = shift;

  my $status = new PlugNPay::Util::Status(1);
  if (!$merchant) {
    $status->setFalse();
    $status->setError('No merchant account specified.');
    return $status;
  }

  my $errorMsg;
  eval {
    # get request data
    my $timeWindow      = $authHashData->{'timeWindow'};
    my $requestedFields = $authHashData->{'fields'};

    my $newHashKeyFields = [ $timeWindow, $hashKey ];
    foreach my $requestedField (sort @{$requestedFields}) {
      push (@{$newHashKeyFields}, $requestedField);
    }

    my $features = new PlugNPay::Features($merchant,'general');
    $features->setFeatureValues('authhashkey', $newHashKeyFields);

    # save features
    my $gatewayAccount = new PlugNPay::GatewayAccount($merchant);
    $gatewayAccount->setFeatures($features);
    my $success = $gatewayAccount->save();
    if (!$success) {
      $errorMsg = 'Failed to save account data.';
    }
  };

  if ($@ || $errorMsg) {
    if ($@) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_verification_inbound_hash' });
      $logger->log({
        'error'    => $@,
        'function' => 'saveVerificationHash',
        'merchant' => $merchant
      });

      $errorMsg = 'Failed to save verifcation (inbound) hash.';
    }

    $status->setFalse();
    $status->setError($errorMsg);
    $status->setErrorDetails($@);
  }

  return $status;
}

sub deleteVerificationHash {
  my $self = shift;
  my $merchant = shift;

  my $status = new PlugNPay::Util::Status(1);

  if (!$merchant) {
    $status->setFalse();
    $status->setError('No merchant account specified.');
    return $status;
  }

  my $errorMsg;
  eval {
    my $gatewayAccount = new PlugNPay::GatewayAccount($merchant);
    my $features = $gatewayAccount->getFeatures();
    if ($features->get('authhashkey') ne '') {
      $features->removeFeature('authhashkey');
      $gatewayAccount->setFeatures($features);
      my $success = $gatewayAccount->save();
      if (!$success) {
        $errorMsg = 'Failed to save account data.';
      }
    }
  };

  if ($@ || $errorMsg) {
    if ($@) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_verification_inbound_hash' });
      $logger->log({
        'error'    => $@,
        'function' => 'deleteVerificationHash',
        'merchant' => $merchant
      });

      $errorMsg = 'Failed to delete verification (inbound) hash.';
    }

    $status->setFalse();
    $status->setError($errorMsg);
    $status->setErrorDetails($@);
  }

  return $status;
}

sub doesVerificationHashExist {
  my $self = shift;
  my $merchant = shift;

  my $features = new PlugNPay::Features($merchant,'general');
  return $features->get('authhashkey') ne '';
}

1;
