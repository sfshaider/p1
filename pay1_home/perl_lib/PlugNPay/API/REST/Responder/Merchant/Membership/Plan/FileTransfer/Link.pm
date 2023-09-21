package PlugNPay::API::REST::Responder::Merchant::Membership::Plan::FileTransfer::Link;

use strict;
use PlugNPay::Membership::Plan;
use PlugNPay::Membership::Plan::FileTransfer;
use PlugNPay::Membership::Plan::FileTransfer::Link;
use PlugNPay::Membership::Plan::FileTransfer::JSON;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  if ($action eq 'read') {
    return $self->_read();
  } elsif ($action eq 'create' || $action eq 'update') {
    return $self->_update();
  } elsif ($action eq 'delete') {
    return $self->_delete();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'};
  my $merchantPlanID = $self->getResourceData()->{'plan'};

  if (!$merchantPlanID) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No plan ID specified.' };
  }

  my $plan = new PlugNPay::Membership::Plan($merchant);
  $plan->loadByMerchantPlanID($merchantPlanID);
  if (!$plan->getPlanID()) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Invalid plan ID.' };
  }

  my $count = 0;
  my $linkedSettings = [];

  my $linker = new PlugNPay::Membership::Plan::FileTransfer::Link();
  my $fileTransferSettings = $linker->loadPlanFileTransferSettings($plan->getPlanID());
  if (@{$fileTransferSettings} > 0) {
    my $json = new PlugNPay::Membership::Plan::FileTransfer::JSON();
    foreach my $settings (@{$fileTransferSettings}) {
      my $fileTransfer = new PlugNPay::Membership::Plan::FileTransfer($merchant);
      $fileTransfer->loadFileTransferSettings($settings->getFileTransferID());
      push (@{$linkedSettings}, $json->fileTransferToJSON($fileTransfer));
      $count++;
    }
  }

  $self->setResponseCode(200);
  return { 'linkSettings' => $linkedSettings, 'count' => $count, 'status' => 'success' };
}

sub _update {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'};
  my $merchantPlanID = $self->getResourceData()->{'plan'};
  my $inputData = $self->getInputData();

  if (!$merchantPlanID) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No plan id specified.' };
  }

  my $plan = new PlugNPay::Membership::Plan($merchant);
  $plan->loadByMerchantPlanID($merchantPlanID);
  if (!$plan->getPlanID()) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Invalid plan id.' };
  }

  my $linker = new PlugNPay::Membership::Plan::FileTransfer::Link($merchant);
  my $updateFileTransferStatus = $linker->updatePlanFileTransferSettings($plan->getPlanID(), $inputData);
  if (!$updateFileTransferStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updateFileTransferStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully updated plan file transfer settings.' };
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'};
  my $merchantPlanID = $self->getResourceData()->{'plan'};
  my $fileTransferIdentifier = $self->getResourceData()->{'filetransfer'};

  if (!$merchantPlanID) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No plan id specified.' };
  }

  my $plan = new PlugNPay::Membership::Plan($merchant);
  $plan->loadByMerchantPlanID($merchantPlanID);
  if (!$plan->getPlanID()) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Invalid plan id.' };
  }
 
  my $deleteFileTransferStatus;
  my $fileTransfer = new PlugNPay::Membership::Plan::FileTransfer($merchant);
  if ($fileTransferIdentifier) {
    $deleteFileTransferStatus = $fileTransfer->deleteFileTransferSettingsForPlan($plan->getPlanID(), $fileTransferIdentifier);
  } else {
    $deleteFileTransferStatus = $fileTransfer->deleteFileTransferSettingsForPlan($plan->getPlanID());
  }

  if (!$deleteFileTransferStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deleteFileTransferStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Successfully deleted link settings for plan.' };
}

1;
