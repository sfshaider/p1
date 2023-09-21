package PlugNPay::Client::Datacap;

use PlugNPay::Merchant;
use PlugNPay::Util::Status;
use PlugNPay::Util::UniqueID;
use PlugNPay::Logging::DataLog;
use PlugNPay::Merchant::Device;
use PlugNPay::Processor::Process;
use PlugNPay::Merchant::DeviceLink;
use PlugNPay::Merchant::DeviceConnection;

use strict;

sub new {
  my $class = shift;
  my $self = {};

  bless $self, $class;

  my $merchant = shift || '';

  if ($merchant) {
    my $merchantObj = new PlugNPay::Merchant($merchant);
    $self->setMerchant($merchantObj->getMerchantUsername());
    $self->setMerchantID($merchantObj->getMerchantID());
  }
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

sub setMerchantID {
  my $self = shift;
  my $merchantID = shift;
  $self->{'merchantID'} = $merchantID;
}

sub getMerchantID {
  my $self = shift;
  return $self->{'merchantID'};
}

sub setTransaction {
  my $self = shift;
  my $transaction = shift;
  $self->{'transaction'} = $transaction;
}

sub getTransaction {
  my $self = shift;
  return $self->{'transaction'};
}

sub setCustomData {
  my $self = shift;
  my $key = shift;
  my $value = shift;
  $self->{'customData'}{$key} = $value;
}

sub getCustomData {
  my $self = shift;
  return $self->{'customData'};
}

sub performTransaction {
  my $self = shift;
  my $options = shift;
  my $transaction = $options->{'transaction'};
  my $terminalSerialNumber = $options->{'terminalSerialNumber'};
  my $status;

  $status = $self->_isMerchantConfigured($terminalSerialNumber);

  if ($status) {
    $status = $self->_createTransaction($transaction);
  }

  return $status;
}

sub _isMerchantConfigured {
  my $self = shift;
  my $pinPadSerialNumber = shift;
  my $merchantID = shift || $self->getMerchantID();
  my $pinPad = new PlugNPay::Merchant::Device();
  my $tranCloud = new PlugNPay::Merchant::Device();
  my $deviceLink = new PlugNPay::Merchant::DeviceLink();
  my $deviceConnection = new PlugNPay::Merchant::DeviceConnection();

  my $status = new PlugNPay::Util::Status(1);
  my $errMsg;
 
  if (!$pinPad->doesSerialNumberExist($pinPadSerialNumber)) {
    $errMsg = 'Serial Number does not exist.';
  } elsif (!$pinPad->isDeviceConnectedToMerchant($merchantID, $pinPadSerialNumber)) {
    $errMsg = 'The current device is not set up for the merchant specified. ';
  } else {
    my ($tranCloudID, $isLinked);

    $pinPad->loadDeviceBySerialNumber($pinPadSerialNumber);
    $tranCloudID = $deviceLink->loadLinkedTranCloudDevice($pinPad->getID());

    $tranCloud->loadDevice($tranCloudID);
    $isLinked = $deviceLink->isDeviceLinked($tranCloud->getID(), $pinPad->getID());

    if (!$isLinked) {
      $errMsg = 'Pinpad and TranCloud Device are not linked.';
    }
  }

  if ($errMsg) {
    $status->setFalse();
    $status->setError('Configuration Error.');
    $status->setErrorDetails($errMsg);
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'processor'});
    $logger->log({
      'status'    => 'ERROR',
      'message'   => 'Configuration error',
      'processor' => 'Datacap',
      'function'  => '_isTransactionReady',
      'module'    => ref($self),
      'error'     => $errMsg
    });
  } else {
    $deviceConnection->loadDeviceIPAndPort($pinPad->getID());
    $self->setCustomData('tranDeviceID', $tranCloud->getDeviceID());
    $self->setCustomData('secureDevice', 'CloudEMV2');
    $self->setCustomData('pinPadIpAddress', $deviceConnection->getIPAddress());
    $self->setCustomData('pinPadIpPort', $deviceConnection->getPort());
  }

  return $status;
}

sub _createTransaction {
  my $self = shift;
  my $transaction = shift || $self->getTransaction();

  my $status = new PlugNPay::Util::Status(1);
  my @tranState = split('_', $transaction->getTransactionState());
  my $operation = lc $tranState[0];

  if ($operation eq 'sale' || $operation eq 'credit') {
    my $process = new PlugNPay::Processor::Process($operation);
    my $response = {};
    $transaction->setCustomData($self->getCustomData());

    eval {
      $response = $process->dispatchTransaction($transaction);
    };

    if ($@) {
      $status->setFalse();
      $status->setError('Failed to connect to processor.');
      $status->setErrorDetails($@);
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'processor' });
      $logger->log({
        'status'    => 'ERROR',
        'message'   => 'Failed to connect to processor.',
        'processor' => 'Datacap',
        'function'  => '_createTransaction',
        'module'    => ref($self),
        'error'     => $@
      });
    } elsif ($response->{'FinalStatus'} =~ /failure/i) {
      $status->setFalse();
      $status->setError('Failed to dispatch transaction.');
      $status->setErrorDetails($response->{'MErrMsg'});
    }
  } else {
    $status->setFalse();
    $status->setError('Failed to create transaction.');
    $status->setErrorDetails('Processor does not support ' . $operation . ' transactions.')
  }

  return $status;
}

sub loadTransactionResults {
  my $self = shift;
  my $transactionID = shift;

  my ($util, $binary, $array);

  $util = new PlugNPay::Util::UniqueID();
  $util->fromHex($transactionID);

  $binary = $util->inBinary();
  $array = [$binary];

  return new PlugNPay::Processor::Process()->getProcessedTransactions($array);
}

1;
