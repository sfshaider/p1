package PlugNPay::API::REST::Responder::Merchant::Membership::Group;

use strict;
use PlugNPay::Membership::Group;
use PlugNPay::Membership::Group::JSON;
use PlugNPay::GatewayAccount::LinkedAccounts;

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
  } elsif ($action eq 'create') {
    return $self->_create();
  } elsif ($action eq 'delete') {
    return $self->_delete();
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
  my $group = new PlugNPay::Membership::Group($merchant);

  my $groupName = lc $inputData->{'groupName'};
  $groupName =~ s/[^a-z0-9_]//g;

  my $saveGroupStatus = $group->saveMerchantGroup($groupName);
  if (!$saveGroupStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $saveGroupStatus->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Group successfully saved.' };
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $groupIdentifier = $self->getResourceData()->{'group'};
  my $options = $self->getResourceOptions();

  my $count = 0;
  my $groups = [];

  my $group = new PlugNPay::Membership::Group($merchant);

  if ($groupIdentifier) {
    $group->loadGroupByName($groupIdentifier);
    if (!$group->getGroupID()) {
      $self->setResponseCode(404);
      return { 'status' => 'error', 'message' => 'Group name not found.' };
    }

    my $json = new PlugNPay::Membership::Group::JSON();
    push (@{$groups}, $json->groupToJSON($group));
    $count++;
  } else {
    $group->setLimitData({ 'limit' => $options->{'pageLength'}, 'offset' => $options->{'page'} * $options->{'pageLength'} });
    my $merchantGroups = $group->loadGroupsForMerchant();
    if (@{$merchantGroups} > 0) {
      my $json = new PlugNPay::Membership::Group::JSON();
      foreach my $merchantGroup (@{$merchantGroups}) {
        push (@{$groups}, $json->groupToJSON($merchantGroup));
      }
    }

    $count = $group->getGroupListSize();
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'groups' => $groups, 'count' => $count };
}

sub _update {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $groupIdentifier = $self->getResourceData()->{'group'};
  my $inputData = $self->getInputData();

  my $group = new PlugNPay::Membership::Group($merchant);
  $group->loadGroupByName($groupIdentifier);
  if (!$group->getGroupID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Group name not found.' };
  }

  my $groupName = lc $inputData->{'groupName'};
  $groupName =~ s/[^a-z0-9_]//g;

  my $updateGroupStatus = $group->updateMerchantGroup($groupName);
  if (!$updateGroupStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updateGroupStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Group successfully updated.' };
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $groupIdentifier = $self->getResourceData()->{'group'};

  if (!$groupIdentifier) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No group specified.' };
  }

  my $group = new PlugNPay::Membership::Group($merchant);
  $group->loadGroupByName($groupIdentifier);
  my $deleteGroupStatus = $group->deleteMerchantGroup();
  if (!$deleteGroupStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deleteGroupStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Group successfully deleted.' };
}

1;
