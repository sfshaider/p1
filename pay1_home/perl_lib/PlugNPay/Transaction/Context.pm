package PlugNPay::Transaction::Context;

use strict;
use PlugNPay::Die;
use PlugNPay::DBConnection;
use PlugNPay::Processor;
use PlugNPay::Util::UniqueID;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Transaction::Loader::History;
use PlugNPay::Util::StackTrace;

our $__transaction_versions__ = {
  legacy => 'legacy',
  unified => 'unified'
};

# Stored procedures and tables used in this module:
## in pnp_transaction
#### table: transaction_context ####
# CREATE TABLE `transaction_context` (
#   `id` bigint(11) unsigned NOT NULL AUTO_INCREMENT,
#   `merchant_id` int(11) unsigned NOT NULL,
#   `pnp_transaction_id` varbinary(22) NOT NULL DEFAULT '',
#   `active_context_id` varbinary(22) NOT NULL DEFAULT '',
#   `expiration` varchar(16) NOT NULL DEFAULT '',
#   PRIMARY KEY (`id`),
#   UNIQUE KEY `merchant_id-pnp_transaction_id` (`merchant_id`,`pnp_transaction_id`)
# ) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=latin1;
#
#### procedure: acquire_transaction_lock ####
# DELIMITER ;;
# CREATE  PROCEDURE `acquire_transaction_lock`(
#     IN input_merchant_id int(11) unsigned,
#     IN input_transaction_id varbinary(22),
#     IN input_context_id varbinary(22),
#     IN input_expiration varchar(16)
# )
# BEGIN
#   INSERT INTO transaction_context (`merchant_id`,`pnp_transaction_id`,`active_context_id`, `expiration`) VALUES (input_merchant_id,input_transaction_id, input_context_id, input_expiration);
#   SELECT COUNT(*) as `lock_status` FROM `transaction_context` WHERE `merchant_id` = input_merchant_id AND `pnp_transaction_id` = input_transaction_id AND `active_context_id` = input_context_id;
# END;;
# DELIMITER ;
#
#### procedure: release_transaction_lock ####
# DELIMITER ;;
# CREATE  PROCEDURE `release_transaction_lock`(
#     IN input_merchant_id int(11) unsigned,
#     IN input_transaction_id varbinary(22),
#     IN input_context_id varbinary(22)
# )
# BEGIN
#   DELETE FROM transaction_context WHERE `merchant_id` = input_merchant_id AND `pnp_transaction_id` = input_transaction_id AND `active_context_id` = input_context_id;
#   SELECT COUNT(*) as `lock_status` FROM `transaction_context` WHERE `merchant_id` = input_merchant_id AND `pnp_transaction_id` = input_transaction_id AND `active_context_id` = input_context_id;
#
# END;;
# DELIMITER ;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $input = shift;
  my $gatewayAccount = $input->{'gatewayAccount'};
  my $transactionId = $input->{'transactionId'};
  my $processor = $input->{'processorId'};
  my $transactionVersion = $input->{'transactionVersion'};

  $self->{'transactionVersion'} = $__transaction_versions__->{$transactionVersion};

  if (!defined $self->{'transactionVersion'}) {
    die('A transaction version can not be determined for the context');
  }

  if (!defined $gatewayAccount) {
    die('A context can not be created without a gatewayAccount');
  }
  if (!defined $transactionId) {
    die('A context can not be created without a transactionId');
  }

  my $iid = new PlugNPay::GatewayAccount::InternalID();

  $self->{'merchantId'} = $iid->getMerchantID("$gatewayAccount"); # quotes coerce into scalar value.
  $self->{'gatewayAccount'} = $gatewayAccount;
  $self->{'transactionId'} = $transactionId;

  my $contextId = new PlugNPay::Util::UniqueID()->inHex();
  $self->{'contextId'} = $contextId;

  return $self;
}

sub releaseLock {
  my $self = shift;
  $self->_releaseTransactionContextLock();
}

sub _acquireTransactionContextLock {
  my $self = shift;

  if ($self->{'lockAttempted'}) {
    return $self->{'locked'};
  }

  my $dbs = new PlugNPay::DBConnection();

  my $btid = PlugNPay::Util::UniqueID::fromHexToBinary($self->{'transactionId'});
  my $bcid = PlugNPay::Util::UniqueID::fromHexToBinary($self->{'contextId'});
  my $merchantId = $self->{'merchantId'};

  my $timestamp = new PlugNPay::Sys::Time()->nowInFormat('iso_gm');
  my $lockSuccess;

  my $result;
  eval {
    $result = $dbs->fetchallOrDie('pnp_transaction',q/
      call acquire_transaction_lock(?,?,?,?)
    /,[$merchantId,$btid,$bcid,$timestamp],{});
  };

  $lockSuccess = $result->{'result'}[0]{'lock_status'};
  $self->{'lockAttempted'} = 1;

  if (!$lockSuccess) {
    die('failed to acquire lock for transacton');
  } else {
    $self->{'locked'} = 1;
    return 1;
  }
}

sub _releaseTransactionContextLock {
  my $self = shift;

  if ($self->{'released'}) {
    return;
  }

  my $dbs = new PlugNPay::DBConnection();

  my $btid = PlugNPay::Util::UniqueID::fromHexToBinary($self->{'transactionId'});
  my $bcid = PlugNPay::Util::UniqueID::fromHexToBinary($self->{'contextId'});
  my $merchantId = $self->{'merchantId'};

  my $result = $dbs->fetchallOrDie('pnp_transaction',q/
    call release_transaction_lock(?,?,?)
  /,[$merchantId,$btid,$bcid],{});

  $self->{'released'} = 1;
}

sub getGatewayAccount {
  my $self = shift;
  my $gatewayAccount = $self->{'gatewayAccount'};
  my $ga = new PlugNPay::GatewayAccount("$gatewayAccount");
  return $ga;
}

sub getAccountFeatures {
  my $self = shift;
  my $ga = $self->getGatewayAccount();
  return $ga->getFeatures();
}

sub getDBTransactionData {
  my $self = shift;

  # do not retry loading the data more than once
  if ($self->{'loadTransactionDataAttempted'}) {
    return $self->{'transactionCurrentData'};
  }

  my $transactionId = $self->{'transactionId'};
  my $gatewayAccount = $self->{'gatewayAccount'};
  my $transactionVersion = $self->{'transactionVersion'};

  if (!$self->{'transactionCurrentData'}) {
    $self->{'loadTransactionDataAttempted'} = 1;
    # unpack the transaction id if it's not 22 characters
    if (length($transactionId) != 22) {
      my $tempTransactionId = PlugNPay::Util::UniqueID::fromBinaryToHex($transactionId);
      # if, after being unpacked, it is purely numeric and <= 23 characters,
      # set the transaction id to the legacy transaction id value
      if ($tempTransactionId =~ /^[0-9]+$/ && length($tempTransactionId) <= 23) {
        $transactionId = $tempTransactionId;
      }
    }

    # acquire lock on the transaction so we know the info loaded will not change
    $self->_acquireTransactionContextLock();

    my $transactionLoader = new PlugNPay::Transaction::Loader({ loadPaymentData => 1 });
    my $loaded = $transactionLoader->load({ gatewayAccount => "$gatewayAccount", transactionID => $transactionId, version => $transactionVersion });
    my $hexTransactionId = PlugNPay::Util::UniqueID::fromBinaryToHex($self->{'transactionId'});
    if (defined $loaded->{"$gatewayAccount"} && defined $loaded->{"$gatewayAccount"}{$hexTransactionId}) {
      $self->{'transactionCurrentData'} = $loaded->{$gatewayAccount}{$hexTransactionId};
    }
  }

  if ($self->{'transactionCurrentData'} && "$gatewayAccount" ne $self->{'transactionCurrentData'}->getGatewayAccount()) {
    return undef;
  }
  return $self->{'transactionCurrentData'};
}

sub getTransactionHistory {
  my $self = shift;
  if (!defined $self->{'transactionCurrentHistory'}) {
    my $transactionInfo = $self->getDBTransactionData();
    if ($transactionInfo) {
      my $transactionId = $transactionInfo->getPNPTransactionID();
      my $history = new PlugNPay::Transaction::Loader::History($transactionId)->getTransactionHistory();
      $self->{'transactionCurrentHistory'} = $history;
    }
  }

  return $self->{'transactionCurrentHistory'};
}

sub getTransactionVersion {
  my $self = shift;
  return $self->{'transactionVersion'};
}

sub destroy {
  my $self = shift;
  $self->{'transactionId'} = undef;
  $self->{'transaction'} = undef;
  $self->{'contextId'} = undef;
}

1;
