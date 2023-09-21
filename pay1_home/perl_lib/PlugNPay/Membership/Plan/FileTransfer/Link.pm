package PlugNPay::Membership::Plan::FileTransfer::Link;

use strict;
use PlugNPay::Merchant;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Merchant::Proxy;
use PlugNPay::Logging::DataLog;
use PlugNPay::Membership::Plan::FileTransfer;

######################################
# Module: Plan::FileTransfer::Link
# ------------------------------------
# Description:
#   This module is responsible for 
#   associating payment plans with 
#   file transfer settings.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $merchant = shift;
  if ($merchant) {
    if (ref($merchant) =~ /^PlugNPay::Merchant::Proxy/) {
      $self->{'merchantDB'} = $merchant;
    } else {
      $self->setMerchantID($merchant);
      $self->{'merchantDB'} = new PlugNPay::Merchant::Proxy($merchant);
    }
  }

  return $self;
}

sub setMerchantID {
  my $self = shift;
  my $merchant = shift;
  
  if ($merchant !~ /^[0-9]+$/) {
    $merchant = new PlugNPay::Merchant($merchant)->getMerchantID();
  }

  $self->{'merchantID'} = $merchant;
}

sub getMerchantID {
  my $self = shift;
  return $self->{'merchantID'};
}

sub setLinkID {
  my $self = shift;
  my $linkID = shift;
  $self->{'linkID'} = $linkID;
}

sub getLinkID {
  my $self = shift;
  return $self->{'linkID'};
}

sub setPlanID {
  my $self = shift;
  my $planID = shift;
  $self->{'planID'} = $planID;
}

sub getPlanID {
  my $self = shift;
  return $self->{'planID'};
}

sub setFileTransferID {
  my $self = shift;
  my $fileTransferID = shift;
  $self->{'fileTransferID'} = $fileTransferID;
}

sub getFileTransferID {
  my $self = shift;
  return $self->{'fileTransferID'};
}

###############################################
# Subroutine: loadPlanFileTransferSettings
# ---------------------------------------------
# Description:
#   Given a plan ID, loads all the associated
#   file transfer settings.
sub loadPlanFileTransferSettings {
  my $self = shift;
  my $planID = shift;
  
  my $fileTransferLinkSettings = [];

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               plan_id,
               file_transfer_id
        FROM recurring1_plan_file_transfer_link
        WHERE plan_id = ?/, [$planID], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        my $fileTransferLink = new PlugNPay::Membership::Plan::FileTransfer::Link();
        $fileTransferLink->_setFileTransferLinkDataFromRow($row);
        push (@{$fileTransferLinkSettings}, $fileTransferLink);
      }
    } 
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadPlanFileTransferSettings'
    });
  }

  return $fileTransferLinkSettings;
}

sub _setFileTransferLinkDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'linkID'} = $row->{'id'};
  $self->{'planID'} = $row->{'plan_id'};
  $self->{'fileTransferID'} = $row->{'file_transfer_id'};
}

sub savePlanFileTransferSettings {
  my $self = shift;
  my $planID = shift;
  my $data = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $merchantDB = $self->{'merchantDB'};
  if (!$merchantDB->isMaster()) {
    $status->setFalse();
    $status->setError('Access denied.');
    return $status;
  }

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');

    my $existingFileIDHash = {};
    my $existingFileSettings = $self->loadPlanFileTransferSettings($planID);
    foreach my $existingFileSetting (@{$existingFileSettings}) {
      $existingFileIDHash->{$existingFileSetting->getFileTransferID()} = 1;
    }

    my @newLinkParams = ();
    my @newLinkValues = ();

    if (ref ($data->{'linkIDs'}) ne 'ARRAY') {
      push (@errorMsg, 'Invalid format of link IDs.');
    } else {
      my $fileTransferIDs = $data->{'linkIDs'};
      foreach my $fileIdentifier (@{$fileTransferIDs}) {
        my $fileTransfer = new PlugNPay::Membership::Plan::FileTransfer($merchantDB);
        $fileTransfer->loadByFileTransferIdentifier($fileIdentifier);
        if (!$fileTransfer->getFileTransferID()) {
          push (@errorMsg, 'Invalid file transfer identifier.');
        } else {
          if (!exists $existingFileIDHash->{$fileTransfer->getFileTransferID()}) {
            push (@newLinkParams, '(?,?)');
            push (@newLinkValues, $planID, $fileTransfer->getFileTransferID());
          }
        }
      }

      if (@errorMsg == 0) {
        if (@newLinkValues > 0) {
          $dbs->executeOrDie('merchant_cust',
            q/INSERT INTO recurring1_plan_file_transfer_link
              ( plan_id,
                file_transfer_id )
              VALUES / . join(',', @newLinkParams), \@newLinkValues);
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      $self->_log({
        'error'    => $@,
        'function' => 'updatePlanFileTransferSettings',
        'planID'   => $planID
      });

      push (@errorMsg, 'Error while attempting to update file transfer settings.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

sub updatePlanFileTransferSettings {
  my $self = shift;
  my $planID = shift;
  my $updateData = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $merchantDB = $self->{'merchantDB'};
  if (!$merchantDB->isMaster()) {
    $status->setFalse();
    $status->setError('Access denied.');
    return $status;
  }

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');

    my $existingFileSettings = $self->loadPlanFileTransferSettings($planID);

    my $existingFileIDHash = {};
    foreach my $existingFileSetting (@{$existingFileSettings}) {
      $existingFileIDHash->{$existingFileSetting->getFileTransferID()} = 1;
    }

    my @newLinkParams = ();
    my @newLinkValues = ();

    if (ref ($updateData->{'linkIDs'}) ne 'ARRAY') {
      push (@errorMsg, 'Invalid format of link IDs.');
    } else {
      my $fileTransferIDs = $updateData->{'linkIDs'};
      foreach my $fileIdentifier (@{$fileTransferIDs}) {
        my $fileTransfer = new PlugNPay::Membership::Plan::FileTransfer($merchantDB);
        $fileTransfer->loadByFileTransferIdentifier($fileIdentifier);
        if (!$fileTransfer->getFileTransferID()) {
          push (@errorMsg, 'Invalid file transfer identifier.');
        } else {
          if (!exists $existingFileIDHash->{$fileTransfer->getFileTransferID()}) {
            push (@newLinkParams, '(?,?)');
            push (@newLinkValues, $planID, $fileTransfer->getFileTransferID());
          } else {
            delete $existingFileIDHash->{$fileTransfer->getFileTransferID()};
          }
        }
      }

      if (@errorMsg == 0) {
        if (@newLinkValues > 0) {
          $dbs->executeOrDie('merchant_cust',
            q/INSERT INTO recurring1_plan_file_transfer_link
              ( plan_id,
                file_transfer_id )
              VALUES / . join(',', @newLinkParams), \@newLinkValues);
        }

        if (keys %{$existingFileIDHash} > 0) {
          my @removeLinkParams = ();
          my @removeLinkValues = ();
          my $sql = q/DELETE FROM recurring1_plan_file_transfer_link
                      WHERE plan_id = ?
                      AND file_transfer_id IN (/;
          push (@removeLinkValues, $planID);
          foreach my $deleteFileID (keys %{$existingFileIDHash}) {
            push (@removeLinkValues, $deleteFileID);
            push (@removeLinkParams, '?');
          }

          $dbs->executeOrDie('merchant_cust', $sql . join(',', @removeLinkParams) . ')', \@removeLinkValues);
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      $self->_log({
        'error'    => $@,
        'function' => 'updatePlanFileTransferSettings',
        'planID'   => $planID
      });

      push (@errorMsg, 'Error while attempting to update file transfer settings.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

###################################################
# Subroutine: deleteFileTransferSettingsForPlan
# -------------------------------------------------
# Description:
#   Deletes file transfer settings for a plan. If
#   the transfer ID is not sent, it deletes all
#   associated transfer settings.
sub deleteFileTransferSettingsForPlan {
  my $self = shift;
  my $planID = shift;
  my $fileTransferID = shift || undef;

  my $status = new PlugNPay::Util::Status(1);
  my $errorMsg;

  my $merchantDB = $self->{'merchantDB'};
  if (!$merchantDB->isMaster()) {
    $status->setFalse();
    $status->setError('Access denied.');
    return $status;
  }

  my @values = ();

  my $sql = q/DELETE FROM recurring1_plan_file_transfer_link
              WHERE plan_id = ?/;
  push (@values, $planID);

  if ($fileTransferID) {
    $sql .= ' AND file_transfer_id = ?';
    push (@values, $fileTransferID);
  }

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust', $sql, \@values);
  };

  if ($@) {
    $self->_log({
      'function' => 'deleteFileTransferSettingsForPlan',
      'error'    => $@,
      'planID'   => $planID
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete plan file transfer settings.');
  }

  return $status;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_plan_filetransfer_link' });
  $logger->log($logInfo);
}

1;
