package PlugNPay::API::REST::Responder::Merchant::Membership::Plan::FileTransfer;

use strict;
use PlugNPay::Merchant::Host;
use PlugNPay::Merchant::HostConnection;
use PlugNPay::GatewayAccount::LinkedAccounts;
use PlugNPay::Membership::Plan::FileTransfer;
use PlugNPay::Merchant::HostConnection::Protocol;
use PlugNPay::Membership::Plan::FileTransfer::JSON;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  # check linked account
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  if ($merchant ne $self->getGatewayAccount()) {
    my $linked = new PlugNPay::GatewayAccount::LinkedAccounts($self->getGatewayAccount())->isLinkedTo($merchant);
    if (!$linked) {
      $self->setResponseCode(403);
      return { 'error' => 'Access Denied' };
    }
  }

  if ($action eq 'read') {
    return $self->_read();
  } elsif ($action eq 'delete') {
    return $self->_delete();
  } elsif ($action eq 'create') {
    return $self->_create();
  } elsif ($action eq 'update') {
    return $self->_update();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _create {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $inputData = $self->getInputData();

  my $fileTransfer = new PlugNPay::Membership::Plan::FileTransfer($merchant);
  my $saveFileTransferStatus = $fileTransfer->saveFileTransferSettings($inputData);
  if (!$saveFileTransferStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $saveFileTransferStatus->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'File transfer settings saved succcessfully.' };
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $fileTransferIdentifier = $self->getResourceData()->{'filetransfer'};
  my $options = $self->getResourceOptions();

  my $count = 0;
  my $fileTransferData = [];

  my $fileTransfer = new PlugNPay::Membership::Plan::FileTransfer($merchant);
  if ($fileTransferIdentifier) {
    $fileTransfer->loadByFileTransferIdentifier($fileTransferIdentifier);
    if (!$fileTransfer->getFileTransferID()) {
      $self->setResponseCode(404);
      return { 'status' => 'error', 'message' => 'File transfer identifier not found.' };
    }

    my $json = new PlugNPay::Membership::Plan::FileTransfer::JSON();
    push (@{$fileTransferData}, $json->fileTransferToJSON($fileTransfer));
    $count++;
  } else {
    $fileTransfer->setLimitData({ 'limit' => $options->{'pageLength'}, 'offset' => $options->{'page'} * $options->{'pageLength'} });
    my $fileTransferSettings = $fileTransfer->loadMerchantFileTransferSettings();

    if (@{$fileTransferSettings} > 0) {
      my $json = new PlugNPay::Membership::Plan::FileTransfer::JSON();
      foreach my $settings (@{$fileTransferSettings}) {
        push (@{$fileTransferData}, $json->fileTransferToJSON($settings));
      }
    }

    $count = $fileTransfer->getFileTransferListSize();
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'filetransfers' => $fileTransferData, 'count' => $count };
}

sub _update {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $fileTransferIdentifier = $self->getResourceData()->{'filetransfer'};
  my $inputData = $self->getInputData();

  if (!$fileTransferIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No file transfer identifier specified.' };
  }

  my $fileTransfer = new PlugNPay::Membership::Plan::FileTransfer($merchant);
  $fileTransfer->loadByFileTransferIdentifier($fileTransferIdentifier);
  if (!$fileTransfer->getFileTransferID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Invalid file transfer identifier.' };
  }

  my $updateFileTransferStatus = $fileTransfer->updateFileTransferSettings($inputData);
  if (!$updateFileTransferStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updateFileTransferStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Updated file transfer settings successfully.' };
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $fileTransferIdentifier = $self->getResourceData()->{'filetransfer'};

  my $fileTransfer = new PlugNPay::Membership::Plan::FileTransfer($merchant);
  $fileTransfer->loadByFileTransferIdentifier($fileTransferIdentifier);
  my $deleteFileTransferStatus = $fileTransfer->deleteFileTransferSettings();
  if (!$deleteFileTransferStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deleteFileTransferStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Deleted file transfer settings successfully.' };
}

1;
