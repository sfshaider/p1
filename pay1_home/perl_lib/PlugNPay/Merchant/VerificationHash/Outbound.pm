package PlugNPay::Merchant::VerificationHash::Outbound;

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
    'currency',
    'FinalStatus'
  ];
}

sub loadVerificationHash {
  my $self = shift;
  my $merchant = shift;

  my $verificationHash = {};

  my $features = new PlugNPay::Features($merchant,'general');
  my $values = $features->getFeatureValues('hashkey');
  my $hashKey = shift(@{$values}); # shift off key

  # seperate default fields
  my %defaultFields = map { $_ => 1 } @{$self->getDefaultFields()};
  my @customFields = ();
  my @fields = ();

  foreach my $value (@{$values}) {
    if (exists $defaultFields{$value}) {
      push (@fields, $value);
    } else {
      push (@customFields, $value);
    }
  }

  $verificationHash = { 
    'hashKey'      => $hashKey,
    'fields'       => \@fields,
    'customFields' => \@customFields,
    'values'       => $values # to demonstrate order of values
  };

  return $verificationHash;
}

sub saveVerificationHash {
  my $self = shift;
  my $merchant = shift;
  my $hashKey = shift;
  my $requestedFields = shift;

  my $status = new PlugNPay::Util::Status(1);
  my $errorMsg;

  if (!$merchant) {
    $status->setFalse();
    $status->setError('No merchant account specified.');
    return $status;
  }

  eval {
    my $newHashKeyFields = [ $hashKey ];
    foreach my $requestedField (sort @{$requestedFields}) {
      push (@{$newHashKeyFields}, $requestedField);
    }

    my $features = new PlugNPay::Features($merchant,'general');
    $features->setFeatureValues('hashkey', $newHashKeyFields);

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
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_verification_outbound_hash' });
      $logger->log({
        'error'    => $@,
        'function' => 'saveVerificationHash',
        'merchant' => $merchant
      });

      $errorMsg = 'Failed to save verification (outbound) key.';
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
  my $errorMsg;

  if (!$merchant) {
    $status->setFalse();
    $status->setError('No merchant account specified.');
    return $status;
  }

  eval {
    my $gatewayAccount = new PlugNPay::GatewayAccount($merchant);
    my $features = $gatewayAccount->getFeatures();
    if ($features->get('hashkey') ne '') {
      $features->removeFeature('hashkey');
      $gatewayAccount->setFeatures($features);
      my $success = $gatewayAccount->save();
      if (!$success) {
        $errorMsg = 'Failed to save account data.';
      }
    }
  };

  if ($@ || $errorMsg) {
    if ($@) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'merchant_verification_outbound_hash' });
      $logger->log({
        'error'    => $@,
        'function' => 'deleteVerificationHash',
        'merchant' => $merchant
      });

      $errorMsg = 'Failed to delete verification (outbound) key.';
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
  return $features->get('hashkey') ne '';
}

1;
