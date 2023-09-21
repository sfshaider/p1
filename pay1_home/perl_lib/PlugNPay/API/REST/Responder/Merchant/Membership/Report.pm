package PlugNPay::API::REST::Responder::Merchant::Membership::Report;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::Membership::Report;
use PlugNPay::Merchant::Customer::Link;
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
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _read {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();

  my $report = new PlugNPay::Membership::Report($merchant);
  my $membershipReport = $report->loadMembershipReport();

  $self->setResponseCode(200);
  return { 'status' => 'success', 'report' => $membershipReport };
}

1;
