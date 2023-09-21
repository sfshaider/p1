package PlugNPay::API::REST::Responder::Merchant::Membership::Plan;

use strict;
use PlugNPay::Membership::Plan;
use PlugNPay::Membership::Plan::JSON;
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
  } elsif ($action eq 'update') {
    return $self->_update();
  } elsif ($action eq 'create') {
    return $self->_create();
  } elsif ($action eq 'delete') {
    return $self->_delete();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _create {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $inputData = $self->getInputData();

  my $plan = new PlugNPay::Membership::Plan($merchant);
  my $savePlanStatus = $plan->savePaymentPlan($inputData);
  if (!$savePlanStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $savePlanStatus->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Payment plan saved successfully.' };
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $merchantPlanID = $self->getResourceData()->{'plan'};
  my $options = $self->getResourceOptions();
  
  my $count = 0;
  my $plans = [];

  my $plan = new PlugNPay::Membership::Plan($merchant);
  if ($merchantPlanID) {
    $plan->loadByMerchantPlanID($merchantPlanID);
    if (!$plan->getPlanID()) {
      $self->setResponseCode(404);
      return { 'status' => 'error', 'message' => 'Invalid plan id.' };
    }
 
    my $json = new PlugNPay::Membership::Plan::JSON();
    push (@{$plans}, $json->planToJSON($plan));
    $count++;
  } else {
    $plan->setLimitData({ 'limit' => $options->{'pageLength'}, 'offset' => $options->{'page'} * $options->{'pageLength'} });
    my $merchantPlans = $plan->loadPaymentPlans();
    if (@{$merchantPlans} > 0) {
      my $json = new PlugNPay::Membership::Plan::JSON();
      foreach my $merchantPlan (@{$merchantPlans}) {
        push (@{$plans}, $json->planToJSON($merchantPlan));
      }
    }

    $count = $plan->getPlanListSize();
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'plans' => $plans, 'count' => $count };
}

sub _update {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $merchantPlanID = $self->getResourceData()->{'plan'};
  my $inputData = $self->getInputData();

  if (!$merchantPlanID) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No plan id specified.' };
  }

  my $plan = new PlugNPay::Membership::Plan($merchant);
  $plan->loadByMerchantPlanID($merchantPlanID);
  if (!$plan->getPlanID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Invalid plan id.' };
  }

  my $updatePlanStatus = $plan->updatePaymentPlan($inputData);
  if (!$updatePlanStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $updatePlanStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Payment plan updated successfully.' };
}

sub _delete {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $merchantPlanID = $self->getResourceData()->{'plan'};

  if (!$merchantPlanID) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'No plan id specified.' };
  }

  my $plan = new PlugNPay::Membership::Plan($merchant);
  $plan->loadByMerchantPlanID($merchantPlanID);
  my $deletePlanStatus = $plan->deletePaymentPlan();
  if (!$deletePlanStatus) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $deletePlanStatus->getError() };
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'message' => 'Payment plan deleted successfully.' };
}

1;
